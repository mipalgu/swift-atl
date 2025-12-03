//
// EClass.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

// MARK: - EClass

/// A class in the Ecore metamodel.
///
/// `EClass` represents a class definition in the metamodel, similar to a class declaration
/// in object-oriented programming languages. It defines the structure and behaviour of
/// model objects through:
///
/// - **Structural Features**: Attributes and references that define the class's properties
/// - **Operations**: Methods that can be invoked on instances
/// - **Inheritance**: Supertypes that this class extends
/// - **Metadata**: Whether the class is abstract or represents an interface
///
/// ## Example
///
/// ```swift
/// let person = EClass(
///     name: "Person",
///     isAbstract: false,
///     structuralFeatures: [
///         // Features would be added here
///     ]
/// )
/// ```
///
/// ## Inheritance
///
/// Classes can extend multiple supertypes through the ``eSuperTypes`` property.
/// The ``allSuperTypes`` computed property provides the complete inheritance hierarchy
/// including transitive supertypes.
///
/// ## Feature Access
///
/// Structural features can be accessed by name using ``getStructuralFeature(name:)``
/// or filtered by type using ``allAttributes`` and ``allReferences``.
public struct EClass: ENamedElement {
    /// The type of classifier for this class.
    ///
    /// All instances of `EClass` use ``EClassClassifier`` as their metaclass.
    public typealias Classifier = EClassClassifier

    /// Unique identifier for this class.
    ///
    /// Used for identity-based equality and hashing.
    public let id: EUUID

    /// The metaclass describing this class.
    public let eClass: Classifier

    /// The name of this class.
    ///
    /// Should be unique within the containing package. By convention, class names
    /// use UpperCamelCase.
    public var name: String

    /// Annotations attached to this class.
    ///
    /// Commonly used for code generation hints, documentation, or constraints.
    public var eAnnotations: [EAnnotation]

    /// Whether this class is abstract.
    ///
    /// Abstract classes cannot be instantiated directly and typically define
    /// common behaviour for concrete subclasses.
    public var isAbstract: Bool

    /// Whether this class represents an interface.
    ///
    /// Interfaces define contracts without implementation and can be mixed into
    /// classes through multiple inheritance.
    public var isInterface: Bool

    /// The direct supertypes of this class.
    ///
    /// Classes can extend multiple supertypes, enabling multiple inheritance.
    /// For the complete inheritance hierarchy including transitive supertypes,
    /// use ``allSuperTypes``.
    public var eSuperTypes: [EClass]

    /// The structural features (attributes and references) of this class.
    ///
    /// Features defined directly on this class, not including inherited features.
    /// For all features including inherited ones, use ``allStructuralFeatures``.
    public var eStructuralFeatures: [any EStructuralFeature]

    /// The operations (methods) of this class.
    ///
    /// Operations defined directly on this class, not including inherited operations.
    public var eOperations: [any EOperation]

    /// Internal storage for feature values.
    private var storage: EObjectStorage

    /// Creates a new class.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (generates a new UUID if not provided).
    ///   - name: The name of the class.
    ///   - isAbstract: Whether the class is abstract (default: false).
    ///   - isInterface: Whether the class represents an interface (default: false).
    ///   - eSuperTypes: The direct supertypes (empty by default).
    ///   - eStructuralFeatures: The structural features (empty by default).
    ///   - eOperations: The operations (empty by default).
    ///   - eAnnotations: Annotations (empty by default).
    public init(
        id: EUUID = EUUID(),
        name: String,
        isAbstract: Bool = false,
        isInterface: Bool = false,
        eSuperTypes: [EClass] = [],
        eStructuralFeatures: [any EStructuralFeature] = [],
        eOperations: [any EOperation] = [],
        eAnnotations: [EAnnotation] = []
    ) {
        self.id = id
        self.eClass = EClassClassifier()
        self.name = name
        self.isAbstract = isAbstract
        self.isInterface = isInterface
        self.eSuperTypes = eSuperTypes
        self.eStructuralFeatures = eStructuralFeatures
        self.eOperations = eOperations
        self.eAnnotations = eAnnotations
        self.storage = EObjectStorage()
    }

    // MARK: - Computed Properties

    /// All structural features including inherited ones.
    ///
    /// Combines features from this class and all supertypes, with this class's
    /// features taking precedence in case of name conflicts.
    public var allStructuralFeatures: [any EStructuralFeature] {
        var features = eStructuralFeatures
        for superType in eSuperTypes {
            features.append(contentsOf: superType.allStructuralFeatures)
        }
        return features
    }

    /// All attributes including inherited ones.
    ///
    /// Filters ``allStructuralFeatures`` to return only attributes.
    public var allAttributes: [any EAttribute] {
        return allStructuralFeatures.compactMap { $0 as? any EAttribute }
    }

    /// All references including inherited ones.
    ///
    /// Filters ``allStructuralFeatures`` to return only references.
    public var allReferences: [any EReference] {
        return allStructuralFeatures.compactMap { $0 as? any EReference }
    }

    /// All containment references including inherited ones.
    ///
    /// Filters ``allReferences`` to return only containment references.
    /// Containment references define parent-child relationships in the model.
    public var allContainments: [any EReference] {
        return allReferences.filter { reference in
            // Will check containment property when EReference is fully implemented
            // For now, return empty array
            return false
        }
    }

    /// All supertypes including transitive ones.
    ///
    /// Returns the complete inheritance hierarchy by recursively collecting
    /// all direct and indirect supertypes. The result includes:
    /// - Direct supertypes (``eSuperTypes``)
    /// - Supertypes of supertypes (transitively)
    ///
    /// Duplicates are included if a class appears multiple times in the hierarchy.
    public var allSuperTypes: [EClass] {
        var result = eSuperTypes
        for superType in eSuperTypes {
            result.append(contentsOf: superType.allSuperTypes)
        }
        return result
    }

    // MARK: - Methods

    /// Retrieves a structural feature by name.
    ///
    /// Searches this class's features first, then inherited features.
    ///
    /// - Parameter name: The name of the feature to find.
    /// - Returns: The matching feature, or `nil` if not found.
    public func getStructuralFeature(name: String) -> (any EStructuralFeature)? {
        return allStructuralFeatures.first { $0.name == name }
    }

    /// Retrieves an attribute by name.
    ///
    /// Convenience method that searches only attributes.
    ///
    /// - Parameter name: The name of the attribute to find.
    /// - Returns: The matching attribute, or `nil` if not found.
    public func getEAttribute(name: String) -> (any EAttribute)? {
        return allAttributes.first { $0.name == name }
    }

    /// Retrieves a reference by name.
    ///
    /// Convenience method that searches only references.
    ///
    /// - Parameter name: The name of the reference to find.
    /// - Returns: The matching reference, or `nil` if not found.
    public func getEReference(name: String) -> (any EReference)? {
        return allReferences.first { $0.name == name }
    }

    /// Checks if this class is a supertype of another class.
    ///
    /// Returns `true` if `other` directly or indirectly extends this class.
    ///
    /// - Parameter other: The class to check.
    /// - Returns: `true` if this class is a supertype of `other`, `false` otherwise.
    public func isSuperTypeOf(_ other: EClass) -> Bool {
        // Check if other directly extends this class
        if other.eSuperTypes.contains(where: { $0.id == self.id }) {
            return true
        }
        // Check transitively
        for superType in other.eSuperTypes {
            if self.isSuperTypeOf(superType) {
                return true
            }
        }
        return false
    }

    // MARK: - EObject Protocol Implementation

    /// Reflectively retrieves the value of a feature.
    ///
    /// This implementation uses internal storage to dynamically access feature values
    /// without compile-time knowledge of the feature.
    ///
    /// - Parameter feature: The structural feature whose value to retrieve.
    /// - Returns: The feature's current value, or `nil` if not set.
    public func eGet(_ feature: some EStructuralFeature) -> (any EcoreValue)? {
        return storage.get(feature: feature.id)
    }

    /// Reflectively sets the value of a feature.
    ///
    /// This implementation uses internal storage to dynamically modify feature values.
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

    /// Compares two classes for equality.
    ///
    /// Classes are equal if they have the same identifier.
    ///
    /// - Parameters:
    ///   - lhs: The first class to compare.
    ///   - rhs: The second class to compare.
    /// - Returns: `true` if the classes are equal, `false` otherwise.
    public static func == (lhs: EClass, rhs: EClass) -> Bool {
        return lhs.id == rhs.id
    }

    /// Hashes the essential components of this class.
    ///
    /// Only the identifier is used for hashing to maintain consistency with equality.
    ///
    /// - Parameter hasher: The hasher to use for combining components.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - Classifier Type

/// Metaclass for `EClass`.
///
/// Describes the structure of `EClass` itself within the metamodel hierarchy.
/// This is the classifier that describes all `EClass` instances.
public struct EClassClassifier: EClassifier {
    /// Unique identifier for this metaclass.
    ///
    /// Each instance creates its own unique identifier.
    public let id: EUUID = EUUID()

    /// The name of this classifier.
    ///
    /// Always returns `"EClass"` to identify this as the metaclass for classes.
    public var name: String { "EClass" }
}
