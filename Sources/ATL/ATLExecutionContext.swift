//
//  ATLExecutionContext.swift
//  ATL
//
//  Created by Rene Hexel on 8/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import OrderedCollections

/// Execution context for ATL transformations, coordinating between ATL constructs and the ECore execution framework.
///
/// The ATL execution context serves as the main coordination layer for ATL transformations,
/// delegating heavy computational operations to the underlying `ECoreExecutionEngine` while
/// managing ATL-specific state such as helpers, rules, and trace links on the MainActor.
///
/// ## Architecture
///
/// Following the established swift-ecore pattern:
/// - **Coordination**: Handled on `@MainActor` for UI integration and command compatibility
/// - **Computation**: Delegated to `ECoreExecutionEngine` actor for performance
/// - **Commands**: Integrated with EMF command framework for undo/redo support
///
/// ## Integration with ECore
///
/// The context bridges ATL concepts to ECore fundamentals:
/// - ATL expressions → ECore expressions via ATLECoreBridge
/// - ATL models → ECore IModel interface via ATLModelAdapters
/// - ATL operations → ECoreExecutionEngine delegated calls
/// - ATL helpers → Runtime behavior injection
///
/// ## Example Usage
///
/// ```swift
/// let context = ATLExecutionContext(
///     module: atlModule,
///     sources: ["IN": sourceModel],
///     targets: ["OUT": targetModel],
///     executionEngine: engine
/// )
///
/// let result = try await context.evaluateHelper("myHelper", arguments: [value])
/// ```
@MainActor
public final class ATLExecutionContext: Sendable {

    // MARK: - Properties

    /// The ATL module being executed.
    public let module: ATLModule

    /// Source models indexed by their aliases.
    public private(set) var sources: OrderedDictionary<String, Resource>

    /// Target models indexed by their aliases.
    public private(set) var targets: OrderedDictionary<String, Resource>

    /// Variable bindings in the current execution scope.
    private var variables: [String: (any EcoreValue)?] = [:]

    /// Scope stack for nested variable contexts.
    private var scopeStack: [[String: (any EcoreValue)?]] = []

    /// Trace links between source and target elements.
    private var traceLinks: [ATLTraceLink] = []

    /// Lazy bindings waiting for resolution.
    private var lazyBindings: [ATLLazyBinding] = []

    /// Helper functions registered for this context.
    private var helpers: [String: any ATLHelperType] = [:]

    /// Error context for tracking issues during execution.
    private var errorContext: ATLErrorContext = ATLErrorContext()

    /// The underlying ECore execution engine for heavy computation.
    public let executionEngine: ECoreExecutionEngine

    /// Optional command stack for undo/redo support.
    private let commandStack: CommandStack?

    /// Debug mode flag for systematic tracing.
    public var debug: Bool = false

    // MARK: - Initialisation

    /// Creates a new ATL execution context.
    ///
    /// - Parameters:
    ///   - module: The ATL module to execute
    ///   - sources: Source models indexed by alias
    ///   - targets: Target models indexed by alias
    ///   - executionEngine: The ECore execution engine to delegate to
    ///   - commandStack: Optional command stack for undo/redo support
    public init(
        module: ATLModule,
        sources: OrderedDictionary<String, Resource> = [:],
        targets: OrderedDictionary<String, Resource> = [:],
        executionEngine: ECoreExecutionEngine,
        commandStack: CommandStack? = nil
    ) {
        self.module = module
        self.sources = sources
        self.targets = targets
        self.executionEngine = executionEngine
        self.commandStack = commandStack

        // Register module helpers
        for (name, helper) in module.helpers {
            self.helpers[name] = helper
        }
    }

    // MARK: - Variable Management

    /// Set a variable value in the current scope.
    ///
    /// - Parameters:
    ///   - name: Variable name
    ///   - value: Variable value
    public func setVariable(_ name: String, value: (any EcoreValue)?) {
        if debug {
            print("[SCOPE DEBUG] Setting variable '\(name)' in current scope (depth: \(scopeStack.count))")
        }
        variables[name] = value
    }

    /// Get a variable value from the current scope or scope stack.
    ///
    /// - Parameter name: Variable name
    /// - Returns: Variable value if found
    /// - Throws: `ATLExecutionError` if variable not found
    public func getVariable(_ name: String) throws -> (any EcoreValue)? {
        if debug {
            print("[SCOPE DEBUG] Getting variable '\(name)' (depth: \(scopeStack.count), current vars: \(variables.keys.sorted()), stack vars: \(scopeStack.map { $0.keys.sorted() }))")
        }

        // Check current scope first
        if let value = variables[name] {
            if debug {
                print("[SCOPE DEBUG]   Found '\(name)' in current scope")
            }
            return value
        }

        // Check scope stack
        for (index, scope) in scopeStack.reversed().enumerated() {
            if let value = scope[name] {
                if debug {
                    print("[SCOPE DEBUG]   Found '\(name)' in stack at depth \(scopeStack.count - index - 1)")
                }
                return value
            }
        }

        if debug {
            print("[SCOPE DEBUG]   Variable '\(name)' NOT FOUND")
        }
        throw ATLExecutionError.variableNotFound(name)
    }

    /// Push a new variable scope onto the stack.
    public func pushScope() {
        if debug {
            print("[SCOPE DEBUG] Pushing scope (current vars: \(variables.keys.sorted())) -> depth will be \(scopeStack.count + 1)")
        }
        scopeStack.append(variables)
        variables = [:]
    }

    /// Pop the current variable scope from the stack.
    public func popScope() {
        if debug {
            print("[SCOPE DEBUG] Popping scope (current vars: \(variables.keys.sorted())) depth \(scopeStack.count) -> \(scopeStack.count - 1)")
        }
        guard !scopeStack.isEmpty else { return }
        variables = scopeStack.removeLast()
        if debug {
            print("[SCOPE DEBUG]   Restored vars: \(variables.keys.sorted())")
        }
    }

    // MARK: - Model Management

    /// Add a source model to the context.
    ///
    /// - Parameters:
    ///   - alias: Model alias
    ///   - resource: Model resource
    public func addSource(_ alias: String, resource: Resource) async {
        sources[alias] = resource

        // Create IModel wrapper and register with execution engine
        let referenceModel = module.sourceMetamodels[alias]!
        let ecoreRefModel = EcoreReferenceModel(rootPackage: referenceModel, resource: Resource())
        let model = EcoreModel(resource: resource, referenceModel: ecoreRefModel, isTarget: false)
        await executionEngine.registerModel(model, alias: alias)
    }

    /// Add a target model to the context.
    ///
    /// - Parameters:
    ///   - alias: Model alias
    ///   - resource: Model resource
    public func addTarget(_ alias: String, resource: Resource) async {
        targets[alias] = resource

        // Create IModel wrapper and register with execution engine
        let referenceModel = module.targetMetamodels[alias]!
        let ecoreRefModel = EcoreReferenceModel(rootPackage: referenceModel, resource: Resource())
        let model = EcoreModel(resource: resource, referenceModel: ecoreRefModel, isTarget: true)
        await executionEngine.registerModel(model, alias: alias)
    }

    /// Get a source model by alias.
    ///
    /// - Parameter alias: Model alias
    /// - Returns: Model resource if found
    public func getSource(_ alias: String) -> Resource? {
        return sources[alias]
    }

    /// Get a target model by alias.
    ///
    /// - Parameter alias: Model alias
    /// - Returns: Model resource if found
    public func getTarget(_ alias: String) -> Resource? {
        return targets[alias]
    }

    // MARK: - Navigation Operations (Delegated to ExecutionEngine)

    /// Navigate a property from a source object using the execution engine.
    ///
    /// Navigate to a property on an object.
    ///
    /// - Parameters:
    ///   - object: Source object
    ///   - property: Property name
    /// - Returns: Navigation result
    /// - Throws: `ECoreExecutionError` if navigation fails
    public func navigate(from object: (any EcoreValue)?, property: String) async throws -> (
        any EcoreValue
    )? {
        guard let eObject = object as? (any EObject) else {
            let objectType = object != nil ? String(reflecting: type(of: object!)) : "nil"
            throw ATLExecutionError.typeError("Source is not an EObject of type: \(objectType)")
        }

        // First try ECore navigation for actual properties
        do {
            return try await executionEngine.navigate(from: eObject, property: property)
        } catch {
            // If ECore navigation fails, try contextual helper fallback
            if let helper = module.helpers[property] as? ATLHelperWrapper,
                helper.contextType != nil
            {

                if debug {
                    print(
                        "[ATL DEBUG] Property '\(property)' not found, trying contextual helper fallback"
                    )
                }

                // Context helper - bind receiver as 'self' and evaluate directly
                pushScope()
                defer { popScope() }

                // Bind receiver as 'self'
                setVariable("self", value: object)

                // Bind parameters (contextual helpers typically have no parameters)
                for (parameter, _) in zip(helper.parameters, []) {
                    setVariable(parameter.name, value: nil)
                }

                // Evaluate the helper body expression
                return try await helper.bodyExpression.evaluate(in: self)
            }

            // Neither property nor helper found, rethrow original error
            throw error
        }
    }

    // MARK: - Helper Management

    /// Call a helper function with arguments.
    ///
    /// - Parameters:
    ///   - name: Helper name
    ///   - arguments: Helper arguments
    /// - Returns: Helper result
    /// - Throws: `ATLExecutionError` if helper call fails
    public func callHelper(_ name: String, arguments: [(any EcoreValue)?]) async throws -> (
        any EcoreValue
    )? {
        guard let helper = helpers[name] else {
            throw ATLExecutionError.helperNotFound(name)
        }

        // Debug: Show current variables before pushing scope (if debug enabled)
        if debug {
            let currentVars = variables.keys.sorted()
            print("[ATL DEBUG] Helper '\(name)' called - current variables: \(currentVars)")
            print("[ATL DEBUG] Scope stack depth: \(scopeStack.count)")
        }

        // Push new scope for helper execution
        pushScope()
        defer { popScope() }

        // Bind parameters
        for (index, parameter) in helper.parameters.enumerated() {
            if index < arguments.count {
                setVariable(parameter.name, value: arguments[index])
            }
        }

        // Evaluate helper expression using ECore bridge
        guard let helperWrapper = helper as? ATLHelperWrapper else {
            throw ATLExecutionError.runtimeError("Helper '\(name)' is not a supported helper type")
        }

        let ecoreExpression = helperWrapper.bodyExpression.toECoreExpression()
        let context = try buildECoreContext()
        if debug {
            print("[ATL DEBUG] ECore context keys: \(context.keys.sorted())")
        }
        let result = try await executionEngine.evaluate(ecoreExpression, context: context)

        return result
    }

    /// Register a helper function.
    ///
    /// - Parameter helper: Helper to register
    public func registerHelper(_ helper: any ATLHelperType) {
        helpers[helper.name] = helper
    }

    // MARK: - Element Creation (Command-Based)

    /// Create a new element in a target model using commands.
    ///
    /// - Parameters:
    ///   - type: Element type name
    ///   - targetAlias: Target model alias
    /// - Returns: Created element
    /// - Throws: `ATLExecutionError` if creation fails
    public func createElement(type: String, in metamodelName: String) async throws -> any EObject {
        // Parse the type specification
        let (parsedMetamodel, typeName) = parseQualifiedTypeName(type)
        let actualMetamodelName = parsedMetamodel ?? metamodelName

        // Find the model alias that uses this metamodel
        guard
            let modelAlias = module.targetMetamodels.first(where: {
                $0.value.name == actualMetamodelName
            })?.key
        else {
            throw ATLExecutionError.invalidOperation(
                "No target model found for metamodel '\(actualMetamodelName)'")
        }

        guard let targetResource = targets[modelAlias] else {
            throw ATLExecutionError.runtimeError("Target model '\(modelAlias)' not found")
        }

        // Find the EClass for the type
        let eClass = try findEClass(name: typeName, in: modelAlias)

        // Get the target metamodel for this model alias
        guard let targetMetamodel = module.targetMetamodels[modelAlias] else {
            throw ATLExecutionError.invalidOperation(
                "No target metamodel found for model '\(modelAlias)'")
        }

        // Create the element using the factory
        let factory = targetMetamodel.eFactoryInstance
        let element = factory.create(eClass)

        // Add element to target resource directly
        // Command stack integration would need a proper container object
        await targetResource.add(element)

        return element
    }

    // MARK: - Query Operations (Delegated to ExecutionEngine)

    /// Find all elements of a given type using the execution engine.
    ///
    /// - Parameter typeName: Type name to search for
    /// - Returns: Array of matching elements
    /// - Throws: `ATLExecutionError` if query fails
    public func findElementsOfType(_ typeName: String) async throws -> [any EObject] {
        let eClass = try findEClass(name: typeName)
        return await executionEngine.allInstancesOf(eClass)
    }

    // MARK: - Trace Management

    /// Add a trace link between source and target elements.
    ///
    /// - Parameters:
    ///   - ruleName: Name of the rule creating the link
    ///   - sourceElement: Source element ID
    ///   - targetElements: Target element IDs
    public func addTraceLink(ruleName: String, sourceElement: EUUID, targetElements: [EUUID]) {
        let traceLink = ATLTraceLink(
            ruleName: ruleName,
            sourceElement: sourceElement,
            targetElements: targetElements
        )
        traceLinks.append(traceLink)
    }

    /// Get trace links for a source element.
    ///
    /// - Parameter sourceElement: Source element ID
    /// - Returns: Array of matching trace links
    public func getTraceLinks(for sourceElement: EUUID) -> [ATLTraceLink] {
        return traceLinks.filter { $0.sourceElement == sourceElement }
    }

    // MARK: - Lazy Binding Management

    /// Add a lazy binding for later resolution.
    ///
    /// - Parameter binding: Binding to add
    public func addLazyBinding(_ binding: ATLLazyBinding) {
        lazyBindings.append(binding)
    }

    /// Resolve all pending lazy bindings.
    ///
    /// - Throws: `ATLExecutionError` if resolution fails
    public func resolveLazyBindings() async throws {
        for binding in lazyBindings {
            try await binding.resolve(in: self)
        }
        lazyBindings.removeAll()
    }

    // MARK: - Error Management

    /// Get the current error context.
    ///
    /// - Returns: Error context
    public func getErrorContext() -> ATLErrorContext {
        return errorContext
    }

    /// Clear the error context.
    public func clearErrorContext() {
        errorContext = ATLErrorContext()
    }

    // MARK: - Cache Management (Delegated)

    /// Clear all caches in the execution engine.
    public func clearCaches() async {
        await executionEngine.clearCaches()
    }

    /// Get cache statistics from the execution engine.
    ///
    /// - Returns: Cache statistics
    public func getCacheStatistics() async -> [String: Int] {
        return await executionEngine.getCacheStatistics()
    }

    // MARK: - Private Implementation

    /// Build ECore evaluation context from ATL variables.
    private func buildECoreContext() throws -> [String: any EcoreValue] {
        var context: [String: any EcoreValue] = [:]

        // Add current variables
        for (name, value) in variables {
            if let ecoreValue = value {
                context[name] = ecoreValue
            }
        }

        // Add scope stack variables
        for scope in scopeStack {
            for (name, value) in scope {
                if context[name] == nil, let ecoreValue = value {
                    context[name] = ecoreValue
                }
            }
        }

        return context
    }

    /// Find an EClass by name.
    private func findEClass(name: String, in modelAlias: String? = nil) throws -> EClass {
        // If a model alias is provided, look only in that metamodel
        if let modelAlias = modelAlias {
            if let metamodel = module.targetMetamodels[modelAlias] {
                if let eClass = metamodel.getClassifier(name) as? EClass {
                    return eClass
                }
            } else if let metamodel = module.sourceMetamodels[modelAlias] {
                if let eClass = metamodel.getClassifier(name) as? EClass {
                    return eClass
                }
            }
            throw ATLExecutionError.typeError("Class '\(name)' not found in model '\(modelAlias)'")
        }

        // Otherwise, search all target metamodels first, then source metamodels
        for metamodel in module.targetMetamodels.values {
            if let eClass = metamodel.getClassifier(name) as? EClass {
                return eClass
            }
        }

        for metamodel in module.sourceMetamodels.values {
            if let eClass = metamodel.getClassifier(name) as? EClass {
                return eClass
            }
        }

        throw ATLExecutionError.typeError("Unknown type: \(name)")
    }

    /// Find an element by ID across all models.
    ///
    /// - Parameter id: Element ID to find
    /// - Returns: Element if found
    public func findElement(_ id: EUUID) async -> (any EObject)? {
        // Search in target models first
        for resource in targets.values {
            if let element = await resource.resolve(id) {
                return element
            }
        }

        // Search in source models if not found in targets
        for resource in sources.values {
            if let element = await resource.resolve(id) {
                return element
            }
        }

        return nil
    }

    /// Parse a qualified type name into model alias and type name.
    private func parseQualifiedTypeName(_ qualifiedType: String) -> (String?, String) {
        let components = qualifiedType.split(separator: "!")
        if components.count == 2 {
            return (String(components[0]), String(components[1]))
        } else {
            return (nil, qualifiedType)
        }
    }
}

// MARK: - Supporting Types

/// Error context for tracking issues during ATL execution.
public struct ATLErrorContext: Sendable, Equatable {
    /// Error messages collected during execution.
    public private(set) var errors: [String] = []

    /// Warning messages collected during execution.
    public private(set) var warnings: [String] = []

    /// Timeline of events for debugging.
    public private(set) var timeline: [(Date, String)] = []

    /// Add an error message.
    mutating func addError(_ message: String) {
        errors.append(message)
        timeline.append((Date(), "ERROR: \(message)"))
    }

    /// Add a warning message.
    mutating func addWarning(_ message: String) {
        warnings.append(message)
        timeline.append((Date(), "WARNING: \(message)"))
    }

    /// Add an event to the timeline.
    mutating func addEvent(_ message: String) {
        timeline.append((Date(), "INFO: \(message)"))
    }

    /// Check if there are any errors.
    public var hasErrors: Bool {
        return !errors.isEmpty
    }

    /// Check if there are any warnings.
    public var hasWarnings: Bool {
        return !warnings.isEmpty
    }

    /// Get a summary of all errors and warnings.
    public func summary() -> String {
        var result: [String] = []
        if !errors.isEmpty {
            result.append("Errors (\(errors.count)):")
            result.append(contentsOf: errors.map { "  - \(String($0))" })
        }
        if !warnings.isEmpty {
            result.append("Warnings (\(warnings.count)):")
            result.append(contentsOf: warnings.map { "  - \(String($0))" })
        }
        return result.joined(separator: "\n")
    }

    /// Equality comparison for testing.
    public static func == (lhs: ATLErrorContext, rhs: ATLErrorContext) -> Bool {
        return lhs.errors == rhs.errors && lhs.warnings == rhs.warnings
    }
}

/// Trace link between source and target elements in ATL transformations.
///
/// Trace links provide bidirectional mapping between elements transformed
/// by ATL rules, enabling impact analysis and transformation debugging.
public struct ATLTraceLink: Sendable, Equatable, Hashable {
    /// Name of the ATL rule that created this trace link.
    public let ruleName: String

    /// Unique identifier of the source element.
    public let sourceElement: EUUID

    /// Unique identifiers of the target elements created from the source.
    public let targetElements: [EUUID]

    /// Creates a new trace link.
    ///
    /// - Parameters:
    ///   - ruleName: Name of the creating rule
    ///   - sourceElement: Source element ID
    ///   - targetElements: Target element IDs
    public init(ruleName: String, sourceElement: EUUID, targetElements: [EUUID]) {
        self.ruleName = ruleName
        self.sourceElement = sourceElement
        self.targetElements = targetElements
    }
}

/// Lazy binding for deferred property assignment in ATL transformations.
///
/// Lazy bindings allow ATL rules to defer property assignments until after
/// all target elements are created, enabling forward references and circular
/// dependencies to be resolved correctly.
public struct ATLLazyBinding: Sendable {
    /// Target element to assign the property to.
    public let targetElement: EUUID

    /// Property name to assign.
    public let property: String

    /// Expression to evaluate for the property value.
    public let expression: any ATLExpression

    /// Creates a new lazy binding.
    ///
    /// - Parameters:
    ///   - targetElement: Target element ID
    ///   - property: Property name
    ///   - expression: Value expression
    public init(targetElement: EUUID, property: String, expression: any ATLExpression) {
        self.targetElement = targetElement
        self.property = property
        self.expression = expression
    }

    /// Resolve the lazy binding by evaluating the expression and setting the property.
    ///
    /// - Parameter context: Execution context for evaluation
    /// - Throws: `ATLExecutionError` if resolution fails
    func resolve(in context: ATLExecutionContext) async throws {
        // Find the target element
        guard let targetObject = await findElement(targetElement, in: context) else {
            throw ATLExecutionError.runtimeError("Element with ID '\(targetElement)' not found")
        }

        // Evaluate the expression
        let value = try await expression.evaluate(in: context)

        // Set the property using the execution engine
        try await context.executionEngine.setProperty(
            targetObject, property: property, value: value)
    }

    /// Find an element by ID in the context.
    private func findElement(_ id: EUUID, in context: ATLExecutionContext) async -> (any EObject)? {
        return await context.findElement(id)
    }
}
