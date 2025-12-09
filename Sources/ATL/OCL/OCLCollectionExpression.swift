//
//  OCLCollectionExpression.swift
//  OCL
//
//  Created by Rene Hexel on 9/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
//  OCL collection expression types and iterator operations.
//  Based on the Eclipse ATL OCL metamodel collection operations.
//
import ECore
import Foundation

// MARK: - Lambda Expression

/// OCL Lambda Expression for iterator operations.
///
/// Lambda expressions represent function-like constructs used in OCL collection
/// operations such as `select`, `reject`, `collect`, `exists`, and `forAll`.
///
/// ## Example Usage
///
/// ```swift
/// // Equivalent to OCL: collection->select(item | item.age > 18)
/// let lambda = OCLLambdaExpression(
///     parameter: "item",
///     body: OCLBinaryOperationExpression(...)
/// )
/// ```
public struct OCLLambdaExpression: OCLExpression {
    /// The parameter name for the lambda variable.
    public let parameter: String

    /// The expression body of the lambda.
    public let body: any OCLExpression

    /// Creates a lambda expression.
    ///
    /// - Parameters:
    ///   - parameter: The name of the lambda parameter
    ///   - body: The expression to evaluate with the parameter bound
    public init(parameter: String, body: any OCLExpression) {
        self.parameter = parameter
        self.body = body
    }

    @MainActor
    public func evaluate(in context: OCLExecutionContext) async throws -> (any EcoreValue)? {
        return try await body.evaluate(in: context)
    }

    /// Evaluates the lambda expression with a parameter value bound.
    ///
    /// - Parameters:
    ///   - parameterValue: The value to bind to the lambda parameter
    ///   - context: The execution context
    /// - Returns: The evaluation result
    /// - Throws: OCL execution errors
    @MainActor
    public func evaluateWith(
        parameterValue: (any EcoreValue)?,
        in context: OCLExecutionContext
    ) async throws -> (any EcoreValue)? {
        context.pushScope()
        defer {
            context.popScope()
        }

        context.setVariable(parameter, value: parameterValue)
        return try await body.evaluate(in: context)
    }

    public static func == (lhs: OCLLambdaExpression, rhs: OCLLambdaExpression) -> Bool {
        return lhs.parameter == rhs.parameter && areOCLExpressionsEqual(lhs.body, rhs.body)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(parameter)
        hashOCLExpression(body, into: &hasher)
    }
}

// MARK: - Iterate Expression

/// Represents an OCL iterate expression with the full OCL syntax.
///
/// Supports the complete OCL iterate syntax:
/// ```
/// collection->iterate(param; accumulator : Type = defaultValue | body_expression)
/// ```
///
/// ## Example Usage
///
/// ```swift
/// let sum = OCLIterateExpression(
///     source: numbersExpr,
///     parameter: "n",
///     accumulator: "sum",
///     accumulatorType: "Integer",
///     defaultValue: OCLLiteralExpression(value: 0),
///     body: addExpr
/// )
/// ```
public struct OCLIterateExpression: OCLExpression {
    /// The source collection expression.
    public let source: any OCLExpression

    /// The iteration parameter name.
    public let parameter: String

    /// The accumulator variable name.
    public let accumulator: String

    /// The accumulator type (optional).
    public let accumulatorType: String?

    /// The default value for the accumulator.
    public let defaultValue: any OCLExpression

    /// The body expression that computes the new accumulator value.
    public let body: any OCLExpression

    /// Creates a new iterate expression.
    ///
    /// - Parameters:
    ///   - source: The source collection expression
    ///   - parameter: The iteration parameter name
    ///   - accumulator: The accumulator variable name
    ///   - accumulatorType: The accumulator type (optional)
    ///   - defaultValue: The default value for the accumulator
    ///   - body: The body expression
    public init(
        source: any OCLExpression,
        parameter: String,
        accumulator: String,
        accumulatorType: String? = nil,
        defaultValue: any OCLExpression,
        body: any OCLExpression
    ) {
        self.source = source
        self.parameter = parameter
        self.accumulator = accumulator
        self.accumulatorType = accumulatorType
        self.defaultValue = defaultValue
        self.body = body
    }

    @MainActor
    public func evaluate(in context: OCLExecutionContext) async throws -> (any EcoreValue)? {
        guard let sourceValue = try await source.evaluate(in: context) else {
            throw OCLExecutionError.typeError("iterate() requires non-nil collection")
        }

        guard let collection = sourceValue as? [Any] else {
            throw OCLExecutionError.typeError("iterate() requires Collection receiver")
        }

        var accValue = try await defaultValue.evaluate(in: context)

        context.pushScope()
        defer {
            context.popScope()
        }

        for item in collection {
            context.setVariable(parameter, value: item as? (any EcoreValue))
            context.setVariable(accumulator, value: accValue)
            accValue = try await body.evaluate(in: context)
        }

        return accValue
    }

    public static func == (lhs: OCLIterateExpression, rhs: OCLIterateExpression) -> Bool {
        return areOCLExpressionsEqual(lhs.source, rhs.source)
            && lhs.parameter == rhs.parameter
            && lhs.accumulator == rhs.accumulator
            && lhs.accumulatorType == rhs.accumulatorType
            && areOCLExpressionsEqual(lhs.defaultValue, rhs.defaultValue)
            && areOCLExpressionsEqual(lhs.body, rhs.body)
    }

    public func hash(into hasher: inout Hasher) {
        hashOCLExpression(source, into: &hasher)
        hasher.combine(parameter)
        hasher.combine(accumulator)
        hasher.combine(accumulatorType)
        hashOCLExpression(defaultValue, into: &hasher)
        hashOCLExpression(body, into: &hasher)
    }
}

// MARK: - Collection Literal Expression

/// Represents an OCL collection literal expression.
///
/// Collection literals create collections with explicit element values,
/// supporting Sequence, Set, Bag, and OrderedSet collection types.
///
/// ## Example Usage
///
/// ```swift
/// let seqLit = OCLCollectionLiteralExpression(
///     collectionType: "Sequence",
///     elements: [
///         OCLLiteralExpression(value: 1),
///         OCLLiteralExpression(value: 2),
///         OCLLiteralExpression(value: 3)
///     ]
/// )
/// ```
public struct OCLCollectionLiteralExpression: OCLExpression {
    /// The type of collection (e.g., "Sequence", "Set", "Bag", "OrderedSet").
    public let collectionType: String

    /// The expressions for the collection elements.
    public let elements: [any OCLExpression]

    /// Creates a new collection literal expression.
    ///
    /// - Parameters:
    ///   - collectionType: The collection type identifier
    ///   - elements: The element expressions
    public init(collectionType: String, elements: [any OCLExpression]) {
        self.collectionType = collectionType
        self.elements = elements
    }

    @MainActor
    public func evaluate(in context: OCLExecutionContext) async throws -> (any EcoreValue)? {
        var evaluatedElements: [String] = []
        for elementExpr in elements {
            if let value = try await elementExpr.evaluate(in: context) {
                evaluatedElements.append("\(value)")
            }
        }

        switch collectionType {
        case "Sequence":
            return evaluatedElements
        case "Set":
            return Array(Set(evaluatedElements))
        case "Bag":
            return evaluatedElements
        case "OrderedSet":
            // Remove duplicates while preserving order
            var seen = Set<String>()
            var ordered: [String] = []
            for element in evaluatedElements {
                if !seen.contains(element) {
                    seen.insert(element)
                    ordered.append(element)
                }
            }
            return ordered
        default:
            throw OCLExecutionError.unsupportedOperation("Unknown collection type: \(collectionType)")
        }
    }

    public static func == (lhs: OCLCollectionLiteralExpression, rhs: OCLCollectionLiteralExpression) -> Bool {
        guard lhs.collectionType == rhs.collectionType && lhs.elements.count == rhs.elements.count else {
            return false
        }

        for (leftElement, rightElement) in zip(lhs.elements, rhs.elements) {
            if type(of: leftElement) != type(of: rightElement) {
                return false
            }
        }
        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(collectionType)
        hasher.combine(elements.count)
        for element in elements {
            hasher.combine(ObjectIdentifier(type(of: element)))
        }
    }
}

// MARK: - Collection Expression

/// Collection operations supported by OCL.
public enum OCLCollectionOperation: String, Sendable, CaseIterable, Equatable, Hashable {
    // Iterator operations
    case select, reject, collect, exists, forAll, any, one, iterate

    // Query operations
    case size, isEmpty, notEmpty, first, last

    // Set operations
    case union, intersection, difference

    // Type conversions
    case asSet, asSequence, asBag, asOrderedSet, flatten

    // Collection modification
    case including, excluding

    // Sorting
    case sortedBy
}

/// Represents an OCL collection operation expression.
///
/// Collection expressions handle OCL-style collection operations that don't
/// require complex iterator expressions (those use specific expression types).
///
/// ## Example Usage
///
/// ```swift
/// let sizeExpr = OCLCollectionExpression(
///     source: collectionExpr,
///     operation: .size
/// )
/// ```
public struct OCLCollectionExpression: OCLExpression {
    /// The source collection expression.
    public let source: any OCLExpression

    /// The collection operation to perform.
    public let operation: OCLCollectionOperation

    /// The iterator variable name for operations that require one.
    public let iterator: String?

    /// The body expression for iterator-based operations.
    public let body: (any OCLExpression)?

    /// Creates a new collection expression.
    ///
    /// - Parameters:
    ///   - source: The source collection
    ///   - operation: The collection operation
    ///   - iterator: Optional iterator variable name
    ///   - body: Optional body expression for iterator operations
    public init(
        source: any OCLExpression,
        operation: OCLCollectionOperation,
        iterator: String? = nil,
        body: (any OCLExpression)? = nil
    ) {
        self.source = source
        self.operation = operation
        self.iterator = iterator
        self.body = body
    }

    @MainActor
    public func evaluate(in context: OCLExecutionContext) async throws -> (any EcoreValue)? {
        let sourceValue = try await source.evaluate(in: context)

        switch operation {
        case .size:
            if let collection = sourceValue as? [any EcoreValue] {
                return collection.count
            } else if let string = sourceValue as? String {
                return string.count
            }
            return 0

        case .isEmpty:
            if let collection = sourceValue as? [any EcoreValue] {
                return collection.isEmpty
            } else if let string = sourceValue as? String {
                return string.isEmpty
            }
            return true

        case .notEmpty:
            if let collection = sourceValue as? [any EcoreValue] {
                return !collection.isEmpty
            } else if let string = sourceValue as? String {
                return !string.isEmpty
            }
            return false

        default:
            // Complex operations handled by OCLMethodCallExpression
            return nil
        }
    }

    public static func == (lhs: OCLCollectionExpression, rhs: OCLCollectionExpression) -> Bool {
        guard lhs.operation == rhs.operation && lhs.iterator == rhs.iterator else { return false }

        guard type(of: lhs.source) == type(of: rhs.source) else { return false }
        guard areOCLExpressionsEqual(lhs.source, rhs.source) else { return false }

        switch (lhs.body, rhs.body) {
        case (nil, nil):
            return true
        case (let lhsBody?, let rhsBody?):
            guard type(of: lhsBody) == type(of: rhsBody) else { return false }
            return areOCLExpressionsEqual(lhsBody, rhsBody)
        default:
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(operation)
        hasher.combine(iterator)
        hasher.combine(String(describing: type(of: source)))
        hashOCLExpression(source, into: &hasher)

        if let body = body {
            hasher.combine(String(describing: type(of: body)))
            hashOCLExpression(body, into: &hasher)
        } else {
            hasher.combine("nil")
        }
    }
}
