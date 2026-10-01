//
//  ATLTypeOperationTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import OrderedCollections
import Testing

@testable import ATL

/// Tests for `oclIsKindOf`, `oclIsTypeOf`, `oclAsType`, `oclType` and `allInstances`.
@Suite("ATL Type Operation Tests")
@MainActor
struct ATLTypeOperationTests {

    /// Evaluates an expression with `obj` bound to an object of the given class.
    private func evaluate(
        _ expression: String, object: DynamicEObject, fixture: ShapeFixture
    ) async throws -> (any EcoreValue)? {
        let harness = try await LanguageHarness.make(expression: expression, fixture: fixture)
        harness.context.setVariable("obj", value: object)
        return try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
    }

    // MARK: - oclIsKindOf over the supertype closure

    @Test(
        "oclIsKindOf accepts the class and every supertype",
        arguments: [
            ("Shapes!LabelledCircle", true), ("Shapes!Circle", true), ("Shapes!Shape", true),
            ("Shapes!Square", false), ("Shapes!Drawing", false), ("OclAny", true),
            ("LabelledCircle", true), ("Shape", true),
        ])
    func kindOfSupertypeClosure(typeName: String, expected: Bool) async throws {
        let fixture = ShapeFixture()
        let object = fixture.make(fixture.labelledCircle)
        let result = try await evaluate("obj.oclIsKindOf(\(typeName))", object: object, fixture: fixture)
        #expect(result as? Bool == expected)
    }

    @Test("oclIsKindOf follows every supertype, not only the first")
    func kindOfSecondSupertype() async throws {
        let string = EDataType(name: "EString")
        let first = EClass(name: "First", eStructuralFeatures: [EAttribute(name: "a", eType: string)])
        let second = EClass(name: "Second")
        let both = EClass(name: "Both", eSuperTypes: [first, second])
        let package = EPackage(
            name: "Multi", nsURI: "http://example.org/multi", eClassifiers: [first, second, both])
        let module = ATLModule(
            name: "M", sourceMetamodels: ["IN": package], targetMetamodels: ["OUT": package])
        let context = ATLExecutionContext(
            module: module, executionEngine: ECoreExecutionEngine(models: [:]))
        let object = DynamicEObject(eClass: both)

        context.setVariable("o", value: object)
        for typeName in ["Multi!First", "Multi!Second", "Multi!Both"] {
            let expression = ATLMethodCallExpression(
                receiver: ATLVariableExpression(name: "o"), methodName: "oclIsKindOf",
                arguments: [ATLTypeLiteralExpression(typeName: typeName)])
            #expect(try await expression.evaluate(in: context) as? Bool == true)
        }
    }

    @Test("oclIsKindOf handles diamond inheritance without looping")
    func diamondInheritance() {
        let top = EClass(name: "Top")
        let left = EClass(name: "Left", eSuperTypes: [top])
        let right = EClass(name: "Right", eSuperTypes: [top])
        let bottom = EClass(name: "Bottom", eSuperTypes: [left, right])
        let object = DynamicEObject(eClass: bottom)
        #expect(ATLTypeMatching.isKind(object, of: "Top"))
        #expect(ATLTypeMatching.distance(of: object, to: "Top") == 2)
        #expect(ATLTypeMatching.distance(of: object, to: "Bottom") == 0)
        #expect(ATLTypeMatching.distance(of: object, to: "Left") == 1)
    }

    @Test(
        "oclIsKindOf on primitive values",
        arguments: [
            ("1.oclIsKindOf(Integer)", true), ("1.oclIsKindOf(Real)", true),
            ("1.5.oclIsKindOf(Integer)", false), ("1.5.oclIsKindOf(Real)", true),
            ("'a'.oclIsKindOf(String)", true), ("'a'.oclIsKindOf(Integer)", false),
            ("true.oclIsKindOf(Boolean)", true), ("true.oclIsKindOf(String)", false),
            ("1.oclIsKindOf(OclAny)", true), ("OclUndefined.oclIsKindOf(String)", false),
            ("Sequence{1}.oclIsKindOf(Sequence(Integer))", true),
            ("Sequence{1}.oclIsKindOf(Collection(Integer))", true),
            ("Set{1}.oclIsKindOf(Set(Integer))", true),
            ("Set{1}.oclIsKindOf(Sequence(Integer))", false),
            ("OrderedSet{1}.oclIsKindOf(Collection(Integer))", true),
        ])
    func primitiveKinds(expression: String, expected: Bool) async throws {
        #expect(try await LanguageHarness.evaluate(expression) as? Bool == expected)
    }

    // MARK: - oclIsTypeOf

    @Test(
        "oclIsTypeOf is exact",
        arguments: [
            ("Shapes!LabelledCircle", true), ("Shapes!Circle", false), ("Shapes!Shape", false),
        ])
    func typeOfIsExact(typeName: String, expected: Bool) async throws {
        let fixture = ShapeFixture()
        let object = fixture.make(fixture.labelledCircle)
        let result = try await evaluate("obj.oclIsTypeOf(\(typeName))", object: object, fixture: fixture)
        #expect(result as? Bool == expected)
    }

    @Test(
        "oclIsTypeOf on primitive values",
        arguments: [
            ("1.oclIsTypeOf(Integer)", true), ("1.oclIsTypeOf(Real)", false),
            ("1.5.oclIsTypeOf(Real)", true), ("'a'.oclIsTypeOf(String)", true),
            ("OclUndefined.oclIsTypeOf(OclUndefined)", true),
        ])
    func primitiveTypes(expression: String, expected: Bool) async throws {
        #expect(try await LanguageHarness.evaluate(expression) as? Bool == expected)
    }

    // MARK: - oclAsType

    @Test("oclAsType returns the receiver when it conforms")
    func asTypeConforming() async throws {
        let fixture = ShapeFixture()
        let object = fixture.make(fixture.circle, ["name": "c"])
        let result = try await evaluate("obj.oclAsType(Shapes!Shape)", object: object, fixture: fixture)
        #expect((result as? any EObject)?.id == object.id)
    }

    @Test("oclAsType fails when the receiver does not conform")
    func asTypeNonConforming() async throws {
        let fixture = ShapeFixture()
        let object = fixture.make(fixture.circle)
        await #expect(throws: ATLExecutionError.self) {
            _ = try await self.evaluate("obj.oclAsType(Shapes!Square)", object: object, fixture: fixture)
        }
    }

    @Test("oclAsType converts integers to reals and keeps the undefined value")
    func asTypePrimitives() async throws {
        #expect(try await LanguageHarness.evaluate("3.oclAsType(Real)") as? Double == 3.0)
        #expect(try await LanguageHarness.evaluate("'a'.oclAsType(String)") as? String == "a")
        #expect(try await LanguageHarness.evaluate("OclUndefined.oclAsType(String)") == nil)
        await #expect(throws: ATLExecutionError.self) {
            _ = try await LanguageHarness.evaluate("'a'.oclAsType(Integer)")
        }
    }

    // MARK: - oclType

    @Test("oclType returns the class of a model object")
    func typeOfObject() async throws {
        let fixture = ShapeFixture()
        let object = fixture.make(fixture.circle)
        let result = try await evaluate("obj.oclType()", object: object, fixture: fixture)
        #expect((result as? EClass)?.name == "Circle")
        let same = try await evaluate(
            "obj.oclType() = obj.oclType() and obj.oclType().name = 'Circle'",
            object: object, fixture: fixture)
        #expect(same as? Bool == true)
    }

    @Test(
        "oclType names primitive and collection types",
        arguments: [
            ("1.oclType()", "Integer"), ("1.5.oclType()", "Real"), ("'a'.oclType()", "String"),
            ("true.oclType()", "Boolean"), ("OclUndefined.oclType()", "OclUndefined"),
            ("Sequence{1}.oclType()", "Sequence"), ("Set{1}.oclType()", "Set"),
            ("OrderedSet{1}.oclType()", "OrderedSet"),
        ])
    func typeOfPrimitive(expression: String, expected: String) async throws {
        #expect(try await LanguageHarness.evaluate(expression) as? String == expected)
    }

    @Test("Type names reduce to their base name")
    func baseNames() {
        #expect(ATLTypeMatching.baseName("Shapes!Circle") == "Circle")
        #expect(ATLTypeMatching.baseName("Sequence(Integer)") == "Sequence")
        #expect(ATLTypeMatching.baseName("Sequence(Shapes!Circle)") == "Sequence")
        #expect(ATLTypeMatching.baseName("String") == "String")
        #expect(ATLTypeMatching.typeName(of: 1) == "Integer")
    }

    // MARK: - allInstances

    private func populatedSource(_ fixture: ShapeFixture) async -> (Resource, [DynamicEObject]) {
        let resource = Resource(uri: "test://source")
        let objects = [
            fixture.make(fixture.circle, ["name": "c1"]),
            fixture.make(fixture.labelledCircle, ["name": "c2"]),
            fixture.make(fixture.square, ["name": "s1"]),
        ]
        for object in objects { await resource.add(object) }
        return (resource, objects)
    }

    @Test("allInstances returns every instance including subclass instances")
    func allInstancesIncludesSubclasses() async throws {
        let fixture = ShapeFixture()
        let (resource, _) = await populatedSource(fixture)
        let sources: OrderedDictionary<String, Resource> = ["IN": resource]

        let circles = try await LanguageHarness.evaluate(
            "Shapes!Circle.allInstances()->collect(c | c.name)->sortedBy(n | n)", fixture: fixture,
            sources: sources)
        #expect(circles.strings == ["c1", "c2"])

        let shapes = try await LanguageHarness.evaluate(
            "Shapes!Shape.allInstances()->size()", fixture: fixture, sources: sources)
        #expect(shapes as? Int == 3)
    }

    @Test("allInstancesFrom restricts the search to one model")
    func allInstancesFromModel() async throws {
        let fixture = ShapeFixture()
        let (resource, _) = await populatedSource(fixture)
        let sources: OrderedDictionary<String, Resource> = ["IN": resource]

        let result = try await LanguageHarness.evaluate(
            "Shapes!Square.allInstancesFrom('IN')->size()", fixture: fixture, sources: sources)
        #expect(result as? Int == 1)
    }

    @Test("allInstancesFrom rejects unknown models and non-model receivers")
    func allInstancesFromErrors() async throws {
        let fixture = ShapeFixture()
        await #expect(throws: ATLExecutionError.self) {
            _ = try await LanguageHarness.evaluate(
                "Shapes!Square.allInstancesFrom('NOPE')", fixture: fixture)
        }
        await #expect(throws: ATLExecutionError.self) {
            _ = try await LanguageHarness.evaluate("3.allInstancesFrom('IN')", fixture: fixture)
        }
        await #expect(throws: ATLExecutionError.self) {
            _ = try await LanguageHarness.evaluate("3.allInstances()", fixture: fixture)
        }
    }

    @Test("allInstancesFrom requires a string model name and oclIsKindOf a type")
    func argumentTypeErrors() async {
        await #expect(throws: ATLExecutionError.self) {
            _ = try await LanguageHarness.evaluate("Shapes!Square.allInstancesFrom(3)")
        }
        await #expect(throws: ATLExecutionError.self) {
            _ = try await LanguageHarness.evaluate("1.oclIsKindOf(1 + 1)")
        }
    }

    @Test("A type argument may be an expression that evaluates to a type name")
    func computedTypeName() async throws {
        #expect(try await LanguageHarness.evaluate("1.oclIsKindOf('Integer')") as? Bool == true)
    }

    @Test("allInstances rejects unknown metamodels and classes")
    func allInstancesUnknown() async {
        await #expect(throws: ATLExecutionError.self) {
            _ = try await LanguageHarness.evaluate("Other!Square.allInstances()")
        }
        await #expect(throws: ATLExecutionError.self) {
            _ = try await LanguageHarness.evaluate("Shapes!Triangle.allInstances()")
        }
    }

    @Test("allInstances of a target-only metamodel searches the target model")
    func allInstancesTarget() async throws {
        let fixture = ShapeFixture()
        let item = EClass(name: "Item")
        let package = EPackage(name: "Targets", nsURI: "http://example.org/targets", eClassifiers: [item])
        let module = ATLModule(
            name: "T", sourceMetamodels: ["IN": fixture.package], targetMetamodels: ["OUT": package])
        let target = Resource(uri: "test://target")
        await target.add(DynamicEObject(eClass: item))
        let context = ATLExecutionContext(
            module: module, sources: [:], targets: ["OUT": target],
            executionEngine: ECoreExecutionEngine(models: [:]))
        let call = ATLMethodCallExpression(
            receiver: ATLTypeLiteralExpression(typeName: "Targets!Item"), methodName: "allInstances")
        #expect(try await call.evaluate(in: context).collectionElements?.count == 1)
    }

    @Test("Unqualified allInstances searches all models")
    func allInstancesUnqualified() async throws {
        let fixture = ShapeFixture()
        let (resource, _) = await populatedSource(fixture)
        let sources: OrderedDictionary<String, Resource> = ["IN": resource]
        let harness = try await LanguageHarness.make(fixture: fixture, sources: sources)
        let call = ATLMethodCallExpression(
            receiver: ATLLiteralExpression(value: "Square"), methodName: "allInstances")
        #expect(try await call.evaluate(in: harness.context).collectionElements?.count == 1)
    }
}
