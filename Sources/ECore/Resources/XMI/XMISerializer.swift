//
// XMISerializer.swift
// ECore
//
//  Created by Rene Hexel on 4/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation
import SwiftXML

/// Serialises EMF objects to XMI (XML Metadata Interchange) format
///
/// The XMI serialiser converts in-memory object graphs stored in Resources to XMI files.
/// It handles:
/// - Metamodel (.ecore) files with full Ecore support
/// - Model instance (.xmi) files with arbitrary attributes
/// - Containment references (nested elements)
/// - Same-resource references (href attributes with XPath, e.g., `href="#//@employees.0"`)
/// - Cross-resource references (href attributes with URI and fragment, e.g., `href="department-b.xmi#/"`)
/// - Proper XML namespace declarations
///
/// ## Cross-Resource References
///
/// When a reference points to an object in another resource (represented as a `ResourceProxy`),
/// the serializer generates an href with the target resource's URI and fragment:
/// ```xml
/// <mainDepartment href="department-b.xmi#/"/>
/// ```
///
/// ## Usage Example
///
/// ```swift
/// let serializer = XMISerializer()
/// try await serializer.serialize(resource, to: outputURL)
/// ```
public struct XMISerializer: Sendable {

    /// Initialise a new XMI serialiser
    public init() {}

    /// Serialise a Resource to an XMI file
    ///
    /// - Parameters:
    ///   - resource: The Resource containing objects to serialise
    ///   - url: The URL where the XMI file should be written
    /// - Throws: `XMIError` if serialisation fails or I/O errors occur
    public func serialize(_ resource: Resource, to url: URL) async throws {
        let xmiString = try await serialize(resource)
        try xmiString.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Serialise a Resource to an XMI string
    ///
    /// - Parameter resource: The Resource containing objects to serialise
    /// - Returns: XMI formatted string
    /// - Throws: `XMIError` if serialisation fails
    public func serialize(_ resource: Resource) async throws -> String {
        let roots = await resource.getRootObjects()

        guard !roots.isEmpty else {
            throw XMIError.parseError("No root object to serialise")
        }

        // Build XML document
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"

        if roots.count == 1 {
            // Single root object - serialize directly as the root element
            let rootObject = roots[0]
            xml += try await serializeObject(rootObject, in: resource, indentLevel: 0)
        } else {
            // Multiple root objects - wrap in xmi:XMI element like pyecore
            xml += "<xmi:XMI xmi:version=\"2.0\" xmlns:xmi=\"http://www.omg.org/XMI\""

            // Collect all namespaces from all root objects
            var namespaces: Set<String> = []
            for rootObject in roots {
                let objectNamespaces = await collectNamespaces(rootObject, in: resource)
                namespaces.formUnion(objectNamespaces)
            }

            // Add namespace declarations
            for namespace in namespaces.sorted() {
                xml += " \(namespace)"
            }
            xml += ">\n"

            // Serialize each root object as a child of xmi:XMI
            for rootObject in roots {
                xml += try await serializeObject(rootObject, in: resource, indentLevel: 1)
                xml += "\n"
            }

            xml += "</xmi:XMI>"
        }
        xml += "\n"

        return xml
    }

    // MARK: - Private Serialization Methods

    /// Serialise an object to XML
    ///
    /// - Parameters:
    ///   - object: The object to serialise
    ///   - resource: The Resource for context and navigation
    ///   - indentLevel: Current indentation level for formatting
    /// - Returns: XML string representation
    /// - Throws: `XMIError` if serialisation fails
    private func serializeObject(_ object: any EObject, in resource: Resource, indentLevel: Int) async throws -> String {
        let indent = String(repeating: "    ", count: indentLevel)

        // Get object's class name
        let className = getClassName(object)

        // Determine namespace prefix and element name
        let (_, elementName) = getElementName(object, className: className)

        // Start element
        var xml = "\(indent)<\(elementName)"

        // Add namespace declarations at root level
        if indentLevel == 0 {
            xml += try await addNamespaceDeclarations(object, className: className, in: resource)
        }

        // Add attributes
        xml += try await addAttributes(object, in: resource)

        // Get contained children
        let children = try await getContainedChildren(object, in: resource)

        // Get cross-references
        let references = try await getCrossReferences(object, in: resource)

        // Check if we need to close element
        if children.isEmpty && references.isEmpty {
            xml += "/>"
        } else {
            xml += ">\n"

            // Serialise contained children
            for (featureName, childObjects) in children {
                for childObject in childObjects {
                    if childObject is DynamicEObject {
                        // Contained child as nested element
                        xml += try await serializeContainedChild(childObject, featureName: featureName, in: resource, indentLevel: indentLevel + 1)
                    }
                }
            }

            // Serialise cross-references
            for (featureName, target) in references {
                xml += try await serializeCrossReference(featureName: featureName, target: target, in: resource, indentLevel: indentLevel + 1)
            }

            // Close element
            xml += "\(indent)</\(elementName)>"
        }

        return xml
    }

    /// Serialise a contained child element
    ///
    /// - Parameters:
    ///   - object: The child object to serialise
    ///   - featureName: The feature name for the child
    ///   - resource: The Resource for context
    ///   - indentLevel: Current indentation level
    /// - Returns: XML string
    /// - Throws: `XMIError` if serialisation fails
    private func serializeContainedChild(_ object: any EObject, featureName: String, in resource: Resource, indentLevel: Int) async throws -> String {
        let indent = String(repeating: "    ", count: indentLevel)

        // Get attributes of child
        let attributes = try await getObjectAttributes(object, in: resource)

        // Get contained children of this child
        let children = try await getContainedChildren(object, in: resource)

        // Get cross-references
        let references = try await getCrossReferences(object, in: resource)

        var xml = "\(indent)<\(featureName)"

        // Add attributes
        for (key, value) in attributes.sorted(by: { $0.key < $1.key }) {
            xml += " \(key)=\"\(escapeXML(value))\""
        }

        if children.isEmpty && references.isEmpty {
            xml += "/>\n"
        } else {
            xml += ">\n"

            // Serialise nested children
            for (childFeatureName, childObjects) in children {
                for childObject in childObjects {
                    xml += try await serializeContainedChild(childObject, featureName: childFeatureName, in: resource, indentLevel: indentLevel + 1)
                }
            }

            // Serialise cross-references
            for (refFeatureName, target) in references {
                xml += try await serializeCrossReference(featureName: refFeatureName, target: target, in: resource, indentLevel: indentLevel + 1)
            }

            xml += "\(indent)</\(featureName)>\n"
        }

        return xml
    }

    /// Serialise a cross-reference as href
    ///
    /// - Parameters:
    ///   - featureName: The feature name
    ///   - target: Target of the reference (EUUID for same-resource, ResourceProxy for cross-resource)
    ///   - resource: The Resource for context
    ///   - indentLevel: Current indentation level
    /// - Returns: XML string
    /// - Throws: `XMIError` if serialisation fails
    private func serializeCrossReference(featureName: String, target: any EcoreValue, in resource: Resource, indentLevel: Int) async throws -> String {
        let indent = String(repeating: "    ", count: indentLevel)

        let href: String

        if let targetId = target as? EUUID {
            // Same-resource reference: Generate XPath
            href = try await generateXPath(for: targetId, in: resource)
        } else if let proxy = target as? ResourceProxy {
            // Cross-resource reference: Use proxy's URI and fragment
            let fragment = proxy.fragment.hasPrefix("#") ? proxy.fragment : "#\(proxy.fragment)"
            href = "\(proxy.uri)\(fragment)"
        } else {
            throw XMIError.invalidReference("Unsupported reference type: \(type(of: target))")
        }

        return "\(indent)<\(featureName) href=\"\(href)\"/>\n"
    }

    /// Generate XPath reference for an object
    ///
    /// - Parameters:
    ///   - objectId: The target object ID
    ///   - resource: The Resource containing the object
    /// - Returns: XPath string (e.g., "#//@members.0")
    /// - Throws: `XMIError` if path generation fails
    private func generateXPath(for objectId: EUUID, in resource: Resource) async throws -> String {
        let roots = await resource.getRootObjects()

        guard let targetObject = await resource.resolve(objectId) else {
            throw XMIError.invalidReference("Cannot resolve object \(objectId)")
        }

        // If target is a root object, use simple fragment
        if roots.contains(where: { $0.id == objectId }) {
            return "#/"
        }

        // Build path from root to target
        // This is a simplified implementation - in full EMF, we'd track containment hierarchy
        // For now, try to find the path by examining all objects

        if let path = await findPath(to: targetObject, in: resource) {
            return "#\(path)"
        }

        // Fallback: use object ID as fragment
        return "#\(objectId.uuidString)"
    }

    /// Find XPath from root to target object
    ///
    /// - Parameters:
    ///   - target: The target object
    ///   - resource: The Resource
    /// - Returns: XPath string (e.g., "//@members.0")
    private func findPath(to target: any EObject, in resource: Resource) async -> String? {
        let roots = await resource.getRootObjects()

        for root in roots {
            if let path = await findPath(to: target, from: root, currentPath: "//", in: resource) {
                return path
            }
        }

        return nil
    }

    /// Recursively find path from current object to target
    ///
    /// - Parameters:
    ///   - target: The target object
    ///   - current: Current object in traversal
    ///   - currentPath: Path accumulated so far
    ///   - resource: The Resource
    /// - Returns: Complete path if found
    private func findPath(to target: any EObject, from current: any EObject, currentPath: String, in resource: Resource) async -> String? {
        // Get all features of current object
        guard let dynamicObject = current as? DynamicEObject else {
            return nil
        }

        let allFeatures = await resource.getFeatureNames(objectId: dynamicObject.id)

        for featureName in allFeatures {
            // Only consider containment relationships for XPath generation
            // Use metamodel information to determine if this is a containment feature
            if let feature = dynamicObject.eClass.getStructuralFeature(name: featureName),
               let reference = feature as? EReference {
                // Skip non-containment references - only traverse containment relationships
                guard reference.containment else { continue }

                // Skip features that are opposites of containment relationships
                if let oppositeId = reference.opposite,
                   let oppositeRef = dynamicObject.eClass.allReferences.first(where: { $0.id == oppositeId }),
                   oppositeRef.containment {
                    continue
                }
            } else {
                // For dynamic features without metamodel info, assume non-containment
                // In proper EMF, all structural features should have metamodel definitions
                continue
            }

            guard let value = await resource.eGet(objectId: dynamicObject.id, feature: featureName) else {
                continue
            }

            // Check if this is a containment feature
            if let childId = value as? EUUID {
                // Single-valued feature
                if childId == target.id {
                    return "\(currentPath)@\(featureName)"
                }

                // Recurse
                if let childObject = await resource.resolve(childId) {
                    if let path = await findPath(to: target, from: childObject, currentPath: "\(currentPath)@\(featureName)/", in: resource) {
                        return path
                    }
                }
            } else if let childIds = value as? [EUUID] {
                // Multi-valued feature
                for (index, childId) in childIds.enumerated() {
                    if childId == target.id {
                        return "\(currentPath)@\(featureName).\(index)"
                    }

                    // Recurse
                    if let childObject = await resource.resolve(childId) {
                        if let path = await findPath(to: target, from: childObject, currentPath: "\(currentPath)@\(featureName).\(index)/", in: resource) {
                            return path
                        }
                    }
                }
            }
        }

        return nil
    }

    /// Add namespace declarations to root element
    ///
    /// - Parameters:
    ///   - object: The root object
    ///   - className: The class name
    ///   - resource: The Resource
    /// - Returns: Namespace declaration string
    private func addNamespaceDeclarations(_ object: any EObject, className: String, in resource: Resource) async throws -> String {
        var declarations = ""

        // Always add XMI namespace
        declarations += " xmi:version=\"2.0\""
        declarations += " xmlns:xmi=\"http://www.omg.org/XMI\""

        // Determine namespace based on object type
        if className.hasPrefix("E") {
            // Ecore metamodel object
            declarations += " xmlns:ecore=\"http://www.eclipse.org/emf/2002/Ecore\""
        } else {
            // Instance object - extract namespace from eClass
            if object is DynamicEObject {
                // Try to determine namespace from available attributes
                if let nsURI = await resource.eGet(objectId: object.id, feature: "nsURI") as? String {
                    let prefix = await resource.eGet(objectId: object.id, feature: "nsPrefix") as? String ?? "ns"
                    declarations += " xmlns:\(prefix)=\"\(nsURI)\""
                } else {
                    // Use a generic namespace based on class name
                    let prefix = className.lowercased()
                    declarations += " xmlns:\(prefix)=\"http://swift-modelling.org/test/\(prefix)\""
                }
            }
        }

        return declarations
    }

    /// Add attributes to element
    ///
    /// - Parameters:
    ///   - object: The object
    ///   - resource: The Resource
    /// - Returns: Attributes string
    private func addAttributes(_ object: any EObject, in resource: Resource) async throws -> String {
        var attributes = ""

        let objectAttributes = try await getObjectAttributes(object, in: resource)

        // Sort attributes for consistent output
        for (key, value) in objectAttributes.sorted(by: { $0.key < $1.key }) {
            attributes += " \(key)=\"\(escapeXML(value))\""
        }

        return attributes
    }

    /// Get attributes of an object (non-reference features)
    ///
    /// - Parameters:
    ///   - object: The object
    ///   - resource: The Resource
    /// - Returns: Dictionary of attribute names to string values
    private func getObjectAttributes(_ object: any EObject, in resource: Resource) async throws -> [String: String] {
        var attributes: [String: String] = [:]

        guard let dynamicObject = object as? DynamicEObject else {
            return attributes
        }

        let featureNames = await resource.getFeatureNames(objectId: dynamicObject.id)

        for featureName in featureNames {
            // Skip internal features
            if featureName.hasPrefix("_") || featureName == "eClass" {
                continue
            }

            guard let value = await resource.eGet(objectId: dynamicObject.id, feature: featureName) else {
                continue
            }

            // Only serialise primitive types as attributes
            if value is EUUID || value is [EUUID] {
                // Skip references - they're handled separately
                continue
            }

            // Convert value to string
            attributes[featureName] = convertToString(value)
        }

        return attributes
    }

    /// Get contained children of an object
    ///
    /// - Parameters:
    ///   - object: The parent object
    ///   - resource: The Resource
    /// - Returns: Dictionary of feature name to child objects
    private func getContainedChildren(_ object: any EObject, in resource: Resource) async throws -> [String: [any EObject]] {
        var children: [String: [any EObject]] = [:]

        guard let dynamicObject = object as? DynamicEObject else {
            return children
        }

        let featureNames = await resource.getFeatureNames(objectId: dynamicObject.id)

        for featureName in featureNames {
            // Use metamodel to determine if this is a containment feature
            if let feature = dynamicObject.eClass.getStructuralFeature(name: featureName),
               let reference = feature as? EReference {
                // Only include containment references
                guard reference.containment else { continue }

                // Skip features that are opposites of containment relationships
                if let oppositeId = reference.opposite,
                   let oppositeRef = dynamicObject.eClass.allReferences.first(where: { $0.id == oppositeId }),
                   oppositeRef.containment {
                    continue
                }
            } else if let feature = dynamicObject.eClass.getStructuralFeature(name: featureName),
                      feature is EAttribute {
                // Skip attributes - they're not containment
                continue
            } else {
                // Dynamic features without metamodel - assume non-containment
                continue
            }

            guard let value = await resource.eGet(objectId: dynamicObject.id, feature: featureName) else {
                continue
            }

            if let childId = value as? EUUID {
                if let childObject = await resource.resolve(childId), childObject is DynamicEObject {
                    // This is containment - serialize as child elements
                    children[featureName] = [childObject]
                }
            } else if let childIds = value as? [EUUID] {
                var childObjects: [any EObject] = []
                for childId in childIds {
                    if let childObject = await resource.resolve(childId), childObject is DynamicEObject {
                        childObjects.append(childObject)
                    }
                }
                if !childObjects.isEmpty {
                    children[featureName] = childObjects
                }
            }
        }

        return children
    }

    /// Get cross-references (non-containment references)
    ///
    /// Returns both same-resource references (EUUID) and cross-resource references (ResourceProxy).
    ///
    /// - Parameters:
    ///   - object: The object
    ///   - resource: The Resource
    /// - Returns: Dictionary of feature name to target (EUUID or ResourceProxy)
    private func getCrossReferences(_ object: any EObject, in resource: Resource) async throws -> [String: any EcoreValue] {
        var references: [String: any EcoreValue] = [:]

        guard let dynamicObject = object as? DynamicEObject else {
            return references
        }

        let featureNames = await resource.getFeatureNames(objectId: dynamicObject.id)

        for featureName in featureNames {
            // Use metamodel to determine if this is a cross-reference (non-containment reference)
            if let feature = dynamicObject.eClass.getStructuralFeature(name: featureName),
               let reference = feature as? EReference {
                // Only include non-containment references
                guard !reference.containment else { continue }

                // Skip features that are opposites of containment relationships
                if let oppositeId = reference.opposite,
                   let oppositeRef = dynamicObject.eClass.allReferences.first(where: { $0.id == oppositeId }),
                   oppositeRef.containment {
                    continue
                }

                if let value = await resource.eGet(objectId: dynamicObject.id, feature: featureName) {
                    // Can be EUUID (same-resource) or ResourceProxy (cross-resource)
                    if value is EUUID || value is ResourceProxy {
                        references[featureName] = value
                    }
                }
            }
            // Skip attributes and dynamic features - they're not references
        }

        return references
    }

    /// Collect all namespace declarations needed for an object and its children
    ///
    /// - Parameters:
    ///   - object: The object to analyze
    ///   - resource: The Resource for context
    /// - Returns: Set of namespace declaration strings
    private func collectNamespaces(_ object: any EObject, in resource: Resource) async -> Set<String> {
        var namespaces: Set<String> = []

        // Get object's class name
        let className = getClassName(object)

        // Add this object's namespace using same logic as addNamespaceDeclarations
        if className.hasPrefix("E") {
            // Ecore metamodel object
            namespaces.insert("xmlns:ecore=\"http://www.eclipse.org/emf/2002/Ecore\"")
        } else {
            // Instance object - use generic namespace based on class name
            let prefix = className.lowercased()
            let namespaceDecl = "xmlns:\(prefix)=\"http://swift-modelling.org/test/\(prefix)\""
            namespaces.insert(namespaceDecl)
        }

        // Add XSI namespace if needed (for type declarations)
        namespaces.insert("xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"")

        // For now, just collect namespaces from this object
        // TODO: Add recursive collection from contained objects if needed

        return namespaces
    }

    /// Get element name and namespace prefix
    ///
    /// - Parameters:
    ///   - object: The object
    ///   - className: The class name
    /// - Returns: Tuple of (namespace prefix, element name)
    private func getElementName(_ object: any EObject, className: String) -> (String, String) {
        if className.hasPrefix("E") {
            // Ecore metamodel object
            return ("ecore", "ecore:\(className)")
        } else {
            // Instance object
            let prefix = className.lowercased()
            return (prefix, "\(prefix):\(className)")
        }
    }

    /// Get class name from object
    ///
    /// - Parameter object: The object
    /// - Returns: Class name
    private func getClassName(_ object: any EObject) -> String {
        if let dynamicObject = object as? DynamicEObject {
            return dynamicObject.eClass.name
        }
        return "Object"
    }

    /// Convert a value to string representation
    ///
    /// - Parameter value: The value to convert
    /// - Returns: String representation
    private func convertToString(_ value: any EcoreValue) -> String {
        switch value {
        case let string as String:
            return string
        case let int as Int:
            return "\(int)"
        case let double as Double:
            return "\(double)"
        case let bool as Bool:
            return bool ? "true" : "false"
        case let uuid as EUUID:
            return uuid.uuidString
        default:
            return "\(value)"
        }
    }

    /// Escape XML special characters
    ///
    /// - Parameter string: The string to escape
    /// - Returns: Escaped string
    private func escapeXML(_ string: String) -> String {
        return string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}
