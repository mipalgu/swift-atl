//
//  ATLDiagnostics.swift
//  ATL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation

/// The stable codes of the diagnostics that ATL parsing reports.
///
/// Each code is a dotted identifier that tools can match on without depending on
/// the wording of a message.
public enum ATLDiagnosticCode: String, Sendable, CaseIterable, Hashable {
    /// A token appears where the grammar does not allow it.
    case unexpectedToken = "atl.unexpectedToken"

    /// A declaration or expression is malformed.
    case invalidSyntax = "atl.invalidSyntax"

    /// The source has no module declaration.
    case missingModule = "atl.missingModule"

    /// The name in the module declaration is missing or malformed.
    case invalidModuleName = "atl.invalidModuleName"

    /// An expression is malformed.
    case invalidExpression = "atl.invalidExpression"

    /// A construct of the ATL language is not supported.
    case unsupportedConstruct = "atl.unsupportedConstruct"

    /// A character cannot start any token.
    case unexpectedCharacter = "atl.unexpectedCharacter"

    /// A string literal has no closing quote.
    case unterminatedString = "atl.unterminatedString"

    /// A `#` is not followed by an enumeration literal name.
    case invalidEnumerationLiteral = "atl.invalidEnumerationLiteral"

    /// A numeric literal cannot be read.
    case invalidNumber = "atl.invalidNumber"

    /// A header directive is malformed.
    case invalidDirective = "atl.invalidDirective"

    /// A metamodel of the module is not bound to a package.
    case metamodelNotFound = "atl.metamodelNotFound"

    /// The code that classifies a parse error.
    ///
    /// - Parameter error: The error thrown by the parser.
    /// - Returns: The matching diagnostic code.
    static func code(for error: ATLParseError) -> ATLDiagnosticCode {
        switch error {
        case .invalidSyntax: return .invalidSyntax
        case .unexpectedToken: return .unexpectedToken
        case .missingModule: return .missingModule
        case .invalidModuleName: return .invalidModuleName
        case .invalidExpression: return .invalidExpression
        case .unsupportedConstruct: return .unsupportedConstruct
        case .metamodelNotFound: return .metamodelNotFound
        case .fileNotFound, .invalidEncoding: return .invalidSyntax
        }
    }
}

extension ATLParseError {
    /// A human-readable description of the error.
    var diagnosticMessage: String {
        switch self {
        case .invalidSyntax(let message), .unexpectedToken(let message),
            .invalidModuleName(let message), .invalidExpression(let message),
            .unsupportedConstruct(let message), .fileNotFound(let message),
            .metamodelNotFound(let message):
            return message
        case .missingModule:
            return "The source has no module declaration"
        case .invalidEncoding:
            return "The source is not valid UTF-8 text"
        }
    }
}

/// The kinds of node in the outline of an ATL module.
///
/// The kinds are the values of ``OutlineNode/kind`` in the outline that
/// ``ATLParseResult`` carries.
public enum ATLOutlineKind {
    /// The module declaration, which contains every other node.
    public static let module = "module"

    /// A helper with a parameter list.
    public static let helper = "helper"

    /// A helper without a parameter list, which is evaluated once per context.
    public static let attribute = "attribute"

    /// A query.
    public static let query = "query"

    /// A matched rule.
    public static let matchedRule = "matchedRule"

    /// A rule with a parameter list.
    public static let calledRule = "calledRule"

    /// A lazy rule.
    public static let lazyRule = "lazyRule"

    /// A source pattern of a rule.
    public static let sourcePattern = "sourcePattern"

    /// A target pattern of a rule.
    public static let targetPattern = "targetPattern"
}

/// The result of parsing ATL source text while collecting diagnostics.
///
/// Parsing recovers from errors, so the module holds every declaration that was
/// read correctly, and the diagnostics describe each declaration that was not.
public struct ATLParseResult: Sendable {
    /// The parsed module, or `nil` when the source has no usable module declaration.
    public var module: ATLModule?

    /// The problems found, in source order.
    public var diagnostics: [SourceDiagnostic]

    /// The outline of the source text.
    ///
    /// The outline holds one module node whose children are the helpers, queries
    /// and rules. A source without a module declaration has those nodes at the top level.
    public var outline: [OutlineNode]

    /// The lexical tokens of the source text, including comments.
    public var tokens: [SourceToken]

    /// Creates a parse result.
    ///
    /// - Parameters:
    ///   - module: The parsed module.
    ///   - diagnostics: The problems found.
    ///   - outline: The outline of the source text.
    ///   - tokens: The lexical tokens of the source text.
    public init(
        module: ATLModule?, diagnostics: [SourceDiagnostic], outline: [OutlineNode],
        tokens: [SourceToken]
    ) {
        self.module = module
        self.diagnostics = diagnostics
        self.outline = outline
        self.tokens = tokens
    }
}

/// Lexical analysis of ATL source text for tools such as editors.
public enum ATLSyntax {

    /// Splits ATL source text into classified tokens.
    ///
    /// The tokeniser never fails: text that cannot be read becomes a token of kind
    /// ``SourceTokenKind/invalid``. Comments are included, and a comment that holds a
    /// header directive such as `-- @path Name=file.ecore` is of kind
    /// ``SourceTokenKind/directive``. Whitespace is not reported. Positions count UTF-8
    /// offsets, lines from one and columns in Unicode scalars from one, and the line
    /// terminators `\r\n`, `\r` and `\n` each end one line.
    ///
    /// - Parameter text: The ATL source text.
    /// - Returns: The tokens in source order.
    public static func tokens(in text: String) -> [SourceToken] {
        let scan = ATLLexer(content: text).scanAll()
        return sourceTokens(of: scan)
    }

    /// Classifies the tokens of a scan.
    ///
    /// - Parameter scan: The result of scanning source text.
    /// - Returns: The tokens in source order, with comments.
    static func sourceTokens(of scan: ATLScan) -> [SourceToken] {
        var result: [SourceToken] = []
        var previous: ATLToken?
        let parserTokens = scan.tokens.filter { $0.type != .eof }
        var commentIndex = 0
        for token in parserTokens {
            while commentIndex < scan.comments.count,
                scan.comments[commentIndex].offset < token.offset
            {
                result.append(commentToken(scan.comments[commentIndex]))
                commentIndex += 1
            }
            result.append(SourceToken(kind: kind(of: token, after: previous), range: token.range))
            previous = token
        }
        for comment in scan.comments[commentIndex...] {
            result.append(commentToken(comment))
        }
        return result
    }

    private static func commentToken(_ comment: ATLToken) -> SourceToken {
        guard case .comment(let text) = comment.type else {
            return SourceToken(kind: .comment, range: comment.range)
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isDirective = ATLLanguage.Directive.all.contains { trimmed.hasPrefix($0 + " ") }
        return SourceToken(kind: isDirective ? .directive : .comment, range: comment.range)
    }

    private static func kind(of token: ATLToken, after previous: ATLToken?) -> SourceTokenKind {
        switch token.type {
        case .keyword(let word):
            return ATLLanguage.PrimitiveType(rawValue: word) != nil ? .typeName : .keyword
        case .identifier(let name):
            if previous?.type == .operator(String(ATLLanguage.metamodelSeparator)) {
                return .typeName
            }
            if ATLLanguage.contextualKeywords.contains(name) { return .keyword }
            if ATLLanguage.typeNames.contains(name) { return .typeName }
            return .identifier
        case .stringLiteral: return .string
        case .integerLiteral, .realLiteral: return .number
        case .enumLiteral: return .enumLiteral
        case .booleanLiteral: return .boolean
        case .operator: return .operator
        case .punctuation: return .punctuation
        case .comment: return .comment
        case .invalid: return .invalid
        case .whitespace, .newline, .eof: return .text
        }
    }
}
