//
//  ATLParser.swift
//  ATL
//
//  Created by Rene Hexel on 6/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import ECore
import Foundation
import OrderedCollections

/// Errors that can occur during ATL parsing
public enum ATLParseError: Error, Sendable {
    case invalidSyntax(String)
    case unexpectedToken(String)
    case missingModule
    case invalidModuleName(String)
    case invalidExpression(String)
    case unsupportedConstruct(String)
    case fileNotFound(String)
    case invalidEncoding
}

/// Parser for ATL (Atlas Transformation Language) files
///
/// The ATL parser converts ATL source files into structured ATL modules that can be
/// executed by the ATL virtual machine. It supports:
/// - Module declarations with source/target metamodels
/// - Helper function definitions (context and context-free)
/// - Matched transformation rules
/// - Called transformation rules
/// - Query expressions
/// - Basic ATL expression syntax
///
/// ## Supported ATL Constructs
///
/// - **Modules**: `module ModuleName;`
/// - **Create statements**: `create OUT : Target from IN : Source;`
/// - **Helpers**: `helper def : helperName() : Type = expression;`
/// - **Context helpers**: `helper context Type def : helperName() : Type = expression;`
/// - **Matched rules**: `rule RuleName { from ... to ... }`
/// - **Called rules**: `rule RuleName(params) { to ... }`
/// - **Queries**: `query QueryName = expression;`
/// - **Expressions**: literals, variables, operations, navigation
///
/// ## Example Usage
///
/// ```swift
/// let parser = ATLParser()
/// let module = try await parser.parse(atlFileURL)
/// ```
///
/// - Note: This is a simplified parser focused on supporting the Swift ATL implementation.
///   It may not support all advanced ATL features found in Eclipse ATL.
public actor ATLParser {

    /// Public initializer for ATLParser
    public init() {}

    /// Parse an ATL file and return an ATL module
    /// - Parameter url: The URL of the ATL file to parse
    /// - Returns: An ATLModule representing the parsed ATL content
    /// - Throws: ATLParseError if parsing fails
    public func parse(_ url: URL) async throws -> ATLModule {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw ATLParseError.fileNotFound(url.path)
        }

        // Pass the full path for proper relative path resolution
        return try await parseContent(content, filename: url.path)
    }

    /// Parse ATL content from a string
    /// - Parameters:
    ///   - content: The ATL source content
    ///   - filename: Optional filename for error reporting
    ///   - searchPaths: Optional array of directory paths to search for metamodel files
    /// - Returns: An ATLModule representing the parsed ATL content
    /// - Throws: ATLParseError if parsing fails
    public func parseContent(
        _ content: String,
        filename: String = "unknown",
        searchPaths: [String] = []
    ) async throws -> ATLModule {
        let lexer = ATLLexer(content: content)
        let tokens = try lexer.tokenize()
        let parser = ATLSyntaxParser(tokens: tokens, filename: filename)

        var module = try parser.parseModule()

        // Load metamodels from @path directives
        let baseURL = URL(fileURLWithPath: filename)
        module = try await loadMetamodels(
            into: module,
            pathDirectives: lexer.pathDirectives,
            relativeTo: baseURL,
            searchPaths: searchPaths
        )

        return module
    }

    /// Loads all metamodels specified by @path directives and replaces dummy metamodels.
    ///
    /// - Parameters:
    ///   - module: The parsed ATL module with dummy metamodels
    ///   - pathDirectives: Dictionary mapping metamodel names to file paths from @path directives
    ///   - baseURL: The URL of the ATL file (for resolving relative paths)
    ///   - searchPaths: Array of directory paths to search for metamodel files
    /// - Returns: The module with real loaded metamodels
    private func loadMetamodels(
        into module: ATLModule,
        pathDirectives: [String: String],
        relativeTo baseURL: URL,
        searchPaths: [String]
    ) async throws -> ATLModule {
        var sourceMetamodels = module.sourceMetamodels
        var targetMetamodels = module.targetMetamodels

        // Load source metamodels
        for (alias, metamodel) in sourceMetamodels {
            if let filePath = pathDirectives[metamodel.name],
               let loadedPackage = try await loadMetamodel(
                   name: metamodel.name,
                   from: filePath,
                   relativeTo: baseURL,
                   searchPaths: searchPaths
               )
            {
                sourceMetamodels[alias] = loadedPackage
            }
        }

        // Load target metamodels
        for (alias, metamodel) in targetMetamodels {
            if let filePath = pathDirectives[metamodel.name],
               let loadedPackage = try await loadMetamodel(
                   name: metamodel.name,
                   from: filePath,
                   relativeTo: baseURL,
                   searchPaths: searchPaths
               )
            {
                targetMetamodels[alias] = loadedPackage
            }
        }

        // Return new module with loaded metamodels
        return ATLModule(
            name: module.name,
            sourceMetamodels: sourceMetamodels,
            targetMetamodels: targetMetamodels,
            helpers: module.helpers,
            matchedRules: module.matchedRules,
            calledRules: module.calledRules
        )
    }

    /// Loads a metamodel from an Ecore file.
    ///
    /// - Parameters:
    ///   - metamodelName: The name of the metamodel (from @path directive)
    ///   - filePath: The file path from the @path directive
    ///   - baseURL: The URL of the ATL file (for resolving relative paths)
    ///   - searchPaths: Array of directory paths to search for metamodel files
    /// - Returns: The loaded EPackage, or nil if loading fails
    private func loadMetamodel(
        name metamodelName: String,
        from filePath: String,
        relativeTo baseURL: URL,
        searchPaths: [String]
    ) async throws -> EPackage? {
        var candidateURLs: [URL] = []

        if filePath.hasPrefix("/") {
            // Workspace-relative path - search in search paths
            // Remove leading '/' to get relative path
            let relativePath = String(filePath.dropFirst())

            // Try each search path
            for searchPath in searchPaths {
                let candidate = URL(fileURLWithPath: searchPath)
                    .appendingPathComponent(relativePath)
                candidateURLs.append(candidate)
            }
        } else {
            // Regular relative path - resolve relative to ATL file
            let base = baseURL.deletingLastPathComponent()
            candidateURLs.append(base.appendingPathComponent(filePath))
        }

        // Try each candidate URL
        for candidateURL in candidateURLs {
            let resolved = candidateURL.standardizedFileURL

            guard FileManager.default.fileExists(atPath: resolved.path) else {
                continue
            }

            do {
                // Use EPackage initializer to load the .ecore file
                let package = try await EPackage(url: resolved)
                return package
            } catch {
                // Try next candidate if this one fails to parse
                continue
            }
        }

        // None of the candidates worked
        return nil
    }
}

// MARK: - ATL Lexer

/// Token types for ATL lexical analysis
private enum ATLTokenType: Equatable {
    case keyword(String)
    case identifier(String)
    case stringLiteral(String)
    case integerLiteral(Int)
    case booleanLiteral(Bool)
    case `operator`(String)
    case punctuation(String)
    case comment(String)
    case whitespace
    case newline
    case eof
}

/// Token representation
private struct ATLToken: Equatable {
    let type: ATLTokenType
    let value: String
    let line: Int
    let column: Int
}

/// ATL lexical analyzer
private class ATLLexer {
    private let content: String
    private var position: String.Index
    private var line: Int = 1
    private var column: Int = 1

    /// Storage for @path directives extracted from comments
    /// Maps metamodel name to file path (e.g., "Families" -> "/Families2Persons/Families.ecore")
    var pathDirectives: [String: String] = [:]

    private static let keywords: Set<String> = [
        "module", "create", "from", "helper", "def", "context", "rule", "query",
        "if", "then", "else", "endif", "and", "or", "not", "true", "false",
        "let", "in", "do", "to", "self", "lazy",
        "Integer", "String", "Boolean", "Real",
    ]

    private static let `operators`: Set<String> = [
        "+", "-", "*", "/", "=", "<>", "<", ">", "<=", ">=", "->", ".", ":", "<-", "!",
    ]

    private static let punctuation: Set<String> = [
        "(", ")", "{", "}", "[", "]", ";", ",", "|",
    ]

    init(content: String) {
        self.content = content
        self.position = content.startIndex
    }

    func tokenize() throws -> [ATLToken] {
        var tokens: [ATLToken] = []

        while position < content.endIndex {
            let token = try nextToken()

            // Skip whitespace and comments for parsing
            switch token.type {
            case .whitespace, .comment, .newline:
                continue
            default:
                tokens.append(token)
            }
        }

        tokens.append(ATLToken(type: .eof, value: "", line: line, column: column))
        return tokens
    }

    /// Extracts and stores @path directives from comments.
    ///
    /// Expected format: `@path MetamodelName=/path/to/Metamodel.ecore`
    ///
    /// - Parameter comment: The comment text (without the leading `--`)
    private func extractPathDirective(from comment: String) {
        let trimmed = comment.trimmingCharacters(in: .whitespaces)

        // Remove "@path " prefix
        guard trimmed.hasPrefix("@path ") else { return }
        let directive = String(trimmed.dropFirst(6))  // Remove "@path "

        // Parse "Name=/path/to/file.ecore"
        let components = directive.split(separator: "=", maxSplits: 1)
        guard components.count == 2 else {
            // Malformed @path directive - silently ignore
            return
        }

        let metamodelName = String(components[0]).trimmingCharacters(in: .whitespaces)
        let filePath = String(components[1]).trimmingCharacters(in: .whitespaces)

        pathDirectives[metamodelName] = filePath
    }

    private func nextToken() throws -> ATLToken {
        guard position < content.endIndex else {
            return ATLToken(type: .eof, value: "", line: line, column: column)
        }

        let startLine = line
        let startColumn = column
        let char = content[position]

        // Skip whitespace
        if char.isWhitespace {
            if char.isNewline {
                advance()
                return ATLToken(type: .newline, value: "\n", line: startLine, column: startColumn)
            } else {
                while position < content.endIndex && content[position].isWhitespace
                    && !content[position].isNewline
                {
                    advance()
                }
                return ATLToken(type: .whitespace, value: " ", line: startLine, column: startColumn)
            }
        }

        // Comments
        if char == "-" && peek() == "-" {
            advance()  // first -
            advance()  // second -
            var comment = ""
            while position < content.endIndex && !content[position].isNewline {
                comment.append(content[position])
                advance()
            }

            // Extract @path directive if present
            extractPathDirective(from: comment)

            return ATLToken(
                type: .comment(comment), value: "--" + comment, line: startLine, column: startColumn
            )
        }

        // String literals
        if char == "'" {
            return try parseStringLiteral(startLine: startLine, startColumn: startColumn)
        }

        // Numbers
        if char.isNumber {
            return parseNumericLiteral(startLine: startLine, startColumn: startColumn)
        }

        // Multi-character operators
        if char == "<" {
            if peek() == ">" {
                advance()  // <
                advance()  // >
                return ATLToken(
                    type: .`operator`("<>"), value: "<>", line: startLine, column: startColumn)
            } else if peek() == "=" {
                advance()  // <
                advance()  // =
                return ATLToken(
                    type: .`operator`("<="), value: "<=", line: startLine, column: startColumn)
            } else if peek() == "-" {
                advance()  // <
                advance()  // -
                return ATLToken(
                    type: .`operator`("<-"), value: "<-", line: startLine, column: startColumn)
            }
        } else if char == ">" && peek() == "=" {
            advance()  // >
            advance()  // =
            return ATLToken(
                type: .`operator`(">="), value: ">=", line: startLine, column: startColumn)
        } else if char == "-" && peek() == ">" {
            advance()  // -
            advance()  // >
            return ATLToken(
                type: .`operator`("->"), value: "->", line: startLine, column: startColumn)
        }

        // Single-character operators
        if Self.`operators`.contains(String(char)) {
            advance()
            return ATLToken(
                type: .`operator`(String(char)), value: String(char), line: startLine,
                column: startColumn)
        }

        // Punctuation
        if Self.punctuation.contains(String(char)) {
            advance()
            return ATLToken(
                type: .punctuation(String(char)), value: String(char), line: startLine,
                column: startColumn)
        }

        // Identifiers and keywords
        if char.isLetter || char == "_" {
            return parseIdentifier(startLine: startLine, startColumn: startColumn)
        }

        throw ATLParseError.unexpectedToken(
            "Unexpected character: '\(char)' at line \(line), column \(column)")
    }

    private func parseStringLiteral(startLine: Int, startColumn: Int) throws -> ATLToken {
        advance()  // Skip opening quote
        var value = ""

        while position < content.endIndex && content[position] != "'" {
            value.append(content[position])
            advance()
        }

        guard position < content.endIndex else {
            throw ATLParseError.invalidSyntax("Unterminated string literal at line \(startLine)")
        }

        advance()  // Skip closing quote
        return ATLToken(
            type: .stringLiteral(value), value: "'\(value)'", line: startLine, column: startColumn)
    }

    private func parseNumericLiteral(startLine: Int, startColumn: Int) -> ATLToken {
        var value = ""

        while position < content.endIndex
            && (content[position].isNumber || content[position] == ".")
        {
            value.append(content[position])
            advance()
        }

        if let intValue = Int(value) {
            return ATLToken(
                type: .integerLiteral(intValue), value: value, line: startLine, column: startColumn)
        }

        // For simplicity, treat as integer even if parsing fails
        return ATLToken(
            type: .integerLiteral(0), value: value, line: startLine, column: startColumn)
    }

    private func parseIdentifier(startLine: Int, startColumn: Int) -> ATLToken {
        var value = ""

        while position < content.endIndex
            && (content[position].isLetter || content[position].isNumber
                || content[position] == "_")
        {
            value.append(content[position])
            advance()
        }

        // Check for boolean literals
        if value == "true" {
            return ATLToken(
                type: .booleanLiteral(true), value: value, line: startLine, column: startColumn)
        } else if value == "false" {
            return ATLToken(
                type: .booleanLiteral(false), value: value, line: startLine, column: startColumn)
        }

        // Check if it's a keyword
        if Self.keywords.contains(value) {
            return ATLToken(
                type: .keyword(value), value: value, line: startLine, column: startColumn)
        }

        return ATLToken(
            type: .identifier(value), value: value, line: startLine, column: startColumn)
    }

    private func advance() {
        if position < content.endIndex {
            if content[position].isNewline {
                line += 1
                column = 1
            } else {
                column += 1
            }
            position = content.index(after: position)
        }
    }

    private func peek() -> Character? {
        let nextIndex = content.index(after: position)
        guard nextIndex < content.endIndex else { return nil }
        return content[nextIndex]
    }
}

// MARK: - ATL Syntax Parser

/// ATL syntax parser
private class ATLSyntaxParser {
    private let tokens: [ATLToken]
    private var position: Int = 0
    private let filename: String

    init(tokens: [ATLToken], filename: String) {
        self.tokens = tokens
        self.filename = filename
    }

    func parseModule() throws -> ATLModule {
        // Parse module declaration
        guard let moduleName = try parseModuleDeclaration() else {
            throw ATLParseError.missingModule
        }

        var sourceMetamodels: OrderedDictionary<String, EPackage> = [:]
        var targetMetamodels: OrderedDictionary<String, EPackage> = [:]
        var helpers: OrderedDictionary<String, any ATLHelperType> = [:]
        var matchedRules: [ATLMatchedRule] = []
        var calledRules: OrderedDictionary<String, ATLCalledRule> = [:]

        // Parse create statement if present
        if currentToken()?.type == .keyword("create") {
            let (source, target) = try parseCreateStatement()
            sourceMetamodels = source
            targetMetamodels = target
        }

        // Parse module contents
        while !isAtEnd() {
            if currentToken()?.type == .keyword("helper") {
                let helper = try parseHelper()
                helpers[helper.name] = helper
            } else if currentToken()?.type == .keyword("lazy") {
                // Parse lazy rule (same as called rule in ATL)
                advance()  // consume 'lazy'
                guard consumeKeyword("rule") else {
                    throw ATLParseError.invalidSyntax("Expected 'rule' keyword after 'lazy'")
                }
                let rule = try parseLazyRule()
                calledRules[rule.name] = rule
            } else if currentToken()?.type == .keyword("rule") {
                let rule = try parseRule()
                if let matchedRule = rule as? ATLMatchedRule {
                    matchedRules.append(matchedRule)
                } else if let calledRule = rule as? ATLCalledRule {
                    calledRules[calledRule.name] = calledRule
                }
            } else if currentToken()?.type == .keyword("query") {
                let helper = try parseQuery()
                helpers[helper.name] = helper
            } else {
                advance()
            }
        }

        // Create default metamodels if none specified
        if sourceMetamodels.isEmpty {
            sourceMetamodels["IN"] = EPackage(name: "DefaultSource", nsURI: "http://default.source")
        }
        if targetMetamodels.isEmpty {
            targetMetamodels["OUT"] = EPackage(
                name: "DefaultTarget", nsURI: "http://default.target")
        }

        return ATLModule(
            name: moduleName,
            sourceMetamodels: sourceMetamodels,
            targetMetamodels: targetMetamodels,
            helpers: helpers,
            matchedRules: matchedRules,
            calledRules: calledRules
        )
    }

    private func parseModuleDeclaration() throws -> String? {
        guard consumeKeyword("module") else {
            return nil
        }

        guard let nameToken = currentToken(),
            case .identifier(let name) = nameToken.type
        else {
            throw ATLParseError.invalidModuleName("Expected module name")
        }

        advance()
        consumePunctuation(";")

        return name
    }

    private func parseCreateStatement() throws -> (
        OrderedDictionary<String, EPackage>, OrderedDictionary<String, EPackage>
    ) {
        guard consumeKeyword("create") else {
            throw ATLParseError.invalidSyntax("Expected 'create' keyword")
        }

        var targetMetamodels: OrderedDictionary<String, EPackage> = [:]
        var sourceMetamodels: OrderedDictionary<String, EPackage> = [:]

        // Parse target models: OUT : TargetMM
        while let token = currentToken(), case .identifier(let alias) = token.type {
            advance()
            consumeOperator(":")

            guard let mmToken = currentToken(),
                case .identifier(let metamodelName) = mmToken.type
            else {
                throw ATLParseError.invalidSyntax("Expected metamodel name")
            }
            advance()

            targetMetamodels[alias] = EPackage(
                name: metamodelName, nsURI: "http://\(metamodelName.lowercased())")

            if currentToken()?.type == .keyword("from") {
                break
            }

            if currentToken()?.type == .punctuation(",") {
                advance()
            }
        }

        // Parse 'from' keyword
        if consumeKeyword("from") {
            // Parse source models: IN : SourceMM
            while let token = currentToken(), case .identifier(let alias) = token.type {
                advance()
                consumeOperator(":")

                guard let mmToken = currentToken(),
                    case .identifier(let metamodelName) = mmToken.type
                else {
                    throw ATLParseError.invalidSyntax("Expected metamodel name")
                }
                advance()

                sourceMetamodels[alias] = EPackage(
                    name: metamodelName, nsURI: "http://\(metamodelName.lowercased())")

                if currentToken()?.type == .punctuation(";") {
                    break
                }

                if currentToken()?.type == .punctuation(",") {
                    advance()
                }
            }
        }

        consumePunctuation(";")

        return (sourceMetamodels, targetMetamodels)
    }

    private func parseQuery() throws -> any ATLHelperType {
        guard consumeKeyword("query") else {
            throw ATLParseError.invalidSyntax("Expected 'query' keyword")
        }

        guard let nameToken = currentToken(),
            case .identifier(let name) = nameToken.type
        else {
            throw ATLParseError.invalidSyntax("Expected query name")
        }
        advance()

        consumeOperator("=")

        let bodyExpression = try parseExpression()

        consumePunctuation(";")

        return ATLHelperWrapper(
            name: name,
            contextType: nil,
            returnType: "OclAny",
            parameters: [],
            body: bodyExpression
        )
    }

    private func parseHelper() throws -> any ATLHelperType {
        consumeKeyword("helper")

        var contextType: String? = nil

        // Check for context helper: helper context Type def : name
        if consumeKeyword("context") {
            contextType = try parseTypeExpression()
            guard consumeKeyword("def") else {
                throw ATLParseError.invalidSyntax("Expected 'def' after context type")
            }
        } else {
            // Context-free helper: helper def : name
            guard consumeKeyword("def") else {
                throw ATLParseError.invalidSyntax("Expected 'def' after helper keyword")
            }
        }

        // Consume the colon operator (may have whitespace before it)
        guard currentToken()?.type == .`operator`(":") else {
            throw ATLParseError.invalidSyntax("Expected ':' after helper def")
        }
        advance()

        guard let nameToken = currentToken(),
            case .identifier(let name) = nameToken.type
        else {
            throw ATLParseError.invalidSyntax("Expected helper name")
        }
        advance()

        // Parse parameters if present
        var parameters: [ATLParameter] = []
        if consumePunctuation("(") {
            parameters = try parseParameterList()
            consumePunctuation(")")
        }

        // Parse return type - consume colon
        guard consumeOperator(":") else {
            throw ATLParseError.invalidSyntax("Expected ':' before return type")
        }
        let returnType = try parseTypeExpression()

        // Consume equals operator
        guard consumeOperator("=") else {
            throw ATLParseError.invalidSyntax("Expected '=' before helper body")
        }

        let bodyExpression = try parseExpression()

        consumePunctuation(";")

        return ATLHelperWrapper(
            name: name,
            contextType: contextType,
            returnType: returnType,
            parameters: parameters,
            body: bodyExpression
        )
    }

    private func parseParameterList() throws -> [ATLParameter] {
        var parameters: [ATLParameter] = []

        while !isAtEnd() && currentToken()?.type != .punctuation(")") {
            guard let nameToken = currentToken(),
                case .identifier(let paramName) = nameToken.type
            else {
                throw ATLParseError.invalidSyntax("Expected parameter name")
            }
            advance()

            guard consumeOperator(":") else {
                throw ATLParseError.invalidSyntax("Expected ':' after parameter name")
            }
            let paramType = try parseTypeExpression()

            parameters.append(ATLParameter(name: paramName, type: paramType))

            if currentToken()?.type == .punctuation(",") {
                advance()
            } else {
                break
            }
        }

        return parameters
    }

    private func parseTypeExpression() throws -> String {
        guard let typeToken = currentToken() else {
            throw ATLParseError.invalidSyntax("Expected type expression but reached end of input")
        }

        switch typeToken.type {
        case .identifier(let typeName), .keyword(let typeName):
            advance()

            // Check for metamodel qualified type: Source!Person (do this first)
            if let currentTok = currentToken(), case .`operator`(let op) = currentTok.type,
                op == "!"
            {
                advance()

                guard let classToken = currentToken() else {
                    throw ATLParseError.invalidSyntax("Expected class name after '!'")
                }

                let className: String
                switch classToken.type {
                case .identifier(let name), .keyword(let name):
                    className = name
                default:
                    throw ATLParseError.invalidSyntax("Expected class name after '!'")
                }
                advance()

                return "\(typeName)!\(className)"
            }

            // Handle generic types like Sequence(Type), Set(Type), etc.
            // Only for non-metamodel qualified types
            if let currentTok = currentToken(), case .punctuation(let punct) = currentTok.type,
                punct == "("
            {
                advance()  // consume '('

                // Special handling for TupleType which has field declarations: TupleType(name : Type, ...)
                if typeName == "TupleType" {
                    var fields: [String] = []
                    while !isAtEnd() && !(currentToken()?.type == .punctuation(")")) {
                        // Parse field name
                        guard let fieldToken = currentToken(),
                            case .identifier(let fieldName) = fieldToken.type
                        else {
                            throw ATLParseError.invalidSyntax("Expected field name in TupleType")
                        }
                        advance()

                        // Expect ':'
                        guard consumeOperator(":") else {
                            throw ATLParseError.invalidSyntax(
                                "Expected ':' after field name in TupleType")
                        }

                        // Parse field type
                        let fieldType = try parseTypeExpression()
                        fields.append("\(fieldName) : \(fieldType)")

                        // Check for comma or end
                        if !consumePunctuation(",") {
                            break
                        }
                    }

                    guard consumePunctuation(")") else {
                        throw ATLParseError.invalidSyntax("Expected ')' after TupleType fields")
                    }

                    return "\(typeName)(\(fields.joined(separator: ", ")))"
                }

                // Regular generic type with single type parameter
                let elementType = try parseTypeExpression()
                guard let closingTok = currentToken(),
                    case .punctuation(let closingPunct) = closingTok.type,
                    closingPunct == ")"
                else {
                    let currentValue = currentToken()?.value ?? "EOF"
                    let position =
                        "line \(currentToken()?.line ?? -1), column \(currentToken()?.column ?? -1)"
                    throw ATLParseError.invalidSyntax(
                        "Expected ')' after generic type parameter '\(elementType)', but found '\(currentValue)' at \(position). Context: parsing type '\(typeName)'"
                    )
                }
                advance()  // consume ')'
                return "\(typeName)(\(elementType))"
            }

            return typeName

        default:
            throw ATLParseError.invalidSyntax(
                "Expected type identifier, but found token: '\(typeToken.value)' of type \(typeToken.type)"
            )
        }
    }

    private func parseRule() throws -> any ATLRuleType {
        guard consumeKeyword("rule") else {
            throw ATLParseError.invalidSyntax("Expected 'rule' keyword")
        }

        guard let nameToken = currentToken(),
            case .identifier(let ruleName) = nameToken.type
        else {
            throw ATLParseError.invalidSyntax("Expected rule name")
        }
        advance()

        // Check if this is a called rule (has parameters)
        if currentToken()?.type == .punctuation("(") {
            return try parseCalledRule(name: ruleName)
        } else {
            return try parseMatchedRule(name: ruleName)
        }
    }

    private func parseMatchedRule(name: String) throws -> ATLMatchedRule {
        guard consumePunctuation("{") else {
            throw ATLParseError.invalidSyntax("Expected '{' to start matched rule body")
        }

        // Parse 'from' clause
        guard consumeKeyword("from") else {
            throw ATLParseError.invalidSyntax("Expected 'from' clause in matched rule")
        }
        let sourcePattern = try parseSourcePattern()

        // Parse 'to' clause
        guard consumeKeyword("to") else {
            throw ATLParseError.invalidSyntax("Expected 'to' clause in matched rule")
        }
        var targetPatterns: [ATLTargetPattern] = []

        repeat {
            targetPatterns.append(try parseTargetPattern())

            if currentToken()?.type == .punctuation(",") {
                advance()
            } else {
                break
            }
        } while !isAtEnd() && currentToken()?.type != .punctuation("}")
            && currentToken()?.type != .keyword("do")

        // Parse optional 'do' block (skip for now)
        if currentToken()?.type == .keyword("do") {
            try skipDoBlock()
        }

        guard consumePunctuation("}") else {
            throw ATLParseError.invalidSyntax("Expected '}' to end matched rule")
        }

        return ATLMatchedRule(
            name: name,
            sourcePattern: sourcePattern,
            targetPatterns: targetPatterns
        )
    }

    private func parseCalledRule(name: String) throws -> ATLCalledRule {
        advance()  // consume '('
        let parameters = try parseParameterList()
        guard consumePunctuation(")") else {
            throw ATLParseError.invalidSyntax("Expected ')' after called rule parameters")
        }

        guard consumePunctuation("{") else {
            throw ATLParseError.invalidSyntax("Expected '{' to start called rule body")
        }

        // Parse 'to' clause
        guard consumeKeyword("to") else {
            throw ATLParseError.invalidSyntax("Expected 'to' clause in called rule")
        }
        var targetPatterns: [ATLTargetPattern] = []

        repeat {
            targetPatterns.append(try parseTargetPattern())

            if currentToken()?.type == .punctuation(",") {
                advance()
            } else {
                break
            }
        } while !isAtEnd() && currentToken()?.type != .punctuation("}")

        guard consumePunctuation("}") else {
            throw ATLParseError.invalidSyntax("Expected '}' to end called rule")
        }

        return ATLCalledRule(
            name: name,
            parameters: parameters,
            targetPatterns: targetPatterns,
            body: []  // Simplified for now
        )
    }

    private func parseLazyRule() throws -> ATLCalledRule {
        // Parse rule name
        guard let nameToken = currentToken(),
            case .identifier(let ruleName) = nameToken.type
        else {
            throw ATLParseError.invalidSyntax("Expected lazy rule name")
        }
        advance()

        guard consumePunctuation("{") else {
            throw ATLParseError.invalidSyntax("Expected '{' to start lazy rule body")
        }

        // Parse 'from' clause to extract parameter
        guard consumeKeyword("from") else {
            throw ATLParseError.invalidSyntax("Expected 'from' clause in lazy rule")
        }

        // Parse source pattern (which becomes the parameter)
        guard let varToken = currentToken(),
            case .identifier(let varName) = varToken.type
        else {
            throw ATLParseError.invalidSyntax("Expected source variable name")
        }
        advance()

        guard consumeOperator(":") else {
            throw ATLParseError.invalidSyntax("Expected ':' after source variable name")
        }
        let paramType = try parseTypeExpression()

        let parameter = ATLParameter(name: varName, type: paramType)

        // Parse 'to' clause
        guard consumeKeyword("to") else {
            throw ATLParseError.invalidSyntax("Expected 'to' clause in lazy rule")
        }
        var targetPatterns: [ATLTargetPattern] = []

        repeat {
            targetPatterns.append(try parseTargetPattern())

            if currentToken()?.type == .punctuation(",") {
                advance()
            } else {
                break
            }
        } while !isAtEnd() && currentToken()?.type != .punctuation("}")

        guard consumePunctuation("}") else {
            throw ATLParseError.invalidSyntax("Expected '}' to end lazy rule")
        }

        return ATLCalledRule(
            name: ruleName,
            parameters: [parameter],
            targetPatterns: targetPatterns,
            body: []  // Simplified for now
        )
    }

    private func parseSourcePattern() throws -> ATLSourcePattern {
        guard let varToken = currentToken(),
            case .identifier(let varName) = varToken.type
        else {
            throw ATLParseError.invalidSyntax("Expected source variable name")
        }
        advance()

        guard consumeOperator(":") else {
            throw ATLParseError.invalidSyntax("Expected ':' after source variable name")
        }
        let type = try parseTypeExpression()

        // Parse optional guard condition in parentheses
        var `guard`: (any ATLExpression)? = nil
        if currentToken()?.type == .punctuation("(") {
            advance()
            `guard` = try parseExpression()
            consumePunctuation(")")
        }

        return ATLSourcePattern(
            variableName: varName,
            type: type,
            guard: `guard`
        )
    }

    private func parseTargetPattern() throws -> ATLTargetPattern {
        guard let varToken = currentToken(),
            case .identifier(let varName) = varToken.type
        else {
            throw ATLParseError.invalidSyntax("Expected target variable name")
        }
        advance()

        guard consumeOperator(":") else {
            throw ATLParseError.invalidSyntax("Expected ':' after target variable name")
        }
        let type = try parseTypeExpression()

        var bindings: [ATLPropertyBinding] = []

        if currentToken()?.type == .punctuation("(") {
            advance()

            // Parse property bindings
            while !isAtEnd() && currentToken()?.type != .punctuation(")") {
                guard let propToken = currentToken(),
                    case .identifier(let propName) = propToken.type
                else {
                    throw ATLParseError.invalidSyntax("Expected property name")
                }
                advance()

                guard consumeOperator("<-") else {
                    throw ATLParseError.invalidSyntax(
                        "Expected '<-' after property name '\(propName)'")
                }
                let valueExpression = try parseExpression()

                bindings.append(
                    ATLPropertyBinding(
                        property: propName,
                        expression: valueExpression
                    ))

                if let commaToken = currentToken(), case .punctuation(let punct) = commaToken.type,
                    punct == ","
                {
                    advance()
                } else {
                    break
                }
            }

            guard consumePunctuation(")") else {
                throw ATLParseError.invalidSyntax("Expected ')' after target pattern bindings")
            }
        }

        return ATLTargetPattern(
            variableName: varName,
            type: type,
            bindings: bindings
        )
    }

    private func parseExpression() throws -> any ATLExpression {
        return try parseConditionalExpression()
    }

    private func parseConditionalExpression() throws -> any ATLExpression {
        // Handle if-then-else expressions
        if let token = currentToken(), case .keyword(let keyword) = token.type, keyword == "if" {
            advance()
            let condition = try parseOrExpression()

            guard consumeKeyword("then") else {
                let currentTok = currentToken()?.value ?? "EOF"
                throw ATLParseError.invalidSyntax(
                    "Expected 'then' in conditional expression, found '\(currentTok)'")
            }
            let thenExpr = try parseExpression()

            guard consumeKeyword("else") else {
                let currentTok = currentToken()?.value ?? "EOF"
                throw ATLParseError.invalidSyntax(
                    "Expected 'else' in conditional expression, found '\(currentTok)'")
            }

            // Check if this is an 'else if' chain (no endif for nested if)
            let elseExpr: any ATLExpression
            if let token = currentToken(), case .keyword(let keyword) = token.type, keyword == "if"
            {
                // This is 'else if' - parse as nested conditional WITHOUT consuming endif
                // (the endif belongs to the outermost if)
                advance()  // consume 'if'
                let nestedCondition = try parseOrExpression()

                guard consumeKeyword("then") else {
                    throw ATLParseError.invalidSyntax("Expected 'then' after 'else if' condition")
                }
                let nestedThen = try parseExpression()

                guard consumeKeyword("else") else {
                    throw ATLParseError.invalidSyntax("Expected 'else' in 'else if' chain")
                }
                let nestedElse = try parseExpression()

                elseExpr = ATLConditionalExpression(
                    condition: nestedCondition,
                    thenExpression: nestedThen,
                    elseExpression: nestedElse
                )
            } else {
                // Regular else clause
                elseExpr = try parseExpression()
            }

            guard consumeKeyword("endif") else {
                let currentTok = currentToken()?.value ?? "EOF"
                throw ATLParseError.invalidSyntax(
                    "Expected 'endif' in conditional expression, found '\(currentTok)'")
            }

            return ATLConditionalExpression(
                condition: condition,
                thenExpression: thenExpr,
                elseExpression: elseExpr
            )
        }

        return try parseOrExpression()
    }

    private func parseOrExpression() throws -> any ATLExpression {
        var expr = try parseAndExpression()

        while currentToken()?.type == .keyword("or") {
            advance()
            let right = try parseAndExpression()
            expr = ATLBinaryOperationExpression(
                left: expr,
                operator: .or,
                right: right
            )
        }

        return expr
    }

    private func parseAndExpression() throws -> any ATLExpression {
        var expr = try parseEqualityExpression()

        while currentToken()?.type == .keyword("and") {
            advance()
            let right = try parseEqualityExpression()
            expr = ATLBinaryOperationExpression(
                left: expr,
                operator: .and,
                right: right
            )
        }

        return expr
    }

    private func parseEqualityExpression() throws -> any ATLExpression {
        var expr = try parseRelationalExpression()

        while let token = currentToken(),
            case .`operator`(let op) = token.type,
            ["=", "<>"].contains(op)
        {
            advance()
            let right = try parseRelationalExpression()
            let binOp: ATLBinaryOperator = op == "=" ? .equals : .notEquals
            expr = ATLBinaryOperationExpression(
                left: expr,
                operator: binOp,
                right: right
            )
        }

        return expr
    }

    private func parseRelationalExpression() throws -> any ATLExpression {
        var expr = try parseAdditiveExpression()

        while let token = currentToken(),
            case .`operator`(let op) = token.type,
            ["<", ">", "<=", ">="].contains(op)
        {
            advance()
            let right = try parseAdditiveExpression()
            let binOp: ATLBinaryOperator = {
                switch op {
                case "<": return .lessThan
                case ">": return .greaterThan
                case "<=": return .lessThanOrEqual
                case ">=": return .greaterThanOrEqual
                default: return .lessThan
                }
            }()
            expr = ATLBinaryOperationExpression(
                left: expr,
                operator: binOp,
                right: right
            )
        }

        return expr
    }

    private func parseAdditiveExpression() throws -> any ATLExpression {
        var expr = try parseMultiplicativeExpression()

        while let token = currentToken(),
            case .`operator`(let op) = token.type,
            ["+", "-"].contains(op)
        {
            advance()
            let right = try parseMultiplicativeExpression()
            let binOp: ATLBinaryOperator = op == "+" ? .plus : .minus
            expr = ATLBinaryOperationExpression(
                left: expr,
                operator: binOp,
                right: right
            )
        }

        return expr
    }

    private func parseMultiplicativeExpression() throws -> any ATLExpression {
        var expr = try parseUnaryExpression()

        while let token = currentToken(),
            case .`operator`(let op) = token.type,
            ["*", "/"].contains(op)
        {
            advance()
            let right = try parseUnaryExpression()
            let binOp: ATLBinaryOperator = op == "*" ? .multiply : .divide
            expr = ATLBinaryOperationExpression(
                left: expr,
                operator: binOp,
                right: right
            )
        }

        return expr
    }

    private func parseUnaryExpression() throws -> any ATLExpression {
        // Handle 'not' operator
        if currentToken()?.type == .keyword("not") {
            advance()
            let expr = try parseUnaryExpression()
            return ATLUnaryOperationExpression(
                operator: .not,
                operand: expr
            )
        }

        // Handle unary minus (e.g., -3, -x)
        if let token = currentToken(), case .operator(let op) = token.type, op == "-" {
            advance()
            let expr = try parseUnaryExpression()
            return ATLUnaryOperationExpression(
                operator: .minus,
                operand: expr
            )
        }

        return try parsePostfixExpression()
    }

    private func parsePostfixExpression() throws -> any ATLExpression {
        var expr = try parsePrimaryExpression()

        while !isAtEnd() {
            if let token = currentToken(), case .`operator`(let op) = token.type,
                op == "." || op == "->"
            {
                advance()
                guard let nameToken = currentToken(),
                    case .identifier(let propertyName) = nameToken.type
                else {
                    throw ATLParseError.invalidSyntax("Expected property name after '\(op)'")
                }
                advance()

                // Check for method call
                if let currentTok = currentToken(), case .punctuation(let punct) = currentTok.type,
                    punct == "("
                {
                    advance()

                    // Special handling for iterate method
                    if propertyName == "iterate" {
                        expr = try parseIterateExpression(source: expr)
                    } else {
                        var args: [any ATLExpression] = []

                        while !isAtEnd() && !(currentToken()?.type == .punctuation(")")) {
                            // Check for lambda expression syntax: param | body
                            if let firstToken = currentToken(),
                                case .identifier(let paramName) = firstToken.type
                            {
                                // Look ahead for '|' to detect lambda
                                let savedPosition = position
                                advance()  // consume potential parameter

                                if let barToken = currentToken(),
                                    case .punctuation(let p) = barToken.type, p == "|"
                                {
                                    // This is a lambda expression
                                    advance()  // consume '|'
                                    let body = try parseExpression()
                                    args.append(
                                        ATLLambdaExpression(parameter: paramName, body: body))
                                } else {
                                    // Not a lambda, restore position and parse as regular expression
                                    position = savedPosition
                                    args.append(try parseExpression())
                                }
                            } else {
                                args.append(try parseExpression())
                            }

                            if let commaToken = currentToken(),
                                case .punctuation(let p) = commaToken.type, p == ","
                            {
                                advance()
                            } else {
                                break
                            }
                        }

                        guard consumePunctuation(")") else {
                            throw ATLParseError.invalidSyntax("Expected ')' after method arguments")
                        }

                        expr = ATLMethodCallExpression(
                            receiver: expr,
                            methodName: propertyName,
                            arguments: args
                        )
                    }
                } else {
                    expr = ATLNavigationExpression(source: expr, property: propertyName)
                }
            } else {
                break
            }
        }

        return expr
    }

    private func parsePrimaryExpression() throws -> any ATLExpression {
        guard let token = currentToken() else {
            throw ATLParseError.invalidSyntax("Unexpected end of input")
        }

        switch token.type {
        case .keyword(let kw) where kw == "let":
            // Parse let expression: let varName : Type = initExpr in bodyExpr
            return try parseLetExpression()

        case .stringLiteral(let value):
            advance()
            return ATLLiteralExpression(value: value)

        case .integerLiteral(let value):
            advance()
            return ATLLiteralExpression(value: value)

        case .booleanLiteral(let value):
            advance()
            return ATLLiteralExpression(value: value)

        case .identifier(let name) where name == "Tuple":
            // Parse tuple expression: Tuple{field1 : Type1 = expr1, field2 : Type2 = expr2, ...}
            return try parseTupleExpression()

        case .identifier(let collectionType)
        where collectionType == "Sequence" || collectionType == "Set" || collectionType == "Bag":
            // Handle collection literals like Sequence{}, Set{1, 2, 3}, etc.
            advance()  // consume collection type
            guard consumePunctuation("{") else {
                let currentTok = currentToken()?.value ?? "EOF"
                throw ATLParseError.invalidSyntax(
                    "Expected '{' after collection type '\(collectionType)', but found '\(currentTok)'"
                )
            }

            var elements: [any ATLExpression] = []

            // Parse elements if any
            while !isAtEnd() && !(currentToken()?.type == .punctuation("}")) {
                elements.append(try parseExpression())

                if let commaToken = currentToken(), case .punctuation(let p) = commaToken.type,
                    p == ","
                {
                    advance()
                } else {
                    break
                }
            }

            guard consumePunctuation("}") else {
                throw ATLParseError.invalidSyntax("Expected '}' after collection elements")
            }

            return ATLCollectionLiteralExpression(
                collectionType: collectionType, elements: elements)

        case .identifier(let name):
            advance()

            // Check for metamodel-qualified type: Model!Type
            if let currentTok = currentToken(), case .operator(let op) = currentTok.type, op == "!"
            {
                advance()  // consume '!'
                guard let typeToken = currentToken(),
                    case .identifier(let typeName) = typeToken.type
                else {
                    throw ATLParseError.invalidSyntax(
                        "Expected type name after '!' in metamodel-qualified type")
                }
                advance()  // consume type name
                return ATLTypeLiteralExpression(typeName: "\(name)!\(typeName)")
            }

            // Check for function call
            if let currentTok = currentToken(), case .punctuation(let punct) = currentTok.type,
                punct == "("
            {
                advance()
                var args: [any ATLExpression] = []

                while !isAtEnd() && !(currentToken()?.type == .punctuation(")")) {
                    // Check for lambda expression syntax: param | body
                    if let firstToken = currentToken(),
                        case .identifier(let paramName) = firstToken.type
                    {
                        // Look ahead for '|' to detect lambda
                        let savedPosition = position
                        advance()  // consume potential parameter

                        if let barToken = currentToken(), case .punctuation(let p) = barToken.type,
                            p == "|"
                        {
                            // This is a lambda expression
                            advance()  // consume '|'
                            let body = try parseExpression()
                            args.append(ATLLambdaExpression(parameter: paramName, body: body))
                        } else {
                            // Not a lambda, restore position and parse as regular expression
                            position = savedPosition
                            args.append(try parseExpression())
                        }
                    } else {
                        args.append(try parseExpression())
                    }

                    if let commaToken = currentToken(), case .punctuation(let p) = commaToken.type,
                        p == ","
                    {
                        advance()
                    } else {
                        break
                    }
                }

                guard consumePunctuation(")") else {
                    throw ATLParseError.invalidSyntax("Expected ')' after function arguments")
                }

                return ATLHelperCallExpression(
                    helperName: name,
                    arguments: args
                )
            } else {
                return ATLVariableExpression(name: name)
            }

        case .punctuation("("):
            advance()
            let expr = try parseExpression()
            guard consumePunctuation(")") else {
                throw ATLParseError.invalidSyntax("Expected ')' after parenthesized expression")
            }
            return expr

        case .keyword("self"):
            advance()
            return ATLVariableExpression(name: "self")

        case .keyword("if"):
            // Handle if expressions that weren't caught by parseConditionalExpression
            return try parseConditionalExpression()

        default:
            throw ATLParseError.invalidSyntax("Unexpected token: \(token.value)")
        }
    }

    private func skipDoBlock() throws {
        guard consumeKeyword("do") else {
            throw ATLParseError.invalidSyntax("Expected 'do' keyword")
        }
        guard consumePunctuation("{") else {
            throw ATLParseError.invalidSyntax("Expected '{' after 'do'")
        }

        var braceCount = 1
        while !isAtEnd() && braceCount > 0 {
            if currentToken()?.type == .punctuation("{") {
                braceCount += 1
            } else if currentToken()?.type == .punctuation("}") {
                braceCount -= 1
            }
            advance()
        }

        if braceCount > 0 {
            throw ATLParseError.invalidSyntax("Unclosed 'do' block")
        }
    }

    // MARK: - Helper Methods

    private func currentToken() -> ATLToken? {
        guard position < tokens.count else { return nil }
        return tokens[position]
    }

    private func advance() {
        if position < tokens.count {
            position += 1
        }
    }

    /// Parses an iterate expression with complex syntax.
    ///
    /// Handles: iterate(param; accumulator : Type = defaultValue | body_expression)
    ///
    /// - Parameter source: The source collection expression
    /// - Returns: An ATLIterateExpression
    /// - Throws: ATLParseError if parsing fails
    private func parseIterateExpression(source: any ATLExpression) throws
        -> ATLIterateExpression
    {
        // Parse parameter name
        guard let paramToken = currentToken(),
            case .identifier(let paramName) = paramToken.type
        else {
            throw ATLParseError.invalidSyntax("Expected parameter name in iterate expression")
        }
        advance()

        // Expect semicolon
        guard consumePunctuation(";") else {
            throw ATLParseError.invalidSyntax("Expected ';' after iterate parameter")
        }

        // Parse accumulator name
        guard let accToken = currentToken(),
            case .identifier(let accumulatorName) = accToken.type
        else {
            throw ATLParseError.invalidSyntax("Expected accumulator name in iterate expression")
        }
        advance()

        // Parse optional type annotation
        var accumulatorType: String? = nil
        if consumeOperator(":") {
            accumulatorType = try parseTypeExpression()
        }

        // Expect equals sign
        guard consumeOperator("=") else {
            throw ATLParseError.invalidSyntax("Expected '=' after accumulator declaration")
        }

        // Parse default value expression up to '|'
        let defaultValue = try parseExpressionUntilPipe()

        // Expect pipe
        guard consumePunctuation("|") else {
            throw ATLParseError.invalidSyntax("Expected '|' before iterate body expression")
        }

        // Parse body expression up to ')'
        let body = try parseExpressionUntilCloseParen()

        // Expect closing parenthesis
        guard consumePunctuation(")") else {
            throw ATLParseError.invalidSyntax("Expected ')' after iterate body expression")
        }

        return ATLIterateExpression(
            source: source,
            parameter: paramName,
            accumulator: accumulatorName,
            accumulatorType: accumulatorType,
            defaultValue: defaultValue,
            body: body
        )
    }

    /// Parses an expression until encountering a '|' token.
    ///
    /// - Returns: The parsed expression
    /// - Throws: ATLParseError if parsing fails
    private func parseExpressionUntilPipe() throws -> any ATLExpression {
        // Simple implementation - parse until we see '|'
        // For now, we'll use parseConditionalExpression which handles most cases
        return try parseConditionalExpression()
    }

    /// Parses an expression until encountering a specific keyword.
    ///
    /// - Parameter keyword: The keyword to stop at
    /// - Returns: The parsed expression
    /// - Throws: ATLParseError if parsing fails
    private func parseExpressionUntilKeyword(_ keyword: String) throws -> any ATLExpression {
        // Parse expression, but stop when we encounter the specified keyword
        // Use parseOrExpression to avoid consuming keywords like 'in'
        return try parseOrExpression()
    }

    /// Parses an expression until encountering a ')' token.
    ///
    /// - Returns: The parsed expression
    /// - Throws: ATLParseError if parsing fails
    private func parseExpressionUntilCloseParen() throws -> any ATLExpression {
        // Simple implementation - parse until we see ')'
        // For now, we'll use parseConditionalExpression which handles most cases
        return try parseConditionalExpression()
    }

    private func isAtEnd() -> Bool {
        return position >= tokens.count || currentToken()?.type == .eof
    }

    /// Parses a let expression: let varName : Type = initExpr in bodyExpr
    private func parseLetExpression() throws -> any ATLExpression {
        // Consume 'let' keyword
        guard consumeKeyword("let") else {
            throw ATLParseError.invalidSyntax("Expected 'let' keyword")
        }

        // Parse variable name
        guard let varToken = currentToken(), case .identifier(let varName) = varToken.type else {
            throw ATLParseError.invalidSyntax("Expected variable name after 'let'")
        }
        advance()

        // Parse optional type annotation: : Type
        var varType: String? = nil
        if consumeOperator(":") {
            varType = try parseTypeExpression()
        }

        // Expect '=' for initialisation
        guard consumeOperator("=") else {
            throw ATLParseError.invalidSyntax(
                "Expected '=' after variable declaration in let expression")
        }

        // Parse initialisation expression (stopping before 'in')
        let initExpr = try parseExpressionUntilKeyword("in")

        // Expect 'in' keyword
        guard consumeKeyword("in") else {
            throw ATLParseError.invalidSyntax("Expected 'in' keyword after let initialisation")
        }

        // Parse body expression
        let bodyExpr = try parseExpression()

        return ATLLetExpression(
            variableName: varName,
            variableType: varType,
            initExpression: initExpr,
            inExpression: bodyExpr
        )
    }

    /// Parses a tuple expression: Tuple{field1 : Type1 = expr1, field2 : Type2 = expr2, ...}
    private func parseTupleExpression() throws -> any ATLExpression {
        // Consume 'Tuple' identifier
        advance()

        // Expect '{'
        guard consumePunctuation("{") else {
            throw ATLParseError.invalidSyntax("Expected '{' after 'Tuple'")
        }

        var fields: [(name: String, type: String?, value: any ATLExpression)] = []

        // Parse fields
        while !isAtEnd() && !(currentToken()?.type == .punctuation("}")) {
            // Parse field name
            guard let fieldToken = currentToken(), case .identifier(let fieldName) = fieldToken.type
            else {
                throw ATLParseError.invalidSyntax("Expected field name in tuple")
            }
            advance()

            // Parse optional type annotation: : Type
            var fieldType: String? = nil
            if consumeOperator(":") {
                fieldType = try parseTypeExpression()
            }

            // Expect '=' for field value
            guard consumeOperator("=") else {
                throw ATLParseError.invalidSyntax("Expected '=' after field name in tuple")
            }

            // Parse field value expression
            let fieldValue = try parseExpression()

            fields.append((name: fieldName, type: fieldType, value: fieldValue))

            // Check for comma or end of tuple
            if !consumePunctuation(",") {
                break
            }
        }

        // Expect '}'
        guard consumePunctuation("}") else {
            throw ATLParseError.invalidSyntax("Expected '}' after tuple fields")
        }

        return ATLTupleExpression(fields: fields)
    }

    @discardableResult
    private func consumeKeyword(_ keyword: String) -> Bool {
        guard let token = currentToken(),
            case .keyword(let kw) = token.type,
            kw == keyword
        else {
            return false
        }
        advance()
        return true
    }

    @discardableResult
    private func consumePunctuation(_ punct: String) -> Bool {
        guard let token = currentToken(),
            case .punctuation(let p) = token.type,
            p == punct
        else {
            return false
        }
        advance()
        return true
    }

    @discardableResult
    private func expectPunctuation(_ punct: String) throws -> Bool {
        guard consumePunctuation(punct) else {
            let currentTok = currentToken()?.value ?? "EOF"
            throw ATLParseError.invalidSyntax("Expected '\(punct)' but found '\(currentTok)'")
        }
        return true
    }

    @discardableResult
    private func consumeOperator(_ op: String) -> Bool {
        guard let token = currentToken(),
            case .`operator`(let o) = token.type,
            o == op
        else {
            return false
        }
        advance()
        return true
    }

}
