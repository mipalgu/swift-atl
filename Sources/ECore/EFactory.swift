//
// EFactory.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation
import BigInt

// MARK: - EFactory

/// A factory for creating instances of model elements.
///
/// `EFactory` provides the factory pattern for creating instances of classes defined
/// in a metamodel package. Each factory is associated with a specific ``EPackage`` and
/// can create instances of the classes in that package.
///
/// ## Key Capabilities
///
/// - **Create Objects**: Instantiate objects of a given class using ``create(_:)``
/// - **Parse Data Types**: Convert string literals to typed values using ``createFromString(_:_:)``
/// - **Convert to Strings**: Convert typed values to string literals using ``convertToString(_:_:)``
///
/// ## Example
///
/// ```swift
/// let companyPackage = EPackage(
///     name: "company",
///     nsURI: "http://example.org/company",
///     nsPrefix: "company"
/// )
///
/// let factory = EFactory(ePackage: companyPackage)
///
/// // Create an Employee instance (in practice, would return a proper object)
/// if let employeeClass = companyPackage.getEClass("Employee") {
///     let employee = factory.create(employeeClass)
///     print("Created instance of \(employee.eClass.name)")
/// }
///
/// // Parse a string into an Int
/// let intType = EDataType(name: "EInt")
/// if let value = factory.createFromString(intType, "42") as? Int {
///     print("Parsed value: \(value)")
/// }
/// ```
///
/// ## Important Note
///
/// This basic implementation creates generic `EObject` instances. In a complete
/// implementation, factories would be code-generated or use dynamic proxies to
/// create specific typed instances with proper feature storage.
public struct EFactory: ENamedElement {
    /// The type of classifier for this factory.
    ///
    /// All instances of `EFactory` use ``EFactoryClassifier`` as their metaclass.
    public typealias Classifier = EFactoryClassifier

    /// Unique identifier for this factory.
    ///
    /// Used for identity-based equality and hashing.
    public let id: EUUID

    /// The metaclass describing this factory.
    public let eClass: Classifier

    /// The name of this factory.
    ///
    /// Typically derived from the package name (e.g., "CompanyFactory" for the "company" package).
    public var name: String

    /// Annotations attached to this factory.
    public var eAnnotations: [EAnnotation]

    /// The package that this factory creates instances for.
    ///
    /// The factory can create instances of any class defined in this package.
    public var ePackage: EPackage

    /// Internal storage for feature values.
    private var storage: EObjectStorage

    /// Creates a new factory.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (generates a new UUID if not provided).
    ///   - name: The name of the factory (defaults to package name + "Factory").
    ///   - ePackage: The package that this factory creates instances for.
    ///   - eAnnotations: Annotations (empty by default).
    public init(
        id: EUUID = EUUID(),
        name: String? = nil,
        ePackage: EPackage,
        eAnnotations: [EAnnotation] = []
    ) {
        self.id = id
        self.eClass = EFactoryClassifier()
        self.name = name ?? "\(ePackage.name.prefix(1).uppercased())\(ePackage.name.dropFirst())Factory"
        self.ePackage = ePackage
        self.eAnnotations = eAnnotations
        self.storage = EObjectStorage()
    }

    // MARK: - Object Creation

    /// Creates an instance of the specified class.
    ///
    /// This method creates a new object of the given class type. In this basic implementation,
    /// it returns a generic `DynamicEObject` that stores feature values dynamically.
    ///
    /// In a complete EMF implementation, this would:
    /// 1. Use code generation to create specific typed classes
    /// 2. Or use dynamic proxies to create objects with proper behaviour
    ///
    /// - Parameter eClass: The class to instantiate.
    /// - Returns: A new instance of the specified class.
    ///
    /// ## Example
    ///
    /// ```swift
    /// if let employeeClass = package.getEClass("Employee") {
    ///     let employee = factory.create(employeeClass)
    ///     // In a complete implementation, would be able to:
    ///     // employee.eSet(nameAttribute, "Alice")
    /// }
    /// ```
    public func create(_ eClass: EClass) -> DynamicEObject {
        return DynamicEObject(eClass: eClass)
    }

    /// Creates a value from a string literal for the given data type.
    ///
    /// Converts a string representation to a typed value. This is used during
    /// deserialisation (e.g., from XMI or JSON) to convert attribute values from
    /// strings to their proper Swift types.
    ///
    /// - Parameters:
    ///   - eDataType: The data type to create a value for.
    ///   - literal: The string literal to convert.
    /// - Returns: The converted value, or `nil` if conversion fails.
    ///
    /// ## Supported Conversions
    ///
    /// - `EString` → `String`
    /// - `EInt` → `Int`
    /// - `EBoolean` → `Bool`
    /// - `EFloat` → `Float`
    /// - `EDouble` → `Double`
    /// - Custom data types (uses instanceClassName for reflection)
    ///
    /// ## Example
    ///
    /// ```swift
    /// let intType = EDataType(name: "EInt")
    /// if let value = factory.createFromString(intType, "42") as? Int {
    ///     print("Parsed: \(value)")  // 42
    /// }
    /// ```
    public func createFromString(_ eDataType: EDataType, _ literal: String) -> (any EcoreValue)? {
        // Handle standard Ecore primitive types
        switch eDataType.name {
        case "EString":
            return literal as EString
        case "EInt", "EIntegerObject":
            return Int(literal) as EInt?
        case "EBoolean", "EBooleanObject":
            return Bool(literal) as EBoolean?
        case "EFloat", "EFloatObject":
            return Float(literal) as EFloat?
        case "EDouble", "EDoubleObject":
            return Double(literal) as EDouble?
        case "EByte":
            return Int8(literal) as EByte?
        case "EShort":
            return Int16(literal) as EShort?
        case "ELong":
            return Int64(literal) as ELong?
        case "EBigInteger":
            return BigInt(literal) as EBigInteger?
        case "EDate":
            // ISO 8601 date parsing
            let formatter = ISO8601DateFormatter()
            return formatter.date(from: literal) as EDate?
        default:
            // For custom data types, return the literal as-is
            // In a complete implementation, would use instanceClassName for conversion
            return literal as EString
        }
    }

    /// Converts a value to a string literal for the given data type.
    ///
    /// Converts a typed value to its string representation. This is used during
    /// serialisation (e.g., to XMI or JSON) to convert attribute values to strings.
    ///
    /// - Parameters:
    ///   - eDataType: The data type of the value.
    ///   - value: The value to convert.
    /// - Returns: The string representation of the value.
    ///
    /// ## Example
    ///
    /// ```swift
    /// let intType = EDataType(name: "EInt")
    /// let literal = factory.convertToString(intType, 42)
    /// print(literal)  // "42"
    /// ```
    public func convertToString(_ eDataType: EDataType, _ value: any EcoreValue) -> String {
        // Handle standard Ecore primitive types
        switch eDataType.name {
        case "EDate":
            if let date = value as? EDate {
                let formatter = ISO8601DateFormatter()
                return formatter.string(from: date)
            }
        default:
            break
        }

        // Default: use string description
        return String(describing: value)
    }

    // MARK: - EObject Protocol Implementation

    /// Reflectively retrieves the value of a feature.
    ///
    /// This method provides dynamic access to the factory's properties without
    /// requiring compile-time knowledge of the feature.
    ///
    /// - Parameter feature: The structural feature whose value to retrieve.
    /// - Returns: The feature's current value, or `nil` if not set.
    public func eGet(_ feature: some EStructuralFeature) -> (any EcoreValue)? {
        return storage.get(feature: feature.id)
    }

    /// Reflectively sets the value of a feature.
    ///
    /// This method provides dynamic modification of the factory's properties.
    /// Setting a value to `nil` has the same effect as calling ``eUnset(_:)``.
    ///
    /// - Parameters:
    ///   - feature: The structural feature to modify.
    ///   - value: The new value, or `nil` to unset.
    public mutating func eSet(_ feature: some EStructuralFeature, _ value: (any EcoreValue)?) {
        storage.set(feature: feature.id, value: value)
    }

    /// Checks whether a feature has been explicitly set.
    ///
    /// A feature is considered "set" if it has been assigned a value, even if that
    /// value equals the feature's default.
    ///
    /// - Parameter feature: The structural feature to check.
    /// - Returns: `true` if the feature has been set, `false` otherwise.
    public func eIsSet(_ feature: some EStructuralFeature) -> Bool {
        return storage.isSet(feature: feature.id)
    }

    /// Unsets a feature, returning it to its default value.
    ///
    /// After unsetting, ``eIsSet(_:)`` will return `false` for this feature,
    /// and ``eGet(_:)`` will return `nil`.
    ///
    /// - Parameter feature: The structural feature to unset.
    public mutating func eUnset(_ feature: some EStructuralFeature) {
        storage.unset(feature: feature.id)
    }

    // MARK: - Equatable & Hashable

    /// Compares two factories for equality.
    ///
    /// Factories are equal if they have the same identifier.
    ///
    /// - Parameters:
    ///   - lhs: The first factory to compare.
    ///   - rhs: The second factory to compare.
    /// - Returns: `true` if the factories are equal, `false` otherwise.
    public static func == (lhs: EFactory, rhs: EFactory) -> Bool {
        return lhs.id == rhs.id
    }

    /// Hashes the essential components of this factory.
    ///
    /// Only the identifier is used for hashing to maintain consistency with equality.
    ///
    /// - Parameter hasher: The hasher to use for combining components.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Classifier Type

/// Metaclass for `EFactory`.
///
/// Describes the structure of `EFactory` itself within the metamodel hierarchy.
public struct EFactoryClassifier: EClassifier {
    /// Unique identifier for this metaclass.
    public let id: EUUID = EUUID()

    /// The name of this classifier.
    ///
    /// Always returns `"EFactory"` to identify this as the metaclass for factories.
    public var name: String { "EFactory" }
}
