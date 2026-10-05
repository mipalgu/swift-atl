//
//  ATLParser.swift
//  ATL
//
//  Created by Rene Hexel on 6/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
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
    case metamodelNotFound(String)
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
    private let debug: Bool

    /// Public initializer for ATLParser
    public init(enableDebugging: Bool = false) {
        debug = enableDebugging
    }

    /// Parse an ATL file and return an ATL module
    /// - Returns: An ATLModule representing the parsed ATL content
    /// - Throws: ATLParseError if parsing fails
    ///
    /// - Parameters:
    ///   - url: The URL of the ATL file to parse
    ///   - metamodelRegistry: Packages that `@nsURI` directives and metamodel names may bind to
    public func parse(_ url: URL, metamodelRegistry: ATLMetamodelRegistry = .empty) async throws
        -> ATLModule
    {
        guard let content = try? String(contentsOf: url, encoding: .utf8) else {
            throw ATLParseError.fileNotFound(url.path)
        }

        // Pass the full path for proper relative path resolution
        return try await parseContent(
            content, filename: url.path, metamodelRegistry: metamodelRegistry)
    }

    /// Parse ATL content from a string.
    ///
    /// - Parameters:
    ///   - content: The ATL source content
    ///   - filename: Optional filename for error reporting
    ///   - searchPaths: Optional array of directory paths to search for metamodel files
    ///   - continueAfterErrors: Whether to continue parsing after encountering errors
    ///   - metamodelRegistry: Packages that `@nsURI` directives and metamodel names may bind to
    /// - Returns: An ATLModule representing the parsed ATL content
    /// - Throws: ATLParseError if parsing fails
    public func parseContent(
        _ content: String,
        filename: String = "unknown",
        searchPaths: [String] = [],
        continueAfterErrors: Bool = true,
        metamodelRegistry: ATLMetamodelRegistry = .empty
    ) async throws -> ATLModule {
        let lexer = ATLLexer(content: content)
        let tokens = try lexer.tokenize()
        if let directiveError = lexer.directives.errors.first {
            throw ATLParseError.invalidSyntax(directiveError)
        }
        let parser = ATLSyntaxParser(tokens: tokens, filename: filename)

        var module = try parser.parseModule().withParameters(lexer.directives.parameters)

        // Bind metamodels from @nsURI directives and the registry
        let registryBinding = try bindRegistryMetamodels(
            of: module,
            directives: lexer.directives,
            registry: metamodelRegistry,
            continueAfterErrors: continueAfterErrors
        )
        module = registryBinding.module

        // Load metamodels from @path directives
        let baseURL = URL(fileURLWithPath: filename)
        module = try await loadMetamodels(
            into: module,
            pathDirectives: lexer.pathDirectives,
            relativeTo: baseURL,
            searchPaths: searchPaths,
            continueAfterErrors: continueAfterErrors,
            boundAliases: registryBinding.aliases
        )

        return module
    }

    /// Parses ATL content from a string, collecting diagnostics instead of throwing.
    ///
    /// The parser recovers from problems: after a problem in a declaration it skips
    /// to the next helper, query or rule, and after a problem in a property binding it
    /// skips to the next binding. The module therefore holds every declaration that was
    /// read correctly, and each problem has a diagnostic with a source range and a stable
    /// ``ATLDiagnosticCode``. Metamodels that no package can be found for are reported as
    /// warnings. The method never throws.
    ///
    /// - Parameters:
    ///   - content: The ATL source content.
    ///   - name: The name of the document, which relative metamodel paths are resolved against.
    ///   - metamodelRegistry: Packages that `@nsURI` directives and metamodel names may bind to.
    /// - Returns: The module, diagnostics, outline and tokens of the content.
    public func parseDiagnosing(
        _ content: String,
        name: String,
        metamodelRegistry: ATLMetamodelRegistry = .empty
    ) async -> ATLParseResult {
        let lexer = ATLLexer(content: content)
        let scan = lexer.scanAll()
        var diagnostics: [SourceDiagnostic] = scan.problems.map {
            SourceDiagnostic(
                severity: .error, code: $0.code.rawValue, message: $0.error.diagnosticMessage,
                range: $0.range, document: name)
        }
        for (message, range) in zip(lexer.directives.errors, scan.directiveProblems) {
            diagnostics.append(
                SourceDiagnostic(
                    severity: .error, code: ATLDiagnosticCode.invalidDirective.rawValue,
                    message: message, range: range, document: name))
        }

        let syntax = ATLSyntaxParser(tokens: scan.tokens, filename: name, recovering: true)
        var module = syntax.parseRecovering()
        diagnostics += syntax.diagnostics

        if let parsed = module {
            var bound = parsed.withParameters(lexer.directives.parameters)
            var aliases: Set<String> = []
            if let binding = try? bindRegistryMetamodels(
                of: bound, directives: lexer.directives, registry: metamodelRegistry,
                continueAfterErrors: true)
            {
                bound = binding.module
                aliases = binding.aliases
            }
            if let loaded = try? await loadMetamodels(
                into: bound, pathDirectives: lexer.pathDirectives,
                relativeTo: URL(fileURLWithPath: name), searchPaths: [],
                continueAfterErrors: true, boundAliases: aliases)
            {
                bound = loaded
            }
            diagnostics += unboundMetamodelDiagnostics(
                of: bound, ranges: syntax.metamodelRanges, document: name)
            module = bound
        }

        diagnostics = diagnostics.enumerated().sorted {
            let first = $0.element.range?.start.utf8Offset ?? 0
            let second = $1.element.range?.start.utf8Offset ?? 0
            return first == second ? $0.offset < $1.offset : first < second
        }.map(\.element)

        return ATLParseResult(
            module: module, diagnostics: diagnostics, outline: syntax.outline,
            tokens: ATLSyntax.sourceTokens(of: scan))
    }

    /// Reports the declared metamodels that are still placeholders.
    ///
    /// - Parameters:
    ///   - module: The module after metamodels have been bound and loaded.
    ///   - ranges: The ranges of the metamodel names in the module header.
    ///   - document: The name of the document.
    /// - Returns: A warning for each declared metamodel without a package.
    private func unboundMetamodelDiagnostics(
        of module: ATLModule, ranges: [String: SourceRange], document: String
    ) -> [SourceDiagnostic] {
        var reported: Set<String> = []
        var result: [SourceDiagnostic] = []
        for (alias, package) in Array(module.sourceMetamodels) + Array(module.targetMetamodels) {
            let name = module.declaredMetamodelNames[alias] ?? package.name
            let isPlaceholder =
                package.eClassifiers.isEmpty && package.nsURI == "http://\(name.lowercased())"
            guard isPlaceholder, let range = ranges[name], reported.insert(name).inserted else {
                continue
            }
            result.append(
                SourceDiagnostic(
                    severity: .warning, code: ATLDiagnosticCode.metamodelNotFound.rawValue,
                    message:
                        "No package is available for metamodel '\(name)'; add an @path or @nsURI directive or register the package",
                    range: range, document: document))
        }
        return result
    }

    /// Binds metamodels to packages supplied by a registry.
    ///
    /// A metamodel with an `@nsURI` directive is bound to the package registered
    /// for that namespace URI. A metamodel without any `@path` or `@nsURI`
    /// directive is bound to the registered package of the same name, if there is one.
    ///
    /// - Parameters:
    ///   - module: The parsed module whose metamodels are still placeholders.
    ///   - directives: The directives collected from the module header.
    ///   - registry: The registry to resolve packages from.
    ///   - continueAfterErrors: When `true`, an unresolved `@nsURI` leaves the placeholder in place.
    /// - Returns: The module with bound metamodels and the aliases that were bound.
    /// - Throws: ``ATLParseError/metamodelNotFound(_:)`` for an unresolved `@nsURI` when errors are fatal.
    private func bindRegistryMetamodels(
        of module: ATLModule,
        directives: ATLDirectives,
        registry: ATLMetamodelRegistry,
        continueAfterErrors: Bool
    ) throws -> (module: ATLModule, aliases: Set<String>) {
        var boundAliases: Set<String> = []

        func bound(_ metamodels: OrderedDictionary<String, EPackage>) throws
            -> OrderedDictionary<String, EPackage>
        {
            var result = metamodels
            for (alias, placeholder) in metamodels {
                let name = placeholder.name
                if let nsURI = directives.namespaceURIs[name] {
                    guard let package = registry.package(nsURI: nsURI) else {
                        if continueAfterErrors { continue }
                        throw ATLParseError.metamodelNotFound(
                            "No metamodel is registered for nsURI '\(nsURI)' (metamodel '\(name)')")
                    }
                    result[alias] = package
                    boundAliases.insert(alias)
                } else if directives.paths[name] == nil, let package = registry.package(named: name)
                {
                    result[alias] = package
                    boundAliases.insert(alias)
                }
            }
            return result
        }

        let source = try bound(module.sourceMetamodels)
        let target = try bound(module.targetMetamodels)
        guard !boundAliases.isEmpty else { return (module, boundAliases) }
        return (module.withMetamodels(source: source, target: target), boundAliases)
    }

    /// Loads all metamodels specified by @path directives and replaces dummy metamodels.
    ///
    /// - Parameters:
    ///   - module: The parsed ATL module with dummy metamodels
    ///   - pathDirectives: Dictionary mapping metamodel names to file paths from @path directives
    ///   - baseURL: The URL of the ATL file (for resolving relative paths)
    ///   - searchPaths: Array of directory paths to search for metamodel files
    /// - Returns: The module with real loaded metamodels
    private func loadMetamodels(into module: ATLModule, pathDirectives: [String: String], relativeTo baseURL: URL, searchPaths: [String], continueAfterErrors: Bool = true, boundAliases: Set<String> = []) async throws -> ATLModule {
        if debug {
            print("[ATL] loadMetamodels: Starting metamodel loading")
            print("[ATL]   Path directives: \(pathDirectives)")
            print("[ATL]   Base URL: \(baseURL)")
            print("[ATL]   Search paths: \(searchPaths)")
        }

        var sourceMetamodels = module.sourceMetamodels
        var targetMetamodels = module.targetMetamodels

        if debug {
            print("[ATL]   Source metamodels to load: \(sourceMetamodels.keys.joined(separator: ", "))")
            print("[ATL]   Target metamodels to load: \(targetMetamodels.keys.joined(separator: ", "))")
        }

        // Load source metamodels
        for (alias, metamodel) in sourceMetamodels {
            if boundAliases.contains(alias) { continue }
            if debug {
                print("[ATL] Processing source metamodel '\(alias)' -> '\(metamodel.name)'")
            }

            if let filePath = pathDirectives[metamodel.name] {
                if debug {
                    print("[ATL]   Found path directive: '\(metamodel.name)' -> '\(filePath)'")
                }

                if let loadedPackage = try await loadMetamodel(
                    name: metamodel.name,
                    from: filePath,
                    relativeTo: baseURL,
                    searchPaths: searchPaths
                ) {
                    sourceMetamodels[alias] = loadedPackage
                } else {
                    let errorMsg = "Failed to load source metamodel '\(metamodel.name)' from '\(filePath)'. Check that the file exists and the metamodel path is correct."
                    if continueAfterErrors {
                        if debug {
                            print("[ATL] Warning: \(errorMsg), using fallback")
                        }
                        // Keep the original metamodel as fallback for tests and synthetic scenarios
                    } else {
                        throw ATLParseError.metamodelNotFound(errorMsg)
                    }
                }
            } else {
                let errorMsg = "No @path directive found for source metamodel '\(metamodel.name)'. Add a @path directive like: -- @path \(metamodel.name)=/path/to/\(metamodel.name).ecore"
                if continueAfterErrors {
                    if debug {
                        print("[ATL] Warning: \(errorMsg), using fallback")
                    }
                    // Keep the original metamodel as fallback for tests and synthetic scenarios
                } else {
                    throw ATLParseError.metamodelNotFound(errorMsg)
                }
            }
        }

        // Load target metamodels
        for (alias, metamodel) in targetMetamodels {
            if boundAliases.contains(alias) { continue }
            if debug {
                print("[ATL] Processing target metamodel '\(alias)' -> '\(metamodel.name)'")
            }

            if let filePath = pathDirectives[metamodel.name] {
                if debug {
                    print("[ATL]   Found path directive: '\(metamodel.name)' -> '\(filePath)'")
                }

                if let loadedPackage = try await loadMetamodel(
                    name: metamodel.name,
                    from: filePath,
                    relativeTo: baseURL,
                    searchPaths: searchPaths
                ) {
                    targetMetamodels[alias] = loadedPackage
                } else {
                    let errorMsg = "Failed to load target metamodel '\(metamodel.name)' from '\(filePath)'. Check that the file exists and the metamodel path is correct."
                    if continueAfterErrors {
                        if debug {
                            print("[ATL] Warning: \(errorMsg), using fallback")
                        }
                        // Keep the original metamodel as fallback for tests and synthetic scenarios
                    } else {
                        throw ATLParseError.metamodelNotFound(errorMsg)
                    }
                }
            } else {
                let errorMsg = "No @path directive found for target metamodel '\(metamodel.name)'. Add a @path directive like: -- @path \(metamodel.name)=/path/to/\(metamodel.name).ecore"
                if continueAfterErrors {
                    if debug {
                        print("[ATL] Warning: \(errorMsg), using fallback")
                    }
                    // Keep the original metamodel as fallback for tests and synthetic scenarios
                } else {
                    throw ATLParseError.metamodelNotFound(errorMsg)
                }
            }
        }

        // Validate loaded metamodels and provide warnings for fallback instances
        if debug {
            print("[ATL] Metamodel loading summary:")
            for (alias, metamodel) in sourceMetamodels {
                if metamodel.nsURI.isEmpty || metamodel.nsURI == "http://\(metamodel.name.lowercased())" || metamodel.eClassifiers.isEmpty {
                    print("[ATL] WARNING: Source metamodel '\(alias)' (\(metamodel.name)) appears to be a fallback instance")
                    print("[ATL]   nsURI: '\(metamodel.nsURI)' (expected: actual metamodel URI)")
                    print("[ATL]   Classifiers: \(metamodel.eClassifiers.count) (expected: > 0)")
                    print("[ATL]   This may cause transformation failures. Check @path directive and file existence.")
                } else {
                    print("[ATL] ✓ Source metamodel '\(alias)' (\(metamodel.name)) loaded successfully")
                }
            }
            for (alias, metamodel) in targetMetamodels {
                if metamodel.nsURI.isEmpty || metamodel.nsURI == "http://\(metamodel.name.lowercased())" || metamodel.eClassifiers.isEmpty {
                    print("[ATL] WARNING: Target metamodel '\(alias)' (\(metamodel.name)) appears to be a fallback instance")
                    print("[ATL]   nsURI: '\(metamodel.nsURI)' (expected: actual metamodel URI)")
                    print("[ATL]   Classifiers: \(metamodel.eClassifiers.count) (expected: > 0)")
                    print("[ATL]   This may cause transformation failures. Check @path directive and file existence.")
                } else {
                    print("[ATL] ✓ Target metamodel '\(alias)' (\(metamodel.name)) loaded successfully")
                }
            }
        }

        // Return new module with loaded metamodels
        return module.withMetamodels(source: sourceMetamodels, target: targetMetamodels)
    }

    /// Loads a metamodel from an Ecore file.
    ///
    /// - Parameters:
    ///   - metamodelName: The name of the metamodel (from @path directive)
    ///   - filePath: The file path from the @path directive
    ///   - baseURL: The URL of the ATL file (for resolving relative paths)
    ///   - searchPaths: Array of directory paths to search for metamodel files
    /// - Returns: The loaded EPackage, or nil if loading fails
    private func loadMetamodel(name metamodelName: String, from filePath: String, relativeTo baseURL: URL, searchPaths: [String]) async throws -> EPackage? {
        if debug {
            print("[ATL] loadMetamodel: Loading '\(metamodelName)' from '\(filePath)'")
            print("[ATL]   Base URL: \(baseURL)")
            print("[ATL]   Search paths: \(searchPaths)")
        }

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
                if debug {
                    print("[ATL]     Workspace-relative candidate: \(candidate.path)")
                }
            }
        } else {
            // Regular relative path - resolve relative to ATL file first
            let base = baseURL.deletingLastPathComponent()
            let candidate = base.appendingPathComponent(filePath)
            candidateURLs.append(candidate)
            if debug {
                print("[ATL]     Relative candidate: \(candidate.path)")
            }
            // Also try each search path as a fallback
            for searchPath in searchPaths {
                let fallbackCandidate = URL(fileURLWithPath: searchPath)
                    .appendingPathComponent(filePath)
                candidateURLs.append(fallbackCandidate)
                if debug {
                    print("[ATL]     Search path fallback candidate: \(fallbackCandidate.path)")
                }
            }
        }

        // Try each candidate URL
        if debug {
            print("[ATL]   Trying \(candidateURLs.count) candidate URL(s)")
        }

        for candidateURL in candidateURLs {
            let resolved = candidateURL.standardizedFileURL

            if debug {
                print("[ATL]     Checking: \(resolved.path)")
            }

            guard FileManager.default.fileExists(atPath: resolved.path) else {
                if debug {
                    print("[ATL]       File not found")
                }
                continue
            }

            if debug {
                print("[ATL]       File exists, attempting to load")
            }

            do {
                // Use EPackage initializer to load the .ecore file
                let package = try await EPackage(url: resolved, enableDebugging: debug)
                if debug {
                    print("[ATL] Loaded metamodel '\(metamodelName)' from: \(resolved.path)")
                    print("[ATL]   Package name: '\(package.name)', nsURI: '\(package.nsURI)', nsPrefix: '\(package.nsPrefix)')")
                    print("[ATL]   Package has \(package.eClassifiers.count) classifiers")
                }

                // Validate that the package was loaded correctly
                if debug && ( package.nsURI.isEmpty || package.nsURI == "http://\(package.name.lowercased())" ) {
                    print("[ATL] Warning: Package nsURI appears to be fallback value, may indicate parsing failure")
                }

                if debug && package.eClassifiers.isEmpty {
                    print("[ATL] Warning: Package has no classifiers, may indicate parsing failure")
                }

                return package
            } catch {
                if debug {
                    print("[ATL] Failed to load metamodel from: \(resolved.path) - \(error)")
                }
                // Try next candidate if this one fails to parse
                continue
            }
        }

        // None of the candidates worked
        if debug {
            print("[ATL] loadMetamodel: No valid candidates found for '\(metamodelName)'")
        }
        return nil
    }
}

// MARK: - ATL Syntax Parser

/// A declaration header that the outline records for a declaration being parsed.
private struct ATLOutlineHeader {
    var kind: String
    var name: String
    var selectionRange: SourceRange
    var contextType: String?
    var returnType: String?
    var parameters: [ATLParameter] = []
    var children: [OutlineNode] = []
}

/// ATL syntax parser
///
/// In its default mode the parser stops at the first problem and throws. In its
/// recovering mode it records a diagnostic for each problem, skips to the next
/// declaration or binding and carries on.
private class ATLSyntaxParser {
    private let tokens: [ATLToken]
    private var position: Int = 0
    private let filename: String
    private let recovering: Bool

    /// The diagnostics recorded while recovering from problems.
    private(set) var diagnostics: [SourceDiagnostic] = []

    /// The outline of the declarations that were parsed.
    private(set) var outline: [OutlineNode] = []

    /// The ranges of the metamodel names in the `create` statement.
    private(set) var metamodelRanges: [String: SourceRange] = [:]

    private var pendingOutline: ATLOutlineHeader?
    private var errorRangeOverride: SourceRange?

    init(tokens: [ATLToken], filename: String, recovering: Bool = false) {
        self.tokens = tokens
        self.filename = filename
        self.recovering = recovering
    }

    /// Parses a module and stops at the first problem.
    ///
    /// - Returns: The parsed module.
    /// - Throws: ``ATLParseError`` for the first problem found.
    func parseModule() throws -> ATLModule {
        guard let module = try parseModuleBody() else {
            throw ATLParseError.missingModule
        }
        return module
    }

    /// Parses a module, recording each problem as a diagnostic and carrying on.
    ///
    /// - Returns: The module, or `nil` when the source has no usable module declaration.
    func parseRecovering() -> ATLModule? {
        // Recovery handles every error, so this never throws
        (try? parseModuleBody()) ?? nil
    }

    private func parseModuleBody() throws -> ATLModule? {
        let firstIndex = position
        var moduleName: String?
        var moduleSelection: SourceRange?

        let headerStart = position
        do {
            if let name = try parseModuleDeclaration() {
                moduleName = name
                moduleSelection = tokens[headerStart + 1].range
            } else if recovering {
                record(.missingModule, at: headerStart)
            } else {
                throw ATLParseError.missingModule
            }
        } catch let error as ATLParseError {
            guard recovering else { throw error }
            record(error, at: position)
            recoverToDeclaration(startedAt: headerStart)
        }

        var sourceMetamodels: OrderedDictionary<String, EPackage> = [:]
        var targetMetamodels: OrderedDictionary<String, EPackage> = [:]
        var helpers: OrderedDictionary<String, any ATLHelperType> = [:]
        var helperOverloads: OrderedDictionary<String, [any ATLHelperType]> = [:]
        var matchedRules: [ATLMatchedRule] = []
        var calledRules: OrderedDictionary<String, ATLCalledRule> = [:]
        var declarationNodes: [OutlineNode] = []

        // Parse create statement if present
        if currentToken()?.type == .keyword("create") {
            let createStart = position
            do {
                let (source, target) = try parseCreateStatement()
                sourceMetamodels = source
                targetMetamodels = target
            } catch let error as ATLParseError {
                guard recovering else { throw error }
                record(error, at: position)
                recoverToDeclaration(startedAt: createStart)
            }
        }

        // Parse module contents
        while !isAtEnd() {
            let declarationStart = position
            pendingOutline = nil
            do {
                if currentToken()?.type == .keyword("helper") {
                    let helper = try parseHelper()
                    helpers[helper.name] = helper
                    helperOverloads[helper.name, default: []].removeAll {
                        $0.contextType == helper.contextType
                    }
                    helperOverloads[helper.name, default: []].append(helper)
                } else if startsRuleDeclaration() {
                    let rule = try parseRuleDeclaration()
                    if let matchedRule = rule as? ATLMatchedRule {
                        matchedRules.append(matchedRule)
                    } else if let calledRule = rule as? ATLCalledRule {
                        calledRules[calledRule.name] = calledRule
                    }
                } else if currentToken()?.type == .keyword("query") {
                    let helper = try parseQuery()
                    helpers[helper.name] = helper
                } else if let token = currentToken(),
                    token.type == .identifier(ATLLanguage.UnsupportedKeyword.uses)
                {
                    throw unsupported(
                        "Library imports ('uses') are not supported at \(describe(token))",
                        at: position)
                } else {
                    try skipUnexpectedTokens()
                    continue
                }
                appendOutlineNode(startedAt: declarationStart, to: &declarationNodes)
            } catch let error as ATLParseError {
                guard recovering else { throw error }
                record(error, at: position)
                recoverToDeclaration(startedAt: declarationStart)
                appendOutlineNode(startedAt: declarationStart, to: &declarationNodes)
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

        let moduleRange = coveredRange(from: firstIndex)
        guard let moduleName, let moduleSelection else {
            outline = declarationNodes
            return nil
        }
        outline = [
            OutlineNode(
                id: Self.outlineIdentifier(kind: ATLOutlineKind.module, name: moduleName),
                kind: ATLOutlineKind.module, name: moduleName, range: moduleRange,
                selectionRange: moduleSelection, children: declarationNodes)
        ]

        return ATLModule(
            name: moduleName,
            sourceMetamodels: sourceMetamodels,
            targetMetamodels: targetMetamodels,
            helpers: helpers,
            matchedRules: matchedRules,
            calledRules: calledRules,
            helperOverloads: helperOverloads,
            origin: SourceOrigin(moduleRange)
        )
    }

    private func parseModuleDeclaration() throws -> String? {
        if let token = currentToken(), token.type == .identifier(ATLLanguage.UnsupportedKeyword.library) {
            throw unsupported(
                "Libraries ('library') are not supported at \(describe(token))", at: position)
        }
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
            if alias == ATLLanguage.UnsupportedKeyword.refining {
                throw unsupported(
                    "Refining mode ('refining') is not supported at \(describe(token))",
                    at: position)
            }
            advance()
            guard consumeOperator(":") else {
                throw ATLParseError.invalidSyntax("Expected ':' after the model name '\(alias)'")
            }

            guard let mmToken = currentToken(),
                case .identifier(let metamodelName) = mmToken.type
            else {
                throw ATLParseError.invalidSyntax("Expected metamodel name")
            }
            metamodelRanges[metamodelName] = metamodelRanges[metamodelName] ?? mmToken.range
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
                guard consumeOperator(":") else {
                    throw ATLParseError.invalidSyntax(
                        "Expected ':' after the model name '\(alias)'")
                }

                guard let mmToken = currentToken(),
                    case .identifier(let metamodelName) = mmToken.type
                else {
                    throw ATLParseError.invalidSyntax("Expected metamodel name")
                }
                metamodelRanges[metamodelName] = metamodelRanges[metamodelName] ?? mmToken.range
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
        let start = position
        guard consumeKeyword("query") else {
            throw ATLParseError.invalidSyntax("Expected 'query' keyword")
        }

        guard let nameToken = currentToken(),
            case .identifier(let name) = nameToken.type
        else {
            throw ATLParseError.invalidSyntax("Expected query name")
        }
        pendingOutline = ATLOutlineHeader(
            kind: ATLOutlineKind.query, name: name, selectionRange: nameToken.range)
        advance()

        consumeOperator("=")

        let bodyExpression = try parseExpression()

        consumePunctuation(";")

        return ATLHelperWrapper(
            name: name,
            contextType: nil,
            returnType: "OclAny",
            parameters: [],
            body: bodyExpression,
            origin: origin(from: start)
        )
    }

    private func parseHelper() throws -> any ATLHelperType {
        let start = position
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
        pendingOutline = ATLOutlineHeader(
            kind: ATLOutlineKind.helper, name: name, selectionRange: nameToken.range,
            contextType: contextType)
        advance()

        // Parse parameters if present
        var parameters: [ATLParameter] = []
        var hasParameterList = false
        if consumePunctuation("(") {
            hasParameterList = true
            parameters = try parseParameterList()
            guard consumePunctuation(")") else {
                throw ATLParseError.invalidSyntax("Expected ')' after the helper parameters")
            }
        }
        pendingOutline?.kind = hasParameterList ? ATLOutlineKind.helper : ATLOutlineKind.attribute

        // Parse return type - consume colon
        guard consumeOperator(":") else {
            throw ATLParseError.invalidSyntax("Expected ':' before return type")
        }
        let returnType = try parseTypeExpression()
        pendingOutline?.returnType = returnType

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
            body: bodyExpression,
            isAttribute: !hasParameterList,
            origin: origin(from: start)
        )
    }

    private func parseParameterList() throws -> [ATLParameter] {
        var parameters: [ATLParameter] = []

        while !isAtEnd() && currentToken()?.type != .punctuation(")") {
            let start = position
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

            parameters.append(
                ATLParameter(name: paramName, type: paramType, origin: origin(from: start)))

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

    private func parseSourcePattern() throws -> ATLSourcePattern {
        let start = position
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
            guard consumePunctuation(")") else {
                throw ATLParseError.invalidSyntax("Expected ')' after the source pattern guard")
            }
        }

        let range = coveredRange(from: start)
        addOutlineChild(
            kind: ATLOutlineKind.sourcePattern, name: varName, type: type, range: range,
            selection: varToken.range)
        return ATLSourcePattern(
            variableName: varName,
            type: type,
            guard: `guard`,
            origin: SourceOrigin(range)
        )
    }

    private func parseTargetPattern() throws -> ATLTargetPattern {
        let start = position
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

        if let token = currentToken(), case .identifier(let word) = token.type,
            word == ATLLanguage.UnsupportedKeyword.distinct
                || word == ATLLanguage.UnsupportedKeyword.foreach
        {
            throw unsupported(
                "Iterated target patterns ('\(word)') are not supported at \(describe(token))",
                at: position)
        }

        var bindings: [ATLPropertyBinding] = []

        if currentToken()?.type == .punctuation("(") {
            advance()

            // Parse property bindings
            while !isAtEnd() && currentToken()?.type != .punctuation(")") {
                let bindingStart = position
                do {
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
                            expression: valueExpression,
                            origin: origin(from: bindingStart)
                        ))
                } catch let error as ATLParseError {
                    guard recovering, recoverBinding(from: bindingStart, after: error) else {
                        throw error
                    }
                    continue
                }

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

        let range = coveredRange(from: start)
        addOutlineChild(
            kind: ATLOutlineKind.targetPattern, name: varName, type: type, range: range,
            selection: varToken.range)
        return ATLTargetPattern(
            variableName: varName,
            type: type,
            bindings: bindings,
            origin: SourceOrigin(range)
        )
    }

    private func parseExpression() throws -> any ATLExpression {
        return try parseConditionalExpression()
    }

    private func parseConditionalExpression() throws -> any ATLExpression {
        let start = position
        // Handle if-then-else expressions
        if let token = currentToken(), case .keyword(let keyword) = token.type, keyword == "if" {
            advance()
            let condition = try parseImpliesExpression()

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

            let elseExpr = try parseExpression()

            // A chain written as `else if ... else ... endif` shares one
            // `endif`; a fully nested conditional has its own.
            if elseExpr is ATLConditionalExpression {
                _ = consumeKeyword("endif")
            } else {
                guard consumeKeyword("endif") else {
                    let currentTok = currentToken()?.value ?? "EOF"
                    throw ATLParseError.invalidSyntax(
                        "Expected 'endif' in conditional expression, found '\(currentTok)'")
                }
            }

            return ATLConditionalExpression(
                condition: condition,
                thenExpression: thenExpr,
                elseExpression: elseExpr,
                origin: origin(from: start)
            )
        }

        return try parseImpliesExpression()
    }

    /// Parses the lowest-precedence boolean level: `a implies b`.
    private func parseImpliesExpression() throws -> any ATLExpression {
        let start = position
        var expr = try parseDisjunctionExpression()

        while consumeInfixKeyword(.implies) {
            let right = try parseDisjunctionExpression()
            expr = ATLBinaryExpression(
                left: expr, operator: .implies, right: right, origin: origin(from: start))
        }

        return expr
    }

    /// Parses `a or b` and `a xor b`, which bind more weakly than `and`.
    private func parseDisjunctionExpression() throws -> any ATLExpression {
        let start = position
        var expr = try parseAndExpression()

        while true {
            let binOp: ATLBinaryOperator
            if currentToken()?.type == .keyword("or") {
                advance()
                binOp = .or
            } else if consumeInfixKeyword(.xor) {
                binOp = .xor
            } else {
                break
            }
            let right = try parseAndExpression()
            expr = ATLBinaryExpression(
                left: expr, operator: binOp, right: right, origin: origin(from: start))
        }

        return expr
    }

    private func parseAndExpression() throws -> any ATLExpression {
        let start = position
        var expr = try parseEqualityExpression()

        while currentToken()?.type == .keyword("and") {
            advance()
            let right = try parseEqualityExpression()
            expr = ATLBinaryExpression(
                left: expr,
                operator: .and,
                right: right,
                origin: origin(from: start)
            )
        }

        return expr
    }

    private func parseEqualityExpression() throws -> any ATLExpression {
        let start = position
        var expr = try parseRelationalExpression()

        while let token = currentToken(),
            case .`operator`(let op) = token.type,
            ["=", "<>"].contains(op)
        {
            advance()
            let right = try parseRelationalExpression()
            let binOp: ATLBinaryOperator = op == "=" ? .equals : .notEquals
            expr = ATLBinaryExpression(
                left: expr,
                operator: binOp,
                right: right,
                origin: origin(from: start)
            )
        }

        return expr
    }

    private func parseRelationalExpression() throws -> any ATLExpression {
        let start = position
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
            expr = ATLBinaryExpression(
                left: expr,
                operator: binOp,
                right: right,
                origin: origin(from: start)
            )
        }

        return expr
    }

    private func parseAdditiveExpression() throws -> any ATLExpression {
        let start = position
        var expr = try parseMultiplicativeExpression()

        while let token = currentToken(),
            case .`operator`(let op) = token.type,
            ["+", "-"].contains(op)
        {
            advance()
            let right = try parseMultiplicativeExpression()
            let binOp: ATLBinaryOperator = op == "+" ? .plus : .minus
            expr = ATLBinaryExpression(
                left: expr,
                operator: binOp,
                right: right,
                origin: origin(from: start)
            )
        }

        return expr
    }

    private func parseMultiplicativeExpression() throws -> any ATLExpression {
        let start = position
        var expr = try parseUnaryExpression()

        while true {
            let binOp: ATLBinaryOperator
            if let token = currentToken(), case .`operator`(let op) = token.type,
                ["*", "/"].contains(op)
            {
                advance()
                binOp = op == "*" ? .multiply : .divide
            } else if consumeInfixKeyword(.div) {
                binOp = .integerDivide
            } else if consumeInfixKeyword(.mod) {
                binOp = .modulo
            } else {
                break
            }
            let right = try parseUnaryExpression()
            expr = ATLBinaryExpression(
                left: expr,
                operator: binOp,
                right: right,
                origin: origin(from: start)
            )
        }

        return expr
    }

    private func parseUnaryExpression() throws -> any ATLExpression {
        let start = position
        // Handle 'not' operator
        if currentToken()?.type == .keyword("not") {
            advance()
            let expr = try parseUnaryExpression()
            return ATLUnaryExpression(
                operator: .not,
                operand: expr,
                origin: origin(from: start)
            )
        }

        // Handle unary minus (e.g., -3, -x)
        if let token = currentToken(), case .operator(let op) = token.type, op == "-" {
            advance()
            let expr = try parseUnaryExpression()
            return ATLUnaryExpression(
                operator: .minus,
                operand: expr,
                origin: origin(from: start)
            )
        }

        return try parsePostfixExpression()
    }

    private func parsePostfixExpression() throws -> any ATLExpression {
        let start = position
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
                        expr = try parseIterateExpression(source: expr, start: start)
                    } else {
                        var args: [any ATLExpression] = []

                        while !isAtEnd() && !(currentToken()?.type == .punctuation(")")) {
                            // Check for lambda expression syntax: param | body
                            if let lambda = try parseLambdaIfPresent() {
                                args.append(lambda)
                            } else if let firstToken = currentToken(),
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
                                        ATLLambdaExpression(
                                            parameter: paramName, body: body,
                                            origin: origin(from: savedPosition)))
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
                            arguments: args,
                            origin: origin(from: start)
                        )
                    }
                } else {
                    expr = ATLNavigationExpression(
                        source: expr, property: propertyName, origin: origin(from: start))
                }
            } else {
                break
            }
        }

        return expr
    }

    private func parsePrimaryExpression() throws -> any ATLExpression {
        let start = position
        guard let token = currentToken() else {
            throw ATLParseError.invalidSyntax("Unexpected end of input")
        }

        switch token.type {
        case .keyword(let kw) where kw == "let":
            // Parse let expression: let varName : Type = initExpr in bodyExpr
            return try parseLetExpression()

        case .stringLiteral(let value):
            advance()
            return ATLLiteralExpression(value: value, origin: origin(from: start))

        case .integerLiteral(let value):
            advance()
            return ATLLiteralExpression(value: value, origin: origin(from: start))

        case .realLiteral(let value):
            advance()
            return ATLLiteralExpression(value: value, origin: origin(from: start))

        case .enumLiteral(let name):
            advance()
            return ATLEnumLiteralExpression(name: name, origin: origin(from: start))

        case .keyword(let typeName) where ATLLanguage.PrimitiveType(rawValue: typeName) != nil:
            advance()
            return ATLTypeLiteralExpression(typeName: typeName, origin: origin(from: start))

        case .identifier(let name)
        where name == ATLLanguage.UndefinedLiteral.oclUndefined
            || name == ATLLanguage.UndefinedLiteral.null:
            advance()
            return ATLLiteralExpression(value: nil, origin: origin(from: start))

        case .booleanLiteral(let value):
            advance()
            return ATLLiteralExpression(value: value, origin: origin(from: start))

        case .identifier(let name) where name == "Tuple":
            // Parse tuple expression: Tuple{field1 : Type1 = expr1, field2 : Type2 = expr2, ...}
            return try parseTupleExpression()

        case .identifier(let name)
        where ATLLanguage.genericTypeNames.contains(name) && isNextPunctuation("("):
            // A generic type used as a value, as in `oclIsKindOf(Sequence(Integer))`
            return ATLTypeLiteralExpression(
                typeName: try parseTypeExpression(), origin: origin(from: start))

        case .identifier(let collectionType)
        where ATLCollectionKind(rawValue: collectionType) != nil:
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
                collectionType: collectionType, elements: elements,
                origin: origin(from: start))

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
                return ATLTypeLiteralExpression(
                    typeName: "\(name)!\(typeName)", origin: origin(from: start))
            }

            // Check for function call
            if let currentTok = currentToken(), case .punctuation(let punct) = currentTok.type,
                punct == "("
            {
                advance()
                var args: [any ATLExpression] = []

                while !isAtEnd() && !(currentToken()?.type == .punctuation(")")) {
                    // Check for lambda expression syntax: param | body
                    if let lambda = try parseLambdaIfPresent() {
                        args.append(lambda)
                    } else if let firstToken = currentToken(),
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
                            args.append(ATLLambdaExpression(
                                            parameter: paramName, body: body,
                                            origin: origin(from: savedPosition)))
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
                    arguments: args,
                    origin: origin(from: start)
                )
            } else {
                return ATLVariableExpression(name: name, origin: origin(from: start))
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
            return ATLVariableExpression(name: "self", origin: origin(from: start))

        case .keyword("if"):
            // Handle if expressions that weren't caught by parseConditionalExpression
            return try parseConditionalExpression()

        default:
            throw ATLParseError.invalidSyntax("Unexpected token: \(token.value)")
        }
    }

    // MARK: - Helper Methods

    // MARK: - Origins, Diagnostics and Outline

    /// The range from a token to the last token that has been consumed.
    ///
    /// - Parameter startIndex: The index of the first token of the range.
    /// - Returns: The range, empty at the first token if nothing has been consumed since.
    private func coveredRange(from startIndex: Int) -> SourceRange {
        let first = tokens[min(startIndex, tokens.count - 1)]
        guard position > startIndex else { return SourceRange(start: first.start, end: first.start) }
        let last = tokens[min(position - 1, tokens.count - 1)]
        return SourceRange(start: first.start, end: max(first.end, last.end))
    }

    /// The origin of a node that started at a token and ends at the last consumed token.
    ///
    /// - Parameter startIndex: The index of the first token of the node.
    /// - Returns: The origin covering the node.
    private func origin(from startIndex: Int) -> SourceOrigin {
        SourceOrigin(coveredRange(from: startIndex))
    }

    /// Describes where a token is for use in messages.
    private func describe(_ token: ATLToken) -> String {
        "line \(token.line), column \(token.column)"
    }

    /// Creates an unsupported-construct error that is reported at a token.
    ///
    /// - Parameters:
    ///   - message: The description of the construct.
    ///   - index: The index of the token that starts the construct.
    /// - Returns: The error to throw.
    private func unsupported(_ message: String, at index: Int) -> ATLParseError {
        errorRangeOverride = tokens[min(index, tokens.count - 1)].range
        return .unsupportedConstruct(message)
    }

    /// Records a problem as a diagnostic at a token.
    ///
    /// A problem at an invalid token is not recorded, because the lexical problem
    /// that made the token invalid has been reported already.
    ///
    /// - Parameters:
    ///   - error: The problem.
    ///   - index: The index of the token at which the problem was found.
    private func record(_ error: ATLParseError, at index: Int) {
        if let diagnostic = diagnostic(for: error, at: index) { diagnostics.append(diagnostic) }
    }

    private func diagnostic(for error: ATLParseError, at index: Int) -> SourceDiagnostic? {
        let token = tokens[min(index, tokens.count - 1)]
        let override = errorRangeOverride
        errorRangeOverride = nil
        if case .invalid = token.type, override == nil { return nil }
        return SourceDiagnostic(
            severity: .error, code: ATLDiagnosticCode.code(for: error).rawValue,
            message: error.diagnosticMessage, range: override ?? token.range,
            document: filename)
    }

    /// Whether the current token starts a helper, a query or a rule.
    private func startsDeclaration() -> Bool {
        guard let token = currentToken() else { return false }
        return token.type == .keyword("helper") || token.type == .keyword("query")
            || startsRuleDeclaration()
    }

    /// Skips the rest of a declaration that could not be parsed.
    ///
    /// Tokens are skipped up to the next helper, query or rule, or up to the brace
    /// that closes the declaration. Braces are counted from the start of the
    /// declaration, so a failure inside a rule body skips the rest of that body.
    ///
    /// - Parameter startIndex: The index of the first token of the failed declaration.
    private func recoverToDeclaration(startedAt startIndex: Int) {
        var depth = 0
        for token in tokens[startIndex..<min(position, tokens.count)] {
            if token.type == .punctuation("{") { depth += 1 }
            if token.type == .punctuation("}") { depth -= 1 }
        }
        if position == startIndex { advance() }
        while !isAtEnd() {
            if startsDeclaration() { break }
            if currentToken()?.type == .punctuation("{") { depth += 1 }
            if currentToken()?.type == .punctuation("}") {
                depth -= 1
                advance()
                if depth <= 0 { break }
                continue
            }
            advance()
        }
    }

    /// Handles tokens that cannot start a declaration.
    ///
    /// While recovering, a run of such tokens is reported as a single diagnostic.
    ///
    /// - Throws: ``ATLParseError/unexpectedToken(_:)`` when not recovering.
    private func skipUnexpectedTokens() throws {
        guard let first = currentToken() else { return }
        guard recovering else {
            throw ATLParseError.unexpectedToken(
                "Unexpected token '\(first.value)' at \(describe(first))")
        }
        let startIndex = position
        while !isAtEnd() && !startsDeclaration() { advance() }
        let range = coveredRange(from: startIndex)
        let invalidOnly = tokens[startIndex..<position].allSatisfy {
            if case .invalid = $0.type { return true }
            return false
        }
        guard !invalidOnly else { return }
        diagnostics.append(
            SourceDiagnostic(
                severity: .error, code: ATLDiagnosticCode.unexpectedToken.rawValue,
                message: "Unexpected token '\(first.value)' at \(describe(first))", range: range,
                document: filename))
    }

    /// Skips the rest of a property binding that could not be parsed.
    ///
    /// Tokens are skipped to the next comma or to the closing parenthesis of the
    /// binding list, whichever comes first outside nested brackets. The problem is
    /// recorded only when such a point is found.
    ///
    /// - Parameters:
    ///   - error: The problem found in the binding.
    ///   - startIndex: The index of the first token of the binding.
    /// - Returns: `true` if parsing can carry on after the binding.
    private func recoverBinding(from startIndex: Int, after error: ATLParseError) -> Bool {
        let errorIndex = position
        let pending = diagnostic(for: error, at: errorIndex)
        var depth = 0
        for token in tokens[startIndex..<min(errorIndex, tokens.count)] {
            depth += Self.bracketChange(of: token)
        }
        depth = max(depth, 0)
        while !isAtEnd() && !startsDeclaration() {
            guard let token = currentToken() else { break }
            let change = Self.bracketChange(of: token)
            if change < 0 && depth == 0 {
                guard token.type == .punctuation(")") else { break }
                if let pending { diagnostics.append(pending) }
                return true
            }
            if token.type == .punctuation(",") && depth == 0 {
                advance()
                if let pending { diagnostics.append(pending) }
                return true
            }
            depth += change
            advance()
        }
        position = errorIndex
        return false
    }

    private static func bracketChange(of token: ATLToken) -> Int {
        guard case .punctuation(let text) = token.type else { return 0 }
        switch text {
        case "(", "[", "{": return 1
        case ")", "]", "}": return -1
        default: return 0
        }
    }

    /// Records the outline node of the declaration that was just parsed or abandoned.
    ///
    /// - Parameters:
    ///   - startIndex: The index of the first token of the declaration.
    ///   - nodes: The nodes of the declarations so far.
    private func appendOutlineNode(startedAt startIndex: Int, to nodes: inout [OutlineNode]) {
        guard let header = pendingOutline else { return }
        pendingOutline = nil
        var identifier = Self.outlineIdentifier(kind: header.kind, name: header.name)
        var suffix = 1
        let existing = Set(nodes.map(\.id))
        while existing.contains(identifier) {
            suffix += 1
            identifier = Self.outlineIdentifier(kind: header.kind, name: header.name, suffix: suffix)
        }
        nodes.append(
            OutlineNode(
                id: identifier, kind: header.kind, name: header.name,
                detail: Self.outlineDetail(of: header), range: coveredRange(from: startIndex),
                selectionRange: header.selectionRange, children: header.children))
    }

    private static func outlineIdentifier(kind: String, name: String, suffix: Int = 1) -> String {
        let base = "\(kind):\(name)"
        return suffix > 1 ? "\(base)#\(suffix)" : base
    }

    private static func outlineDetail(of header: ATLOutlineHeader) -> String? {
        let arrow = "->"
        switch header.kind {
        case ATLOutlineKind.helper, ATLOutlineKind.attribute:
            guard let returnType = header.returnType else { return header.contextType }
            return [header.contextType, arrow, returnType].compactMap { $0 }.joined(separator: " ")
        case ATLOutlineKind.matchedRule, ATLOutlineKind.lazyRule, ATLOutlineKind.calledRule:
            let sources = header.children.filter { $0.kind == ATLOutlineKind.sourcePattern }
                .compactMap(\.detail)
            let targets = header.children.filter { $0.kind == ATLOutlineKind.targetPattern }
                .compactMap(\.detail).joined(separator: ", ")
            let from =
                header.kind == ATLOutlineKind.calledRule
                ? "(" + header.parameters.map { "\($0.name) : \($0.type)" }.joined(separator: ", ")
                    + ")"
                : sources.joined(separator: ", ")
            let parts = [from, targets.isEmpty ? "" : arrow + " " + targets]
            let detail = parts.filter { !$0.isEmpty }.joined(separator: " ")
            return detail.isEmpty ? nil : detail
        default:
            return nil
        }
    }

    /// Adds a child node to the outline header of the declaration being parsed.
    private func addOutlineChild(
        kind: String, name: String, type: String, range: SourceRange, selection: SourceRange
    ) {
        guard let header = pendingOutline else { return }
        let identifier = Self.outlineIdentifier(
            kind: kind, name: name,
            suffix: header.children.filter { $0.kind == kind && $0.name == name }.count + 1)
        pendingOutline?.children.append(
            OutlineNode(
                id: "\(header.kind):\(header.name)/\(identifier)",
                kind: kind, name: name, detail: type, range: range, selectionRange: selection))
    }


    private func currentToken() -> ATLToken? {
        guard position < tokens.count else { return nil }
        return tokens[position]
    }

    private func advance() {
        if position < tokens.count {
            position += 1
        }
    }

    fileprivate func peekToken(_ offset: Int) -> ATLToken? {
        let index = position + offset
        guard index >= 0, index < tokens.count else { return nil }
        return tokens[index]
    }

    /// Parses an iterate expression with complex syntax.
    ///
    /// Handles: iterate(param; accumulator : Type = defaultValue | body_expression)
    ///
    /// - Parameters:
    ///   - source: The source collection expression
    ///   - start: The index of the first token of the whole expression
    /// - Returns: An ATLIterateExpression
    /// - Throws: ATLParseError if parsing fails
    private func parseIterateExpression(source: any ATLExpression, start: Int) throws
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
            body: body,
            origin: origin(from: start)
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
        // Use parseImpliesExpression to avoid consuming keywords like 'in'
        return try parseImpliesExpression()
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
        let start = position
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
            inExpression: bodyExpr,
            origin: origin(from: start)
        )
    }

    /// Parses a tuple expression: Tuple{field1 : Type1 = expr1, field2 : Type2 = expr2, ...}
    private func parseTupleExpression() throws -> any ATLExpression {
        let start = position
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

        return ATLTupleExpression(fields: fields, origin: origin(from: start))
    }

    /// Whether the token after the current one is the given punctuation.
    ///
    /// - Parameter punctuation: The punctuation to look for.
    /// - Returns: `true` if the following token is that punctuation.
    private func isNextPunctuation(_ punctuation: String) -> Bool {
        guard position + 1 < tokens.count else { return false }
        return tokens[position + 1].type == .punctuation(punctuation)
    }

    /// Consumes an infix keyword (`implies`, `xor`, `div`, `mod`), which the lexer reads as an identifier.
    ///
    /// - Parameter keyword: The keyword to consume.
    /// - Returns: `true` if the current token was the keyword and has been consumed.
    private func consumeInfixKeyword(_ keyword: ATLLanguage.InfixKeyword) -> Bool {
        guard let token = currentToken(), case .identifier(let name) = token.type,
            name == keyword.rawValue
        else {
            return false
        }
        advance()
        return true
    }

    /// Parses an iterator lambda such as `e | body`, `a, b | body` or `e : Type | body`.
    ///
    /// The position is left unchanged when the upcoming tokens are not a lambda.
    ///
    /// - Returns: The lambda, or `nil` when the arguments do not start with iterator variables and a bar.
    private func parseLambdaIfPresent() throws -> ATLLambdaExpression? {
        let savedPosition = position
        var names: [String] = []

        while let token = currentToken(), case .identifier(let name) = token.type {
            names.append(name)
            advance()
            if consumeOperator(":") {
                guard (try? parseTypeExpression()) != nil else {
                    position = savedPosition
                    return nil
                }
            }
            if !consumePunctuation(",") { break }
        }

        guard !names.isEmpty, consumePunctuation("|") else {
            position = savedPosition
            return nil
        }
        let body = try parseExpression()
        return ATLLambdaExpression(
            parameters: names, body: body, origin: origin(from: savedPosition))
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

// MARK: - Rule Declarations

/// The modifiers that can precede the `rule` keyword.
private struct ATLRuleModifiers {

    /// The rule is declared `abstract`.
    var isAbstract = false

    /// The rule is declared `unique`.
    var isUnique = false

    /// The rule is declared `lazy`.
    var isLazy = false

    /// The rule is declared `entrypoint`.
    var isEntrypoint = false

    /// The rule is declared `endpoint`.
    var isEndpoint = false
}

extension ATLSyntaxParser {

    /// Whether the current token starts a rule declaration.
    ///
    /// A declaration starts with the `rule` keyword or with rule modifiers that
    /// are followed by it.
    ///
    /// - Returns: `true` if a rule declaration starts at the current token
    fileprivate func startsRuleDeclaration() -> Bool {
        var offset = 0
        while let token = token(at: offset) {
            if token.type == .keyword("rule") { return true }
            guard isRuleModifier(token) else { return false }
            offset += 1
        }
        return false
    }

    /// Whether a token is one of the rule modifiers.
    ///
    /// - Parameter token: The token to test
    /// - Returns: `true` for `lazy`, `abstract`, `unique`, `entrypoint` and `endpoint`
    private func isRuleModifier(_ token: ATLToken) -> Bool {
        switch token.type {
        case .keyword("lazy"):
            return true
        case .identifier(let name):
            return [
                ATLReservedNames.abstract, ATLReservedNames.unique,
                ATLReservedNames.entrypoint, ATLReservedNames.endpoint,
                ATLLanguage.UnsupportedKeyword.nodefault,
            ].contains(name)
        default:
            return false
        }
    }

    /// Consumes the modifiers in front of the `rule` keyword.
    ///
    /// - Returns: The modifiers that were present
    /// - Throws: ``ATLParseError/unsupportedConstruct(_:)`` for a modifier that is not supported
    private func parseRuleModifiers() throws -> ATLRuleModifiers {
        var modifiers = ATLRuleModifiers()
        while let token = currentToken(), isRuleModifier(token) {
            switch token.value {
            case ATLLanguage.UnsupportedKeyword.nodefault:
                throw unsupported(
                    "The 'nodefault' rule modifier is not supported at \(describe(token))",
                    at: position)
            case "lazy": modifiers.isLazy = true
            case ATLReservedNames.abstract: modifiers.isAbstract = true
            case ATLReservedNames.unique: modifiers.isUnique = true
            case ATLReservedNames.entrypoint: modifiers.isEntrypoint = true
            default: modifiers.isEndpoint = true
            }
            advance()
        }
        return modifiers
    }

    /// Consumes an identifier with the given text, if it is the current token.
    ///
    /// - Parameter text: The identifier text
    /// - Returns: `true` if the identifier was consumed
    private func consumeIdentifier(_ text: String) -> Bool {
        guard let token = currentToken(), case .identifier(let name) = token.type, name == text
        else { return false }
        advance()
        return true
    }

    /// Parses a matched, called or lazy rule including its modifiers.
    ///
    /// The body consists of the optional sections `from`, `using`, `to` and `do`
    /// in that order. A rule with a parameter list is a called rule, a lazy rule
    /// takes its parameters from its `from` section, and any other rule is a
    /// matched rule.
    ///
    /// - Returns: The parsed ``ATLMatchedRule`` or ``ATLCalledRule``
    /// - Throws: ``ATLParseError`` for malformed rule declarations
    fileprivate func parseRuleDeclaration() throws -> any ATLRuleType {
        let start = position
        let modifiers = try parseRuleModifiers()
        guard consumeKeyword("rule") else {
            throw ATLParseError.invalidSyntax("Expected 'rule' keyword")
        }
        guard let nameToken = currentToken(), case .identifier(let name) = nameToken.type else {
            throw ATLParseError.invalidSyntax("Expected rule name")
        }
        pendingOutline = ATLOutlineHeader(
            kind: modifiers.isLazy ? ATLOutlineKind.lazyRule : ATLOutlineKind.matchedRule,
            name: name, selectionRange: nameToken.range)
        advance()

        var parameters: [ATLParameter]?
        if consumePunctuation("(") {
            parameters = try parseParameterList()
            guard consumePunctuation(")") else {
                throw ATLParseError.invalidSyntax("Expected ')' after called rule parameters")
            }
            if !modifiers.isLazy {
                pendingOutline?.kind = ATLOutlineKind.calledRule
                pendingOutline?.parameters = parameters ?? []
            }
        }

        var superRuleName: String?
        let extendsIndex = position
        if consumeIdentifier(ATLReservedNames.extends) {
            guard let superToken = currentToken(), case .identifier(let superName) = superToken.type
            else {
                throw ATLParseError.invalidSyntax("Expected rule name after 'extends'")
            }
            advance()
            superRuleName = superName
        }

        guard consumePunctuation("{") else {
            throw ATLParseError.invalidSyntax(
                "Expected '{' to start \(parameters != nil ? "called" : modifiers.isLazy ? "lazy" : "matched") rule body"
            )
        }

        var sourcePatterns: [ATLSourcePattern] = []
        if consumeKeyword("from") {
            sourcePatterns = try parseSourcePatternList()
        }
        let localVariables = try parseUsingSection()
        var targetPatterns: [ATLTargetPattern] = []
        if consumeKeyword("to") {
            targetPatterns = try parseTargetPatternList()
        }
        var statements: [any ATLStatement] = []
        if currentToken()?.type == .keyword("do") {
            statements = try parseDoBlock()
        }
        guard consumePunctuation("}") else {
            throw ATLParseError.invalidSyntax(
                "Expected '}' to end \(parameters != nil ? "called" : modifiers.isLazy ? "lazy" : "matched") rule"
            )
        }

        if modifiers.isLazy {
            guard !sourcePatterns.isEmpty else {
                throw ATLParseError.invalidSyntax("Expected 'from' clause in lazy rule")
            }
            guard !targetPatterns.isEmpty else {
                throw ATLParseError.invalidSyntax("Expected 'to' clause in lazy rule")
            }
            guard superRuleName == nil else {
                throw unsupported(
                    "'extends' is only supported for matched rules, not lazy rule '\(name)'",
                    at: extendsIndex)
            }
            return ATLCalledRule(
                name: name,
                parameters: sourcePatterns.map { ATLParameter(name: $0.variableName, type: $0.type, origin: $0.origin) },
                targetPatterns: targetPatterns,
                body: statements,
                localVariables: localVariables,
                isLazy: true,
                isUnique: modifiers.isUnique,
                guard: conjunction(of: sourcePatterns.compactMap(\.guard)),
                origin: origin(from: start)
            )
        }

        if let parameters {
            guard superRuleName == nil else {
                throw unsupported(
                    "'extends' is only supported for matched rules, not called rule '\(name)'",
                    at: extendsIndex)
            }
            guard !targetPatterns.isEmpty || !statements.isEmpty else {
                throw ATLParseError.invalidSyntax("Expected 'to' clause in called rule")
            }
            return ATLCalledRule(
                name: name,
                parameters: parameters,
                targetPatterns: targetPatterns,
                body: statements,
                localVariables: localVariables,
                isEntrypoint: modifiers.isEntrypoint,
                isEndpoint: modifiers.isEndpoint,
                origin: origin(from: start)
            )
        }

        guard let primary = sourcePatterns.first else {
            throw ATLParseError.invalidSyntax("Expected 'from' clause in matched rule")
        }
        guard !targetPatterns.isEmpty || modifiers.isAbstract || superRuleName != nil else {
            throw ATLParseError.invalidSyntax("Expected 'to' clause in matched rule")
        }
        return ATLMatchedRule(
            name: name,
            sourcePattern: primary,
            targetPatterns: targetPatterns,
            guard: primary.guard,
            additionalSourcePatterns: Array(sourcePatterns.dropFirst()),
            localVariables: localVariables,
            doStatements: statements,
            superRuleName: superRuleName,
            isAbstract: modifiers.isAbstract,
            origin: origin(from: start)
        )
    }

    /// Combines guard expressions with `and`.
    ///
    /// - Parameter guards: The guards to combine
    /// - Returns: The conjunction, or `nil` without guards
    private func conjunction(of guards: [any ATLExpression]) -> (any ATLExpression)? {
        guard var combined = guards.first else { return nil }
        for next in guards.dropFirst() {
            combined = ATLBinaryExpression(
                left: combined, operator: .and, right: next, origin: combined.origin)
        }
        return combined
    }

    /// Parses the comma-separated source patterns of a `from` section.
    ///
    /// - Returns: The source patterns in declaration order
    /// - Throws: ``ATLParseError`` for malformed patterns
    private func parseSourcePatternList() throws -> [ATLSourcePattern] {
        var patterns = [try parseSourcePattern()]
        while consumePunctuation(",") {
            patterns.append(try parseSourcePattern())
        }
        return patterns
    }

    /// Parses the comma-separated target patterns of a `to` section.
    ///
    /// - Returns: The target patterns in declaration order
    /// - Throws: ``ATLParseError`` for malformed patterns
    private func parseTargetPatternList() throws -> [ATLTargetPattern] {
        var patterns = [try parseTargetPattern()]
        while consumePunctuation(",") {
            patterns.append(try parseTargetPattern())
        }
        return patterns
    }

    /// Parses an optional `using { name : Type = expression; ... }` section.
    ///
    /// - Returns: The declared local variables, empty if there is no section
    /// - Throws: ``ATLParseError`` for malformed declarations
    private func parseUsingSection() throws -> [ATLLocalVariable] {
        guard consumeIdentifier(ATLReservedNames.using) else { return [] }
        guard consumePunctuation("{") else {
            throw ATLParseError.invalidSyntax("Expected '{' after 'using'")
        }
        var variables: [ATLLocalVariable] = []
        while !isAtEnd() && currentToken()?.type != .punctuation("}") {
            let variableStart = position
            guard let nameToken = currentToken(), case .identifier(let name) = nameToken.type else {
                throw ATLParseError.invalidSyntax("Expected variable name in 'using' section")
            }
            advance()
            var type: String?
            if consumeOperator(":") {
                type = try parseTypeExpression()
            }
            guard consumeOperator("=") else {
                throw ATLParseError.invalidSyntax(
                    "Expected '=' after variable '\(name)' in 'using' section")
            }
            let expression = try parseExpression()
            consumePunctuation(";")
            variables.append(
                ATLLocalVariable(
                    name: name, type: type, expression: expression,
                    origin: origin(from: variableStart)))
        }
        guard consumePunctuation("}") else {
            throw ATLParseError.invalidSyntax("Expected '}' to end 'using' section")
        }
        return variables
    }

    // MARK: - Imperative Statements

    /// Parses an imperative `do { ... }` block.
    ///
    /// - Returns: The statements of the block
    /// - Throws: ``ATLParseError`` for malformed statements
    private func parseDoBlock() throws -> [any ATLStatement] {
        guard consumeKeyword("do") else {
            throw ATLParseError.invalidSyntax("Expected 'do' keyword")
        }
        return try parseStatementBlock()
    }

    /// Parses a brace-delimited sequence of statements.
    ///
    /// - Returns: The statements of the block
    /// - Throws: ``ATLParseError`` for a missing brace or a malformed statement
    private func parseStatementBlock() throws -> [any ATLStatement] {
        guard consumePunctuation("{") else {
            throw ATLParseError.invalidSyntax("Expected '{' to start a block of statements")
        }
        var statements: [any ATLStatement] = []
        while !isAtEnd() && currentToken()?.type != .punctuation("}") {
            statements.append(try parseStatement())
        }
        guard consumePunctuation("}") else {
            throw ATLParseError.invalidSyntax("Unclosed block of statements")
        }
        return statements
    }

    /// Parses one imperative statement.
    ///
    /// Statements are conditionals (`if (c) { } else { }`), loops
    /// (`for (x in c) { }`), declarations (`x : T = e;`), assignments to
    /// variables or target features (`x <- e;`, `t.f <- e;`, `x := e;`) and
    /// expression statements.
    ///
    /// - Returns: The parsed statement
    /// - Throws: ``ATLParseError`` for malformed statements
    private func parseStatement() throws -> any ATLStatement {
        let start = position
        if consumeKeyword("if") {
            return try parseConditionalStatement(start: start)
        }
        if case .identifier(ATLReservedNames.forLoop)? = currentToken()?.type,
            token(at: 1)?.type == .punctuation("(")
        {
            return try parseForStatement()
        }
        if let declaration = try parseDeclarationOrVariableAssignment() {
            return declaration
        }

        let expression = try parseExpression()
        var assignment: (target: ATLAssignmentTarget, value: any ATLExpression)?
        if consumeOperator("<-") {
            let value = try parseExpression()
            switch expression {
            case let variable as ATLVariableExpression:
                assignment = (.variable(variable.name), value)
            case let navigation as ATLNavigationExpression:
                assignment = (.feature(owner: navigation.source, name: navigation.property), value)
            default:
                throw ATLParseError.invalidSyntax(
                    "Expected a variable or a feature on the left of '<-'")
            }
        }
        consumePunctuation(";")
        if let assignment {
            return ATLAssignmentStatement(
                target: assignment.target, value: assignment.value, origin: origin(from: start))
        }
        return ATLExpressionStatement(expression: expression, origin: origin(from: start))
    }

    /// Parses a variable declaration or a `:=` assignment, if one starts here.
    ///
    /// - Returns: The statement, or `nil` if the statement is of another kind
    /// - Throws: ``ATLParseError`` for malformed declarations
    private func parseDeclarationOrVariableAssignment() throws -> (any ATLStatement)? {
        let start = position
        guard case .identifier(let name)? = currentToken()?.type,
            token(at: 1)?.type == .operator(":")
        else { return nil }

        if token(at: 2)?.type == .operator("=") {
            advance()
            advance()
            advance()
            let value = try parseExpression()
            consumePunctuation(";")
            return ATLAssignmentStatement(
                target: .variable(name), value: value, origin: origin(from: start))
        }

        advance()
        advance()
        let type = try parseTypeExpression()
        var initialiser: (any ATLExpression)?
        if consumeOperator("=") || consumeOperator("<-") {
            initialiser = try parseExpression()
        }
        consumePunctuation(";")
        return ATLVariableDeclarationStatement(
            name: name, type: type, initialiser: initialiser, origin: origin(from: start))
    }

    /// Parses the remainder of an `if` statement after the `if` keyword.
    ///
    /// - Parameter start: The index of the `if` token.
    /// - Returns: The conditional statement
    /// - Throws: ``ATLParseError`` for a malformed condition or block
    private func parseConditionalStatement(start: Int) throws -> any ATLStatement {
        let condition = try parseExpression()
        let thenStatements = try parseStatementBlock()
        var elseStatements: [any ATLStatement] = []
        if consumeKeyword("else") {
            let nestedStart = position
            if consumeKeyword("if") {
                elseStatements = [try parseConditionalStatement(start: nestedStart)]
            } else {
                elseStatements = try parseStatementBlock()
            }
        }
        consumePunctuation(";")
        return ATLConditionalStatement(
            condition: condition, thenStatements: thenStatements, elseStatements: elseStatements,
            origin: origin(from: start))
    }

    /// Parses a `for (variable in collection) { ... }` statement.
    ///
    /// - Returns: The for statement
    /// - Throws: ``ATLParseError`` for a malformed header or block
    private func parseForStatement() throws -> any ATLStatement {
        let start = position
        advance()  // 'for'
        advance()  // '('
        guard case .identifier(let variable)? = currentToken()?.type else {
            throw ATLParseError.invalidSyntax("Expected loop variable name after 'for ('")
        }
        advance()
        guard consumeKeyword("in") else {
            throw ATLParseError.invalidSyntax("Expected 'in' after loop variable '\(variable)'")
        }
        let collection = try parseExpression()
        guard consumePunctuation(")") else {
            throw ATLParseError.invalidSyntax("Expected ')' after the loop collection")
        }
        let body = try parseStatementBlock()
        consumePunctuation(";")
        return ATLForStatement(
            variable: variable, collection: collection, body: body, origin: origin(from: start))
    }

    /// Returns the token at an offset from the current position.
    ///
    /// - Parameter offset: The distance from the current token
    /// - Returns: The token, or `nil` beyond the end of input
    fileprivate func token(at offset: Int) -> ATLToken? {
        return peekToken(offset)
    }
}
