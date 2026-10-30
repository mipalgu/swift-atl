//
//  ATLCollectionRangeTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 30/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ATL

// MARK: - Lexing

/// Tests for the lexing of collection ranges such as `1..3`.
@Suite("ATL Collection Range Lexing")
struct ATLCollectionRangeLexingTests {

    /// The token types of a source text, without the end of input.
    private func types(_ source: String) throws -> [ATLTokenType] {
        try ATLLexer(content: source).tokenize().map(\.type).filter { $0 != .eof }
    }

    @Test("Two integers joined by '..' are lexed as a range, not as reals")
    func integerRange() throws {
        #expect(try types("1..3") == [.integerLiteral(1), .operator(".."), .integerLiteral(3)])
        #expect(try types("1 .. 3") == [.integerLiteral(1), .operator(".."), .integerLiteral(3)])
    }

    @Test("A real literal before or after '..' keeps its fraction")
    func realBounds() throws {
        #expect(try types("1.5..3") == [.realLiteral(1.5), .operator(".."), .integerLiteral(3)])
        #expect(try types("1..2.5") == [.integerLiteral(1), .operator(".."), .realLiteral(2.5)])
    }

    @Test("Real literals and navigation are unchanged")
    func unchanged() throws {
        #expect(try types("1.5") == [.realLiteral(1.5)])
        #expect(try types("3.size") == [.integerLiteral(3), .operator("."), .identifier("size")])
        #expect(try types("a.b") == [.identifier("a"), .operator("."), .identifier("b")])
    }

    @Test("Identifiers may be range bounds")
    func identifierBounds() throws {
        #expect(try types("a..b") == [.identifier("a"), .operator(".."), .identifier("b")])
    }
}

// MARK: - Parsing

/// Tests for parsing collection literals that hold ranges.
@Suite("ATL Collection Range Parsing")
struct ATLCollectionRangeParsingTests {

    /// Parses a query unit and returns its body.
    private func body(_ expression: String) async throws -> any ATLExpression {
        let unit = try await ATLParser(options: .standard).parseContent("query Q = \(expression);")
        return try #require(unit.queryBody)
    }

    /// The message of a parse error, or `nil` when the error is not a parse error.
    private func message(_ error: any Error) -> String? {
        (error as? ATLParseError)?.diagnosticMessage
    }

    @Test(
        "Every collection kind accepts a range",
        arguments: ATLCollectionKind.allCases)
    func everyKind(kind: ATLCollectionKind) async throws {
        let literal = try #require(
            try await body("\(kind.rawValue){1..3}") as? ATLCollectionLiteralExpression)
        #expect(literal.collectionType == kind.rawValue)
        #expect(literal.elements.count == 1)
        let range = try #require(literal.elements.first as? ATLCollectionRangeExpression)
        #expect((range.first as? ATLLiteralExpression)?.value as? Int == 1)
        #expect((range.last as? ATLLiteralExpression)?.value as? Int == 3)
    }

    @Test("Ranges mix with ordinary items")
    func mixedParts() async throws {
        let literal = try #require(
            try await body("Sequence{0, 2..4, 9}") as? ATLCollectionLiteralExpression)
        #expect(literal.elements.count == 3)
        #expect(literal.elements[0] is ATLLiteralExpression)
        #expect(literal.elements[1] is ATLCollectionRangeExpression)
        #expect(literal.elements[2] is ATLLiteralExpression)
    }

    @Test("Range bounds may be arbitrary expressions")
    func expressionBounds() async throws {
        let literal = try #require(
            try await body("Sequence{1 + 1..thisModule.n * 2}") as? ATLCollectionLiteralExpression)
        let range = try #require(literal.elements.first as? ATLCollectionRangeExpression)
        #expect(range.first is ATLBinaryExpression)
        #expect(range.last is ATLBinaryExpression)
    }

    @Test("A range records the source text it was parsed from")
    func origin() async throws {
        let source = "query Q = Sequence{0, 2..4};"
        let unit = try await ATLParser(options: .standard).parseContent(source)
        let literal = try #require(unit.queryBody as? ATLCollectionLiteralExpression)
        let range = try #require(literal.elements.last as? ATLCollectionRangeExpression)
        #expect(ATLDiagnosingParserTests.slice(range.origin.range, of: source) == "2..4")
    }

    @Test("Ranges that differ in a bound are not equal")
    func equality() async throws {
        let one = try await body("Sequence{1..3}")
        let same = try await body("Sequence{1..3}")
        let item = try await body("Sequence{1, 3}")
        #expect(areATLExpressionsEqual(one, same))
        #expect(!areATLExpressionsEqual(one, item))
        let range = ATLCollectionRangeExpression(
            first: ATLLiteralExpression(value: 1), last: ATLLiteralExpression(value: 3))
        let other = ATLCollectionRangeExpression(
            first: ATLLiteralExpression(value: 1), last: ATLLiteralExpression(value: 4))
        #expect(range == range)
        #expect(range != other)
        #expect(range.hashValue == range.hashValue)
    }

    @Test(
        "A malformed range is reported with an informative message",
        arguments: [
            ("Sequence{1..}", "last value of the range"),
            ("Sequence{1.., 2}", "last value of the range"),
            ("Sequence{..3}", "first value of the range"),
            ("Sequence{1..2..3}", "only one '..'"),
            ("1..3", "inside a collection literal"),
        ])
    func malformed(expression: String, expected: String) async throws {
        do {
            _ = try await body(expression)
            Issue.record("'\(expression)' should not parse")
        } catch {
            let text = try #require(message(error))
            #expect(text.contains(expected), "\(text)")
            #expect(text.contains("line 1"), "\(text)")
        }
    }

    @Test("A parse error describes itself instead of naming its case number")
    func localisedDescription() async throws {
        do {
            _ = try await body("Sequence{1..}")
            Issue.record("The range should not parse")
        } catch {
            #expect(error.localizedDescription.contains("last value of the range"))
            #expect(!error.localizedDescription.contains("error 0"))
        }
    }

    @Test("Diagnosing a malformed range points at the offending token")
    func diagnosing() async throws {
        let source = "query Q = Sequence{1..};"
        let result = await ATLParser(options: .standard).parseDiagnosing(source, name: "Q.atl")
        let diagnostic = try #require(result.diagnostics.first)
        #expect(diagnostic.message.contains("last value of the range"))
        #expect(ATLDiagnosingParserTests.slice(diagnostic.range, of: source) == "}")
    }
}

// MARK: - Evaluation

/// Tests for evaluating collection literals that hold ranges.
@Suite("ATL Collection Range Evaluation")
@MainActor
struct ATLCollectionRangeEvaluationTests {

    @Test(
        "Ranges expand to the integers they span",
        arguments: [
            ("Sequence{1..3}", [1, 2, 3]),
            ("Sequence{0, 2..4, 9}", [0, 2, 3, 4, 9]),
            ("Sequence{1..1}", [1]),
            ("Sequence{3..1}", []),
            ("Sequence{-2..1}", [-2, -1, 0, 1]),
            ("Sequence{1 + 1..2 * 3}", [2, 3, 4, 5, 6]),
            ("Sequence{1..3, 2..3}", [1, 2, 3, 2, 3]),
            ("Bag{1..3, 2..3}", [1, 2, 3, 2, 3]),
            ("Set{1..3, 2..4}", [1, 2, 3, 4]),
            ("OrderedSet{3, 1..4}", [3, 1, 2, 4]),
            ("OrderedSet{5..2}", []),
            ("Sequence{1..3}->collect(e | e * e)", [1, 4, 9]),
            ("let n : Integer = 4 in Sequence{n - 1..n}", [3, 4]),
        ])
    func expansion(expression: String, expected: [Int]) async throws {
        let value = try await LanguageHarness.evaluate(expression, options: .standard)
        #expect(value.integers == expected)
        #expect(value.collectionElements?.count == expected.count)
    }

    @Test(
        "A range literal has the kind it is written with",
        arguments: ATLCollectionKind.allCases)
    func kinds(kind: ATLCollectionKind) async throws {
        let value = try await LanguageHarness.evaluate("\(kind.rawValue){1..2}", options: .standard)
        #expect(value.integers == [1, 2])
        if kind.isUnique {
            #expect((value as? ATLCollectionValue)?.kind == kind)
        } else {
            #expect(value is EcoreValueArray)
        }
    }

    @Test("A range matches the equivalent includingRange operation")
    func matchesIncludingRange() async throws {
        let value = try await LanguageHarness.evaluate(
            "Sequence{0, 2..4} = Sequence{0}->includingRange(2, 4)", options: .standard)
        #expect(value as? Bool == true)
    }

    @Test(
        "A bound that is not an Integer is a type error",
        arguments: [
            "Sequence{1.5..3}",
            "Sequence{1..3.0}",
            "Set{'a'..'c'}",
            "Sequence{true..false}",
            "Bag{1..OclUndefined}",
            "OrderedSet{OclUndefined..2}",
        ])
    func nonIntegerBounds(expression: String) async {
        do {
            _ = try await LanguageHarness.evaluate(expression, options: .standard)
            Issue.record("'\(expression)' should not evaluate")
        } catch ATLExecutionError.typeError(let message) {
            #expect(message.contains("Integer"), "\(message)")
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test("A range longer than the range limit is reported instead of built")
    func tooLong() async {
        await #expect(throws: ATLExecutionError.self) {
            _ = try await LanguageHarness.evaluate(
                "Sequence{1..\(ATLBuiltinOperations.maximumRangeLength + 1)}", options: .standard)
        }
        await #expect(throws: ATLExecutionError.self) {
            _ = try await LanguageHarness.evaluate(
                "Sequence{-9223372036854775807..9223372036854775807}", options: .standard)
        }
    }

    @Test("A range on its own evaluates to the sequence of its integers")
    func standalone() async throws {
        let range = ATLCollectionRangeExpression(
            first: ATLLiteralExpression(value: 2), last: ATLLiteralExpression(value: 4))
        let harness = try await LanguageHarness.make()
        let value = try await range.evaluate(in: harness.context)
        #expect(value.integers == [2, 3, 4])
    }

    @Test("A helper may build a range from its parameters")
    func helper() async throws {
        let value = try await LanguageHarness.evaluate(
            "thisModule.upTo(4)->sum()",
            declarations: "helper def : upTo(n : Integer) : Sequence(Integer) = Sequence{1..n};",
            options: .standard)
        #expect(value as? Int == 10)
    }

    @Test("A rule may use a range in its filter and bindings")
    func rule() async throws {
        let fixture = ShapeFixture()
        let source = """
            module Count;
            create OUT : Shapes from IN : Shapes;
            rule Circle2Circle {
                from s : Shapes!Circle (Sequence{1..3}->includes(s.name.size()))
                to t : Shapes!Circle ( name <- s.name + Sequence{1..s.name.size()}->size().toString() )
            }
            """
        let registry = ATLMetamodelRegistry(packages: [fixture.package])
        let module = try await ATLParser(options: .standard).parseContent(source, metamodelRegistry: registry)

        let input = Resource(uri: "test://in")
        await input.add(fixture.make(fixture.circle, ["name": "ab"]))
        await input.add(fixture.make(fixture.circle, ["name": "long"]))
        let output = Resource(uri: "test://out")
        try await ATLVirtualMachine(module: module).execute(
            sources: ["IN": input], targets: ["OUT": output])

        let created = await output.getAllInstancesOf(fixture.circle)
        #expect(created.count == 1)
        #expect((created.first as? DynamicEObject)?.eGet("name") as? String == "ab2")
    }
}

// MARK: - Queries

/// Tests for collection ranges in query units.
@Suite("ATL Collection Range Queries")
@MainActor
struct ATLCollectionRangeQueryTests {

    /// Evaluates a query without input models.
    private func evaluate(_ source: String) async throws -> (any EcoreValue)? {
        let unit = try await ATLParser(options: .standard).parseContent(source)
        return try await ATLVirtualMachine(module: unit).evaluateQuery(sources: [:])
    }

    @Test("A query evaluates a range literal")
    func query() async throws {
        #expect(try await evaluate("query Q = Sequence{1..3}->size();") as? Int == 3)
        #expect(try await evaluate("query Q = Set{1..3, 2..5}->size();") as? Int == 5)
        #expect(try await evaluate("query Q = Sequence{5..1}->isEmpty();") as? Bool == true)
    }

    @Test("A query helper may return a range literal")
    func queryHelper() async throws {
        let value = try await evaluate(
            """
            query Q = thisModule.squares(3);
            helper def : squares(n : Integer) : Sequence(Integer) =
                Sequence{1..n}->collect(i | i * i);
            """)
        #expect(value.integers == [1, 4, 9])
    }
}

// MARK: - XMI Round Trip

/// Tests for writing collection ranges to XMI and reading them back.
@Suite("ATL Collection Range Round Trip")
@MainActor
struct ATLCollectionRangeRoundTripTests {

    /// Wraps an expression in an XMI document.
    private func wrap(_ expressionXMI: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <root xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
              xmlns:ocl="http://www.eclipse.org/ocl/1.1.0/Ecore"
              xmlns:atl="http://www.eclipse.org/gmt/2005/ATL">
        \(expressionXMI)</root>
        """
    }

    @Test(
        "A collection literal with ranges survives a round trip",
        arguments: ATLCollectionKind.allCases)
    func roundTrip(kind: ATLCollectionKind) async throws {
        let unit = try await ATLParser(options: .standard).parseContent(
            "query Q = \(kind.rawValue){0, 2..thisModule.n + 1, 9};")
        let original = try #require(unit.queryBody as? ATLCollectionLiteralExpression)

        let xmi = ATLExpressionXMISerializer().serialize(original)
        let parsed = try ATLExpressionXMIParser().parse(wrap(xmi))

        let literal = try #require(parsed as? ATLCollectionLiteralExpression)
        #expect(literal.collectionType == kind.rawValue)
        #expect(literal.elements.count == 3)
        let range = try #require(literal.elements[1] as? ATLCollectionRangeExpression)
        #expect((range.first as? ATLLiteralExpression)?.value as? Int == 2)
        #expect(range.last is ATLBinaryExpression)
        #expect(areATLExpressionsEqual(literal, original))
    }

    @Test("A range read back from XMI evaluates like the original")
    func evaluation() async throws {
        let original = ATLCollectionLiteralExpression(
            collectionType: ATLCollectionKind.sequence.rawValue,
            elements: [
                ATLLiteralExpression(value: 0),
                ATLCollectionRangeExpression(
                    first: ATLLiteralExpression(value: 2), last: ATLLiteralExpression(value: 4)),
            ])
        let parsed = try ATLExpressionXMIParser().parse(
            wrap(ATLExpressionXMISerializer().serialize(original)))
        let harness = try await LanguageHarness.make()
        let value = try await parsed.evaluate(in: harness.context)
        #expect(value.integers == [0, 2, 3, 4])
    }

    @Test("A range in XMI without a bound is reported")
    func missingBound() {
        let xmi = """
            <expression xsi:type="ocl:CollectionLiteralExp" kind="Sequence">
              <parts>
                <expression xsi:type="ocl:CollectionRange">
                  <first><expression xsi:type="ocl:IntegerExp" integerSymbol="1"/></first>
                </expression>
              </parts>
            </expression>
            """
        #expect(throws: ExpressionParseError.self) {
            _ = try ATLExpressionXMIParser().parse(wrap(xmi))
        }
    }
}
