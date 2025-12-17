//
//  ATLECoreBridge.swift
//  ATL
//
//  Created by Rene Hexel on 8/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import ECore
import Foundation

/// Bridge for converting ATL expressions to ECore expressions.
///
/// This bridge enables ATL transformations to leverage the underlying
/// swift-ecore execution framework by converting ATL-specific expression
/// types to the equivalent ECore expression representation.
///
/// ## Architecture
///
/// The bridge follows a visitor pattern, providing conversion methods
/// for each ATL expression type. The conversion is designed to preserve
/// semantics whilst enabling performance optimisations in the ECore
/// execution engine.
///
/// ## Example Usage
///
/// ```swift
/// let atlExpression = ATLNavigationExpression(
///     source: ATLVariableExpression(name: "self"),
///     property: "firstName"
/// )
///
/// let ecoreExpression = atlExpression.toECoreExpression()
/// let result = try await executionEngine.evaluate(ecoreExpression, context: context)
/// ```
extension ATLExpression {
    /// Convert this ATL expression to an ECore expression.
    ///
    /// This method provides the primary bridge between ATL and ECore expression
    /// systems, enabling ATL transformations to execute using the high-performance
    /// ECore execution engine whilst maintaining ATL semantics.
    ///
    /// - Returns: Equivalent ECore expression
    public func toECoreExpression() -> ECoreExpression {
        switch self {
        case let literalExpr as ATLLiteralExpression:
            return literalExpr.toECoreExpression()
        case let variableExpr as ATLVariableExpression:
            return variableExpr.toECoreExpression()
        case let navigationExpr as ATLNavigationExpression:
            return navigationExpr.toECoreExpression()
        case let operationExpr as ATLOperationExpression:
            return operationExpr.toECoreExpression()
        case let binaryOpExpr as ATLBinaryExpression:
            return binaryOpExpr.toECoreExpression()
        case let unaryOpExpr as ATLUnaryExpression:
            return unaryOpExpr.toECoreExpression()
        case let conditionalExpr as ATLConditionalExpression:
            return conditionalExpr.toECoreExpression()
        case let collectionExpr as ATLCollectionExpression:
            return collectionExpr.toECoreExpression()
        case let helperCallExpr as ATLHelperCallExpression:
            return helperCallExpr.toECoreExpression()
        default:
            // Fallback for unknown expression types
            return .literal(value: .string("UnsupportedExpression: \(type(of: self))"))
        }
    }
}

// MARK: - Literal Expression Bridge

extension ATLLiteralExpression {
    /// Convert ATL literal to ECore literal expression.
    func toECoreExpression() -> ECoreExpression {
        guard let value = value else {
            return .literal(value: .null)
        }

        switch value {
        case let stringValue as String:
            return .literal(value: .string(stringValue))
        case let intValue as Int:
            return .literal(value: .int(intValue))
        case let boolValue as Bool:
            return .literal(value: .boolean(boolValue))
        case let doubleValue as Double:
            return .literal(value: .double(doubleValue))
        case let floatValue as Float:
            return .literal(value: .float(floatValue))
        case let uuidValue as EUUID:
            return .literal(value: .uuid(uuidValue))
        default:
            // For unknown types, convert based on type
            if let stringValue = value as? String {
                return .literal(value: .string(stringValue))
            } else if let intValue = value as? Int {
                return .literal(value: .int(intValue))
            } else if let boolValue = value as? Bool {
                return .literal(value: .boolean(boolValue))
            } else {
                // Fallback to nil for unsupported types
                return .literal(value: .string(""))
            }
        }
    }
}

// MARK: - Variable Expression Bridge

extension ATLVariableExpression {
    /// Convert ATL variable reference to ECore variable expression.
    func toECoreExpression() -> ECoreExpression {
        return .variable(name: name)
    }
}

// MARK: - Navigation Expression Bridge

extension ATLNavigationExpression {
    /// Convert ATL navigation to ECore navigation expression.
    func toECoreExpression() -> ECoreExpression {
        return .navigation(
            source: source.toECoreExpression(),
            property: property
        )
    }
}

// MARK: - Operation Expression Bridge

extension ATLOperationExpression {
    /// Convert ATL operation call to ECore method call expression.
    func toECoreExpression() -> ECoreExpression {
        let receiverExpression = source?.toECoreExpression() ?? .variable(name: "self")
        let argumentExpressions = arguments.map { $0.toECoreExpression() }

        return .methodCall(
            receiver: receiverExpression,
            methodName: operationName,
            arguments: argumentExpressions
        )
    }
}

// MARK: - Binary Operation Expression Bridge

extension ATLBinaryExpression {
    /// Convert ATL binary operation to appropriate ECore expression.
    func toECoreExpression() -> ECoreExpression {
        let leftExpr = left.toECoreExpression()
        let rightExpr = right.toECoreExpression()

        // Map ATL binary operators to ECore method calls
        let methodName = operatorToMethodName(`operator`)

        return .methodCall(
            receiver: leftExpr,
            methodName: methodName,
            arguments: [rightExpr]
        )
    }

    /// Map ATL binary operators to method names.
    private func operatorToMethodName(_ op: ATLBinaryOperator) -> String {
        switch op {
        case .plus:
            return "+"
        case .minus:
            return "-"
        case .multiply:
            return "*"
        case .divide:
            return "/"
        case .modulo:
            return "%"
        case .equals:
            return "="
        case .notEquals:
            return "<>"
        case .lessThan:
            return "<"
        case .lessThanOrEqual:
            return "<="
        case .greaterThan:
            return ">"
        case .greaterThanOrEqual:
            return ">="
        case .and:
            return "and"
        case .or:
            return "or"
        case .union:
            return "union"
        case .intersection:
            return "intersection"
        case .difference:
            return "difference"
        case .includes:
            return "includes"
        case .excludes:
            return "excludes"
        case .implies:
            return "implies"
        }
    }
}

// MARK: - Unary Operation Expression Bridge

extension ATLUnaryExpression {
    /// Convert ATL unary operation to ECore method call expression.
    func toECoreExpression() -> ECoreExpression {
        let operandExpr = operand.toECoreExpression()
        let methodName = unaryOperatorToMethodName(`operator`)

        return .methodCall(
            receiver: operandExpr,
            methodName: methodName,
            arguments: []
        )
    }

    /// Map ATL unary operators to method names.
    private func unaryOperatorToMethodName(_ op: ATLUnaryOperator) -> String {
        switch op {
        case .not:
            return "not"
        case .minus:
            return "unaryMinus"

        }
    }
}

// MARK: - Conditional Expression Bridge

extension ATLConditionalExpression {
    /// Convert ATL conditional (if-then-else) to ECore method call.
    func toECoreExpression() -> ECoreExpression {
        let conditionExpr = condition.toECoreExpression()
        let thenExpr = thenExpression.toECoreExpression()
        let elseExpr = elseExpression.toECoreExpression()

        // Model if-then-else as a method call on the condition
        return .methodCall(
            receiver: conditionExpr,
            methodName: "ifThenElse",
            arguments: [thenExpr, elseExpr]
        )
    }
}

// MARK: - Collection Expression Bridge

extension ATLCollectionExpression {
    /// Convert ATL collection operations to ECore expressions.
    func toECoreExpression() -> ECoreExpression {
        let sourceExpr = source.toECoreExpression()

        switch operation {
        case .select:
            if let iterator = iterator, let body = body {
                // Convert select to ECore filter expression
                let conditionExpr = convertIteratorBody(body, iteratorName: iterator)
                return .filter(collection: sourceExpr, condition: conditionExpr)
            }

        case .collect:
            if let iterator = iterator, let body = body {
                // Convert collect to ECore select expression
                let mapperExpr = convertIteratorBody(body, iteratorName: iterator)
                return .select(collection: sourceExpr, mapper: mapperExpr)
            }

        case .exists, .forAll, .reject, .any, .one:
            // Convert to method calls on the collection
            let methodName = collectionOperationToMethodName(operation)
            let arguments: [ECoreExpression]

            if let iterator = iterator, let body = body {
                let iteratorExpr = convertIteratorBody(body, iteratorName: iterator)
                arguments = [iteratorExpr]
            } else {
                arguments = []
            }

            return .methodCall(
                receiver: sourceExpr,
                methodName: methodName,
                arguments: arguments
            )

        case .size, .isEmpty, .notEmpty, .first, .last:
            // Simple property-style operations
            return .methodCall(
                receiver: sourceExpr,
                methodName: collectionOperationToMethodName(operation),
                arguments: []
            )

        case .iterate:
            // Iterate operation with iterator and body
            let methodName = collectionOperationToMethodName(operation)
            let arguments: [ECoreExpression]

            if let iterator = iterator, let body = body {
                let iteratorExpr = convertIteratorBody(body, iteratorName: iterator)
                arguments = [iteratorExpr]
            } else {
                arguments = []
            }

            return .methodCall(
                receiver: sourceExpr,
                methodName: methodName,
                arguments: arguments
            )

        case .union, .intersection, .difference:
            // Binary collection operations
            return .methodCall(
                receiver: sourceExpr,
                methodName: collectionOperationToMethodName(operation),
                arguments: []
            )

        case .asSet, .asSequence, .asBag:
            // Collection type conversions
            return .methodCall(
                receiver: sourceExpr,
                methodName: collectionOperationToMethodName(operation),
                arguments: []
            )

        case .flatten:
            // Flatten nested collections
            return .methodCall(
                receiver: sourceExpr,
                methodName: collectionOperationToMethodName(operation),
                arguments: []
            )

        case .including, .excluding:
            // Collection modification operations
            return .methodCall(
                receiver: sourceExpr,
                methodName: collectionOperationToMethodName(operation),
                arguments: []
            )

        case .sortedBy:
            // Sorting operation
            let methodName = collectionOperationToMethodName(operation)
            let arguments: [ECoreExpression]

            if let iterator = iterator, let body = body {
                let iteratorExpr = convertIteratorBody(body, iteratorName: iterator)
                arguments = [iteratorExpr]
            } else {
                arguments = []
            }

            return .methodCall(
                receiver: sourceExpr,
                methodName: methodName,
                arguments: arguments
            )
        }

        // Fallback for unsupported operations
        return .methodCall(
            receiver: sourceExpr,
            methodName: "unsupportedOperation",
            arguments: []
        )
    }

    /// Convert iterator body expression to use iterator variable.
    private func convertIteratorBody(_ body: any ATLExpression, iteratorName: String)
        -> ECoreExpression
    {
        // This would need more sophisticated variable substitution
        // For now, assume the body can be converted directly
        return body.toECoreExpression()
    }

    /// Map ATL collection operations to method names.
    private func collectionOperationToMethodName(_ op: ATLCollectionOperation) -> String {
        switch op {
        case .select:
            return "select"
        case .collect:
            return "collect"
        case .exists:
            return "exists"
        case .forAll:
            return "forAll"
        case .reject:
            return "reject"
        case .any:
            return "any"
        case .one:
            return "one"
        case .size:
            return "size"
        case .isEmpty:
            return "isEmpty"
        case .notEmpty:
            return "notEmpty"
        case .first:
            return "first"
        case .last:
            return "last"
        case .iterate:
            return "iterate"
        case .union:
            return "union"
        case .intersection:
            return "intersection"
        case .difference:
            return "difference"
        case .asSet:
            return "asSet"
        case .asSequence:
            return "asSequence"
        case .asBag:
            return "asBag"
        case .flatten:
            return "flatten"
        case .including:
            return "including"
        case .excluding:
            return "excluding"
        case .sortedBy:
            return "sortedBy"
        }
    }
}

// MARK: - Helper Call Expression Bridge

extension ATLHelperCallExpression {
    /// Convert ATL helper call to ECore method call expression.
    func toECoreExpression() -> ECoreExpression {
        let argumentExpressions = arguments.map { $0.toECoreExpression() }

        if false {  // TODO: Fix context handling when ATLHelperCallExpression has context support
            // Context helper: context.helperName(args)
            return .methodCall(
                receiver: .variable(name: "context"),  // Placeholder for context
                methodName: helperName,
                arguments: argumentExpressions
            )
        } else {
            // Context-free helper: treat as a variable reference to the helper
            return .methodCall(
                receiver: .variable(name: helperName),
                methodName: "invoke",
                arguments: argumentExpressions
            )
        }
    }
}

// MARK: - Rule Bridge Extensions

extension ATLRuleType {
    /// Convert ATL rule to ECore query expressions.
    ///
    /// ATL rules are converted to equivalent ECore expressions that can be
    /// executed using the ECore execution engine. This enables rule pattern
    /// matching and filtering to leverage the engine's optimisations.
    ///
    /// - Returns: Array of ECore expressions representing rule logic
    public func toECoreExpressions() -> [ECoreExpression] {
        var expressions: [ECoreExpression] = []

        // For now, return a placeholder expression based on rule name
        // Full implementation would need access to rule patterns
        let ruleExpr: ECoreExpression = .methodCall(
            receiver: .variable(name: "self"),
            methodName: "executeRule",
            arguments: [.literal(value: .string(name))]
        )
        expressions.append(ruleExpr)

        return expressions
    }
}

// MARK: - Helper Bridge Extensions

extension ATLHelperWrapper {
    /// Convert ATL helper body to ECore expression.
    ///
    /// Helper bodies are converted to ECore expressions that can be evaluated
    /// within the ECore execution engine's context management system.
    ///
    /// - Returns: ECore expression representing helper logic
    public func toECoreExpression() -> ECoreExpression {
        return bodyExpression.toECoreExpression()
    }
}

// MARK: - Model Bridge Extensions

// MARK: - Expression Value Conversion

extension ECoreExpressionValue {
    /// Create an ECore expression value from an ATL value.
    ///
    /// - Parameter atlValue: ATL value to convert
    /// - Returns: Equivalent ECore expression value
    public static func from(_ atlValue: Any?) -> ECoreExpressionValue {
        guard let value = atlValue else {
            return .null
        }

        switch value {
        case let stringValue as String:
            return .string(stringValue)
        case let intValue as Int:
            return .int(intValue)
        case let boolValue as Bool:
            return .boolean(boolValue)
        case let doubleValue as Double:
            return .double(doubleValue)
        case let floatValue as Float:
            return .float(floatValue)
        case let uuidValue as EUUID:
            return .uuid(uuidValue)
        default:
            // Handle unknown types safely
            if let stringValue = value as? String {
                return .string(stringValue)
            } else if let intValue = value as? Int {
                return .int(intValue)
            } else if let boolValue = value as? Bool {
                return .boolean(boolValue)
            } else {
                return .string("")
            }
        }
    }
}
