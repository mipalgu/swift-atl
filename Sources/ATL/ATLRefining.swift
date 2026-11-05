//
//  ATLRefining.swift
//  ATL
//
//  Created by Rene Hexel on 5/11/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// The model handling of refining mode.
///
/// In refining mode each target model starts as a copy of the source model in the
/// same position of the module header. These functions pair the models, check that
/// they can be paired, make the copies, and delete the copies that rules drop.
enum ATLRefining {

    /// A target model together with the source model it refines.
    struct ModelPair: Sendable, Equatable {
        /// The name of the source model.
        let source: String

        /// The name of the target model that starts as a copy of the source model.
        let target: String
    }

    /// Pairs the target models of a module with its source models in declaration order.
    ///
    /// - Parameter module: The module whose models are paired.
    /// - Returns: One pair for each source model, in declaration order.
    /// - Throws: ``ATLExecutionError/invalidOperation(_:)`` when the module declares a
    ///   different number of target and source models, or a target model whose
    ///   metamodel differs from that of the source model it is paired with.
    static func modelPairs(of module: ATLModule) throws -> [ModelPair] {
        let sources = Array(module.sourceMetamodels.keys)
        let targets = Array(module.targetMetamodels.keys)
        guard sources.count == targets.count else {
            throw ATLExecutionError.invalidOperation(
                "Refining mode pairs each target model with a source model, but module '\(module.name)' "
                    + "declares \(targets.count) target model(s) and \(sources.count) source model(s)")
        }
        return try zip(sources, targets).map { source, target in
            let sourceMetamodel = metamodelName(of: source, in: module, sources: true)
            let targetMetamodel = metamodelName(of: target, in: module, sources: false)
            guard sourceMetamodel == targetMetamodel else {
                throw ATLExecutionError.invalidOperation(
                    "Refining mode requires target model '\(target)' to conform to the metamodel of "
                        + "source model '\(source)', but '\(target)' conforms to '\(targetMetamodel)' "
                        + "and '\(source)' to '\(sourceMetamodel)'")
            }
            return ModelPair(source: source, target: target)
        }
    }

    /// The model elements of a source model, checked to be copyable.
    ///
    /// - Parameters:
    ///   - resource: The source model.
    ///   - model: The name of the source model, for error messages.
    /// - Returns: Every element of the model, in document order.
    /// - Throws: ``ATLExecutionError/unsupportedOperation(_:)`` when the model holds an
    ///   element that is not an instance of a dynamic class, such as an element of an
    ///   Ecore metamodel.
    static func elements(of resource: Resource, model: String) async throws -> [DynamicEObject] {
        var elements: [DynamicEObject] = []
        for object in await resource.getAllObjectsIncludingContents() {
            guard let element = object as? DynamicEObject else {
                let className =
                    (object.eClass as? any ENamedElement)?.name ?? String(describing: type(of: object))
                throw ATLExecutionError.unsupportedOperation(
                    "Refining mode copies instances of dynamic classes only, but source model '\(model)' "
                        + "holds an element of class '\(className)'")
            }
            elements.append(element)
        }
        return elements
    }

    /// Copies model elements, pointing references between copied elements to the copies.
    ///
    /// Each copy has the class of its original and the values of every feature that is
    /// set on the original. A reference to an element that has a copy refers to that
    /// copy; any other reference is kept as it is.
    ///
    /// - Parameters:
    ///   - elements: The elements to copy.
    ///   - copies: The identifier of each copy, indexed by the identifier of its original.
    /// - Returns: The copies, in the order of `elements`.
    static func copies(of elements: [DynamicEObject], identifiers copies: [EUUID: EUUID]) -> [DynamicEObject] {
        elements.map { element in
            var copy = DynamicEObject(id: copies[element.id] ?? EUUID(), eClass: element.eClass)
            for name in element.getFeatureNames() {
                copy.eSet(name, value: element.eGet(name).map { redirect($0, to: copies) })
            }
            return copy
        }
    }

    /// Redirects the element identifiers in a value to the copies of those elements.
    ///
    /// - Parameters:
    ///   - value: A stored feature value.
    ///   - copies: The identifier of each copy, indexed by the identifier of its original.
    /// - Returns: The value with every copied identifier replaced by that of the copy.
    private static func redirect(_ value: any EcoreValue, to copies: [EUUID: EUUID]) -> any EcoreValue {
        switch value {
        case let identifier as EUUID:
            return copies[identifier] ?? identifier
        case let identifiers as [EUUID]:
            return identifiers.map { copies[$0] ?? $0 }
        case let array as EcoreValueArray:
            return EcoreValueArray(array.values.map { redirect($0, to: copies) }, kind: array.kind)
        default:
            return value
        }
    }

    /// Deletes dropped elements from the target models, together with their contents.
    ///
    /// Each dropped element is removed with every element that it contains, directly or
    /// indirectly, at the time of the call. An element that a rule has placed in a
    /// containment reference of an element that remains has moved there, so it is kept
    /// with its own contents even though the dropped element still lists it. Every
    /// remaining element of the target models loses its references to the removed
    /// elements: a single-valued reference is unset, and a removed element is taken out
    /// of the value of a many-valued one.
    ///
    /// - Parameters:
    ///   - dropped: The identifiers of the dropped elements; repeated identifiers and
    ///     identifiers that no target model holds are ignored.
    ///   - targets: The target models.
    static func delete(_ dropped: [EUUID], from targets: [Resource]) async {
        var containers: [EUUID: Set<EUUID>] = [:]
        var held = Set<EUUID>()
        for target in targets {
            for object in await target.getAllObjects() {
                held.insert(object.id)
                for child in await target.eContents(of: object) {
                    containers[child.id, default: []].insert(object.id)
                }
            }
        }
        var removed = Set(dropped.filter(held.contains))
        guard !removed.isEmpty else { return }
        var growing = true
        while growing {
            growing = false
            for (child, holders) in containers where !removed.contains(child) && holders.isSubset(of: removed) {
                removed.insert(child)
                growing = true
            }
        }
        for target in targets {
            for object in await target.getAllObjects() where !removed.contains(object.id) {
                guard var element = object as? DynamicEObject else { continue }
                var changed = false
                for name in element.getFeatureNames() {
                    guard let value = element.eGet(name) else { continue }
                    switch pruned(value, removing: removed) {
                    case .unchanged:
                        continue
                    case .unset:
                        element.eUnset(name)
                    case .replaced(let remaining):
                        element.eSet(name, value: remaining)
                    }
                    changed = true
                }
                if changed {
                    await target.register(element)
                }
            }
            for id in removed {
                await target.remove(id: id)
            }
        }
    }

    /// What becomes of a stored feature value when elements are deleted.
    private enum PrunedValue {
        /// The value refers to no deleted element.
        case unchanged

        /// The value is a reference to a deleted element, so the feature is unset.
        case unset

        /// The value is a collection that held deleted elements, without them.
        case replaced(any EcoreValue)
    }

    /// Removes the references to deleted elements from a stored feature value.
    ///
    /// - Parameters:
    ///   - value: A stored feature value.
    ///   - removed: The identifiers of the deleted elements.
    /// - Returns: How the value changes.
    private static func pruned(_ value: any EcoreValue, removing removed: Set<EUUID>) -> PrunedValue {
        switch value {
        case let identifier as EUUID:
            return removed.contains(identifier) ? .unset : .unchanged
        case let identifiers as [EUUID]:
            let remaining = identifiers.filter { !removed.contains($0) }
            return remaining.count == identifiers.count ? .unchanged : .replaced(remaining)
        case let array as EcoreValueArray:
            let remaining = array.values.filter { !(($0 as? EUUID).map(removed.contains) ?? false) }
            return remaining.count == array.values.count
                ? .unchanged : .replaced(EcoreValueArray(remaining, kind: array.kind))
        default:
            return .unchanged
        }
    }

    /// The name of the metamodel a model conforms to, as declared in the module header.
    ///
    /// - Parameters:
    ///   - model: The model name.
    ///   - module: The module declaring the model.
    ///   - sources: Whether the model is a source model.
    /// - Returns: The declared metamodel name, or the name of the bound package.
    private static func metamodelName(of model: String, in module: ATLModule, sources: Bool) -> String {
        if let declared = module.declaredMetamodelNames[model] { return declared }
        let package = sources ? module.sourceMetamodels[model] : module.targetMetamodels[model]
        return package?.name ?? model
    }
}
