//
// EModelElement.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

// MARK: - EAnnotation

/// An annotation on a model element.
///
/// Annotations provide a mechanism to attach arbitrary metadata to model elements
/// without modifying the core metamodel. They are commonly used for:
///
/// - Documentation and comments
/// - Tool-specific metadata
/// - Generation hints
/// - Validation constraints
///
/// Each annotation has a source URI that identifies its purpose and a dictionary
/// of key-value details containing the actual metadata.
///
/// ## Example
///
/// ```swift
/// let docAnnotation = EAnnotation(
///     source: "http://www.eclipse.org/emf/2002/GenModel",
///     details: ["documentation": "This class represents a person"]
/// )
/// ```
public struct EAnnotation: EcoreValue {
    /// Unique identifier for this annotation.
    ///
    /// Used for identity-based equality comparison.
    public let id: EUUID

    /// The source URI identifying the annotation's purpose.
    ///
    /// This URI typically identifies the tool or framework that created the annotation
    /// and interprets its details. Common examples include:
    ///
    /// - `http://www.eclipse.org/emf/2002/GenModel` - EMF code generation settings
    /// - `http://www.eclipse.org/emf/2002/Ecore` - Ecore-specific metadata
    ///
    /// The source should be unique within the containing model element's annotations.
    public var source: String

    /// Key-value pairs of annotation details.
    ///
    /// The details dictionary contains the actual metadata associated with this annotation.
    /// Keys and values are both strings, allowing flexible representation of various
    /// metadata types.
    public var details: [String: String]

    /// Creates a new annotation.
    ///
    /// - Parameters:
    ///   - id: Unique identifier (generates a new UUID if not provided).
    ///   - source: The source URI identifying the annotation's purpose.
    ///   - details: Key-value pairs of annotation metadata (empty by default).
    public init(
        id: EUUID = EUUID(),
        source: String,
        details: [String: String] = [:]
    ) {
        self.id = id
        self.source = source
        self.details = details
    }

    /// Compares two annotations for equality.
    ///
    /// Annotations are equal if they have the same identifier, source, and details.
    ///
    /// - Parameters:
    ///   - lhs: The first annotation to compare.
    ///   - rhs: The second annotation to compare.
    /// - Returns: `true` if the annotations are equal, `false` otherwise.
    public static func == (lhs: EAnnotation, rhs: EAnnotation) -> Bool {
        lhs.id == rhs.id &&
        lhs.source == rhs.source &&
        lhs.details == rhs.details
    }

    /// Hashes the essential components of this annotation.
    ///
    /// - Parameter hasher: The hasher to use for combining components.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(source)
        hasher.combine(details)
    }
}

// MARK: - EModelElement

/// Base protocol for model elements that can have annotations.
///
/// `EModelElement` extends ``EObject`` to add support for attaching annotations,
/// making it the base for most metamodel elements including classes, attributes,
/// references, packages, and more.
///
/// Annotations allow metadata to be attached to model elements without modifying
/// the core metamodel structure, supporting use cases such as:
///
/// - Code generation directives
/// - Documentation strings
/// - Validation rules
/// - Tool-specific settings
///
/// ## Usage
///
/// ```swift
/// struct MyClass: EModelElement {
///     let id: EUUID
///     let eClass: MyClassifier
///     var eAnnotations: [EAnnotation] = []
///
///     mutating func addDocumentation(_ text: String) {
///         let annotation = EAnnotation(
///             source: "http://www.eclipse.org/emf/2002/GenModel",
///             details: ["documentation": text]
///         )
///         eAnnotations.append(annotation)
///     }
/// }
/// ```
public protocol EModelElement: EObject {
    /// Annotations attached to this model element.
    ///
    /// The array can contain multiple annotations, each identified by a unique source URI.
    /// Annotations are typically added during model construction or by tools processing the model.
    var eAnnotations: [EAnnotation] { get set }

    /// Retrieves an annotation by its source URI.
    ///
    /// This convenience method searches the ``eAnnotations`` array for an annotation
    /// with the specified source URI.
    ///
    /// - Parameter source: The source URI to search for.
    /// - Returns: The first annotation matching the source, or `nil` if not found.
    func getEAnnotation(source: String) -> EAnnotation?
}

// Default implementation
extension EModelElement {
    /// Default implementation of annotation lookup.
    ///
    /// Searches linearly through ``eAnnotations`` for the first annotation
    /// matching the given source URI.
    ///
    /// - Parameter source: The source URI to search for.
    /// - Returns: The first matching annotation, or `nil` if not found.
    public func getEAnnotation(source: String) -> EAnnotation? {
        return eAnnotations.first { $0.source == source }
    }
}

// MARK: - ENamedElement

/// Base protocol for model elements that have a name.
///
/// `ENamedElement` extends ``EModelElement`` to add a name attribute,
/// making it the base for most metamodel constructs including:
///
/// - Classes and data types
/// - Attributes and references
/// - Packages and factories
/// - Operations and parameters
///
/// The name is used for identification within the model and typically must be
/// unique within its containing element (e.g., attribute names must be unique
/// within a class).
///
/// ## Usage
///
/// ```swift
/// struct MyAttribute: ENamedElement {
///     let id: EUUID
///     let eClass: MyClassifier
///     var name: String
///     var eAnnotations: [EAnnotation] = []
///
///     init(name: String) {
///         self.id = EUUID()
///         self.eClass = MyClassifier(name: "EAttribute")
///         self.name = name
///     }
/// }
/// ```
public protocol ENamedElement: EModelElement {
    /// The name of this element.
    ///
    /// The name should be a valid identifier and is typically unique within
    /// the containing element. For example:
    ///
    /// - Class names must be unique within their package
    /// - Attribute names must be unique within their class
    /// - Package names must be unique within their parent package
    var name: String { get set }
}
