//
//  ATLExpressionXMISerializer.swift
//  ATL
//
//  Created by Rene Hexel on 10/12/2025.
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

    /// The options that select how collection ranges are written.
    public let options: ATLOptions

    /// Creates a new expression XMI serializer that behaves as in swift-atl 0.6.
    ///
    /// The serializer uses ``ATLOptions/legacy``, which writes collection ranges as
    /// OCL collection ranges.
    public init() {
        self.init(options: .legacy)
    }

    /// Creates a new expression XMI serializer with the given options.
    ///
    /// - Parameter options: The options whose ``ATLOptions/collectionRangeEncoding``
    ///   selects how collection ranges are written.
    public init(options: ATLOptions) {
        self.options = options
    }

    // MARK: - Serialization

    /// Serializes an ATL expression to XMI format.
    ///
    /// Collection ranges are written as the ``ATLOptions/collectionRangeEncoding``
    /// of the serializer's ``options`` selects.
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
        } else if let binary = expression as? ATLBinaryExpression {
            return serializeBinaryOperation(binary, indent: indentString)
        } else if let unary = expression as? ATLUnaryExpression {
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
            if options.collectionRangeEncoding == .portable,
                let portable = ATLPortableRanges.rewriting(collectionLiteral)
            {
                return serialize(portable, indent: indent)
            }
            return serializeCollectionLiteral(collectionLiteral, indent: indentString)
        } else if let range = expression as? ATLCollectionRangeExpression {
            if options.collectionRangeEncoding == .portable {
                return serialize(ATLPortableRanges.sequence(of: range), indent: indent)
            }
            return serializeCollectionRange(range, indent: indentString)
        } else if let collection = expression as? ATLCollectionExpression {
            return serializeCollection(collection, indent: indentString)
        } else if let typeLiteral = expression as? ATLTypeLiteralExpression {
            return serializeTypeLiteral(typeLiteral, indent: indentString)
        } else if let enumLiteral = expression as? ATLEnumLiteralExpression {
            return "\(indentString)<expression xsi:type=\"ocl:EnumLiteralExp\" name=\"\(escapeXML(enumLiteral.name))\"/>\n"
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

    private func serializeBinaryOperation(_ binary: ATLBinaryExpression, indent: String) -> String {
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

    private func serializeUnaryOperation(_ unary: ATLUnaryExpression, indent: String) -> String {
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

        for parameter in lambda.parameters {
            xmi += "\(indent)  <parameter name=\"\(escapeXML(parameter))\"/>\n"
        }

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

    private func serializeCollectionRange(_ range: ATLCollectionRangeExpression, indent: String) -> String {
        let names = ATLCollectionRangeXMI.self
        var xmi = "\(indent)<expression xsi:type=\"\(names.qualifiedType)\">\n"
        xmi += "\(indent)  <\(names.first)>\n"
        xmi += serialize(range.first, indent: indent.count + 4)
        xmi += "\(indent)  </\(names.first)>\n"
        xmi += "\(indent)  <\(names.last)>\n"
        xmi += serialize(range.last, indent: indent.count + 4)
        xmi += "\(indent)  </\(names.last)>\n"
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

/// The XMI names of a collection range, shared by the expression serialiser and parser.
///
/// A range is written as an OCL `CollectionRange` part of a collection literal,
/// with its bounds in `first` and `last` containers.
enum ATLCollectionRangeXMI {
    /// The type name of a range part.
    static let type = "CollectionRange"

    /// The namespace-qualified type name of a range part.
    static let qualifiedType = "ocl:" + type

    /// The container of the first bound.
    static let first = "first"

    /// The container of the last bound.
    static let last = "last"
}

/// Rewrites collection literals that hold ranges into equivalent expressions without ranges.
///
/// A range whose bounds are integer literals becomes the integers it spans. The parts
/// before any other range become the receiver of an `includingRange` call with the
/// bounds of the range, and the parts after it are added with `includingAll`.
enum ATLPortableRanges {
    /// Rewrites a collection literal without ranges.
    ///
    /// - Parameter literal: The collection literal to rewrite.
    /// - Returns: An equivalent expression without ranges, or `nil` when the literal
    ///   holds no range.
    static func rewriting(_ literal: ATLCollectionLiteralExpression) -> (any ATLExpression)? {
        guard literal.elements.contains(where: { $0 is ATLCollectionRangeExpression }) else {
            return nil
        }
        let kind = literal.collectionType
        var result: (any ATLExpression)?
        var items: [any ATLExpression] = []
        func addItems() {
            guard !items.isEmpty || result == nil else { return }
            let part = ATLCollectionLiteralExpression(collectionType: kind, elements: items)
            result =
                result.map {
                    ATLMethodCallExpression(
                        receiver: $0, methodName: ATLOperation.includingAll.rawValue, arguments: [part])
                } ?? part
            items = []
        }
        for element in literal.elements {
            guard let range = element as? ATLCollectionRangeExpression else {
                items.append(element)
                continue
            }
            if let integers = constantIntegers(of: range) {
                items += integers.map { ATLLiteralExpression(value: $0) }
                continue
            }
            addItems()
            if let receiver = result {
                result = ATLMethodCallExpression(
                    receiver: receiver, methodName: ATLOperation.includingRange.rawValue,
                    arguments: [range.first, range.last])
            }
        }
        addItems()
        return result
    }

    /// Rewrites a range on its own, which stands for a sequence, without ranges.
    ///
    /// - Parameter range: The range to rewrite.
    /// - Returns: An equivalent expression without ranges.
    static func sequence(of range: ATLCollectionRangeExpression) -> any ATLExpression {
        let literal = ATLCollectionLiteralExpression(
            collectionType: ATLCollectionKind.sequence.rawValue, elements: [range])
        return rewriting(literal) ?? literal
    }

    /// The integers of a range whose bounds are integer literals.
    ///
    /// - Parameter range: The range whose integers are wanted.
    /// - Returns: The integers in ascending order, or `nil` when a bound is not an
    ///   integer literal or the range holds more integers than a range may hold.
    static func constantIntegers(of range: ATLCollectionRangeExpression) -> [Int]? {
        guard let low = integerLiteral(range.first), let high = integerLiteral(range.last) else {
            return nil
        }
        guard low <= high else { return [] }
        let (span, overflow) = high.subtractingReportingOverflow(low)
        guard !overflow, span < ATLBuiltinOperations.maximumRangeLength else { return nil }
        return Array(low...high)
    }

    /// The value of an integer literal, which may be negated.
    ///
    /// - Parameter expression: The expression to inspect.
    /// - Returns: The integer, or `nil` when the expression is not an integer literal.
    private static func integerLiteral(_ expression: any ATLExpression) -> Int? {
        if let literal = expression as? ATLLiteralExpression { return literal.value as? Int }
        guard let negation = expression as? ATLUnaryExpression, negation.operator == .minus,
            let value = (negation.operand as? ATLLiteralExpression)?.value as? Int
        else { return nil }
        let (negated, overflow) = (0).subtractingReportingOverflow(value)
        return overflow ? nil : negated
    }
}
