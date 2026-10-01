//
//  ATLLiteralTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import ATL

/// Tests for string escapes, real, enumeration and undefined literals, and collection literals.
@Suite("ATL Literal Tests")
@MainActor
struct ATLLiteralTests {

    // MARK: - String escapes

    @Test(
        "String literals decode escape sequences",
        arguments: [
            ("'it\\'s'", "it's"),
            ("'a\\nb'", "a\nb"),
            ("'a\\tb'", "a\tb"),
            ("'back\\\\slash'", "back\\slash"),
            ("'cr\\rlf'", "cr\rlf"),
            ("'say \\\"hi\\\"'", "say \"hi\""),
            ("'\\u0041'", "A"),
            ("'\\101'", "A"),
            ("'\\s+'", "\\s+"),
            ("''", ""),
        ])
    func stringEscapes(literal: String, expected: String) async throws {
        let result = try await LanguageHarness.evaluate(literal)
        #expect(result as? String == expected)
    }

    @Test("An escaped quote does not end a string literal")
    func escapedQuoteContinuesLiteral() async throws {
        let result = try await LanguageHarness.evaluate("'a\\'' + 'b'")
        #expect(result as? String == "a'b")
    }

    @Test("An unterminated string literal is rejected")
    func unterminatedString() async throws {
        await #expect(throws: ATLParseError.self) {
            _ = try await LanguageHarness.evaluate("'abc\\'")
        }
    }

    // MARK: - Real literals

    @Test(
        "Real literals keep their value",
        arguments: [("3.14", 3.14), ("0.5", 0.5), ("10.0", 10.0), ("1e3", 1000.0), ("2.5e-1", 0.25)])
    func realLiterals(literal: String, expected: Double) async throws {
        let result = try await LanguageHarness.evaluate(literal)
        #expect(result as? Double == expected)
    }

    @Test("Integer literals stay integers")
    func integerLiteral() async throws {
        let result = try await LanguageHarness.evaluate("42")
        #expect(result as? Int == 42)
    }

    @Test("A point after an integer without digits is navigation, not a fraction")
    func integerThenMethod() async throws {
        let result = try await LanguageHarness.evaluate("7.mod(4)")
        #expect(result as? Int == 3)
    }

    @Test("Real arithmetic uses the real value")
    func realArithmetic() async throws {
        let result = try await LanguageHarness.evaluate("1.5 + 2.25")
        #expect(result as? Double == 3.75)
    }

    // MARK: - Undefined

    @Test("OclUndefined evaluates to the undefined value", arguments: ["OclUndefined", "null"])
    func undefinedLiteral(literal: String) async throws {
        let result = try await LanguageHarness.evaluate(literal)
        #expect(result == nil)
    }

    @Test("Undefined values can be tested and compared")
    func undefinedComparison() async throws {
        #expect(try await LanguageHarness.evaluate("OclUndefined.oclIsUndefined()") as? Bool == true)
        #expect(try await LanguageHarness.evaluate("OclUndefined = OclUndefined") as? Bool == true)
        #expect(try await LanguageHarness.evaluate("1 = OclUndefined") as? Bool == false)
        #expect(try await LanguageHarness.evaluate("1 <> OclUndefined") as? Bool == true)
    }

    // MARK: - Enumeration literals

    @Test("An enumeration literal evaluates to its name")
    func enumerationLiteral() async throws {
        let result = try await LanguageHarness.evaluate("#Editable")
        #expect(result as? String == "Editable")
    }

    @Test("Enumeration literals compare equal to stored literal names")
    func enumerationLiteralComparison() async throws {
        #expect(try await LanguageHarness.evaluate("#Editable = 'Editable'") as? Bool == true)
        #expect(try await LanguageHarness.evaluate("#Editable = #Readonly") as? Bool == false)
    }

    @Test("A hash without a name is rejected")
    func bareHash() async throws {
        await #expect(throws: ATLParseError.self) {
            _ = try await LanguageHarness.evaluate("# + 1")
        }
    }

    @Test("Enumeration literal expressions are equatable and hashable")
    func enumerationLiteralEquality() {
        let a = ATLEnumLiteralExpression(name: "A")
        #expect(a == ATLEnumLiteralExpression(name: "A"))
        #expect(a != ATLEnumLiteralExpression(name: "B"))
        #expect(a.hashValue == ATLEnumLiteralExpression(name: "A").hashValue)
        #expect(areATLExpressionsEqual(a, ATLEnumLiteralExpression(name: "A")))
    }

    // MARK: - Collection literals

    @Test("Sequence literals keep the element values and their order")
    func sequenceLiteral() async throws {
        let result = try await LanguageHarness.evaluate("Sequence{3, 1, 2, 1}")
        #expect(result is EcoreValueArray)
        #expect(result.integers == [3, 1, 2, 1])
    }

    @Test("Set literals remove duplicates and keep first-occurrence order")
    func setLiteral() async throws {
        let result = try await LanguageHarness.evaluate("Set{3, 1, 3, 2}")
        let set = try #require(result as? ATLCollectionValue)
        #expect(set.kind == .set)
        #expect(result.integers == [3, 1, 2])
    }

    @Test("OrderedSet literals are recognised and ordered")
    func orderedSetLiteral() async throws {
        let result = try await LanguageHarness.evaluate("OrderedSet{'b', 'a', 'b'}")
        let set = try #require(result as? ATLCollectionValue)
        #expect(set.kind == .orderedSet)
        #expect(result.strings == ["b", "a"])
    }

    @Test("Empty OrderedSet and Bag literals parse")
    func emptyLiterals() async throws {
        #expect(try await LanguageHarness.evaluate("OrderedSet{}").collectionElements?.isEmpty == true)
        #expect(try await LanguageHarness.evaluate("Bag{}").collectionElements?.isEmpty == true)
    }

    @Test("Bag literals keep duplicates")
    func bagLiteral() async throws {
        #expect(try await LanguageHarness.evaluate("Bag{1, 1, 2}").integers == [1, 1, 2])
    }

    @Test("Collection literals hold objects, not their descriptions")
    func literalHoldsObjects() async throws {
        let fixture = ShapeFixture()
        let circle = fixture.make(fixture.circle, ["name": "c"])
        let harness = try await LanguageHarness.make(
            expression: "Sequence{self_, self_}", fixture: fixture)
        harness.context.setVariable("self_", value: circle)
        let result = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        let elements = try #require(result.collectionElements)
        #expect(elements.count == 2)
        #expect((elements[0] as? any EObject)?.id == circle.id)
    }

    @Test("Nested collection literals are not flattened")
    func nestedLiterals() async throws {
        let result = try await LanguageHarness.evaluate("Sequence{Sequence{1, 2}, Sequence{3}}")
        #expect(result.collectionElements?.count == 2)
        let flat = try await LanguageHarness.evaluate("Sequence{Sequence{1, 2}, Sequence{3}}->flatten()")
        #expect(flat.integers == [1, 2, 3])
    }

    @Test("Set equality ignores order, sequence equality does not")
    func collectionEquality() async throws {
        #expect(try await LanguageHarness.evaluate("Set{1, 2} = Set{2, 1}") as? Bool == true)
        #expect(try await LanguageHarness.evaluate("Sequence{1, 2} = Sequence{2, 1}") as? Bool == false)
        #expect(try await LanguageHarness.evaluate("Sequence{1, 2} = Sequence{1, 2}") as? Bool == true)
    }

    @Test("Unknown collection kinds are rejected")
    func unknownCollectionKind() async throws {
        let literal = ATLCollectionLiteralExpression(collectionType: "Heap", elements: [])
        let harness = try await LanguageHarness.make()
        await #expect(throws: ATLExecutionError.self) {
            _ = try await literal.evaluate(in: harness.context)
        }
    }
}
