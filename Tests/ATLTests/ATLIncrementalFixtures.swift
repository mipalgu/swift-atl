//
//  ATLIncrementalFixtures.swift
//  ATLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import OrderedCollections
import Testing

@testable import ATL

/// A deterministic pseudo-random generator (SplitMix64), so that edit sequences repeat.
struct SplitMixGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}

/// Builds metamodel classes concisely.
enum MetamodelKit {
    static let string = EDataType(name: "EString", instanceClassName: "String")
    static let int = EDataType(name: "EInt", instanceClassName: "Int")
    static let bool = EDataType(name: "EBoolean", instanceClassName: "Bool")

    static func attribute(_ name: String, _ type: EDataType) -> EAttribute {
        EAttribute(name: name, eType: type)
    }
}

// MARK: - Families to a register of persons

/// A families metamodel and a persons metamodel, both written for these tests.
struct FamilyMetamodels {
    let families: EPackage
    let persons: EPackage
    let registry: EClass
    let family: EClass
    let member: EClass

    init() {
        let k = MetamodelKit.self
        var member = EClass(name: "Member")
        member.eStructuralFeatures = [
            k.attribute("firstName", k.string), k.attribute("age", k.int), k.attribute("isFemale", k.bool),
        ]
        member.eStructuralFeatures.append(EReference(name: "mentor", eType: member))
        let family = EClass(
            name: "Family",
            eStructuralFeatures: [
                k.attribute("lastName", k.string),
                EReference(name: "members", eType: member, upperBound: -1, containment: true),
            ])
        let registry = EClass(
            name: "Registry",
            eStructuralFeatures: [EReference(name: "families", eType: family, upperBound: -1, containment: true)])
        families = EPackage(
            name: "Families", nsURI: "http://example.org/families", nsPrefix: "families",
            eClassifiers: [registry, family, member])

        var person = EClass(name: "Person", isAbstract: true)
        person.eStructuralFeatures = [k.attribute("fullName", k.string), k.attribute("age", k.int)]
        person.eStructuralFeatures.append(EReference(name: "mentor", eType: person))
        let male = EClass(name: "Male", eSuperTypes: [person])
        let female = EClass(name: "Female", eSuperTypes: [person])
        let register = EClass(
            name: "Register",
            eStructuralFeatures: [EReference(name: "persons", eType: person, upperBound: -1, containment: true)])
        persons = EPackage(
            name: "Persons", nsURI: "http://example.org/persons", nsPrefix: "persons",
            eClassifiers: [register, person, male, female])
        self.registry = registry
        self.family = family
        self.member = member
    }

    /// A transformation of families into a register of persons, written for these tests.
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
            to reg : Persons!Register (
                persons <- Families!Member.allInstances()->select(m | m.age >= 0)
            )
        }

        rule Member2Male {
            from s : Families!Member (not s.isFemale)
            to t : Persons!Male (
                fullName <- s.displayName,
                age <- s.age,
                mentor <- s.mentor
            )
        }

        rule Member2Female {
            from s : Families!Member (s.isFemale)
            to t : Persons!Female (
                fullName <- s.displayName,
                age <- s.age,
                mentor <- s.mentor
            )
        }
        """
}

/// A source model of families, edited through the editing operations of its resource.
@MainActor
struct FamilyWorld {
    let metamodels = FamilyMetamodels()
    let resource: Resource
    let registry: DynamicEObject
    var counter = 0

    init(families: Int, membersPerFamily: Int, seed: UInt64) async throws {
        resource = Resource(uri: "memory:/families.xmi")
        var root = DynamicEObject(eClass: metamodels.registry)
        var generator = SplitMixGenerator(seed: seed)
        var previous: EUUID?
        var familyObjects: [DynamicEObject] = []
        var memberObjects: [(family: EUUID, member: DynamicEObject)] = []
        for f in 0..<families {
            var family = DynamicEObject(eClass: metamodels.family)
            family.eSet("lastName", value: "Family\(f)")
            familyObjects.append(family)
            for m in 0..<membersPerFamily {
                var member = DynamicEObject(eClass: metamodels.member)
                member.eSet("firstName", value: "M\(f)x\(m)")
                member.eSet("age", value: Int.random(in: 1...90, using: &generator))
                member.eSet("isFemale", value: Bool.random(using: &generator))
                if let previous, Int.random(in: 0..<3, using: &generator) == 0 {
                    member.eSet("mentor", value: previous)
                }
                previous = member.id
                memberObjects.append((family.id, member))
            }
        }
        // Built in one step, so that large models load quickly
        var familiesByID = Dictionary(uniqueKeysWithValues: familyObjects.map { ($0.id, $0) })
        for (familyID, member) in memberObjects {
            var list = (familiesByID[familyID]?.eGet("members") as? [EUUID]) ?? []
            list.append(member.id)
            familiesByID[familyID]?.eSet("members", value: list)
        }
        root.eSet("families", value: familyObjects.map(\.id))
        await resource.add(contentsOf: [root] + familyObjects.map { familiesByID[$0.id]! } + memberObjects.map(\.member))
        registry = root
    }

    var module: ATLModule {
        get async throws {
            try await ATLParser().parseContent(FamilyMetamodels.module)
                .withMetamodels(source: ["IN": metamodels.families], target: ["OUT": metamodels.persons])
        }
    }

    func ids(of className: String) async -> [EUUID] {
        await resource.getAllObjectsIncludingContents().filter { $0.eClass.name == className }.map(\.id)
    }

    /// Applies a random edit to the families.
    mutating func randomEdit(_ generator: inout SplitMixGenerator) async throws {
        let members = await ids(of: "Member")
        let families = await ids(of: "Family")
        counter += 1
        switch Int.random(in: 0..<10, using: &generator) {
        case 0 where !members.isEmpty:
            try await resource.eSetWithChanges(
                objectId: members.randomElement(using: &generator)!, feature: "firstName", value: "N\(counter)")
        case 1 where !members.isEmpty:
            try await resource.eSetWithChanges(
                objectId: members.randomElement(using: &generator)!, feature: "age",
                value: Int.random(in: 1...90, using: &generator))
        case 2 where !members.isEmpty:
            let member = members.randomElement(using: &generator)!
            let current = await resource.eGet(objectId: member, feature: "isFemale") as? Bool ?? false
            try await resource.eSetWithChanges(objectId: member, feature: "isFemale", value: !current)
        case 3 where members.count > 1:
            let mentor = Bool.random(using: &generator) ? members.randomElement(using: &generator) : nil
            try await resource.eSetWithChanges(
                objectId: members.randomElement(using: &generator)!, feature: "mentor", value: mentor)
        case 4 where !families.isEmpty:
            try await resource.eSetWithChanges(
                objectId: families.randomElement(using: &generator)!, feature: "lastName", value: "L\(counter)")
        case 5 where !families.isEmpty:
            var member = DynamicEObject(eClass: metamodels.member)
            member.eSet("firstName", value: "New\(counter)")
            member.eSet("age", value: Int.random(in: 1...90, using: &generator))
            member.eSet("isFemale", value: Bool.random(using: &generator))
            let family = families.randomElement(using: &generator)!
            let size = (await resource.eGet(objectId: family, feature: "members") as? [EUUID])?.count ?? 0
            try await resource.eAdd(
                objectId: family, feature: "members", value: member, at: Int.random(in: 0...size, using: &generator))
        case 6 where members.count > 2:
            await resource.delete([members.randomElement(using: &generator)!])
        case 7 where !members.isEmpty && !families.isEmpty:
            try await resource.eAdd(
                objectId: families.randomElement(using: &generator)!, feature: "members",
                value: members.randomElement(using: &generator)!)
        case 8:
            var family = DynamicEObject(eClass: metamodels.family)
            family.eSet("lastName", value: "F\(counter)")
            try await resource.eAdd(objectId: registry.id, feature: "families", value: family)
        case 9 where families.count > 2:
            await resource.delete([families.randomElement(using: &generator)!])
        default:
            if let member = members.first {
                try await resource.eSetWithChanges(objectId: member, feature: "age", value: counter)
            }
        }
    }
}

// MARK: - Classes to relational tables

/// A classes metamodel and a relational metamodel, both written for these tests.
struct ClassMetamodels {
    let classes: EPackage
    let relational: EPackage
    let package: EClass
    let eClass: EClass
    let attribute: EClass
    let dataType: EClass

    init() {
        let k = MetamodelKit.self
        let classifier = EClass(name: "Classifier", isAbstract: true, eStructuralFeatures: [k.attribute("name", k.string)])
        let dataType = EClass(name: "DataType", eSuperTypes: [classifier])
        let attribute = EClass(
            name: "Attribute",
            eStructuralFeatures: [
                k.attribute("name", k.string), k.attribute("multiValued", k.bool),
                EReference(name: "type", eType: classifier),
            ])
        var eClass = EClass(name: "Class", eSuperTypes: [classifier])
        eClass.eStructuralFeatures = [
            k.attribute("isAbstract", k.bool),
            EReference(name: "attributes", eType: attribute, upperBound: -1, containment: true),
        ]
        eClass.eStructuralFeatures.append(EReference(name: "superClass", eType: eClass))
        let package = EClass(
            name: "Package",
            eStructuralFeatures: [
                k.attribute("name", k.string),
                EReference(name: "classes", eType: eClass, upperBound: -1, containment: true),
                EReference(name: "types", eType: dataType, upperBound: -1, containment: true),
            ])
        classes = EPackage(
            name: "Classes", nsURI: "http://example.org/classes", nsPrefix: "classes",
            eClassifiers: [classifier, dataType, attribute, eClass, package])

        let type = EClass(name: "Type", eStructuralFeatures: [k.attribute("name", k.string)])
        let column = EClass(
            name: "Column",
            eStructuralFeatures: [k.attribute("name", k.string), EReference(name: "type", eType: type)])
        let table = EClass(
            name: "Table",
            eStructuralFeatures: [
                k.attribute("name", k.string), k.attribute("width", k.int),
                EReference(name: "columns", eType: column, upperBound: -1, containment: true),
            ])
        let schema = EClass(
            name: "Schema",
            eStructuralFeatures: [
                k.attribute("name", k.string),
                EReference(name: "tables", eType: table, upperBound: -1, containment: true),
                EReference(name: "types", eType: type, upperBound: -1, containment: true),
            ])
        relational = EPackage(
            name: "Relational", nsURI: "http://example.org/relational", nsPrefix: "relational",
            eClassifiers: [type, column, table, schema])
        self.package = package
        self.eClass = eClass
        self.attribute = attribute
        self.dataType = dataType
    }

    /// A transformation of classes into relational tables, written for these tests.
    static let module = """
        module Classes2Tables;
        create OUT : Relational from IN : Classes;

        helper def : integerType : Classes!DataType =
            Classes!DataType.allInstances()->select(d | d.name = 'Integer')->first();

        helper context Classes!Class def : allAttributes : Sequence(Classes!Attribute) =
            if self.superClass.oclIsUndefined() then self.attributes
            else self.superClass.allAttributes->union(self.attributes) endif;

        rule Package2Schema {
            from p : Classes!Package
            to s : Relational!Schema (
                name <- p.name,
                tables <- p.classes->select(c | not c.isAbstract),
                types <- p.types
            )
        }

        rule DataType2Type {
            from d : Classes!DataType
            to t : Relational!Type ( name <- d.name )
        }

        rule Class2Table {
            from c : Classes!Class (not c.isAbstract)
            using { label : String = c.name.toLower(); }
            to t : Relational!Table (
                name <- label,
                width <- c.allAttributes->size(),
                columns <- c.attributes->select(a | not a.multiValued)
            )
        }

        rule Attribute2Column {
            from a : Classes!Attribute (not a.multiValued)
            to col : Relational!Column ( name <- a.name, type <- a.type )
        }

        rule MultiValued2Table {
            from a : Classes!Attribute (a.multiValued)
            to t : Relational!Table (
                name <- a.refImmediateComposite().name + '_' + a.name,
                columns <- Sequence{key, value}
            ),
            key : Relational!Column ( name <- 'id', type <- thisModule.integerType ),
            value : Relational!Column ( name <- a.name, type <- a.type )
        }
        """
}

/// A source model of classes, edited through the editing operations of its resource.
@MainActor
struct ClassWorld {
    let metamodels = ClassMetamodels()
    let resource: Resource
    let package: DynamicEObject
    var counter = 0

    init(classes: Int, attributesPerClass: Int, seed: UInt64) async throws {
        resource = Resource(uri: "memory:/classes.xmi")
        var generator = SplitMixGenerator(seed: seed)
        var package = DynamicEObject(eClass: metamodels.package)
        package.eSet("name", value: "model")
        var types: [DynamicEObject] = []
        for name in ["Integer", "String", "Boolean"] {
            var type = DynamicEObject(eClass: metamodels.dataType)
            type.eSet("name", value: name)
            types.append(type)
        }
        var classObjects: [DynamicEObject] = []
        var attributes: [DynamicEObject] = []
        for c in 0..<classes {
            var eClass = DynamicEObject(eClass: metamodels.eClass)
            eClass.eSet("name", value: "Class\(c)")
            eClass.eSet("isAbstract", value: Int.random(in: 0..<5, using: &generator) == 0)
            if let superClass = classObjects.randomElement(using: &generator), Bool.random(using: &generator) {
                eClass.eSet("superClass", value: superClass.id)
            }
            var owned: [EUUID] = []
            for a in 0..<attributesPerClass {
                var attribute = DynamicEObject(eClass: metamodels.attribute)
                attribute.eSet("name", value: "a\(c)x\(a)")
                attribute.eSet("multiValued", value: Int.random(in: 0..<4, using: &generator) == 0)
                attribute.eSet("type", value: types.randomElement(using: &generator)!.id)
                attributes.append(attribute)
                owned.append(attribute.id)
            }
            eClass.eSet("attributes", value: owned)
            classObjects.append(eClass)
        }
        package.eSet("classes", value: classObjects.map(\.id))
        package.eSet("types", value: types.map(\.id))
        await resource.add(contentsOf: [package] + types + classObjects + attributes)
        self.package = package
    }

    var module: ATLModule {
        get async throws {
            try await ATLParser().parseContent(ClassMetamodels.module)
                .withMetamodels(source: ["IN": metamodels.classes], target: ["OUT": metamodels.relational])
        }
    }

    func ids(of className: String) async -> [EUUID] {
        await resource.getAllObjectsIncludingContents().filter { $0.eClass.name == className }.map(\.id)
    }

    /// Applies a random edit to the classes.
    mutating func randomEdit(_ generator: inout SplitMixGenerator) async throws {
        let classes = await ids(of: "Class")
        let attributes = await ids(of: "Attribute")
        let types = await ids(of: "DataType")
        counter += 1
        switch Int.random(in: 0..<11, using: &generator) {
        case 0 where !classes.isEmpty:
            try await resource.eSetWithChanges(
                objectId: classes.randomElement(using: &generator)!, feature: "name", value: "C\(counter)")
        case 1 where !classes.isEmpty:
            let target = classes.randomElement(using: &generator)!
            let current = await resource.eGet(objectId: target, feature: "isAbstract") as? Bool ?? false
            try await resource.eSetWithChanges(objectId: target, feature: "isAbstract", value: !current)
        case 2 where !attributes.isEmpty:
            let target = attributes.randomElement(using: &generator)!
            let current = await resource.eGet(objectId: target, feature: "multiValued") as? Bool ?? false
            try await resource.eSetWithChanges(objectId: target, feature: "multiValued", value: !current)
        case 3 where !attributes.isEmpty:
            try await resource.eSetWithChanges(
                objectId: attributes.randomElement(using: &generator)!, feature: "type",
                value: types.randomElement(using: &generator))
        case 4 where classes.count > 1:
            // Only an earlier class may become the superclass, so that no cycle forms
            let position = Int.random(in: 1..<classes.count, using: &generator)
            let superClass = Bool.random(using: &generator)
                ? classes[Int.random(in: 0..<position, using: &generator)] : nil
            try await resource.eSetWithChanges(objectId: classes[position], feature: "superClass", value: superClass)
        case 5 where !classes.isEmpty:
            var attribute = DynamicEObject(eClass: metamodels.attribute)
            attribute.eSet("name", value: "n\(counter)")
            attribute.eSet("multiValued", value: Bool.random(using: &generator))
            attribute.eSet("type", value: types.randomElement(using: &generator)!)
            try await resource.eAdd(
                objectId: classes.randomElement(using: &generator)!, feature: "attributes", value: attribute)
        case 6 where attributes.count > 1:
            await resource.delete([attributes.randomElement(using: &generator)!])
        case 7:
            var eClass = DynamicEObject(eClass: metamodels.eClass)
            eClass.eSet("name", value: "K\(counter)")
            let size = (await resource.eGet(objectId: package.id, feature: "classes") as? [EUUID])?.count ?? 0
            try await resource.eAdd(
                objectId: package.id, feature: "classes", value: eClass, at: Int.random(in: 0...size, using: &generator))
        case 8 where classes.count > 2:
            // Classes that others extend are kept, so that no superclass reference dangles
            var extended = Set<EUUID>()
            for id in classes {
                if let superClass = await resource.eGet(objectId: id, feature: "superClass") as? EUUID {
                    extended.insert(superClass)
                }
            }
            if let doomed = classes.filter({ !extended.contains($0) }).randomElement(using: &generator) {
                await resource.delete([doomed])
            }
        case 9 where attributes.count > 1 && classes.count > 1:
            try await resource.eAdd(
                objectId: classes.randomElement(using: &generator)!, feature: "attributes",
                value: attributes.randomElement(using: &generator)!)
        case 10 where !types.isEmpty:
            try await resource.eSetWithChanges(
                objectId: types.randomElement(using: &generator)!, feature: "name",
                value: Bool.random(using: &generator) ? "Integer" : "T\(counter)")
        default:
            try await resource.eSetWithChanges(objectId: package.id, feature: "name", value: "P\(counter)")
        }
    }
}

// MARK: - Batch reference

/// Runs a module as a whole over a source model and serialises the target model.
@MainActor
func batchXMI(
    module: ATLModule, source: Resource, targetURI: String, options: ATLOptions = .standard
) async throws -> String {
    let target = Resource(uri: targetURI)
    let machine = ATLVirtualMachine(module: module, options: options)
    try await machine.execute(sources: ["IN": source], targets: ["OUT": target])
    return try await XMISerializer().serialize(target)
}
