//
//  ATLHelperOverloadTests.swift
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

/// Tests for helpers keyed by context type and name, and for attribute helper caching.
@Suite("ATL Helper Overload Tests")
@MainActor
struct ATLHelperOverloadTests {

    private static let labels = """
        helper context Shapes!Shape def : label() : String = 'shape ' + self.name;
        helper context Shapes!Circle def : label() : String = 'circle ' + self.name;
        helper context Shapes!LabelledCircle def : label() : String = 'labelled ' + self.name;
        """

    private func evaluate(
        _ expression: String, declarations: String = labels, objects: [String: DynamicEObject] = [:],
        fixture: ShapeFixture = ShapeFixture()
    ) async throws -> (any EcoreValue)? {
        let harness = try await LanguageHarness.make(
            declarations: declarations, expression: expression, fixture: fixture)
        for (name, object) in objects { harness.context.setVariable(name, value: object) }
        return try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
    }

    // MARK: - Parsing

    @Test("Helpers that share a name but not a context all survive parsing")
    func overloadsAreKept() async throws {
        let harness = try await LanguageHarness.make(declarations: Self.labels)
        let overloads = try #require(harness.module.helperOverloads["label"])
        #expect(overloads.count == 3)
        #expect(
            overloads.compactMap(\.contextType)
                == ["Shapes!Shape", "Shapes!Circle", "Shapes!LabelledCircle"])
        #expect(harness.module.helpers["label"] != nil)
    }

    @Test("A repeated definition for the same context replaces the earlier one")
    func redefinitionReplaces() async throws {
        let harness = try await LanguageHarness.make(
            declarations: """
                helper context Shapes!Shape def : label() : String = 'first';
                helper context Shapes!Shape def : label() : String = 'second';
                """)
        #expect(harness.module.helperOverloads["label"]?.count == 1)
    }

    @Test("Hand-built modules get overloads derived from their helpers")
    func derivedOverloads() {
        let helper = ATLHelperWrapper(
            name: "h", contextType: "Integer", returnType: "Integer",
            body: ATLLiteralExpression(value: 1))
        let module = ATLModule(
            name: "M", sourceMetamodels: ["IN": EPackage(name: "A")],
            targetMetamodels: ["OUT": EPackage(name: "B")], helpers: ["h": helper])
        #expect(module.helperOverloads["h"]?.count == 1)
    }

    // MARK: - Dispatch on the dynamic type

    @Test(
        "The most specific context type wins",
        arguments: [("circle", "circle c"), ("labelled", "labelled l"), ("square", "shape s")])
    func mostSpecificWins(variable: String, expected: String) async throws {
        let fixture = ShapeFixture()
        let objects: [String: DynamicEObject] = [
            "circle": fixture.make(fixture.circle, ["name": "c"]),
            "labelled": fixture.make(fixture.labelledCircle, ["name": "l"]),
            "square": fixture.make(fixture.square, ["name": "s"]),
        ]
        let result = try await evaluate("\(variable).label()", objects: objects, fixture: fixture)
        #expect(result as? String == expected)
    }

    @Test("Overloads are chosen per element when called inside a collection operation")
    func dispatchInsideIterator() async throws {
        let fixture = ShapeFixture()
        let list = EcoreValueArray([
            fixture.make(fixture.square, ["name": "s"]),
            fixture.make(fixture.labelledCircle, ["name": "l"]),
            fixture.make(fixture.circle, ["name": "c"]),
        ])
        let harness = try await LanguageHarness.make(
            declarations: Self.labels, expression: "list->collect(e | e.label())", fixture: fixture)
        harness.context.setVariable("list", value: list)
        let result = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        #expect(result.strings == ["shape s", "labelled l", "circle c"])
    }

    @Test("A helper for a class takes precedence over a built-in operation of the same name")
    func helperShadowsBuiltin() async throws {
        let fixture = ShapeFixture()
        let object = fixture.make(fixture.circle, ["name": "c"])
        let result = try await evaluate(
            "obj.size()",
            declarations: "helper context Shapes!Circle def : size() : Integer = 99;",
            objects: ["obj": object], fixture: fixture)
        #expect(result as? Int == 99)
    }

    @Test("A receiver without an applicable helper is an error")
    func noApplicableHelper() async throws {
        let fixture = ShapeFixture()
        let object = fixture.make(fixture.drawing)
        await #expect(throws: ATLExecutionError.self) {
            _ = try await self.evaluate("obj.label()", objects: ["obj": object], fixture: fixture)
        }
    }

    @Test("A later helper for the same context and name replaces the earlier one")
    func parameterCount() async throws {
        let fixture = ShapeFixture()
        let object = fixture.make(fixture.circle, ["name": "c"])
        let declarations = """
            helper context Shapes!Circle def : tag() : String = 'plain';
            helper context Shapes!Circle def : tag(suffix : String) : String = 'tagged ' + suffix;
            """
        // Declared for the same context, so the second replaces the first
        let result = try await evaluate(
            "obj.tag('x')", declarations: declarations, objects: ["obj": object], fixture: fixture)
        #expect(result as? String == "tagged x")
    }

    @Test("Helpers on primitive types dispatch on the value type")
    func primitiveContexts() async throws {
        let declarations = """
            helper context String def : shout() : String = self.toUpper() + '!';
            helper context Integer def : twice() : Integer = self * 2;
            helper context Real def : twice() : Real = self * 2.0;
            helper context Boolean def : flip() : Boolean = not self;
            helper context OclAny def : describe() : String = 'anything';
            helper context Integer def : describe() : String = 'a number';
            """
        #expect(try await evaluate("'hey'.shout()", declarations: declarations) as? String == "HEY!")
        #expect(try await evaluate("21.twice()", declarations: declarations) as? Int == 42)
        #expect(try await evaluate("1.25.twice()", declarations: declarations) as? Double == 2.5)
        #expect(try await evaluate("true.flip()", declarations: declarations) as? Bool == false)
        #expect(try await evaluate("5.describe()", declarations: declarations) as? String == "a number")
        #expect(try await evaluate("'s'.describe()", declarations: declarations) as? String == "anything")
    }

    @Test("Integers use a Real helper when no Integer helper exists")
    func integerUsesRealHelper() async throws {
        let declarations = "helper context Real def : half() : Real = self / 2.0;"
        #expect(try await evaluate("5.half()", declarations: declarations) as? Double == 2.5)
    }

    @Test("A helper on a collection type applies to collections")
    func collectionContext() async throws {
        let declarations = "helper context Sequence(Integer) def : total() : Integer = self->sum();"
        #expect(try await evaluate("Sequence{1, 2, 3}.total()", declarations: declarations) as? Int == 6)
    }

    @Test("An attribute helper on a collection type is evaluated each time it is called")
    func collectionAttributeHelper() async throws {
        let declarations = "helper context Sequence(Integer) def : total : Integer = self->sum();"
        #expect(try await evaluate("Sequence{1, 2}.total()", declarations: declarations) as? Int == 3)
    }

    @Test("Context-free helpers are unaffected by contextual helpers of the same name")
    func globalHelperCoexists() async throws {
        let declarations = """
            helper context Shapes!Circle def : label() : String = 'contextual';
            helper def : label() : String = 'global';
            """
        let fixture = ShapeFixture()
        let object = fixture.make(fixture.circle)
        let global = try await evaluate("thisModule.label()", declarations: declarations)
        #expect(global as? String == "global")
        let contextual = try await evaluate(
            "obj.label()", declarations: declarations, objects: ["obj": object], fixture: fixture)
        #expect(contextual as? String == "contextual")
    }

    @Test("A context-free helper can be called with the receiver bound to self")
    func globalHelperWithReceiver() async throws {
        let declarations = "helper def : doubleIt() : Integer = self * 2;"
        #expect(try await evaluate("5.doubleIt()", declarations: declarations) as? Int == 10)
    }

    @Test("Errors raised by a context-free helper called on a receiver propagate")
    func globalHelperWithReceiverFails() async throws {
        let declarations = "helper def : broken() : Integer = 1 div 0;"
        let harness = try await LanguageHarness.make(
            declarations: declarations, expression: "5.broken()")
        harness.context.debug = true
        await #expect(throws: ATLExecutionError.self) {
            _ = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        }
    }

    @Test("Contextual helper selection is traced when debugging")
    func debugTrace() async throws {
        let fixture = ShapeFixture()
        let harness = try await LanguageHarness.make(
            declarations: "helper context Shapes!Square def : area : Real = 1.0;",
            expression: "obj.area", fixture: fixture)
        harness.context.debug = true
        harness.context.setVariable("obj", value: fixture.make(fixture.square))
        let result = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        #expect(result as? Double == 1.0)
    }

    @Test("Contextual helpers cannot be read as module attributes")
    func contextualAsModuleAttribute() async {
        await #expect(throws: ATLExecutionError.self) {
            _ = try await self.evaluate("thisModule.label")
        }
    }

    @Test("A helper that is not declared is reported as missing")
    func missingModuleAttribute() async {
        await #expect(throws: ATLExecutionError.self) {
            _ = try await self.evaluate("thisModule.nothing")
        }
    }

    // MARK: - Attribute helpers

    @Test("Attribute helpers are navigated like features")
    func attributeNavigation() async throws {
        let fixture = ShapeFixture()
        let object = fixture.make(fixture.square, ["name": "s", "side": 3.0])
        let declarations = "helper context Shapes!Square def : area : Real = self.side * self.side;"
        let result = try await evaluate(
            "obj.area", declarations: declarations, objects: ["obj": object], fixture: fixture)
        #expect(result as? Double == 9.0)
    }

    @Test("Attribute helpers on primitive values are navigated too")
    func primitiveAttribute() async throws {
        let declarations = "helper context String def : twin : String = self + self;"
        #expect(try await evaluate("'ab'.twin", declarations: declarations) as? String == "abab")
    }

    @Test("Attributes are flagged by the absence of a parameter list")
    func attributeFlag() async throws {
        let harness = try await LanguageHarness.make(
            declarations: """
                helper context Shapes!Square def : area : Real = 1.0;
                helper context Shapes!Square def : perimeter() : Real = 2.0;
                """)
        let area = try #require(harness.module.helperOverloads["area"]?.first as? ATLHelperWrapper)
        let perimeter = try #require(harness.module.helperOverloads["perimeter"]?.first as? ATLHelperWrapper)
        #expect(area.isAttribute)
        #expect(!perimeter.isAttribute)
    }

    @Test("Attribute helper values are cached per receiver, operations are not")
    func attributeCaching() async throws {
        let fixture = ShapeFixture()
        let resource = Resource(uri: "test://source")
        let first = fixture.make(fixture.square, ["name": "a"])
        await resource.add(first)
        let declarations = """
            helper context Shapes!Shape def : seen : Integer = Shapes!Shape.allInstances()->size();
            helper context Shapes!Shape def : seenNow() : Integer = Shapes!Shape.allInstances()->size();
            """
        let harness = try await LanguageHarness.make(
            declarations: declarations, expression: "obj.seen", fixture: fixture,
            sources: ["IN": resource])
        harness.context.setVariable("obj", value: first)
        let before = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        #expect(before as? Int == 1)

        let second = fixture.make(fixture.square, ["name": "b"])
        await resource.add(second)

        let cached = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        #expect(cached as? Int == 1)

        let operation = ATLNavigationExpression(
            source: ATLVariableExpression(name: "obj"), property: "seen")
        #expect(try await operation.evaluate(in: harness.context) as? Int == 1)

        let fresh = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "obj"), methodName: "seenNow")
        #expect(try await fresh.evaluate(in: harness.context) as? Int == 2)

        // A different receiver computes its own value
        harness.context.setVariable("other", value: second)
        let other = ATLNavigationExpression(
            source: ATLVariableExpression(name: "other"), property: "seen")
        #expect(try await other.evaluate(in: harness.context) as? Int == 2)

        harness.context.clearAttributeHelperCache()
        #expect(try await operation.evaluate(in: harness.context) as? Int == 2)
    }

    @Test("Context-free attribute helpers are computed once")
    func globalAttributeCaching() async throws {
        let fixture = ShapeFixture()
        let resource = Resource(uri: "test://source")
        await resource.add(fixture.make(fixture.square, ["name": "a"]))
        let declarations = "helper def : count : Integer = Shapes!Shape.allInstances()->size();"
        let harness = try await LanguageHarness.make(
            declarations: declarations, expression: "thisModule.count", fixture: fixture,
            sources: ["IN": resource])
        let before = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        #expect(before as? Int == 1)
        await resource.add(fixture.make(fixture.square, ["name": "b"]))
        let after = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        #expect(after as? Int == 1)
    }

    @Test("Undefined attribute values are cached as undefined")
    func undefinedAttributeIsCached() async throws {
        let fixture = ShapeFixture()
        let object = fixture.make(fixture.square)
        let declarations = "helper context Shapes!Square def : nothing : OclAny = OclUndefined;"
        let result = try await evaluate(
            "obj.nothing", declarations: declarations, objects: ["obj": object], fixture: fixture)
        #expect(result == nil)
    }

    // MARK: - Navigation over collections

    @Test("Navigating a feature over a collection collects the values")
    func implicitCollect() async throws {
        let fixture = ShapeFixture()
        let list = EcoreValueArray([
            fixture.make(fixture.square, ["name": "s"]),
            fixture.make(fixture.circle, ["name": "c"]),
        ])
        let harness = try await LanguageHarness.make(expression: "list.name", fixture: fixture)
        harness.context.setVariable("list", value: list)
        let result = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        #expect(result.strings == ["s", "c"])
    }
}
