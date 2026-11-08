//
//  ATLIncrementalTransformation.swift
//  ATL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
public import ECore
public import EMFBase
import Foundation
public import OrderedCollections

/// How an ``ATLIncrementalTransformation`` keeps its target models up to date.
public enum ATLIncrementalStrategy: Sendable, Equatable {
    /// Changes of the source models are propagated match by match and binding by binding.
    case propagation

    /// The module uses constructs outside the fragment that can be propagated, so each
    /// update executes the whole transformation again.
    ///
    /// The reason is one of the constants of ``ATLIncrementalHazard``.
    case reexecution(reason: String)
}

/// When an ``ATLIncrementalTransformation`` evaluates the bindings that changes affect.
public enum ATLBindingPropagation: Sendable, Equatable {
    /// Affected bindings are evaluated during each update, so that the target models are
    /// up to date when the update returns.
    case immediate

    /// Affected bindings are only marked as stale during an update, and evaluated when their
    /// value is requested with ``ATLIncrementalTransformation/value(of:feature:)`` or when
    /// ``ATLIncrementalTransformation/materialise()`` is called, in the manner of the lazy
    /// bindings of ReactiveATL. Until then, the target models hold the earlier values of
    /// stale bindings.
    case onDemand
}

/// The size of the dependency records that an ``ATLIncrementalTransformation`` keeps.
///
/// Each count of computations is the number of records of that kind, and each count of
/// entries is the number of model parts that those records name together (see
/// ``ModelDependencies/count``).
public struct ATLIncrementalDependencyStatistics: Sendable, Equatable {
    /// The number of source element tuples whose guard outcomes are kept.
    public let candidates: Int

    /// The number of matches.
    public let matches: Int

    /// The number of guard evaluations with recorded dependencies.
    public let guards: Int

    /// The number of model parts that the guard records name.
    public let guardEntries: Int

    /// The number of matches whose `using` variables have recorded dependencies.
    public let locals: Int

    /// The number of model parts that the records of `using` variables name.
    public let localEntries: Int

    /// The number of bindings with recorded dependencies.
    public let bindings: Int

    /// The number of model parts that the binding records name.
    public let bindingEntries: Int

    /// The number of cached attribute helper values with recorded dependencies.
    public let helpers: Int

    /// The number of model parts that the helper records name.
    public let helperEntries: Int

    /// The number of model parts named by all records together.
    public var totalEntries: Int { guardEntries + localEntries + bindingEntries + helperEntries }
}

/// What one update of an ``ATLIncrementalTransformation`` did.
public struct ATLIncrementalUpdate: Sendable, Equatable {
    /// The number of source changes processed.
    public let changeCount: Int

    /// Whether the transformation was executed again as a whole.
    public let reexecuted: Bool

    /// Why the transformation was executed again, if it was.
    public let reason: String?

    /// The number of rule guards evaluated for source element tuples.
    public let guardsEvaluated: Int

    /// The number of matches whose target elements were created.
    public let matchesAdded: Int

    /// The number of matches whose target elements were deleted.
    public let matchesRemoved: Int

    /// The number of evaluations of `using` variables of existing matches.
    public let localsEvaluated: Int

    /// The number of bindings evaluated and assigned.
    public let bindingsEvaluated: Int

    /// The number of bindings marked as stale for on-demand evaluation.
    public let bindingsDeferred: Int

    /// Creates an update report.
    ///
    /// - Parameters:
    ///   - changeCount: The number of source changes processed.
    ///   - reexecuted: Whether the transformation was executed again as a whole.
    ///   - reason: Why the transformation was executed again.
    ///   - guardsEvaluated: The number of guard evaluations.
    ///   - matchesAdded: The number of matches added.
    ///   - matchesRemoved: The number of matches removed.
    ///   - localsEvaluated: The number of evaluations of `using` variables.
    ///   - bindingsEvaluated: The number of bindings evaluated.
    ///   - bindingsDeferred: The number of bindings marked as stale.
    public init(
        changeCount: Int, reexecuted: Bool = false, reason: String? = nil, guardsEvaluated: Int = 0,
        matchesAdded: Int = 0, matchesRemoved: Int = 0, localsEvaluated: Int = 0,
        bindingsEvaluated: Int = 0, bindingsDeferred: Int = 0
    ) {
        self.changeCount = changeCount
        self.reexecuted = reexecuted
        self.reason = reason
        self.guardsEvaluated = guardsEvaluated
        self.matchesAdded = matchesAdded
        self.matchesRemoved = matchesRemoved
        self.localsEvaluated = localsEvaluated
        self.bindingsEvaluated = bindingsEvaluated
        self.bindingsDeferred = bindingsDeferred
    }
}

/// An ATL transformation whose target models are kept up to date as its source models change.
///
/// An incremental transformation first executes its module as ``ATLVirtualMachine`` does,
/// producing the same target models, while recording what each rule guard, `using`
/// variable and binding reads from the source models and the trace (see
/// ``ModelDependencies``). It then watches the source models for changes made through the
/// editing operations of ``Resource`` (see ``Resource/addChangeObserver(_:)``). Each call
/// of ``update()`` propagates the changes collected since the previous one, following
/// incremental ATL ([Jouault and Tisi](https://doi.org/10.1007/978-3-642-13688-7_9)), YAMTL
/// ([Boronat](https://doi.org/10.1007/s10009-020-00583-y)) and the dependency tracking of
/// incremental query engines:
///
/// 1. Guards whose dependencies changed are evaluated again, and the rules whose source
///    element types gained or lost instances are matched again, evaluating the guards of
///    new source element tuples only.
/// 2. The target elements of matches that no longer hold are deleted, those of new matches
///    are created, and the trace is brought up to date.
/// 3. The `using` variables and bindings whose dependencies changed, including those that
///    resolved a source element whose trace changed, are evaluated again and assigned.
///
/// After every update the target models are exactly as a fresh execution of the module over
/// the changed source models would leave them, including the order of root elements and of
/// feature values, so that their serialised forms are identical.
///
/// A module that uses constructs outside the fragment that can be propagated (refining
/// mode, called and lazy rules, `do` sections, bindings of references with opposites, or
/// expressions that read target elements or change models) is kept up to date by executing
/// it again on each update; ``strategy`` tells which applies. Changes that cannot be
/// summarised precisely, such as rebinding an element to another class, also cause a
/// re-execution. The target models belong to the transformation: a re-execution clears
/// them before executing the module again.
///
/// Incremental execution is opt-in: ``ATLVirtualMachine`` behaves exactly as before.
///
/// ```swift
/// let transformation = ATLIncrementalTransformation(module: module, options: .standard)
/// try await transformation.execute(sources: ["IN": families], targets: ["OUT": persons])
/// try await families.eSetWithChanges(objectId: member, feature: "firstName", value: "Jo")
/// let report = try await transformation.update()
/// ```
@MainActor
public final class ATLIncrementalTransformation {

    // MARK: - Types

    /// A match, identified by its rule and its source elements.
    struct MatchKey: Hashable, Sendable {
        /// The position of the rule among the effective matched rules.
        let rule: Int
        /// The source elements, in source pattern order.
        let sources: [EUUID]
    }

    /// A binding of a match.
    struct BindingKey: Hashable, Sendable {
        /// The match.
        let match: MatchKey
        /// The position of the target pattern.
        let pattern: Int
        /// The position of the binding among the bindings of the target pattern.
        let binding: Int
    }

    /// The state of a match.
    struct MatchState {
        /// The source and `using` variables in scope for the bindings.
        var variables: [(name: String, value: (any EcoreValue)?)]
        /// The target elements, in target pattern order.
        let targetIDs: [EUUID]
    }

    /// The reason to abandon a propagation and execute the module again.
    private struct Fallback: Error {
        let reason: String
    }

    // MARK: - Properties

    /// The module that the transformation executes.
    public let module: ATLModule

    /// The options that select how expressions are evaluated.
    public let options: ATLOptions

    /// How navigation reads features that the models leave unset.
    public let unsetFeatureReads: UnsetFeatureReads

    /// When bindings affected by changes are evaluated.
    public let bindingPropagation: ATLBindingPropagation

    /// How the transformation keeps its target models up to date.
    ///
    /// The strategy is decided from the module before the first execution, and becomes
    /// ``ATLIncrementalStrategy/reexecution(reason:)`` if an execution finds that an
    /// expression reads target elements, changes models, or has a binding deferred.
    public private(set) var strategy: ATLIncrementalStrategy

    /// Where the `writeTo` and `writeToWithCharset` string operations may write files.
    public var fileOutput: ATLFileOutputPolicy = .disabled {
        didSet { machine.fileOutput = fileOutput }
    }

    /// The report of the latest update, if any.
    public private(set) var lastUpdate: ATLIncrementalUpdate?

    /// Whether the transformation has been executed.
    public private(set) var hasExecuted = false

    /// The helpers implemented in Swift that the transformation can call.
    private let nativeHelpers: [ATLNativeHelper]

    /// The virtual machine of the latest execution.
    private var machine: ATLVirtualMachine

    /// The source models, by model name.
    private var sources: OrderedDictionary<String, Resource> = [:]

    /// The target models, by model name.
    private var targets: OrderedDictionary<String, Resource> = [:]

    /// The values of the module parameters.
    private var parameters: [String: any EcoreValue] = [:]

    /// The source changes reported and not yet propagated.
    private let queue = ResourceChangeQueue()

    /// The registrations with the source models.
    private var observations: [(resource: Resource, observation: ResourceChangeObservation)] = []

    /// The effective matched rules, in matching order.
    private var rules: [ATLEffectiveMatchedRule] = []

    /// The position of each effective rule, by rule name.
    private var ruleIndex: [String: Int] = [:]

    /// The source model and class of each source pattern, per rule.
    private var patternClasses: [[(alias: String, eClass: EClass)]] = []

    /// The names of the classes of the source patterns, per rule.
    private var patternClassNames: [Set<String>] = []

    /// The source element tuples of each rule in matching order, and whether their guards hold.
    private var candidates: [OrderedDictionary<[EUUID], Bool>] = []

    /// What the guards of each tuple read.
    private var guardIndex = ModelDependencyIndex<MatchKey>()

    /// The matches, in the order in which an execution creates them.
    private var matches: OrderedDictionary<MatchKey, MatchState> = [:]

    /// What the `using` variables of each match read.
    private var localsIndex = ModelDependencyIndex<MatchKey>()

    /// What each binding read.
    private var bindingIndex = ModelDependencyIndex<BindingKey>()

    /// What each cached attribute helper value read.
    private var helperIndex = ModelDependencyIndex<ATLAttributeCacheKey>()

    /// The bindings awaiting on-demand evaluation.
    private var staleBindings: Set<BindingKey> = []

    /// The target elements, with the match and target pattern that created each.
    private var targetOwners: [EUUID: (match: MatchKey, pattern: Int)] = [:]

    /// Elements that may have lost their container and so become root elements.
    private var orphanCandidates: Set<EUUID> = []

    /// Target elements whose features may have to be put back in binding order.
    private var reorderCandidates: Set<EUUID> = []

    /// Whether the root elements of the target models may be out of order.
    private var rootsNeedOrdering = false

    // MARK: - Initialisation

    /// Creates an incremental transformation for a module.
    ///
    /// - Parameters:
    ///   - module: The ATL module to execute.
    ///   - options: The options that select how expressions are evaluated, such as
    ///     ``ATLOptions/standard``.
    ///   - unsetFeatureReads: How navigation reads a feature that the model leaves unset.
    ///   - nativeHelpers: Helpers implemented in Swift that the transformation can call.
    ///     Expressions that call them are evaluated again after every change.
    ///   - bindingPropagation: When bindings affected by changes are evaluated;
    ///     ``ATLBindingPropagation/immediate`` by default.
    public init(
        module: ATLModule, options: ATLOptions,
        unsetFeatureReads: UnsetFeatureReads = .defaults,
        nativeHelpers: [ATLNativeHelper] = [],
        bindingPropagation: ATLBindingPropagation = .immediate
    ) {
        self.module = module
        self.options = options
        self.unsetFeatureReads = unsetFeatureReads
        self.nativeHelpers = nativeHelpers
        self.bindingPropagation = bindingPropagation
        self.machine = ATLVirtualMachine(
            module: module, options: options, unsetFeatureReads: unsetFeatureReads,
            nativeHelpers: nativeHelpers)
        self.strategy = Self.staticStrategy(of: module)
    }

    // MARK: - Public interface

    /// The number of source changes collected and not yet propagated.
    public var pendingChangeCount: Int { queue.count }

    /// The number of matches of the matched rules.
    public var matchCount: Int { matches.count }

    /// The number of bindings awaiting on-demand evaluation.
    public var staleBindingCount: Int { staleBindings.count }

    /// The size of the dependency records kept for propagation.
    public var dependencyStatistics: ATLIncrementalDependencyStatistics {
        ATLIncrementalDependencyStatistics(
            candidates: candidates.reduce(0) { $0 + $1.count }, matches: matches.count,
            guards: guardIndex.count, guardEntries: guardIndex.entryCount,
            locals: localsIndex.count, localEntries: localsIndex.entryCount,
            bindings: bindingIndex.count, bindingEntries: bindingIndex.entryCount,
            helpers: helperIndex.count, helperEntries: helperIndex.entryCount)
    }

    /// Whether the transformation is watching its source models for changes.
    public var isObserving: Bool { !observations.isEmpty }

    /// The statistics of the latest execution of the module as a whole.
    public private(set) var statistics = ATLExecutionStatistics()

    /// Executes the transformation and starts watching the source models for changes.
    ///
    /// The target models receive exactly the elements that ``ATLVirtualMachine`` creates for
    /// the same models. Executing again starts afresh with the given models.
    ///
    /// - Parameters:
    ///   - sources: Source models indexed by the names the module declares.
    ///   - targets: Target models indexed by the names the module declares; they should be
    ///     empty, and belong to the transformation from now on.
    ///   - parameters: Values for the module parameters declared with `-- @param`, by name.
    /// - Throws: The errors of ``ATLVirtualMachine/execute(sources:targets:parameters:)``.
    public func execute(
        sources: OrderedDictionary<String, Resource>,
        targets: OrderedDictionary<String, Resource>,
        parameters: [String: any EcoreValue] = [:]
    ) async throws {
        await stop()
        _ = queue.drain()
        self.sources = sources
        self.targets = targets
        self.parameters = parameters
        hasExecuted = false
        strategy = Self.staticStrategy(of: module)
        try await executeModule()
        hasExecuted = true
        for resource in sources.values where !observations.contains(where: { $0.resource === resource }) {
            observations.append((resource, await queue.observe(resource)))
        }
    }

    /// Stops watching the source models.
    ///
    /// Changes collected and not yet propagated are kept for the next ``update()``.
    public func stop() async {
        for (resource, observation) in observations {
            await resource.removeChangeObserver(observation)
        }
        observations = []
    }

    /// Propagates the source changes collected since the previous update.
    ///
    /// - Returns: What the update did.
    /// - Throws: ``ATLExecutionError/invalidOperation(_:)`` before the first execution, and
    ///   the errors of a re-execution, which a failing propagation falls back to.
    @discardableResult
    public func update() async throws -> ATLIncrementalUpdate {
        try await update(for: queue.drain())
    }

    /// Propagates source changes reported elsewhere, such as by
    /// ``Resource/recordingChanges(_:)``.
    ///
    /// Use this method instead of ``update()`` when the changes are not collected by the
    /// transformation itself, for example after ``stop()``.
    ///
    /// - Parameter changes: The changes made to the source models, in order.
    /// - Returns: What the update did.
    /// - Throws: ``ATLExecutionError/invalidOperation(_:)`` before the first execution, and
    ///   the errors of a re-execution, which a failing propagation falls back to.
    @discardableResult
    public func update(for changes: [ResourceChange]) async throws -> ATLIncrementalUpdate {
        guard hasExecuted else {
            throw ATLExecutionError.invalidOperation(
                "An incremental transformation must be executed before it can be updated")
        }
        guard !changes.isEmpty else {
            let report = ATLIncrementalUpdate(changeCount: 0)
            lastUpdate = report
            return report
        }
        if case .reexecution(let reason) = strategy {
            return try await reexecute(changes: changes.count, reason: reason)
        }
        let impact = await ModelChangeImpact(changes: changes, in: Array(sources.values))
        if impact.isUnbounded {
            return try await reexecute(changes: changes.count, reason: ATLIncrementalHazard.unboundedChange)
        }
        do {
            let report = try await propagate(changes, impact: impact)
            lastUpdate = report
            return report
        } catch let fallback as Fallback {
            strategy = .reexecution(reason: fallback.reason)
            return try await reexecute(changes: changes.count, reason: fallback.reason)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            return try await reexecute(changes: changes.count, reason: "\(error)")
        }
    }

    /// Evaluates every stale binding, so that the target models are up to date.
    ///
    /// With ``ATLBindingPropagation/immediate`` propagation, no binding is ever stale.
    ///
    /// - Returns: The number of bindings evaluated.
    /// - Throws: The errors of a re-execution, which a failing evaluation falls back to.
    @discardableResult
    public func materialise() async throws -> Int {
        guard !staleBindings.isEmpty || rootsNeedOrdering || !orphanCandidates.isEmpty else { return 0 }
        let pending = ordered(staleBindings)
        do {
            for key in pending { try await reapply(key) }
            staleBindings.subtract(pending)
            try await finishTargets()
        } catch let fallback as Fallback {
            strategy = .reexecution(reason: fallback.reason)
            _ = try await reexecute(changes: 0, reason: fallback.reason)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            _ = try await reexecute(changes: 0, reason: "\(error)")
        }
        return pending.count
    }

    /// The value of a feature of a target element, evaluating its stale bindings first.
    ///
    /// Only the stale bindings of that element and feature are evaluated, as ReactiveATL
    /// computes the target model on demand.
    ///
    /// - Parameters:
    ///   - element: The identifier of the target element.
    ///   - feature: The name of the feature.
    /// - Returns: The stored value of the feature, or `nil` if it is unset or no target model
    ///   holds the element.
    /// - Throws: The errors of a re-execution, which a failing evaluation falls back to.
    public func value(of element: EUUID, feature: String) async throws -> (any EcoreValue)? {
        if let owner = targetOwners[element] {
            let rule = rules[owner.match.rule]
            let bindings = rule.targetPatterns[owner.pattern].bindings
            let keys = bindings.indices
                .filter { bindings[$0].property == feature }
                .map { BindingKey(match: owner.match, pattern: owner.pattern, binding: $0) }
                .filter(staleBindings.contains)
            if !keys.isEmpty {
                do {
                    for key in keys {
                        try await reapply(key)
                        staleBindings.remove(key)
                    }
                    try await orderFeatures()
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    let reason = (error as? Fallback)?.reason ?? "\(error)"
                    _ = try await reexecute(changes: 0, reason: reason)
                }
            }
        }
        for resource in targets.values where await resource.contains(id: element) {
            return await resource.eGet(objectId: element, feature: feature)
        }
        return nil
    }

    // MARK: - Strategy

    /// Decides from the module whether changes can be propagated.
    ///
    /// - Parameter module: The module.
    /// - Returns: The strategy for the module.
    private static func staticStrategy(of module: ATLModule) -> ATLIncrementalStrategy {
        if module.queryBody != nil { return .reexecution(reason: ATLIncrementalHazard.query) }
        if module.isRefining { return .reexecution(reason: ATLIncrementalHazard.refining) }
        if !module.calledRules.isEmpty { return .reexecution(reason: ATLIncrementalHazard.calledRules) }
        for rule in module.matchedRules {
            if !rule.doStatements.isEmpty { return .reexecution(reason: ATLIncrementalHazard.imperativeSection) }
            for pattern in rule.targetPatterns {
                let components = pattern.type.split(separator: ATLLanguage.metamodelSeparator).map(String.init)
                guard components.count == 2,
                    let alias = module.targetAlias(forMetamodel: components[0]),
                    let eClass = module.targetMetamodels[alias]?.getClassifier(components[1]) as? EClass
                else { continue }
                for binding in pattern.bindings {
                    if let reference = eClass.getStructuralFeature(name: binding.property) as? EReference,
                        reference.opposite != nil || reference.container
                    {
                        return .reexecution(reason: ATLIncrementalHazard.oppositeReference)
                    }
                }
            }
        }
        return .propagation
    }

    // MARK: - Execution

    /// Executes the module as a whole, recording its dependencies when they are needed.
    private func executeModule() async throws {
        machine = ATLVirtualMachine(
            module: module, options: options, unsetFeatureReads: unsetFeatureReads,
            nativeHelpers: nativeHelpers)
        machine.fileOutput = fileOutput
        resetState()
        let propagates = strategy == .propagation
        if propagates { machine.incrementalJournal = ATLIncrementalJournal() }
        try await machine.execute(sources: sources, targets: targets, parameters: parameters)
        statistics = machine.getStatistics()
        guard propagates else { return }
        if let hazard = machine.executionContext.incrementalHazard {
            strategy = .reexecution(reason: hazard)
            machine.incrementalJournal = nil
            resetState()
            return
        }
        do {
            try buildState()
        } catch let fallback as Fallback {
            strategy = .reexecution(reason: fallback.reason)
            machine.incrementalJournal = nil
            resetState()
        }
    }

    /// Clears the target models and executes the module again.
    ///
    /// If the execution fails, the transformation counts as not executed until
    /// ``execute(sources:targets:parameters:)`` succeeds.
    ///
    /// - Parameters:
    ///   - changes: The number of changes that caused the re-execution.
    ///   - reason: Why the module is executed again.
    /// - Returns: The report of the update.
    private func reexecute(changes: Int, reason: String) async throws -> ATLIncrementalUpdate {
        hasExecuted = false
        for target in targets.values { await target.clear() }
        try await executeModule()
        hasExecuted = true
        let report = ATLIncrementalUpdate(changeCount: changes, reexecuted: true, reason: reason)
        lastUpdate = report
        return report
    }

    /// Forgets every recorded dependency and match.
    private func resetState() {
        rules = []
        ruleIndex = [:]
        patternClasses = []
        patternClassNames = []
        candidates = []
        guardIndex.removeAll()
        matches = [:]
        localsIndex.removeAll()
        bindingIndex.removeAll()
        helperIndex.removeAll()
        staleBindings = []
        targetOwners = [:]
        orphanCandidates = []
        reorderCandidates = []
        rootsNeedOrdering = false
    }

    /// Builds the incremental state from the journal of an execution.
    private func buildState() throws {
        guard let journal = machine.incrementalJournal else { return }
        rules = try machine.effectiveMatchedRules()
        for (position, rule) in rules.enumerated() {
            ruleIndex[rule.rule.name] = position
            let classes = try rule.rule.sourcePatterns.map { try machine.sourceClass(forType: $0.type) }
            patternClasses.append(classes)
            patternClassNames.append(Set(classes.map(\.eClass.name)))
            candidates.append([:])
        }
        for record in journal.guards {
            guard let position = ruleIndex[record.ruleName] else { continue }
            try checkEarlyReads(record.dependencies)
            candidates[position][record.sourceIDs] = record.holds
            let key = MatchKey(rule: position, sources: record.sourceIDs)
            if !record.dependencies.isEmpty { guardIndex.insert(record.dependencies, for: key) }
        }
        for record in journal.matches {
            guard let position = ruleIndex[record.ruleName] else { continue }
            try checkEarlyReads(record.dependencies)
            let key = MatchKey(rule: position, sources: record.sourceIDs)
            matches[key] = MatchState(variables: record.variables, targetIDs: record.targetIDs)
            if !record.dependencies.isEmpty { localsIndex.insert(record.dependencies, for: key) }
            for (pattern, id) in record.targetIDs.enumerated() { targetOwners[id] = (key, pattern) }
        }
        for record in journal.bindings {
            guard let owner = targetOwners[record.targetID] else { continue }
            bindingIndex.insert(
                record.dependencies,
                for: BindingKey(match: owner.match, pattern: owner.pattern, binding: record.ordinal))
        }
        indexHelperCache()
        machine.incrementalJournal = ATLIncrementalJournal()
    }

    /// Rejects reads of the trace by guards and `using` variables.
    ///
    /// Guards and `using` variables are evaluated while the trace is being built, so what
    /// they read of it depends on the order of matching.
    ///
    /// - Parameter dependencies: What a guard or `using` variable read.
    /// - Throws: ``Fallback`` if the trace was read.
    private func checkEarlyReads(_ dependencies: ModelDependencies) throws {
        if dependencies.features.contains(where: { $0.feature == ATLReservedNames.traceDependency }) {
            throw Fallback(reason: ATLIncrementalHazard.targetRead)
        }
    }

    /// Indexes the dependencies of the attribute helper values cached since the last call.
    private func indexHelperCache() {
        let context = machine.executionContext
        for key in context.takeRecordedHelperKeys() {
            guard let dependencies = context.attributeHelperCache[key]?.dependencies else { continue }
            helperIndex.insert(dependencies, for: key)
        }
    }

    // MARK: - Propagation

    /// Propagates changes match by match and binding by binding.
    ///
    /// - Parameters:
    ///   - changes: The source changes.
    ///   - impact: Their summary.
    /// - Returns: What the propagation did.
    private func propagate(_ changes: [ResourceChange], impact: ModelChangeImpact) async throws
        -> ATLIncrementalUpdate
    {
        let context = machine.executionContext
        context.incrementalHazard = nil
        machine.incrementalJournal = ATLIncrementalJournal()
        await context.executionEngine.invalidateCaches(for: changes)
        invalidateHelpers(affectedBy: impact)

        // Matching
        var guardsEvaluated = 0
        var candidatesChanged = false
        let affectedGuards = guardIndex.dependents(affectedBy: impact)
        let reorders = Self.reordersContents(changes, impact: impact)
        for position in rules.indices {
            if reorders || !patternClassNames[position].isDisjoint(with: impact.affectedExtents) {
                let (evaluated, changed) = try await rematch(position, affectedGuards: affectedGuards)
                guardsEvaluated += evaluated
                candidatesChanged = candidatesChanged || changed
            } else {
                for key in affectedGuards where key.rule == position && candidates[position][key.sources] != nil {
                    guard let tuple = await sourceObjects(key.sources) else { continue }
                    let holds = try await evaluateGuards(of: key, tuple: tuple)
                    if candidates[position][key.sources] != holds { candidatesChanged = true }
                    candidates[position][key.sources] = holds
                    guardsEvaluated += 1
                }
            }
        }
        let order = candidatesChanged ? matchOrder() : []
        var added: [MatchKey] = []
        var removed: [MatchKey] = []
        var traceChanged = Set<EUUID>()
        if candidatesChanged, order != Array(matches.keys) {
            let wanted = Set(order)
            removed = matches.keys.filter { !wanted.contains($0) }
            added = order.filter { matches[$0] == nil }
            for key in removed { try await removeMatch(key) }
            var created: [MatchKey: MatchState] = [:]
            for key in added { created[key] = try await createMatch(key) }
            var reordered = OrderedDictionary<MatchKey, MatchState>()
            reordered.reserveCapacity(order.count)
            for key in order { reordered[key] = matches[key] ?? created[key] }
            matches = reordered
            rebuildTrace()
            for key in added + removed { traceChanged.formUnion(key.sources) }
            rootsNeedOrdering = true
        }

        // Bindings
        var combined = impact
        for id in traceChanged {
            combined.add(
                ResourceChange(kind: .set, objectID: id, feature: ATLReservedNames.traceDependency),
                objectClass: nil)
        }
        if !traceChanged.isEmpty { invalidateHelpers(affectedBy: combined) }
        let addedSet = Set(added)
        var pending = Set<BindingKey>()
        var localsEvaluated = 0
        for key in ordered(localsIndex.dependents(affectedBy: combined)) where !addedSet.contains(key) {
            try await reevaluateLocals(of: key)
            localsEvaluated += 1
            pending.formUnion(bindingKeys(of: key))
        }
        for key in bindingIndex.dependents(affectedBy: combined) where !addedSet.contains(key.match) {
            pending.insert(key)
        }
        for key in added { pending.formUnion(bindingKeys(of: key)) }
        var bindingsEvaluated = 0
        var bindingsDeferred = 0
        switch bindingPropagation {
        case .immediate:
            for key in ordered(pending) {
                try await reapply(key)
                bindingsEvaluated += 1
            }
            try await finishTargets()
        case .onDemand:
            staleBindings.formUnion(pending)
            bindingsDeferred = pending.count
        }
        indexHelperCache()
        return ATLIncrementalUpdate(
            changeCount: changes.count, guardsEvaluated: guardsEvaluated, matchesAdded: added.count,
            matchesRemoved: removed.count, localsEvaluated: localsEvaluated,
            bindingsEvaluated: bindingsEvaluated, bindingsDeferred: bindingsDeferred)
    }

    /// Discards the cached attribute helper values that changes affect.
    ///
    /// - Parameter impact: The summary of the changes.
    private func invalidateHelpers(affectedBy impact: ModelChangeImpact) {
        for key in helperIndex.dependents(affectedBy: impact) {
            machine.executionContext.attributeHelperCache[key] = nil
            helperIndex.remove(key)
        }
    }

    /// Matches a rule again against the current source models.
    ///
    /// Tuples whose guards were evaluated before and are not affected keep their outcome.
    ///
    /// - Parameters:
    ///   - position: The position of the rule.
    ///   - affectedGuards: The tuples whose guards the changes affect.
    /// - Returns: The number of guard evaluations, and whether the tuples, their order or
    ///   the outcome of a guard changed.
    private func rematch(_ position: Int, affectedGuards: Set<MatchKey>) async throws -> (Int, Bool) {
        let context = machine.executionContext
        var lists: [[any EObject]] = []
        for (alias, eClass) in patternClasses[position] {
            guard let resource = context.getSource(alias) else {
                throw ATLExecutionError.invalidOperation("Source model '\(alias)' not found")
            }
            lists.append(await resource.getAllInstancesOf(eClass))
        }
        var tuples: [[any EObject]] = [[]]
        for instances in lists {
            tuples = tuples.flatMap { prefix in instances.map { prefix + [$0] } }
        }
        var updated = OrderedDictionary<[EUUID], Bool>()
        updated.reserveCapacity(tuples.count)
        var evaluated = 0
        for tuple in tuples {
            let ids = tuple.map(\.id)
            let key = MatchKey(rule: position, sources: ids)
            if let known = candidates[position][ids], !affectedGuards.contains(key) {
                updated[ids] = known
            } else {
                updated[ids] = try await evaluateGuards(of: key, tuple: tuple)
                evaluated += 1
            }
        }
        for ids in candidates[position].keys where updated[ids] == nil {
            guardIndex.remove(MatchKey(rule: position, sources: ids))
        }
        let changed = updated != candidates[position]
        candidates[position] = updated
        return (evaluated, changed)
    }

    /// Decides whether changes may alter the document order of elements that existed before.
    ///
    /// Creating or deleting elements changes the instances of their classes, which the
    /// affected extents describe. Moving an existing element to another container, or to
    /// another position in its container, may also change the order in which the instances
    /// of other classes are listed.
    ///
    /// - Parameters:
    ///   - changes: The changes.
    ///   - impact: Their summary.
    /// - Returns: `true` if an existing element moved.
    private static func reordersContents(_ changes: [ResourceChange], impact: ModelChangeImpact) -> Bool {
        guard impact.changesContainmentStructure else { return false }
        if !impact.movedObjects.subtracting(impact.createdObjects).subtracting(impact.deletedObjects).isEmpty {
            return true
        }
        return changes.contains { $0.kind == .move }
    }

    /// Evaluates the guards of a rule for a tuple, recording what they read.
    ///
    /// - Parameters:
    ///   - key: The rule and the identifiers of the tuple.
    ///   - tuple: The source elements.
    /// - Returns: Whether the guards hold.
    private func evaluateGuards(of key: MatchKey, tuple: [any EObject]) async throws -> Bool {
        let context = machine.executionContext
        context.dependencyRecorder.begin()
        let holds: Bool
        do {
            holds = try await machine.satisfiesGuards(rules[key.rule], sources: tuple)
        } catch {
            context.dependencyRecorder.end()
            throw error
        }
        let dependencies = context.dependencyRecorder.end()
        try checkHazard()
        try checkEarlyReads(dependencies)
        if dependencies.isEmpty {
            guardIndex.remove(key)
        } else {
            guardIndex.insert(dependencies, for: key)
        }
        return holds
    }

    /// The matches that an execution would create, in creation order.
    ///
    /// A source element tuple matched both by a rule and by a rule extending it is
    /// transformed by the extending rule only.
    private func matchOrder() -> [MatchKey] {
        var rulesBySources: [[EUUID]: [Int]] = [:]
        for (position, tuples) in candidates.enumerated() {
            for (ids, holds) in tuples where holds { rulesBySources[ids, default: []].append(position) }
        }
        var order: [MatchKey] = []
        for (position, tuples) in candidates.enumerated() {
            let name = rules[position].rule.name
            for (ids, holds) in tuples where holds {
                let hidden = (rulesBySources[ids] ?? []).contains { other in
                    other != position && rules[other].rule.name != name
                        && rules[other].chainNames.contains(name)
                }
                if !hidden { order.append(MatchKey(rule: position, sources: ids)) }
            }
        }
        return order
    }

    /// Deletes the target elements of a match that no longer holds.
    ///
    /// - Parameter key: The match.
    private func removeMatch(_ key: MatchKey) async throws {
        guard let state = matches[key] else { return }
        for id in state.targetIDs {
            for resource in targets.values where await resource.contains(id: id) {
                if let object = await resource.resolve(id), let eClass = object.eClass as? EClass {
                    for reference in eClass.eAllReferences where reference.containment {
                        orphanCandidates.formUnion(Self.identifiers(object.eGet(reference)))
                    }
                }
                await resource.remove(id: id)
            }
            targetOwners[id] = nil
            orphanCandidates.remove(id)
            reorderCandidates.remove(id)
        }
        for binding in bindingKeys(of: key) {
            bindingIndex.remove(binding)
            staleBindings.remove(binding)
        }
        localsIndex.remove(key)
        matches[key] = nil
    }

    /// Creates the target elements of a new match.
    ///
    /// - Parameter key: The match.
    /// - Returns: The state of the match, whose bindings remain to be applied.
    private func createMatch(_ key: MatchKey) async throws -> MatchState {
        guard let tuple = await sourceObjects(key.sources) else {
            throw Fallback(reason: "a matched source element is missing")
        }
        let pending = try await machine.createTargets(
            for: ATLVirtualMachine.MatchCandidate(rule: rules[key.rule], sources: tuple))
        try checkHazard()
        if let record = machine.incrementalJournal?.matches.popLast() {
            try checkEarlyReads(record.dependencies)
            if !record.dependencies.isEmpty { localsIndex.insert(record.dependencies, for: key) }
        }
        for (pattern, id) in pending.targetIDs.enumerated() { targetOwners[id] = (key, pattern) }
        return MatchState(variables: pending.variables, targetIDs: pending.targetIDs)
    }

    /// Records the trace links of all matches, in match order.
    private func rebuildTrace() {
        var links: [ATLTraceLink] = []
        links.reserveCapacity(matches.count)
        for (key, state) in matches {
            let rule = rules[key.rule]
            links.append(
                ATLTraceLink(
                    ruleName: rule.rule.name, sourceElement: key.sources[0], targetElements: state.targetIDs,
                    additionalSourceElements: Array(key.sources.dropFirst()),
                    targetNames: rule.targetPatterns.map(\.variableName), kind: .matched))
        }
        machine.executionContext.replaceTraceLinks(links)
    }

    /// Evaluates the `using` variables of a match again.
    ///
    /// - Parameter key: The match.
    private func reevaluateLocals(of key: MatchKey) async throws {
        guard var state = matches[key], let tuple = await sourceObjects(key.sources) else { return }
        let context = machine.executionContext
        let rule = rules[key.rule]
        context.pushScope()
        defer { context.popScope() }
        machine.bindSourceVariables(of: rule, sources: tuple)
        var variables: [(name: String, value: (any EcoreValue)?)] = []
        for member in rule.chain {
            for (pattern, element) in zip(member.sourcePatterns, tuple) {
                variables.append((pattern.variableName, element))
            }
        }
        context.dependencyRecorder.begin()
        do {
            for local in rule.localVariables {
                let value = try await local.expression.evaluate(in: context)
                context.setVariable(local.name, value: value)
                variables.append((local.name, value))
            }
        } catch {
            context.dependencyRecorder.end()
            throw error
        }
        let dependencies = context.dependencyRecorder.end()
        try checkHazard()
        try checkEarlyReads(dependencies)
        if dependencies.isEmpty {
            localsIndex.remove(key)
        } else {
            localsIndex.insert(dependencies, for: key)
        }
        state.variables = variables
        matches[key] = state
    }

    /// Evaluates a binding again and assigns its value.
    ///
    /// - Parameter key: The binding.
    private func reapply(_ key: BindingKey) async throws {
        guard let state = matches[key.match] else { return }
        let context = machine.executionContext
        let rule = rules[key.match.rule]
        let binding = rule.targetPatterns[key.pattern].bindings[key.binding]
        context.pushScope()
        defer { context.popScope() }
        for (name, value) in state.variables { context.setVariable(name, value: await current(value)) }
        var element: (any EObject)?
        for (position, (pattern, id)) in zip(rule.targetPatterns, state.targetIDs).enumerated() {
            let object = await context.findTargetObject(id)
            context.setVariable(pattern.variableName, value: object)
            if position == key.pattern { element = object }
        }
        guard let element, let eClass = element.eClass as? EClass else {
            throw Fallback(reason: "a target element is missing")
        }
        let feature = eClass.getStructuralFeature(name: binding.property)
        let containment = (feature as? EReference)?.containment == true
        let previous = feature.flatMap { element.eGet($0) }
        let before = containment ? Self.identifiers(previous) : []
        let wasSet = previous != nil
        try await machine.applyBinding(binding, to: element, ordinal: key.binding)
        try checkHazard()
        if let record = machine.incrementalJournal?.bindings.popLast() {
            bindingIndex.insert(record.dependencies, for: key)
        }
        guard let resource = await targetResource(of: element.id) else { return }
        let after = await resource.eGet(objectId: element.id, feature: binding.property)
        if containment {
            let kept = Set(Self.identifiers(after))
            orphanCandidates.formUnion(before.filter { !kept.contains($0) })
            rootsNeedOrdering = true
        }
        if !wasSet && after != nil { reorderCandidates.insert(element.id) }
    }

    /// Restores the order of root elements and of features after bindings were assigned.
    private func finishTargets() async throws {
        try await orderFeatures()
        for id in orphanCandidates {
            guard let resource = await targetResource(of: id), let object = await resource.resolve(id) else { continue }
            await resource.add(object)
        }
        if !orphanCandidates.isEmpty { rootsNeedOrdering = true }
        orphanCandidates = []
        guard rootsNeedOrdering else { return }
        var order: [EUUID] = []
        order.reserveCapacity(targetOwners.count)
        for state in matches.values { order.append(contentsOf: state.targetIDs) }
        for resource in targets.values { await resource.reorderRoots(order) }
        rootsNeedOrdering = false
    }

    /// Puts the set features of target elements back into the order of their bindings.
    ///
    /// An execution sets the features of a target element only through its bindings, in
    /// binding order, so a feature that a later update sets for the first time is moved to
    /// the position its binding gives it.
    private func orderFeatures() async throws {
        defer { reorderCandidates = [] }
        for id in reorderCandidates {
            guard let owner = targetOwners[id], let resource = await targetResource(of: id) else { continue }
            let bindings = rules[owner.match.rule].targetPatterns[owner.pattern].bindings
            var expected: [String] = []
            for binding in bindings where !expected.contains(binding.property) {
                if await resource.eGet(objectId: id, feature: binding.property) != nil {
                    expected.append(binding.property)
                }
            }
            let actual = await resource.getFeatureNames(objectId: id)
            guard actual != expected else { continue }
            var values: [(String, any EcoreValue)] = []
            for name in actual {
                if let value = await resource.eGet(objectId: id, feature: name) { values.append((name, value)) }
            }
            let ranked = values.sorted { lhs, rhs in
                (expected.firstIndex(of: lhs.0) ?? Int.max) < (expected.firstIndex(of: rhs.0) ?? Int.max)
            }
            for (name, _) in values { await resource.eSet(objectId: id, feature: name, value: nil) }
            for (name, value) in ranked { await resource.eSet(objectId: id, feature: name, value: value) }
        }
    }

    // MARK: - Helpers

    /// Throws if an evaluation since the last check cannot be propagated incrementally.
    private func checkHazard() throws {
        if let hazard = machine.executionContext.incrementalHazard { throw Fallback(reason: hazard) }
    }

    /// The keys of all bindings of a match.
    ///
    /// - Parameter key: The match.
    /// - Returns: The bindings, in pattern and binding order.
    private func bindingKeys(of key: MatchKey) -> [BindingKey] {
        rules[key.rule].targetPatterns.enumerated().flatMap { pattern, target in
            target.bindings.indices.map { BindingKey(match: key, pattern: pattern, binding: $0) }
        }
    }

    /// Sorts bindings into match, pattern and binding order.
    ///
    /// - Parameter keys: The bindings.
    /// - Returns: The bindings of existing matches, sorted.
    private func ordered(_ keys: Set<BindingKey>) -> [BindingKey] {
        keys.compactMap { key in matches.index(forKey: key.match).map { (key, $0) } }
            .sorted { lhs, rhs in
                (lhs.1, lhs.0.pattern, lhs.0.binding) < (rhs.1, rhs.0.pattern, rhs.0.binding)
            }
            .map(\.0)
    }

    /// Sorts matches into match order.
    ///
    /// - Parameter keys: The matches.
    /// - Returns: The existing matches, sorted.
    private func ordered(_ keys: Set<MatchKey>) -> [MatchKey] {
        keys.compactMap { key in matches.index(forKey: key).map { (key, $0) } }
            .sorted { $0.1 < $1.1 }
            .map(\.0)
    }

    /// The current state of the source elements of a tuple.
    ///
    /// - Parameter ids: The identifiers of the elements.
    /// - Returns: The elements, or `nil` if a source model no longer holds one of them.
    private func sourceObjects(_ ids: [EUUID]) async -> [any EObject]? {
        var objects: [any EObject] = []
        for id in ids {
            guard let object = await sourceObject(id) else { return nil }
            objects.append(object)
        }
        return objects
    }

    /// The current state of a source element.
    private func sourceObject(_ id: EUUID) async -> (any EObject)? {
        for resource in sources.values {
            if let object = await resource.resolve(id) { return object }
        }
        return nil
    }

    /// A value with every source element replaced by its current state.
    private func current(_ value: (any EcoreValue)?) async -> (any EcoreValue)? {
        if let object = value as? any EObject {
            return await sourceObject(object.id) ?? object
        }
        return value
    }

    /// The target model that holds an element.
    private func targetResource(of id: EUUID) async -> Resource? {
        for resource in targets.values where await resource.contains(id: id) { return resource }
        return nil
    }

    /// The element identifiers held by a reference value.
    private static func identifiers(_ value: (any EcoreValue)?) -> [EUUID] {
        guard let value else { return [] }
        if let id = value as? EUUID { return [id] }
        if let ids = value as? [EUUID] { return ids }
        if let array = value as? EcoreValueArray { return array.values.flatMap { identifiers($0) } }
        return []
    }
}
