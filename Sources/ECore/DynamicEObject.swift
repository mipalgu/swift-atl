//
// DynamicEObject.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

// MARK: - EMF URI Utilities

/// Utilities for working with EMF-compliant URIs
private enum EMFURIUtils {
    /// Generates an EMF URI for a classifier within a package.
    ///
    /// Creates URIs following the EMF standard format: "nsURI#//ClassName".
    /// If the package has no namespace URI, falls back to using just the classifier name.
    ///
    /// - Parameters:
    ///   - classifier: The classifier to generate a URI for.
    ///   - package: The package containing the classifier (optional).
    /// - Returns: An EMF-compliant URI string for the classifier.
    static func generateURI(for classifier: any EClassifier, in package: EPackage?) -> String {
        guard let package = package, !package.nsURI.isEmpty else {
            return classifier.name // Fall back to simple name
        }
        return "\(package.nsURI)#//\(classifier.name)"
    }

    /// Extracts the class name from an EMF URI or returns the original string if it's a simple name.
    ///
    /// Parses EMF URIs to extract just the classifier name portion. If the input
    /// doesn't follow EMF URI format, returns the input unchanged.
    ///
    /// ## Examples
    /// - `"http://mytest/1.0#//Person"` → `"Person"`
    /// - `"Person"` → `"Person"`
    ///
    /// - Parameter uri: The URI string to parse (may be a simple name or full EMF URI).
    /// - Returns: The extracted class name from the URI fragment, or the original string.
    static func extractClassName(from uri: String) -> String {
        if let fragmentRange = uri.range(of: "#//") {
            return String(uri[fragmentRange.upperBound...])
        }
        return uri
    }

    /// Checks if a string is an EMF URI by looking for the standard fragment separator.
    ///
    /// EMF URIs contain the fragment separator "#//" which distinguishes them from
    /// simple class names or other URI formats.
    ///
    /// - Parameter string: The string to test for EMF URI format.
    /// - Returns: `true` if the string contains the EMF fragment separator "#//", `false` otherwise.
    static func isEMFURI(_ string: String) -> Bool {
        return URL(string: string) != nil && string.contains("#//")
    }
}

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
/// employee.eSet(nameAttr, "Alice")
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

    // MARK: - String-based Convenience Methods

    /// Reflectively retrieves the value of a feature by name.
    ///
    /// - Parameter featureName: The name of the structural feature to retrieve.
    /// - Returns: The feature's current value, or `nil` if not set or not found.
    public func eGet(_ featureName: String) -> (any EcoreValue)? {
        if let feature = eClass.getStructuralFeature(name: featureName) {
            // Use the proper feature if it exists in the eClass
            return eGet(feature)
        } else {
            // For dynamic objects without full metamodel, retrieve by name
            return storage.get(name: featureName)
        }
    }

    /// Reflectively sets the value of a feature by name.
    ///
    /// - Parameters:
    ///   - featureName: The name of the structural feature to modify.
    ///   - value: The new value, or `nil` to unset.
    public mutating func eSet(_ featureName: String, value: (any EcoreValue)?) {
        if let feature = eClass.getStructuralFeature(name: featureName) {
            // Use the proper feature if it exists in the eClass
            eSet(feature, value)
        } else {
            // For dynamic objects without full metamodel, store by name
            // This allows XMI parsing to work even when eClass doesn't have all features defined
            storage.set(name: featureName, value: value)
        }
    }

    /// Checks whether a feature has been explicitly set by name.
    ///
    /// - Parameter featureName: The name of the structural feature to check.
    /// - Returns: `true` if the feature has been set, `false` otherwise.
    public func eIsSet(_ featureName: String) -> Bool {
        guard let feature = eClass.getStructuralFeature(name: featureName) else {
            return false
        }
        return eIsSet(feature)
    }

    /// Unsets a feature by name, returning it to its default value.
    ///
    /// - Parameter featureName: The name of the structural feature to unset.
    public mutating func eUnset(_ featureName: String) {
        guard let feature = eClass.getStructuralFeature(name: featureName) else {
            return
        }
        eUnset(feature)
    }

    /// Get all feature names that have been set on this object.
    ///
    /// Returns names for both metamodel-defined features (stored by ID) and
    /// dynamic features (stored by name). This ensures cross-format serialization
    /// works correctly - features stored in ID-based storage after JSON parsing
    /// will be included when serializing to XMI.
    ///
    /// - Returns: Array of feature names
    public func getFeatureNames() -> [String] {
        var featureNames = Set<String>()

        // Add names from metamodel-defined features that have been set (ID-based storage)
        for attribute in eClass.allAttributes {
            if storage.isSet(feature: attribute.id) {
                featureNames.insert(attribute.name)
            }
        }

        for reference in eClass.allReferences {
            if storage.isSet(feature: reference.id) {
                featureNames.insert(reference.name)
            }
        }

        // Add names from dynamic features (name-based storage)
        featureNames.formUnion(storage.getFeatureNames())

        return Array(featureNames)
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
    /// Produces JSON in EMF-compliant format with the eClass URI and feature values.
    /// Uses EMF URI format when package context is available, otherwise falls back to simple name.
    ///
    /// - Parameter encoder: The encoder to write data to.
    /// - Throws: Encoding errors if serialization fails.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)

        // Get package context from userInfo if available
        let package = encoder.userInfo[.ePackageKey] as? EPackage

        // Encode the eClass as EMF URI or simple name
        let eClassIdentifier = EMFURIUtils.generateURI(for: eClass, in: package)
        try container.encode(eClassIdentifier, forKey: DynamicCodingKey(stringValue: "eClass")!)

        // Track which features we've encoded from the metamodel
        var encodedFeatures = Set<String>()

        // Encode all set attributes from metamodel
        for attribute in eClass.allAttributes {
            guard eIsSet(attribute), let value = eGet(attribute) else { continue }

            let key = DynamicCodingKey(stringValue: attribute.name)!
            try encodeValue(value, for: attribute, to: &container, key: key)
            encodedFeatures.insert(attribute.name)
        }

        // Encode all set references from metamodel
        for reference in eClass.allReferences {
            guard eIsSet(reference), let value = eGet(reference) else { continue }

            let key = DynamicCodingKey(stringValue: reference.name)!
            try encodeReference(value, for: reference, to: &container, key: key)
            encodedFeatures.insert(reference.name)
        }

        // Encode all dynamically set features that aren't in the metamodel
        // This is crucial for XMI → JSON conversion where the EClass may not have all features defined
        for featureName in storage.getFeatureNames() {
            // Skip if already encoded from metamodel
            guard !encodedFeatures.contains(featureName) else { continue }
            guard let value = storage.get(name: featureName) else { continue }

            let key = DynamicCodingKey(stringValue: featureName)!

            // Encode the value directly without type checking
            // (we don't have feature metadata for dynamic features)
            try encodeDynamicValue(value, to: &container, key: key)
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

        // Decode the eClass identifier (can be EMF URI or simple name)
        let eClassIdentifier = try container.decode(String.self, forKey: DynamicCodingKey(stringValue: "eClass")!)

        // Get EClass from userInfo
        guard let eClass = decoder.userInfo[.eClassKey] as? EClass else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "EClass must be provided in decoder.userInfo[.eClassKey]"
                )
            )
        }

        // Extract class name from EMF URI if needed and validate
        let extractedClassName = EMFURIUtils.extractClassName(from: eClassIdentifier)
        guard eClass.name == extractedClassName else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "EClass name mismatch: expected \(eClass.name), got \(extractedClassName) (from \(eClassIdentifier))"
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
            // Only skip if the key is not present, but throw errors for type mismatches
            if container.contains(key) {
                let value = try decodeValue(for: attribute, from: container, key: key, decoder: decoder)
                if let value = value {
                    storage.set(feature: attribute.id, value: value)
                }
            }
        }

        // Decode all references
        for reference in eClass.allReferences {
            let key = DynamicCodingKey(stringValue: reference.name)!
            if let value = try? decodeReference(for: reference, from: container, key: key, decoder: decoder) {
                storage.set(feature: reference.id, value: value)
            }
        }

        // Decode dynamic features not defined in eClass
        // This makes init(from:) symmetric with encode(to:) for cross-format conversion
        // Without this, fields in JSON that aren't in the metamodel are silently lost

        // Get all keys from JSON
        let allKeys = Set(container.allKeys.map { $0.stringValue })

        // Get keys already processed from eClass
        var processedKeys = Set(eClass.allAttributes.map { $0.name })
        processedKeys.formUnion(eClass.allReferences.map { $0.name })
        processedKeys.insert("eClass")

        // Process remaining dynamic keys not defined in the metamodel
        for keyString in allKeys.subtracting(processedKeys) {
            let key = DynamicCodingKey(stringValue: keyString)!
            if let value = try? decodeGenericValue(from: container, forKey: key) {
                storage.set(name: keyString, value: value)
            }
        }
    }

    /// Helper to decode an attribute value from JSON with type coercion.
    ///
    /// Decodes an attribute value from the JSON container, performing reasonable
    /// type coercion when possible (e.g., converting numbers to strings for EString attributes).
    /// Supports all standard Ecore data types with fallback to string representation.
    ///
    /// - Parameters:
    ///   - attribute: The attribute metadata defining the expected type and constraints.
    ///   - container: The keyed decoding container containing the JSON data.
    ///   - key: The dynamic coding key identifying the attribute in the JSON.
    ///   - decoder: The decoder instance for error reporting and context.
    /// - Returns: The decoded value as an `EcoreValue`, or `nil` if the key is not present.
    /// - Throws: `DecodingError` if the value cannot be converted to the expected type.
    private func decodeValue(
        for attribute: EAttribute,
        from container: KeyedDecodingContainer<DynamicCodingKey>,
        key: DynamicCodingKey,
        decoder: Decoder
    ) throws -> (any EcoreValue)? {
        // Determine the expected type from the attribute's eType
        let typeName = attribute.eType.name

        switch typeName {
        case "EString":
            // Try to decode as string, but allow reasonable coercion
            if let stringValue = try? container.decode(EString.self, forKey: key) {
                return stringValue
            } else if let intValue = try? container.decode(EInt.self, forKey: key) {
                return String(intValue)
            } else if let doubleValue = try? container.decode(EDouble.self, forKey: key) {
                return String(doubleValue)
            } else if let boolValue = try? container.decode(EBoolean.self, forKey: key) {
                return String(boolValue)
            } else {
                throw DecodingError.typeMismatch(EString.self, DecodingError.Context(
                    codingPath: decoder.codingPath + [key],
                    debugDescription: "Cannot convert value to EString"
                ))
            }
        case "EInt", "EIntegerObject":
            // Try to decode as int, reject invalid strings
            if let intValue = try? container.decode(EInt.self, forKey: key) {
                return intValue
            } else if let stringValue = try? container.decode(EString.self, forKey: key),
                      let convertedInt = EInt(stringValue) {
                return convertedInt
            } else {
                throw DecodingError.typeMismatch(EInt.self, DecodingError.Context(
                    codingPath: decoder.codingPath + [key],
                    debugDescription: "Cannot convert value to EInt"
                ))
            }
        case "EBoolean", "EBooleanObject":
            // Try to decode as boolean, reject invalid strings
            if let boolValue = try? container.decode(EBoolean.self, forKey: key) {
                return boolValue
            } else if let stringValue = try? container.decode(EString.self, forKey: key) {
                let lowercased = stringValue.lowercased()
                if lowercased == "true" {
                    return true
                } else if lowercased == "false" {
                    return false
                } else {
                    throw DecodingError.typeMismatch(EBoolean.self, DecodingError.Context(
                        codingPath: decoder.codingPath + [key],
                        debugDescription: "Cannot convert '\(stringValue)' to EBoolean"
                    ))
                }
            } else {
                throw DecodingError.typeMismatch(EBoolean.self, DecodingError.Context(
                    codingPath: decoder.codingPath + [key],
                    debugDescription: "Cannot convert value to EBoolean"
                ))
            }
        case "EDouble", "EDoubleObject":
            if let doubleValue = try? container.decode(EDouble.self, forKey: key) {
                return doubleValue
            } else if let stringValue = try? container.decode(EString.self, forKey: key),
                      let convertedDouble = EDouble(stringValue) {
                return convertedDouble
            } else {
                throw DecodingError.typeMismatch(EDouble.self, DecodingError.Context(
                    codingPath: decoder.codingPath + [key],
                    debugDescription: "Cannot convert value to EDouble"
                ))
            }
        case "EFloat", "EFloatObject":
            if let floatValue = try? container.decode(EFloat.self, forKey: key) {
                return floatValue
            } else if let stringValue = try? container.decode(EString.self, forKey: key),
                      let convertedFloat = EFloat(stringValue) {
                return convertedFloat
            } else {
                throw DecodingError.typeMismatch(EFloat.self, DecodingError.Context(
                    codingPath: decoder.codingPath + [key],
                    debugDescription: "Cannot convert value to EFloat"
                ))
            }
        case "EDate":
            // Be forgiving with date formats - try multiple approaches
            if let dateValue = try? container.decode(EDate.self, forKey: key) {
                return dateValue
            } else if let stringValue = try? container.decode(EString.self, forKey: key) {
                return try parseDate(from: stringValue)
            } else {
                throw DecodingError.typeMismatch(EDate.self, DecodingError.Context(
                    codingPath: decoder.codingPath + [key],
                    debugDescription: "Cannot convert value to EDate"
                ))
            }
        default:
            // For unsupported types, throw an error for type safety
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath + [key],
                    debugDescription: "Unsupported attribute type: \(typeName)"
                )
            )
        }
    }

    /// Helper to parse date from string using multiple EMF-compatible formats.
    ///
    /// Attempts to parse date strings using various formats commonly used in EMF:
    /// - ISO 8601 format (preferred)
    /// - PyEcore format with microseconds
    /// - Standard date-time format without microseconds
    /// - Simple date format (yyyy-MM-dd)
    ///
    /// - Parameter dateString: The string representation of the date to parse.
    /// - Returns: The parsed date as an `EDate`.
    /// - Throws: `DecodingError` if the string cannot be parsed using any supported format.
    private func parseDate(from dateString: String) throws -> EDate {
        // Try ISO8601 first
        let iso8601Formatter = ISO8601DateFormatter()
        if let date = iso8601Formatter.date(from: dateString) {
            return date
        }

        // Try pyecore format: %Y-%m-%dT%H:%M:%S.%f%z
        let pyecoreFormatter = DateFormatter()
        pyecoreFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
        pyecoreFormatter.timeZone = TimeZone(secondsFromGMT: 0)
        if let date = pyecoreFormatter.date(from: dateString) {
            return date
        }

        // Try without microseconds: %Y-%m-%dT%H:%M:%S%z
        pyecoreFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        if let date = pyecoreFormatter.date(from: dateString) {
            return date
        }

        // Try basic ISO format without timezone
        pyecoreFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        if let date = pyecoreFormatter.date(from: dateString) {
            return date
        }

        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: [],
                debugDescription: "Invalid date format: \(dateString)"
            )
        )
    }

    /// Helper to decode a reference value from JSON.
    ///
    /// Decodes references as URI strings that can be resolved to actual objects.
    /// Multi-valued references are represented as arrays of URI strings.
    /// Currently simplified for basic URI-based cross-references.
    ///
    /// - Parameters:
    ///   - reference: The reference metadata defining multiplicity and target type.
    ///   - container: The keyed decoding container containing the JSON data.
    ///   - key: The dynamic coding key identifying the reference in the JSON.
    ///   - decoder: The decoder instance for error reporting and context.
    /// - Returns: The decoded reference value(s), or `nil` if not implemented or not present.
    /// - Throws: `DecodingError` if the reference structure is invalid.
    private func decodeReference(
        for reference: EReference,
        from container: KeyedDecodingContainer<DynamicCodingKey>,
        key: DynamicCodingKey,
        decoder: Decoder
    ) throws -> (any EcoreValue)? {
        if reference.isMany {
            // Multi-valued reference - let decodeGenericValue handle arrays
            return try? decodeGenericValue(from: container, forKey: key)
        } else {
            // Single-valued reference
            if reference.containment {
                // Try to decode as nested object
                if let nestedObject = try? container.decode(DynamicEObject.self, forKey: key) {
                    return nestedObject
                }
            }
            // Try to decode as ID reference
            if let idString = try? container.decode(String.self, forKey: key),
               let uuid = EUUID(uuidString: idString) {
                return uuid
            }
            return nil
        }
    }

    /// Create a dynamic EClass from an eClass URI string and JSON dictionary
    static func createDynamicEClass(from eClassURI: String, jsonDict: [String: Any]) -> EClass {
        // Extract class name from URI (e.g., "http://package#//ClassName" -> "ClassName")
        let className: String
        if let hashIndex = eClassURI.lastIndex(of: "#") {
            let fragment = String(eClassURI[eClassURI.index(after: hashIndex)...])
            className = fragment.replacingOccurrences(of: "//", with: "")
        } else if let slashIndex = eClassURI.lastIndex(of: "/") {
            className = String(eClassURI[eClassURI.index(after: slashIndex)...])
        } else {
            className = eClassURI
        }

        // Infer attributes from JSON keys (excluding eClass)
        var features: [any EStructuralFeature] = []
        for (key, value) in jsonDict {
            if key == "eClass" { continue }

            // Infer type from value
            if value as? Bool != nil {
                let attribute = EAttribute(name: key, eType: EDataType(name: "EBoolean"))
                features.append(attribute)
            } else if value is String {
                let attribute = EAttribute(name: key, eType: EDataType(name: "EString"))
                features.append(attribute)
            } else if value is Int {
                let attribute = EAttribute(name: key, eType: EDataType(name: "EInt"))
                features.append(attribute)
            } else if value is Double || value is Float {
                let attribute = EAttribute(name: key, eType: EDataType(name: "EDouble"))
                features.append(attribute)
            } else if value is [Any] {
                // Array - containment reference
                let targetType = EClass(name: "EObject") // Default target type
                let reference = EReference(name: key, eType: targetType, upperBound: -1, containment: true)
                features.append(reference)
            } else if value is [String: Any] {
                // Nested object - containment reference
                let targetType = EClass(name: "EObject") // Default target type
                let reference = EReference(name: key, eType: targetType, containment: true)
                features.append(reference)
            } else {
                let attribute = EAttribute(name: key, eType: EDataType(name: "EString"))
                features.append(attribute)
            }
        }

        return EClass(name: className, eStructuralFeatures: features)
    }

    /// Helper to encode a dynamically stored value to JSON (without metamodel information).
    ///
    /// This method handles encoding values that don't have associated EStructuralFeature metadata.
    /// It performs type inference to encode values appropriately for JSON.
    ///
    /// - Parameters:
    ///   - value: The value to encode.
    ///   - container: The keyed encoding container to write the value to.
    ///   - key: The coding key for this feature.
    /// - Throws: Encoding errors if serialisation fails.
    private func encodeDynamicValue(
        _ value: any EcoreValue,
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
        case let date as Date:
            // Format date to match pyecore
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            let dateString = formatter.string(from: date)
            try container.encode(dateString, forKey: key)
        case let object as DynamicEObject:
            // Nested object
            try container.encode(object, forKey: key)
        case let id as EUUID:
            // ID reference
            try container.encode(id.uuidString, forKey: key)
        case let array as [any EcoreValue]:
            // Array of values - try to encode as JSON array
            if let stringArray = array as? [String] {
                try container.encode(stringArray, forKey: key)
            } else if let intArray = array as? [Int] {
                try container.encode(intArray, forKey: key)
            } else if let objectArray = array as? [DynamicEObject] {
                try container.encode(objectArray, forKey: key)
            } else {
                // Fallback: encode as array of strings
                let stringArray = array.map { String(describing: $0) }
                try container.encode(stringArray, forKey: key)
            }
        default:
            // For other types, use string representation
            try container.encode(String(describing: value), forKey: key)
        }
    }

    /// Encodes attribute values using appropriate JSON representations for each
    /// Ecore data type. Handles special cases like dates (ISO 8601 format) and
    /// maintains type fidelity where possible.
    ///
    /// - Parameters:
    ///   - value: The attribute value to encode.
    ///   - attribute: The attribute metadata for type information.
    ///   - container: The keyed encoding container to write the value to.
    ///   - key: The dynamic coding key identifying the attribute in the JSON.
    /// - Throws: `EncodingError` if the value cannot be encoded to the expected format.
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
        case let date as Date:
            // Format date to match pyecore: %Y-%m-%dT%H:%M:%S.%f%z
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSSSSXXXXX"
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            let dateString = formatter.string(from: date)
            try container.encode(dateString, forKey: key)
        default:
            // For other types, use string representation
            try container.encode(String(describing: value), forKey: key)
        }
    }

    /// Helper to encode a reference value to JSON.
    ///
    /// Encodes references as URI strings for cross-reference resolution.
    /// Multi-valued references are encoded as JSON arrays of URI strings.
    /// Currently simplified for basic URI-based serialisation.
    ///
    /// - Parameters:
    ///   - value: The reference value(s) to encode.
    ///   - reference: The reference metadata for multiplicity information.
    ///   - container: The keyed encoding container to write the value to.
    ///   - key: The dynamic coding key identifying the reference in the JSON.
    /// - Throws: `EncodingError` if the reference structure cannot be serialised.
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

    /// Helper to decode a value without metamodel type information.
    ///
    /// Tries to decode as common types in order until one succeeds.
    /// Used for dynamic attributes not defined in the metamodel during cross-format conversion.
    ///
    /// This method enables symmetric encoding/decoding: just as `encode(to:)` encodes dynamic
    /// features not in the metamodel, this method decodes JSON fields that aren't defined
    /// in `eClass.allAttributes` or `eClass.allReferences`.
    ///
    /// - Parameters:
    ///   - container: The keyed decoding container containing the JSON data.
    ///   - key: The coding key for the field to decode.
    /// - Returns: The decoded value as an `EcoreValue`, or `nil` if all type attempts fail.
    private func decodeGenericValue(
        from container: KeyedDecodingContainer<DynamicCodingKey>,
        forKey key: DynamicCodingKey
    ) throws -> (any EcoreValue)? {
        // Try primitive types in order of specificity
        // Bool first because JSON true/false could also parse as string
        if let value = try? container.decode(Bool.self, forKey: key) { return value }

        // Integers before doubles to preserve precision
        if let value = try? container.decode(Int.self, forKey: key) { return value }
        if let value = try? container.decode(Double.self, forKey: key) { return value }

        // String is very common and flexible
        if let value = try? container.decode(String.self, forKey: key) { return value }

        // Try collections
        if let value = try? container.decode([String].self, forKey: key) { return value }
        if let value = try? container.decode([Int].self, forKey: key) { return value }
        if let value = try? container.decode([Bool].self, forKey: key) { return value }
        if let value = try? container.decode([Double].self, forKey: key) { return value }

        // Try nested objects (last as they're most complex)
        if let value = try? container.decode(DynamicEObject.self, forKey: key) { return value }
        if let value = try? container.decode([DynamicEObject].self, forKey: key) { return value }

        // All type attempts failed
        return nil
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

    /// Key for providing EPackage context during JSON encoding.
    ///
    /// Use this key to pass the EPackage to the encoder's userInfo for EMF-compliant URIs:
    ///
    /// ```swift
    /// let encoder = JSONEncoder()
    /// encoder.userInfo[.ePackageKey] = myPackage
    /// let jsonData = try encoder.encode(dynamicObject)
    /// ```
    public static let ePackageKey = CodingUserInfoKey(rawValue: "ePackage")!
}
