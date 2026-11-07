//
//  ATLIncrementalRecording.swift
//  ATL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// The reasons why evaluations cannot be propagated incrementally.
///
/// Each reason names a construct outside the fragment of ATL that
/// ``ATLIncrementalTransformation`` propagates change by change; a transformation
/// that uses one is kept up to date by re-executing it instead.
public enum ATLIncrementalHazard {
    /// An expression read an element of a target model.
    public static let targetRead = "an expression reads elements of a target model"

    /// An expression created or changed model elements.
    public static let modelChange = "an expression creates or changes model elements"

    /// A binding could not be evaluated when its rule was applied and was deferred.
    public static let deferredBinding = "a binding was deferred until all rules had been applied"

    /// The module refines its source models in place.
    public static let refining = "the module refines its source models"

    /// The module declares called, lazy or unique lazy rules.
    public static let calledRules = "the module declares called or lazy rules"

    /// A matched rule has an imperative `do` section.
    public static let imperativeSection = "a matched rule has a 'do' section"

    /// A binding sets a reference that has an opposite.
    public static let oppositeReference = "a binding sets a reference that has an opposite"

    /// The module is a query rather than a transformation.
    public static let query = "the module is a query"

    /// A change could not be summarised precisely, such as the rebinding of an element to
    /// another class.
    public static let unboundedChange = "a change affects the whole model"
}

extension ATLExecutionContext {

    /// Notes that the evaluations being recorded cannot be propagated incrementally.
    ///
    /// Only the first reason is kept. Outside a recording, nothing is noted.
    ///
    /// - Parameter reason: The reason, one of the constants of ``ATLIncrementalHazard``.
    func noteIncrementalHazard(_ reason: String) {
        guard dependencyRecorder.isRecording, incrementalHazard == nil else { return }
        incrementalHazard = reason
    }

    /// Records the read of a feature, or of a containment property, of a source element.
    ///
    /// - Parameters:
    ///   - property: The name of the feature or containment property.
    ///   - object: The element read from.
    func recordRead(of property: String, from object: any EObject) {
        let feature = (object.eClass as? EClass)?.getStructuralFeature(name: property)
        if feature == nil, let navigation = EObjectNavigationProperty(rawValue: property) {
            switch navigation {
            case .eContainer, .eContainingFeature:
                dependencyRecorder.recordContainer(of: object.id)
            case .eContents:
                dependencyRecorder.recordObject(object.id)
            case .eAllContents:
                dependencyRecorder.recordObject(object.id)
                dependencyRecorder.recordContainmentStructure()
            }
            return
        }
        dependencyRecorder.recordFeature(property, of: object.id)
        if let attribute = feature as? EAttribute, attribute.derived || attribute.volatile {
            dependencyRecorder.recordUnbounded()
        } else if let reference = feature as? EReference {
            if reference.derived || reference.volatile {
                dependencyRecorder.recordUnbounded()
            } else if reference.transient {
                dependencyRecorder.recordContainer(of: object.id)
            }
        }
    }

    /// Records the enumeration of the instances of a class.
    ///
    /// Instances are listed in document order, so the enumeration also depends on the
    /// containment structure. Enumerating the instances of a target model cannot be
    /// propagated incrementally.
    ///
    /// - Parameters:
    ///   - className: The name of the class.
    ///   - isSource: Whether the instances are those of a source model.
    func recordExtent(_ className: String, isSource: Bool) {
        guard isSource else {
            noteIncrementalHazard(ATLIncrementalHazard.targetRead)
            return
        }
        dependencyRecorder.recordExtent(className)
        dependencyRecorder.recordContainmentStructure()
    }
}

/// What a transformation run read and created, recorded for incremental propagation.
///
/// The virtual machine fills a journal while one is installed; without one, it records
/// nothing.
struct ATLIncrementalJournal {
    /// The evaluation of the guards of a rule for a tuple of source elements.
    struct GuardRecord {
        /// The name of the rule.
        let ruleName: String
        /// The source elements, in source pattern order.
        let sourceIDs: [EUUID]
        /// Whether the guards held.
        let holds: Bool
        /// What evaluating the guards read.
        let dependencies: ModelDependencies
    }

    /// A match whose target elements were created.
    struct MatchRecord {
        /// The name of the rule.
        let ruleName: String
        /// The source elements, in source pattern order.
        let sourceIDs: [EUUID]
        /// The source and `using` variables in scope for the bindings.
        let variables: [(name: String, value: (any EcoreValue)?)]
        /// The created target elements, in target pattern order.
        let targetIDs: [EUUID]
        /// What evaluating the `using` variables read.
        let dependencies: ModelDependencies
    }

    /// The application of a binding to a target element.
    struct BindingRecord {
        /// The target element.
        let targetID: EUUID
        /// The position of the binding among the bindings of its target pattern.
        let ordinal: Int
        /// What evaluating and storing the binding read.
        let dependencies: ModelDependencies
    }

    /// The guard evaluations, in order.
    var guards: [GuardRecord] = []

    /// The matches, in order of creation.
    var matches: [MatchRecord] = []

    /// The binding applications, in order.
    var bindings: [BindingRecord] = []
}
