//
// DynamicEObject.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

// MARK: - DynamicEObject

/// A dynamic implementation of `EObject` that stores feature values generically.
///
/// This type provides a basic object implementation that can represent instances
/// of any ``EClass``. Feature values are stored in a dictionary and accessed reflectively.
///
/// ## Usage
///
/// In a complete EMF implementation, code generation would create specific typed classes
/// for each `EClass`. This dynamic implementation serves as a fallback and for testing.
///
/// ## Example
///
/// ```swift
/// let employeeClass = EClass(name: "Employee")
/// let nameAttr = EAttribute(name: "name", eType: stringType)
///
/// var employee = DynamicEObject(eClass: employeeClass)
/// employee.eSet(nameAttr, "Alice" as EString)
///
/// if let name = employee.eGet(nameAttr) as? EString {
///     print("Employee name: \(name)")
/// }
/// ```
///
/// ## JSON Serialization
///
/// `DynamicEObject` conforms to `Codable` and can be serialized to/from JSON.
/// The JSON format matches pyecore's format:
///
/// ```json
/// {
///   "eClass": "http://package.uri#//ClassName",
///   "attributeName": "value",
///   "referenceName": { ... }
/// }
/// ```
public struct DynamicEObject: EObject {
    /// The type of classifier for dynamic objects.
    public typealias Classifier = EClass

    /// Unique identifier for this object.
    public let id: EUUID

    /// The class (metaclass) of this object.
    public let eClass: EClass

    /// Internal storage for feature values.
    private var storage: EObjectStorage

    /// Creates a new dynamic object.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (generates a new UUID if not provided).
    ///   - eClass: The class that defines this object's structure.
    public init(id: EUUID = EUUID(), eClass: EClass) {
        self.id = id
        self.eClass = eClass
        self.storage = EObjectStorage()
    }

    // MARK: - EObject Protocol Implementation

    /// Reflectively retrieves the value of a feature.
    ///
    /// - Parameter feature: The structural feature whose value to retrieve.
    /// - Returns: The feature's current value, or `nil` if not set.
    public func eGet(_ feature: some EStructuralFeature) -> (any EcoreValue)? {
        return storage.get(feature: feature.id)
    }

    /// Reflectively sets the value of a feature.
    ///
    /// - Parameters:
    ///   - feature: The structural feature to modify.
    ///   - value: The new value, or `nil` to unset.
    public mutating func eSet(_ feature: some EStructuralFeature, _ value: (any EcoreValue)?) {
        storage.set(feature: feature.id, value: value)
    }

    /// Checks whether a feature has been explicitly set.
    ///
    /// - Parameter feature: The structural feature to check.
    /// - Returns: `true` if the feature has been set, `false` otherwise.
    public func eIsSet(_ feature: some EStructuralFeature) -> Bool {
        return storage.isSet(feature: feature.id)
    }

    /// Unsets a feature, returning it to its default value.
    ///
    /// - Parameter feature: The structural feature to unset.
    public mutating func eUnset(_ feature: some EStructuralFeature) {
        storage.unset(feature: feature.id)
    }

    // MARK: - Equatable & Hashable

    /// Compares two dynamic objects for equality.
    ///
    /// Objects are equal if they have the same identifier.
    ///
    /// - Parameters:
    ///   - lhs: The first object to compare.
    ///   - rhs: The second object to compare.
    /// - Returns: `true` if the objects are equal, `false` otherwise.
    public static func == (lhs: DynamicEObject, rhs: DynamicEObject) -> Bool {
        return lhs.id == rhs.id
    }

    /// Hashes the essential components of this object.
    ///
    /// Only the identifier is used for hashing to maintain consistency with equality.
    ///
    /// - Parameter hasher: The hasher to use for combining components.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Codable Conformance

extension DynamicEObject: Codable {
    /// Coding keys for JSON serialization.
    ///
    /// Maps between JSON keys and internal representation. Uses "eClass" for
    /// the metaclass name to match pyecore format.
    private enum CodingKeys: String, CodingKey {
        case eClass
        // Dynamic keys for features will be added during encoding/decoding
    }

    /// Encodes this object to JSON.
    ///
    /// Produces JSON in pyecore format with the eClass name and feature values.
    ///
    /// - Parameter encoder: The encoder to write data to.
    /// - Throws: Encoding errors if serialization fails.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)

        // Encode the eClass name
        try container.encode(eClass.name, forKey: DynamicCodingKey(stringValue: "eClass")!)

        // Encode all set attributes
        for attribute in eClass.allAttributes {
            guard eIsSet(attribute), let value = eGet(attribute) else { continue }

            let key = DynamicCodingKey(stringValue: attribute.name)!
            try encodeValue(value, for: attribute, to: &container, key: key)
        }

        // Encode all set references
        for reference in eClass.allReferences {
            guard eIsSet(reference), let value = eGet(reference) else { continue }

            let key = DynamicCodingKey(stringValue: reference.name)!
            try encodeReference(value, for: reference, to: &container, key: key)
        }
    }

    /// Decodes this object from JSON.
    ///
    /// Reads JSON in pyecore format and populates feature values using the reflective API.
    ///
    /// ## Usage
    ///
    /// The EClass must be provided through the decoder's userInfo dictionary:
    ///
    /// ```swift
    /// let decoder = JSONDecoder()
    /// decoder.userInfo[.eClassKey] = employeeClass
    /// let employee = try decoder.decode(DynamicEObject.self, from: jsonData)
    /// ```
    ///
    /// - Parameter decoder: The decoder to read data from.
    /// - Throws: Decoding errors if deserialization fails or if EClass is not provided in userInfo.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)

        // Decode the eClass name (for validation)
        let eClassName = try container.decode(String.self, forKey: DynamicCodingKey(stringValue: "eClass")!)

        // Get EClass from userInfo
        guard let eClass = decoder.userInfo[.eClassKey] as? EClass else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "EClass must be provided in decoder.userInfo[.eClassKey]"
                )
            )
        }

        // Validate eClass name matches
        guard eClass.name == eClassName else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "EClass name mismatch: expected \(eClass.name), got \(eClassName)"
                )
            )
        }

        // Initialize object
        self.id = EUUID()
        self.eClass = eClass
        self.storage = EObjectStorage()

        // Decode all attributes
        for attribute in eClass.allAttributes {
            let key = DynamicCodingKey(stringValue: attribute.name)!
            if let value = try? decodeValue(for: attribute, from: container, key: key) {
                storage.set(feature: attribute.id, value: value)
            }
        }

        // Decode all references
        for reference in eClass.allReferences {
            let key = DynamicCodingKey(stringValue: reference.name)!
            if let value = try? decodeReference(for: reference, from: container, key: key, decoder: decoder) {
                storage.set(feature: reference.id, value: value)
            }
        }
    }

    /// Helper to decode an attribute value.
    private func decodeValue(
        for attribute: EAttribute,
        from container: KeyedDecodingContainer<DynamicCodingKey>,
        key: DynamicCodingKey
    ) throws -> (any EcoreValue)? {
        // Determine the expected type from the attribute's eType
        let typeName = attribute.eType.name

        switch typeName {
        case "EString":
            return try container.decode(String.self, forKey: key) as EString
        case "EInt", "EIntegerObject":
            return try container.decode(Int.self, forKey: key) as EInt
        case "EBoolean", "EBooleanObject":
            return try container.decode(Bool.self, forKey: key) as EBoolean
        case "EDouble", "EDoubleObject":
            return try container.decode(Double.self, forKey: key) as EDouble
        case "EFloat", "EFloatObject":
            return try container.decode(Float.self, forKey: key) as EFloat
        default:
            // For custom types, try string
            return try container.decode(String.self, forKey: key) as EString
        }
    }

    /// Helper to decode a reference value.
    private func decodeReference(
        for reference: EReference,
        from container: KeyedDecodingContainer<DynamicCodingKey>,
        key: DynamicCodingKey,
        decoder: Decoder
    ) throws -> (any EcoreValue)? {
        if reference.isMany {
            // Multi-valued reference - would be an array
            // For now, simplified - will implement with Resource/ResourceSet
            return nil
        } else {
            // Try to decode as nested object
            if let nestedObject = try? container.decode(DynamicEObject.self, forKey: key) {
                return nestedObject
            }
            // Try to decode as ID reference
            if let idString = try? container.decode(String.self, forKey: key),
               let uuid = EUUID(uuidString: idString) {
                return uuid
            }
            return nil
        }
    }

    /// Helper to encode an attribute value.
    private func encodeValue(
        _ value: any EcoreValue,
        for attribute: EAttribute,
        to container: inout KeyedEncodingContainer<DynamicCodingKey>,
        key: DynamicCodingKey
    ) throws {
        // Handle different value types
        switch value {
        case let string as String:
            try container.encode(string, forKey: key)
        case let int as Int:
            try container.encode(int, forKey: key)
        case let bool as Bool:
            try container.encode(bool, forKey: key)
        case let double as Double:
            try container.encode(double, forKey: key)
        case let float as Float:
            try container.encode(float, forKey: key)
        default:
            // For other types, use string representation
            try container.encode(String(describing: value), forKey: key)
        }
    }

    /// Helper to encode a reference value.
    private func encodeReference(
        _ value: any EcoreValue,
        for reference: EReference,
        to container: inout KeyedEncodingContainer<DynamicCodingKey>,
        key: DynamicCodingKey
    ) throws {
        if let object = value as? DynamicEObject {
            // Encode nested object
            if reference.isMany {
                // Multi-valued reference - would be an array
                // For now, simplified
                try container.encode(object, forKey: key)
            } else {
                try container.encode(object, forKey: key)
            }
        } else if let id = value as? EUUID {
            // ID reference - encode as string
            try container.encode(id.uuidString, forKey: key)
        }
    }
}

// MARK: - Dynamic Coding Key

/// A dynamic coding key for encoding/decoding arbitrary feature names.
///
/// This allows encoding and decoding of features by their string names
/// without requiring compile-time knowledge of all possible keys.
private struct DynamicCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }
}

// MARK: - CodingUserInfoKey Extension

extension CodingUserInfoKey {
    /// Key for providing EClass context during JSON decoding.
    ///
    /// Use this key to pass the EClass to the decoder's userInfo:
    ///
    /// ```swift
    /// let decoder = JSONDecoder()
    /// decoder.userInfo[.eClassKey] = employeeClass
    /// let employee = try decoder.decode(DynamicEObject.self, from: jsonData)
    /// ```
    public static let eClassKey = CodingUserInfoKey(rawValue: "eClass")!
}
