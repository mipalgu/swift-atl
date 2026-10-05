//
//  ATLLexer.swift
//  ATL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

// MARK: - Tokens

/// Token types for ATL lexical analysis
enum ATLTokenType: Equatable {
    case keyword(String)
    case identifier(String)
    case stringLiteral(String)
    case integerLiteral(Int)
    case realLiteral(Double)
    case enumLiteral(String)
    case booleanLiteral(Bool)
    case `operator`(String)
    case punctuation(String)
    case comment(String)
    case whitespace
    case newline
    case invalid(String)
    case eof
}

/// A lexical token with its position in the source text.
///
/// Lines and columns count from one. A column counts Unicode scalars, and
/// a `\r\n` pair is one line terminator, as in `LineTable`. Offsets count
/// UTF-8 bytes from the start of the text.
struct ATLToken: Equatable {
    /// The kind of token and its decoded value.
    let type: ATLTokenType

    /// The source text of the token.
    let value: String

    /// The line on which the token starts.
    let line: Int

    /// The column at which the token starts.
    let column: Int

    /// The UTF-8 offset at which the token starts.
    let offset: Int

    /// The UTF-8 offset just after the token.
    let endOffset: Int

    /// The line on which the token ends.
    let endLine: Int

    /// The column just after the token.
    let endColumn: Int

    /// Creates a token.
    ///
    /// - Parameters:
    ///   - type: The kind of token.
    ///   - value: The source text of the token.
    ///   - line: The line on which the token starts.
    ///   - column: The column at which the token starts.
    ///   - offset: The UTF-8 offset at which the token starts.
    ///   - endOffset: The UTF-8 offset just after the token.
    ///   - endLine: The line on which the token ends, by default the start line.
    ///   - endColumn: The column just after the token, by default the start column.
    init(
        type: ATLTokenType, value: String, line: Int, column: Int, offset: Int = 0,
        endOffset: Int = 0, endLine: Int? = nil, endColumn: Int? = nil
    ) {
        self.type = type
        self.value = value
        self.line = line
        self.column = column
        self.offset = offset
        self.endOffset = endOffset
        self.endLine = endLine ?? line
        self.endColumn = endColumn ?? column
    }

    /// The position at which the token starts.
    var start: SourcePosition { SourcePosition(utf8Offset: offset, line: line, column: column) }

    /// The position just after the token.
    var end: SourcePosition {
        SourcePosition(utf8Offset: endOffset, line: endLine, column: endColumn)
    }

    /// The source range the token covers.
    var range: SourceRange { SourceRange(start: start, end: end) }
}

/// A lexical problem found while scanning source text.
struct ATLLexicalProblem {
    /// The diagnostic code that classifies the problem.
    let code: ATLDiagnosticCode

    /// The error that a throwing parse reports for the problem.
    let error: ATLParseError

    /// The text the problem covers.
    let range: SourceRange
}

/// The result of scanning source text without stopping at lexical problems.
struct ATLScan {
    /// The tokens the parser reads, without comments and ending with an end-of-file token.
    var tokens: [ATLToken] = []

    /// The comments in source order.
    var comments: [ATLToken] = []

    /// The lexical problems in source order.
    var problems: [ATLLexicalProblem] = []

    /// The ranges of comments that hold a malformed directive.
    var directiveProblems: [SourceRange] = []
}

// MARK: - Lexer

/// ATL lexical analyzer
///
/// The lexer works on Unicode scalars and tracks the UTF-8 offset, line and
/// column of every token. The line terminators `\r\n`, `\r` and `\n` each end
/// one line, and the source text is never rewritten.
final class ATLLexer {
    private let scalars: [Unicode.Scalar]
    private var index = 0
    private var offset = 0
    private var line = 1
    private var column = 1
    private var scan = ATLScan()

    /// The header directives (`@path`, `@nsURI` and `@param`) extracted from comments.
    var directives = ATLDirectives()

    /// Maps metamodel name to file path (e.g., "Families" -> "/Families2Persons/Families.ecore")
    var pathDirectives: [String: String] { directives.paths }

    /// Creates a lexer for ATL source text.
    ///
    /// Line terminators in the text (`\r\n`, a lone `\r` and `\n`) are all treated as
    /// a single line break, so that tokens, directives, string literals and source
    /// locations are the same whichever convention the source file uses.
    ///
    /// - Parameter content: The ATL source text to tokenise.
    init(content: String) {
        self.scalars = Array(content.unicodeScalars)
    }

    /// Converts every line terminator in a text to a single line feed.
    ///
    /// - Parameter text: The text whose line terminators are normalised.
    /// - Returns: The text with `\r\n` and lone `\r` replaced by `\n`.
    static func normalisingLineEndings(_ text: String) -> String {
        var normalised = String.UnicodeScalarView()
        var previousWasCarriageReturn = false
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\r":
                normalised.append("\n")
                previousWasCarriageReturn = true
            case "\n":
                if !previousWasCarriageReturn { normalised.append(scalar) }
                previousWasCarriageReturn = false
            default:
                normalised.append(scalar)
                previousWasCarriageReturn = false
            }
        }
        return String(normalised)
    }

    /// Splits the source text into tokens.
    ///
    /// Whitespace, newlines and comments are dropped from the result, which always
    /// ends with an end-of-file token. Header directives found in comments are
    /// collected in ``directives``.
    ///
    /// - Returns: The tokens of the source text.
    /// - Throws: ``ATLParseError`` for an unterminated string literal or an unexpected character.
    func tokenize() throws -> [ATLToken] {
        let result = scanAll()
        if let problem = result.problems.first { throw problem.error }
        return result.tokens
    }

    /// Splits the source text into tokens without stopping at lexical problems.
    ///
    /// A character or literal that cannot be read becomes an invalid token and the
    /// scan carries on, so every part of the text is accounted for.
    ///
    /// - Returns: The parser tokens, the comments and the problems that were found.
    func scanAll() -> ATLScan {
        while index < scalars.count {
            scanToken()
        }
        scan.tokens.append(
            ATLToken(
                type: .eof, value: "", line: line, column: column, offset: offset,
                endOffset: offset, endLine: line, endColumn: column))
        return scan
    }

    // MARK: Scanning

    private struct Mark {
        let offset: Int
        let line: Int
        let column: Int
    }

    private var mark: Mark { Mark(offset: offset, line: line, column: column) }

    private func token(_ type: ATLTokenType, _ value: String, from start: Mark) -> ATLToken {
        ATLToken(
            type: type, value: value, line: start.line, column: start.column,
            offset: start.offset, endOffset: offset, endLine: line, endColumn: column)
    }

    private func emit(_ type: ATLTokenType, _ value: String, from start: Mark) {
        scan.tokens.append(token(type, value, from: start))
    }

    private func report(
        _ code: ATLDiagnosticCode, _ error: ATLParseError, from start: Mark
    ) -> ATLToken {
        let invalid = token(.invalid(""), "", from: start)
        scan.problems.append(
            ATLLexicalProblem(code: code, error: error, range: invalid.range))
        return invalid
    }

    private func emitInvalid(_ problem: ATLToken, text: String) {
        scan.tokens.append(
            ATLToken(
                type: .invalid(text), value: text, line: problem.line, column: problem.column,
                offset: problem.offset, endOffset: problem.endOffset, endLine: problem.endLine,
                endColumn: problem.endColumn))
    }

    private func scanToken() {
        let scalar = scalars[index]

        if scalar.properties.isWhitespace {
            advance()
            return
        }

        let start = mark

        if startsComment(at: 0) {
            scanComment(from: start)
        } else if Character(scalar) == ATLLanguage.stringDelimiter {
            scanString(from: start)
        } else if Character(scalar) == ATLLanguage.enumerationLiteralPrefix {
            scanEnumerationLiteral(from: start)
        } else if Character(scalar).isNumber {
            scanNumber(from: start)
        } else if let text = multiCharacterOperator() {
            advance()
            advance()
            emit(.operator(text), text, from: start)
        } else if ATLLanguage.operators.contains(String(scalar)) {
            advance()
            emit(.operator(String(scalar)), String(scalar), from: start)
        } else if ATLLanguage.punctuation.contains(String(scalar)) {
            advance()
            emit(.punctuation(String(scalar)), String(scalar), from: start)
        } else if Character(scalar).isLetter || scalar == "_" {
            scanIdentifier(from: start)
        } else {
            let character = Character(scalar)
            advance()
            let problem = report(
                .unexpectedCharacter,
                .unexpectedToken(
                    "Unexpected character: '\(character)' at line \(start.line), column \(start.column)"
                ), from: start)
            emitInvalid(problem, text: String(character))
        }
    }

    private func scalar(at distance: Int) -> Unicode.Scalar? {
        let target = index + distance
        return target < scalars.count ? scalars[target] : nil
    }

    private func startsComment(at distance: Int) -> Bool {
        scalar(at: distance) == "-" && scalar(at: distance + 1) == "-"
    }

    private func multiCharacterOperator() -> String? {
        guard let first = scalar(at: 0), let second = scalar(at: 1) else { return nil }
        let pair = String(first) + String(second)
        return ATLLanguage.multiCharacterOperators.contains(pair) ? pair : nil
    }

    private func isLineEnd(_ scalar: Unicode.Scalar) -> Bool {
        scalar == "\n" || scalar == "\r"
    }

    private func isIdentifierPart(_ scalar: Unicode.Scalar) -> Bool {
        let character = Character(scalar)
        if character.isLetter || character.isNumber || scalar == "_" { return true }
        switch scalar.properties.generalCategory {
        case .nonspacingMark, .spacingMark, .enclosingMark: return true
        default: return false
        }
    }

    private func scanComment(from start: Mark) {
        advance()
        advance()
        var text = String.UnicodeScalarView()
        while index < scalars.count, !isLineEnd(scalars[index]) {
            text.append(scalars[index])
            advance()
        }
        let comment = String(text)
        let errorCount = directives.errors.count
        directives.record(comment: comment)
        let result = token(.comment(comment), ATLLanguage.lineCommentPrefix + comment, from: start)
        if directives.errors.count > errorCount {
            scan.directiveProblems.append(result.range)
        }
        scan.comments.append(result)
    }

    private func scanString(from start: Mark) {
        advance()
        var raw = String.UnicodeScalarView()

        while index < scalars.count, Character(scalars[index]) != ATLLanguage.stringDelimiter {
            if Character(scalars[index]) == ATLLanguage.StringEscape.introducer {
                raw.append(scalars[index])
                advance()
                guard index < scalars.count else { break }
            }
            appendNormalised(scalars[index], to: &raw)
            advance()
        }

        guard index < scalars.count else {
            let problem = report(
                .unterminatedString,
                .invalidSyntax("Unterminated string literal at line \(start.line)"), from: start)
            emitInvalid(problem, text: String(ATLLanguage.stringDelimiter) + String(raw))
            return
        }

        advance()
        let rawText = String(raw)
        let delimiter = String(ATLLanguage.stringDelimiter)
        emit(
            .stringLiteral(ATLStringEscapes.decode(rawText)), delimiter + rawText + delimiter,
            from: start)
    }

    private func appendNormalised(_ scalar: Unicode.Scalar, to text: inout String.UnicodeScalarView)
    {
        text.append(scalar == "\r" ? "\n" : scalar)
    }

    private func scanEnumerationLiteral(from start: Mark) {
        advance()
        var name = ""
        while index < scalars.count, isIdentifierPartOfLiteral(scalars[index]) {
            name.unicodeScalars.append(scalars[index])
            advance()
        }
        guard !name.isEmpty else {
            let problem = report(
                .invalidEnumerationLiteral,
                .unexpectedToken(
                    "Expected an enumeration literal name after '#' at line \(start.line), column \(start.column)"
                ), from: start)
            emitInvalid(problem, text: String(ATLLanguage.enumerationLiteralPrefix))
            return
        }
        emit(.enumLiteral(name), "#\(name)", from: start)
    }

    private func isIdentifierPartOfLiteral(_ scalar: Unicode.Scalar) -> Bool {
        let character = Character(scalar)
        return character.isLetter || character.isNumber || scalar == "_"
    }

    private func isASCIIDigit(_ scalar: Unicode.Scalar?) -> Bool {
        guard let scalar else { return false }
        return scalar.isASCII && Character(scalar).isNumber
    }

    private func scanNumber(from start: Mark) {
        var value = ""
        var isReal = false

        func appendDigits() {
            while let next = scalar(at: 0), isASCIIDigit(next) {
                value.unicodeScalars.append(next)
                advance()
            }
        }

        appendDigits()

        // A fraction needs a digit after the point, so that `3.size()` still navigates
        if scalar(at: 0) == ".", isASCIIDigit(scalar(at: 1)) {
            isReal = true
            value.append(".")
            advance()
            appendDigits()
        }

        if let marker = scalar(at: 0), marker == "e" || marker == "E" {
            let hasSign = scalar(at: 1) == "+" || scalar(at: 1) == "-"
            if isASCIIDigit(scalar(at: hasSign ? 2 : 1)) {
                isReal = true
                value.append("e")
                advance()
                if hasSign {
                    value.unicodeScalars.append(scalars[index])
                    advance()
                }
                appendDigits()
            }
        }

        if !isReal, let integer = Int(value) {
            emit(.integerLiteral(integer), value, from: start)
            return
        }

        guard let real = Double(value) else {
            // A number that is not made of ASCII digits still consumes one scalar
            if value.isEmpty { advance() }
            let problem = report(
                .invalidNumber,
                .invalidSyntax(
                    "Invalid numeric literal '\(value)' at line \(start.line), column \(start.column)"
                ), from: start)
            emitInvalid(problem, text: value)
            return
        }
        emit(.realLiteral(real), value, from: start)
    }

    private func scanIdentifier(from start: Mark) {
        var value = ""
        while index < scalars.count, isIdentifierPart(scalars[index]) {
            value.unicodeScalars.append(scalars[index])
            advance()
        }

        if value == "true" {
            emit(.booleanLiteral(true), value, from: start)
        } else if value == "false" {
            emit(.booleanLiteral(false), value, from: start)
        } else if ATLLanguage.keywords.contains(value) {
            emit(.keyword(value), value, from: start)
        } else {
            emit(.identifier(value), value, from: start)
        }
    }

    private func advance() {
        guard index < scalars.count else { return }
        let current = scalars[index]
        offset += current.utf8.count
        index += 1
        switch current {
        case "\r":
            if index < scalars.count, scalars[index] == "\n" {
                offset += 1
                index += 1
            }
            line += 1
            column = 1
        case "\n":
            line += 1
            column = 1
        default:
            column += 1
        }
    }
}
