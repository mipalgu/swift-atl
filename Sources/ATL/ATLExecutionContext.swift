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

    /// Positions in ``traceLinks`` indexed by the first source element of each link.
    private var traceLinkIndex: [EUUID: [Int]] = [:]

    /// Elements created by unique lazy rules, keyed by rule and argument tuple.
    private var uniqueRuleResults: [ATLUniqueRuleKey: [EUUID]] = [:]

    /// Lazy bindings waiting for resolution.
    private var lazyBindings: [ATLLazyBinding] = []

    /// Helper functions registered for this context.
    var helpers: [String: any ATLHelperType] = [:]

    /// Values of attribute helpers that have been computed, keyed by helper and receiver.
    var attributeHelperCache: [ATLAttributeCacheKey: ATLCachedValue] = [:]

    /// The values of the declared module parameters, available as `thisModule.<name>`.
    var moduleParameters: [String: any EcoreValue] = [:]

    /// Error context for tracking issues during execution.
    private var errorContext: ATLErrorContext = ATLErrorContext()

    /// The underlying ECore execution engine for heavy computation.
    public let executionEngine: ECoreExecutionEngine

    /// Optional command stack for undo/redo support.
    private let commandStack: CommandStack?

    /// Debug mode flag for systematic tracing.
    public var debug: Bool = false

    /// Back-reference to the owning virtual machine for called rule dispatch.
    public weak var virtualMachine: ATLVirtualMachine?

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
            print(
                "[SCOPE DEBUG] Setting variable '\(name)' in current scope (depth: \(scopeStack.count))"
            )
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
            print(
                "[SCOPE DEBUG] Getting variable '\(name)' (depth: \(scopeStack.count), current vars: \(variables.keys.sorted()), stack vars: \(scopeStack.map { $0.keys.sorted() }))"
            )
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
                    print(
                        "[SCOPE DEBUG]   Found '\(name)' in stack at depth \(scopeStack.count - index - 1)"
                    )
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
            print(
                "[SCOPE DEBUG] Pushing scope (current vars: \(variables.keys.sorted())) -> depth will be \(scopeStack.count + 1)"
            )
        }
        scopeStack.append(variables)
        variables = [:]
    }

    /// Pop the current variable scope from the stack.
    public func popScope() {
        if debug {
            print(
                "[SCOPE DEBUG] Popping scope (current vars: \(variables.keys.sorted())) depth \(scopeStack.count) -> \(scopeStack.count - 1)"
            )
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
        if ATLCollections.isCollection(object) {
            return try await navigateCollection(ATLCollections.elements(of: object), property: property)
        }

        guard var eObject = object as? (any EObject) else {
            // Attribute helpers can be declared for primitive types too
            if let object, let helper = bestContextHelper(
                named: property, receiver: object, argumentCount: 0, includingOclAny: true)
            {
                return try await invokeContextHelper(helper, receiver: object, arguments: [])
            }
            let objectType = object != nil ? String(reflecting: type(of: object!)) : "nil"
            throw ATLExecutionError.typeError("Source is not an EObject of type: \(objectType)")
        }

        // Target elements change while a transformation runs, so navigate their current state
        if let current = await findTargetObject(eObject.id) {
            eObject = current
        }

        // First try ECore navigation for actual properties
        do {
            return try await executionEngine.navigate(from: eObject, property: property)
        } catch {
            // If ECore navigation fails, try the contextual helper selected by the receiver's type
            if let helper = bestContextHelper(
                named: property, receiver: eObject, argumentCount: 0, includingOclAny: true)
            {
                if debug {
                    print(
                        "[ATL DEBUG] Property '\(property)' not found, using contextual helper"
                    )
                }
                return try await invokeContextHelper(helper, receiver: eObject, arguments: [])
            }

            // Native metamodel elements answer their name without a reflective metamodel
            if property == ATLLanguage.namePropertyName, let named = eObject as? any ENamedElement {
                return named.name
            }

            // Neither property nor helper found, rethrow original error
            throw error
        }
    }

    // MARK: - Helper Management

    /// Call a helper function with arguments.
    ///
    /// This method resolves standard registered helpers and also handles ATL's
    /// `resolveTemp` operation as a built-in dispatch path. The built-in branch
    /// keeps trace-link resolution available even when the module does not expose
    /// `resolveTemp` as an ordinary helper definition.
    ///
    /// - Parameters:
    ///   - name: The helper name to call.
    ///   - arguments: The evaluated helper arguments.
    /// - Returns: The helper result, if one is produced.
    /// - Throws: `ATLExecutionError` if helper dispatch or evaluation fails.
    public func callHelper(_ name: String, arguments: [(any EcoreValue)?]) async throws -> (
        any EcoreValue
    )? {
        if name == ATLReservedNames.resolveTemp {
            return try await resolveTemp(arguments)
        }

        guard let helper = globalHelper(named: name) else {
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

        // Evaluate helper body expression using ATL evaluator directly
        guard let helperWrapper = helper as? ATLHelperWrapper else {
            throw ATLExecutionError.runtimeError("Helper '\(name)' is not a supported helper type")
        }

        return try await helperWrapper.bodyExpression.evaluate(in: self)
    }

    /// Register a helper function.
    ///
    /// - Parameter helper: Helper to register
    public func registerHelper(_ helper: any ATLHelperType) {
        helpers[helper.name] = helper
    }

    /// Dispatch a `thisModule.method()` call.
    ///
    /// Dispatch first checks built-in operations such as `resolveTemp`, then
    /// tries called rules through the owning virtual machine, and finally falls
    /// back to module helpers. This mirrors ATL's mixed dispatch model while
    /// preserving the existing helper resolution path.
    ///
    /// - Parameters:
    ///   - name: The method name to dispatch.
    ///   - arguments: The evaluated argument values.
    /// - Returns: The result of the dispatched call, if any.
    /// - Throws: `ATLExecutionError` if dispatch fails.
    public func dispatchThisModuleMethod(_ name: String, arguments: [(any EcoreValue)?]) async throws -> (any EcoreValue)? {
        if name == ATLReservedNames.resolveTemp {
            return try await resolveTemp(arguments)
        }

        // Try called rules first via the virtual machine
        if module.calledRules[name] != nil, let vm = virtualMachine {
            let elements = try await vm.executeCalledRule(name, arguments: arguments)
            return elements.first.map { $0 as any EcoreValue }
        }
        // Fall back to helpers
        return try await callHelper(name, arguments: arguments)
    }

    /// Dispatch a `thisModule.attribute` navigation to a context-free helper.
    ///
    /// Rejects contextual helpers (they require a receiver object). Calls the
    /// matching context-free helper with no arguments.
    ///
    /// - Parameter name: Attribute name (maps to a helper name)
    /// - Returns: The result of evaluating the helper
    /// - Throws: `ATLExecutionError` if the helper is not found or is contextual
    public func dispatchThisModuleAttribute(_ name: String) async throws -> (any EcoreValue)? {
        if let parameter = try moduleParameterValue(named: name) {
            return parameter.value
        }
        guard let helper = globalHelper(named: name) as? ATLHelperWrapper else {
            if helpers[name] != nil || module.helperOverloads[name] != nil {
                throw ATLExecutionError.runtimeError(
                    "Contextual helper '\(name)' requires a receiver object and cannot be accessed as a thisModule attribute"
                )
            }
            throw ATLExecutionError.helperNotFound(name)
        }
        return try await evaluateGlobalAttribute(helper)
    }

    /// Resolve a named target element traced from a source object.
    ///
    /// `resolveTemp(source, 'name')` returns the target element that the rule
    /// transforming `source` created for the target pattern called `name`.
    /// When `source` is a collection, it identifies a rule with several source
    /// elements by their tuple. Without a name, the default (first) target
    /// element is returned. Lazy rule results are found as well as matched rule
    /// results.
    ///
    /// - Parameter arguments: The evaluated ATL arguments: the source object (or a
    ///   collection of source objects) followed by the optional target pattern name.
    /// - Returns: The resolved target object.
    /// - Throws: `ATLExecutionError` if the arguments are invalid or no traced target can be found.
    private func resolveTemp(_ arguments: [(any EcoreValue)?]) async throws -> (any EcoreValue)? {
        let sourceIDs: [EUUID]
        if let sourceObject = arguments.first as? (any EObject) {
            sourceIDs = [sourceObject.id]
        } else if let collection = arguments.first.flatMap({ $0 }) as? EcoreValueArray,
            case let objects = collection.values.compactMap({ $0 as? (any EObject) }),
            !objects.isEmpty, objects.count == collection.values.count
        {
            sourceIDs = objects.map(\.id)
        } else {
            throw ATLExecutionError.typeError(
                "resolveTemp() requires a source EObject as its first argument")
        }
        let patternName = arguments.count > 1 ? arguments[1] as? String : nil

        let links = getTraceLinks(forSources: sourceIDs)
        for link in links {
            let targetID: EUUID?
            if let patternName {
                targetID = link.targetID(named: patternName)
            } else {
                targetID = link.targetElements.first
            }
            if let targetID, let targetObject = await findTargetObject(targetID) {
                return targetObject
            }
        }

        if let patternName {
            throw ATLExecutionError.runtimeError(
                "resolveTemp() could not find target element '\(patternName)' for source object \(sourceIDs[0])"
            )
        }
        throw ATLExecutionError.runtimeError(
            "resolveTemp() could not find a target element for source object \(sourceIDs[0])")
    }

    // MARK: - Target Model Access

    /// Looks up an element in the target models.
    ///
    /// - Parameter id: The identifier of the element
    /// - Returns: The current state of the element, or `nil` if no target model holds it
    public func findTargetObject(_ id: EUUID) async -> (any EObject)? {
        for resource in targets.values {
            if let object = await resource.getObject(id) {
                return object
            }
        }
        return nil
    }

    /// Finds the source or target model that holds an element.
    ///
    /// - Parameter id: The identifier of the element
    /// - Returns: The resource containing the element, or `nil` if none does
    public func resourceContaining(_ id: EUUID) async -> Resource? {
        for resource in targets.values where await resource.contains(id: id) {
            return resource
        }
        for resource in sources.values where await resource.contains(id: id) {
            return resource
        }
        return nil
    }

    /// Assigns a value to a feature of a target element.
    ///
    /// For reference features, model elements in the value are converted to the
    /// form stored in the target model: a source element transformed by a
    /// matched rule is replaced by that rule's default target element, an
    /// element of the same target model is stored by identifier, and any other
    /// element is stored as a cross-resource proxy. See ``ATLReferenceStorage``.
    /// Collection values are unwrapped, so their elements are resolved the same way,
    /// and enumeration and numeric attribute values are validated and converted
    /// by ``ATLValueConversion``.
    ///
    /// - Parameters:
    ///   - element: The target element to modify
    ///   - name: The name of the feature to set
    ///   - value: The evaluated value to assign
    /// - Throws: ``ATLExecutionError`` if the element is not part of a target model,
    ///   has no feature of that name, or the value is not valid for the feature (such as
    ///   an unknown enumeration literal)
    public func assignFeature(on element: any EObject, feature name: String, value: (any EcoreValue)?)
        async throws
    {
        let classifier: any EClassifier = element.eClass
        guard let eClass = classifier as? EClass else {
            throw ATLExecutionError.typeError(
                "Element eClass is not an EClass: \(type(of: classifier))"
            )
        }
        guard let feature = eClass.getStructuralFeature(name: name) else {
            if debug {
                print("[ATL DEBUG] Failed to find property '\(name)' in class '\(eClass.name)'")
                print("[ATL DEBUG]   All features: \(eClass.allStructuralFeatures.map { $0.name })")
            }
            throw ATLExecutionError.invalidOperation(
                "Property '\(name)' not found in class '\(eClass.name)'"
            )
        }
        guard let resource = await targetResource(containing: element.id) else {
            throw ATLExecutionError.invalidOperation(
                "Cannot assign '\(name)': element of class '\(eClass.name)' is not part of a target model"
            )
        }

        let prepared = try ATLValueConversion.prepare(value, for: feature)
        let stored = await ATLReferenceStorage.storedValue(
            for: prepared, feature: feature, in: resource, context: self)
        guard await resource.eSet(objectId: element.id, feature: name, value: stored) else {
            throw ATLExecutionError.runtimeError(
                "Could not set property '\(name)' of class '\(eClass.name)'")
        }
        if debug {
            print("[ATL DEBUG] Updated property '\(name)' = '\(String(describing: value))'")
        }
    }

    /// Finds the target model that holds an element.
    ///
    /// - Parameter id: The identifier of the element
    /// - Returns: The target resource containing the element, or `nil`
    private func targetResource(containing id: EUUID) async -> Resource? {
        for resource in targets.values where await resource.contains(id: id) {
            return resource
        }
        return nil
    }

    /// Rebinds a variable that is already declared in an enclosing scope.
    ///
    /// - Parameters:
    ///   - name: The variable name
    ///   - value: The new value
    /// - Throws: ``ATLExecutionError/variableNotFound(_:)`` if no scope declares the variable
    public func assignVariable(_ name: String, value: (any EcoreValue)?) throws {
        if variables.index(forKey: name) != nil {
            variables[name] = value
            return
        }
        for index in scopeStack.indices.reversed() where scopeStack[index].index(forKey: name) != nil {
            scopeStack[index][name] = value
            return
        }
        throw ATLExecutionError.variableNotFound(name)
    }

    // MARK: - Element Creation (Command-Based)

    /// Create a new element in a target model using commands.
    ///
    /// - Parameters:
    ///   - type: Element type name
    ///   - metamodelName: Target metamodel name
    /// - Returns: Created element
    /// - Throws: `ATLExecutionError` if creation fails
    public func createElement(type: String, in metamodelName: String) async throws -> any EObject {
        // Parse the type specification
        let (parsedMetamodel, typeName) = parseQualifiedTypeName(type)
        let actualMetamodelName = parsedMetamodel ?? metamodelName

        // Find the model alias that uses this metamodel
        guard let modelAlias = module.targetAlias(forMetamodel: actualMetamodelName)
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
    /// The link is recorded as the result of a matched rule with unnamed target elements.
    ///
    /// - Parameters:
    ///   - ruleName: Name of the rule creating the link
    ///   - sourceElement: Source element ID
    ///   - targetElements: Target element IDs
    public func addTraceLink(ruleName: String, sourceElement: EUUID, targetElements: [EUUID]) {
        addTraceLink(
            ATLTraceLink(
                ruleName: ruleName,
                sourceElement: sourceElement,
                targetElements: targetElements
            ))
    }

    /// Add a fully specified trace link.
    ///
    /// - Parameter link: The link to record
    public func addTraceLink(_ link: ATLTraceLink) {
        traceLinkIndex[link.sourceElement, default: []].append(traceLinks.count)
        traceLinks.append(link)
    }

    /// Get trace links for a source element.
    ///
    /// - Parameter sourceElement: Source element ID
    /// - Returns: Array of matching trace links
    public func getTraceLinks(for sourceElement: EUUID) -> [ATLTraceLink] {
        return (traceLinkIndex[sourceElement] ?? []).map { traceLinks[$0] }
    }

    /// Get the trace links recorded for a tuple of source elements.
    ///
    /// - Parameter sourceElements: The identifiers of the source elements, in pattern order
    /// - Returns: The links whose source elements are exactly the given tuple
    public func getTraceLinks(forSources sourceElements: [EUUID]) -> [ATLTraceLink] {
        guard let first = sourceElements.first else { return [] }
        return getTraceLinks(for: first).filter { $0.allSourceElements == sourceElements }
    }

    /// The identifier of the default target element of a transformed source element.
    ///
    /// The default target element is the first target element created by the
    /// matched rule that transformed the source element. Lazy and called rules
    /// do not contribute to the default resolution of bindings.
    ///
    /// - Parameter sourceElement: The source element ID
    /// - Returns: The target element ID, or `nil` if no matched rule transformed the element
    public func defaultTargetID(for sourceElement: EUUID) -> EUUID? {
        return getTraceLinks(for: sourceElement)
            .first(where: { $0.kind == .matched && $0.additionalSourceElements.isEmpty })?
            .targetElements.first
    }

    /// Discards all state accumulated by a previous transformation run.
    ///
    /// Trace links, pending lazy bindings and the results of unique lazy rules
    /// are cleared; variables, models and helpers are retained.
    public func resetTransformationState() {
        traceLinks.removeAll()
        traceLinkIndex.removeAll()
        lazyBindings.removeAll()
        uniqueRuleResults.removeAll()
    }

    /// The elements an unique rule created for an argument tuple, if it has run for it.
    ///
    /// - Parameter key: The rule and argument tuple
    /// - Returns: The identifiers of the created elements, or `nil`
    func uniqueRuleResult(for key: ATLUniqueRuleKey) -> [EUUID]? {
        return uniqueRuleResults[key]
    }

    /// Remembers the elements an unique rule created for an argument tuple.
    ///
    /// - Parameters:
    ///   - elements: The identifiers of the created elements
    ///   - key: The rule and argument tuple
    func storeUniqueRuleResult(_ elements: [EUUID], for key: ATLUniqueRuleKey) {
        uniqueRuleResults[key] = elements
    }

    // MARK: - Lazy Binding Management

    /// Add a lazy binding for later resolution.
    ///
    /// - Parameter binding: Binding to add
    public func addLazyBinding(_ binding: ATLLazyBinding) {
        lazyBindings.append(binding)
    }

    /// Add a lazy binding with current variable context captured.
    ///
    /// - Parameters:
    ///   - targetElement: Target element ID
    ///   - property: Property name
    ///   - expression: Expression to evaluate
    public func addLazyBindingWithContext(
        targetElement: EUUID,
        property: String,
        expression: any ATLExpression
    ) {
        // Capture current variables and scope stack variables
        var capturedVars: [String: (any EcoreValue)?] = [:]

        // Add current scope variables
        for (name, value) in variables {
            capturedVars[name] = value
        }

        // Add scope stack variables (in reverse order for proper precedence)
        for scope in scopeStack.reversed() {
            for (name, value) in scope {
                if capturedVars[name] == nil {
                    capturedVars[name] = value
                }
            }
        }

        let binding = ATLLazyBinding(
            targetElement: targetElement,
            property: property,
            expression: expression,
            capturedVariables: capturedVars
        )
        lazyBindings.append(binding)
    }

    /// Resolve all pending lazy bindings.
    ///
    /// - Throws: `ATLExecutionError` if resolution fails
    public func resolveLazyBindings() async throws {
        try await resolveLazyBindings {}
    }

    /// The number of bindings awaiting resolution.
    var pendingLazyBindingCount: Int { lazyBindings.count }

    /// Resolves the pending lazy bindings, calling a closure before each one.
    ///
    /// - Parameter beforeEach: Called before each binding is resolved; it may throw to stop the run.
    /// - Throws: Errors raised by `beforeEach` or by a binding.
    func resolveLazyBindings(beforeEach: () async throws -> Void) async throws {
        for binding in lazyBindings {
            try await beforeEach()
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

    /// The kind of rule that created a trace link.
    public enum Kind: Sendable, Equatable, Hashable {
        /// A matched rule applied to a source element.
        case matched
        /// A lazy rule invoked with source elements.
        case lazy
    }

    /// Name of the ATL rule that created this trace link.
    public let ruleName: String

    /// Unique identifier of the source element.
    ///
    /// For rules matching several source elements this is the first of them.
    public let sourceElement: EUUID

    /// Unique identifiers of the source elements after the first, in pattern order.
    public let additionalSourceElements: [EUUID]

    /// Unique identifiers of the target elements created from the source.
    public let targetElements: [EUUID]

    /// The target pattern names of ``targetElements``, in the same order.
    ///
    /// Empty when the link was recorded without pattern names.
    public let targetNames: [String]

    /// The kind of rule that created the link.
    public let kind: Kind

    /// Creates a new trace link.
    ///
    /// - Parameters:
    ///   - ruleName: Name of the creating rule
    ///   - sourceElement: Source element ID
    ///   - targetElements: Target element IDs
    ///   - additionalSourceElements: Source element IDs after the first
    ///   - targetNames: The target pattern names, parallel to `targetElements`
    ///   - kind: The kind of rule that created the link
    public init(
        ruleName: String,
        sourceElement: EUUID,
        targetElements: [EUUID],
        additionalSourceElements: [EUUID] = [],
        targetNames: [String] = [],
        kind: Kind = .matched
    ) {
        self.ruleName = ruleName
        self.sourceElement = sourceElement
        self.additionalSourceElements = additionalSourceElements
        self.targetElements = targetElements
        self.targetNames = targetNames
        self.kind = kind
    }

    /// All source element identifiers in pattern order.
    public var allSourceElements: [EUUID] {
        [sourceElement] + additionalSourceElements
    }

    /// The identifier of the target element created for a named target pattern.
    ///
    /// - Parameter name: The target pattern name
    /// - Returns: The identifier, or `nil` if the rule has no pattern of that name
    public func targetID(named name: String) -> EUUID? {
        guard let index = targetNames.firstIndex(of: name), index < targetElements.count else {
            return nil
        }
        return targetElements[index]
    }
}

/// Identifies an invocation of a unique lazy rule by rule name and argument tuple.
struct ATLUniqueRuleKey: Hashable {

    /// The name of the rule.
    let ruleName: String

    /// The arguments identifying the invocation; model elements by identifier.
    let arguments: [AnyHashable]

    /// Creates a key for an invocation.
    ///
    /// - Parameters:
    ///   - ruleName: The name of the rule
    ///   - arguments: The evaluated arguments of the invocation
    init(ruleName: String, arguments: [(any EcoreValue)?]) {
        self.ruleName = ruleName
        self.arguments = arguments.map { argument in
            if let object = argument as? (any EObject) {
                return AnyHashable(object.id)
            }
            if let argument {
                return AnyHashable(argument)
            }
            return AnyHashable(Optional<Int>.none)
        }
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

    /// Captured variable context from when the binding was created.
    public let capturedVariables: [String: (any EcoreValue)?]

    /// Creates a new lazy binding.
    ///
    /// - Parameters:
    ///   - targetElement: Target element ID
    ///   - property: Property name
    ///   - expression: Value expression
    ///   - capturedVariables: Captured variable context from when the binding was created
    public init(
        targetElement: EUUID, property: String, expression: any ATLExpression,
        capturedVariables: [String: (any EcoreValue)?] = [:]
    ) {
        self.targetElement = targetElement
        self.property = property
        self.expression = expression
        self.capturedVariables = capturedVariables
    }

    /// Resolve the lazy binding by evaluating the expression and setting the property.
    ///
    /// - Parameter context: Execution context for evaluation
    /// - Throws: `ATLExecutionError` if resolution fails
    @MainActor
    func resolve(in context: ATLExecutionContext) async throws {
        // Find the target element
        guard let targetObject = await findElement(targetElement, in: context) else {
            throw ATLExecutionError.runtimeError("Element with ID '\(targetElement)' not found")
        }

        // Temporarily restore captured variables during expression evaluation
        context.pushScope()
        defer { context.popScope() }

        // Restore captured variables
        for (name, value) in capturedVariables {
            context.setVariable(name, value: value)
        }

        // Evaluate the expression with restored scope
        let value = try await expression.evaluate(in: context)
        try await context.assignFeature(on: targetObject, feature: property, value: value)
    }

    /// Find an element by ID in the context.
    private func findElement(_ id: EUUID, in context: ATLExecutionContext) async -> (any EObject)? {
        return await context.findElement(id)
    }
}
