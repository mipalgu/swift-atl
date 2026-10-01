//
//  ATLLanguageExpressions.swift
//  ATL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// An enumeration literal such as `#Editable`.
///
/// An enumeration literal evaluates to the name of the literal as a string,
/// which is the representation swift-ecore uses for enumeration-typed attribute
/// values of dynamic objects. When the literal is bound to an attribute whose
/// type is an enumeration, the binding checks that the enumeration declares the
/// literal.
///
/// ## Example Usage
///
/// ```swift
/// // property <- #Editable
/// let literal = ATLEnumLiteralExpression(name: "Editable")
/// ```
public struct ATLEnumLiteralExpression: ATLExpression, Equatable, Hashable {

    /// The name of the enumeration literal, without the leading `#`.
    public let name: String

    /// Creates an enumeration literal expression.
    ///
    /// - Parameter name: The literal name, without the leading `#`.
    public init(name: String) {
        precondition(!name.isEmpty, "Enumeration literal name must not be empty")
        self.name = name
    }

    /// Evaluates to the literal name.
    ///
    /// - Parameter context: The execution context, which is not consulted.
    /// - Returns: The literal name as a string.
    @MainActor
    public func evaluate(in context: ATLExecutionContext) async throws -> (any EcoreValue)? {
        name
    }
}

/// The result of a built-in operation, which may legitimately be the undefined value.
struct ATLBuiltinResult {
    /// The value produced by the operation, or `nil` for the undefined value.
    let value: (any EcoreValue)?
}

/// Evaluation of operators whose semantics differ from the plain OCL library calls.
///
/// ATL operators treat the undefined value as a normal operand of `=` and `<>`,
/// use three-valued logic for `and`, `or`, `xor` and `implies`, and compare
/// model objects by identity.
enum ATLOperatorSemantics {

    /// Decides a logical operator from its left operand alone, if possible.
    ///
    /// `false and x`, `true or x` and `false implies x` do not depend on `x`, so
    /// the right operand is not evaluated.
    ///
    /// - Parameters:
    ///   - operator: The operator.
    ///   - left: The evaluated left operand.
    /// - Returns: The result, or `nil` when the right operand is needed.
    static func shortCircuit(_ operator: ATLBinaryOperator, left: (any EcoreValue)?)
        -> ATLBuiltinResult?
    {
        guard let flag = left as? Bool else { return nil }
        switch `operator` {
        case .and where !flag: return ATLBuiltinResult(value: false)
        case .or where flag: return ATLBuiltinResult(value: true)
        case .implies where !flag: return ATLBuiltinResult(value: true)
        default: return nil
        }
    }

    /// Evaluates the operators that this type owns.
    ///
    /// - Parameters:
    ///   - operator: The operator.
    ///   - left: The evaluated left operand.
    ///   - right: The evaluated right operand.
    /// - Returns: The result, or `nil` when the operator is evaluated by the OCL library.
    /// - Throws: ``ATLExecutionError`` for operands of the wrong type or division by zero.
    static func evaluate(
        _ operator: ATLBinaryOperator, left: (any EcoreValue)?, right: (any EcoreValue)?
    ) throws -> ATLBuiltinResult? {
        switch `operator` {
        case .equals:
            return ATLBuiltinResult(value: ATLValues.areEqual(left, right))
        case .notEquals:
            return ATLBuiltinResult(value: !ATLValues.areEqual(left, right))
        case .and, .or, .implies, .xor:
            return ATLBuiltinResult(value: try logical(`operator`, left, right))
        case .integerDivide:
            return ATLBuiltinResult(value: try integerDivide(left, right))
        default:
            return nil
        }
    }

    private static func truthValue(_ value: (any EcoreValue)?, _ operator: ATLBinaryOperator) throws
        -> Bool?
    {
        guard let value else { return nil }
        guard let flag = value as? Bool else {
            throw ATLExecutionError.typeError(
                "Operator '\(`operator`.rawValue)' requires Boolean operands but was given \(type(of: value))"
            )
        }
        return flag
    }

    /// Three-valued logic: an undefined operand yields an undefined result unless the other operand decides it.
    private static func logical(
        _ operator: ATLBinaryOperator, _ left: (any EcoreValue)?, _ right: (any EcoreValue)?
    ) throws -> Bool? {
        let l = try truthValue(left, `operator`)
        let r = try truthValue(right, `operator`)

        switch `operator` {
        case .and:
            if l == false || r == false { return false }
            return (l == nil || r == nil) ? nil : true
        case .or:
            if l == true || r == true { return true }
            return (l == nil || r == nil) ? nil : false
        case .implies:
            if l == false || r == true { return true }
            return (l == nil || r == nil) ? nil : false
        default:
            guard let l, let r else { return nil }
            return l != r
        }
    }

    private static func integerDivide(_ left: (any EcoreValue)?, _ right: (any EcoreValue)?) throws
        -> Int
    {
        guard let dividend = left as? Int, let divisor = right as? Int else {
            throw ATLExecutionError.typeError("Operator 'div' requires Integer operands")
        }
        guard divisor != 0 else { throw ATLExecutionError.divisionByZero }
        return dividend / divisor
    }
}

/// Adaptation of expression results to the features they are assigned to.
enum ATLValueConversion {

    /// Prepares a value for storing into a structural feature.
    ///
    /// Set and ordered set values become plain arrays, because models store
    /// collections as arrays. For attributes typed by an enumeration, the value
    /// must name one of the enumeration's literals (an integer is mapped to the
    /// literal with that value); the literal name is stored. Integers assigned to
    /// real attributes become reals.
    ///
    /// - Parameters:
    ///   - value: The evaluated value.
    ///   - feature: The feature the value is assigned to.
    /// - Returns: The value to store, or `nil` for the undefined value.
    /// - Throws: ``ATLExecutionError/invalidEnumerationLiteral(_:)`` when an enumeration-typed
    ///   attribute is given a value that is not one of its literals.
    static func prepare(_ value: Any?, for feature: any EStructuralFeature) throws
        -> (any EcoreValue)?
    {
        guard var prepared = value as? (any EcoreValue) else { return nil }
        if let collection = prepared as? ATLCollectionValue {
            prepared = collection.asEcoreValueArray
        }
        guard let attribute = feature as? EAttribute else { return prepared }

        if let enumeration = attribute.eType as? EEnum {
            if let array = prepared as? EcoreValueArray {
                return EcoreValueArray(try array.values.map { try literal($0, in: enumeration) })
            }
            return try literal(prepared, in: enumeration)
        }
        return coerceNumber(prepared, to: attribute.eType.name)
    }

    /// Prepares a value for storing into a named feature of an object.
    ///
    /// - Parameters:
    ///   - value: The evaluated value.
    ///   - property: The feature name.
    ///   - object: The object whose class declares the feature.
    /// - Returns: The value to store, converted as for ``prepare(_:for:)`` when the feature is known.
    /// - Throws: ``ATLExecutionError/invalidEnumerationLiteral(_:)`` for an invalid enumeration literal.
    static func prepare(_ value: Any?, property: String, of object: any EObject) throws
        -> (any EcoreValue)?
    {
        guard let eClass = object.eClass as? EClass,
            let feature = eClass.getStructuralFeature(name: property)
        else {
            return (value as? ATLCollectionValue)?.asEcoreValueArray ?? value as? (any EcoreValue)
        }
        return try prepare(value, for: feature)
    }

    private static func literal(_ value: any EcoreValue, in enumeration: EEnum) throws
        -> any EcoreValue
    {
        if let name = value as? String, enumeration.getLiteral(name: name) != nil {
            return name
        }
        if let number = value as? Int, let literal = enumeration.getLiteral(value: number) {
            return literal.name
        }
        let known = enumeration.literals.map(\.name).joined(separator: ", ")
        throw ATLExecutionError.invalidEnumerationLiteral(
            "'\(value)' is not a literal of enumeration '\(enumeration.name)' (literals: \(known))")
    }

    private static func coerceNumber(_ value: any EcoreValue, to typeName: String) -> any EcoreValue {
        let realTypes = [EcoreDataType.eDouble.rawValue, EcoreDataType.eDoubleObject.rawValue]
        if let number = value as? Int, realTypes.contains(typeName) {
            return Double(number)
        }
        return value
    }
}
