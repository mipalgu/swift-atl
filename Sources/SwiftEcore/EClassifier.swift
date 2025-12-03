//
// EClassifier.swift
// SwiftEcore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

// MARK: - EDataType

/// A data type in the Ecore metamodel.
///
/// `EDataType` represents primitive and serialisable types in the metamodel, including:
/// - Primitive types (EString, EInt, EBoolean, etc.)
/// - Custom serialisable types with string representation
/// - Value objects that can be converted to/from strings
///
/// Data types differ from classes in that they have value semantics and can be
/// serialised as attribute values rather than requiring object identity.
///
/// ## Example
///
/// ```swift
/// let stringType = EDataType(
///     id: EUUID(),
///     name: "EString",
///     instanceClassName: "Swift.String",
///     serialisable: true
/// )
/// ```
public struct EDataType: ENamedElement {
    /// The type of classifier for this data type.
    public typealias Classifier = EDataTypeClassifier

    /// Unique identifier for this data type.
    public let id: EUUID

    /// The metaclass describing this data type.
    public let eClass: Classifier

    /// The name of this data type.
    ///
    /// Should be unique within the containing package. Examples: "EString", "EInt", "URI".
    public var name: String

    /// Annotations attached to this data type.
    ///
    /// Can be used for generation hints, documentation, or validation constraints.
    public var eAnnotations: [EAnnotation]

    /// Whether this data type can be serialised to/from strings.
    ///
    /// Serialisable data types can be converted to string literals in XMI/JSON.
    /// Non-serialisable types require custom serialisation logic.
    public var serialisable: Bool

    /// The fully qualified name of the instance class (optional).
    ///
    /// For Swift, this might be "Swift.String", "Foundation.Date", etc.
    /// Used for code generation and reflection.
    public var instanceClassName: String?

    /// The default value for this data type as a string literal (optional).
    ///
    /// Used when attributes of this type are not explicitly set.
    public var defaultValueLiteral: String?

    /// Internal storage for feature values.
    private var storage: EObjectStorage

    /// Creates a new data type.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (generates a new UUID if not provided).
    ///   - name: The name of the data type.
    ///   - serialisable: Whether the type can be serialised (default: true).
    ///   - instanceClassName: Optional fully qualified class name.
    ///   - defaultValueLiteral: Optional default value as string.
    ///   - eAnnotations: Annotations (empty by default).
    public init(
        id: EUUID = EUUID(),
        name: String,
        serialisable: Bool = true,
        instanceClassName: String? = nil,
        defaultValueLiteral: String? = nil,
        eAnnotations: [EAnnotation] = []
    ) {
        self.id = id
        self.eClass = EDataTypeClassifier()
        self.name = name
        self.serialisable = serialisable
        self.instanceClassName = instanceClassName
        self.defaultValueLiteral = defaultValueLiteral
        self.eAnnotations = eAnnotations
        self.storage = EObjectStorage()
    }

    public func eGet(_ feature: some EStructuralFeature) -> (any EcoreValue)? {
        return storage.get(feature: feature.id)
    }

    public mutating func eSet(_ feature: some EStructuralFeature, _ value: (any EcoreValue)?) {
        storage.set(feature: feature.id, value: value)
    }

    public func eIsSet(_ feature: some EStructuralFeature) -> Bool {
        return storage.isSet(feature: feature.id)
    }

    public mutating func eUnset(_ feature: some EStructuralFeature) {
        storage.unset(feature: feature.id)
    }

    public static func == (lhs: EDataType, rhs: EDataType) -> Bool {
        return lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - EEnumLiteral

/// A literal value within an enumeration.
///
/// `EEnumLiteral` represents a single named value in an `EEnum`, similar to
/// enum cases in Swift or constants in Java enums.
///
/// ## Example
///
/// ```swift
/// let blackbird = EEnumLiteral(
///     name: "blackbird",
///     value: 0,
///     literal: "BLACKBIRD"
/// )
/// ```
public struct EEnumLiteral: ENamedElement {
    /// The type of classifier for this enum literal.
    public typealias Classifier = EEnumLiteralClassifier

    /// Unique identifier for this literal.
    public let id: EUUID

    /// The metaclass describing this enum literal.
    public let eClass: Classifier

    /// The name of this literal.
    ///
    /// Used as the identifier in generated code. Example: "blackbird".
    public var name: String

    /// Annotations attached to this literal.
    public var eAnnotations: [EAnnotation]

    /// The integer value of this literal.
    ///
    /// Used for ordinal comparisons and serialisation. Typically starts at 0.
    public var value: Int

    /// The string literal representation (optional).
    ///
    /// If not provided, defaults to the name. Example: "BLACKBIRD" vs "blackbird".
    public var literal: String?

    /// Internal storage for feature values.
    private var storage: EObjectStorage

    /// Creates a new enum literal.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (generates a new UUID if not provided).
    ///   - name: The name of the literal.
    ///   - value: The integer value (typically ordinal position).
    ///   - literal: Optional string representation (defaults to name if not provided).
    ///   - eAnnotations: Annotations (empty by default).
    public init(
        id: EUUID = EUUID(),
        name: String,
        value: Int,
        literal: String? = nil,
        eAnnotations: [EAnnotation] = []
    ) {
        self.id = id
        self.eClass = EEnumLiteralClassifier()
        self.name = name
        self.value = value
        self.literal = literal
        self.eAnnotations = eAnnotations
        self.storage = EObjectStorage()
    }

    public func eGet(_ feature: some EStructuralFeature) -> (any EcoreValue)? {
        return storage.get(feature: feature.id)
    }

    public mutating func eSet(_ feature: some EStructuralFeature, _ value: (any EcoreValue)?) {
        storage.set(feature: feature.id, value: value)
    }

    public func eIsSet(_ feature: some EStructuralFeature) -> Bool {
        return storage.isSet(feature: feature.id)
    }

    public mutating func eUnset(_ feature: some EStructuralFeature) {
        storage.unset(feature: feature.id)
    }

    public static func == (lhs: EEnumLiteral, rhs: EEnumLiteral) -> Bool {
        return lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - EEnum

/// An enumeration type in the Ecore metamodel.
///
/// `EEnum` represents enumerated types with a fixed set of named values,
/// similar to Swift enums or Java enums.
///
/// Each enum contains a collection of ``EEnumLiteral`` values that define
/// the valid values for attributes of this type.
///
/// ## Example
///
/// ```swift
/// let birdType = EEnum(
///     name: "BirdType",
///     literals: [
///         EEnumLiteral(name: "blackbird", value: 0),
///         EEnumLiteral(name: "thrush", value: 1),
///         EEnumLiteral(name: "bluebird", value: 2)
///     ]
/// )
///
/// // Look up literal by name
/// let literal = birdType.getLiteral(name: "thrush")
/// print(literal?.value)  // 1
/// ```
public struct EEnum: ENamedElement {
    /// The type of classifier for this enum.
    public typealias Classifier = EEnumClassifier

    /// Unique identifier for this enum.
    public let id: EUUID

    /// The metaclass describing this enum.
    public let eClass: Classifier

    /// The name of this enum.
    ///
    /// Should be unique within the containing package. Example: "BirdType".
    public var name: String

    /// Annotations attached to this enum.
    public var eAnnotations: [EAnnotation]

    /// The literals (named values) in this enum.
    ///
    /// Each literal has a unique name and integer value within the enum.
    public var literals: [EEnumLiteral]

    /// Internal storage for feature values.
    private var storage: EObjectStorage

    /// Creates a new enumeration.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (generates a new UUID if not provided).
    ///   - name: The name of the enum.
    ///   - literals: The literal values in this enum.
    ///   - eAnnotations: Annotations (empty by default).
    public init(
        id: EUUID = EUUID(),
        name: String,
        literals: [EEnumLiteral] = [],
        eAnnotations: [EAnnotation] = []
    ) {
        self.id = id
        self.eClass = EEnumClassifier()
        self.name = name
        self.literals = literals
        self.eAnnotations = eAnnotations
        self.storage = EObjectStorage()
    }

    /// Retrieves a literal by its name.
    ///
    /// - Parameter name: The name of the literal to find.
    /// - Returns: The matching literal, or `nil` if not found.
    public func getLiteral(name: String) -> EEnumLiteral? {
        return literals.first { $0.name == name }
    }

    /// Retrieves a literal by its integer value.
    ///
    /// - Parameter value: The integer value of the literal to find.
    /// - Returns: The matching literal, or `nil` if not found.
    public func getLiteral(value: Int) -> EEnumLiteral? {
        return literals.first { $0.value == value }
    }

    public func eGet(_ feature: some EStructuralFeature) -> (any EcoreValue)? {
        return storage.get(feature: feature.id)
    }

    public mutating func eSet(_ feature: some EStructuralFeature, _ value: (any EcoreValue)?) {
        storage.set(feature: feature.id, value: value)
    }

    public func eIsSet(_ feature: some EStructuralFeature) -> Bool {
        return storage.isSet(feature: feature.id)
    }

    public mutating func eUnset(_ feature: some EStructuralFeature) {
        storage.unset(feature: feature.id)
    }

    public static func == (lhs: EEnum, rhs: EEnum) -> Bool {
        return lhs.id == rhs.id
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Classifier Types

/// Metaclass for `EDataType`.
public struct EDataTypeClassifier: EClassifier {
    public let id: EUUID = EUUID()
    public var name: String { "EDataType" }
}

/// Metaclass for `EEnumLiteral`.
public struct EEnumLiteralClassifier: EClassifier {
    public let id: EUUID = EUUID()
    public var name: String { "EEnumLiteral" }
}

/// Metaclass for `EEnum`.
public struct EEnumClassifier: EClassifier {
    public let id: EUUID = EUUID()
    public var name: String { "EEnum" }
}
