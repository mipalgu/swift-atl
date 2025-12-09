//
//  OCLTupleExpression.swift
//  OCL
//
//  Created by Rene Hexel on 9/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
//  OCL tuple expression support.
//
import ECore
import Foundation
import OrderedCollections

// MARK: - Tuple Expression

/// Represents an OCL tuple expression with typed fields.
///
/// Tuple expressions create structured composite values with named fields,
/// following the OCL syntax:
/// ```
/// Tuple{field1 : Type1 = value1, field2 : Type2 = value2, ...}
/// ```
///
/// ## Example Usage
///
/// ```swift
/// let tupleExpr = OCLTupleExpression(
///     fields: [
///         ("author", "String", OCLNavigationExpression(...)),
///         ("pages", "Integer", OCLNavigationExpression(...))
///     ]
/// )
/// ```
public struct OCLTupleExpression: OCLExpression {
    /// Tuple field definition.
    public typealias TupleField = (name: String, type: String?, value: any OCLExpression)

    /// The fields of the tuple.
    public let fields: [TupleField]

    /// Creates a new tuple expression.
    ///
    /// - Parameter fields: The tuple fields with names, optional types, and value expressions
    public init(fields: [TupleField]) {
        self.fields = fields
    }

    @MainActor
    public func evaluate(in context: OCLExecutionContext) async throws -> (any EcoreValue)? {
        var result: OrderedDictionary<String, any EcoreValue> = [:]

        for field in fields {
            let value = try await field.value.evaluate(in: context)
            if let value = value {
                result[field.name] = value
            }
        }

        // Return as a dictionary which conforms to EcoreValue when it contains EcoreValue values
        return result as? (any EcoreValue)
    }

    public static func == (lhs: OCLTupleExpression, rhs: OCLTupleExpression) -> Bool {
        guard lhs.fields.count == rhs.fields.count else { return false }

        for (lField, rField) in zip(lhs.fields, rhs.fields) {
            guard lField.name == rField.name && lField.type == rField.type else {
                return false
            }
            guard areOCLExpressionsEqual(lField.value, rField.value) else {
                return false
            }
        }

        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(fields.count)
        for field in fields {
            hasher.combine(field.name)
            hasher.combine(field.type)
            hashOCLExpression(field.value, into: &hasher)
        }
    }
}
