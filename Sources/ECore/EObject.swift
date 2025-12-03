//
// EObject.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

// MARK: - Forward Declarations

/// A classifier (type) in the Ecore metamodel.
///
/// Classifiers define types in the metamodel, including classes, data types, and enumerations.
/// Each classifier has a unique identifier and a name that distinguishes it within its package.
public protocol EClassifier: Sendable, Identifiable, Hashable where ID == EUUID {
    /// The name of this classifier.
    ///
    /// Must be unique within the containing package.
    var name: String { get }
}

/// A structural feature (attribute or reference) in the Ecore metamodel.
///
/// Structural features represent the properties of a class, including both attributes
/// (data values) and references (relationships to other objects).
public protocol EStructuralFeature: Sendable, Identifiable, Hashable where ID == EUUID {
    /// The name of this structural feature.
    ///
    /// Must be unique within the containing class.
    var name: String { get }
}

/// An operation in the Ecore metamodel.
///
/// Operations represent the behavioural methods that can be invoked on instances of a class.
public protocol EOperation: Sendable, Identifiable, Hashable where ID == EUUID {
    /// The name of this operation.
    ///
    /// Must be unique within the containing class.
    var name: String { get }
}

// MARK: - EObject Protocol

/// Base protocol for all Ecore model elements.
///
/// `EObject` is the root of the Ecore metamodel hierarchy. All model elements
/// (both metamodel definitions and model instances) conform to this protocol.
///
/// ## Key Capabilities
///
/// - **Reflective Access**: Features can be accessed dynamically via ``eGet(_:)`` and ``eSet(_:_:)``
/// - **Identity**: Every object has a unique identifier via `Identifiable`
/// - **Value Semantics**: Thread-safe through `Sendable` and value comparison via `Hashable`
///
/// ## Usage
///
/// Types conforming to `EObject` must implement the reflective API to allow
/// dynamic access to their structural features (attributes and references).
public protocol EObject: EcoreValue {
    /// The type of classifier (metaclass) for this object.
    ///
    /// This associated type allows each `EObject` to specify its own classifier type,
    /// providing type safety whilst maintaining flexibility.
    associatedtype Classifier: EClassifier

    /// The identifier type (must be EUUID).
    ///
    /// All Ecore objects use `EUUID` for identity.
    associatedtype ID = EUUID

    /// Unique identifier for this object.
    ///
    /// The identifier is immutable and distinguishes this object from all others.
    /// Identity-based equality uses this property.
    var id: EUUID { get }

    /// Returns the metaclass (EClass) describing this object's type.
    ///
    /// Every `EObject` knows its metaclass, which describes its structure including:
    /// - Attributes (data properties)
    /// - References (relationships to other objects)
    /// - Operations (behavioural methods)
    /// - Supertypes (inheritance hierarchy)
    var eClass: Classifier { get }

    /// Reflectively retrieves the value of a feature.
    ///
    /// This method provides dynamic access to the object's properties without
    /// requiring compile-time knowledge of the feature.
    ///
    /// - Parameter feature: The structural feature whose value to retrieve.
    /// - Returns: The feature's current value, or `nil` if not set.
    func eGet(_ feature: some EStructuralFeature) -> (any EcoreValue)?

    /// Reflectively sets the value of a feature.
    ///
    /// This method provides dynamic modification of the object's properties.
    /// Setting a value to `nil` has the same effect as calling ``eUnset(_:)``.
    ///
    /// - Parameters:
    ///   - feature: The structural feature to modify.
    ///   - value: The new value, or `nil` to unset.
    mutating func eSet(_ feature: some EStructuralFeature, _ value: (any EcoreValue)?)

    /// Checks whether a feature has been explicitly set.
    ///
    /// A feature is considered "set" if it has been assigned a value, even if that
    /// value equals the feature's default. This differs from checking if the value
    /// is `nil`, as unset features may have non-nil defaults.
    ///
    /// - Parameter feature: The structural feature to check.
    /// - Returns: `true` if the feature has been set, `false` otherwise.
    func eIsSet(_ feature: some EStructuralFeature) -> Bool

    /// Unsets a feature, returning it to its default value.
    ///
    /// After unsetting, ``eIsSet(_:)`` will return `false` for this feature,
    /// and ``eGet(_:)`` will return the feature's default value (which may be `nil`).
    ///
    /// - Parameter feature: The structural feature to unset.
    mutating func eUnset(_ feature: some EStructuralFeature)
}

// MARK: - Helper Types

/// Internal storage for feature values in an `EObject`.
///
/// This helper type manages the dynamic storage of feature values for objects
/// conforming to ``EObject``. It tracks both the values themselves and which
/// features have been explicitly set.
///
/// ## Important
///
/// This is a helper type and does **not** conform to `EObject` itself.
/// It provides the storage mechanism for types that **do** conform to `EObject`.
///
/// ## Implementation Notes
///
/// - Uses a dictionary for efficient feature value lookup by identifier
/// - Maintains a separate set to track which features are explicitly set
/// - Supports value semantics through `Sendable`, `Equatable`, and `Hashable`
public struct EObjectStorage: Sendable {
    /// Dictionary mapping feature identifiers to their values.
    private var values: [EUUID: any EcoreValue]

    /// Set of feature identifiers that have been explicitly set.
    private var isset: Set<EUUID>

    /// Creates a new empty storage.
    ///
    /// The storage is initialised with no features set.
    public init() {
        self.values = [:]
        self.isset = []
    }

    /// Retrieves the value for a feature.
    ///
    /// - Parameter feature: The identifier of the feature to retrieve.
    /// - Returns: The feature's value, or `nil` if not set.
    public func get(feature: EUUID) -> (any EcoreValue)? {
        return values[feature]
    }

    /// Sets the value for a feature.
    ///
    /// If `value` is `nil`, this is equivalent to calling ``unset(feature:)``.
    ///
    /// - Parameters:
    ///   - feature: The identifier of the feature to set.
    ///   - value: The new value, or `nil` to unset.
    public mutating func set(feature: EUUID, value: (any EcoreValue)?) {
        if let value = value {
            values[feature] = value
            isset.insert(feature)
        } else {
            values.removeValue(forKey: feature)
            isset.remove(feature)
        }
    }

    /// Checks whether a feature has been explicitly set.
    ///
    /// - Parameter feature: The identifier of the feature to check.
    /// - Returns: `true` if the feature has been set, `false` otherwise.
    public func isSet(feature: EUUID) -> Bool {
        return isset.contains(feature)
    }

    /// Unsets a feature, removing its value and set status.
    ///
    /// After unsetting, ``isSet(feature:)`` will return `false` and
    /// ``get(feature:)`` will return `nil`.
    ///
    /// - Parameter feature: The identifier of the feature to unset.
    public mutating func unset(feature: EUUID) {
        values.removeValue(forKey: feature)
        isset.remove(feature)
    }
}

extension EObjectStorage: Equatable {
    /// Compares two storage instances for equality.
    ///
    /// Storages are equal if they have the same set features and matching values
    /// for those features. Value comparison uses string representation.
    ///
    /// - Parameters:
    ///   - lhs: The first storage to compare.
    ///   - rhs: The second storage to compare.
    /// - Returns: `true` if the storages are equal, `false` otherwise.
    public static func == (lhs: EObjectStorage, rhs: EObjectStorage) -> Bool {
        // Compare isset first for efficiency
        guard lhs.isset == rhs.isset else { return false }

        // Compare each set value
        for key in lhs.isset {
            guard let lValue = lhs.values[key],
                  let rValue = rhs.values[key] else {
                return false
            }

            // Compare using string representation (simplified)
            // In production, would use proper value comparison
            if String(describing: lValue) != String(describing: rValue) {
                return false
            }
        }
        return true
    }
}

extension EObjectStorage: Hashable {
    /// Hashes the essential components of this storage.
    ///
    /// Combines the set of set features and their values in deterministic order.
    ///
    /// - Parameter hasher: The hasher to use for combining components.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(isset)
        // Hash the values in a deterministic order
        for key in isset.sorted() {
            if let value = values[key] {
                hasher.combine(key)
                hasher.combine(String(describing: value))
            }
        }
    }
}
