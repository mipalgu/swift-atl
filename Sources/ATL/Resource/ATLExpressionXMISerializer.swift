//
//  ATLExpressionXMISerializer.swift
//  ATL
//
//  Created by Claude on 10/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
//  Serializes ATL/OCL expressions to Eclipse ATL XMI format.
//
import Foundation

/// Serializes ATL/OCL expressions to Eclipse ATL XMI format.
///
/// This serializer converts expression trees into the standard Eclipse ATL XMI
/// representation, following the OCL metamodel structure defined in the ATL specification.
///
/// ## Expression Types Supported
///
/// - **Literals**: Integer, string, boolean, and null literals
/// - **Variables**: Variable references
/// - **Navigation**: Property and feature navigation
/// - **Operations**: Binary, unary, and method call operations
/// - **Collections**: Collection literals and operations
/// - **Control Flow**: Conditional (if-then-else) expressions
/// - **Advanced**: Let expressions, lambda expressions, iterate expressions
///
/// ## XMI Format
///
/// Expressions are serialized with `xsi:type` attributes to distinguish types:
/// ```xml
/// <expression xsi:type="ocl:VariableExp" varName="sourceElement"/>
/// <expression xsi:type="ocl:OperationCallExp" operationName="concat">
///   <source xsi:type="ocl:VariableExp" varName="firstName"/>
///   <arguments xsi:type="ocl:StringExp" stringSymbol="..."/>
/// </expression>
/// ```
public struct ATLExpressionXMISerializer {

    // MARK: - Initialisation

    /// Creates a new expression XMI serializer.
    public init() {}

    // MARK: - Serialization

    /// Serializes an ATL expression to XMI format.
    ///
    /// - Parameters:
    ///   - expression: The expression to serialize
    ///   - indent: The indentation level for formatting (default: 2 spaces)
    /// - Returns: The XMI representation of the expression
    public func serialize(_ expression: any ATLExpression, indent: Int = 2) -> String {
        let indentString = String(repeating: " ", count: indent)

        // Dispatch to appropriate serializer based on expression type
        if let literal = expression as? ATLLiteralExpression {
            return serializeLiteral(literal, indent: indentString)
        } else if let variable = expression as? ATLVariableExpression {
            return serializeVariable(variable, indent: indentString)
        } else if let navigation = expression as? ATLNavigationExpression {
            return serializeNavigation(navigation, indent: indentString)
        } else if let binary = expression as? ATLBinaryOperationExpression {
            return serializeBinaryOperation(binary, indent: indentString)
        } else if let unary = expression as? ATLUnaryOperationExpression {
            return serializeUnaryOperation(unary, indent: indentString)
        } else if let conditional = expression as? ATLConditionalExpression {
            return serializeConditional(conditional, indent: indentString)
        } else if let methodCall = expression as? ATLMethodCallExpression {
            return serializeMethodCall(methodCall, indent: indentString)
        } else if let helperCall = expression as? ATLHelperCallExpression {
            return serializeHelperCall(helperCall, indent: indentString)
        } else if let lambda = expression as? ATLLambdaExpression {
            return serializeLambda(lambda, indent: indentString)
        } else if let iterate = expression as? ATLIterateExpression {
            return serializeIterate(iterate, indent: indentString)
        } else if let letExpr = expression as? ATLLetExpression {
            return serializeLet(letExpr, indent: indentString)
        } else if let tuple = expression as? ATLTupleExpression {
            return serializeTuple(tuple, indent: indentString)
        } else if let collectionLiteral = expression as? ATLCollectionLiteralExpression {
            return serializeCollectionLiteral(collectionLiteral, indent: indentString)
        } else if let collection = expression as? ATLCollectionExpression {
            return serializeCollection(collection, indent: indentString)
        } else if let typeLiteral = expression as? ATLTypeLiteralExpression {
            return serializeTypeLiteral(typeLiteral, indent: indentString)
        } else {
            // Unknown expression type - serialize as placeholder
            return "\(indentString)<expression xsi:type=\"ocl:OclExpression\"><!-- Unknown expression type --></expression>\n"
        }
    }

    // MARK: - Literal Serialization

    private func serializeLiteral(_ literal: ATLLiteralExpression, indent: String) -> String {
        guard let value = literal.value else {
            return "\(indent)<expression xsi:type=\"ocl:OclUndefinedExp\"/>\n"
        }

        if let intValue = value as? Int {
            return "\(indent)<expression xsi:type=\"ocl:IntegerExp\" integerSymbol=\"\(intValue)\"/>\n"
        } else if let doubleValue = value as? Double {
            return "\(indent)<expression xsi:type=\"ocl:RealExp\" realSymbol=\"\(doubleValue)\"/>\n"
        } else if let stringValue = value as? String {
            let escaped = escapeXML(stringValue)
            return "\(indent)<expression xsi:type=\"ocl:StringExp\" stringSymbol=\"\(escaped)\"/>\n"
        } else if let boolValue = value as? Bool {
            return "\(indent)<expression xsi:type=\"ocl:BooleanExp\" booleanSymbol=\"\(boolValue)\"/>\n"
        } else {
            return "\(indent)<expression xsi:type=\"ocl:OclExpression\"><!-- Unsupported literal type --></expression>\n"
        }
    }

    private func serializeVariable(_ variable: ATLVariableExpression, indent: String) -> String {
        return "\(indent)<expression xsi:type=\"ocl:VariableExp\" varName=\"\(escapeXML(variable.name))\"/>\n"
    }

    private func serializeTypeLiteral(_ typeLiteral: ATLTypeLiteralExpression, indent: String) -> String {
        return "\(indent)<expression xsi:type=\"ocl:TypeExp\" typeName=\"\(escapeXML(typeLiteral.typeName))\"/>\n"
    }

    // MARK: - Navigation Serialization

    private func serializeNavigation(_ navigation: ATLNavigationExpression, indent: String) -> String {
        var xmi = "\(indent)<expression xsi:type=\"ocl:NavigationOrAttributeCallExp\" name=\"\(escapeXML(navigation.property))\">\n"
        xmi += "\(indent)  <source>\n"
        xmi += serialize(navigation.source, indent: indent.count + 4)
        xmi += "\(indent)  </source>\n"
        xmi += "\(indent)</expression>\n"
        return xmi
    }

    // MARK: - Operation Serialization

    private func serializeBinaryOperation(_ binary: ATLBinaryOperationExpression, indent: String) -> String {
        let opName = binary.operator.rawValue
        var xmi = "\(indent)<expression xsi:type=\"ocl:OperationCallExp\" operationName=\"\(escapeXML(opName))\">\n"

        xmi += "\(indent)  <source>\n"
        xmi += serialize(binary.left, indent: indent.count + 4)
        xmi += "\(indent)  </source>\n"

        xmi += "\(indent)  <arguments>\n"
        xmi += serialize(binary.right, indent: indent.count + 4)
        xmi += "\(indent)  </arguments>\n"

        xmi += "\(indent)</expression>\n"
        return xmi
    }

    private func serializeUnaryOperation(_ unary: ATLUnaryOperationExpression, indent: String) -> String {
        let opName = unary.operator.rawValue
        var xmi = "\(indent)<expression xsi:type=\"ocl:OperationCallExp\" operationName=\"\(escapeXML(opName))\">\n"

        xmi += "\(indent)  <source>\n"
        xmi += serialize(unary.operand, indent: indent.count + 4)
        xmi += "\(indent)  </source>\n"

        xmi += "\(indent)</expression>\n"
        return xmi
    }

    private func serializeMethodCall(_ methodCall: ATLMethodCallExpression, indent: String) -> String {
        var xmi = "\(indent)<expression xsi:type=\"ocl:OperationCallExp\" operationName=\"\(escapeXML(methodCall.methodName))\">\n"

        xmi += "\(indent)  <source>\n"
        xmi += serialize(methodCall.receiver, indent: indent.count + 4)
        xmi += "\(indent)  </source>\n"

        for argument in methodCall.arguments {
            xmi += "\(indent)  <arguments>\n"
            xmi += serialize(argument, indent: indent.count + 4)
            xmi += "\(indent)  </arguments>\n"
        }

        xmi += "\(indent)</expression>\n"
        return xmi
    }

    private func serializeHelperCall(_ helperCall: ATLHelperCallExpression, indent: String) -> String {
        var xmi = "\(indent)<expression xsi:type=\"atl:HelperCallExp\" helperName=\"\(escapeXML(helperCall.helperName))\">\n"

        for argument in helperCall.arguments {
            xmi += "\(indent)  <arguments>\n"
            xmi += serialize(argument, indent: indent.count + 4)
            xmi += "\(indent)  </arguments>\n"
        }

        xmi += "\(indent)</expression>\n"
        return xmi
    }

    // MARK: - Control Flow Serialization

    private func serializeConditional(_ conditional: ATLConditionalExpression, indent: String) -> String {
        var xmi = "\(indent)<expression xsi:type=\"ocl:IfExp\">\n"

        xmi += "\(indent)  <condition>\n"
        xmi += serialize(conditional.condition, indent: indent.count + 4)
        xmi += "\(indent)  </condition>\n"

        xmi += "\(indent)  <thenExpression>\n"
        xmi += serialize(conditional.thenExpression, indent: indent.count + 4)
        xmi += "\(indent)  </thenExpression>\n"

        xmi += "\(indent)  <elseExpression>\n"
        xmi += serialize(conditional.elseExpression, indent: indent.count + 4)
        xmi += "\(indent)  </elseExpression>\n"

        xmi += "\(indent)</expression>\n"
        return xmi
    }

    // MARK: - Lambda and Iterate Serialization

    private func serializeLambda(_ lambda: ATLLambdaExpression, indent: String) -> String {
        // Lambda expressions are just parameter bindings with a body
        // They're typically used as part of collection operations
        // Serialize as a simple parameter-body structure
        var xmi = "\(indent)<expression xsi:type=\"ocl:LambdaExp\">\n"

        xmi += "\(indent)  <parameter name=\"\(escapeXML(lambda.parameter))\"/>\n"

        xmi += "\(indent)  <body>\n"
        xmi += serialize(lambda.body, indent: indent.count + 4)
        xmi += "\(indent)  </body>\n"

        xmi += "\(indent)</expression>\n"
        return xmi
    }

    private func serializeIterate(_ iterate: ATLIterateExpression, indent: String) -> String {
        var xmi = "\(indent)<expression xsi:type=\"ocl:IterateExp\">\n"

        xmi += "\(indent)  <source>\n"
        xmi += serialize(iterate.source, indent: indent.count + 4)
        xmi += "\(indent)  </source>\n"

        xmi += "\(indent)  <iterators name=\"\(escapeXML(iterate.parameter))\"/>\n"

        xmi += "\(indent)  <result name=\"\(escapeXML(iterate.accumulator))\">\n"
        xmi += "\(indent)    <initExpression>\n"
        xmi += serialize(iterate.defaultValue, indent: indent.count + 6)
        xmi += "\(indent)    </initExpression>\n"
        xmi += "\(indent)  </result>\n"

        xmi += "\(indent)  <body>\n"
        xmi += serialize(iterate.body, indent: indent.count + 4)
        xmi += "\(indent)  </body>\n"

        xmi += "\(indent)</expression>\n"
        return xmi
    }

    // MARK: - Let Expression Serialization

    private func serializeLet(_ letExpr: ATLLetExpression, indent: String) -> String {
        var xmi = "\(indent)<expression xsi:type=\"ocl:LetExp\">\n"

        xmi += "\(indent)  <variable name=\"\(escapeXML(letExpr.variableName))\""
        if let type = letExpr.variableType {
            xmi += " type=\"\(escapeXML(type))\""
        }
        xmi += ">\n"
        xmi += "\(indent)    <initExpression>\n"
        xmi += serialize(letExpr.initExpression, indent: indent.count + 6)
        xmi += "\(indent)    </initExpression>\n"
        xmi += "\(indent)  </variable>\n"

        xmi += "\(indent)  <in_>\n"
        xmi += serialize(letExpr.inExpression, indent: indent.count + 4)
        xmi += "\(indent)  </in_>\n"

        xmi += "\(indent)</expression>\n"
        return xmi
    }

    // MARK: - Tuple Serialization

    private func serializeTuple(_ tuple: ATLTupleExpression, indent: String) -> String {
        var xmi = "\(indent)<expression xsi:type=\"ocl:TupleLiteralExp\">\n"

        for (fieldName, fieldType, fieldValue) in tuple.fields {
            xmi += "\(indent)  <tuplePart name=\"\(escapeXML(fieldName))\""
            if let type = fieldType {
                xmi += " type=\"\(escapeXML(type))\""
            }
            xmi += ">\n"
            xmi += "\(indent)    <initExpression>\n"
            xmi += serialize(fieldValue, indent: indent.count + 6)
            xmi += "\(indent)    </initExpression>\n"
            xmi += "\(indent)  </tuplePart>\n"
        }

        xmi += "\(indent)</expression>\n"
        return xmi
    }

    // MARK: - Collection Serialization

    private func serializeCollectionLiteral(_ collectionLiteral: ATLCollectionLiteralExpression, indent: String) -> String {
        // Use the collectionType string directly (e.g., "Sequence", "Set", "Bag")
        let kindName = collectionLiteral.collectionType

        var xmi = "\(indent)<expression xsi:type=\"ocl:CollectionLiteralExp\" kind=\"\(escapeXML(kindName))\">\n"

        for element in collectionLiteral.elements {
            xmi += "\(indent)  <parts>\n"
            xmi += serialize(element, indent: indent.count + 4)
            xmi += "\(indent)  </parts>\n"
        }

        xmi += "\(indent)</expression>\n"
        return xmi
    }

    private func serializeCollection(_ collection: ATLCollectionExpression, indent: String) -> String {
        let opName = collection.operation.rawValue
        var xmi = "\(indent)<expression xsi:type=\"ocl:IteratorExp\" name=\"\(escapeXML(opName))\">\n"

        xmi += "\(indent)  <source>\n"
        xmi += serialize(collection.source, indent: indent.count + 4)
        xmi += "\(indent)  </source>\n"

        // Serialize iterator if present
        if let iterator = collection.iterator {
            xmi += "\(indent)  <iterators name=\"\(escapeXML(iterator))\"/>\n"
        }

        // Serialize body if present
        if let body = collection.body {
            xmi += "\(indent)  <body>\n"
            xmi += serialize(body, indent: indent.count + 4)
            xmi += "\(indent)  </body>\n"
        }

        xmi += "\(indent)</expression>\n"
        return xmi
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
