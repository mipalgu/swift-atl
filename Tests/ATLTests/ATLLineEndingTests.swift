//
//  ATLLineEndingTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ATL

/// Tests that ATL source text parses and runs identically with every line ending convention.
@Suite("ATL Line Ending Tests")
@MainActor
struct ATLLineEndingTests {

    /// The line terminators that source text may use.
    enum LineEnding: String, CaseIterable, CustomTestStringConvertible {
        case lineFeed = "\n"
        case carriageReturnLineFeed = "\r\n"
        case carriageReturn = "\r"

        var testDescription: String {
            switch self {
            case .lineFeed: return "LF"
            case .carriageReturnLineFeed: return "CRLF"
            case .carriageReturn: return "CR"
            }
        }

        /// The terminators other than a line feed.
        static let nonLineFeed: [LineEnding] = [.carriageReturnLineFeed, .carriageReturn]

        /// Rewrites LF-terminated text with this line terminator.
        func apply(to text: String) -> String {
            text.replacingOccurrences(of: "\n", with: rawValue)
        }
    }


    private let fixture = ShapeFixture()

    private var registry: ATLMetamodelRegistry { ATLMetamodelRegistry(packages: [fixture.package]) }

    /// A module exercising directives, comments, helpers, rules, do blocks and strings.
    private var moduleText: String {
        """
        -- @nsURI Shapes=\(ShapeFixture.namespaceURI)
        -- @path Shapes=/models/Shapes.ecore
        -- @param prefix : String = 'copy of '
        -- @param count : Integer = 3
        -- @param ratio : Real = 1.5
        -- @param verbose : Boolean = false
        -- @param required : String
        -- an ordinary comment
        module Lines;
        create OUT : Shapes from IN : Shapes;
        -- helper comment
        helper def : twice(n : Integer) : Integer = n * 2;
        helper def : banner() : String = 'first
        second';
        rule Circle2Circle {
            from s : Shapes!Circle
            to t : Shapes!Circle (
                name <- thisModule.prefix + s.name,
                radius <- s.radius * thisModule.ratio
            )
            do {
                t.name <- t.name + '!';
            }
        }
        """
    }

    private func parse(_ text: String) async throws -> ATLModule {
        try await ATLParser().parseContent(text, metamodelRegistry: registry)
    }

    private func tokens(_ text: String) throws -> (ATLLexer, [ATLToken]) {
        let lexer = ATLLexer(content: text)
        return (lexer, try lexer.tokenize())
    }

    @Test("Parameters parse identically with every line ending", arguments: LineEnding.nonLineFeed)
    func parameters(ending: LineEnding) async throws {
        let reference = try await parse(moduleText).parameters
        let module = try await parse(ending.apply(to: moduleText))
        #expect(module.parameters == reference)
        #expect(
            reference.map(\.name) == ["prefix", "count", "ratio", "verbose", "required"])
        #expect(module.parameters[0].defaultValue == .string("copy of "))
        #expect(module.parameters[1].defaultValue == .integer(3))
        #expect(module.parameters[2].defaultValue == .real(1.5))
        #expect(module.parameters[3].defaultValue == .boolean(false))
        #expect(module.parameters[4].isRequired)
    }

    @Test("Path and namespace directives carry no line terminator", arguments: LineEnding.allCases)
    func bindingDirectives(ending: LineEnding) throws {
        let (lexer, _) = try tokens(ending.apply(to: moduleText))
        #expect(lexer.directives.paths == ["Shapes": "/models/Shapes.ecore"])
        #expect(lexer.directives.namespaceURIs == ["Shapes": ShapeFixture.namespaceURI])
        #expect(lexer.directives.errors.isEmpty)
    }

    @Test("Modules have the same structure with every line ending", arguments: LineEnding.nonLineFeed)
    func moduleStructure(ending: LineEnding) async throws {
        let reference = try await parse(moduleText)
        let module = try await parse(ending.apply(to: moduleText))
        #expect(module.name == reference.name)
        #expect(module.helpers.keys.elements == reference.helpers.keys.elements)
        #expect(module.matchedRules.map(\.name) == reference.matchedRules.map(\.name))
        #expect(module.matchedRules.first?.doStatements.count == reference.matchedRules.first?.doStatements.count)
        #expect(module.matchedRules.first?.doStatements.isEmpty == false)
        #expect(Array(module.sourceMetamodels.keys) == Array(reference.sourceMetamodels.keys))
        #expect(Array(module.targetMetamodels.keys) == Array(reference.targetMetamodels.keys))
    }

    @Test("Token streams match apart from line terminators", arguments: LineEnding.nonLineFeed)
    func tokenStreams(ending: LineEnding) throws {
        let reference = try tokens(moduleText).1
        let candidate = try tokens(ending.apply(to: moduleText)).1
        #expect(candidate.map(\.type) == reference.map(\.type))
        #expect(candidate.map(\.line) == reference.map(\.line))
        #expect(candidate.map(\.column) == reference.map(\.column))
    }

    @Test("Comments stop at the line terminator", arguments: LineEnding.allCases)
    func comments(ending: LineEnding) throws {
        let text = ending.apply(to: "-- first\n-- second\nmodule M;\n")
        let comments = try tokens(text).1.compactMap { token -> String? in
            if case .comment(let text) = token.type { return text }
            return nil
        }
        // Comments are dropped from the token stream, so check the module token positions
        #expect(comments.isEmpty)
        let module = try #require(try tokens(text).1.first)
        #expect(module.value == "module")
        #expect(module.line == 3)
        #expect(module.column == 1)
    }

    @Test("String literals spanning line ends decode identically", arguments: LineEnding.allCases)
    func multilineStrings(ending: LineEnding) throws {
        let text = ending.apply(to: "'one\ntwo'")
        let token = try #require(try tokens(text).1.first)
        guard case .stringLiteral(let value) = token.type else {
            Issue.record("Expected a string literal")
            return
        }
        #expect(value == "one\ntwo")
    }

    @Test("Error locations count each line terminator once", arguments: LineEnding.allCases)
    func errorLocations(ending: LineEnding) async throws {
        let text = ending.apply(to: "module M;\n\n\n'unterminated")
        await #expect {
            try await ATLParser().parseContent(text)
        } throws: { error in
            guard case ATLParseError.invalidSyntax(let message) = error else { return false }
            return message.contains("line 4")
        }
        let (_, parsed) = try tokens(ending.apply(to: "module M;\n\n\nrule"))
        #expect(parsed.last(where: { $0.type != .eof })?.line == 4)
        let character = ending.apply(to: "module M;\n\n^")
        await #expect {
            try await ATLParser().parseContent(character)
        } throws: { error in
            guard case ATLParseError.unexpectedToken(let message) = error else { return false }
            return message.contains("line 3, column 1")
        }
    }

    @Test("Malformed directives are still reported", arguments: LineEnding.allCases)
    func malformedDirective(ending: LineEnding) throws {
        let (lexer, _) = try tokens(ending.apply(to: "-- @param broken\nmodule M;\n"))
        #expect(lexer.directives.errors.count == 1)
    }

    @Test("A transformation from line-ended source equals the LF run", arguments: LineEnding.nonLineFeed)
    func endToEnd(ending: LineEnding) async throws {
        func run(_ text: String) async throws -> (String?, Double?, [String]) {
            let module = try await parse(text)
            let input = Resource(uri: "test://in")
            await input.add(fixture.make(fixture.circle, ["name": "c", "radius": 2.0]))
            let output = Resource(uri: "test://out")
            try await ATLVirtualMachine(module: module).execute(
                sources: ["IN": input], targets: ["OUT": output],
                parameters: ["required": "x", "count": 7])
            let created = try #require(
                await output.getAllInstancesOf(fixture.circle).first as? DynamicEObject)
            return (
                created.eGet("name") as? String, created.eGet("radius") as? Double,
                module.parameters.map(\.name)
            )
        }
        let reference = try await run(moduleText)
        let candidate = try await run(ending.apply(to: moduleText))
        #expect(reference.0 == "copy of c!")
        #expect(reference.1 == 3.0)
        #expect(candidate.0 == reference.0)
        #expect(candidate.1 == reference.1)
        #expect(candidate.2 == reference.2)
    }
}

/// Tests for directive text that still carries a line terminator.
@Suite("ATL Directive Terminator Tests")
struct ATLDirectiveTerminatorTests {

    @Test("Trailing terminators never reach directive values", arguments: ["\r", "\r\n", "\n", ""])
    func trailingTerminators(terminator: String) {
        var directives = ATLDirectives()
        directives.record(comment: " @path Name=/a/b.ecore\(terminator)")
        directives.record(comment: " @nsURI Name=http://example.org/n\(terminator)")
        directives.record(comment: " @param flag : Boolean = true\(terminator)")
        directives.record(comment: " @param label : String\(terminator)")
        #expect(directives.paths == ["Name": "/a/b.ecore"])
        #expect(directives.namespaceURIs == ["Name": "http://example.org/n"])
        #expect(directives.parameters.map(\.name) == ["flag", "label"])
        #expect(directives.parameters.first?.defaultValue == .boolean(true))
        #expect(directives.errors.isEmpty)
    }

    @Test("Line endings are normalised to line feeds")
    func normalisation() {
        #expect(ATLLexer.normalisingLineEndings("a\r\nb\rc\nd\r\r\ne") == "a\nb\nc\nd\n\ne")
        #expect(ATLLexer.normalisingLineEndings("") == "")
    }
}
