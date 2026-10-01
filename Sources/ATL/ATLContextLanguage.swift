//
//  ATLContextLanguage.swift
//  ATL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// Identifies one cached attribute helper value.
struct ATLAttributeCacheKey: Hashable, Sendable {
    /// The helper name.
    let helperName: String

    /// The helper's context type, or `nil` for a context-free helper.
    let contextType: String?

    /// A description of the receiver that distinguishes receivers from each other.
    let receiver: String

    /// The cache key for a receiver value, if the value can be keyed.
    ///
    /// Model objects are keyed by identifier and primitive values by type and value;
    /// other values are not cached.
    ///
    /// - Parameters:
    ///   - helper: The attribute helper.
    ///   - receiver: The receiver value.
    /// - Returns: The key, or `nil` when the receiver cannot be keyed.
    static func key(for helper: ATLHelperWrapper, receiver: any EcoreValue) -> ATLAttributeCacheKey? {
        let description: String
        switch receiver {
        case let object as any EObject:
            description = "object:\(object.id.uuidString)"
        case is String, is Int, is Double, is Bool:
            description = "\(type(of: receiver)):\(receiver)"
        default:
            return nil
        }
        return ATLAttributeCacheKey(
            helperName: helper.name, contextType: helper.contextType, receiver: description)
    }

    /// The cache key of a context-free attribute helper.
    ///
    /// - Parameter helper: The attribute helper.
    /// - Returns: The key that identifies the helper's single value.
    static func key(forGlobal helper: ATLHelperWrapper) -> ATLAttributeCacheKey {
        ATLAttributeCacheKey(helperName: helper.name, contextType: nil, receiver: "global")
    }
}

/// A cached attribute helper value, which may be the undefined value.
struct ATLCachedValue {
    /// The cached value, or `nil` for the undefined value.
    let value: (any EcoreValue)?
}

extension ATLExecutionContext {

    // MARK: - Helper Lookup

    /// Selects the contextual helper that applies to a receiver.
    ///
    /// Among the helpers of the given name whose parameter count matches, the one
    /// whose context type is closest to the receiver's dynamic type wins, so that a
    /// helper declared for a subclass overrides one declared for its superclass.
    ///
    /// - Parameters:
    ///   - name: The helper name.
    ///   - receiver: The receiver value.
    ///   - argumentCount: The number of arguments of the call.
    ///   - includingOclAny: Whether helpers declared for `OclAny` may be selected.
    /// - Returns: The most specific applicable helper, or `nil` when none applies.
    func bestContextHelper(
        named name: String, receiver: any EcoreValue, argumentCount: Int, includingOclAny: Bool
    ) -> ATLHelperWrapper? {
        var candidates = (module.helperOverloads[name] ?? []).compactMap { $0 as? ATLHelperWrapper }
        if let registered = helpers[name] as? ATLHelperWrapper, registered.contextType != nil {
            candidates.removeAll { $0.contextType == registered.contextType }
            candidates.append(registered)
        }

        var best: (helper: ATLHelperWrapper, distance: Int)?
        for candidate in candidates {
            guard let contextType = candidate.contextType,
                candidate.parameters.count == argumentCount,
                let distance = ATLTypeMatching.distance(of: receiver, to: contextType),
                includingOclAny || distance < ATLTypeMatching.anyDistance
            else { continue }
            if best == nil || distance < best!.distance {
                best = (candidate, distance)
            }
        }
        return best?.helper
    }

    /// Finds the context-free helper of a name.
    ///
    /// - Parameter name: The helper name.
    /// - Returns: The helper, or `nil` when only contextual helpers (or none) have that name.
    func globalHelper(named name: String) -> (any ATLHelperType)? {
        if let registered = helpers[name], registered.contextType == nil {
            return registered
        }
        return module.helperOverloads[name]?.first { $0.contextType == nil }
    }

    // MARK: - Helper Invocation

    /// Evaluates a contextual helper for a receiver.
    ///
    /// The receiver is bound to `self` and the arguments to the helper's parameters.
    /// The value of an attribute helper is computed once per receiver and reused.
    ///
    /// - Parameters:
    ///   - helper: The helper to evaluate.
    ///   - receiver: The receiver value.
    ///   - arguments: The evaluated arguments.
    /// - Returns: The value of the helper body.
    /// - Throws: ``ATLExecutionError`` when the body fails.
    func invokeContextHelper(
        _ helper: ATLHelperWrapper, receiver: any EcoreValue, arguments: [(any EcoreValue)?]
    ) async throws -> (any EcoreValue)? {
        let key =
            helper.isAttribute && arguments.isEmpty
            ? ATLAttributeCacheKey.key(for: helper, receiver: receiver) : nil
        if let key, let cached = attributeHelperCache[key] {
            return cached.value
        }

        pushScope()
        defer { popScope() }
        setVariable(ATLLanguage.selfVariable, value: receiver)
        for (parameter, argument) in zip(helper.parameters, arguments) {
            setVariable(parameter.name, value: argument)
        }
        let value = try await helper.bodyExpression.evaluate(in: self)

        if let key {
            attributeHelperCache[key] = ATLCachedValue(value: value)
        }
        return value
    }

    /// Evaluates a context-free attribute helper, computing it once.
    ///
    /// - Parameter helper: The context-free helper.
    /// - Returns: The value of the helper body.
    /// - Throws: ``ATLExecutionError`` when the body fails.
    func evaluateGlobalAttribute(_ helper: ATLHelperWrapper) async throws -> (any EcoreValue)? {
        guard helper.isAttribute else {
            return try await callHelper(helper.name, arguments: [])
        }
        let key = ATLAttributeCacheKey.key(forGlobal: helper)
        if let cached = attributeHelperCache[key] {
            return cached.value
        }
        let value = try await callHelper(helper.name, arguments: [])
        attributeHelperCache[key] = ATLCachedValue(value: value)
        return value
    }

    /// Forgets all computed attribute helper values.
    ///
    /// The virtual machine calls this before each execution, because attribute
    /// values depend on the models of that execution.
    func clearAttributeHelperCache() {
        attributeHelperCache.removeAll()
    }

    // MARK: - Navigation over Collections

    /// Navigates a feature over every element of a collection and collects the results.
    ///
    /// - Parameters:
    ///   - elements: The elements to navigate from.
    ///   - property: The feature name.
    /// - Returns: The flattened results as a sequence; undefined results are dropped.
    /// - Throws: ``ATLExecutionError`` when navigation from an element fails.
    func navigateCollection(_ elements: [any EcoreValue], property: String) async throws
        -> (any EcoreValue)?
    {
        var collected: [any EcoreValue] = []
        for element in elements {
            guard let value = try await navigate(from: element, property: property) else { continue }
            collected.append(
                contentsOf: ATLCollections.isCollection(value)
                    ? ATLCollections.elements(of: value) : [value])
        }
        return EcoreValueArray(collected)
    }

    // MARK: - Module Parameters

    /// Supplies the values of the module's declared parameters.
    ///
    /// Parameters that are not supplied take their declared default values.
    ///
    /// - Parameter supplied: The caller's values by parameter name.
    /// - Throws: ``ATLExecutionError/unknownParameter(_:)`` for a name the module does not declare,
    ///   ``ATLExecutionError/missingParameter(_:)`` for a required parameter without a value, and
    ///   ``ATLExecutionError/typeError(_:)`` for a value of the wrong type.
    public func setModuleParameters(_ supplied: [String: any EcoreValue]) throws {
        let declared = Set(module.parameters.map(\.name))
        if let unknown = supplied.keys.sorted().first(where: { !declared.contains($0) }) {
            throw ATLExecutionError.unknownParameter(unknown)
        }

        var resolved: [String: any EcoreValue] = [:]
        for parameter in module.parameters {
            if let value = supplied[parameter.name] {
                resolved[parameter.name] = try parameter.validated(value)
            } else if let defaultValue = parameter.defaultValue {
                resolved[parameter.name] = defaultValue.ecoreValue
            } else {
                throw ATLExecutionError.missingParameter(parameter.name)
            }
        }
        moduleParameters = resolved
    }

    /// Reads a declared module parameter.
    ///
    /// - Parameter name: The parameter name.
    /// - Returns: The value, or `nil` when the module declares no parameter of that name.
    /// - Throws: ``ATLExecutionError/missingParameter(_:)`` when a required parameter has no value.
    func moduleParameterValue(named name: String) throws -> ATLBuiltinResult? {
        guard let parameter = module.parameters.first(where: { $0.name == name }) else {
            return nil
        }
        if let value = moduleParameters[name] {
            return ATLBuiltinResult(value: value)
        }
        guard let defaultValue = parameter.defaultValue else {
            throw ATLExecutionError.missingParameter(name)
        }
        return ATLBuiltinResult(value: defaultValue.ecoreValue)
    }
}
