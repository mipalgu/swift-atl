//
//  ATLXMISerializer.swift
//  ATL
//
//  Created by Claude on 10/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
//  Serializes ATL modules to Eclipse ATL XMI format.
//
import ECore
import EMFBase
import Foundation

/// Serializes ATL modules to Eclipse ATL XMI format.
///
/// `ATLXMISerializer` converts ATL modules into the standard Eclipse ATL XMI
/// representation, following the ATL metamodel structure defined at
/// `http://www.eclipse.org/gmt/2005/ATL`.
///
/// ## Overview
///
/// The serializer supports all ATL constructs:
/// - **Modules**: Top-level transformation units with source/target metamodel references
/// - **Rules**: Matched rules, called rules, and lazy rules
/// - **Helpers**: Context-free and contextual helper functions
/// - **Queries**: Query definitions (when supported)
/// - **Expressions**: Full OCL expression trees including let, tuple, iterate, etc.
///
/// ## XMI Format
///
/// The generated XMI follows Eclipse ATL standards:
/// ```xml
/// <?xml version="1.0" encoding="UTF-8"?>
/// <atl:Module xmi:version="2.0"
///             xmlns:xmi="http://www.omg.org/XMI"
///             xmlns:atl="http://www.eclipse.org/gmt/2005/ATL"
///             name="ModuleName">
///   <!-- Module contents -->
/// </atl:Module>
/// ```
///
/// ## Example Usage
///
/// ```swift
/// let serializer = ATLXMISerializer()
/// let xmi = try serializer.serialize(atlModule)
/// print(xmi)
/// ```
public struct ATLXMISerializer {

    // MARK: - Initialisation

    /// Creates a new ATL XMI serializer.
    public init() {}

    /// Expression serializer for handling expression trees.
    private let expressionSerializer = ATLExpressionXMISerializer()

    // MARK: - Serialization

    /// Serializes an ATL module to Eclipse ATL XMI format.
    ///
    /// - Parameter module: The ATL module to serialize
    /// - Returns: The XMI representation as a string
    /// - Throws: `ATLResourceError.serializationError` if serialization fails
    public func serialize(_ module: ATLModule) throws -> String {
        var xmi = """
        <?xml version="1.0" encoding="UTF-8"?>
        <atl:Module xmi:version="2.0"
                    xmlns:xmi="http://www.omg.org/XMI"
                    xmlns:atl="http://www.eclipse.org/gmt/2005/ATL"
                    name="\(escapeXML(module.name))">

        """

        // Serialize inModels (source metamodels)
        for (alias, package) in module.sourceMetamodels {
            xmi += serializeOclModel(alias: alias, package: package, kind: "IN")
        }

        // Serialize outModels (target metamodels)
        for (alias, package) in module.targetMetamodels {
            xmi += serializeOclModel(alias: alias, package: package, kind: "OUT")
        }

        // Serialize helpers
        for (name, helper) in module.helpers {
            xmi += try serializeHelper(helper, name: name)
        }

        // Serialize matched rules
        for rule in module.matchedRules {
            xmi += try serializeMatchedRule(rule)
        }

        // Serialize called rules (including lazy rules)
        for (name, rule) in module.calledRules {
            xmi += try serializeCalledRule(rule, name: name)
        }

        xmi += "</atl:Module>\n"
        return xmi
    }

    // MARK: - OCL Model Serialization

    private func serializeOclModel(alias: String, package: EPackage, kind: String) -> String {
        // Use the package nsURI as the metamodel reference
        let metamodel = package.nsURI.isEmpty ? "http://\(package.name.lowercased())" : package.nsURI
        return """
          <inModels name="\(escapeXML(alias))" metamodel="\(escapeXML(metamodel))" kind="\(kind)"/>

        """
    }

    // MARK: - Helper Serialization

    private func serializeHelper(_ helper: any ATLHelperType, name: String) throws -> String {
        var xmi = """
          <helpers xsi:type="atl:Helper"
                   xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                   name="\(escapeXML(name))">

        """

        // Serialize context type if present
        if let contextType = helper.contextType {
            xmi += """
              <contextType name="\(escapeXML(contextType))"/>

        """
        }

        // Serialize parameters
        for param in helper.parameters {
            xmi += serializeParameter(param)
        }

        // Serialize return type
        xmi += """
          <returnType name="\(escapeXML(helper.returnType))"/>

        """

        // Serialize helper body if it's an ATLHelperWrapper with accessible body
        if let wrapper = helper as? ATLHelperWrapper {
            xmi += "    <definition>\n"
            xmi += "      <body>\n"
            xmi += expressionSerializer.serialize(wrapper.bodyExpression, indent: 8)
            xmi += "      </body>\n"
            xmi += "    </definition>\n"
        } else {
            xmi += "    <!-- Helper body expression: type-erased helper -->\n"
        }

        xmi += "  </helpers>\n"
        return xmi
    }

    // MARK: - Rule Serialization

    private func serializeMatchedRule(_ rule: ATLMatchedRule) throws -> String {
        var xmi = """
          <elements xsi:type="atl:MatchedRule"
                    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                    name="\(escapeXML(rule.name))">

        """

        // Serialize source pattern
        xmi += try serializeSourcePattern(rule.sourcePattern)

        // Serialize target patterns
        for targetPattern in rule.targetPatterns {
            xmi += try serializeTargetPattern(targetPattern)
        }

        xmi += "  </elements>\n"
        return xmi
    }

    private func serializeCalledRule(_ rule: ATLCalledRule, name: String) throws -> String {
        var xmi = """
          <elements xsi:type="atl:CalledRule"
                    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                    name="\(escapeXML(name))">

        """

        // Serialize parameters
        for param in rule.parameters {
            xmi += serializeParameter(param)
        }

        // Serialize target patterns
        for targetPattern in rule.targetPatterns {
            xmi += try serializeTargetPattern(targetPattern)
        }

        xmi += "  </elements>\n"
        return xmi
    }

    // MARK: - Pattern Serialization

    private func serializeSourcePattern(_ pattern: ATLSourcePattern) throws -> String {
        var xmi = """
            <inPattern>
              <elements name="\(escapeXML(pattern.variableName))" type="\(escapeXML(pattern.type))">

        """

        // Serialize filter (guard condition) if present
        if let guardExpr = pattern.guard {
            xmi += "        <filter>\n"
            xmi += expressionSerializer.serialize(guardExpr, indent: 10)
            xmi += "        </filter>\n"
        }

        xmi += """
              </elements>
            </inPattern>

        """
        return xmi
    }

    private func serializeTargetPattern(_ pattern: ATLTargetPattern) throws -> String {
        var xmi = """
            <outPattern>
              <elements name="\(escapeXML(pattern.variableName))" type="\(escapeXML(pattern.type))">

        """

        // Serialize bindings
        for binding in pattern.bindings {
            xmi += "        <bindings propertyName=\"\(escapeXML(binding.property))\">\n"
            xmi += "          <value>\n"
            xmi += expressionSerializer.serialize(binding.expression, indent: 12)
            xmi += "          </value>\n"
            xmi += "        </bindings>\n"
        }

        xmi += """
              </elements>
            </outPattern>

        """
        return xmi
    }

    // MARK: - Parameter Serialization

    private func serializeParameter(_ param: ATLParameter) -> String {
        return """
            <parameters name="\(escapeXML(param.name))" type="\(escapeXML(param.type))"/>

        """
    }

    // MARK: - Utility Methods

    /// Escapes special XML characters in strings.
    ///
    /// - Parameter string: The string to escape
    /// - Returns: The escaped string safe for XML attributes and content
    private func escapeXML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
