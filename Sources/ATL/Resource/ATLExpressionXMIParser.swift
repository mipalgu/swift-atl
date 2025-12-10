//
//  ATLExpressionXMIParser.swift
//  ATL
//
//  Created by Claude on 10/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
//  Parses ATL/OCL expressions from Eclipse ATL XMI format.
//
import Foundation

/// Parses ATL/OCL expressions from Eclipse ATL XMI format.
///
/// This parser reconstructs expression trees from the standard Eclipse ATL XMI
/// representation, following the OCL metamodel structure.
///
/// ## Supported Expression Types
///
/// - **Literals**: Integer, Real, String, Boolean, Undefined
/// - **Variables**: Variable references
/// - **Navigation**: Property and feature navigation
/// - **Operations**: Binary, unary, and method call operations
/// - **Collections**: Collection literals and iterator operations
/// - **Control Flow**: Conditional (if-then-else) expressions
/// - **Advanced**: Let expressions, lambda expressions, iterate expressions, tuples
///
/// ## XMI Format
///
/// Expressions are identified by `xsi:type` attributes:
/// ```xml
/// <expression xsi:type="ocl:VariableExp" varName="x"/>
/// <expression xsi:type="ocl:IntegerExp" integerSymbol="42"/>
/// ```
///
/// ## Architecture
///
/// This parser uses a recursive descent approach with DOM-based XML parsing.
/// Each expression type has a dedicated parsing method, eliminating shared state
/// and naturally handling arbitrary nesting through recursion.
public struct ATLExpressionXMIParser {

    // MARK: - Initialisation

    /// Creates a new expression XMI parser.
    public init() {}

    // MARK: - Parsing

    /// Parses an expression from XMI format.
    ///
    /// - Parameter xmi: The XMI content containing the expression
    /// - Returns: The parsed expression
    /// - Throws: Parsing errors if the XMI is invalid
    public func parse(_ xmi: String) throws -> any ATLExpression {
        guard let data = xmi.data(using: .utf8) else {
            throw ExpressionParseError.invalidXML("Failed to convert XMI to UTF-8")
        }

        let document = try XMLDocument(data: data, options: [])
        guard let root = document.rootElement() else {
            throw ExpressionParseError.invalidXML("No root element")
        }

        // Find first expression element (could be direct child or nested)
        guard let exprElement = findFirstExpression(in: root) else {
            throw ExpressionParseError.noExpression("No expression element found")
        }

        return try parseExpression(exprElement)
    }

    // MARK: - Helper Methods

    /// Finds the first expression element in the tree.
    private func findFirstExpression(in element: XMLElement) -> XMLElement? {
        if element.name == "expression" {
            return element
        }

        for child in element.children ?? [] {
            if let childElement = child as? XMLElement,
               let found = findFirstExpression(in: childElement) {
                return found
            }
        }

        return nil
    }

    /// Gets attribute value from element.
    private func attribute(_ name: String, from element: XMLElement) -> String? {
        return element.attribute(forName: name)?.stringValue
    }

    /// Gets required attribute value from element.
    private func requiredAttribute(_ name: String, from element: XMLElement) throws -> String {
        guard let value = attribute(name, from: element) else {
            throw ExpressionParseError.missingAttribute("Missing required attribute '\(name)'")
        }
        return value
    }

    /// Finds first child element with given name.
    private func child(_ name: String, in element: XMLElement) -> XMLElement? {
        return element.elements(forName: name).first
    }

    /// Finds first expression element within a named container.
    private func childExpression(_ containerName: String, in element: XMLElement) throws -> XMLElement? {
        guard let container = child(containerName, in: element) else {
            return nil
        }
        return child("expression", in: container)
    }

    // MARK: - Expression Parsing Dispatcher

    /// Parses an expression element based on its xsi:type.
    private func parseExpression(_ element: XMLElement) throws -> any ATLExpression {
        // Get type from xsi:type or type attribute
        guard let type = attribute("xsi:type", from: element) ?? attribute("type", from: element) else {
            throw ExpressionParseError.missingAttribute("Missing xsi:type or type attribute")
        }

        // Dispatch to appropriate parser based on type
        if type.contains("VariableExp") {
            return try parseVariable(element)
        } else if type.contains("IntegerExp") {
            return try parseInteger(element)
        } else if type.contains("RealExp") {
            return try parseReal(element)
        } else if type.contains("StringExp") {
            return try parseString(element)
        } else if type.contains("BooleanExp") {
            return try parseBoolean(element)
        } else if type.contains("OclUndefinedExp") {
            return parseUndefined()
        } else if type.contains("TypeExp") {
            return try parseTypeLiteral(element)
        } else if type.contains("NavigationOrAttributeCallExp") {
            return try parseNavigation(element)
        } else if type.contains("OperationCallExp") {
            return try parseOperationCall(element)
        } else if type.contains("HelperCallExp") {
            return try parseHelperCall(element)
        } else if type.contains("IfExp") {
            return try parseConditional(element)
        } else if type.contains("IteratorExp") {
            return try parseIterator(element)
        } else if type.contains("IterateExp") {
            return try parseIterate(element)
        } else if type.contains("LetExp") {
            return try parseLet(element)
        } else if type.contains("LambdaExp") {
            return try parseLambda(element)
        } else if type.contains("TupleLiteralExp") {
            return try parseTuple(element)
        } else if type.contains("CollectionLiteralExp") {
            return try parseCollectionLiteral(element)
        } else {
            throw ExpressionParseError.unsupportedType("Unsupported expression type: \(type)")
        }
    }

    // MARK: - Literal Expression Parsers

    private func parseVariable(_ element: XMLElement) throws -> ATLVariableExpression {
        let varName = try requiredAttribute("varName", from: element)
        return ATLVariableExpression(name: varName)
    }

    private func parseInteger(_ element: XMLElement) throws -> ATLLiteralExpression {
        let symbol = try requiredAttribute("integerSymbol", from: element)
        guard let value = Int(symbol) else {
            throw ExpressionParseError.invalidXML("Invalid integer value: \(symbol)")
        }
        return ATLLiteralExpression(value: value)
    }

    private func parseReal(_ element: XMLElement) throws -> ATLLiteralExpression {
        let symbol = try requiredAttribute("realSymbol", from: element)
        guard let value = Double(symbol) else {
            throw ExpressionParseError.invalidXML("Invalid real value: \(symbol)")
        }
        return ATLLiteralExpression(value: value)
    }

    private func parseString(_ element: XMLElement) throws -> ATLLiteralExpression {
        let symbol = try requiredAttribute("stringSymbol", from: element)
        return ATLLiteralExpression(value: symbol)
    }

    private func parseBoolean(_ element: XMLElement) throws -> ATLLiteralExpression {
        let symbol = try requiredAttribute("booleanSymbol", from: element)
        guard let value = Bool(symbol) else {
            throw ExpressionParseError.invalidXML("Invalid boolean value: \(symbol)")
        }
        return ATLLiteralExpression(value: value)
    }

    private func parseUndefined() -> ATLLiteralExpression {
        return ATLLiteralExpression(value: nil)
    }

    private func parseTypeLiteral(_ element: XMLElement) throws -> ATLTypeLiteralExpression {
        let typeName = try requiredAttribute("typeName", from: element)
        return ATLTypeLiteralExpression(typeName: typeName)
    }

    // MARK: - Navigation Expression Parser

    private func parseNavigation(_ element: XMLElement) throws -> ATLNavigationExpression {
        let name = try requiredAttribute("name", from: element)

        guard let sourceElement = try childExpression("source", in: element) else {
            throw ExpressionParseError.missingAttribute("Missing source for navigation")
        }

        let source = try parseExpression(sourceElement)
        return ATLNavigationExpression(source: source, property: name)
    }

    // MARK: - Operation Expression Parsers

    private func parseOperationCall(_ element: XMLElement) throws -> any ATLExpression {
        let opName = try requiredAttribute("operationName", from: element)

        // Parse source
        let sourceElement = try childExpression("source", in: element)
        let source = try sourceElement.map { try parseExpression($0) }

        // Parse arguments
        let argumentElements = element.elements(forName: "arguments")
        var arguments: [any ATLExpression] = []
        for argContainer in argumentElements {
            if let argExpr = child("expression", in: argContainer) {
                arguments.append(try parseExpression(argExpr))
            }
        }

        // Determine expression type based on operation name and argument count
        if let src = source, arguments.isEmpty {
            // Unary operation or method call with no arguments
            if let op = ATLUnaryOperator(rawValue: opName) {
                return ATLUnaryOperationExpression(operator: op, operand: src)
            } else {
                return ATLMethodCallExpression(receiver: src, methodName: opName, arguments: [])
            }
        } else if let src = source, arguments.count == 1 {
            // Binary operation or method call with one argument
            if let op = ATLBinaryOperator(rawValue: opName) {
                return ATLBinaryOperationExpression(left: src, operator: op, right: arguments[0])
            } else {
                return ATLMethodCallExpression(receiver: src, methodName: opName, arguments: arguments)
            }
        } else if let src = source {
            // Method call with multiple arguments
            return ATLMethodCallExpression(receiver: src, methodName: opName, arguments: arguments)
        } else {
            throw ExpressionParseError.invalidXML("OperationCallExp must have a source")
        }
    }

    private func parseHelperCall(_ element: XMLElement) throws -> ATLHelperCallExpression {
        let helperName = try requiredAttribute("helperName", from: element)

        // Parse arguments
        let argumentElements = element.elements(forName: "arguments")
        var arguments: [any ATLExpression] = []
        for argContainer in argumentElements {
            if let argExpr = child("expression", in: argContainer) {
                arguments.append(try parseExpression(argExpr))
            }
        }

        return ATLHelperCallExpression(helperName: helperName, arguments: arguments)
    }

    // MARK: - Control Flow Expression Parsers

    private func parseConditional(_ element: XMLElement) throws -> ATLConditionalExpression {
        // Parse condition
        guard let conditionElement = try childExpression("condition", in: element) else {
            throw ExpressionParseError.missingAttribute("Missing condition in IfExp")
        }
        let condition = try parseExpression(conditionElement)

        // Parse then expression
        guard let thenElement = try childExpression("thenExpression", in: element) else {
            throw ExpressionParseError.missingAttribute("Missing thenExpression in IfExp")
        }
        let thenExpr = try parseExpression(thenElement)

        // Parse else expression
        guard let elseElement = try childExpression("elseExpression", in: element) else {
            throw ExpressionParseError.missingAttribute("Missing elseExpression in IfExp")
        }
        let elseExpr = try parseExpression(elseElement)

        return ATLConditionalExpression(
            condition: condition,
            thenExpression: thenExpr,
            elseExpression: elseExpr
        )
    }

    // MARK: - Collection Expression Parsers

    private func parseIterator(_ element: XMLElement) throws -> any ATLExpression {
        let name = try requiredAttribute("name", from: element)

        // Parse source
        guard let sourceElement = try childExpression("source", in: element) else {
            throw ExpressionParseError.missingAttribute("Missing source in IteratorExp")
        }
        let source = try parseExpression(sourceElement)

        // Parse iterator name (optional)
        let iteratorName = child("iterators", in: element).flatMap { attribute("name", from: $0) }

        // Parse body (optional)
        let bodyElement = try childExpression("body", in: element)
        let body = try bodyElement.map { try parseExpression($0) }

        // Create collection expression
        guard let operation = ATLCollectionOperation(rawValue: name) else {
            throw ExpressionParseError.unsupportedType("Unknown collection operation: \(name)")
        }

        return ATLCollectionExpression(
            source: source,
            operation: operation,
            iterator: iteratorName,
            body: body
        )
    }

    private func parseIterate(_ element: XMLElement) throws -> ATLIterateExpression {
        // Parse source
        guard let sourceElement = try childExpression("source", in: element) else {
            throw ExpressionParseError.missingAttribute("Missing source in IterateExp")
        }
        let source = try parseExpression(sourceElement)

        // Parse iterator name
        guard let iteratorsElement = child("iterators", in: element),
              let iteratorName = attribute("name", from: iteratorsElement) else {
            throw ExpressionParseError.missingAttribute("Missing iterator in IterateExp")
        }

        // Parse accumulator (result)
        guard let resultElement = child("result", in: element),
              let accumulatorName = attribute("name", from: resultElement) else {
            throw ExpressionParseError.missingAttribute("Missing result in IterateExp")
        }

        // Parse accumulator type (optional)
        let accumulatorType = resultElement.attribute(forName: "type")?.stringValue

        // Parse accumulator init expression
        guard let initElement = try childExpression("initExpression", in: resultElement) else {
            throw ExpressionParseError.missingAttribute("Missing initExpression in IterateExp result")
        }
        let initExpr = try parseExpression(initElement)

        // Parse body
        guard let bodyElement = try childExpression("body", in: element) else {
            throw ExpressionParseError.missingAttribute("Missing body in IterateExp")
        }
        let body = try parseExpression(bodyElement)

        return ATLIterateExpression(
            source: source,
            parameter: iteratorName,
            accumulator: accumulatorName,
            accumulatorType: accumulatorType,
            defaultValue: initExpr,
            body: body
        )
    }

    private func parseCollectionLiteral(_ element: XMLElement) throws -> ATLCollectionLiteralExpression {
        let kind = attribute("kind", from: element) ?? "Sequence"

        // Parse parts (collection elements)
        let partsElements = element.elements(forName: "parts")
        var elements: [any ATLExpression] = []
        for partContainer in partsElements {
            if let partExpr = child("expression", in: partContainer) {
                elements.append(try parseExpression(partExpr))
            }
        }

        return ATLCollectionLiteralExpression(collectionType: kind, elements: elements)
    }

    // MARK: - Advanced Expression Parsers

    private func parseLet(_ element: XMLElement) throws -> ATLLetExpression {
        // Parse variable
        guard let variableElement = child("variable", in: element),
              let varName = attribute("name", from: variableElement) else {
            throw ExpressionParseError.missingAttribute("Missing variable in LetExp")
        }

        let varType = attribute("type", from: variableElement)

        // Parse init expression
        guard let initElement = try childExpression("initExpression", in: variableElement) else {
            throw ExpressionParseError.missingAttribute("Missing initExpression in LetExp variable")
        }
        let initExpr = try parseExpression(initElement)

        // Parse in expression
        guard let inElement = try childExpression("in_", in: element) else {
            throw ExpressionParseError.missingAttribute("Missing in_ in LetExp")
        }
        let inExpr = try parseExpression(inElement)

        return ATLLetExpression(
            variableName: varName,
            variableType: varType,
            initExpression: initExpr,
            inExpression: inExpr
        )
    }

    private func parseLambda(_ element: XMLElement) throws -> ATLLambdaExpression {
        // Parse parameter
        guard let parameterElement = child("parameter", in: element),
              let paramName = attribute("name", from: parameterElement) else {
            throw ExpressionParseError.missingAttribute("Missing parameter in LambdaExp")
        }

        // Parse body
        guard let bodyElement = try childExpression("body", in: element) else {
            throw ExpressionParseError.missingAttribute("Missing body in LambdaExp")
        }
        let body = try parseExpression(bodyElement)

        return ATLLambdaExpression(parameter: paramName, body: body)
    }

    private func parseTuple(_ element: XMLElement) throws -> ATLTupleExpression {
        // Parse tuple parts
        let partElements = element.elements(forName: "tuplePart")
        var fields: [(name: String, type: String?, value: any ATLExpression)] = []

        for partElement in partElements {
            guard let name = attribute("name", from: partElement) else {
                throw ExpressionParseError.missingAttribute("Missing name in tuplePart")
            }

            let type = attribute("type", from: partElement)

            guard let initElement = try childExpression("initExpression", in: partElement) else {
                throw ExpressionParseError.missingAttribute("Missing initExpression in tuplePart")
            }
            let initExpr = try parseExpression(initElement)

            fields.append((name: name, type: type, value: initExpr))
        }

        return ATLTupleExpression(fields: fields)
    }
}

// MARK: - Expression Parse Errors

/// Errors that can occur during expression parsing.
public enum ExpressionParseError: Error, LocalizedError {
    case invalidXML(String)
    case parsingFailed(String)
    case noExpression(String)
    case unsupportedType(String)
    case missingAttribute(String)

    public var errorDescription: String? {
        switch self {
        case .invalidXML(let message): return "Invalid XML: \(message)"
        case .parsingFailed(let message): return "Parsing failed: \(message)"
        case .noExpression(let message): return "No expression: \(message)"
        case .unsupportedType(let message): return "Unsupported type: \(message)"
        case .missingAttribute(let message): return "Missing attribute: \(message)"
        }
    }
}
