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

    /// The source range the node was parsed from, if it was parsed.
    ///
    /// The origin never takes part in equality or hashing, so nodes that differ only
    /// in where they were written compare equal.
    public let origin: SourceOrigin

    /// Creates an enumeration literal expression.
    ///
    /// - Parameters:
    ///   - name: The literal name, without the leading `#`.
    ///   - origin: The source range the node was parsed from.
    public init(name: String, origin: SourceOrigin = .init()) {
        precondition(!name.isEmpty, "Enumeration literal name must not be empty")
        self.name = name
        self.origin = origin
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

/// A range of integers that is a part of a collection literal, as in `Sequence{1..3}`.
///
/// A range stands for every integer from its first to its last value, both
/// included and in ascending order. It may appear in a `Sequence`, `Set`,
/// `OrderedSet` or `Bag` literal and may be mixed with ordinary items, as in
/// `Sequence{0, 2..4, 9}`, which holds `0, 2, 3, 4, 9`. A range whose first value
/// is greater than its last value contributes no elements, and a `Set` or an
/// `OrderedSet` keeps only the first occurrence of each integer.
///
/// Both bounds may be arbitrary expressions, but each must evaluate to an
/// `Integer`; any other value, including the undefined value, is a type error.
///
/// ## Example Usage
///
/// ```swift
/// // Sequence{1..n}
/// let literal = ATLCollectionLiteralExpression(
///     collectionType: "Sequence",
///     elements: [
///         ATLCollectionRangeExpression(
///             first: ATLLiteralExpression(value: 1),
///             last: ATLVariableExpression(name: "n"))
///     ])
/// ```
public struct ATLCollectionRangeExpression: ATLExpression, Equatable, Hashable {

    /// The expression for the first integer of the range.
    public let first: any ATLExpression

    /// The expression for the last integer of the range.
    public let last: any ATLExpression

    /// The source range the node was parsed from, if it was parsed.
    ///
    /// The origin never takes part in equality or hashing, so nodes that differ only
    /// in where they were written compare equal.
    public let origin: SourceOrigin

    /// Creates a collection range.
    ///
    /// - Parameters:
    ///   - first: The expression for the first integer of the range.
    ///   - last: The expression for the last integer of the range.
    ///   - origin: The source range the node was parsed from.
    public init(first: any ATLExpression, last: any ATLExpression, origin: SourceOrigin = .init()) {
        self.first = first
        self.last = last
        self.origin = origin
    }

    /// Evaluates the range to the sequence of the integers it spans.
    ///
    /// Inside a collection literal, the integers become elements of the literal
    /// instead, so a range never appears there as a nested sequence.
    ///
    /// - Parameter context: The execution context in which the bounds are evaluated.
    /// - Returns: A `Sequence` of the integers from the first to the last value.
    /// - Throws: ``ATLExecutionError/typeError(_:)`` when a bound is not an `Integer`,
    ///   or ``ATLExecutionError/runtimeError(_:)`` when the range is too long to build.
    @MainActor
    public func evaluate(in context: ATLExecutionContext) async throws -> (any EcoreValue)? {
        ATLCollections.make(kind: .sequence, try await integers(in: context))
    }

    /// Evaluates the bounds and returns the integers the range spans.
    ///
    /// - Parameter context: The execution context in which the bounds are evaluated.
    /// - Returns: The integers from the first to the last value in ascending order,
    ///   or no integers when the first value is greater than the last value.
    /// - Throws: ``ATLExecutionError/typeError(_:)`` when a bound is not an `Integer`,
    ///   or ``ATLExecutionError/runtimeError(_:)`` when the range would hold more than
    ///   the number of integers that `includingRange` may add in one call.
    @MainActor
    func integers(in context: ATLExecutionContext) async throws -> [any EcoreValue] {
        let low = try Self.bound(try await first.evaluate(in: context), named: "first")
        let high = try Self.bound(try await last.evaluate(in: context), named: "last")
        guard low <= high else { return [] }
        let limit = ATLBuiltinOperations.maximumRangeLength
        let (span, overflow) = high.subtractingReportingOverflow(low)
        guard !overflow, span < limit else {
            throw ATLExecutionError.runtimeError(
                "The collection range \(low)\(ATLLanguage.rangeSeparator)\(high) holds more than \(limit) integers")
        }
        return (low...high).map { $0 as any EcoreValue }
    }

    /// Checks that a bound of the range is an integer.
    ///
    /// - Parameters:
    ///   - value: The value of the bound.
    ///   - role: Which bound the value is, for the error message.
    /// - Returns: The integer value of the bound.
    /// - Throws: ``ATLExecutionError/typeError(_:)`` when the value is not an `Integer`.
    private static func bound(_ value: (any EcoreValue)?, named role: String) throws -> Int {
        guard let integer = value as? Int else {
            let integerType = ATLLanguage.PrimitiveType.integer.rawValue
            throw ATLExecutionError.typeError(
                "The \(role) value of a collection range must be an \(integerType), not \(ATLTypeMatching.typeName(of: value))")
        }
        return integer
    }

    /// Compares two ranges by their bounds.
    ///
    /// - Parameters:
    ///   - lhs: The first range.
    ///   - rhs: The second range.
    /// - Returns: `true` when both bounds are equal expressions.
    public static func == (lhs: ATLCollectionRangeExpression, rhs: ATLCollectionRangeExpression)
        -> Bool
    {
        areATLExpressionsEqual(lhs.first, rhs.first) && areATLExpressionsEqual(lhs.last, rhs.last)
    }

    /// Hashes the bounds of the range.
    ///
    /// - Parameter hasher: The hasher to combine the bounds into.
    public func hash(into hasher: inout Hasher) {
        hashATLExpression(first, into: &hasher)
        hashATLExpression(last, into: &hasher)
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
    ///   - integerDivision: What `/` yields for two Integer operands.
    /// - Returns: The result, or `nil` when the operator is evaluated by the OCL library.
    /// - Throws: ``ATLExecutionError`` for operands of the wrong type or division by zero.
    static func evaluate(
        _ operator: ATLBinaryOperator, left: (any EcoreValue)?, right: (any EcoreValue)?,
        integerDivision: ATLIntegerDivision
    ) throws -> ATLBuiltinResult? {
        switch `operator` {
        case .divide:
            return try divideIntegers(left, right, integerDivision).map { ATLBuiltinResult(value: $0) }
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

    /// Divides two Integers with the `/` operator.
    ///
    /// With ``ATLIntegerDivision/real``, the quotient is a Real, as `/` is in OCL and
    /// Eclipse ATL. With ``ATLIntegerDivision/truncating``, it is the Integer that
    /// `div` yields. Operands that are not both Integers are left to the division of
    /// the OCL library, which yields a Real.
    ///
    /// - Parameters:
    ///   - left: The dividend.
    ///   - right: The divisor.
    ///   - integerDivision: What the quotient of two Integers is.
    /// - Returns: The quotient, or `nil` when an operand is not an Integer.
    /// - Throws: ``ATLExecutionError/divisionByZero`` when both operands are Integers and
    ///   the divisor is zero.
    private static func divideIntegers(
        _ left: (any EcoreValue)?, _ right: (any EcoreValue)?, _ integerDivision: ATLIntegerDivision
    ) throws -> (any EcoreValue)? {
        guard let dividend = left as? Int, let divisor = right as? Int else { return nil }
        switch integerDivision {
        case .real:
            guard divisor != 0 else { throw ATLExecutionError.divisionByZero }
            return Double(dividend) / Double(divisor)
        case .truncating:
            return try integerDivide(dividend, divisor)
        }
    }

    /// Divides two integers, discarding the remainder.
    ///
    /// The quotient is truncated towards zero, as in Java, which ATL builds on.
    /// This implements both the `div` operator and the `div` operation.
    ///
    /// - Parameters:
    ///   - left: The dividend.
    ///   - right: The divisor.
    /// - Returns: The integer quotient.
    /// - Throws: ``ATLExecutionError/typeError(_:)`` when an operand is not an Integer, and
    ///   ``ATLExecutionError/divisionByZero`` when the divisor is zero.
    static func integerDivide(_ left: (any EcoreValue)?, _ right: (any EcoreValue)?) throws
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
@MainActor
enum ATLValueConversion {

    /// Prepares a value for storing into a structural feature.
    ///
    /// Set, ordered set and bag values become plain arrays, because models store
    /// collections as arrays. Values of many-valued attributes are stored as
    /// typed arrays (`[String]`, `[Int]`, `[Double]` or `[Bool]`). A collection
    /// assigned to a many-valued attribute contributes its elements, nested
    /// collections are flattened by one level, and a single value becomes a
    /// one-element array. For attributes typed by an
    /// enumeration, the value must name one of the enumeration's literals, by
    /// name or by literal text (an integer is mapped to the literal with that
    /// value); the literal name is stored.
    ///
    /// A value of an attribute typed by a primitive Ecore type, and each value of a
    /// many-valued one, must have that type, as the Eclipse Modeling Framework requires:
    /// an Integer for `EInt`, `ELong`, `EShort`, `EByte` and `EBigInteger` and their object
    /// types, a Real or an Integer for `EDouble`, `EFloat` and `EBigDecimal` and their
    /// object types, a Boolean for `EBoolean` and a String for `EString`. A Real is never
    /// an Integer, even when its value is integral. Integers assigned to `EDouble` and
    /// `EFloat` attributes become Reals. Attributes of other data types take any value,
    /// and a collection assigned to a single-valued attribute that is not typed by an
    /// enumeration is stored as a list.
    ///
    /// - Parameters:
    ///   - value: The evaluated value.
    ///   - feature: The feature the value is assigned to.
    ///   - className: The name of the class whose element is assigned, which error
    ///     messages name when it is given.
    /// - Returns: The value to store, or `nil` for the undefined value.
    /// - Throws: ``ATLExecutionError/invalidEnumerationLiteral(_:)`` when an enumeration-typed
    ///   attribute is given a value that is not one of its literals, and
    ///   ``ATLExecutionError/typeError(_:)`` when an attribute of a primitive Ecore type is
    ///   given a value of another type.
    static func prepare(_ value: Any?, for feature: any EStructuralFeature, in className: String? = nil)
        throws -> (any EcoreValue)?
    {
        guard let value = value as? (any EcoreValue) else { return nil }
        let prepared = ATLCollections.storable(value)
        guard let attribute = feature as? EAttribute else { return prepared }

        let enumeration = attribute.eType as? EEnum
        if attribute.isMany {
            if let enumeration {
                return EcoreValueArray(
                    try flattened(prepared).map { try literal($0, in: enumeration) })
            }
            let elements = flattened(prepared)
            return try manyValued(
                elements.map { try convert($0, for: attribute, enumeration: enumeration, in: className) },
                of: attribute)
        }
        if let array = prepared as? EcoreValueArray, enumeration != nil {
            return EcoreValueArray(
                try array.values.map {
                    try convert($0, for: attribute, enumeration: enumeration, in: className)
                })
        }
        return try convert(prepared, for: attribute, enumeration: enumeration, in: className)
    }

    /// Prepares a value for storing into a named feature of an object.
    ///
    /// - Parameters:
    ///   - value: The evaluated value.
    ///   - property: The feature name.
    ///   - object: The object whose class declares the feature.
    /// - Returns: The value to store, converted as for ``prepare(_:for:in:)`` when the feature is known.
    /// - Throws: ``ATLExecutionError/invalidEnumerationLiteral(_:)`` for an invalid enumeration
    ///   literal and ``ATLExecutionError/typeError(_:)`` for a value of another type than the
    ///   primitive Ecore type of the attribute.
    static func prepare(_ value: Any?, property: String, of object: any EObject) throws
        -> (any EcoreValue)?
    {
        guard let eClass = object.eClass as? EClass,
            let feature = eClass.getStructuralFeature(name: property)
        else {
            return (value as? (any EcoreValue)).map(ATLCollections.storable)
        }
        return try prepare(value, for: feature, in: eClass.name)
    }

    /// Lists the elements a value contributes to a many-valued feature.
    ///
    /// A collection, including a typed array such as `[String]`, contributes its
    /// elements, and a collection nested within it (as produced by `collect`)
    /// contributes its elements in turn, so that nesting is flattened by one
    /// level. A single value contributes itself.
    private static func flattened(_ value: any EcoreValue) -> [any EcoreValue] {
        ATLCollections.elements(of: value).flatMap { element -> [any EcoreValue] in
            ATLCollections.isCollection(element) ? ATLCollections.elements(of: element) : [element]
        }
    }

    /// Converts a single value for an attribute.
    ///
    /// - Parameters:
    ///   - value: The value.
    ///   - attribute: The attribute the value is assigned to.
    ///   - enumeration: The enumeration that types the attribute, if any.
    ///   - className: The name of the class whose element is assigned, if known.
    /// - Returns: The value to store.
    /// - Throws: ``ATLExecutionError/invalidEnumerationLiteral(_:)`` and
    ///   ``ATLExecutionError/typeError(_:)`` as ``prepare(_:for:in:)`` describes.
    private static func convert(
        _ value: any EcoreValue, for attribute: EAttribute, enumeration: EEnum?, in className: String?
    ) throws -> any EcoreValue {
        if let enumeration {
            return try literal(value, in: enumeration)
        }
        return try checked(value, for: attribute, in: className)
    }

    /// The kinds of value that the attributes of the primitive Ecore types hold.
    private enum PrimitiveKind {
        /// Integers, for the integer types.
        case integer
        /// Reals, or Integers that stand for Reals, for the floating point and decimal types.
        case real
        /// Booleans.
        case boolean
        /// Strings.
        case string

        /// The kind of value of a data type, if it is a primitive Ecore type.
        ///
        /// - Parameter typeName: The name of the data type.
        init?(typeName: String) {
            switch EcoreDataType(rawValue: typeName) {
            case .eInt, .eIntegerObject, .eLong, .eLongObject, .eShort, .eShortObject, .eByte,
                .eByteObject, .eBigInteger:
                self = .integer
            case .eDouble, .eDoubleObject, .eFloat, .eFloatObject, .eBigDecimal:
                self = .real
            case .eBoolean, .eBooleanObject:
                self = .boolean
            case .eString, .eStringObject:
                self = .string
            default:
                return nil
            }
        }
    }

    /// The primitive Ecore types whose attributes store Integers as Reals.
    private static let widenedRealTypes: Set<String> = [
        EcoreDataType.eDouble.rawValue, EcoreDataType.eDoubleObject.rawValue,
        EcoreDataType.eFloat.rawValue, EcoreDataType.eFloatObject.rawValue,
    ]

    /// Checks that a single value suits an attribute.
    ///
    /// - Parameters:
    ///   - value: The value.
    ///   - attribute: The attribute the value is assigned to.
    ///   - className: The name of the class whose element is assigned, if known.
    /// - Returns: The value, with an Integer widened to a Real for an `EDouble` or `EFloat`
    ///   attribute; a collection is returned as it is.
    /// - Throws: ``ATLExecutionError/typeError(_:)`` when the attribute is typed by a
    ///   primitive Ecore type that the value does not have.
    private static func checked(_ value: any EcoreValue, for attribute: EAttribute, in className: String?)
        throws -> any EcoreValue
    {
        let typeName = attribute.eType.name
        guard let kind = PrimitiveKind(typeName: typeName), !ATLCollections.isCollection(value) else {
            return value
        }
        let isInteger = value is any BinaryInteger
        let isReal = value is any BinaryFloatingPoint || value is Decimal
        switch kind {
        case .integer where isInteger, .real where isReal, .boolean where value is Bool,
            .string where value is String:
            return value
        case .real where isInteger:
            guard widenedRealTypes.contains(typeName), let integer = value as? any BinaryInteger else {
                return value
            }
            return Double(integer)
        default:
            throw ATLExecutionError.typeError(
                ATLExecutionMessage.attributeType(
                    value: ATLValueText.render(value), valueType: ATLTypeMatching.typeName(of: value),
                    attribute: attribute.name, className: className, attributeType: typeName,
                    suggestsInteger: kind == .integer && isReal))
        }
    }

    /// Chooses the stored form of the values of a many-valued attribute.
    ///
    /// Values of one primitive type are stored as a typed array (`[String]`,
    /// `[Int]`, `[Double]` or `[Bool]`), which is the form a loaded model uses.
    /// An empty list takes the type of the attribute. Other values, and the
    /// literal names of enumeration-typed attributes, are stored as an
    /// `EcoreValueArray`.
    private static func manyValued(_ values: [any EcoreValue], of attribute: EAttribute)
        -> any EcoreValue
    {
        if let strings = values as? [String], !values.isEmpty { return strings }
        if let integers = values as? [Int], !values.isEmpty { return integers }
        if let reals = values as? [Double], !values.isEmpty { return reals }
        if let booleans = values as? [Bool], !values.isEmpty { return booleans }
        guard values.isEmpty else { return EcoreValueArray(values) }
        switch attribute.eType.name {
        case EcoreDataType.eInt.rawValue, EcoreDataType.eIntegerObject.rawValue,
            EcoreDataType.eLong.rawValue, EcoreDataType.eLongObject.rawValue:
            return [Int]()
        case EcoreDataType.eDouble.rawValue, EcoreDataType.eDoubleObject.rawValue,
            EcoreDataType.eFloat.rawValue, EcoreDataType.eFloatObject.rawValue:
            return [Double]()
        case EcoreDataType.eBoolean.rawValue, EcoreDataType.eBooleanObject.rawValue:
            return [Bool]()
        default: return [String]()
        }
    }

    /// Finds the literal of an enumeration that a value denotes.
    ///
    /// A string denotes a literal by its name or, failing that, by its literal
    /// text; an integer denotes the literal with that value. The literal name
    /// is returned.
    private static func literal(_ value: any EcoreValue, in enumeration: EEnum) throws
        -> any EcoreValue
    {
        if let name = value as? String {
            if enumeration.getLiteral(name: name) != nil { return name }
            if let match = enumeration.literals.first(where: { $0.literal == name }) {
                return match.name
            }
        }
        if let number = value as? Int, let literal = enumeration.getLiteral(value: number) {
            return literal.name
        }
        let known = enumeration.literals.map(\.name).joined(separator: ", ")
        throw ATLExecutionError.invalidEnumerationLiteral(
            "'\(value)' is not a literal of enumeration '\(enumeration.name)' (literals: \(known))")
    }
}
