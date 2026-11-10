//
//  ATLScalingTests.swift
//  ATLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ATL

/// Generated Families and Persons models whose size the scaling tests choose.
///
/// The source metamodel has a `Registry` that contains `Family` elements, each of which
/// contains `Member` elements. The target metamodel has a `Register` that contains
/// `Male` and `Female` persons. The transformation uses helpers, the container of an
/// element, `allInstances()` and guards, as batch transformations of real models do.
@MainActor
struct ScalingFixture {
    /// The source metamodel.
    let families: EPackage

    /// The target metamodel.
    let persons: EPackage

    /// The number of members of each generated family.
    static let membersPerFamily = 9

    /// The transformation from families to a register of persons.
    static let module = """
        module Families2Register;
        create OUT : Persons from IN : Families;

        helper context Families!Member def : familyName : String =
            if self.refImmediateComposite().oclIsUndefined() then ''
            else self.refImmediateComposite().lastName endif;

        helper context Families!Member def : displayName : String =
            self.firstName + ' ' + self.familyName;

        rule Registry2Register {
            from r : Families!Registry
            to reg : Persons!Register ( persons <- Families!Member.allInstances() )
        }

        rule Member2Male {
            from s : Families!Member (not s.isFemale)
            to t : Persons!Male ( fullName <- s.displayName, mentor <- s.mentor )
        }

        rule Member2Female {
            from s : Families!Member (s.isFemale)
            to t : Persons!Female ( fullName <- s.displayName, mentor <- s.mentor )
        }
        """

    /// Creates the metamodels.
    init() {
        let string = EDataType(name: "EString", instanceClassName: "String")
        let boolean = EDataType(name: "EBoolean", instanceClassName: "Bool")
        var member = EClass(name: "Member")
        member.eStructuralFeatures = [
            EAttribute(name: "firstName", eType: string), EAttribute(name: "isFemale", eType: boolean),
        ]
        member.eStructuralFeatures.append(EReference(name: "mentor", eType: member))
        let family = EClass(
            name: "Family",
            eStructuralFeatures: [
                EAttribute(name: "lastName", eType: string),
                EReference(name: "members", eType: member, upperBound: -1, containment: true),
            ])
        let registry = EClass(
            name: "Registry",
            eStructuralFeatures: [
                EReference(name: "families", eType: family, upperBound: -1, containment: true)
            ])
        families = EPackage(
            name: "Families", nsURI: "http://example.org/families", nsPrefix: "families",
            eClassifiers: [registry, family, member])
        var person = EClass(name: "Person", isAbstract: true)
        person.eStructuralFeatures = [EAttribute(name: "fullName", eType: string)]
        person.eStructuralFeatures.append(EReference(name: "mentor", eType: person))
        let register = EClass(
            name: "Register",
            eStructuralFeatures: [
                EReference(name: "persons", eType: person, upperBound: -1, containment: true)
            ])
        persons = EPackage(
            name: "Persons", nsURI: "http://example.org/persons", nsPrefix: "persons",
            eClassifiers: [
                register, person, EClass(name: "Male", eSuperTypes: [person]),
                EClass(name: "Female", eSuperTypes: [person]),
            ])
    }

    /// The class of the source metamodel with a name.
    private func sourceClass(_ name: String) -> EClass {
        families.getClassifier(name) as! EClass
    }

    /// Builds a source model of a registry with the given number of families.
    ///
    /// Members alternate between female and male, and every third member is mentored
    /// by the member created before it.
    ///
    /// - Parameter familyCount: The number of families.
    /// - Returns: The model.
    func model(families familyCount: Int) async -> Resource {
        let resource = Resource(uri: "memory:/families.xmi")
        var root = DynamicEObject(eClass: sourceClass("Registry"))
        var objects: [DynamicEObject] = []
        var familyIDs: [EUUID] = []
        var previous: EUUID?
        for index in 0..<familyCount {
            var family = DynamicEObject(eClass: sourceClass("Family"))
            family.eSet("lastName", value: "Family\(index)")
            var memberIDs: [EUUID] = []
            for position in 0..<Self.membersPerFamily {
                var member = DynamicEObject(eClass: sourceClass("Member"))
                member.eSet("firstName", value: "M\(index)x\(position)")
                member.eSet("isFemale", value: position % 2 == 0)
                if let previous, position % 3 == 0 { member.eSet("mentor", value: previous) }
                previous = member.id
                memberIDs.append(member.id)
                objects.append(member)
            }
            family.eSet("members", value: memberIDs)
            familyIDs.append(family.id)
            objects.append(family)
        }
        root.eSet("families", value: familyIDs)
        await resource.add(contentsOf: [root] + objects)
        return resource
    }

    /// Creates a virtual machine for the transformation.
    func machine() async throws -> ATLVirtualMachine {
        let module = try await ATLParser().parseContent(Self.module)
            .withMetamodels(source: ["IN": families], target: ["OUT": persons])
        return ATLVirtualMachine(module: module)
    }
}

/// Checks that batch transformations do work in proportion to the size of their models.
///
/// The tests count the internal operations whose number grew with the square of the
/// model size, rather than measuring time, so that they are cheap and deterministic.
@Suite("ATL Scaling Tests")
@MainActor
struct ATLScalingTests {

    @Test("Deciding which rule applies compares each match only with matches of the same elements")
    func hidingComparisonsAreLinear() async throws {
        let fixture = ScalingFixture()
        for familyCount in [10, 40] {
            let source = await fixture.model(families: familyCount)
            let machine = try await fixture.machine()
            try await machine.execute(sources: ["IN": source], targets: ["OUT": Resource()])
            let matches = 1 + familyCount * ScalingFixture.membersPerFamily
            #expect(machine.hidingComparisons <= 2 * matches)
        }
    }

    @Test("The generated register lists every member once, in source order")
    func registerContents() async throws {
        let fixture = ScalingFixture()
        let source = await fixture.model(families: 3)
        let target = Resource(uri: "memory:/register.xmi")
        try await fixture.machine().execute(sources: ["IN": source], targets: ["OUT": target])
        let roots = await target.getRootObjects()
        #expect(roots.count == 1)
        let register = try #require(roots.first as? DynamicEObject)
        let persons = try #require(register.eGet("persons") as? [EUUID])
        #expect(persons.count == 3 * ScalingFixture.membersPerFamily)
        var names: [String] = []
        for id in persons {
            let person = try #require(await target.resolve(id) as? DynamicEObject)
            names.append(try #require(person.eGet("fullName") as? String))
        }
        #expect(names.first == "M0x0 Family0")
        #expect(names.last == "M2x8 Family2")
        #expect(Set(names).count == names.count)
    }

    @Test("A sub-rule still hides the rule it extends when many elements match both")
    func hidingStillApplies() async throws {
        let fixture = ScalingFixture()
        let source = await fixture.model(families: 4)
        let module = try await ATLParser().parseContent(
            """
            module Hiding;
            create OUT : Persons from IN : Families;
            rule Member2Male {
                from s : Families!Member
                to t : Persons!Male ( fullName <- s.firstName )
            }
            rule Member2Female extends Member2Male {
                from s : Families!Member (s.isFemale)
                to t : Persons!Female
            }
            """
        ).withMetamodels(source: ["IN": fixture.families], target: ["OUT": fixture.persons])
        let target = Resource(uri: "memory:/register.xmi")
        let machine = ATLVirtualMachine(module: module)
        try await machine.execute(sources: ["IN": source], targets: ["OUT": target])
        let created = await target.getAllObjects()
        let females = created.filter { $0.eClass.name == "Female" }.count
        let males = created.filter { $0.eClass.name == "Male" }.count
        #expect(females + males == 4 * ScalingFixture.membersPerFamily)
        #expect(females == 4 * 5)
        #expect(machine.hidingComparisons <= 2 * 2 * 4 * ScalingFixture.membersPerFamily)
    }
}
