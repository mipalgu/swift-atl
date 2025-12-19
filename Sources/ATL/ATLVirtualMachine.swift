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

    // MARK: - Initialisation

    /// Creates a new ATL virtual machine for the specified module.
    ///
    /// - Parameter module: The ATL module to execute
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
    }

    // MARK: - Debug Configuration

    /// Enable or disable debug output for systematic tracing.
    ///
    /// When enabled, the virtual machine prints detailed trace information
    /// for rule execution, helper evaluation, and transformation progress.
    ///
    /// - Parameter enabled: Whether to enable debug output
    public func enableDebug(_ enabled: Bool = true) {
        debug = enabled
        executionContext.debug = enabled
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
    /// - Throws: ATL execution errors for transformation failures
    ///
    /// - Note: Source and target model aliases must match the module's metamodel specifications
    public func execute(
        sources: OrderedDictionary<String, Resource>,
        targets: OrderedDictionary<String, Resource>
    ) async throws {
        if debug {
            print("[ATL] Executing transformation: \(module.name)")
            print("[ATL] Source models: \(sources.keys.joined(separator: ", "))")
            print("[ATL] Target models: \(targets.keys.joined(separator: ", "))")
        }

        statistics.reset()
        let startTime = Date()

        // Validate model aliases against module specifications
        try validateModelAliases(sources: sources, targets: targets)

        // Configure execution context with models
        for (alias, resource) in sources {
            executionContext.addSource(alias, resource: resource)
        }
        for (alias, resource) in targets {
            executionContext.addTarget(alias, resource: resource)
        }

        do {
            // Execute matched rules for all applicable source elements
            try await executeMatchedRules()

            // Resolve lazy bindings for forward references
            try await executionContext.resolveLazyBindings()

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

    /// Executes all matched rules for applicable source elements.
    ///
    /// Matched rule execution involves iterating through all source model elements,
    /// testing rule applicability, and executing transformation logic for matching elements.
    ///
    /// - Throws: ATL execution errors for rule execution failures
    private func executeMatchedRules() async throws {
        for rule in module.matchedRules {
            try await executeMatchedRule(rule)
        }
    }

    /// Executes a specific matched rule for all applicable source elements.
    ///
    /// - Parameter rule: The matched rule to execute
    /// - Throws: ATL execution errors for rule execution failures
    private func executeMatchedRule(_ rule: ATLMatchedRule) async throws {
        if debug {
            print("[ATL] Executing rule: \(rule.name)")
        }

        statistics.rulesExecuted += 1

        // Parse source pattern to determine element type and namespace
        let typeComponents = rule.sourcePattern.type.split(separator: "!")
        guard typeComponents.count == 2 else {
            throw ATLExecutionError.typeError(
                "Invalid source type specification: '\(rule.sourcePattern.type)'"
            )
        }

        let metamodelName = String(typeComponents[0])
        let sourceClassName = String(typeComponents[1])

        if debug {
            print("[ATL]   Source type: \(metamodelName)!\(sourceClassName)")
        }

        // Find the model alias that uses this metamodel
        guard let modelAlias = module.sourceMetamodels.first(where: { $0.value.name == metamodelName })?.key else {
            throw ATLExecutionError.invalidOperation("No source model found for metamodel '\(metamodelName)'")
        }

        // Get source resource using the model alias
        guard let sourceResource = executionContext.getSource(modelAlias) else {
            throw ATLExecutionError.invalidOperation("Source model '\(modelAlias)' not found")
        }

        // Get source metamodel using the model alias
        guard let sourceMetamodel = module.sourceMetamodels[modelAlias] else {
            throw ATLExecutionError.invalidOperation("Source metamodel '\(modelAlias)' not found")
        }

        // Find source class
        guard let sourceClass = sourceMetamodel.getClassifier(sourceClassName) as? EClass else {
            throw ATLExecutionError.typeError(
                "Class '\(sourceClassName)' not found in metamodel '\(metamodelName)'"
            )
        }

        // Get all elements of the specified type
        let sourceElements = await sourceResource.getAllInstancesOf(sourceClass)

        // Execute rule for each matching element
        for sourceElement in sourceElements {
            try await executeRuleForElement(rule, sourceElement: sourceElement)
            statistics.elementsProcessed += 1
        }
    }

    /// Executes a matched rule for a specific source element.
    ///
    /// - Parameters:
    ///   - rule: The matched rule to execute
    ///   - sourceElement: The source element to transform
    /// - Throws: ATL execution errors for rule execution failures
    private func executeRuleForElement(_ rule: ATLMatchedRule, sourceElement: any EObject)
        async throws
    {
        if debug {
            print("[ATL]   Checking rule '\(rule.name)' for element: \(sourceElement.eClass.name)")
        }

        // Create new execution scope for rule
        executionContext.pushScope()
        defer {
            Task {
                executionContext.popScope()
            }
        }

        // Bind source element to pattern variable
        executionContext.setVariable(rule.sourcePattern.variableName, value: sourceElement)

        // Evaluate guard condition if present
        if let guardExpression = rule.`guard` {
            if debug {
                print("[ATL]     Evaluating guard...")
            }

            do {
                let guardResult = try await guardExpression.evaluate(in: executionContext)
                guard let guardBool = guardResult as? Bool, guardBool else {
                    if debug {
                        print("[ATL]     Guard failed - skipping element")
                    }
                    return  // Guard failed, skip rule execution
                }

                if debug {
                    print("[ATL]     Guard passed")
                }
            } catch {
                if debug {
                    print("[ATL]     Guard evaluation error: \(error)")
                }
                throw error
            }
        }

        // Create target elements for each target pattern
        var createdElements: [EUUID] = []

        for targetPattern in rule.targetPatterns {
            let targetElement = try await createTargetElement(targetPattern)
            createdElements.append(targetElement.id)

            // Bind target element to pattern variable
            executionContext.setVariable(targetPattern.variableName, value: targetElement)

            // Apply property bindings
            try await applyPropertyBindings(targetPattern, targetElement: targetElement)
        }

        // Record trace link
        executionContext.addTraceLink(
            ruleName: rule.name,
            sourceElement: sourceElement.id,
            targetElements: createdElements
        )
    }

    /// Creates a target element according to the target pattern specification.
    ///
    /// - Parameter pattern: The target pattern defining element creation
    /// - Returns: The created target element
    /// - Throws: ATL execution errors for element creation failures
    private func createTargetElement(_ pattern: ATLTargetPattern) async throws -> any EObject {
        // Parse target type specification
        let typeComponents = pattern.type.split(separator: "!")
        guard typeComponents.count == 2 else {
            throw ATLExecutionError.typeError(
                "Invalid target type specification: '\(pattern.type)'"
            )
        }

        let targetAlias = String(typeComponents[0])

        return try await executionContext.createElement(type: pattern.type, in: targetAlias)
    }

    /// Applies property bindings to a target element.
    ///
    /// - Parameters:
    ///   - pattern: The target pattern containing property bindings
    ///   - targetElement: The target element to configure
    /// - Throws: ATL execution errors for binding failures
    private func applyPropertyBindings(_ pattern: ATLTargetPattern, targetElement: any EObject)
        async throws
    {
        for binding in pattern.bindings {
            do {
                let propertyValue = try await binding.expression.evaluate(in: executionContext)
                try setElementProperty(
                    targetElement, property: binding.property, value: propertyValue)
            } catch {
                // For forward references, create lazy binding
                let lazyBinding = ATLLazyBinding(
                    targetElement: targetElement.id,
                    property: binding.property,
                    expression: binding.expression
                )
                executionContext.addLazyBinding(lazyBinding)
            }
        }
    }

    /// Sets a property value on a target element.
    ///
    /// - Parameters:
    ///   - element: The target element to modify
    ///   - property: The property name to set
    ///   - value: The property value to assign
    /// - Throws: ATL execution errors for invalid property operations
    private func setElementProperty(_ element: any EObject, property: String, value: Any?) throws {
        guard let eClass = element.eClass as? EClass else {
            throw ATLExecutionError.typeError(
                "Element eClass is not an EClass: \(type(of: element.eClass))"
            )
        }

        guard let feature = eClass.getStructuralFeature(name: property) else {
            throw ATLExecutionError.invalidOperation(
                "Property '\(property)' not found in class '\(eClass.name)'"
            )
        }

        var mutableElement = element
        mutableElement.eSet(feature, value as? (any EcoreValue))
    }

    // MARK: - Called Rule Execution

    /// Executes a called rule with the specified parameters.
    ///
    /// Called rules provide imperative transformation capabilities within the
    /// otherwise declarative ATL framework. They are invoked explicitly with
    /// parameters and can create multiple target elements.
    ///
    /// - Parameters:
    ///   - ruleName: The name of the called rule to execute
    ///   - arguments: The argument values to pass to the rule
    /// - Returns: The created target elements
    /// - Throws: ATL execution errors for rule execution failures
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

        // Create new execution scope
        executionContext.pushScope()
        defer {
            Task {
                executionContext.popScope()
            }
        }

        // Bind parameters
        for (parameter, argument) in zip(rule.parameters, arguments) {
            executionContext.setVariable(parameter.name, value: argument)
        }

        // Create target elements
        var createdElements: [any EObject] = []
        for targetPattern in rule.targetPatterns {
            let targetElement = try await createTargetElement(targetPattern)
            createdElements.append(targetElement)

            // Bind target element variable
            executionContext.setVariable(targetPattern.variableName, value: targetElement)

            // Apply property bindings
            try await applyPropertyBindings(targetPattern, targetElement: targetElement)
        }

        // Execute rule body statements
        for statement in rule.body {
            try await statement.execute(in: executionContext)
        }

        statistics.calledRulesExecuted += 1
        return createdElements
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
