//
//  ATLTokenPositionTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ATL

/// Tests for the positions and kinds of ATL source tokens.
@Suite("ATL Token Position Tests")
struct ATLTokenPositionTests {

    /// The text a token covers, read by UTF-8 offsets.
    private func text(of token: SourceToken, in source: String) -> String {
        let bytes = Array(source.utf8)
        return String(decoding: bytes[token.range.start.utf8Offset..<token.range.end.utf8Offset], as: UTF8.self)
    }

    private func kinds(_ source: String) -> [(SourceTokenKind, String)] {
        ATLSyntax.tokens(in: source).map { ($0.kind, text(of: $0, in: source)) }
    }

    @Test("Every kind of token is classified with the text it covers")
    func everyKind() {
        let source = "module M; -- note\nhelper def : f() : Integer = 'a' + 1 + 2.5 + #lit + true and x -> y <> Sequence(S!T);"
        let result = kinds(source)
        let expected: [(SourceTokenKind, String)] = [
            (.keyword, "module"), (.identifier, "M"), (.punctuation, ";"), (.comment, "-- note"),
            (.keyword, "helper"), (.keyword, "def"), (.operator, ":"), (.identifier, "f"),
            (.punctuation, "("), (.punctuation, ")"), (.operator, ":"), (.typeName, "Integer"),
            (.operator, "="), (.string, "'a'"), (.operator, "+"), (.number, "1"), (.operator, "+"),
            (.number, "2.5"), (.operator, "+"), (.enumLiteral, "#lit"), (.operator, "+"),
            (.boolean, "true"), (.keyword, "and"), (.identifier, "x"), (.operator, "->"),
            (.identifier, "y"), (.operator, "<>"), (.typeName, "Sequence"), (.punctuation, "("),
            (.identifier, "S"), (.operator, "!"), (.typeName, "T"), (.punctuation, ")"),
            (.punctuation, ";"),
        ]
        #expect(result.count == expected.count)
        for (actual, wanted) in zip(result, expected) {
            #expect(actual.0 == wanted.0 && actual.1 == wanted.1, "\(actual) is not \(wanted)")
        }
    }

    @Test("Contextual keywords are keywords and directive comments are directives")
    func contextualKeywordsAndDirectives() {
        let result = kinds("-- @path A=/a.ecore\n-- @pathological\nabstract rule R extends S { using { } }")
        #expect(result.first?.0 == .directive)
        #expect(result[1].0 == .comment)
        #expect(result.filter { $0.0 == .keyword }.map(\.1) == ["abstract", "rule", "extends", "using"])
    }

    @Test("Offsets, lines and columns of ASCII tokens")
    func asciiPositions() throws {
        let tokens = ATLSyntax.tokens(in: "module M;\nhelper")
        #expect(tokens.count == 4)
        #expect(tokens[0].range.start == SourcePosition(utf8Offset: 0, line: 1, column: 1))
        #expect(tokens[0].range.end == SourcePosition(utf8Offset: 6, line: 1, column: 7))
        #expect(tokens[2].range.start == SourcePosition(utf8Offset: 8, line: 1, column: 9))
        #expect(tokens[3].range.start == SourcePosition(utf8Offset: 10, line: 2, column: 1))
        #expect(tokens[3].range.end == SourcePosition(utf8Offset: 16, line: 2, column: 7))
    }

    @Test("Columns count scalars and offsets count UTF-8 bytes for non-ASCII text")
    func nonASCIIPositions() throws {
        let source = "-- héllo\nhelper def : größe() : String = 'é😀' + x;"
        let tokens = ATLSyntax.tokens(in: source)
        let comment = tokens[0]
        #expect(comment.kind == .comment)
        #expect(comment.range.end == SourcePosition(utf8Offset: 9, line: 1, column: 9))
        let name = try #require(tokens.first { text(of: $0, in: source) == "größe" })
        #expect(name.range.start == SourcePosition(utf8Offset: 23, line: 2, column: 14))
        #expect(name.range.end == SourcePosition(utf8Offset: 30, line: 2, column: 19))
        let literal = try #require(tokens.first { $0.kind == .string })
        #expect(text(of: literal, in: source) == "'é😀'")
        #expect(literal.range.end.column - literal.range.start.column == 4)
        #expect(literal.range.end.utf8Offset - literal.range.start.utf8Offset == 8)
        let plus = try #require(tokens.first { text(of: $0, in: source) == "+" })
        #expect(plus.range.start.column == literal.range.end.column + 1)
    }

    @Test(
        "Positions agree with the line table for every line ending",
        arguments: ["\n", "\r\n", "\r"])
    func agreesWithLineTable(ending: String) {
        let source = [
            "-- @param p : String = 'x'", "module Ü;", "create OUT : A from IN : B;",
            "helper def : f(a : Integer) : String = 'multi", "line 😀' + #lit;", "rule R {",
            "  from s : B!T", "  to t : A!U ( n <- s.n )", "}",
        ].joined(separator: ending)
        let table = LineTable(source)
        let tokens = ATLSyntax.tokens(in: source)
        #expect(!tokens.isEmpty)
        for token in tokens {
            #expect(token.range.start == table.position(forUTF8Offset: token.range.start.utf8Offset))
            #expect(token.range.end == table.position(forUTF8Offset: token.range.end.utf8Offset))
        }
        let rule = tokens.first { text(of: $0, in: source) == "rule" }
        #expect(rule?.range.start.line == 6)
        #expect(rule?.range.start.column == 1)
    }

    @Test("A string spanning lines ends on the later line", arguments: ["\n", "\r\n", "\r"])
    func multilineString(ending: String) throws {
        let source = "'one\(ending)two' x"
        let tokens = ATLSyntax.tokens(in: source)
        let literal = try #require(tokens.first)
        #expect(literal.kind == .string)
        #expect(literal.range.start.line == 1)
        #expect(literal.range.end.line == 2)
        #expect(literal.range.end.column == 5)
        #expect(tokens[1].range.start.line == 2)
        #expect(tokens[1].range.start.column == 6)
    }

    @Test("Comments end before the line terminator", arguments: ["\n", "\r\n", "\r"])
    func commentEnd(ending: String) throws {
        let source = "-- one\(ending)-- two\(ending)module"
        let tokens = ATLSyntax.tokens(in: source)
        #expect(tokens.map(\.kind) == [.comment, .comment, .keyword])
        #expect(tokens[0].range.end == SourcePosition(utf8Offset: 6, line: 1, column: 7))
        #expect(tokens[1].range.start.line == 2)
        #expect(tokens[2].range.start.line == 3)
    }

    @Test("Unreadable text is marked invalid and scanning continues")
    func invalidText() {
        let source = "module ^ M; #; 'open ended"
        let result = kinds(source)
        #expect(result.map(\.0) == [.keyword, .invalid, .identifier, .punctuation, .invalid, .punctuation, .invalid])
        #expect(result[1].1 == "^")
        #expect(result[4].1 == "#")
        #expect(result[6].1 == "'open ended")
    }

    @Test("Tokenising never fails, whatever the text")
    func neverFails() {
        #expect(ATLSyntax.tokens(in: "").isEmpty)
        #expect(ATLSyntax.tokens(in: "   \r\n  ").isEmpty)
        for sample in ["'", "#", "\u{0}", "²", "1e", "1.", "a--", "<-->", "\u{2028}x"] {
            #expect(!ATLSyntax.tokens(in: sample).isEmpty || sample.isEmpty)
        }
    }

    @Test("Tokens are ordered and never overlap")
    func ordered() {
        let source = "module M; -- c\nhelper def : f() : Integer = 1; -- d\n^ 'x"
        let tokens = ATLSyntax.tokens(in: source)
        for (first, second) in zip(tokens, tokens.dropFirst()) {
            #expect(first.range.end.utf8Offset <= second.range.start.utf8Offset)
        }
    }

    @Test("The parser tokens carry the same positions")
    func lexerTokens() throws {
        let lexer = ATLLexer(content: "ab\r\n  cd")
        let tokens = try lexer.tokenize()
        #expect(tokens.count == 3)
        #expect(tokens[1].offset == 6)
        #expect(tokens[1].endOffset == 8)
        #expect(tokens[1].line == 2 && tokens[1].column == 3)
        #expect(tokens[1].endLine == 2 && tokens[1].endColumn == 5)
        #expect(tokens[2].type == .eof)
        #expect(tokens[2].offset == 8)
    }
}
