//
// Ecoretypes.swift
// SwiftEcore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

// EMF Primitive Type Mappings
public typealias EString = String
public typealias EInt = Int
public typealias EBoolean = Bool
public typealias EFloat = Float
public typealias EDouble = Double
public typealias EDate = Date
public typealias EChar = Character
public typealias EByte = Int8
public typealias EShort = Int16
public typealias ELong = Int64
public typealias EBigDecimal = Decimal
public typealias EBigInteger = Int  // Note: Swift doesn't have BigInteger built-in

/// Type conversion utilities for Ecore primitive types
public enum EcoreTypeConverter: Sendable {
    /// Convert a string to a typed value
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

    /// Convert a typed value to a string
    public static func toString<T>(_ value: T) -> String {
        return "\(value)"
    }
}
