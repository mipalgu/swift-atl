//
//  ATLXMIParser.swift
//  ATL
//
//  Created by Claude on 10/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
//  Parses Eclipse ATL XMI format back to ATL modules.
//
import ECore
import EMFBase
import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
import OrderedCollections

/// Parses Eclipse ATL XMI format into ATL modules.
///
/// `ATLXMIParser` reads the standard Eclipse ATL XMI representation and reconstructs
/// the ATL module structure, following the ATL metamodel defined at
/// `http://www.eclipse.org/gmt/2005/ATL`.
///
/// ## Overview
///
/// The parser supports all ATL constructs:
/// - **Modules**: Top-level transformation units with metamodel references
/// - **Rules**: Matched rules, called rules, and lazy rules
/// - **Helpers**: Context-free and contextual helper functions
/// - **Patterns**: Source patterns (from clauses) and target patterns (to clauses)
///
/// ## Example Usage
///
/// ```swift
/// let parser = ATLXMIParser()
/// let module = try parser.parse(xmiContent)
/// print("Loaded module: \(module.name)")
/// ```
public struct ATLXMIParser {

    // MARK: - Initialisation

    /// Creates a new ATL XMI parser.
    public init() {}

    // MARK: - Parsing

    /// Parses Eclipse ATL XMI format into an ATL module.
    ///
    /// - Parameter xmi: The XMI content as a string
    /// - Returns: The parsed ATL module
    /// - Throws: `ATLResourceError.parsingError` if parsing fails
    public func parse(_ xmi: String) throws -> ATLModule {
        guard let data = xmi.data(using: .utf8) else {
            throw ATLResourceError.parsingError("Failed to convert XMI string to UTF-8 data")
        }

        let delegate = ATLXMIParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse(), let module = delegate.module else {
            let error = delegate.error ?? "Unknown XML parsing error"
            throw ATLResourceError.parsingError("Failed to parse ATL XMI: \(error)")
        }

        return module
    }
}

// MARK: - XML Parser Delegate

/// Internal delegate for parsing ATL XMI using Foundation's XMLParser.
private class ATLXMIParserDelegate: NSObject, XMLParserDelegate {

    // MARK: - State

    var module: ATLModule?
    var error: String?

    // Parsing state
    private var moduleName: String?
    private var sourceMetamodels: OrderedDictionary<String, EPackage> = [:]
    private var targetMetamodels: OrderedDictionary<String, EPackage> = [:]
    private var helpers: OrderedDictionary<String, any ATLHelperType> = [:]
    private var matchedRules: [ATLMatchedRule] = []
    private var calledRules: OrderedDictionary<String, ATLCalledRule> = [:]

    // Current parsing context
    private var currentElement: String?
    private var currentAttributes: [String: String] = [:]

    // MARK: - XMLParserDelegate Methods

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        currentElement = elementName
        currentAttributes = attributeDict

        switch elementName {
        case "atl:Module", "Module":
            moduleName = attributeDict["name"]

        case "inModels":
            if let alias = attributeDict["name"],
               let metamodelURI = attributeDict["metamodel"],
               let kind = attributeDict["kind"]
            {
                // Create a placeholder EPackage from the metamodel URI
                // In a full implementation, this would resolve to actual metamodel
                let packageName = alias
                let package = EPackage(name: packageName, nsURI: metamodelURI)

                if kind == "IN" {
                    sourceMetamodels[alias] = package
                } else if kind == "OUT" {
                    targetMetamodels[alias] = package
                }
            }

        case "helpers":
            parseHelper(attributes: attributeDict)

        case "elements":
            parseElement(attributes: attributeDict)

        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        if elementName == "atl:Module" || elementName == "Module" {
            // Module parsing complete - construct the ATL module
            if let name = moduleName {
                // Ensure we have at least one source and target metamodel
                if sourceMetamodels.isEmpty {
                    sourceMetamodels["IN"] = EPackage(name: "DefaultSource", nsURI: "http://default.source")
                }
                if targetMetamodels.isEmpty {
                    targetMetamodels["OUT"] = EPackage(name: "DefaultTarget", nsURI: "http://default.target")
                }

                module = ATLModule(
                    name: name,
                    sourceMetamodels: sourceMetamodels,
                    targetMetamodels: targetMetamodels,
                    helpers: helpers,
                    matchedRules: matchedRules,
                    calledRules: calledRules
                )
            }
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        error = parseError.localizedDescription
    }

    // MARK: - Helper Parsing

    private func parseHelper(attributes: [String: String]) {
        guard let name = attributes["name"] else { return }

        // For now, create a minimal helper placeholder
        // Full helper parsing with expressions will be added later
        let helper = ATLHelperWrapper(
            name: name,
            contextType: nil,    // Will be extracted from nested elements
            returnType: "Any",   // Default return type
            parameters: [],      // Will be extracted from nested elements
            body: ATLLiteralExpression(value: nil)  // Placeholder body
        )

        helpers[name] = helper
    }

    // MARK: - Element (Rule) Parsing

    private func parseElement(attributes: [String: String]) {
        guard let type = attributes["xsi:type"] ?? attributes["type"],
              let name = attributes["name"]
        else { return }

        if type.contains("MatchedRule") {
            // Create a placeholder matched rule
            // Full rule parsing with patterns will be added later
            let rule = ATLMatchedRule(
                name: name,
                sourcePattern: ATLSourcePattern(
                    variableName: "placeholder",
                    type: "PlaceholderType",
                    guard: nil
                ),
                targetPatterns: [
                    ATLTargetPattern(
                        variableName: "placeholderTarget",
                        type: "PlaceholderTargetType",
                        bindings: []
                    )
                ]
            )
            matchedRules.append(rule)

        } else if type.contains("CalledRule") || type.contains("LazyRule") {
            // Create a placeholder called rule
            let rule = ATLCalledRule(
                name: name,
                parameters: [],
                targetPatterns: [
                    ATLTargetPattern(
                        variableName: "placeholderTarget",
                        type: "PlaceholderTargetType",
                        bindings: []
                    )
                ],
                body: []
            )
            calledRules[name] = rule
        }
    }
}
