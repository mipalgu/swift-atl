//
//  ATLEObjectConformanceTests.swift
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

/// A garden metamodel without a class of its own called `EObject`, and a label metamodel.
///
/// `Garden!EObject` therefore names Ecore's `EObject`, the implicit supertype of every
/// class, so rules and `allInstances()` can use it.
@MainActor
struct GardenFixture {
    /// The name of the garden metamodel.
    static let gardenName = "Garden"

    /// The name of the label metamodel.
    static let labelsName = "Labels"

    let garden: EPackage
    let labels: EPackage
    let plant: EClass
    let tree: EClass
    let shrub: EClass
    let bed: EClass
    let label: EClass

    init() {
        let string = EDataType(name: "EString")
        let plant = EClass(
            name: "Plant", isAbstract: true, eStructuralFeatures: [EAttribute(name: "name", eType: string)])
        let tree = EClass(name: "Tree", eSuperTypes: [plant])
        let shrub = EClass(name: "Shrub", eSuperTypes: [plant])
        let bed = EClass(
            name: "Bed",
            eStructuralFeatures: [
                EAttribute(name: "name", eType: string),
                EReference(name: "plants", eType: plant, upperBound: -1, containment: true),
            ])
        let label = EClass(name: "Label", eStructuralFeatures: [EAttribute(name: "text", eType: string)])
        self.plant = plant
        self.tree = tree
        self.shrub = shrub
        self.bed = bed
        self.label = label
        garden = EPackage(
            name: Self.gardenName, nsURI: "http://example.org/garden", nsPrefix: "gdn",
            eClassifiers: [plant, tree, shrub, bed])
        labels = EPackage(
            name: Self.labelsName, nsURI: "http://example.org/labels", nsPrefix: "lbl", eClassifiers: [label])
    }

    /// Creates a source model with a bed of two trees and a shrub.
    ///
    /// - Returns: The source model and the identifier of its bed.
    func source() async -> (Resource, EUUID) {
        let resource = Resource(uri: "memory:/garden.xmi")
        var bed = DynamicEObject(eClass: bed)
        bed.eSet("name", value: "bed")
        var plants: [DynamicEObject] = []
        for (name, eClass) in [("oak", tree), ("elm", tree), ("box", shrub)] {
            var plant = DynamicEObject(eClass: eClass)
            plant.eSet("name", value: name)
            plants.append(plant)
        }
        bed.eSet("plants", value: plants.map(\.id))
        await resource.add(bed)
        for plant in plants { await resource.add(plant) }
        return (resource, bed.id)
    }

    /// Parses a module that transforms gardens into labels.
    ///
    /// - Parameter rules: The rules and helpers of the module.
    /// - Returns: The parsed module.
    func module(_ rules: String) async throws -> ATLModule {
        let registry = ATLMetamodelRegistry(packages: [garden, labels])
        return try await ATLParser(options: .standard).parseContent(
            """
            module Garden2Labels;
            create OUT : \(Self.labelsName) from IN : \(Self.gardenName);
            \(rules)
            """, metamodelRegistry: registry)
    }

    /// Runs rules on the standard source model.
    ///
    /// - Parameter rules: The rules and helpers of the module.
    /// - Returns: The texts of the labels created, sorted.
    func run(_ rules: String) async throws -> [String] {
        let (source, _) = await source()
        let target = Resource(uri: "memory:/labels.xmi")
        try await ATLVirtualMachine(module: try await module(rules), options: .standard).execute(
            sources: ["IN": source], targets: ["OUT": target])
        return await texts(of: target)
    }

    /// The texts of the labels of a target model.
    ///
    /// - Parameter target: The target model.
    /// - Returns: The texts, sorted.
    func texts(of target: Resource) async -> [String] {
        await target.getAllObjects().compactMap { ($0 as? DynamicEObject)?.eGet("text") as? String }.sorted()
    }
}

/// Tests that Ecore's `EObject` is the supertype of every model object, as in EMF.
@Suite("ATL EObject Conformance Tests")
@MainActor
struct ATLEObjectConformanceTests {

    /// Evaluates an expression with `obj` bound to an object.
    private func evaluate(
        _ expression: String, object: DynamicEObject, fixture: ShapeFixture, declarations: String = ""
    ) async throws -> (any EcoreValue)? {
        let harness = try await LanguageHarness.make(
            declarations: declarations, expression: expression, fixture: fixture)
        harness.context.setVariable("obj", value: object)
        return try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
    }

    // MARK: - Type operations

    @Test(
        "Every model object is a kind of EObject",
        arguments: ["ECORE!EObject", "ecore!EObject", "Shapes!EObject", "EObject"])
    func kindOfEObject(typeName: String) async throws {
        let fixture = ShapeFixture()
        for eClass in [fixture.labelledCircle, fixture.square, fixture.drawing] {
            let result = try await evaluate(
                "obj.oclIsKindOf(\(typeName))", object: fixture.make(eClass), fixture: fixture)
            #expect(result as? Bool == true, "\(eClass.name)")
        }
    }

    @Test("Only an object whose class is EObject is of type EObject")
    func typeOfEObject() async throws {
        let fixture = ShapeFixture()
        let circle = try await evaluate(
            "obj.oclIsTypeOf(ECORE!EObject)", object: fixture.make(fixture.circle), fixture: fixture)
        #expect(circle as? Bool == false)
        let plain = DynamicEObject(eClass: EcorePackage.metaClass(.eObject))
        let object = try await evaluate("obj.oclIsTypeOf(ECORE!EObject)", object: plain, fixture: fixture)
        #expect(object as? Bool == true)
        #expect(ATLTypeMatching.isType(plain, of: "EObject"))
        #expect(!ATLTypeMatching.isType(plain, of: "Shape"))
    }

    @Test("A model object can be cast to EObject")
    func castToEObject() async throws {
        let fixture = ShapeFixture()
        let object = fixture.make(fixture.square)
        let result = try await evaluate("obj.oclAsType(ECORE!EObject)", object: object, fixture: fixture)
        #expect((result as? any EObject)?.id == object.id)
    }

    @Test(
        "Values that are not model objects are not EObjects",
        arguments: [
            "1.oclIsKindOf(ECORE!EObject)", "'a'.oclIsKindOf(ECORE!EObject)",
            "OclUndefined.oclIsKindOf(ECORE!EObject)", "Sequence{1}.oclIsKindOf(ECORE!EObject)",
            "true.oclIsTypeOf(ECORE!EObject)",
        ])
    func primitivesAreNotEObjects(expression: String) async throws {
        #expect(try await LanguageHarness.evaluate(expression) as? Bool == false)
    }

    @Test("EObject is further from a class than any of its supertypes and nearer than OclAny")
    func eObjectDistance() {
        let fixture = ShapeFixture()
        let labelled = fixture.make(fixture.labelledCircle)
        let shape = ATLTypeMatching.distance(of: labelled, to: "Shape")
        let eObject = ATLTypeMatching.distance(of: labelled, to: "ECORE!EObject")
        #expect(shape == 2)
        #expect(eObject == 3)
        #expect(ATLTypeMatching.distance(of: fixture.make(fixture.drawing), to: "EObject") == 1)
        #expect(ATLTypeMatching.distance(of: DynamicEObject(eClass: EcorePackage.metaClass(.eObject)), to: "EObject") == 0)
        #expect((eObject ?? .max) < ATLTypeMatching.anyDistance)
    }

    @Test("A supertype named EObject stays further than every other supertype")
    func explicitEObjectSupertype() {
        let eObject = EClass(name: EcoreClassifier.eObject.rawValue)
        let base = EClass(name: "Base")
        let middle = EClass(name: "Middle", eSuperTypes: [base])
        let leaf = EClass(name: "Leaf", eSuperTypes: [eObject, middle])
        let object = DynamicEObject(eClass: leaf)
        #expect(ATLTypeMatching.distance(of: object, to: "Base") == 2)
        #expect(ATLTypeMatching.distance(of: object, to: "EObject") == 3)
    }

    // MARK: - Contextual helpers

    @Test("A helper on EObject applies to every model object unless a nearer helper exists")
    func helperOnEObject() async throws {
        let declarations = """
            helper context OclAny def : kind() : String = 'any';
            helper context ECORE!EObject def : kind() : String = 'object';
            helper context Shapes!Circle def : kind() : String = 'circle';
            """
        let fixture = ShapeFixture()
        let expected: [(EClass, String)] = [
            (fixture.circle, "circle"), (fixture.labelledCircle, "circle"), (fixture.square, "object"),
            (fixture.drawing, "object"),
        ]
        for (eClass, kind) in expected {
            let result = try await evaluate(
                "obj.kind()", object: fixture.make(eClass), fixture: fixture, declarations: declarations)
            #expect(result as? String == kind, "\(eClass.name)")
        }
        let integer = try await LanguageHarness.evaluate("1.kind()", declarations: declarations)
        #expect(integer as? String == "any")
    }

    @Test("A helper on EObject alone applies to every model object")
    func onlyEObjectHelper() async throws {
        let declarations = "helper context ECORE!EObject def : kind() : String = 'object';"
        let fixture = ShapeFixture()
        let result = try await evaluate(
            "obj.kind()", object: fixture.make(fixture.square), fixture: fixture, declarations: declarations)
        #expect(result as? String == "object")
    }

    // MARK: - allInstances

    @Test("allInstances of EObject returns every object of the model")
    func allInstancesOfEObject() async throws {
        let fixture = GardenFixture()
        let (source, _) = await fixture.source()
        let module = try await fixture.module("helper def : all : Integer = Garden!EObject.allInstances()->size();")
        let context = ATLExecutionContext(
            module: module, sources: ["IN": source], targets: [:],
            executionEngine: ECoreExecutionEngine(models: [:]))
        let count = try await context.callHelper("all", arguments: [])
        #expect(count as? Int == 4)
        let from = try await ATLMethodCallExpression(
            receiver: ATLTypeLiteralExpression(typeName: "Garden!EObject"), methodName: "allInstancesFrom",
            arguments: [ATLLiteralExpression(value: "IN")]
        ).evaluate(in: context)
        #expect(from.collectionElements?.count == 4)
    }

    @Test("allInstances of Ecore's EObject returns every element of an Ecore model")
    func allInstancesOfEcoreEObject() async throws {
        let item = EClass(name: "Item", eStructuralFeatures: [EAttribute(name: "name", eType: EDataType(name: "EString"))])
        let group = EClass(name: "Group")
        let package = EPackage(name: "parts", nsURI: "http://example.org/parts", eClassifiers: [item, group])
        let source = Resource(uri: "memory:/parts.ecore")
        await source.add(package)
        let expected = await source.getAllObjectsIncludingContents().count
        let classes = await source.getAllInstancesOf(EcorePackage.metaClass(.eClass)).count
        let registry = ATLMetamodelRegistry(packages: [EcorePackage.instance])
        let module = try await ATLParser(options: .standard).parseContent(
            """
            module Count;
            create OUT : ecore from IN : ecore;
            helper def : objects : Integer = ecore!EObject.allInstances()->size();
            helper def : classes : Integer = ecore!EClass.allInstances()->size();
            """, metamodelRegistry: registry)
        let context = ATLExecutionContext(
            module: module, sources: ["IN": source], targets: [:],
            executionEngine: ECoreExecutionEngine(models: [:]))
        #expect(expected > classes)
        #expect(try await context.callHelper("objects", arguments: []) as? Int == expected)
        #expect(try await context.callHelper("classes", arguments: []) as? Int == classes)
    }

    // MARK: - Matched rules

    @Test("A rule whose source is EObject matches every object")
    func ruleOnEObject() async throws {
        let texts = try await GardenFixture().run(
            """
            rule Any {
                from o : Garden!EObject
                to l : Labels!Label (text <- o.name)
            }
            """)
        #expect(texts == ["bed", "box", "elm", "oak"])
    }

    @Test("A rule on a class extending a rule on EObject takes the objects of that class")
    func subRuleOfEObjectRule() async throws {
        for options in [ATLOptions.standard, ATLOptions.legacy] {
            let fixture = GardenFixture()
            let (source, _) = await fixture.source()
            let target = Resource(uri: "memory:/labels.xmi")
            let module = try await fixture.module(
                """
                rule Any {
                    from o : Garden!EObject
                    to l : Labels!Label (text <- 'object ' + o.name)
                }
                rule Trees extends Any {
                    from o : Garden!Tree
                    to l : Labels!Label (text <- 'tree ' + o.name)
                }
                """)
            try await ATLVirtualMachine(module: module, options: options).execute(
                sources: ["IN": source], targets: ["OUT": target])
            #expect(await fixture.texts(of: target) == ["object bed", "object box", "tree elm", "tree oak"])
        }
    }

    @Test("A rule on EObject cannot extend a rule on a class")
    func eObjectRuleCannotExtendClassRule() async throws {
        let fixture = GardenFixture()
        await #expect(throws: ATLExecutionError.self) {
            _ = try await fixture.run(
                """
                rule Trees {
                    from o : Garden!Tree
                    to l : Labels!Label (text <- o.name)
                }
                rule Any extends Trees {
                    from o : Garden!EObject
                    to l : Labels!Label (text <- o.name)
                }
                """)
        }
    }

    @Test("Class conformance treats EObject as the supertype of every class and nothing else")
    func classConformance() {
        let fixture = GardenFixture()
        let eObject = EcorePackage.metaClass(.eObject)
        let local = EClass(name: EcoreClassifier.eObject.rawValue)
        #expect(ATLTypeMatching.conforms(fixture.tree, to: eObject))
        #expect(!ATLTypeMatching.conforms(fixture.bed, to: local))
        #expect(ATLTypeMatching.conforms(fixture.tree, to: fixture.plant))
        #expect(ATLTypeMatching.conforms(fixture.tree, to: EClass(name: "Plant")))
        #expect(!ATLTypeMatching.conforms(eObject, to: fixture.tree))
        #expect(!ATLTypeMatching.conforms(fixture.plant, to: fixture.tree))
        #expect(!ATLTypeMatching.conforms(fixture.tree, to: fixture.shrub))
    }

    // MARK: - Incremental propagation

    @Test("Adding an object adds a match of a rule on EObject")
    func incrementalRuleOnEObject() async throws {
        let fixture = GardenFixture()
        let (source, bed) = await fixture.source()
        let target = Resource(uri: "memory:/labels.xmi")
        let module = try await fixture.module(
            """
            rule Any {
                from o : Garden!EObject
                to l : Labels!Label (text <- o.name)
            }
            """)
        let transformation = ATLIncrementalTransformation(module: module, options: .standard)
        try await transformation.execute(sources: ["IN": source], targets: ["OUT": target])
        #expect(transformation.matchCount == 4)
        var shrub = DynamicEObject(eClass: fixture.shrub)
        shrub.eSet("name", value: "yew")
        try await source.eAdd(objectId: bed, feature: "plants", value: shrub, at: 0)
        let report = try await transformation.update()
        #expect(report.matchesAdded == 1)
        #expect(await fixture.texts(of: target) == ["bed", "box", "elm", "oak", "yew"])
    }

    // MARK: - Model adapters

    @Test("The model adapters list every element as an instance of EObject")
    func adaptersListEObjectInstances() async throws {
        let fixture = GardenFixture()
        let (source, _) = await fixture.source()
        let eObject = EcorePackage.metaClass(.eObject)
        let sourceModel = ATLSourceModel(resource: source, alias: "IN", metamodel: fixture.garden)
        #expect(await sourceModel.getElementsByType(eObject).count == 4)
        #expect(await sourceModel.getElementsByType(fixture.tree).count == 2)
        #expect(await sourceModel.getElementsByType(fixture.bed).count == 1)
        let targetModel = ATLTargetModel(resource: source, alias: "OUT", metamodel: fixture.garden)
        #expect(await targetModel.getElementsByType(eObject).count == 4)
        #expect(await targetModel.getElementsByType(fixture.shrub).count == 1)
        #expect(await targetModel.getElementsByType(EClass(name: "Tree")).isEmpty)
    }
}
