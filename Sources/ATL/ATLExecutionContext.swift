//
//  ATLExecutionContext.swift
//  ATL
//
//  Created by Rene Hexel on 6/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import ECore
import Foundation
import OrderedCollections

/// Actor responsible for managing ATL transformation execution state.
///
/// The ATL execution context serves as the central coordinator for transformation execution,
/// maintaining access to source and target models, variable bindings, helper functions,
/// and trace links. It provides a thread-safe environment for concurrent transformation
/// operations while preserving execution state consistency.
///
/// ## Overview
///
/// The execution context manages several key aspects of ATL transformations:
/// - **Model Access**: Provides unified access to source and target models
/// - **Variable Management**: Maintains scoped variable bindings for rules and helpers
/// - **Helper Execution**: Coordinates helper function invocation and caching
/// - **Navigation Support**: Handles property navigation and reference resolution
/// - **Trace Management**: Records transformation relationships for debugging
/// - **Lazy Evaluation**: Supports deferred binding resolution and rule execution
///
/// ## Concurrency Model
///
/// The execution context is implemented as an actor to ensure thread-safe access to
/// transformation state across concurrent rule execution. All state mutations and
/// model operations are serialised through the actor's message queue.
///
/// ## Example Usage
///
/// ```swift
/// let context = ATLExecutionContext(
///     module: transformationModule,
///     sources: ["IN": sourceResource],
///     targets: ["OUT": targetResource]
/// )
///
/// let result = try await context.navigate(from: sourceElement, property: "name")
/// ```
public actor ATLExecutionContext {

    // MARK: - Properties

    /// The ATL module being executed.
    ///
    /// The module provides access to transformation rules, helper functions,
    /// and metamodel specifications required for execution.
    public let module: ATLModule

    /// Source models indexed by their namespace aliases.
    ///
    /// Source models provide read-only access to input data for transformation.
    /// They are keyed by the aliases defined in the ATL module's metamodel bindings.
    public private(set) var sources: OrderedDictionary<String, Resource>

    /// Target models indexed by their namespace aliases.
    ///
    /// Target models provide write access for creating transformed output data.
    /// They are keyed by the aliases defined in the ATL module's metamodel bindings.
    public private(set) var targets: OrderedDictionary<String, Resource>

    /// Current variable bindings within the execution scope.
    ///
    /// Variables include rule parameters, pattern bindings, helper parameters,
    /// and local variable assignments. The context maintains a stack-based
    /// scoping model for nested execution contexts.
    private var variables: [String: (any EcoreValue)?] = [:]

    /// Variable scoping stack for nested contexts.
    ///
    /// The scoping stack enables proper variable isolation within nested
    /// rule and helper invocations, preserving lexical scoping semantics.
    private var scopeStack: [[String: (any EcoreValue)?]] = []

    /// Trace links recording transformation relationships.
    ///
    /// Trace links maintain bidirectional mappings between source and target
    /// elements, enabling transformation debugging and incremental updates.
    public private(set) var traceLinks: [ATLTraceLink] = []

    /// Lazy bindings awaiting resolution.
    ///
    /// Lazy bindings support deferred evaluation of complex transformations
    /// that require multiple passes or circular reference resolution.
    public private(set) var lazyBindings: [ATLLazyBinding] = []

    /// Registered helper functions indexed by signature
    private var helpers: [String: any ATLHelperType] = [:]

    /// Element type cache for performance optimisation
    private var typeCache: [String: [any EObject]] = [:]

    /// Cross-reference resolution cache
    private var resolutionCache: [EUUID: any EObject] = [:]

    /// Error context for debugging
    private var errorContext: ATLErrorContext = ATLErrorContext()

    // MARK: - Initialisation

    /// Creates a new ATL execution context.
    ///
    /// - Parameters:
    ///   - module: The ATL module to execute
    ///   - sources: Source models indexed by namespace aliases
    ///   - targets: Target models indexed by namespace aliases
    ///
    /// - Precondition: Source model aliases must match module source metamodel aliases
    /// - Precondition: Target model aliases must match module target metamodel aliases
    public init(
        module: ATLModule,
        sources: OrderedDictionary<String, Resource> = [:],
        targets: OrderedDictionary<String, Resource> = [:]
    ) {
        self.module = module
        self.sources = sources
        self.targets = targets
    }

    // MARK: - Variable Management

    /// Sets a variable value within the current scope.
    ///
    /// - Parameters:
    ///   - name: The variable name
    ///   - value: The variable value, or `nil` for undefined variables
    ///
    /// - Note: Variable assignments affect only the current scope and do not
    ///   propagate to parent or child scopes.
    public func setVariable(_ name: String, value: (any EcoreValue)?) {
        variables[name] = value
    }

    /// Retrieves a variable value from the current scope hierarchy.
    ///
    /// - Parameter name: The variable name to retrieve
    /// - Returns: The variable value, or `nil` if not found
    /// - Throws: `ATLExecutionError.variableNotFound` if the variable is undefined
    public func getVariable(_ name: String) throws -> (any EcoreValue)? {
        // Check current scope first
        if let value = variables[name] {
            return value
        }

        // Search scope stack from most recent to oldest
        for scope in scopeStack.reversed() {
            if let value = scope[name] {
                return value
            }
        }

        throw ATLExecutionError.variableNotFound(name)
    }

    /// Pushes a new variable scope onto the stack.
    ///
    /// New scopes provide variable isolation for nested rule and helper execution,
    /// preserving the current variable bindings while allowing local modifications.
    public func pushScope() {
        scopeStack.append(variables)
        variables = [:]
    }

    /// Pops the most recent variable scope from the stack.
    ///
    /// Scope popping restores the previous variable bindings and discards
    /// any local variables created within the popped scope.
    ///
    /// - Precondition: At least one scope must be present on the stack
    public func popScope() {
        precondition(!scopeStack.isEmpty, "Cannot pop from empty scope stack")
        variables = scopeStack.removeLast()
    }

    // MARK: - Model Access

    /// Adds a source model to the execution context.
    ///
    /// - Parameters:
    ///   - alias: The namespace alias for model access
    ///   - resource: The source model resource
    public func addSource(_ alias: String, resource: Resource) {
        sources[alias] = resource
    }

    /// Adds a target model to the execution context.
    ///
    /// - Parameters:
    ///   - alias: The namespace alias for model access
    ///   - resource: The target model resource
    public func addTarget(_ alias: String, resource: Resource) {
        targets[alias] = resource
    }

    /// Retrieves a source model by alias.
    ///
    /// - Parameter alias: The namespace alias
    /// - Returns: The source model resource, or `nil` if not found
    public func getSource(_ alias: String) -> Resource? {
        return sources[alias]
    }

    /// Retrieves a target model by alias.
    ///
    /// - Parameter alias: The namespace alias
    /// - Returns: The target model resource, or `nil` if not found
    public func getTarget(_ alias: String) -> Resource? {
        return targets[alias]
    }

    // MARK: - Property Navigation

    /// Navigates from an object to a specified property.
    ///
    /// Property navigation handles metamodel-compliant property access, supporting
    /// both attributes and references with appropriate type conversions and
    /// collection handling.
    ///
    /// - Parameters:
    ///   - object: The source object for navigation
    ///   - property: The property name to navigate to
    /// - Returns: The property value, or `nil` if undefined or inaccessible
    /// - Throws: ATL execution errors for invalid navigation operations
    public func navigate(from object: (any EcoreValue)?, property: String) throws -> (
        any EcoreValue
    )? {
        guard let eObject = object as? any EObject else {
            throw ATLExecutionError.typeError(
                "Cannot navigate property '\(property)' on non-EObject of type \(type(of: object))")
        }

        guard let eClass = eObject.eClass as? EClass else {
            throw ATLExecutionError.typeError(
                "Element eClass is not an EClass: \(type(of: eObject.eClass))")
        }

        // Find the structural feature for the property
        guard let feature = eClass.getStructuralFeature(name: property) else {
            throw ATLExecutionError.invalidOperation(
                "Property '\(property)' not found in class '\(eClass.name)'")
        }

        return eObject.eGet(feature)
    }

    // MARK: - Helper Execution

    /// Invokes a helper function with the specified arguments.
    ///
    /// Helper invocation supports both contextual and context-free helpers,
    /// with automatic parameter binding and scope management.
    ///
    /// - Parameters:
    ///   - name: The helper function name
    ///   - arguments: The argument values to pass
    /// - Returns: The helper's return value
    /// - Throws: ATL execution errors for helper invocation failures
    public func callHelper(_ name: String, arguments: [(any EcoreValue)?]) throws -> (
        any EcoreValue
    )? {
        guard let helper = module.helpers[name] else {
            throw ATLExecutionError.helperNotFound(name)
        }

        // Verify argument count matches parameter count
        guard arguments.count == helper.parameters.count else {
            throw ATLExecutionError.invalidOperation(
                "Helper '\(name)' expects \(helper.parameters.count) arguments, got \(arguments.count)"
            )
        }

        // Create new scope for helper execution
        pushScope()
        defer { popScope() }

        // Bind parameters to arguments
        for (parameter, argument) in zip(helper.parameters, arguments) {
            setVariable(parameter.name, value: argument)
        }

        // For contextual helpers, bind 'self' if available
        if helper.contextType != nil {
            // Context should be available from current variable scope
            // This would typically be set by the calling rule or expression
        }

        // TODO: Evaluate helper body expression
        // This is a placeholder - the actual implementation would evaluate helper.body
        return nil
    }

    // MARK: - Trace Management

    /// Records a trace link between source and target elements.
    ///
    /// Trace links enable transformation debugging, incremental updates, and
    /// bidirectional transformation relationships.
    ///
    /// - Parameters:
    ///   - ruleName: The name of the rule creating the link
    ///   - sourceElement: The source element UUID
    ///   - targetElements: The target element UUIDs
    public func addTraceLink(ruleName: String, sourceElement: EUUID, targetElements: [EUUID]) {
        let traceLink = ATLTraceLink(
            ruleName: ruleName,
            sourceElement: sourceElement,
            targetElements: targetElements
        )
        traceLinks.append(traceLink)
    }

    /// Retrieves trace links for a specific source element.
    ///
    /// - Parameter sourceElement: The source element UUID
    /// - Returns: Array of trace links originating from the source element
    public func getTraceLinks(for sourceElement: EUUID) -> [ATLTraceLink] {
        return traceLinks.filter { $0.sourceElement == sourceElement }
    }

    // MARK: - Lazy Binding Management

    /// Adds a lazy binding for deferred resolution.
    ///
    /// Lazy bindings support complex transformation patterns that require
    /// multiple evaluation passes or circular reference handling.
    ///
    /// - Parameter binding: The lazy binding to add
    public func addLazyBinding(_ binding: ATLLazyBinding) {
        lazyBindings.append(binding)
    }

    /// Resolves all pending lazy bindings.
    ///
    /// Lazy binding resolution occurs after primary transformation execution
    /// to handle forward references and circular dependencies.
    ///
    /// - Throws: ATL execution errors for unresolvable bindings
    public func resolveLazyBindings() async throws {
        for binding in lazyBindings {
            try await binding.resolve(in: self)
        }
        lazyBindings.removeAll()
    }

    // MARK: - Element Creation

    /// Creates a new target element of the specified type.
    ///
    /// Element creation handles metamodel-compliant object instantiation with
    /// automatic resource containment and UUID assignment.
    ///
    /// - Parameters:
    ///   - type: The element type specification (e.g., "Persons!Male")
    ///   - targetAlias: The target model alias for containment
    /// - Returns: The created element
    /// - Throws: ATL execution errors for invalid type specifications
    public func createElement(type: String, in targetAlias: String) async throws -> any EObject {
        // Parse type specification to extract namespace and class name
        let components = type.split(separator: "!")
        guard components.count == 2 else {
            throw ATLExecutionError.typeError(
                "Invalid type specification: '\(type)'. Expected format 'namespace!ClassName'")
        }

        let namespace = String(components[0])
        let className = String(components[1])

        // Verify namespace matches target alias
        guard namespace == targetAlias else {
            throw ATLExecutionError.typeError(
                "Type namespace '\(namespace)' does not match target alias '\(targetAlias)'")
        }

        // Get target resource and metamodel
        guard let targetResource = targets[targetAlias] else {
            throw ATLExecutionError.invalidOperation("Target model '\(targetAlias)' not found")
        }

        guard let metamodel = module.targetMetamodels[targetAlias] else {
            throw ATLExecutionError.invalidOperation("Target metamodel '\(targetAlias)' not found")
        }

        // Find the class in the metamodel
        guard let eClass = metamodel.getClassifier(className) as? EClass else {
            throw ATLExecutionError.typeError(
                "Class '\(className)' not found in metamodel '\(targetAlias)'")
        }

        // Create the element using the metamodel's factory
        let factory = metamodel.eFactoryInstance
        let element = factory.create(eClass)

        // Add element to target resource
        await targetResource.add(element)

        return element
    }
    
    // MARK: - Model Navigation
    
    /// Finds all elements of the specified type in source models.
    ///
    /// This method searches through all source models to find elements
    /// that match the given type specification.
    ///
    /// - Parameter typeName: Type name (potentially qualified with model alias)
    /// - Returns: Array of matching elements
    /// - Throws: `ATLExecutionError.typeNotFound` if type is not found
    public func findElementsOfType(_ typeName: String) async throws -> [any EObject] {
        // Check cache first
        if let cached = typeCache[typeName] {
            return cached
        }
        
        let (modelAlias, className) = parseQualifiedTypeName(typeName)
        var results: [any EObject] = []
        
        // Search in specific model if alias provided
        if let alias = modelAlias {
            if let resource = sources[alias] {
                results = await findElementsInResource(resource, ofType: className)
            } else {
                throw ATLExecutionError.runtimeError("Source model '\(alias)' not found")
            }
        } else {
            // Search in all source models
            for (_, resource) in sources {
                results.append(contentsOf: await findElementsInResource(resource, ofType: className))
            }
        }
        
        // Cache results
        typeCache[typeName] = results
        return results
    }
    
    /// Finds elements in a specific resource that match the given type.
    private func findElementsInResource(_ resource: Resource, ofType className: String) async -> [any EObject] {
        var results: [any EObject] = []
        
        let allObjects = await resource.getAllObjects()
        for object in allObjects {
            if let eClass = object.eClass as? EClass,
               eClass.name == className || isSubtypeOf(eClass, className) {
                results.append(object)
            }
        }
        
        return results
    }
    
    /// Checks if the given EClass is a subtype of the specified class name.
    private func isSubtypeOf(_ eClass: EClass, _ className: String) -> Bool {
        // Check direct inheritance
        for superType in eClass.eSuperTypes {
            if superType.name == className || isSubtypeOf(superType, className) {
                return true
            }
        }
        return false
    }
    
    /// Resolves an element by its identifier.
    ///
    /// - Parameter id: Element identifier
    /// - Returns: Resolved element or nil if not found
    public func resolveElement(_ id: EUUID) async -> (any EObject)? {
        // Check resolution cache
        if let cached = resolutionCache[id] {
            return cached
        }
        
        // Search in all resources
        for (_, resource) in sources {
            if let element = await resource.resolve(id) {
                resolutionCache[id] = element
                return element
            }
        }
        
        for (_, resource) in targets {
            if let element = await resource.resolve(id) {
                resolutionCache[id] = element
                return element
            }
        }
        
        return nil
    }
    
    /// Parses a qualified type name into model alias and class name components.
    ///
    /// - Parameter qualifiedType: Type name (e.g., "Source!Person" or "Person")
    /// - Returns: Tuple of optional model alias and class name
    private func parseQualifiedTypeName(_ qualifiedType: String) -> (String?, String) {
        if let exclamationIndex = qualifiedType.firstIndex(of: "!") {
            let modelAlias = String(qualifiedType[..<exclamationIndex])
            let className = String(qualifiedType[qualifiedType.index(after: exclamationIndex)...])
            return (modelAlias, className)
        } else {
            return (nil, qualifiedType)
        }
    }
    
    // MARK: - Helper Management
    
    /// Registers a helper function for later invocation.
    ///
    /// - Parameter helper: Helper function to register
    public func registerHelper(_ helper: any ATLHelperType) {
        let signature = createHelperSignature(helper)
        helpers[signature] = helper
    }
    
    /// Creates a unique signature for a helper function.
    private func createHelperSignature(_ helper: any ATLHelperType) -> String {
        let parameterTypes = helper.parameters.map { $0.type }.joined(separator: ",")
        let contextPart = helper.contextType.map { "\($0)." } ?? ""
        return "\(contextPart)\(helper.name)(\(parameterTypes))"
    }
    
    // MARK: - Utility Methods
    
    /// Invalidates the element type cache.
    private func invalidateTypeCache() {
        typeCache.removeAll()
    }
    
    /// Clears resolution cache.
    private func clearResolutionCache() {
        resolutionCache.removeAll()
    }
    
    /// Returns the current error context for debugging.
    ///
    /// - Returns: Error context with accumulated errors and warnings
    public func getErrorContext() -> ATLErrorContext {
        errorContext
    }
    
    /// Clears the error context.
    public func clearErrorContext() {
        errorContext = ATLErrorContext()
    }
    
    /// Performs cleanup operations after transformation completion.
    public func cleanup() {
        // Clear caches
        invalidateTypeCache()
        clearResolutionCache()
        
        // Clear error context
        clearErrorContext()
        
        // Reset bindings
        lazyBindings.removeAll()
    }
}

/// Error context for tracking execution errors and warnings.
public struct ATLErrorContext: Sendable {
    
    /// Accumulated errors
    public private(set) var errors: [String] = []
    
    /// Accumulated warnings  
    public private(set) var warnings: [String] = []
    
    /// Execution timeline for debugging
    public private(set) var timeline: [(Date, String)] = []
    
    /// Adds an error to the context.
    ///
    /// - Parameter message: Error message
    public mutating func addError(_ message: String) {
        errors.append(message)
        timeline.append((Date(), "ERROR: \(message)"))
    }
    
    /// Adds a warning to the context.
    ///
    /// - Parameter message: Warning message
    public mutating func addWarning(_ message: String) {
        warnings.append(message)
        timeline.append((Date(), "WARNING: \(message)"))
    }
    
    /// Adds a timeline entry.
    ///
    /// - Parameter message: Timeline message
    public mutating func addEvent(_ message: String) {
        timeline.append((Date(), message))
    }
    
    /// Returns whether any errors have occurred.
    ///
    /// - Returns: True if errors are present
    public var hasErrors: Bool {
        !errors.isEmpty
    }
    
    /// Returns whether any warnings have occurred.
    ///
    /// - Returns: True if warnings are present  
    public var hasWarnings: Bool {
        !warnings.isEmpty
    }
    
    /// Returns a formatted summary of errors and warnings.
    ///
    /// - Returns: Formatted error summary
    public func summary() -> String {
        var result: [String] = []
        
        if !errors.isEmpty {
            result.append("Errors (\(errors.count)):")
            result.append(contentsOf: errors.map { "  - \($0)" })
        }
        
        if !warnings.isEmpty {
            result.append("Warnings (\(warnings.count)):")
            result.append(contentsOf: warnings.map { "  - \($0)" })
        }
        
        if result.isEmpty {
            return "No errors or warnings"
        }
        
        return result.joined(separator: "\n")
    }
}

// MARK: - ATL Trace Link

/// Represents a trace link between source and target elements in ATL transformations.
///
/// Trace links record the relationships established during transformation execution,
/// providing bidirectional mappings between source and target elements. They enable
/// transformation debugging, incremental updates, and impact analysis.
///
/// ## Example Usage
///
/// ```swift
/// let traceLink = ATLTraceLink(
///     ruleName: "Member2Male",
///     sourceElement: memberUUID,
///     targetElements: [maleUUID]
/// )
/// ```
public struct ATLTraceLink: Sendable, Equatable {

    // MARK: - Properties

    /// The name of the transformation rule that created this trace link.
    ///
    /// Rule names enable filtering and grouping of trace links by their
    /// originating transformation rules.
    public let ruleName: String

    /// The UUID of the source element.
    ///
    /// Source element UUIDs provide stable references to input model elements
    /// across transformation sessions and model updates.
    public let sourceElement: EUUID

    /// The UUIDs of the target elements created from the source element.
    ///
    /// Target element arrays support one-to-many transformation patterns
    /// where a single source element produces multiple target elements.
    public let targetElements: [EUUID]

    // MARK: - Initialisation

    /// Creates a new ATL trace link.
    ///
    /// - Parameters:
    ///   - ruleName: The name of the creating transformation rule
    ///   - sourceElement: The source element UUID
    ///   - targetElements: The target element UUIDs
    ///
    /// - Precondition: The rule name must be a non-empty string
    /// - Precondition: At least one target element must be specified
    public init(ruleName: String, sourceElement: EUUID, targetElements: [EUUID]) {
        precondition(!ruleName.isEmpty, "Rule name must not be empty")
        precondition(!targetElements.isEmpty, "At least one target element must be specified")

        self.ruleName = ruleName
        self.sourceElement = sourceElement
        self.targetElements = targetElements
    }
}

// MARK: - ATL Lazy Binding

/// Represents a deferred property binding in ATL transformations.
///
/// Lazy bindings enable complex transformation patterns that require multiple
/// evaluation passes or forward reference resolution. They are resolved after
/// primary transformation execution to handle circular dependencies and
/// references to elements created later in the transformation process.
///
/// ## Example Usage
///
/// ```swift
/// let lazyBinding = ATLLazyBinding(
///     targetElement: personUUID,
///     property: "children",
///     expression: childrenExpression
/// )
/// ```
public struct ATLLazyBinding: Sendable {

    // MARK: - Properties

    /// The UUID of the target element to update.
    public let targetElement: EUUID

    /// The property name to bind.
    public let property: String

    /// The expression to evaluate for the property value.
    public let expression: any ATLExpression

    // MARK: - Initialisation

    /// Creates a new lazy binding.
    ///
    /// - Parameters:
    ///   - targetElement: The target element UUID
    ///   - property: The property name to bind
    ///   - expression: The expression to evaluate
    ///
    /// - Precondition: The property name must be a non-empty string
    public init(targetElement: EUUID, property: String, expression: any ATLExpression) {
        precondition(!property.isEmpty, "Property name must not be empty")

        self.targetElement = targetElement
        self.property = property
        self.expression = expression
    }

    // MARK: - Resolution

    /// Resolves the lazy binding within the execution context.
    ///
    /// - Parameter context: The execution context for expression evaluation
    /// - Throws: ATL execution errors for resolution failures
    public func resolve(in context: ATLExecutionContext) async throws {
        // Find the target element in the available target models
        var targetObject: (any EObject)?

        for (_, resource) in await context.targets {
            if let object = await resource.getObject(targetElement) {
                targetObject = object
                break
            }
        }

        guard let eObject = targetObject else {
            throw ATLExecutionError.invalidOperation(
                "Target element \(targetElement) not found for lazy binding")
        }

        // Evaluate the expression
        let value = try await expression.evaluate(in: context)

        // Get the structural feature for the property
        guard let eClass = eObject.eClass as? EClass else {
            throw ATLExecutionError.typeError(
                "Element eClass is not an EClass: \(type(of: eObject.eClass))")
        }

        guard let feature = eClass.getStructuralFeature(name: property) else {
            throw ATLExecutionError.invalidOperation(
                "Property '\(property)' not found in class '\(eClass.name)'")
        }

        // Set the property value
        var mutableObject = eObject
        mutableObject.eSet(feature, value)
    }
}
