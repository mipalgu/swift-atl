//
//  ATLModelAdapters.swift
//  ATL
//
//  Created by Rene Hexel on 8/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import ECore
import Foundation
import OrderedCollections

/// Adapter for ATL source models to conform to ECore IModel interface.
///
/// Source models provide read-only access to input data for transformations.
/// The adapter bridges ATL's resource-based model representation to the
/// ECore execution engine's IModel interface, enabling seamless integration
/// with navigation and query operations.
///
/// ## Example Usage
///
/// ```swift
/// let sourceAdapter = ATLSourceModel(
///     resource: familiesResource,
///     alias: "Families",
///     metamodel: familiesMetamodel
/// )
///
/// let engine = ECoreExecutionEngine(models: [
///     "Families": sourceAdapter
/// ])
/// ```
public struct ATLSourceModel: IModel {
    /// The underlying resource containing model elements.
    public let resource: Resource

    /// Model alias for namespace identification.
    public let alias: String

    /// Associated metamodel package for type queries.
    public let metamodel: EPackage

    /// Source models are read-only.
    public var isTarget: Bool = false

    /// Reference model (metamodel) for this source model.
    public var referenceModel: IReferenceModel

    /// Type cache for performance optimisation.
    private let typeCache = TypeCache()

    /// Create a new source model adapter.
    ///
    /// - Parameters:
    ///   - resource: Resource containing model elements
    ///   - alias: Model alias for identification
    ///   - metamodel: Associated metamodel package
    public init(resource: Resource, alias: String, metamodel: EPackage) {
        self.resource = resource
        self.alias = alias
        self.metamodel = metamodel
        self.referenceModel = EcoreReferenceModel(rootPackage: metamodel, resource: resource)
    }

    /// Creates a new element of the specified type.
    public func createElement(ofType metaElement: EClass) throws -> any EObject {
        throw ECoreExecutionError.readOnlyModel
    }

    /// Check if an object belongs to this model.
    ///
    /// - Parameter object: Object to check
    /// - Returns: `true` if object belongs to this model
    public func isModelOf(_ object: any EObject) async -> Bool {
        return await resource.contains(id: object.id)
    }

    /// Get all elements of a specific type.
    ///
    /// This method searches through the resource to find all elements
    /// that are instances of the specified EClass or its subtypes.
    ///
    /// - Parameter type: EClass to search for
    /// - Returns: OrderedSet of element UUIDs matching the type
    public func getElementsByType(_ type: EClass) async -> OrderedSet<EUUID> {
        // Check cache first
        let cacheKey = type.name
        if let cached = await typeCache.get(cacheKey) {
            return cached
        }

        let allObjects = await resource.getAllObjects()
        var result = OrderedSet<EUUID>()
        
        for object in allObjects {
            guard let objectClass = object.eClass as? EClass else {
                continue
            }

            if objectClass == type || isSubtype(objectClass, of: type) {
                result.append(object.id)
            }
        }

        // Cache the results
        await typeCache.set(cacheKey, result)
        return result
    }

    /// Get all elements in the model.
    ///
    /// - Returns: OrderedSet of all element UUIDs in the model
    public func getAllElements() async -> OrderedSet<EUUID> {
        let allObjects = await resource.getAllObjects()
        var result = OrderedSet<EUUID>()
        for object in allObjects {
            result.append(object.id)
        }
        return result
    }

    /// Find elements matching a predicate.
    ///
    /// - Parameter predicate: Matching predicate
    /// - Returns: OrderedSet of matching element UUIDs
    public func findElements(matching predicate: @Sendable (any EObject) async -> Bool) async -> OrderedSet<EUUID> {
        let allObjects = await resource.getAllObjects()
        var result = OrderedSet<EUUID>()

        for object in allObjects {
            if await predicate(object) {
                result.append(object.id)
            }
        }

        return result
    }

    /// Check if one EClass is a subtype of another.
    ///
    /// - Parameters:
    ///   - child: Potential subtype
    ///   - parent: Potential supertype
    /// - Returns: `true` if child is a subtype of parent
    private func isSubtype(_ child: EClass, of parent: EClass) -> Bool {
        if child == parent {
            return true
        }

        return child.eSuperTypes.contains { superType in
            isSubtype(superType, of: parent)
        }
    }
}

/// Adapter for ATL target models to conform to ECore IModel interface.
///
/// Target models provide write access for creating transformed output data.
/// The adapter supports element creation, modification, and deletion whilst
/// maintaining consistency with the underlying resource structure.
///
/// ## Example Usage
///
/// ```swift
/// let targetAdapter = ATLTargetModel(
///     resource: personsResource,
///     alias: "Persons",
///     metamodel: personsMetamodel
/// )
///
/// let newPerson = try await targetAdapter.createElement(personClass)
/// ```
public struct ATLTargetModel: IModel {
    /// The underlying resource for storing created elements.
    public let resource: Resource

    /// Model alias for namespace identification.
    public let alias: String

    /// Associated metamodel package for type operations.
    public let metamodel: EPackage

    /// Target models are writable.
    public var isTarget: Bool = true

    /// Reference model (metamodel) for this target model.
    public var referenceModel: IReferenceModel

    /// Type cache for performance optimisation.
    private let typeCache = TypeCache()

    /// Element creation tracking.
    private let createdElements = CreatedElementTracker()

    /// Create a new target model adapter.
    ///
    /// - Parameters:
    ///   - resource: Resource for storing elements
    ///   - alias: Model alias for identification
    ///   - metamodel: Associated metamodel package
    public init(resource: Resource, alias: String, metamodel: EPackage) {
        self.resource = resource
        self.alias = alias
        self.metamodel = metamodel
        self.referenceModel = EcoreReferenceModel(rootPackage: metamodel, resource: resource)
    }

    /// Creates a new element of the specified type.
    public func createElement(ofType metaElement: EClass) throws -> any EObject {
        guard isTarget else {
            throw ECoreExecutionError.readOnlyModel
        }

        guard metamodel.eClassifiers.contains(where: { ($0 as? EClass)?.id == metaElement.id }) else {
            throw ATLModelError.typeNotInMetamodel(metaElement.name, alias)
        }

        let factory = metamodel.eFactoryInstance
        return factory.create(metaElement)
    }

    /// Check if an object belongs to this model.
    ///
    /// - Parameter object: Object to check
    /// - Returns: `true` if object belongs to this model
    public func isModelOf(_ object: any EObject) async -> Bool {
        let inResource = await resource.contains(id: object.id)
        let inCreated = await createdElements.contains(object.id)
        return inResource || inCreated
    }

    /// Get all elements of a specific type.
    ///
    /// - Parameter type: EClass to search for
    /// - Returns: OrderedSet of element UUIDs matching the type
    public func getElementsByType(_ type: EClass) async -> OrderedSet<EUUID> {
        // Check cache first
        let cacheKey = type.name
        if let cached = await typeCache.get(cacheKey) {
            return cached
        }

        let allObjects = await resource.getAllObjects()
        var result = OrderedSet<EUUID>()
        
        for object in allObjects {
            guard let objectClass = object.eClass as? EClass else {
                continue
            }

            if objectClass == type || isSubtype(objectClass, of: type) {
                result.append(object.id)
            }
        }

        // Cache the results
        await typeCache.set(cacheKey, result)
        return result
    }

    /// Create a new element of the specified type.
    ///
    /// - Parameter type: EClass of element to create
    /// - Returns: Created element
    /// - Throws: `ATLModelError` if creation fails
    public func createElement(_ type: EClass) async throws -> any EObject {
        guard metamodel.eClassifiers.contains(where: { ($0 as? EClass)?.id == type.id }) else {
            throw ATLModelError.typeNotInMetamodel(type.name, alias)
        }

        let factory = metamodel.eFactoryInstance
        let element = factory.create(type)

        // Add to resource
        await resource.add(element)

        // Track creation
        await createdElements.add(element.id)

        // Invalidate type cache
        await typeCache.invalidate(type.name)

        return element
    }

    /// Add an existing element to this model.
    ///
    /// - Parameter element: Element to add
    /// - Throws: `ATLModelError` if addition fails
    public func addElement(_ element: any EObject) async throws {
        await resource.add(element)
        await createdElements.add(element.id)

        if let eClass = element.eClass as? EClass {
            await typeCache.invalidate(eClass.name)
        }
    }

    /// Remove an element from this model.
    ///
    /// - Parameter element: Element to remove
    /// - Throws: `ATLModelError` if removal fails
    public func removeElement(_ element: any EObject) async throws {
        await resource.remove(element)
        await createdElements.remove(element.id)

        if let eClass = element.eClass as? EClass {
            await typeCache.invalidate(eClass.name)
        }
    }

    /// Get statistics about element creation.
    ///
    /// - Returns: Statistics about created elements
    public func getCreationStatistics() async -> ElementCreationStatistics {
        let createdCount = await createdElements.count()
        let totalCount = await resource.getAllObjects().count

        return ElementCreationStatistics(
            totalElements: totalCount,
            createdElements: createdCount,
            creationRatio: totalCount > 0 ? Double(createdCount) / Double(totalCount) : 0.0
        )
    }

    /// Clear all created element tracking.
    public func clearCreationTracking() async {
        await createdElements.clear()
        await typeCache.clear()
    }

    /// Check if one EClass is a subtype of another.
    ///
    /// - Parameters:
    ///   - child: Potential subtype
    ///   - parent: Potential supertype
    /// - Returns: `true` if child is a subtype of parent
    private func isSubtype(_ child: EClass, of parent: EClass) -> Bool {
        if child == parent {
            return true
        }

        return child.eSuperTypes.contains { superType in
            isSubtype(superType, of: parent)
        }
    }
}

// MARK: - Supporting Types

/// Thread-safe type cache for performance optimisation.
private actor TypeCache {
    private var cache: [String: OrderedSet<EUUID>] = [:]

    func get(_ key: String) -> OrderedSet<EUUID>? {
        return cache[key]
    }

    func set(_ key: String, _ value: OrderedSet<EUUID>) {
        cache[key] = value
    }

    func invalidate(_ key: String) {
        cache.removeValue(forKey: key)
    }

    func clear() {
        cache.removeAll()
    }
}

/// Thread-safe tracker for created elements.
private actor CreatedElementTracker {
    private var createdElements = OrderedSet<EUUID>()

    func add(_ id: EUUID) {
        createdElements.append(id)
    }

    func remove(_ id: EUUID) {
        createdElements.remove(id)
    }

    func contains(_ id: EUUID) -> Bool {
        return createdElements.contains(id)
    }

    func count() -> Int {
        return createdElements.count
    }

    func clear() {
        createdElements.removeAll()
    }
}

/// Statistics about element creation in target models.
public struct ElementCreationStatistics: Sendable, Equatable {
    /// Total number of elements in the model.
    public let totalElements: Int

    /// Number of elements created during transformation.
    public let createdElements: Int

    /// Ratio of created to total elements (0.0 to 1.0).
    public let creationRatio: Double

    /// Human-readable description of creation statistics.
    public var description: String {
        return "Created \(createdElements) of \(totalElements) elements (\(String(format: "%.1f", creationRatio * 100))%)"
    }
}

/// Errors that can occur during ATL model operations.
public enum ATLModelError: Error, Sendable, Equatable, CustomStringConvertible {
    case typeNotInMetamodel(String, String)
    case elementNotFound(EUUID)
    case readOnlyModel(String)
    case invalidOperation(String)

    public var description: String {
        switch self {
        case .typeNotInMetamodel(let typeName, let modelAlias):
            return "Type '\(typeName)' not found in metamodel for model '\(modelAlias)'"
        case .elementNotFound(let id):
            return "Element with ID '\(id)' not found"
        case .readOnlyModel(let alias):
            return "Cannot modify read-only model '\(alias)'"
        case .invalidOperation(let message):
            return "Invalid model operation: \(message)"
        }
    }
}

/// Factory for creating model adapters from ATL execution context.
public struct ATLModelAdapterFactory {
    /// Create source model adapters from ATL execution context.
    ///
    /// - Parameter context: ATL execution context
    /// - Returns: Dictionary of model adapters keyed by alias
    @MainActor
    public static func createSourceModels(from context: ATLExecutionContext) -> [String: ATLSourceModel] {
        var models: [String: ATLSourceModel] = [:]

        for (alias, resource) in context.sources {
            if let metamodel = context.module.sourceMetamodels[alias] {
                models[alias] = ATLSourceModel(
                    resource: resource,
                    alias: alias,
                    metamodel: metamodel
                )
            }
        }

        return models
    }

    /// Create target model adapters from ATL execution context.
    ///
    /// - Parameter context: ATL execution context
    /// - Returns: Dictionary of model adapters keyed by alias
    @MainActor
    public static func createTargetModels(from context: ATLExecutionContext) -> [String: ATLTargetModel] {
        var models: [String: ATLTargetModel] = [:]

        for (alias, resource) in context.targets {
            if let metamodel = context.module.targetMetamodels[alias] {
                models[alias] = ATLTargetModel(
                    resource: resource,
                    alias: alias,
                    metamodel: metamodel
                )
            }
        }

        return models
    }

    /// Create combined model dictionary for ECore execution engine.
    ///
    /// - Parameter context: ATL execution context
    /// - Returns: Dictionary of IModel instances for execution engine
    @MainActor
    public static func createModelsForEngine(from context: ATLExecutionContext) -> [String: IModel] {
        var models: [String: IModel] = [:]

        // Add source models
        let sourceModels = createSourceModels(from: context)
        for (alias, model) in sourceModels {
            models[alias] = model
        }

        // Add target models
        let targetModels = createTargetModels(from: context)
        for (alias, model) in targetModels {
            models[alias] = model
        }

        return models
    }
}
