//
//  ATLReferenceStorage.swift
//  ATL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

// MARK: - Reserved Names

/// Names with a fixed meaning in the ATL language and its execution model.
///
/// The names are defined once here so that the parser, the expression
/// evaluator and the execution context agree on them.
enum ATLReservedNames {

    /// The implicit receiver of module-level helpers and rules.
    static let thisModule = "thisModule"

    /// The operation that looks up a named target element of a transformed source element.
    static let resolveTemp = "resolveTemp"

    /// The rule modifier marking a lazy rule as memoised.
    static let unique = "unique"

    /// The rule modifier marking a rule as not matching on its own.
    static let abstract = "abstract"

    /// The rule modifier marking a called rule as run at the start of a transformation.
    static let entrypoint = "entrypoint"

    /// The rule modifier marking a called rule as run at the end of a transformation.
    static let endpoint = "endpoint"

    /// The keyword introducing the super rule of a rule.
    static let extends = "extends"

    /// The keyword introducing local variables of a rule.
    static let using = "using"

    /// The keyword introducing an iteration statement.
    static let forLoop = "for"
}

// MARK: - Reference Storage

/// Converts values bound to reference features into the form stored in a model.
///
/// References between elements of one resource are stored as element
/// identifiers. A reference to an element of any other resource, such as a
/// source model element that no rule transformed, is stored as a
/// ``ResourceProxy`` carrying the URI of that resource and an XPath-style
/// fragment locating the element, which the XMI serialiser writes as a
/// cross-document `href`.
///
/// Values bound to multi-valued references are stored as `[EUUID]` when every
/// element lives in the target resource, as `[ResourceProxy]` when every
/// element lives elsewhere, and as an ``EcoreValueArray`` of identifiers and
/// proxies when the two are mixed.
enum ATLReferenceStorage {

    /// Computes the XPath-style fragment locating an element in its resource.
    ///
    /// The first root element is addressed as `/`. Other elements are
    /// addressed by their containment path, for example `//@members.0/@name`.
    /// An element that cannot be located by containment is addressed by its
    /// identifier.
    ///
    /// - Parameters:
    ///   - object: The element to locate
    ///   - resource: The resource containing the element
    /// - Returns: The fragment, without a leading `#`
    static func fragment(for object: any EObject, in resource: Resource) async -> String {
        let roots = await resource.getRootObjects()
        if let first = roots.first, first.id == object.id {
            return "/"
        }
        for root in roots {
            if let path = await path(to: object.id, from: root, prefix: "//", in: resource) {
                return path
            }
        }
        return object.id.uuidString
    }

    /// Converts a value assigned to a feature into its stored form.
    ///
    /// Only values assigned to references are converted: model elements are
    /// replaced by identifiers or proxies, and other values are stored as given.
    ///
    /// - Parameters:
    ///   - value: The evaluated value
    ///   - feature: The feature being assigned
    ///   - resource: The target resource owning the element being assigned
    ///   - context: The execution context holding the sources, targets and trace
    /// - Returns: The value to store
    @MainActor
    static func storedValue(
        for value: (any EcoreValue)?,
        feature: any EStructuralFeature,
        in resource: Resource,
        context: ATLExecutionContext
    ) async -> (any EcoreValue)? {
        guard let reference = feature as? EReference else {
            return value
        }
        guard let value else { return nil }

        var references: [any EcoreValue] = []
        for element in ATLCollectionValues.elements(of: value) {
            if let object = element as? (any EObject) {
                references.append(await referenceValue(for: object, in: resource, context: context))
            } else {
                references.append(element)
            }
        }
        references = unique(references)

        guard reference.isMany else {
            return references.first
        }
        if let identifiers = references as? [EUUID] {
            return identifiers
        }
        if let proxies = references as? [ResourceProxy] {
            return proxies
        }
        return EcoreValueArray(references)
    }

    // MARK: - Private Implementation

    /// Chooses the stored form for one element assigned to a reference.
    ///
    /// - Parameters:
    ///   - object: The element being referenced
    ///   - resource: The target resource owning the referencing element
    ///   - context: The execution context holding the sources, targets and trace
    /// - Returns: The identifier or proxy to store
    @MainActor
    private static func referenceValue(
        for object: any EObject, in resource: Resource, context: ATLExecutionContext
    ) async -> any EcoreValue {
        let referenced: any EObject
        if let targetID = context.defaultTargetID(for: object.id),
            let target = await context.findTargetObject(targetID)
        {
            referenced = target
        } else {
            referenced = object
        }

        if await resource.contains(id: referenced.id) {
            return referenced.id
        }
        if let home = await context.resourceContaining(referenced.id) {
            return ResourceProxy(
                uri: home.uri, fragment: await fragment(for: referenced, in: home))
        }
        return referenced.id
    }

    /// Removes repeated references while preserving order.
    ///
    /// - Parameter values: The references to deduplicate
    /// - Returns: The references with the first occurrence of each kept
    private static func unique(_ values: [any EcoreValue]) -> [any EcoreValue] {
        var seen: Set<AnyHashable> = []
        var result: [any EcoreValue] = []
        for value in values where seen.insert(AnyHashable(value)).inserted {
            result.append(value)
        }
        return result
    }

    /// Finds the containment path from an element to a descendant.
    ///
    /// - Parameters:
    ///   - target: The identifier of the element to find
    ///   - current: The element whose containments are searched
    ///   - prefix: The path accumulated so far
    ///   - resource: The resource containing the elements
    /// - Returns: The path, or `nil` if the element is not contained below `current`
    private static func path(
        to target: EUUID, from current: any EObject, prefix: String, in resource: Resource
    ) async -> String? {
        guard let eClass = current.eClass as? EClass else { return nil }
        for featureName in await resource.getFeatureNames(objectId: current.id) {
            guard let reference = eClass.getStructuralFeature(name: featureName) as? EReference,
                reference.containment,
                let value = await resource.eGet(objectId: current.id, feature: featureName)
            else { continue }
            let children: [EUUID]
            let indexed: Bool
            if let identifier = value as? EUUID {
                children = [identifier]
                indexed = false
            } else if let identifiers = value as? [EUUID] {
                children = identifiers
                indexed = true
            } else {
                continue
            }
            for (index, child) in children.enumerated() {
                let step = indexed ? "@\(featureName).\(index)" : "@\(featureName)"
                if child == target {
                    return prefix + step
                }
                if let childObject = await resource.resolve(child),
                    let found = await path(
                        to: target, from: childObject, prefix: prefix + step + "/", in: resource)
                {
                    return found
                }
            }
        }
        return nil
    }
}
