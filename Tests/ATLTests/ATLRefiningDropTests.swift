//
//  ATLRefiningDropTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 5/11/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ATL

/// A small organisation model with nested containment and opposite references.
///
/// A company contains departments and people. A department contains teams and has a
/// head, who leads it through the opposite single-valued reference `leads`. A team has
/// members, who list their teams through the opposite many-valued reference `teams`.
/// People also refer to a manager and to mentors without opposites.
@MainActor
struct OrganisationFixture {
    let package: EPackage
    let sourceResource = Resource(uri: "test://organisation-in")
    let targetResource = Resource(uri: "test://organisation-out")

    var acme: DynamicEObject!
    var sales: DynamicEObject!
    var labs: DynamicEObject!
    var red: DynamicEObject!
    var blue: DynamicEObject!
    var ann: DynamicEObject!
    var bob: DynamicEObject!
    var cat: DynamicEObject!

    /// The header of a refining module over the organisation metamodel.
    static let header = "module Reorganise;\ncreate OUT : Org refining IN : Org;\n"

    init() {
        let string = EDataType(name: "EString")
        let membersID = EUUID()
        let teamsID = EUUID()
        let headID = EUUID()
        let leadsID = EUUID()

        var person = EClass(name: "Person")
        person.eStructuralFeatures.append(EAttribute(name: "name", eType: string))
        person.eStructuralFeatures.append(EReference(name: "manager", eType: EClass(name: "Person")))
        person.eStructuralFeatures.append(
            EReference(name: "mentors", eType: EClass(name: "Person"), upperBound: -1))
        person.eStructuralFeatures.append(
            EReference(id: teamsID, name: "teams", eType: EClass(name: "Team"), upperBound: -1, opposite: membersID))
        person.eStructuralFeatures.append(
            EReference(id: leadsID, name: "leads", eType: EClass(name: "Department"), opposite: headID))

        var team = EClass(name: "Team")
        team.eStructuralFeatures.append(EAttribute(name: "name", eType: string))
        team.eStructuralFeatures.append(
            EReference(id: membersID, name: "members", eType: person, upperBound: -1, opposite: teamsID))

        var department = EClass(name: "Department")
        department.eStructuralFeatures.append(EAttribute(name: "name", eType: string))
        department.eStructuralFeatures.append(
            EReference(name: "teams", eType: team, upperBound: -1, containment: true))
        department.eStructuralFeatures.append(
            EReference(id: headID, name: "head", eType: person, opposite: leadsID))

        var company = EClass(name: "Company")
        company.eStructuralFeatures.append(EAttribute(name: "name", eType: string))
        company.eStructuralFeatures.append(
            EReference(name: "departments", eType: department, upperBound: -1, containment: true))
        company.eStructuralFeatures.append(
            EReference(name: "people", eType: person, upperBound: -1, containment: true))

        var package = EPackage(name: "Org", nsURI: "http://example.org/organisation", nsPrefix: "org")
        package.eClassifiers.append(contentsOf: [company, department, team, person])
        self.package = package
    }

    /// Creates the source model.
    ///
    /// Acme contains the departments Sales (head Ann, team Red with Ann and Bob) and Labs
    /// (head Cat, team Blue with Cat), and the people Ann, Bob and Cat. Bob's manager is
    /// Ann, and Cat's mentors are Ann and Bob.
    mutating func populate() async {
        func named(_ className: String, _ name: String) -> DynamicEObject {
            var element = DynamicEObject(eClass: (package.getClassifier(className) as? EClass)!)
            element.eSet("name", value: name)
            return element
        }
        acme = named("Company", "Acme")
        sales = named("Department", "Sales")
        labs = named("Department", "Labs")
        red = named("Team", "Red")
        blue = named("Team", "Blue")
        ann = named("Person", "Ann")
        bob = named("Person", "Bob")
        cat = named("Person", "Cat")
        for element in [sales!, labs!, red!, blue!, ann!, bob!, cat!] {
            await sourceResource.register(element)
        }
        await sourceResource.add(acme)
        await set(acme, "departments", [sales.id, labs.id])
        await set(acme, "people", [ann.id, bob.id, cat.id])
        await set(sales, "teams", [red.id])
        await set(labs, "teams", [blue.id])
        await set(sales, "head", ann.id)
        await set(labs, "head", cat.id)
        await set(red, "members", [ann.id, bob.id])
        await set(blue, "members", [cat.id])
        await set(bob, "manager", ann.id)
        await set(cat, "mentors", [ann.id, bob.id])
    }

    func set(_ element: DynamicEObject, _ feature: String, _ value: any EcoreValue) async {
        await sourceResource.eSet(objectId: element.id, feature: feature, value: value)
    }

    /// Parses rules into a module over the organisation metamodel.
    func module(_ declarations: String, header: String = Self.header) async throws -> ATLModule {
        let parsed = try await ATLParser().parseContent(header + declarations)
        return parsed.withMetamodels(source: ["IN": package], target: ["OUT": package])
    }

    /// Parses and runs rules over the source model.
    func run(_ declarations: String, header: String = Self.header) async throws {
        let machine = ATLVirtualMachine(module: try await module(declarations, header: header))
        try await machine.execute(sources: ["IN": sourceResource], targets: ["OUT": targetResource])
    }

    /// The target elements of a class.
    func targets(_ className: String) async -> [DynamicEObject] {
        await targetResource.getAllObjects().compactMap { $0 as? DynamicEObject }
            .filter { $0.eClass.name == className }
    }

    /// The target element of a class with the given name.
    func target(_ className: String, named name: String) async -> DynamicEObject? {
        await targets(className).first { $0.eGet("name") as? String == name }
    }

    /// The names of the target elements that a reference of a target element holds.
    func names(_ feature: String, of className: String, named name: String) async -> [String] {
        guard let element = await target(className, named: name) else { return [] }
        let ids = (element.eGet(feature) as? [EUUID]) ?? (element.eGet(feature) as? EUUID).map { [$0] } ?? []
        var names: [String] = []
        for id in ids {
            if let referenced = await targetResource.resolve(id) as? DynamicEObject,
                let referencedName = referenced.eGet("name") as? String
            {
                names.append(referencedName)
            }
        }
        return names
    }

    /// Every identifier that a target element refers to through its references.
    func referencedIDs() async -> Set<EUUID> {
        var ids = Set<EUUID>()
        for element in await targetResource.getAllObjects().compactMap({ $0 as? DynamicEObject }) {
            for name in element.getFeatureNames() {
                if let id = element.eGet(name) as? EUUID { ids.insert(id) }
                if let list = element.eGet(name) as? [EUUID] { ids.formUnion(list) }
            }
        }
        return ids
    }
}

@Suite("ATL Refining Mode Drop")
@MainActor
struct ATLRefiningDropTests {

    @Test("Dropping a leaf element removes it and every reference to it")
    func dropLeaf() async throws {
        var fixture = OrganisationFixture()
        await fixture.populate()
        try await fixture.run("rule DropBob { from p : Org!Person (p.name = 'Bob') to drop }")

        #expect(await fixture.target("Person", named: "Bob") == nil)
        #expect(await fixture.names("people", of: "Company", named: "Acme") == ["Ann", "Cat"])
        #expect(await fixture.names("members", of: "Team", named: "Red") == ["Ann"])
        #expect(await fixture.names("mentors", of: "Person", named: "Cat") == ["Ann"])
        #expect(await fixture.names("manager", of: "Person", named: "Ann").isEmpty)
        #expect(await fixture.targets("Department").count == 2)
        #expect(await fixture.source(fixture.bob) != nil)
    }

    @Test("Dropping an element unsets single-valued references and opposites to it")
    func dropReferencedElement() async throws {
        var fixture = OrganisationFixture()
        await fixture.populate()
        try await fixture.run("rule DropAnn { from p : Org!Person (p.name = 'Ann') to drop }")

        #expect(await fixture.target("Person", named: "Ann") == nil)
        let sales = try #require(await fixture.target("Department", named: "Sales"))
        #expect(sales.eGet("head") == nil)
        let bob = try #require(await fixture.target("Person", named: "Bob"))
        #expect(bob.eGet("manager") == nil)
        #expect(await fixture.names("members", of: "Team", named: "Red") == ["Bob"])
        #expect(await fixture.names("mentors", of: "Person", named: "Cat") == ["Bob"])
        #expect(await fixture.names("head", of: "Department", named: "Labs") == ["Cat"])
    }

    @Test("Dropping a container removes what it contains and the opposites of its contents")
    func dropContainer() async throws {
        var fixture = OrganisationFixture()
        await fixture.populate()
        try await fixture.run("rule DropSales { from d : Org!Department (d.name = 'Sales') to drop }")

        #expect(await fixture.target("Department", named: "Sales") == nil)
        #expect(await fixture.target("Team", named: "Red") == nil)
        #expect(await fixture.names("departments", of: "Company", named: "Acme") == ["Labs"])
        #expect(await fixture.names("teams", of: "Person", named: "Ann").isEmpty)
        #expect(await fixture.names("teams", of: "Person", named: "Bob").isEmpty)
        #expect(await fixture.names("leads", of: "Person", named: "Ann").isEmpty)
        #expect(await fixture.names("teams", of: "Person", named: "Cat") == ["Blue"])
        #expect(await fixture.targets("Person").count == 3)
        let remaining = Set(await fixture.targetResource.getAllObjects().map(\.id))
        #expect((await fixture.referencedIDs()).isSubset(of: remaining))
    }

    @Test("An element moved out of a dropped container survives with the other changes")
    func dropWithOtherChanges() async throws {
        var fixture = OrganisationFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule DropSales { from d : Org!Department (d.name = 'Sales') to drop }
            rule GrowLabs {
                from d : Org!Department (d.name = 'Labs')
                to t : Org!Department (
                    name <- 'Research',
                    teams <- Org!Team.allInstances()->sortedBy(x | x.name)
                )
            }
            rule RenameBob { from p : Org!Person (p.name = 'Bob') to t : Org!Person (name <- 'Robert') }
            """)

        #expect(await fixture.target("Department", named: "Sales") == nil)
        #expect(await fixture.names("teams", of: "Department", named: "Research") == ["Blue", "Red"])
        #expect(await fixture.names("members", of: "Team", named: "Red") == ["Ann", "Robert"])
        #expect(await fixture.names("departments", of: "Company", named: "Acme") == ["Research"])
        #expect(await fixture.names("mentors", of: "Person", named: "Cat") == ["Ann", "Robert"])
    }

    @Test("Target patterns after drop create new elements that bound references resolve to")
    func dropAndCreate() async throws {
        var fixture = OrganisationFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule ReplaceBob {
                from p : Org!Person (p.name = 'Bob')
                to drop
                   n : Org!Person (name <- p.name + ' Junior')
            }
            rule Red { from s : Org!Team (s.name = 'Red') to t : Org!Team (members <- s.members) }
            """)

        #expect(await fixture.target("Person", named: "Bob") == nil)
        let junior = try #require(await fixture.target("Person", named: "Bob Junior"))
        #expect(await fixture.names("members", of: "Team", named: "Red") == ["Ann", "Bob Junior"])
        #expect(await fixture.targetResource.getRootObjects().contains { $0.id == junior.id })
        #expect(await fixture.names("people", of: "Company", named: "Acme") == ["Ann", "Cat"])
    }

    @Test("Several rules may drop elements, and each element is deleted once")
    func dropSeveral() async throws {
        var fixture = OrganisationFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule DropPeople { from p : Org!Person (p.name <> 'Cat') to drop }
            rule DropRed { from t : Org!Team (t.name = 'Red') to drop }
            """)

        #expect(await fixture.targets("Person").map { $0.eGet("name") as? String } == ["Cat"])
        #expect(await fixture.target("Team", named: "Red") == nil)
        #expect(await fixture.names("teams", of: "Department", named: "Sales").isEmpty)
        #expect(await fixture.names("mentors", of: "Person", named: "Cat").isEmpty)
    }

    @Test("Dropping outside refining mode is an error that leaves the target untouched")
    func dropOutsideRefiningMode() async throws {
        var fixture = OrganisationFixture()
        await fixture.populate()
        await #expect {
            try await fixture.run(
                "rule DropBob { from p : Org!Person (p.name = 'Bob') to drop }",
                header: "module Copy;\ncreate OUT : Org from IN : Org;\n")
        } throws: { error in
            guard case ATLExecutionError.invalidOperation(let message) = error else { return false }
            return message.contains("DropBob") && message.contains("drop") && message.contains("refining")
        }
        #expect(await fixture.targetResource.getAllObjects().isEmpty)
    }

    @Test("A module made refining with refining() may drop")
    func dropAfterRefiningCall() async throws {
        var fixture = OrganisationFixture()
        await fixture.populate()
        let module = try await fixture.module(
            "rule DropBob { from p : Org!Person (p.name = 'Bob') to drop }",
            header: "module Copy;\ncreate OUT : Org from IN : Org;\n")
        try await ATLVirtualMachine(module: module.refining())
            .execute(sources: ["IN": fixture.sourceResource], targets: ["OUT": fixture.targetResource])

        #expect(await fixture.target("Person", named: "Bob") == nil)
        #expect(await fixture.target("Person", named: "Ann") != nil)
    }

    @Test("A rule that extends a dropping rule is an error")
    func extendingDroppingRule() async throws {
        var fixture = OrganisationFixture()
        await fixture.populate()
        await #expect {
            try await fixture.run(
                """
                rule DropPerson { from p : Org!Person to drop }
                rule KeepAnn extends DropPerson { from p : Org!Person (p.name = 'Ann') to t : Org!Person }
                """)
        } throws: { error in
            guard case ATLExecutionError.invalidOperation(let message) = error else { return false }
            return message.contains("KeepAnn") && message.contains("DropPerson")
        }
    }

    @Test("The parsed rule records the drop and the target patterns after it")
    func parsedDrop() async throws {
        let fixture = OrganisationFixture()
        let module = try await fixture.module(
            """
            rule DropOnly { from p : Org!Person to drop }
            rule DropAndCreate { from p : Org!Person to drop n : Org!Person (name <- p.name), m : Org!Team }
            rule Keep { from p : Org!Person to drop : Org!Person (name <- p.name) }
            """)
        let rules = Dictionary(uniqueKeysWithValues: module.matchedRules.map { ($0.name, $0) })
        #expect(rules["DropOnly"]?.dropsSourceElement == true)
        #expect(rules["DropOnly"]?.targetPatterns.isEmpty == true)
        #expect(rules["DropAndCreate"]?.dropsSourceElement == true)
        #expect(rules["DropAndCreate"]?.targetPatterns.map(\.variableName) == ["n", "m"])
        #expect(rules["Keep"]?.dropsSourceElement == false)
        #expect(rules["Keep"]?.targetPatterns.map(\.variableName) == ["drop"])
    }

    @Test("drop after a target pattern is a syntax error that names its position")
    func dropAfterTargetPattern() async {
        await #expect {
            try await ATLParser().parseContent(
                OrganisationFixture.header
                    + "rule R { from p : Org!Person to t : Org!Person (name <- 'x'), drop }\n")
        } throws: { error in
            guard case ATLParseError.invalidSyntax(let message) = error else { return false }
            return message.contains("'drop' must directly follow 'to'") && message.contains("line 3")
        }
    }
}

extension OrganisationFixture {
    /// The current state of a source element.
    func source(_ element: DynamicEObject) async -> DynamicEObject? {
        await sourceResource.resolve(element.id) as? DynamicEObject
    }
}
