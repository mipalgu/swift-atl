//
//  ATLCollectionHelperDispatchTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 7/11/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import ATL

/// Tests for helpers declared on collection types and called on collection receivers.
///
/// ATL selects the helper whose context type is closest to the type of the
/// receiver, so a helper declared for a collection type applies to the collection
/// itself rather than to each of its elements. Navigating a feature over a
/// collection collects the feature over the elements only when no helper applies
/// to the collection.
@Suite("ATL Collection Helper Dispatch Tests")
@MainActor
struct ATLCollectionHelperDispatchTests {

    /// Evaluates an expression with a list of shapes bound to `list`.
    ///
    /// - Parameters:
    ///   - expression: The expression to evaluate.
    ///   - declarations: The helper declarations of the module.
    /// - Returns: The value of the expression.
    private func evaluateOverShapes(_ expression: String, declarations: String) async throws
        -> (any EcoreValue)?
    {
        let fixture = ShapeFixture()
        let list = EcoreValueArray([
            fixture.make(fixture.square, ["name": "s"]),
            fixture.make(fixture.circle, ["name": "c"]),
        ])
        let harness = try await LanguageHarness.make(
            declarations: declarations, expression: expression, fixture: fixture)
        harness.context.setVariable("list", value: list)
        return try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
    }

    /// Evaluates an expression that does not depend on model elements.
    ///
    /// - Parameters:
    ///   - expression: The expression to evaluate.
    ///   - declarations: The helper declarations of the module.
    /// - Returns: The value of the expression.
    private func evaluate(_ expression: String, declarations: String) async throws -> (any EcoreValue)? {
        try await LanguageHarness.evaluate(expression, declarations: declarations)
    }

    // MARK: - Attribute helpers

    @Test("An attribute helper on a sequence of model elements applies to the sequence")
    func sequenceAttributeHelper() async throws {
        let declarations = """
            helper context Sequence(Shapes!Shape) def : names : Sequence(String) =
                self->collect(s | s.name);
            """
        let result = try await evaluateOverShapes("list.names", declarations: declarations)
        #expect(result.strings == ["s", "c"])
    }

    @Test("A collection attribute helper takes precedence over a feature of the elements")
    func collectionHelperShadowsElementFeature() async throws {
        let declarations = "helper context Sequence(Shapes!Shape) def : name : String = 'whole';"
        let result = try await evaluateOverShapes("list.name", declarations: declarations)
        #expect(result as? String == "whole")
    }

    @Test("A collection attribute helper takes precedence over an element helper of the same name")
    func collectionHelperShadowsElementHelper() async throws {
        let declarations = """
            helper context Shapes!Shape def : tag : String = 'element ' + self.name;
            helper context Sequence(Shapes!Shape) def : tag : String = 'sequence';
            """
        let result = try await evaluateOverShapes("list.tag", declarations: declarations)
        #expect(result as? String == "sequence")
    }

    @Test(
        "Attribute helpers apply to receivers of their own collection kind",
        arguments: [
            ("Set(String)", "Set{'a', 'a', 'b'}"),
            ("OrderedSet(String)", "OrderedSet{'a', 'b', 'a'}"),
            ("Sequence(String)", "Sequence{'a', 'b'}"),
        ])
    func kindSpecificAttribute(context: String, receiver: String) async throws {
        let declarations = "helper context \(context) def : count : Integer = self->size();"
        #expect(try await evaluate("\(receiver).count", declarations: declarations) as? Int == 2)
    }

    @Test(
        "A Collection attribute helper applies to every collection kind",
        arguments: ["Sequence{'a', 'b'}", "Set{'a', 'b'}", "OrderedSet{'a', 'b'}", "Bag{'a', 'b'}"])
    func collectionAttribute(receiver: String) async throws {
        let declarations = "helper context Collection(String) def : count : Integer = self->size();"
        #expect(try await evaluate("\(receiver).count", declarations: declarations) as? Int == 2)
    }

    @Test(
        "The most specific collection context wins for attribute helpers",
        arguments: [("Set{'a'}", "set"), ("Sequence{'a'}", "collection")])
    func mostSpecificCollectionAttribute(receiver: String, expected: String) async throws {
        let declarations = """
            helper context Collection(String) def : kind : String = 'collection';
            helper context Set(String) def : kind : String = 'set';
            """
        #expect(try await evaluate("\(receiver).kind", declarations: declarations) as? String == expected)
    }

    @Test("An OclAny attribute helper applies to a collection receiver as a whole")
    func oclAnyAttributeOnCollection() async throws {
        let declarations = "helper context OclAny def : tag : String = 'any';"
        let result = try await evaluateOverShapes("list.tag", declarations: declarations)
        #expect(result as? String == "any")
    }

    @Test("A collection attribute helper is navigated from a collection-valued expression")
    func attributeOnNavigatedCollection() async throws {
        let fixture = ShapeFixture()
        var drawing = fixture.make(fixture.drawing)
        drawing.eSet(
            "shapes",
            value: EcoreValueArray([
                fixture.make(fixture.square, ["name": "s"]),
                fixture.make(fixture.circle, ["name": "c"]),
            ]))
        let declarations = """
            helper context Sequence(Shapes!Shape) def : names : String =
                self->iterate(s; acc : String = '' | acc + s.name);
            """
        let harness = try await LanguageHarness.make(
            declarations: declarations, expression: "drawing.shapes.names", fixture: fixture)
        harness.context.setVariable("drawing", value: drawing)
        let result = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        #expect(result as? String == "sc")
    }

    // MARK: - Operation helpers

    private static let joined = """
        helper context Sequence(String) def : joined() : String =
            self->iterate(s; acc : String = '' | acc + s);
        """

    @Test(
        "An operation helper on a collection is called with either call operator",
        arguments: ["Sequence{'a', 'b'}.joined()", "Sequence{'a', 'b'}->joined()"])
    func collectionOperation(expression: String) async throws {
        #expect(try await evaluate(expression, declarations: Self.joined) as? String == "ab")
    }

    @Test(
        "Operation helpers apply to receivers of their own collection kind",
        arguments: [
            ("Set(String)", "Set{'a', 'a', 'b'}"),
            ("OrderedSet(String)", "OrderedSet{'a', 'b', 'a'}"),
            ("Collection(String)", "Set{'a', 'b'}"),
            ("Collection(String)", "Bag{'a', 'b'}"),
        ])
    func kindSpecificOperation(context: String, receiver: String) async throws {
        let declarations = "helper context \(context) def : count() : Integer = self->size();"
        #expect(try await evaluate("\(receiver)->count()", declarations: declarations) as? Int == 2)
        #expect(try await evaluate("\(receiver).count()", declarations: declarations) as? Int == 2)
    }

    @Test("A collection operation helper takes precedence over a built-in operation")
    func collectionOperationShadowsBuiltin() async throws {
        let declarations = "helper context Sequence(String) def : size() : Integer = 99;"
        #expect(try await evaluate("Sequence{'a'}->size()", declarations: declarations) as? Int == 99)
        #expect(try await evaluate("Set{'a'}->size()", declarations: declarations) as? Int == 1)
    }

    // MARK: - Bag helpers

    /// Evaluates an expression with the standard options, in which Bags are distinct from Sequences.
    ///
    /// - Parameters:
    ///   - expression: The expression to evaluate.
    ///   - declarations: The helper declarations of the module.
    /// - Returns: The value of the expression.
    private func evaluateStandard(_ expression: String, declarations: String) async throws
        -> (any EcoreValue)?
    {
        try await LanguageHarness.evaluate(expression, declarations: declarations, options: .standard)
    }

    @Test(
        "An attribute helper on a Bag applies to Bag receivers",
        arguments: ["Bag{'a', 'a'}", "Sequence{'a', 'a'}->asBag()", "Set{'a', 'b'}->collect(s | s)"])
    func bagAttribute(receiver: String) async throws {
        let declarations = "helper context Bag(String) def : count : Integer = self->size();"
        #expect(try await evaluateStandard("\(receiver).count", declarations: declarations) as? Int == 2)
    }

    @Test("An operation helper on a Bag is called with either call operator")
    func bagOperation() async throws {
        let declarations = "helper context Bag(String) def : count() : Integer = self->size();"
        #expect(try await evaluateStandard("Bag{'a', 'a'}->count()", declarations: declarations) as? Int == 2)
        #expect(try await evaluateStandard("Bag{'a', 'a'}.count()", declarations: declarations) as? Int == 2)
    }

    @Test(
        "A Bag receiver prefers a Bag helper, then a Collection helper, then an OclAny helper",
        arguments: [
            (["Bag", "Collection", "OclAny"], "Bag"),
            (["Collection", "OclAny"], "Collection"),
            (["OclAny"], "OclAny"),
        ])
    func bagPrecedence(contexts: [String], expected: String) async throws {
        let declarations = contexts.map { context in
            let type = context == "OclAny" ? context : "\(context)(String)"
            return """
                helper context \(type) def : kind : String = '\(context)';
                helper context \(type) def : kindOf() : String = '\(context)';
                """
        }.joined(separator: "\n")
        #expect(try await evaluateStandard("Bag{'a'}.kind", declarations: declarations) as? String == expected)
        #expect(try await evaluateStandard("Bag{'a'}->kindOf()", declarations: declarations) as? String == expected)
        #expect(try await evaluateStandard("Bag{'a'}.kindOf()", declarations: declarations) as? String == expected)
    }

    @Test("A Sequence helper does not apply to a Bag, and a Bag helper not to a Sequence")
    func bagAndSequenceHelpersAreDistinct() async throws {
        let sequenceHelper = "helper context Sequence(String) def : size() : Integer = 99;"
        #expect(try await evaluateStandard("Bag{'a'}->size()", declarations: sequenceHelper) as? Int == 1)
        #expect(try await evaluateStandard("Sequence{'a'}->size()", declarations: sequenceHelper) as? Int == 99)
        let bagHelper = "helper context Bag(String) def : size() : Integer = 42;"
        #expect(try await evaluateStandard("Bag{'a'}->size()", declarations: bagHelper) as? Int == 42)
        #expect(try await evaluateStandard("Sequence{'a'}->size()", declarations: bagHelper) as? Int == 1)
        #expect(try await evaluateStandard("Set{'a'}->size()", declarations: bagHelper) as? Int == 1)
    }

    @Test("A Bag attribute helper takes precedence over collection over the elements")
    func bagAttributeShadowsElementFeature() async throws {
        let fixture = ShapeFixture()
        let bag = EcoreValueArray(
            [
                fixture.make(fixture.square, ["name": "s"]),
                fixture.make(fixture.circle, ["name": "c"]),
            ], kind: .bag)
        let declarations = "helper context Bag(Shapes!Shape) def : name : String = 'bag';"
        let harness = try await LanguageHarness.make(
            declarations: declarations, expression: "list.name", fixture: fixture, options: .standard)
        harness.context.setVariable("list", value: bag)
        let result = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        #expect(result as? String == "bag")
    }

    @Test("A Sequence attribute helper does not stop collection over the elements of a Bag")
    func sequenceHelperIgnoredForBag() async throws {
        let fixture = ShapeFixture()
        let bag = EcoreValueArray(
            [
                fixture.make(fixture.square, ["name": "s"]),
                fixture.make(fixture.circle, ["name": "c"]),
            ], kind: .bag)
        let declarations = "helper context Sequence(Shapes!Shape) def : name : String = 'sequence';"
        let harness = try await LanguageHarness.make(
            declarations: declarations, expression: "list.name", fixture: fixture, options: .standard)
        harness.context.setVariable("list", value: bag)
        let result = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        #expect(result.strings == ["s", "c"])
    }

    // MARK: - Implicit collection over elements

    @Test("An element attribute helper is collected over a collection without a collection helper")
    func elementAttributeIsCollected() async throws {
        let declarations = "helper context Shapes!Shape def : tag : String = 'element ' + self.name;"
        let result = try await evaluateOverShapes("list.tag", declarations: declarations)
        #expect(result.strings == ["element s", "element c"])
    }

    @Test("A helper for another collection kind does not stop collection over the elements")
    func otherKindHelperIsIgnored() async throws {
        let declarations = "helper context Set(Shapes!Shape) def : name : String = 'set';"
        let result = try await evaluateOverShapes("list.name", declarations: declarations)
        #expect(result.strings == ["s", "c"])
    }

    @Test("A model feature is still collected over a collection without any helper")
    func featureIsCollected() async throws {
        let result = try await evaluateOverShapes("list.name", declarations: "")
        #expect(result.strings == ["s", "c"])
    }
}
