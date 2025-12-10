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

        let delegate = ExpressionParserDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = delegate

        guard parser.parse() else {
            let error = delegate.error ?? parser.parserError?.localizedDescription ?? "Unknown error"
            throw ExpressionParseError.parsingFailed(error)
        }

        guard let expression = delegate.expression else {
            throw ExpressionParseError.noExpression("No expression was parsed")
        }

        return expression
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

// MARK: - Expression Parser Delegate

/// XML parser delegate for parsing ATL expressions.
private class ExpressionParserDelegate: NSObject, XMLParserDelegate {

    // MARK: - State

    var expression: (any ATLExpression)?
    var error: String?

    // Parsing context stack
    private var contextStack: [ParsingContext] = []
    private var currentElement: String?
    private var currentAttributes: [String: String] = [:]

    // MARK: - Parsing Context

    private enum ParsingContext {
        case expression(type: String, attributes: [String: String])
        case source
        case arguments
        case condition
        case thenExpression
        case elseExpression
        case body
        case initExpression
        case in_
        case variable
        case iterators
        case result
        case parts
        case tuplePart(name: String, type: String?)
        case value
        case filter
        case parameter
    }

    // Temporary storage for building complex expressions
    private var sourceExpression: (any ATLExpression)?
    private var argumentExpressions: [any ATLExpression] = []
    private var conditionExpression: (any ATLExpression)?
    private var thenExpr: (any ATLExpression)?
    private var elseExpr: (any ATLExpression)?
    private var bodyExpression: (any ATLExpression)?
    private var initExpression: (any ATLExpression)?
    private var inExpression: (any ATLExpression)?
    private var variableName: String?
    private var variableType: String?
    private var iteratorName: String?
    private var accumulatorName: String?
    private var accumulatorInit: (any ATLExpression)?
    private var collectionParts: [any ATLExpression] = []
    private var tupleFields: [(name: String, type: String?, value: any ATLExpression)] = []
    private var currentTuplePartName: String?
    private var currentTuplePartType: String?

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
        case "expression":
            handleExpressionStart(attributes: attributeDict)

        case "source":
            contextStack.append(.source)

        case "arguments":
            contextStack.append(.arguments)

        case "condition":
            contextStack.append(.condition)

        case "thenExpression":
            contextStack.append(.thenExpression)

        case "elseExpression":
            contextStack.append(.elseExpression)

        case "body":
            contextStack.append(.body)

        case "initExpression":
            contextStack.append(.initExpression)

        case "in_":
            contextStack.append(.in_)

        case "variable":
            contextStack.append(.variable)
            variableName = attributeDict["name"]
            variableType = attributeDict["type"]

        case "iterators":
            contextStack.append(.iterators)
            iteratorName = attributeDict["name"]

        case "result":
            contextStack.append(.result)
            accumulatorName = attributeDict["name"]

        case "parts":
            contextStack.append(.parts)

        case "tuplePart":
            let name = attributeDict["name"] ?? ""
            let type = attributeDict["type"]
            contextStack.append(.tuplePart(name: name, type: type))
            currentTuplePartName = name
            currentTuplePartType = type

        case "value":
            contextStack.append(.value)

        case "filter":
            contextStack.append(.filter)

        case "parameter":
            contextStack.append(.parameter)
            iteratorName = attributeDict["name"]

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
        if elementName == "expression" {
            handleExpressionEnd()
        } else if !contextStack.isEmpty {
            contextStack.removeLast()
        }

        // Reset tuple part context
        if elementName == "tuplePart" {
            currentTuplePartName = nil
            currentTuplePartType = nil
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: Error) {
        error = parseError.localizedDescription
    }

    // MARK: - Expression Handling

    private func handleExpressionStart(attributes: [String: String]) {
        guard let type = attributes["xsi:type"] ?? attributes["type"] else {
            return
        }

        // Handle simple expressions that don't need sub-elements
        // These are self-contained and we build them immediately
        var simpleExpr: (any ATLExpression)? = nil

        if type.contains("VariableExp") {
            if let varName = attributes["varName"] {
                simpleExpr = ATLVariableExpression(name: varName)
            }
        } else if type.contains("IntegerExp") {
            if let intSymbol = attributes["integerSymbol"], let value = Int(intSymbol) {
                simpleExpr = ATLLiteralExpression(value: value)
            }
        } else if type.contains("RealExp") {
            if let realSymbol = attributes["realSymbol"], let value = Double(realSymbol) {
                simpleExpr = ATLLiteralExpression(value: value)
            }
        } else if type.contains("StringExp") {
            if let stringSymbol = attributes["stringSymbol"] {
                simpleExpr = ATLLiteralExpression(value: stringSymbol)
            }
        } else if type.contains("BooleanExp") {
            if let boolSymbol = attributes["booleanSymbol"], let value = Bool(boolSymbol) {
                simpleExpr = ATLLiteralExpression(value: value)
            }
        } else if type.contains("OclUndefinedExp") {
            simpleExpr = ATLLiteralExpression(value: nil)
        } else if type.contains("TypeExp") {
            if let typeName = attributes["typeName"] {
                simpleExpr = ATLTypeLiteralExpression(typeName: typeName)
            }
        }

        if let expr = simpleExpr {
            // Simple expression - store it directly without pushing context
            storeExpression(expr)
        } else {
            // Complex expression - push context and wait for sub-elements
            contextStack.append(.expression(type: type, attributes: attributes))
        }
    }

    private func handleExpressionEnd() {
        guard let context = contextStack.last,
              case .expression(let type, let attributes) = context else {
            return
        }

        contextStack.removeLast()

        // Build complex expressions that required sub-elements
        let expr: (any ATLExpression)?

        if type.contains("NavigationOrAttributeCallExp") {
            if let name = attributes["name"], let source = sourceExpression {
                expr = ATLNavigationExpression(source: source, property: name)
                sourceExpression = nil
            } else {
                expr = nil
            }
        } else if type.contains("OperationCallExp") {
            if let opName = attributes["operationName"] {
                if let source = sourceExpression, argumentExpressions.isEmpty {
                    // Unary operation
                    if let op = ATLUnaryOperator(rawValue: opName) {
                        expr = ATLUnaryOperationExpression(operator: op, operand: source)
                    } else {
                        // Method call with no arguments
                        expr = ATLMethodCallExpression(receiver: source, methodName: opName, arguments: [])
                    }
                    sourceExpression = nil
                } else if let source = sourceExpression, argumentExpressions.count == 1 {
                    // Binary operation or method call with one argument
                    if let op = ATLBinaryOperator(rawValue: opName) {
                        expr = ATLBinaryOperationExpression(
                            left: source,
                            operator: op,
                            right: argumentExpressions[0]
                        )
                    } else {
                        expr = ATLMethodCallExpression(
                            receiver: source,
                            methodName: opName,
                            arguments: argumentExpressions
                        )
                    }
                    sourceExpression = nil
                    argumentExpressions = []
                } else if let source = sourceExpression {
                    // Method call with multiple arguments
                    expr = ATLMethodCallExpression(
                        receiver: source,
                        methodName: opName,
                        arguments: argumentExpressions
                    )
                    sourceExpression = nil
                    argumentExpressions = []
                } else {
                    expr = nil
                }
            } else {
                expr = nil
            }
        } else if type.contains("HelperCallExp") {
            if let helperName = attributes["helperName"] {
                expr = ATLHelperCallExpression(helperName: helperName, arguments: argumentExpressions)
                argumentExpressions = []
            } else {
                expr = nil
            }
        } else if type.contains("IfExp") {
            if let condition = conditionExpression,
               let thenBranch = thenExpr,
               let elseBranch = elseExpr {
                expr = ATLConditionalExpression(
                    condition: condition,
                    thenExpression: thenBranch,
                    elseExpression: elseBranch
                )
                conditionExpression = nil
                thenExpr = nil
                elseExpr = nil
            } else {
                expr = nil
            }
        } else if type.contains("IteratorExp") {
            if let name = attributes["name"], let source = sourceExpression {
                if let iterator = iteratorName, let body = bodyExpression {
                    expr = ATLLambdaExpression(parameter: iterator, body: body)
                    sourceExpression = nil
                    iteratorName = nil
                    bodyExpression = nil
                } else if let body = bodyExpression {
                    // Collection expression without explicit iterator
                    if let operation = ATLCollectionOperation(rawValue: name) {
                        expr = ATLCollectionExpression(
                            source: source,
                            operation: operation,
                            iterator: iteratorName,
                            body: body
                        )
                        sourceExpression = nil
                        iteratorName = nil
                        bodyExpression = nil
                    } else {
                        expr = nil
                    }
                } else {
                    // Collection expression without body (simple operations like size)
                    if let operation = ATLCollectionOperation(rawValue: name) {
                        expr = ATLCollectionExpression(
                            source: source,
                            operation: operation,
                            iterator: nil,
                            body: nil
                        )
                        sourceExpression = nil
                    } else {
                        expr = nil
                    }
                }
            } else {
                expr = nil
            }
        } else if type.contains("IterateExp") {
            if let source = sourceExpression,
               let iterator = iteratorName,
               let accumulator = accumulatorName,
               let initExpr = accumulatorInit,
               let body = bodyExpression {
                expr = ATLIterateExpression(
                    source: source,
                    parameter: iterator,
                    accumulator: accumulator,
                    accumulatorType: nil,
                    defaultValue: initExpr,
                    body: body
                )
                sourceExpression = nil
                iteratorName = nil
                accumulatorName = nil
                accumulatorInit = nil
                bodyExpression = nil
            } else {
                expr = nil
            }
        } else if type.contains("LetExp") {
            if let varName = variableName,
               let initExpr = initExpression,
               let inExpr = inExpression {
                expr = ATLLetExpression(
                    variableName: varName,
                    variableType: variableType,
                    initExpression: initExpr,
                    inExpression: inExpr
                )
                variableName = nil
                variableType = nil
                initExpression = nil
                inExpression = nil
            } else {
                expr = nil
            }
        } else if type.contains("TupleLiteralExp") {
            expr = ATLTupleExpression(fields: tupleFields)
            tupleFields = []
        } else if type.contains("CollectionLiteralExp") {
            let kind = attributes["kind"] ?? "Sequence"
            expr = ATLCollectionLiteralExpression(collectionType: kind, elements: collectionParts)
            collectionParts = []
        } else if type.contains("LambdaExp") {
            if let param = iteratorName, let body = bodyExpression {
                expr = ATLLambdaExpression(parameter: param, body: body)
                iteratorName = nil
                bodyExpression = nil
            } else {
                expr = nil
            }
        } else {
            // Already handled in handleExpressionStart
            expr = nil
        }

        if let expr = expr {
            storeExpression(expr)
        }
    }

    private func storeExpression(_ expr: any ATLExpression) {
        // Store expression in appropriate context
        guard contextStack.count >= 1 else {
            // Top-level expression
            expression = expr
            return
        }

        let parentContext = contextStack[contextStack.count - 1]

        switch parentContext {
        case .source:
            sourceExpression = expr

        case .arguments:
            argumentExpressions.append(expr)

        case .condition:
            conditionExpression = expr

        case .thenExpression:
            thenExpr = expr

        case .elseExpression:
            elseExpr = expr

        case .body:
            bodyExpression = expr

        case .initExpression:
            // Could be for variable, accumulator, or tuple part
            if contextStack.count >= 2 {
                let grandparentContext = contextStack[contextStack.count - 2]
                if case .result = grandparentContext {
                    accumulatorInit = expr
                } else if case .tuplePart = grandparentContext {
                    if let name = currentTuplePartName {
                        tupleFields.append((name: name, type: currentTuplePartType, value: expr))
                    }
                } else {
                    initExpression = expr
                }
            } else {
                initExpression = expr
            }

        case .in_:
            inExpression = expr

        case .parts:
            collectionParts.append(expr)

        case .value, .filter:
            // Store as generic expression for now
            expression = expr

        default:
            // Default to top-level if context not recognized
            expression = expr
        }
    }
}
