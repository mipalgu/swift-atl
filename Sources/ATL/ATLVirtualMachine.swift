//
//  ATLVirtualMachine.swift
//  ATL
//
//  Created by Rene Hexel on 6/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import OrderedCollections

/// Actor responsible for executing ATL transformations.
///
/// The ATL Virtual Machine orchestrates the execution of Atlas Transformation Language
/// modules, coordinating matched rule evaluation, called rule invocation, and helper
/// function execution. It provides a concurrent execution environment that maintains
/// transformation state consistency while enabling parallel rule processing.
///
/// ## Overview
///
/// The virtual machine operates through several execution phases:
/// - **Initialisation**: Module validation and execution context setup
/// - **Matched Rule Execution**: Automatic rule triggering for matching elements
/// - **Lazy Binding Resolution**: Deferred property binding and reference resolution
/// - **Called Rule Processing**: Explicit rule invocation as requested
/// - **Finalisation**: Target model validation and resource cleanup
///
/// ## Execution Model
///
/// ATL transformations follow a hybrid declarative-imperative model:
/// - **Declarative Phase**: Matched rules execute automatically for all matching source elements
/// - **Imperative Phase**: Called rules execute on-demand through explicit invocations
/// - **Resolution Phase**: Lazy bindings resolve forward references and circular dependencies
///
/// ## Concurrency Design
///
/// The virtual machine is implemented as an actor to ensure thread-safe transformation
/// execution. Rule processing can occur concurrently for independent elements while
/// maintaining serialised access to shared transformation state.
///
/// ## Example Usage
///
/// ```swift
/// let vm = ATLVirtualMachine(module: transformationModule)
///
/// try await vm.execute(
///     sources: ["IN": sourceResource],
///     targets: ["OUT": targetResource]
/// )
/// ```
@MainActor
public final class ATLVirtualMachine {

    // MARK: - Properties

    /// The ATL module to execute.
    ///
    /// The module contains transformation rules, helper functions, and metamodel
    /// specifications that define the transformation behaviour.
    public let module: ATLModule

    /// The execution context managing transformation state.
    ///
    /// The execution context provides access to models, variables, trace links,
    /// and other state required for transformation execution.
    private var executionContext: ATLExecutionContext

    /// Statistics tracking transformation execution.
    ///
    /// Execution statistics provide insights into transformation performance
    /// and rule invocation patterns for debugging and optimisation.
    public private(set) var statistics: ATLExecutionStatistics

    /// Debug mode flag for systematic tracing.
    private var debug: Bool = false

    /// The monitor of the run in progress, if any.
    private var monitor: ATLRunMonitor?

    // MARK: - Initialisation

    /// Creates a new ATL virtual machine for the specified module.
    ///
    /// - Parameters:
    ///   - module: The ATL module to execute
    ///   - enableDebugging: Whether to enable debug output for systematic tracing
    public init(module: ATLModule, enableDebugging: Bool = false) {
        self.module = module

        // Create execution engine with empty models initially
        let executionEngine = ECoreExecutionEngine(models: [:])

        executionContext = ATLExecutionContext(
            module: module,
            executionEngine: executionEngine
        )
        statistics = ATLExecutionStatistics()
        debug = enableDebugging
        // Wire back-reference so helpers and expressions can invoke called rules
        executionContext.virtualMachine = self
    }

    // MARK: - Debug Configuration

    /// Enable or disable debug output for systematic tracing.
    ///
    /// When enabled, the virtual machine prints detailed trace information
    /// for rule execution, helper evaluation, and transformation progress.
    ///
    /// - Parameter enabled: Whether to enable debug output
    public func enableDebugging(_ enabled: Bool = true) async {
        debug = enabled
        executionContext.debug = enabled
        await executionContext.executionEngine.enableDebugging(enabled)
    }

    // MARK: - Transformation Execution

    /// Executes the ATL transformation with the specified models.
    ///
    /// This method orchestrates the complete transformation process, including
    /// matched rule execution, lazy binding resolution, and statistics collection.
    ///
    /// - Parameters:
    ///   - sources: Source models indexed by namespace aliases
    ///   - targets: Target models indexed by namespace aliases
    ///   - parameters: Values for the module parameters declared with `-- @param`, by name
    /// - Throws: ATL execution errors for transformation failures, including
    ///   ``ATLExecutionError/missingParameter(_:)`` for a required parameter without a value
    ///
    /// - Note: Source and target model aliases must match the module's metamodel specifications
    public func execute(
        sources: OrderedDictionary<String, Resource>,
        targets: OrderedDictionary<String, Resource>,
        parameters: [String: any EcoreValue] = [:]
    ) async throws {
        try await execute(
            sources: sources, targets: targets, parameters: parameters, progress: nil)
    }

    /// Executes the ATL transformation, reporting progress and honouring cancellation.
    ///
    /// The run reports a snapshot whenever a rule, match or binding has been
    /// processed, and a final snapshot in the ``ATLProgressPhase/finished`` phase
    /// on success. It checks for cancellation of the surrounding task at every
    /// rule, source element, match and lazy binding, and it suspends for a
    /// moment after each ten milliseconds of work, so that other work on the
    /// main actor, such as the user interface, keeps running.
    ///
    /// A cancelled run throws `CancellationError` and does not report the
    /// finished phase. The target models are left partly populated with the
    /// elements and bindings created up to that point; callers that need an
    /// all-or-nothing result should discard the targets.
    ///
    /// - Parameters:
    ///   - sources: Source models indexed by namespace aliases
    ///   - targets: Target models indexed by namespace aliases
    ///   - parameters: Values for the module parameters declared with `-- @param`, by name
    ///   - progress: A callback that receives progress snapshots on the main actor
    /// - Throws: `CancellationError` when the task is cancelled, otherwise the errors of
    ///   ``execute(sources:targets:parameters:)``
    public func execute(
        sources: OrderedDictionary<String, Resource>,
        targets: OrderedDictionary<String, Resource>,
        parameters: [String: any EcoreValue] = [:],
        progress: ATLProgressHandler?
    ) async throws {
        let monitor = ATLRunMonitor(handler: progress)
        self.monitor = monitor
        defer { self.monitor = nil }
        if debug {
            print("[ATL] Executing transformation: \(module.name)")
            print("[ATL] Source models: \(sources.keys.joined(separator: ", "))")
            print("[ATL] Target models: \(targets.keys.joined(separator: ", "))")
        }

        statistics.reset()
        let startTime = Date()

        // Validate model aliases against module specifications
        try validateModelAliases(sources: sources, targets: targets)

        // Bind module parameters and start with fresh attribute helper values
        try executionContext.setModuleParameters(parameters)
        executionContext.clearAttributeHelperCache()

        // Configure execution context with models
        for (alias, resource) in sources {
            await executionContext.addSource(alias, resource: resource)
        }
        for (alias, resource) in targets {
            await executionContext.addTarget(alias, resource: resource)
        }

        do {
            executionContext.resetTransformationState()

            // Phase 1: match all rules and create every target element, so that
            // bindings can resolve any source element regardless of rule order
            let rules = try effectiveMatchedRules()
            let matches = try await matchRules(rules)

            try await executeCalledRules(.entrypoint) { $0.isEntrypoint }

            // Phase 2: apply bindings and imperative blocks
            for (index, match) in matches.enumerated() {
                monitor.report(
                    .applying, completed: index, total: matches.count, rule: match.rule.rule.name)
                try await monitor.checkpoint()
                try await apply(match)
            }
            monitor.report(.applying, completed: matches.count, total: matches.count)

            // Resolve lazy bindings for forward references
            let pending = executionContext.pendingLazyBindingCount
            monitor.report(.resolvingBindings, completed: 0, total: pending)
            var resolved = 0
            try await executionContext.resolveLazyBindings {
                try await monitor.checkpoint()
                resolved += 1
                monitor.report(.resolvingBindings, completed: resolved, total: pending)
            }

            try await executeCalledRules(.endpoint) { $0.isEndpoint }
            monitor.report(.finished, completed: 1, total: 1)

            // Update execution statistics
            statistics.executionTime = Date().timeIntervalSince(startTime)
            statistics.successful = true

            if debug {
                print("[ATL] Transformation completed successfully")
                print("[ATL] Execution time: \(statistics.executionTime)s")
                print("[ATL] Rules executed: \(statistics.rulesExecuted)")
            }

        } catch {
            statistics.executionTime = Date().timeIntervalSince(startTime)
            statistics.successful = false
            statistics.lastError = error

            if debug {
                print("[ATL] Transformation failed: \(error)")
            }

            throw error
        }
    }

    // MARK: - Matched Rule Execution

    /// A matched rule whose target elements have been created and await their bindings.
    private struct PendingMatch {

        /// The rule that matched.
        let rule: ATLEffectiveMatchedRule

        /// The source and `using` variables in scope when the bindings are evaluated.
        let variables: [(name: String, value: (any EcoreValue)?)]

        /// The identifiers of the created target elements, parallel to the rule's target patterns.
        let targetIDs: [EUUID]
    }

    /// A tuple of source elements that satisfies a rule's source patterns and guards.
    private struct MatchCandidate {

        /// The rule the elements satisfy.
        let rule: ATLEffectiveMatchedRule

        /// The matched source elements, in source pattern order.
        let sources: [any EObject]

        /// The identifiers of the matched source elements.
        var sourceIDs: [EUUID] { sources.map(\.id) }
    }

    /// Computes the effective matched rules of the module.
    ///
    /// - Returns: The non-abstract matched rules with their inheritance resolved
    /// - Throws: ATL execution errors for invalid `extends` relationships
    private func effectiveMatchedRules() throws -> [ATLEffectiveMatchedRule] {
        return try ATLRuleInheritance.effectiveRules(for: module.matchedRules) { sub, base in
            let subClass = try self.sourceClass(forType: sub.type).eClass
            let baseClass = try self.sourceClass(forType: base.type).eClass
            return Self.conforms(subClass, to: baseClass)
        }
    }

    /// Decides whether a class is the same as, or a subtype of, another class.
    ///
    /// - Parameters:
    ///   - candidate: The potential subtype
    ///   - base: The potential supertype
    /// - Returns: `true` if `candidate` conforms to `base`
    private static func conforms(_ candidate: EClass, to base: EClass) -> Bool {
        if candidate.name == base.name { return true }
        return candidate.eSuperTypes.contains { conforms($0, to: base) }
    }

    /// Looks up the class and source model named by a qualified source type.
    ///
    /// - Parameter type: The qualified type, such as `Families!Member`
    /// - Returns: The model alias and class
    /// - Throws: ATL execution errors for malformed or unknown types
    private func sourceClass(forType type: String) throws -> (alias: String, eClass: EClass) {
        let typeComponents = type.split(separator: "!")
        guard typeComponents.count == 2 else {
            throw ATLExecutionError.typeError("Invalid source type specification: '\(type)'")
        }
        let metamodelName = String(typeComponents[0])
        let sourceClassName = String(typeComponents[1])

        if debug {
            print("[ATL]   Source type: \(metamodelName)!\(sourceClassName)")
        }

        guard let modelAlias = module.sourceAlias(forMetamodel: metamodelName)
        else {
            throw ATLExecutionError.invalidOperation(
                "No source model found for metamodel '\(metamodelName)'")
        }
        guard let sourceMetamodel = module.sourceMetamodels[modelAlias] else {
            throw ATLExecutionError.invalidOperation("Source metamodel '\(modelAlias)' not found")
        }
        guard let eClass = sourceMetamodel.getClassifier(sourceClassName) as? EClass else {
            throw ATLExecutionError.typeError(
                "Class '\(sourceClassName)' not found in metamodel '\(metamodelName)'"
            )
        }
        return (modelAlias, eClass)
    }

    /// Matches all rules against the source models and creates their target elements.
    ///
    /// A source element matched by both a rule and a rule extending it is
    /// transformed by the extending rule only.
    ///
    /// - Parameter rules: The effective matched rules
    /// - Returns: The matches, in rule and source element order
    /// - Throws: ATL execution errors for rule execution failures
    private func matchRules(_ rules: [ATLEffectiveMatchedRule]) async throws -> [PendingMatch] {
        let monitor = self.monitor ?? ATLRunMonitor(handler: nil)
        var candidates: [MatchCandidate] = []
        for (index, rule) in rules.enumerated() {
            monitor.report(
                .matching, completed: index, total: rules.count, rule: rule.rule.name)
            try await monitor.checkpoint()
            if debug {
                print("[ATL] Matching rule: \(rule.rule.name)")
            }
            statistics.rulesExecuted += 1
            candidates.append(contentsOf: try await matchingCandidates(for: rule))
        }

        monitor.report(.matching, completed: rules.count, total: rules.count)
        var matches: [PendingMatch] = []
        for candidate in candidates {
            try await monitor.checkpoint()
            let isHidden = candidates.contains { other in
                other.sourceIDs == candidate.sourceIDs
                    && other.rule.rule.name != candidate.rule.rule.name
                    && other.rule.chainNames.contains(candidate.rule.rule.name)
            }
            if !isHidden {
                matches.append(try await createTargets(for: candidate))
            }
        }
        return matches
    }

    /// Finds the source element tuples that satisfy a rule's source patterns and guards.
    ///
    /// - Parameter rule: The rule to match
    /// - Returns: The candidates, in source element order
    /// - Throws: ATL execution errors for rule execution failures
    private func matchingCandidates(for rule: ATLEffectiveMatchedRule) async throws -> [MatchCandidate] {
        var instanceLists: [[any EObject]] = []
        for pattern in rule.rule.sourcePatterns {
            let (alias, eClass) = try sourceClass(forType: pattern.type)
            guard let resource = executionContext.getSource(alias) else {
                throw ATLExecutionError.invalidOperation("Source model '\(alias)' not found")
            }
            instanceLists.append(await resource.getAllInstancesOf(eClass))
        }

        var tuples: [[any EObject]] = [[]]
        for instances in instanceLists {
            tuples = tuples.flatMap { prefix in instances.map { prefix + [$0] } }
        }

        var result: [MatchCandidate] = []
        for tuple in tuples {
            try await monitor?.checkpoint()
            statistics.elementsProcessed += 1
            if try await satisfiesGuards(rule, sources: tuple) {
                result.append(MatchCandidate(rule: rule, sources: tuple))
            }
        }
        return result
    }

    /// Evaluates the guards of a rule and the rules it extends for a source element tuple.
    ///
    /// - Parameters:
    ///   - rule: The rule whose guards are evaluated
    ///   - sources: The source elements bound to the source patterns
    /// - Returns: `true` if every guard holds
    /// - Throws: Errors raised while evaluating a guard
    private func satisfiesGuards(_ rule: ATLEffectiveMatchedRule, sources: [any EObject])
        async throws -> Bool
    {
        executionContext.pushScope()
        defer { executionContext.popScope() }
        bindSourceVariables(of: rule, sources: sources)

        for member in rule.chain {
            var guards: [any ATLExpression] = []
            if let guardExpression = member.`guard` { guards.append(guardExpression) }
            guards.append(contentsOf: member.additionalSourcePatterns.compactMap(\.guard))
            for guardExpression in guards {
                let outcome = try await guardExpression.evaluate(in: executionContext)
                guard let holds = outcome as? Bool, holds else {
                    if debug {
                        print("[ATL]     Guard of '\(member.name)' failed - skipping element")
                    }
                    return false
                }
            }
        }
        return true
    }

    /// Binds the source pattern variables of a rule and the rules it extends.
    ///
    /// - Parameters:
    ///   - rule: The rule whose variables are bound
    ///   - sources: The source elements, in source pattern order
    private func bindSourceVariables(of rule: ATLEffectiveMatchedRule, sources: [any EObject]) {
        for member in rule.chain {
            for (pattern, element) in zip(member.sourcePatterns, sources) {
                executionContext.setVariable(pattern.variableName, value: element)
            }
        }
    }

    /// Creates the target elements of a matched rule and records the trace link.
    ///
    /// The `using` variables are evaluated first, so that they are available
    /// to the bindings applied later.
    ///
    /// - Parameter candidate: The matched rule and source elements
    /// - Returns: The pending match awaiting its bindings
    /// - Throws: ATL execution errors for rule execution failures
    private func createTargets(for candidate: MatchCandidate) async throws -> PendingMatch {
        let rule = candidate.rule
        executionContext.pushScope()
        defer { executionContext.popScope() }

        bindSourceVariables(of: rule, sources: candidate.sources)
        var variables: [(name: String, value: (any EcoreValue)?)] = []
        for member in rule.chain {
            for (pattern, element) in zip(member.sourcePatterns, candidate.sources) {
                variables.append((pattern.variableName, element))
            }
        }
        for local in rule.localVariables {
            let value = try await local.expression.evaluate(in: executionContext)
            executionContext.setVariable(local.name, value: value)
            variables.append((local.name, value))
        }

        var targetIDs: [EUUID] = []
        for pattern in rule.targetPatterns {
            targetIDs.append(try await createTargetElement(type: pattern.type).id)
        }

        let ids = candidate.sourceIDs
        executionContext.addTraceLink(
            ATLTraceLink(
                ruleName: rule.rule.name,
                sourceElement: ids[0],
                targetElements: targetIDs,
                additionalSourceElements: Array(ids.dropFirst()),
                targetNames: rule.targetPatterns.map(\.variableName),
                kind: .matched
            ))
        statistics.traceLinksCreated += 1

        return PendingMatch(rule: rule, variables: variables, targetIDs: targetIDs)
    }

    /// Applies the bindings and imperative block of a matched rule.
    ///
    /// - Parameter match: The pending match whose target elements exist
    /// - Throws: ATL execution errors for rule execution failures
    private func apply(_ match: PendingMatch) async throws {
        executionContext.pushScope()
        defer { executionContext.popScope() }

        for (name, value) in match.variables {
            executionContext.setVariable(name, value: value)
        }
        try await applyTargetPatterns(match.rule.targetPatterns, targetIDs: match.targetIDs)
        for statement in match.rule.doStatements {
            try await statement.execute(in: executionContext)
        }
    }

    /// Creates a target element of the given qualified type.
    ///
    /// - Parameter type: The qualified type, such as `Persons!Male`
    /// - Returns: The created target element
    /// - Throws: ATL execution errors for element creation failures
    private func createTargetElement(type: String) async throws -> any EObject {
        let typeComponents = type.split(separator: "!")
        guard typeComponents.count == 2 else {
            throw ATLExecutionError.typeError("Invalid target type specification: '\(type)'")
        }
        let element = try await executionContext.createElement(
            type: type, in: String(typeComponents[0]))
        statistics.elementsCreated += 1
        return element
    }

    /// Binds the target pattern variables and applies the bindings of each pattern.
    ///
    /// - Parameters:
    ///   - patterns: The target patterns
    ///   - targetIDs: The identifiers of the elements created for the patterns
    /// - Throws: ATL execution errors for binding failures
    private func applyTargetPatterns(_ patterns: [ATLEffectiveTargetPattern], targetIDs: [EUUID])
        async throws
    {
        var elements: [any EObject] = []
        for (pattern, id) in zip(patterns, targetIDs) {
            guard let element = await executionContext.findTargetObject(id) else {
                throw ATLExecutionError.runtimeError("Target element \(id) not found")
            }
            elements.append(element)
            executionContext.setVariable(pattern.variableName, value: element)
        }
        for (pattern, element) in zip(patterns, elements) {
            for binding in pattern.bindings {
                try await applyBinding(binding, to: element)
            }
        }
    }

    /// Evaluates a property binding and assigns its value to a target element.
    ///
    /// A binding that cannot be evaluated yet is retried once all rules have
    /// been applied.
    ///
    /// - Parameters:
    ///   - binding: The binding to apply
    ///   - element: The target element to configure
    /// - Throws: ``ATLExecutionError/invalidEnumerationLiteral(_:)`` when the value is
    ///   not a literal of the enumeration the feature is typed by
    private func applyBinding(_ binding: ATLPropertyBinding, to element: any EObject) async throws {
        do {
            let value = try await binding.expression.evaluate(in: executionContext)
            try await executionContext.assignFeature(
                on: element, feature: binding.property, value: value)
        } catch {
            if case ATLExecutionError.invalidEnumerationLiteral = error { throw error }
            if debug {
                print(
                    "[ATL DEBUG] Binding evaluation failed for property '\(binding.property)': \(error)"
                )
                print("[ATL DEBUG]   Creating lazy binding for later resolution")
            }
            executionContext.addLazyBindingWithContext(
                targetElement: element.id,
                property: binding.property,
                expression: binding.expression
            )
        }
    }

    // MARK: - Called Rule Execution

    /// Executes every parameterless called rule selected by a predicate.
    ///
    /// - Parameters:
    ///   - phase: The phase under which progress is reported
    ///   - selection: Decides which called rules run
    /// - Throws: ATL execution errors for rule execution failures
    private func executeCalledRules(
        _ phase: ATLProgressPhase, _ selection: (ATLCalledRule) -> Bool
    ) async throws {
        let selected = module.calledRules.values.filter(selection)
        monitor?.report(phase, completed: 0, total: selected.count)
        for (index, rule) in selected.enumerated() {
            monitor?.report(phase, completed: index, total: selected.count, rule: rule.name)
            try await monitor?.checkpoint()
            _ = try await executeCalledRule(rule.name, arguments: [])
        }
        monitor?.report(phase, completed: selected.count, total: selected.count)
    }

    /// Executes a called rule with the specified parameters.
    ///
    /// Called rules provide imperative transformation capabilities within the
    /// otherwise declarative ATL framework. They are invoked explicitly with
    /// parameters and can create multiple target elements. Target variables are
    /// bound before property bindings are evaluated so references between sibling
    /// target patterns resolve consistently during the same rule invocation.
    ///
    /// A unique rule returns the elements created by its first invocation for an
    /// argument tuple on every later invocation with the same tuple. Lazy and unique
    /// rules record trace links for their source arguments, so that
    /// `resolveTemp` finds their results. When the rule has a `do` section it runs
    /// after the bindings, with the target pattern variables in scope.
    ///
    /// - Parameters:
    ///   - ruleName: The name of the called rule to execute.
    ///   - arguments: The argument values to pass to the rule.
    /// - Returns: The created target elements, or none if a lazy rule's guard fails or
    ///   one of its arguments is undefined.
    /// - Throws: ATL execution errors for rule execution failures.
    public func executeCalledRule(_ ruleName: String, arguments: [(any EcoreValue)?]) async throws
        -> [any EObject]
    {
        guard let rule = module.calledRules[ruleName] else {
            throw ATLExecutionError.invalidOperation("Called rule '\(ruleName)' not found")
        }

        // Verify argument count
        guard arguments.count == rule.parameters.count else {
            throw ATLExecutionError.invalidOperation(
                "Called rule '\(ruleName)' expects \(rule.parameters.count) arguments, got \(arguments.count)"
            )
        }

        // A lazy rule transforms source elements, so an undefined argument yields nothing
        if rule.isLazy, arguments.contains(where: { $0 == nil }) {
            return []
        }

        let uniqueKey = ATLUniqueRuleKey(ruleName: ruleName, arguments: arguments)
        if rule.isUnique, let existing = executionContext.uniqueRuleResult(for: uniqueKey) {
            return await existing.asyncCompactMap { await executionContext.findTargetObject($0) }
        }

        // Create new execution scope
        executionContext.pushScope()
        defer {
            executionContext.popScope()
        }

        // Bind parameters
        for (parameter, argument) in zip(rule.parameters, arguments) {
            executionContext.setVariable(parameter.name, value: argument)
        }

        if let guardExpression = rule.`guard`,
            try await guardExpression.evaluate(in: executionContext) as? Bool != true
        {
            return []
        }

        for local in rule.localVariables {
            let value = try await local.expression.evaluate(in: executionContext)
            executionContext.setVariable(local.name, value: value)
        }

        // Create all target elements first so sibling target variables
        // are available during subsequent property binding.
        var targetIDs: [EUUID] = []
        for targetPattern in rule.targetPatterns {
            targetIDs.append(try await createTargetElement(type: targetPattern.type).id)
        }

        let sourceIDs = arguments.compactMap { ($0 as? (any EObject))?.id }
        if rule.isLazy || rule.isUnique, let first = sourceIDs.first {
            executionContext.addTraceLink(
                ATLTraceLink(
                    ruleName: rule.name,
                    sourceElement: first,
                    targetElements: targetIDs,
                    additionalSourceElements: Array(sourceIDs.dropFirst()),
                    targetNames: rule.targetPatterns.map(\.variableName),
                    kind: .lazy
                ))
            statistics.traceLinksCreated += 1
        }
        // Recorded before the bindings run, so that cyclic invocations find the elements
        if rule.isUnique {
            executionContext.storeUniqueRuleResult(targetIDs, for: uniqueKey)
        }

        try await applyTargetPatterns(
            rule.targetPatterns.map {
                ATLEffectiveTargetPattern(
                    variableName: $0.variableName, type: $0.type, bindings: $0.bindings)
            },
            targetIDs: targetIDs
        )

        // Execute rule body statements
        for statement in rule.body {
            try await statement.execute(in: executionContext)
        }

        statistics.calledRulesExecuted += 1
        return await targetIDs.asyncCompactMap { await executionContext.findTargetObject($0) }
    }

    // MARK: - Validation

    /// Validates that model aliases match module specifications.
    ///
    /// - Parameters:
    ///   - sources: Source models to validate
    ///   - targets: Target models to validate
    /// - Throws: ATL execution errors for mismatched aliases
    private func validateModelAliases(
        sources: OrderedDictionary<String, Resource>,
        targets: OrderedDictionary<String, Resource>
    ) throws {
        // Validate source aliases
        for sourceAlias in module.sourceMetamodels.keys {
            guard sources[sourceAlias] != nil else {
                throw ATLExecutionError.invalidOperation(
                    "Source model '\(sourceAlias)' required by module but not provided"
                )
            }
        }

        // Validate target aliases
        for targetAlias in module.targetMetamodels.keys {
            guard targets[targetAlias] != nil else {
                throw ATLExecutionError.invalidOperation(
                    "Target model '\(targetAlias)' required by module but not provided"
                )
            }
        }
    }

    // MARK: - Statistics Access

    /// Retrieves current execution statistics.
    ///
    /// - Returns: The current execution statistics
    public func getStatistics() -> ATLExecutionStatistics {
        return statistics
    }
}

// MARK: - ATL Execution Statistics

/// Statistics tracking ATL transformation execution performance and behaviour.
/// Comprehensive execution statistics for ATL transformation monitoring.
///
/// The `ATLExecutionStatistics` structure provides detailed metrics about
/// transformation execution, including performance timing, memory usage,
/// rule invocation patterns, and element processing metrics for debugging
/// and optimisation purposes.
public struct ATLExecutionStatistics: Sendable {

    // MARK: - Properties

    /// Unique identifier for this execution session
    public var executionId: UUID?

    /// The total execution time for the transformation.
    public var executionTime: TimeInterval = 0

    /// Execution start time
    public var startTime: Date?

    /// Execution end time
    public var endTime: Date?

    /// Whether the transformation completed successfully.
    public var successful: Bool = false

    /// The number of matched rules executed.
    public var rulesExecuted: Int = 0

    /// The number of called rules executed.
    public var calledRulesExecuted: Int = 0

    /// The number of source elements processed.
    public var elementsProcessed: Int = 0

    /// The number of target elements created.
    public var elementsCreated: Int = 0

    /// The number of trace links recorded.
    public var traceLinksCreated: Int = 0

    /// The number of lazy bindings resolved.
    public var lazyBindingsResolved: Int = 0

    /// The number of helper functions invoked.
    public var helperInvocations: Int = 0

    /// The number of navigation operations performed.
    public var navigationOperations: Int = 0

    /// Peak memory usage during execution (estimated).
    public var peakMemoryUsage: Int = 0

    /// Rule execution times for performance analysis.
    public var ruleExecutionTimes: [String: TimeInterval] = [:]

    /// Helper execution times for performance analysis.
    public var helperExecutionTimes: [String: TimeInterval] = [:]

    /// Phase execution times.
    public var phaseExecutionTimes: [String: TimeInterval] = [:]

    /// The last error encountered during execution, if any.
    public var lastError: Error?

    /// Execution phases completed
    public var completedPhases: Set<String> = []

    /// Current execution phase
    public var currentPhase: String?

    /// Warnings accumulated during execution
    public var warnings: [String] = []

    /// Performance metrics
    public var performanceMetrics: ATLPerformanceMetrics = ATLPerformanceMetrics()

    // MARK: - Initialisation

    /// Creates new execution statistics with default values.
    public init() {}

    // MARK: - Lifecycle Management

    /// Begins execution with the specified identifier.
    ///
    /// - Parameter id: Unique execution identifier
    public mutating func beginExecution(id: UUID) {
        executionId = id
        startTime = Date()
        reset()
        currentPhase = "initialisation"
        performanceMetrics.reset()
    }

    /// Completes execution with success status and optional error.
    ///
    /// - Parameters:
    ///   - success: Whether execution completed successfully
    ///   - error: Optional error if execution failed
    public mutating func completeExecution(success: Bool, error: Error? = nil) {
        endTime = Date()
        successful = success
        lastError = error
        currentPhase = nil

        if let start = startTime, let end = endTime {
            executionTime = end.timeIntervalSince(start)
        }

        performanceMetrics.finalize()
    }

    /// Begins a new execution phase.
    ///
    /// - Parameter phase: Phase name
    public mutating func beginPhase(_ phase: String) {
        if let current = currentPhase {
            endPhase(current)
        }
        currentPhase = phase
        phaseExecutionTimes[phase] = Date().timeIntervalSinceReferenceDate
    }

    /// Ends the current execution phase.
    ///
    /// - Parameter phase: Phase name to end
    public mutating func endPhase(_ phase: String) {
        if let startTime = phaseExecutionTimes[phase] {
            let duration = Date().timeIntervalSinceReferenceDate - startTime
            phaseExecutionTimes[phase] = duration
            completedPhases.insert(phase)
        }

        if currentPhase == phase {
            currentPhase = nil
        }
    }

    /// Records rule execution time.
    ///
    /// - Parameters:
    ///   - ruleName: Name of the executed rule
    ///   - duration: Execution duration
    public mutating func recordRuleExecution(_ ruleName: String, duration: TimeInterval) {
        ruleExecutionTimes[ruleName, default: 0] += duration
        performanceMetrics.recordRuleExecution(ruleName, duration: duration)
    }

    /// Records helper invocation time.
    ///
    /// - Parameters:
    ///   - helperName: Name of the invoked helper
    ///   - duration: Execution duration
    public mutating func recordHelperInvocation(_ helperName: String, duration: TimeInterval) {
        helperExecutionTimes[helperName, default: 0] += duration
        helperInvocations += 1
        performanceMetrics.recordHelperInvocation(helperName, duration: duration)
    }

    /// Adds a warning message.
    ///
    /// - Parameter message: Warning message
    public mutating func addWarning(_ message: String) {
        warnings.append(message)
    }

    /// Records a navigation operation.
    public mutating func recordNavigation() {
        navigationOperations += 1
        performanceMetrics.recordNavigation()
    }

    /// Updates peak memory usage estimate.
    ///
    /// - Parameter usage: Current memory usage estimate
    public mutating func updateMemoryUsage(_ usage: Int) {
        if usage > peakMemoryUsage {
            peakMemoryUsage = usage
        }
    }

    // MARK: - Statistics Management

    /// Resets all statistics to their initial values.
    public mutating func reset() {
        executionTime = 0
        successful = false
        rulesExecuted = 0
        calledRulesExecuted = 0
        elementsProcessed = 0
        elementsCreated = 0
        traceLinksCreated = 0
        lazyBindingsResolved = 0
        helperInvocations = 0
        navigationOperations = 0
        peakMemoryUsage = 0
        lastError = nil
        ruleExecutionTimes.removeAll()
        helperExecutionTimes.removeAll()
        phaseExecutionTimes.removeAll()
        completedPhases.removeAll()
        currentPhase = nil
        warnings.removeAll()
        performanceMetrics.reset()
    }

    /// Provides a formatted summary of execution statistics.
    ///
    /// - Returns: A human-readable statistics summary
    public func summary() -> String {
        let status = successful ? "✅ Success" : "❌ Failed"
        let duration = String(format: "%.3f", executionTime * 1000)
        let memoryMB = String(format: "%.2f", Double(peakMemoryUsage) / (1024 * 1024))

        var summary = """
            ATL Execution Summary:
            Status: \(status)
            Duration: \(duration)ms
            Peak Memory: \(memoryMB)MB
            Rules Executed: \(rulesExecuted)
            Called Rules: \(calledRulesExecuted)
            Elements Processed: \(elementsProcessed)
            Elements Created: \(elementsCreated)
            Trace Links: \(traceLinksCreated)
            Lazy Bindings: \(lazyBindingsResolved)
            Helper Invocations: \(helperInvocations)
            Navigation Operations: \(navigationOperations)
            """

        if !warnings.isEmpty {
            summary += "\nWarnings (\(warnings.count)):"
            for warning in warnings.prefix(5) {
                summary += "\n  - \(warning)"
            }
            if warnings.count > 5 {
                summary += "\n  ... and \(warnings.count - 5) more"
            }
        }

        if let error = lastError {
            summary += "\nLast Error: \(error.localizedDescription)"
        }

        return summary
    }

    /// Provides detailed performance breakdown.
    ///
    /// - Returns: Detailed performance analysis
    public func detailedSummary() -> String {
        var details = summary()

        details += "\n\nPhase Execution Times:"
        for (phase, duration) in phaseExecutionTimes.sorted(by: { $0.key < $1.key }) {
            let durationMs = String(format: "%.3f", duration * 1000)
            details += "\n  \(phase): \(durationMs)ms"
        }

        if !ruleExecutionTimes.isEmpty {
            details += "\n\nTop Rule Execution Times:"
            let topRules = ruleExecutionTimes.sorted { $0.value > $1.value }.prefix(10)
            for (rule, duration) in topRules {
                let durationMs = String(format: "%.3f", duration * 1000)
                details += "\n  \(rule): \(durationMs)ms"
            }
        }

        if !helperExecutionTimes.isEmpty {
            details += "\n\nTop Helper Execution Times:"
            let topHelpers = helperExecutionTimes.sorted { $0.value > $1.value }.prefix(10)
            for (helper, duration) in topHelpers {
                let durationMs = String(format: "%.3f", duration * 1000)
                details += "\n  \(helper): \(durationMs)ms"
            }
        }

        details += "\n\nPerformance Metrics:"
        details += performanceMetrics.summary()

        return details
    }

    /// Returns execution efficiency metrics.
    ///
    /// - Returns: Efficiency analysis
    public func efficiency() -> String {
        guard executionTime > 0 else { return "No execution data available" }

        let elementsPerSecond = Double(elementsProcessed) / executionTime
        let creationRate = Double(elementsCreated) / executionTime
        let bindingResolutionRate =
            lazyBindingsResolved > 0 ? Double(lazyBindingsResolved) / executionTime : 0

        return """
            Execution Efficiency:
            Elements/sec: \(String(format: "%.2f", elementsPerSecond))
            Creation Rate: \(String(format: "%.2f", creationRate)) elements/sec
            Binding Resolution: \(String(format: "%.2f", bindingResolutionRate)) bindings/sec
            Memory Efficiency: \(String(format: "%.2f", Double(elementsCreated) * 1024 / Double(max(peakMemoryUsage, 1)))) elements/KB
            """
    }
}

/// Performance metrics for detailed analysis.
public struct ATLPerformanceMetrics: Sendable {

    /// Rule performance data
    public var ruleMetrics: [String: RuleMetrics] = [:]

    /// Helper performance data
    public var helperMetrics: [String: HelperMetrics] = [:]

    /// Navigation performance
    public var navigationMetrics = NavigationMetrics()

    /// Memory allocation tracking
    public var memoryMetrics = MemoryMetrics()

    /// Resets all metrics
    public mutating func reset() {
        ruleMetrics.removeAll()
        helperMetrics.removeAll()
        navigationMetrics = NavigationMetrics()
        memoryMetrics = MemoryMetrics()
    }

    /// Finalizes metrics calculations
    public mutating func finalize() {
        // Perform any final calculations
        for (name, var metrics) in ruleMetrics {
            metrics.finalize()
            ruleMetrics[name] = metrics
        }

        for (name, var metrics) in helperMetrics {
            metrics.finalize()
            helperMetrics[name] = metrics
        }

        navigationMetrics.finalize()
        memoryMetrics.finalize()
    }

    /// Records rule execution
    public mutating func recordRuleExecution(_ ruleName: String, duration: TimeInterval) {
        if ruleMetrics[ruleName] == nil {
            ruleMetrics[ruleName] = RuleMetrics()
        }
        ruleMetrics[ruleName]!.recordExecution(duration: duration)
    }

    /// Records helper invocation
    public mutating func recordHelperInvocation(_ helperName: String, duration: TimeInterval) {
        if helperMetrics[helperName] == nil {
            helperMetrics[helperName] = HelperMetrics()
        }
        helperMetrics[helperName]!.recordInvocation(duration: duration)
    }

    /// Records navigation operation
    public mutating func recordNavigation() {
        navigationMetrics.recordOperation()
    }

    /// Returns summary of performance metrics
    public func summary() -> String {
        var summary = ""

        if !ruleMetrics.isEmpty {
            summary += "\n  Rule Performance:"
            let topRules = ruleMetrics.sorted {
                $0.value.averageDuration > $1.value.averageDuration
            }.prefix(5)
            for (name, metrics) in topRules {
                summary += "\n    \(name): \(metrics.summary())"
            }
        }

        if !helperMetrics.isEmpty {
            summary += "\n  Helper Performance:"
            let topHelpers = helperMetrics.sorted {
                $0.value.averageDuration > $1.value.averageDuration
            }.prefix(5)
            for (name, metrics) in topHelpers {
                summary += "\n    \(name): \(metrics.summary())"
            }
        }

        summary += "\n  Navigation: \(navigationMetrics.summary())"
        summary += "\n  Memory: \(memoryMetrics.summary())"

        return summary
    }

    /// Rule-specific performance metrics
    public struct RuleMetrics: Sendable {
        public var executionCount: Int = 0
        public var totalDuration: TimeInterval = 0
        public var minDuration: TimeInterval = .greatestFiniteMagnitude
        public var maxDuration: TimeInterval = 0
        public var averageDuration: TimeInterval = 0

        public mutating func recordExecution(duration: TimeInterval) {
            executionCount += 1
            totalDuration += duration
            minDuration = min(minDuration, duration)
            maxDuration = max(maxDuration, duration)
        }

        public mutating func finalize() {
            averageDuration = executionCount > 0 ? totalDuration / Double(executionCount) : 0
            if minDuration == .greatestFiniteMagnitude {
                minDuration = 0
            }
        }

        public func summary() -> String {
            let avgMs = String(format: "%.3f", averageDuration * 1000)
            let minMs = String(format: "%.3f", minDuration * 1000)
            let maxMs = String(format: "%.3f", maxDuration * 1000)
            return "\(executionCount) executions, avg: \(avgMs)ms, range: \(minMs)-\(maxMs)ms"
        }
    }

    /// Helper-specific performance metrics
    public struct HelperMetrics: Sendable {
        public var invocationCount: Int = 0
        public var totalDuration: TimeInterval = 0
        public var averageDuration: TimeInterval = 0

        public mutating func recordInvocation(duration: TimeInterval) {
            invocationCount += 1
            totalDuration += duration
        }

        public mutating func finalize() {
            averageDuration = invocationCount > 0 ? totalDuration / Double(invocationCount) : 0
        }

        public func summary() -> String {
            let avgMs = String(format: "%.3f", averageDuration * 1000)
            return "\(invocationCount) calls, avg: \(avgMs)ms"
        }
    }

    /// Navigation performance metrics
    public struct NavigationMetrics: Sendable {
        public var operationCount: Int = 0
        public var averageOperationsPerSecond: Double = 0
        private var startTime = Date()

        public mutating func recordOperation() {
            operationCount += 1
        }

        public mutating func finalize() {
            let duration = Date().timeIntervalSince(startTime)
            if duration > 0 {
                averageOperationsPerSecond = Double(operationCount) / duration
            }
        }

        public func summary() -> String {
            let opsPerSec = String(format: "%.2f", averageOperationsPerSecond)
            return "\(operationCount) operations, \(opsPerSec) ops/sec"
        }
    }

    /// Memory usage metrics
    public struct MemoryMetrics: Sendable {
        public var allocationCount: Int = 0
        public var totalAllocatedBytes: Int = 0
        public var peakUsage: Int = 0

        public mutating func finalize() {
            // Memory metrics would be populated by the execution engine
        }

        public func summary() -> String {
            let totalMB = String(format: "%.2f", Double(totalAllocatedBytes) / (1024 * 1024))
            let peakMB = String(format: "%.2f", Double(peakUsage) / (1024 * 1024))
            return "Total: \(totalMB)MB, Peak: \(peakMB)MB"
        }
    }
}

// MARK: - Asynchronous Sequence Helpers

extension Sequence {

    /// Maps each element asynchronously and keeps the non-`nil` results in order.
    ///
    /// - Parameter transform: The asynchronous transformation
    /// - Returns: The non-`nil` transformed values
    @MainActor
    fileprivate func asyncCompactMap<T>(_ transform: @MainActor (Element) async -> T?) async -> [T] {
        var result: [T] = []
        for element in self {
            if let value = await transform(element) {
                result.append(value)
            }
        }
        return result
    }
}
