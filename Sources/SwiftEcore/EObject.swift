//
// EObject.swift
// SwiftEcore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

// MARK: - Forward Declarations

/// A classifier (type) in the Ecore metamodel
public protocol EClassifier: Sendable, Identifiable, Hashable where ID == EUUID {
    var name: String { get }
}

/// A structural feature (attribute or reference) in the Ecore metamodel
public protocol EStructuralFeature: Sendable, Identifiable, Hashable where ID == EUUID {
    var name: String { get }
}

// MARK: - EObject Protocol

/// Base protocol for all Ecore model elements.
///
/// EObject is the root of the Ecore metamodel hierarchy. All model elements
/// (both metamodel and model instances) implement this protocol.
///
/// Key capabilities:
/// - Reflective access to features via `eGet`/`eSet`
/// - Identity via `Identifiable`
/// - Value semantics via `Sendable` and `Hashable`
public protocol EObject: EcoreValue {
    /// The type of classifier (metaclass) for this object
    associatedtype Classifier: EClassifier

    /// The identifier type (must be EUUID)
    associatedtype ID = EUUID

    /// Unique identifier for this object
    var id: EUUID { get }

    /// Returns the metaclass (EClass) describing this object's type
    ///
    /// Every EObject knows its metaclass, which describes its structure
    /// (attributes, references, operations, etc.)
    var eClass: Classifier { get }

    /// Reflectively get the value of a feature
    ///
    /// - Parameter feature: The structural feature to get
    /// - Returns: The feature value, or nil if not set
    func eGet(_ feature: some EStructuralFeature) -> (any EcoreValue)?

    /// Reflectively set the value of a feature
    ///
    /// - Parameters:
    ///   - feature: The structural feature to set
    ///   - value: The new value
    mutating func eSet(_ feature: some EStructuralFeature, _ value: (any EcoreValue)?)

    /// Check if a feature has been explicitly set
    ///
    /// - Parameter feature: The structural feature to check
    /// - Returns: true if the feature is set, false otherwise
    func eIsSet(_ feature: some EStructuralFeature) -> Bool

    /// Unset a feature, returning it to its default value
    ///
    /// - Parameter feature: The structural feature to unset
    mutating func eUnset(_ feature: some EStructuralFeature)
}

// Provide Identifiable conformance
extension EObject {
    public var id: EUUID { id }
}

// MARK: - Helper Types

/// Internal storage for feature values in an EObject.
///
/// This is a helper type and does NOT conform to EObject itself.
/// It provides the storage mechanism for types that DO conform to EObject.
public struct EObjectStorage: Sendable {
    private var values: [EUUID: any EcoreValue]
    private var isset: Set<EUUID>

    public init() {
        self.values = [:]
        self.isset = []
    }

    public func get(feature: EUUID) -> (any EcoreValue)? {
        return values[feature]
    }

    public mutating func set(feature: EUUID, value: (any EcoreValue)?) {
        if let value = value {
            values[feature] = value
            isset.insert(feature)
        } else {
            values.removeValue(forKey: feature)
            isset.remove(feature)
        }
    }

    public func isSet(feature: EUUID) -> Bool {
        return isset.contains(feature)
    }

    public mutating func unset(feature: EUUID) {
        values.removeValue(forKey: feature)
        isset.remove(feature)
    }
}

extension EObjectStorage: Equatable {
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
