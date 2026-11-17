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

    /// The pseudo-feature under which incremental execution records that a computation
    /// read the trace of a source element.
    ///
    /// The name cannot be the name of a structural feature, so it never collides with
    /// a read of the model.
    static let traceDependency = "#trace"

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
/// identifiers, as are references to elements of another resource in the same
/// resource set, which the serialiser locates itself. A reference to an
/// element of any other resource, such as a source model element that no rule
/// transformed, is stored as a
/// [`ResourceProxy`](https://mipalgu.github.io/swift-ecore/documentation/ecore/resourceproxy/) carrying the URI of that resource and an XPath-style
/// fragment locating the element, which the XMI serialiser writes as a
/// cross-document `href`.
///
/// Values bound to multi-valued references are stored as `[EUUID]` when every
/// element lives in the target resource, as `[ResourceProxy]` when every
/// element lives elsewhere, and as an [`EcoreValueArray`](https://mipalgu.github.io/swift-ecore/documentation/emfbase/ecorevaluearray/) of identifiers and
/// proxies when the two are mixed.
///
/// A containment reference holds only elements of target models: a source element
/// that no matched rule transforms is left out of it, with a warning.
enum ATLReferenceStorage {

    /// Computes the XPath-style fragment locating an element in its resource, as the
    /// Eclipse Modeling Framework writes it.
    ///
    /// The only root element of a resource is addressed as `/` and the other elements by
    /// their containment path below it, for example `//@members.0/@name`. Root `n` of a
    /// resource with several roots is addressed as `/n`, and the elements it contains by
    /// their path below it, for example `/1/@members.0`. Elements of Ecore models, whether
    /// native or dynamic, are addressed by the names along their containment path, as EMF
    /// does, for example `//Book/title`, or `/1/Book` below root `1` of a resource with
    /// several roots. An element that cannot be located is addressed by its identifier.
    ///
    /// - Parameters:
    ///   - object: The element to locate
    ///   - resource: The resource containing the element
    /// - Returns: The fragment, without a leading `#`
    static func fragment(for object: any EObject, in resource: Resource) async -> String {
        let roots = await resource.getRootObjects()
        if let position = roots.firstIndex(where: { $0.id == object.id }) {
            return PositionalFragments.rootSegment(position, rootCount: roots.count)
        }
        let navigator = FragmentNavigator(resource: resource)
        if let named = await navigator.fragment(for: object.id) {
            return await rootedFragment(named, of: object, among: roots, navigator: navigator)
        }
        return await PositionalFragments.fragment(for: object.id, in: resource) ?? object.id.uuidString
    }

    /// Places a name-based fragment below the root that contains an element.
    ///
    /// In a resource with several roots, the path `//Book` names the first element called
    /// `Book` below any root, whereas EMF writes the path below the root that contains the
    /// element, such as `/1/Book`.
    ///
    /// - Parameters:
    ///   - named: The name-based fragment of the element, starting with `//`.
    ///   - object: The element.
    ///   - roots: The roots of the resource.
    ///   - navigator: The navigator of the resource.
    /// - Returns: The fragment below the root that contains the element, or `named` for a
    ///   resource with one root or when no root is found.
    private static func rootedFragment(
        _ named: String, of object: any EObject, among roots: [any EObject], navigator: FragmentNavigator
    ) async -> String {
        let prefix = CrossReferenceSyntax.fragmentPathPrefix
        guard roots.count > 1, named.hasPrefix(prefix) else { return named }
        let path = named.dropFirst(prefix.count)
        for position in roots.indices {
            let candidate = PositionalFragments.rootSegment(position, rootCount: roots.count)
                + String(CrossReferenceSyntax.segmentSeparator) + path
            if await navigator.resolve(candidate)?.id == object.id { return candidate }
        }
        return named
    }

    /// Converts a value assigned to a feature into its stored form.
    ///
    /// Only values assigned to references are converted: model elements are
    /// replaced by identifiers or proxies, and other values are stored as given.
    /// A source element that no matched rule transforms is left out of the value of
    /// a containment reference, as Eclipse ATL leaves it out, because an element of
    /// a target model cannot contain an element of a source model; the run reports a
    /// warning naming the element, the reference and the class. A tuple of source
    /// elements is replaced by the default target element of the match of a rule with
    /// several source elements that binds each part of the tuple to the variable of the
    /// same name, as in Eclipse ATL.
    ///
    /// - Parameters:
    ///   - value: The evaluated value
    ///   - feature: The feature being assigned
    ///   - owner: The class of the element being assigned
    ///   - resource: The target resource owning the element being assigned
    ///   - context: The execution context holding the sources, targets and trace
    /// - Returns: The value to store
    /// - Throws: ``ATLExecutionError/typeError(_:)`` when a tuple bound to the reference
    ///   identifies no such match.
    @MainActor
    static func storedValue(
        for value: (any EcoreValue)?,
        feature: any EStructuralFeature,
        of owner: EClass,
        in resource: Resource,
        context: ATLExecutionContext
    ) async throws -> (any EcoreValue)? {
        guard let reference = feature as? EReference else {
            return value
        }
        guard let value else { return nil }

        var references: [any EcoreValue] = []
        for element in ATLCollectionValues.elements(of: value) {
            if let tuple = element as? ATLTupleValue {
                guard let targetID = context.matchedLink(binding: tuple)?.targetElements.first,
                    let target = await context.findTargetObject(targetID)
                else {
                    throw ATLExecutionError.typeError(
                        ATLExecutionMessage.unresolvedTuple(
                            ATLValueText.render(tuple), reference: reference.name, className: owner.name))
                }
                references.append(await referenceValue(for: target, in: resource, context: context))
            } else if let object = element as? (any EObject) {
                if reference.containment, await isUntransformedSourceElement(object, context: context) {
                    context.reportWarning(
                        ATLExecutionMessage.untransformedContainedElement(
                            element: ATLValueText.render(object), reference: reference.name,
                            className: owner.name))
                    continue
                }
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

    /// Whether an element belongs to a source model and no matched rule transforms it.
    ///
    /// - Parameters:
    ///   - object: The element.
    ///   - context: The execution context holding the sources and the trace.
    /// - Returns: `true` for a source element without a default target element.
    @MainActor
    private static func isUntransformedSourceElement(
        _ object: any EObject, context: ATLExecutionContext
    ) async -> Bool {
        guard context.defaultTargetID(for: object.id) == nil else { return false }
        return await context.isSourceElement(object.id)
    }

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
        let recording = context.dependencyRecorder.isRecording
        if recording {
            context.dependencyRecorder.recordFeature(ATLReservedNames.traceDependency, of: object.id)
        }
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
            if let sharedSet = await resource.resourceSet,
                await home.resourceSet === sharedSet
            {
                return referenced.id
            }
            if recording {
                // The fragment locates the element by its position or by the names of the
                // elements containing it
                context.dependencyRecorder.recordContainmentStructure()
                context.dependencyRecorder.recordUnbounded()
            }
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
}
