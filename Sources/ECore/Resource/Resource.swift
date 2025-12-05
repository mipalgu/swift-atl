//
// Resource.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

/// A resource manages model objects and provides EMF-compliant reference resolution.
///
/// Resources serve as containers for model objects, providing identity-based storage
/// and resolution capabilities. They enable cross-reference resolution, URI-based
/// addressing, and proper object lifecycle management following EMF patterns.
///
/// ## Thread Safety
///
/// Resources are thread-safe actors that manage concurrent access to model objects
/// and provide atomic reference resolution operations.
///
/// ## Example
///
/// ```swift
/// let resource = Resource(uri: "http://example.com/mymodel")
///
/// // Add objects to resource
/// let person = DynamicEObject(eClass: personClass)
/// resource.add(person)
///
/// // Resolve references by ID
/// if let resolved = resource.resolve(person.id) {
///     print("Found object: \(resolved)")
/// }
/// ```
@globalActor
public actor Resource {
    /// Global resource actor for thread-safe operations.
    public static let shared = Resource()

    /// The URI identifying this resource.
    ///
    /// Resources are identified by URIs following EMF conventions. The URI
    /// typically indicates the location or logical name of the resource.
    nonisolated public let uri: String

    /// Objects contained in this resource, indexed by their unique identifier.
    ///
    /// All objects within a resource must have unique identifiers. The resource
    /// maintains ownership and provides resolution services.
    private var objects: [EUUID: any EObject]

    /// Root objects that are not contained by other objects in this resource.
    ///
    /// Root objects serve as entry points for model traversal and are typically
    /// the top-level objects that contain the entire model hierarchy.
    /// Maintains insertion order.
    private var rootObjects: [EUUID]

    /// The resource set that owns this resource, if any.
    ///
    /// Resources can be managed independently or as part of a resource set
    /// for cross-resource reference resolution.
    public weak var resourceSet: ResourceSet?

    /// Initialises a new resource with the specified URI.
    ///
    /// - Parameter uri: The URI identifying this resource. Defaults to a generated URI.
    public init(uri: String = "resource://\(UUID().uuidString)") {
        self.uri = uri
        self.objects = [:]
        self.rootObjects = []
    }

    /// Sets the resource set that owns this resource.
    ///
    /// - Parameter resourceSet: The resource set to associate with this resource.
    public func setResourceSet(_ resourceSet: ResourceSet?) {
        self.resourceSet = resourceSet
    }

    // MARK: - Object Management

    /// Registers an object with this resource without adding it as a root object.
    ///
    /// This method adds the object to the resource's object map for ID resolution,
    /// but does not add it to the root objects list. Use this for objects that will
    /// be contained by other objects (e.g., during XMI parsing when parent-child
    /// relationships will be established separately).
    ///
    /// - Parameter object: The object to register with this resource.
    /// - Returns: `true` if the object was registered, `false` if it already exists.
    @discardableResult
    public func register(_ object: any EObject) -> Bool {
        let isNew = objects[object.id] == nil
        objects[object.id] = object
        return isNew
    }

    /// Adds an object to this resource.
    ///
    /// The object becomes owned by this resource and can be resolved by its identifier.
    /// If the object is not contained by another object, it becomes a root object.
    ///
    /// - Parameter object: The object to add to this resource.
    /// - Returns: `true` if the object was added, `false` if it already exists.
    @discardableResult
    public func add(_ object: any EObject) -> Bool {
        let isNew = objects[object.id] == nil

        // Update or add the object
        objects[object.id] = object

        // Check if this should be a root object (not contained by another)
        // This check happens regardless of whether the object is new, because
        // objects might be registered first and then added as roots later
        let isContained = objects.values.contains { container in
            // Check if any object contains this one through containment references
            if let eClass = container.eClass as? EClass {
                return eClass.allReferences.contains { reference in
                    reference.containment && doesObjectContain(container, objectId: object.id, through: reference)
                }
            }
            return false
        }

        if !isContained && !rootObjects.contains(object.id) {
            rootObjects.append(object.id)
        }

        return isNew
    }

    /// Removes an object from this resource.
    ///
    /// - Parameter object: The object to remove from this resource.
    /// - Returns: `true` if the object was removed, `false` if it wasn't found.
    @discardableResult
    public func remove(_ object: any EObject) -> Bool {
        return remove(id: object.id)
    }

    /// Removes an object from this resource by its identifier.
    ///
    /// - Parameter id: The identifier of the object to remove.
    /// - Returns: `true` if the object was removed, `false` if it wasn't found.
    @discardableResult
    public func remove(id: EUUID) -> Bool {
        guard objects.removeValue(forKey: id) != nil else { return false }
        rootObjects.removeAll { $0 == id }
        return true
    }

    /// Removes all objects from this resource.
    public func clear() {
        objects.removeAll()
        rootObjects.removeAll()
    }

    // MARK: - Object Resolution

    /// Resolves an object by its identifier.
    ///
    /// - Parameter id: The unique identifier of the object to resolve.
    /// - Returns: The resolved object, or `nil` if not found in this resource.
    public func resolve(_ id: EUUID) -> (any EObject)? {
        return objects[id]
    }

    /// Resolves an object by its identifier with a specific type.
    ///
    /// - Parameters:
    ///   - id: The unique identifier of the object to resolve.
    ///   - type: The expected type of the resolved object.
    /// - Returns: The resolved object cast to the specified type, or `nil` if not found or wrong type.
    public func resolve<T: EObject>(_ id: EUUID, as type: T.Type) -> T? {
        return objects[id] as? T
    }

    /// Gets all objects contained in this resource.
    ///
    /// - Returns: An array of all objects in this resource.
    public func getAllObjects() -> [any EObject] {
        return Array(objects.values).sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// Gets all root objects in this resource.
    ///
    /// Root objects are those that are not contained by other objects
    /// within the same resource.
    ///
    /// - Returns: An array of root objects.
    public func getRootObjects() -> [any EObject] {
        return rootObjects.compactMap { objects[$0] }
    }

    /// Gets the number of objects in this resource.
    ///
    /// - Returns: The count of objects contained in this resource.
    public func count() -> Int {
        return objects.count
    }

    /// Checks if this resource contains an object with the specified identifier.
    ///
    /// - Parameter id: The identifier to check for.
    /// - Returns: `true` if an object with the identifier exists, `false` otherwise.
    public func contains(id: EUUID) -> Bool {
        return objects[id] != nil
    }

    // MARK: - Reference Resolution

    /// Resolves the opposite reference for a bidirectional reference.
    ///
    /// In EMF, bidirectional references maintain opposites automatically.
    /// This method resolves the opposite reference through ID-based lookup.
    ///
    /// - Parameter reference: The reference whose opposite should be resolved.
    /// - Returns: The opposite reference, or `nil` if not found.
    public func resolveOpposite(_ reference: EReference) -> EReference? {
        guard let oppositeId = reference.opposite else { return nil }

        // Search through all objects to find the reference with the matching ID
        for object in objects.values {
            if let eClass = object.eClass as? EClass {
                for feature in eClass.allReferences {
                    if feature.id == oppositeId {
                        return feature
                    }
                }
            }
        }

        // Check in resource set if this resource is part of one
        // Note: Cross-resource resolution requires async context in ResourceSet
        // Cross-resource resolution would need async context
        return nil
    }

    /// Resolves a reference to its target objects.
    ///
    /// For single-valued references, returns an array with one element.
    /// For multi-valued references, returns all referenced objects.
    ///
    /// - Parameters:
    ///   - reference: The reference to resolve.
    ///   - from: The object containing the reference.
    /// - Returns: An array of resolved target objects.
    public func resolveReference(_ reference: EReference, from object: any EObject) -> [any EObject] {
        guard let value = object.eGet(reference) else { return [] }

        if reference.isMany {
            // Multi-valued reference - extract IDs from array
            // Try casting to array of EUUIDs directly, or convert from Any array
            if let ids = value as? [EUUID] {
                return ids.compactMap { resolve($0) }
            } else if let anyArray = value as? [Any] {
                let ids = anyArray.compactMap { $0 as? EUUID }
                return ids.compactMap { resolve($0) }
            }
        } else {
            // Single-valued reference - direct ID
            if let id = value as? EUUID {
                return resolve(id).map { [$0] } ?? []
            }
        }

        return []
    }

    // MARK: - URI Resolution

    /// Resolves an object by its URI path within this resource.
    ///
    /// EMF uses URI paths to identify objects within resources, typically
    /// following XPath-like syntax for model navigation.
    ///
    /// - Parameter path: The URI path to resolve (e.g., "/@contents.0/@departments.1").
    /// - Returns: The resolved object, or `nil` if the path is invalid.
    public func resolveByPath(_ path: String) -> (any EObject)? {
        // Handle empty path or "/" - return first root
        if path.isEmpty || path == "/" {
            let roots = getRootObjects()
            return roots.first
        }

        // Strip leading slashes for UUID check
        let cleanPath = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        // Handle UUID-based lookup (fragment is just a UUID, possibly with leading slashes)
        if let uuid = UUID(uuidString: cleanPath) {
            return resolve(uuid as EUUID)
        }

        // Handle XPath-style paths
        if path.hasPrefix("/") {
            let components = path.dropFirst().split(separator: "/")

            // If path is just "/", return the first root object
            if components.isEmpty {
                let roots = getRootObjects()
                return roots.first
            }

            // Try to resolve as numeric index into roots
            if let index = Int(components[0]) {
                let roots = getRootObjects()
                guard index < roots.count else { return nil }

                var current: any EObject = roots[index]

                // Navigate through remaining components (feature/index pairs)
                var i = 1
                while i < components.count {
                    let component = String(components[i])

                    // Check if next component exists and is an index
                    if i + 1 < components.count, let featureIndex = Int(components[i + 1]) {
                        // This component is a feature name, next is an index
                        let featureName = component

                        // Cast to DynamicEObject to use string-based eGet
                        guard let dynObj = current as? DynamicEObject else { return nil }

                        // Get the feature value
                        if let featureValue = dynObj.eGet(featureName) as? [EUUID] {
                            guard featureIndex < featureValue.count else { return nil }
                            let nextId = featureValue[featureIndex]
                            guard let nextObj = resolve(nextId) else { return nil }
                            current = nextObj
                        } else {
                            return nil
                        }

                        // Skip both the feature name and index
                        i += 2
                    } else {
                        // Can't navigate further
                        return nil
                    }
                }

                return current
            }

            // Handle @contents.index syntax
            if components[0].hasPrefix("@contents.") {
                let indexStr = String(components[0].dropFirst("@contents.".count))
                guard let index = Int(indexStr) else { return nil }

                let roots = getRootObjects()
                guard index < roots.count else { return nil }

                return roots[index]
            }
        }

        return nil
    }

    // MARK: - Object Modification

    /// Modifies a feature value on an object managed by this resource.
    ///
    /// This method handles bidirectional reference updates automatically.
    /// When setting a reference with an opposite, the opposite side is also updated.
    /// Cross-resource opposite references are coordinated through the ResourceSet.
    ///
    /// - Parameters:
    ///   - objectId: The ID of the object to modify.
    ///   - featureName: The name of the feature to set.
    ///   - value: The new value for the feature.
    /// - Returns: `true` if the modification was successful, `false` otherwise.
    @discardableResult
    public func eSet(objectId: EUUID, feature featureName: String, value: (any EcoreValue)?) async -> Bool {
        guard var object = objects[objectId] as? DynamicEObject else { return false }
        let eClass = object.eClass

        // Check if feature is defined in the eClass
        guard let feature = eClass.getStructuralFeature(name: featureName) else {
            // Feature not defined - use dynamic storage (for XMI parsing without full metamodel)
            object.eSet(featureName, value: value)
            objects[objectId] = object
            return true
        }

        // Handle bidirectional references
        if let reference = feature as? EReference, let oppositeId = reference.opposite {
            // Handle multi-valued references (arrays of UUIDs)
            if reference.isMany {
                // Get old values to unset opposites
                if let oldValues = object.eGet(reference) as? [EUUID] {
                    for oldValueId in oldValues {
                        if var oldTarget = objects[oldValueId] as? DynamicEObject {
                            // Target is in same resource - update directly
                            let targetClass = oldTarget.eClass
                            if let oppositeRef = targetClass.allReferences.first(where: { $0.id == oppositeId }) {
                                if oppositeRef.isMany {
                                    // Remove from array
                                    if var oppositeArray = oldTarget.eGet(oppositeRef) as? [EUUID] {
                                        oppositeArray.removeAll { $0 == objectId }
                                        oldTarget.eSet(oppositeRef, oppositeArray)
                                    }
                                } else {
                                    // Unset single-valued opposite
                                    oldTarget.eSet(oppositeRef, nil)
                                }
                                objects[oldValueId] = oldTarget
                            }
                        } else if let resourceSet = resourceSet {
                            // Target is in different resource - use ResourceSet coordination
                            await resourceSet.updateOpposite(
                                targetId: oldValueId,
                                oppositeRefId: oppositeId,
                                sourceId: objectId,
                                add: false
                            )
                        }
                    }
                }

                // Set the new value
                object.eSet(feature, value)
                objects[objectId] = object

                // Set opposites for new values
                if let newValues = value as? [EUUID] {
                    for newValueId in newValues {
                        if var newTarget = objects[newValueId] as? DynamicEObject {
                            // Target is in same resource - update directly
                            let targetClass = newTarget.eClass
                            if let oppositeRef = targetClass.allReferences.first(where: { $0.id == oppositeId }) {
                                if oppositeRef.isMany {
                                    // Add to array
                                    var oppositeArray = (newTarget.eGet(oppositeRef) as? [EUUID]) ?? []
                                    if !oppositeArray.contains(objectId) {
                                        oppositeArray.append(objectId)
                                    }
                                    newTarget.eSet(oppositeRef, oppositeArray)
                                } else {
                                    // Set single-valued opposite
                                    newTarget.eSet(oppositeRef, objectId)
                                }
                                objects[newValueId] = newTarget
                            }
                        } else if let resourceSet = resourceSet {
                            // Target is in different resource - use ResourceSet coordination
                            await resourceSet.updateOpposite(
                                targetId: newValueId,
                                oppositeRefId: oppositeId,
                                sourceId: objectId,
                                add: true
                            )
                        }
                    }
                }
            } else {
                // Handle single-valued references
                // Get old value to unset opposite if needed
                if let oldValueId = object.eGet(reference) as? EUUID {
                    if var oldTarget = objects[oldValueId] as? DynamicEObject {
                        // Target is in same resource - update directly
                        let targetClass = oldTarget.eClass
                        if let oppositeRef = targetClass.allReferences.first(where: { $0.id == oppositeId }) {
                            if oppositeRef.isMany {
                                // Remove from array
                                if var oppositeArray = oldTarget.eGet(oppositeRef) as? [EUUID] {
                                    oppositeArray.removeAll { $0 == objectId }
                                    oldTarget.eSet(oppositeRef, oppositeArray)
                                }
                            } else {
                                // Unset single-valued opposite
                                oldTarget.eSet(oppositeRef, nil)
                            }
                            objects[oldValueId] = oldTarget
                        }
                    } else if let resourceSet = resourceSet {
                        // Target is in different resource - use ResourceSet coordination
                        await resourceSet.updateOpposite(
                            targetId: oldValueId,
                            oppositeRefId: oppositeId,
                            sourceId: objectId,
                            add: false
                        )
                    }
                }

                // Set the new value
                object.eSet(feature, value)
                objects[objectId] = object

                // Set the opposite if there's a new value
                if let newValueId = value as? EUUID {
                    if var newTarget = objects[newValueId] as? DynamicEObject {
                        // Target is in same resource - update directly
                        let targetClass = newTarget.eClass
                        if let oppositeRef = targetClass.allReferences.first(where: { $0.id == oppositeId }) {
                            if oppositeRef.isMany {
                                // Add to array
                                var oppositeArray = (newTarget.eGet(oppositeRef) as? [EUUID]) ?? []
                                if !oppositeArray.contains(objectId) {
                                    oppositeArray.append(objectId)
                                }
                                newTarget.eSet(oppositeRef, oppositeArray)
                            } else {
                                // Set single-valued opposite
                                newTarget.eSet(oppositeRef, objectId)
                            }
                            objects[newValueId] = newTarget
                        }
                    } else if let resourceSet = resourceSet {
                        // Target is in different resource - use ResourceSet coordination
                        await resourceSet.updateOpposite(
                            targetId: newValueId,
                            oppositeRefId: oppositeId,
                            sourceId: objectId,
                            add: true
                        )
                    }
                }
            }
        } else {
            // Non-bidirectional feature, just set it
            object.eSet(feature, value)
            objects[objectId] = object
        }

        // Handle containment: if this is a containment reference, remove targets from root objects
        if let reference = feature as? EReference, reference.containment {
            if reference.isMany {
                // Multi-valued containment - remove all targets from roots
                if let targetIds = value as? [EUUID] {
                    for targetId in targetIds {
                        rootObjects.removeAll { $0 == targetId }
                    }
                }
            } else {
                // Single-valued containment - remove target from roots
                if let targetId = value as? EUUID {
                    rootObjects.removeAll { $0 == targetId }
                }
            }
        }

        return true
    }

    /// Gets a feature value from an object managed by this resource.
    ///
    /// - Parameters:
    ///   - objectId: The ID of the object to query.
    ///   - featureName: The name of the feature to get.
    /// - Returns: The feature value, or `nil` if not found.
    public func eGet(objectId: EUUID, feature featureName: String) -> (any EcoreValue)? {
        guard let object = objects[objectId] as? DynamicEObject else { return nil }
        return object.eGet(featureName)
    }

    /// Get all feature names for an object
    ///
    /// Returns the names of all features (attributes and references) that have
    /// been set on the specified object.
    ///
    /// - Parameter objectId: The ID of the object to query
    /// - Returns: Array of feature names
    public func getFeatureNames(objectId: EUUID) -> [String] {
        guard let object = objects[objectId] as? DynamicEObject else { return [] }
        return object.getFeatureNames()
    }

    // MARK: - Private Helpers

    /// Checks if a container object contains a target object through a specific reference.
    ///
    /// - Parameters:
    ///   - container: The potential container object.
    ///   - objectId: The ID of the object to check for containment.
    ///   - reference: The containment reference to check.
    /// - Returns: `true` if the container contains the target object.
    private func doesObjectContain(_ container: any EObject, objectId: EUUID, through reference: EReference) -> Bool {
        guard reference.containment else { return false }

        if let value = container.eGet(reference) {
            if reference.isMany {
                if let ids = value as? [EUUID] {
                    return ids.contains(objectId)
                } else if let anyArray = value as? [Any] {
                    let ids = anyArray.compactMap { $0 as? EUUID }
                    return ids.contains(objectId)
                }
            } else {
                if let id = value as? EUUID {
                    return id == objectId
                }
            }
        }

        return false
    }
}

// MARK: - CustomStringConvertible

extension Resource: CustomStringConvertible {
    /// A textual representation of this resource.
    nonisolated public var description: String {
        return "Resource(uri: \"\(uri)\")"
    }
}

// MARK: - Equatable

extension Resource: Equatable {
    /// Compares two resources for equality based on their URI.
    ///
    /// - Parameters:
    ///   - lhs: The first resource to compare.
    ///   - rhs: The second resource to compare.
    /// - Returns: `true` if the resources have the same URI, `false` otherwise.
    nonisolated public static func == (lhs: Resource, rhs: Resource) -> Bool {
        return lhs.uri == rhs.uri
    }
}

// MARK: - Hashable

extension Resource: Hashable {
    /// Hashes the resource based on its URI.
    ///
    /// - Parameter hasher: The hasher to use for combining hash values.
    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(uri)
    }
}
