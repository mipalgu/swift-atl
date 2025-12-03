//
// Ecoretypes.swift
// SwiftEcore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

// MARK: - Marker Protocol

/// Marker protocol for types that can be stored as Ecore values
///
/// All Ecore primitive types and model elements conform to this protocol,
/// providing type-safe storage and retrieval.
public protocol EcoreValue: Sendable, Equatable, Hashable {}

// MARK: - EMF Primitive Type Mappings

/// Unique identifier type for Ecore model elements.
///
/// Maps to Swift's `UUID` type for universal uniqueness across all model elements.
public typealias EUUID = UUID

/// String type for Ecore models.
///
/// Maps to Swift's native `String` type.
public typealias EString = String

/// Integer type for Ecore models.
///
/// Maps to Swift's native `Int` type, providing platform-specific integer precision.
public typealias EInt = Int

/// Boolean type for Ecore models.
///
/// Maps to Swift's native `Bool` type for true/false values.
public typealias EBoolean = Bool

/// Single-precision floating-point type for Ecore models.
///
/// Maps to Swift's `Float` type (32-bit IEEE 754 floating point).
public typealias EFloat = Float

/// Double-precision floating-point type for Ecore models.
///
/// Maps to Swift's `Double` type (64-bit IEEE 754 floating point).
public typealias EDouble = Double

/// Date and time type for Ecore models.
///
/// Maps to Swift's `Date` type for temporal values.
public typealias EDate = Date

/// Character type for Ecore models.
///
/// Maps to Swift's `Character` type for single Unicode scalar values.
public typealias EChar = Character

/// 8-bit signed integer type for Ecore models.
///
/// Maps to Swift's `Int8` type, equivalent to Java's `byte`.
public typealias EByte = Int8

/// 16-bit signed integer type for Ecore models.
///
/// Maps to Swift's `Int16` type, equivalent to Java's `short`.
public typealias EShort = Int16

/// 64-bit signed integer type for Ecore models.
///
/// Maps to Swift's `Int64` type, equivalent to Java's `long`.
public typealias ELong = Int64

/// Arbitrary-precision decimal type for Ecore models.
///
/// Maps to Swift's `Decimal` type for precise decimal arithmetic.
public typealias EBigDecimal = Decimal

/// Arbitrary-precision integer type for Ecore models.
///
/// Maps to Swift's `Int` type as Swift doesn't have a built-in BigInteger.
/// Consider using a third-party library for true arbitrary-precision integers if needed.
public typealias EBigInteger = Int

// MARK: - EcoreValue Conformances

extension EString: EcoreValue {}
extension EInt: EcoreValue {}
extension EBoolean: EcoreValue {}
extension EFloat: EcoreValue {}
extension EDouble: EcoreValue {}
extension EDate: EcoreValue {}
extension EChar: EcoreValue {}
extension EByte: EcoreValue {}
extension EShort: EcoreValue {}
extension ELong: EcoreValue {}
extension EBigDecimal: EcoreValue {}
extension EUUID: EcoreValue {}

/// Type conversion utilities for Ecore primitive types.
///
/// Provides bidirectional conversion between string representations and typed values,
/// supporting serialisation and deserialisation of Ecore models.
public enum EcoreTypeConverter: Sendable {
    /// Converts a string representation to a typed value.
    ///
    /// This method parses the string according to the target type's format requirements.
    /// If the string cannot be parsed into the requested type, `nil` is returned.
    ///
    /// - Parameters:
    ///   - value: The string representation to convert.
    ///   - type: The target type to convert to.
    /// - Returns: The parsed value of type `T`, or `nil` if parsing fails.
    public static func fromString<T>(_ value: String, as type: T.Type) -> T? {
        switch type {
        case is EString.Type:
            return value as? T
        case is EInt.Type:
            return Int(value) as? T
        case is EBoolean.Type:
            return Bool(value) as? T
        case is EFloat.Type:
            return Float(value) as? T
        case is EDouble.Type:
            return Double(value) as? T
        default:
            return nil
        }
    }

    /// Converts a typed value to its string representation.
    ///
    /// This method produces a string representation suitable for serialisation
    /// and can be parsed back using ``fromString(_:as:)``.
    ///
    /// - Parameter value: The value to convert to a string.
    /// - Returns: A string representation of the value.
    public static func toString<T>(_ value: T) -> String {
        return "\(value)"
    }
}
