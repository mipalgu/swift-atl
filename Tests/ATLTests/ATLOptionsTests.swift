//
//  ATLOptionsTests.swift
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

// MARK: - Options

/// Tests for the values and presets of ``ATLOptions``.
@Suite("ATL Options")
struct ATLOptionsValueTests {

    @Test("The default options are the standard preset and accept OCL collection ranges")
    func standard() {
        #expect(ATLOptions() == .standard)
        #expect(ATLOptions.standard.collectionRangeSyntax == .ocl)
        #expect(ATLOptions.standard.collectionRangeEncoding == .collectionRange)
    }

    @Test("The legacy preset rejects collection ranges as swift-atl 0.6 does")
    func legacy() {
        #expect(ATLOptions.legacy.collectionRangeSyntax == .eclipse)
        #expect(ATLOptions.legacy.collectionRangeEncoding == .collectionRange)
        #expect(ATLOptions.legacy != .standard)
    }

    @Test("Each option has two cases whose raw values are their command line spellings")
    func spellings() {
        #expect(ATLCollectionRangeSyntax.allCases.map(\.rawValue) == ["ocl", "eclipse"])
        #expect(
            ATLCollectionRangeEncoding.allCases.map(\.rawValue) == ["collection-range", "portable"])
        #expect(ATLCollectionRangeSyntax(rawValue: "eclipse") == .eclipse)
        #expect(ATLCollectionRangeEncoding(rawValue: "portable") == .portable)
    }

    @Test("Options can be changed one property at a time")
    func mutation() {
        var options = ATLOptions.standard
        options.collectionRangeEncoding = .portable
        #expect(options.collectionRangeSyntax == .ocl)
        #expect(options.collectionRangeEncoding == .portable)
        let eclipse = ATLOptions(collectionRangeSyntax: .eclipse, collectionRangeEncoding: .portable)
        #expect(eclipse.collectionRangeSyntax == .eclipse)
        #expect(eclipse.collectionRangeEncoding == .portable)
    }
}

// MARK: - Collection range syntax

/// Tests for parsing collection ranges with each ``ATLCollectionRangeSyntax``.
@Suite("ATL Collection Range Syntax Option")
struct ATLCollectionRangeSyntaxTests {

    /// Options that accept OCL ranges.
    private static let ocl = ATLOptions(collectionRangeSyntax: .ocl)

    /// Options that reject ranges as Eclipse ATL does.
    private static let eclipse = ATLOptions(collectionRangeSyntax: .eclipse)

    /// The message of a parse error that reports an unsupported range.
    private func rejection(
        _ source: String, parser: ATLParser
    ) async throws -> ATLParseError {
        do {
            _ = try await parser.parseContent(source)
        } catch let error as ATLParseError {
            return error
        }
        Issue.record("'\(source)' should not parse")
        throw ATLParseError.missingModule
    }

    /// Checks that a parse error is the report of an Eclipse ATL range.
    private func expectEclipseRangeError(_ error: ATLParseError) {
        guard case .invalidSyntax(let message) = error else {
            Issue.record("Unexpected error \(error)")
            return
        }
        #expect(message.contains("Eclipse ATL"), "\(message)")
        #expect(message.contains("includingRange"), "\(message)")
        #expect(message.contains("Sequence{1, 2, 3}"), "\(message)")
        #expect(message.contains("line 1"), "\(message)")
        #expect(error.localizedDescription == message)
    }

    @Test("The parser keeps the options it was created with")
    func parserOptions() {
        #expect(ATLParser(options: Self.eclipse).options == Self.eclipse)
        #expect(ATLParser(options: .standard, enableDebugging: true).options == .standard)
    }

    @Test("OCL syntax accepts a range in every collection kind", arguments: ATLCollectionKind.allCases)
    func oclAccepts(kind: ATLCollectionKind) async throws {
        let unit = try await ATLParser(options: Self.ocl).parseContent(
            "query Q = \(kind.rawValue){0, 2..4};")
        let literal = try #require(unit.queryBody as? ATLCollectionLiteralExpression)
        #expect(literal.elements.last is ATLCollectionRangeExpression)
    }

    @Test(
        "Eclipse syntax rejects a range with a message naming the portable alternative",
        arguments: [
            "query Q = Sequence{1..3};",
            "query Q = Set{0, 2..n};",
            "query Q = Bag{a.b..c};",
            "query Q = OrderedSet{1..};",
            "query Q = 1..3;",
        ])
    func eclipseRejects(source: String) async throws {
        let error = try await rejection(source, parser: ATLParser(options: Self.eclipse))
        expectEclipseRangeError(error)
    }

    @Test("The 0.6 parser rejects ranges like Eclipse syntax")
    func legacyRejects() async throws {
        let error = try await rejection("query Q = Sequence{1..3};", parser: ATLParser())
        expectEclipseRangeError(error)
        let unit = try await ATLParser(options: .legacy).parseContent("query Q = Sequence{1, 2};")
        #expect(unit.queryBody is ATLCollectionLiteralExpression)
    }

    @Test(
        "Eclipse syntax leaves reals and navigation unchanged",
        arguments: ["query Q = 1.5;", "query Q = 3.toString();", "query Q = Sequence{1.5, 2}->size();"])
    func eclipseUnchanged(source: String) async throws {
        let eclipse = try await ATLParser(options: Self.eclipse).parseContent(source)
        let ocl = try await ATLParser(options: Self.ocl).parseContent(source)
        let body = try #require(eclipse.queryBody)
        #expect(areATLExpressionsEqual(body, try #require(ocl.queryBody)))
    }

    @Test("Diagnosing with Eclipse syntax reports the range at its separator")
    func eclipseDiagnosing() async throws {
        let source = "query Q = Sequence{1..3};"
        let result = await ATLParser(options: Self.eclipse).parseDiagnosing(source, name: "Q.atl")
        let diagnostic = try #require(result.diagnostics.first)
        #expect(diagnostic.code == ATLDiagnosticCode.invalidSyntax.rawValue)
        #expect(diagnostic.message.contains("Eclipse ATL"))
        #expect(ATLDiagnosingParserTests.slice(diagnostic.range, of: source) == "..")
    }

    @Test("Diagnosing with OCL syntax accepts the range")
    func oclDiagnosing() async throws {
        let result = await ATLParser(options: Self.ocl).parseDiagnosing(
            "query Q = Sequence{1..3};", name: "Q.atl")
        #expect(result.diagnostics.isEmpty)
        #expect(result.module?.queryBody is ATLCollectionLiteralExpression)
    }

    @Test("Each syntax tokenises the range separator as its parser reads it")
    func tokens() async throws {
        let source = "Sequence{1..3}"
        let slices: ([SourceToken]) -> [String?] = { tokens in
            tokens.map { ATLDiagnosingParserTests.slice($0.range, of: source) }
        }
        let split = ["Sequence", "{", "1", ".", ".", "3", "}"]
        let joined = ["Sequence", "{", "1", "..", "3", "}"]
        #expect(slices(ATLSyntax.tokens(in: source, options: Self.ocl)) == joined)
        #expect(slices(ATLSyntax.tokens(in: source, options: Self.eclipse)) == split)
        #expect(slices(ATLSyntax.tokens(in: source)) == split)
        let diagnosed = await ATLParser(options: Self.eclipse).parseDiagnosing(
            "query Q = \(source);", name: "Q.atl")
        #expect(diagnosed.tokens.count == ATLSyntax.tokens(in: "query Q = \(source);").count)
    }
}

// MARK: - Resources

/// Tests for loading and saving ATL resources with options.
@Suite("ATL Resource Options")
@MainActor
struct ATLResourceOptionTests {

    /// Writes ATL source to a temporary file and returns its URL.
    private func write(_ source: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ATLOptions-\(UUID().uuidString).atl")
        try source.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test("A resource with OCL syntax loads a range and the 0.6 resource rejects it")
    func load() async throws {
        let url = try write("query Q = Sequence{1..3};")
        defer { try? FileManager.default.removeItem(at: url) }

        let resource = ATLResource(uri: url.absoluteString, options: .standard)
        #expect(resource.options == .standard)
        try await resource.load()
        #expect(resource.module?.queryBody is ATLCollectionLiteralExpression)

        let legacy = ATLResource(uri: url.absoluteString)
        #expect(legacy.options == .legacy)
        await #expect(throws: ATLParseError.self) { try await legacy.load() }
    }

    @Test("A resource writes ranges with the encoding of its options")
    func save() async throws {
        let unit = try await ATLParser(options: .standard).parseContent(
            "module M; create OUT : T from IN : S;\nhelper def : h : Sequence(Integer) = Sequence{1..3};")
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ATLOptions-\(UUID().uuidString).xmi")
        defer { try? FileManager.default.removeItem(at: url) }

        let portable = ATLOptions(collectionRangeEncoding: .portable)
        try await ATLResource(uri: url.absoluteString, module: unit, options: portable).save()
        let written = try String(contentsOf: url, encoding: .utf8)
        #expect(!written.contains("CollectionRange"))
        #expect(written.contains("integerSymbol=\"2\""))

        try await ATLResource(uri: url.absoluteString, module: unit, options: .standard).save()
        #expect(try String(contentsOf: url, encoding: .utf8).contains("ocl:CollectionRange"))
    }
}

// MARK: - Collection range encoding

/// Tests for writing collection ranges to XMI with each ``ATLCollectionRangeEncoding``.
@Suite("ATL Collection Range Encoding Option")
@MainActor
struct ATLCollectionRangeEncodingTests {

    /// Options that write ranges as OCL collection ranges.
    private static let collectionRange = ATLOptions(collectionRangeEncoding: .collectionRange)

    /// Options that write ranges in the portable encoding.
    private static let portable = ATLOptions(collectionRangeEncoding: .portable)

    /// The declarations that give the bounds of non-constant ranges their values.
    private static let declarations = """
        helper def : n : Integer = 4;
        helper def : none : Integer = 0;
        """

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

    /// Parses an expression with OCL range syntax.
    private func expression(_ text: String) async throws -> any ATLExpression {
        let unit = try await ATLParser(options: .standard).parseContent("query Q = \(text);")
        return try #require(unit.queryBody)
    }

    /// Evaluates an expression in a module that declares the range bound helpers.
    private func evaluate(_ expression: any ATLExpression) async throws -> (any EcoreValue)? {
        let harness = try await LanguageHarness.make(declarations: Self.declarations)
        return try await expression.evaluate(in: harness.context)
    }

    /// Writes an expression with the given options and reads it back.
    private func roundTrip(
        _ expression: any ATLExpression, options: ATLOptions
    ) throws -> (xmi: String, parsed: any ATLExpression) {
        let xmi = ATLExpressionXMISerializer(options: options).serialize(expression)
        return (xmi, try ATLExpressionXMIParser().parse(wrap(xmi)))
    }

    @Test("The serialisers keep the options they were created with")
    func serialiserOptions() {
        #expect(ATLExpressionXMISerializer(options: Self.portable).options == Self.portable)
        #expect(ATLExpressionXMISerializer().options == .legacy)
        #expect(ATLXMISerializer(options: Self.portable).options == Self.portable)
        #expect(ATLXMISerializer().options == .legacy)
    }

    @Test(
        "The collection range encoding reads back the identical literal",
        arguments: ATLCollectionKind.allCases)
    func collectionRangeRoundTrip(kind: ATLCollectionKind) async throws {
        let original = try await expression("\(kind.rawValue){0, 2..thisModule.n, 9}")
        let (xmi, parsed) = try roundTrip(original, options: Self.collectionRange)
        #expect(xmi.contains("ocl:CollectionRange"))
        #expect(areATLExpressionsEqual(parsed, original))
    }

    @Test(
        "The portable encoding writes integer literal ranges as their integers",
        arguments: [
            ("Sequence{1..3}", [1, 2, 3]),
            ("Sequence{0, 2..4, 9}", [0, 2, 3, 4, 9]),
            ("Sequence{-2..1}", [-2, -1, 0, 1]),
            ("Sequence{3..1}", []),
            ("Bag{1..3, 2..3}", [1, 2, 3, 2, 3]),
            ("Set{1..3, 2..4}", [1, 2, 3, 4]),
            ("OrderedSet{3, 1..4}", [3, 1, 2, 4]),
        ])
    func portableConstant(source: String, expected: [Int]) async throws {
        let original = try await expression(source)
        let (xmi, parsed) = try roundTrip(original, options: Self.portable)
        #expect(!xmi.contains("CollectionRange"))
        #expect(!xmi.contains(ATLOperation.includingRange.rawValue))
        let literal = try #require(parsed as? ATLCollectionLiteralExpression)
        #expect(!literal.elements.contains { $0 is ATLCollectionRangeExpression })
        #expect(try await evaluate(parsed).integers == expected)
        #expect(try await evaluate(original).integers == expected)
    }

    @Test(
        "The portable encoding writes other ranges with includingRange and evaluates alike",
        arguments: [
            "Sequence{thisModule.n..6}",
            "Sequence{0, 1..thisModule.n, 9, 2..3}",
            "Sequence{thisModule.n..thisModule.none, 7}",
            "Bag{2, 1..thisModule.n, 2}",
            "Set{5, 1..thisModule.n, 1, 6}",
            "OrderedSet{3, 1..thisModule.n, 0, 2}",
            "Sequence{1..Sequence{1..thisModule.n}->size()}",
        ])
    func portableComputed(source: String) async throws {
        let original = try await expression(source)
        let (xmi, parsed) = try roundTrip(original, options: Self.portable)
        #expect(!xmi.contains("CollectionRange"))
        #expect(xmi.contains("operationName=\"\(ATLOperation.includingRange.rawValue)\""))
        let expected = try await evaluate(original)
        let actual = try await evaluate(parsed)
        #expect(actual.integers == expected.integers)
        #expect(ATLCollections.kind(of: actual) == ATLCollections.kind(of: expected))
    }

    @Test("The portable encoding writes a range on its own as a sequence")
    func portableStandalone() async throws {
        let range = ATLCollectionRangeExpression(
            first: ATLLiteralExpression(value: 2), last: ATLLiteralExpression(value: 4))
        let (xmi, parsed) = try roundTrip(range, options: Self.portable)
        #expect(!xmi.contains("CollectionRange"))
        #expect(try await evaluate(parsed).integers == [2, 3, 4])
    }

    @Test("The portable encoding does not spell out a range longer than the range limit")
    func portableLong() async throws {
        let original = try await expression(
            "Sequence{1..\(ATLBuiltinOperations.maximumRangeLength + 1)}")
        let xmi = ATLExpressionXMISerializer(options: Self.portable).serialize(original)
        #expect(!xmi.contains("CollectionRange"))
        #expect(xmi.contains("operationName=\"\(ATLOperation.includingRange.rawValue)\""))
        #expect(xmi.count < 2_000)
    }

    @Test("The module serialiser writes ranges with the encoding of its options")
    func moduleSerialiser() async throws {
        let unit = try await ATLParser(options: .standard).parseContent(
            "module M; create OUT : T from IN : S;\nhelper def : h : Sequence(Integer) = Sequence{1..3};")
        let portable = try ATLXMISerializer(options: Self.portable).serialize(unit)
        #expect(!portable.contains("CollectionRange"))
        #expect(try ATLXMISerializer(options: Self.collectionRange).serialize(unit).contains("ocl:CollectionRange"))
        #expect(try ATLXMISerializer().serialize(unit).contains("ocl:CollectionRange"))
    }
}
