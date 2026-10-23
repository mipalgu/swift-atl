//
//  ATLNativeHelper.swift
//  ATL
//
//  Created by Rene Hexel on 23/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase

/// A helper implemented in Swift that ATL expressions call like any other helper.
///
/// Native helpers let a host application extend the helpers of a transformation
/// with behaviour that ATL cannot express, such as formatting, lookups or text
/// generation. They are supplied when an ``ATLVirtualMachine`` is created, or
/// later through ``ATLVirtualMachine/register(_:)``.
///
/// A helper with a ``contextType`` is a contextual helper: an expression such as
/// `s.render('x')` calls it with the receiver `s` and the argument `'x'`. A helper
/// without a context type is a module-level helper, called as `greet('a')` or
/// `thisModule.greet('a')`, and receives no receiver. Helpers are found by name and
/// number of arguments; contextual helpers are also selected by the dynamic type of
/// the receiver, and the most specific context type wins. The parameter and return
/// type names describe the helper for lookup and diagnostics. They are not checked
/// against the values passed.
///
/// A native helper takes precedence over a module helper of the same name, context
/// type and number of arguments, so a host can override a helper that the
/// transformation declares. An error thrown by the body is reported as an
/// ``ATLExecutionError`` that names the helper.
///
/// ```swift
/// let greet = ATLNativeHelper(
///     name: "greet", parameterTypes: ["String"], returnType: "String"
/// ) { _, arguments in
///     "hello \(arguments.first.flatMap { $0 as? String } ?? "")"
/// }
/// let machine = ATLVirtualMachine(module: module, nativeHelpers: [greet])
/// ```
public struct ATLNativeHelper: ATLHelperType, Sendable {

    /// The code of a native helper.
    ///
    /// - Parameters:
    ///   - receiver: The value the helper is called on, or `nil` for a module-level
    ///     helper and for the undefined value.
    ///   - arguments: The evaluated arguments, in order.
    /// - Returns: The value of the call, or `nil` for the undefined value.
    public typealias Body =
        @MainActor @Sendable (_ receiver: (any EcoreValue)?, _ arguments: [(any EcoreValue)?])
            async throws -> (any EcoreValue)?

    /// The name by which ATL expressions call the helper.
    public let name: String

    /// The type the helper is declared for, or `nil` for a module-level helper.
    public let contextType: String?

    /// The names of the types of the parameters, one per argument.
    public let parameterTypes: [String]

    /// The name of the type of the result.
    public let returnType: String

    /// The code that computes the result of a call.
    public let body: Body

    /// The parameters of the helper, named `p0`, `p1` and so on.
    public var parameters: [ATLParameter] {
        parameterTypes.enumerated().map { ATLParameter(name: "p\($0.offset)", type: $0.element) }
    }

    /// Creates a native helper.
    ///
    /// - Parameters:
    ///   - name: The name by which ATL expressions call the helper.
    ///   - contextType: The type the helper is declared for, or `nil` (the default) for a
    ///     module-level helper.
    ///   - parameterTypes: The names of the types of the parameters; their number is the
    ///     number of arguments a call must pass. The default is no parameters.
    ///   - returnType: The name of the type of the result.
    ///   - body: The code that computes the result of a call.
    public init(
        name: String, contextType: String? = nil, parameterTypes: [String] = [],
        returnType: String, body: @escaping Body
    ) {
        self.name = name
        self.contextType = contextType
        self.parameterTypes = parameterTypes
        self.returnType = returnType
        self.body = body
    }

    /// Whether another helper is the same native helper by name, context and signature.
    ///
    /// - Parameter other: The helper to compare with.
    /// - Returns: `true` when `other` is a native helper with the same signature.
    public func isEqual(to other: any ATLHelperType) -> Bool {
        guard let other = other as? ATLNativeHelper else { return false }
        return name == other.name && contextType == other.contextType
            && parameterTypes == other.parameterTypes && returnType == other.returnType
    }

    /// A hash value of the name, context and signature.
    ///
    /// - Returns: The hash value.
    public func hashValue() -> Int {
        var hasher = Hasher()
        hasher.combine(name)
        hasher.combine(contextType)
        hasher.combine(parameterTypes)
        hasher.combine(returnType)
        return hasher.finalize()
    }
}

extension ATLExecutionContext {

    /// Finds the native helper for a receiver, name and number of arguments.
    ///
    /// - Parameters:
    ///   - name: The helper name.
    ///   - receiver: The receiver value, or `nil` to look for a module-level helper.
    ///   - argumentCount: The number of arguments of the call.
    ///   - includingOclAny: Whether helpers declared for `OclAny` may be selected.
    /// - Returns: The most specific applicable native helper, or `nil`.
    func nativeHelper(
        named name: String, receiver: (any EcoreValue)?, argumentCount: Int,
        includingOclAny: Bool = true
    ) -> ATLNativeHelper? {
        var best: (helper: ATLNativeHelper, distance: Int)?
        for candidate in nativeHelpers
        where candidate.name == name && candidate.parameterTypes.count == argumentCount {
            guard let contextType = candidate.contextType else {
                if receiver == nil, best == nil { best = (candidate, 0) }
                continue
            }
            guard let receiver,
                let distance = ATLTypeMatching.distance(of: receiver, to: contextType),
                includingOclAny || distance < ATLTypeMatching.anyDistance
            else { continue }
            if best == nil || distance < best!.distance { best = (candidate, distance) }
        }
        return best?.helper
    }

    /// Calls a native helper, reporting a failure of its body by helper name.
    ///
    /// - Parameters:
    ///   - helper: The helper to call.
    ///   - receiver: The receiver value, or `nil` for a module-level helper.
    ///   - arguments: The evaluated arguments.
    /// - Returns: The value computed by the helper.
    /// - Throws: ``ATLExecutionError/runtimeError(_:)`` naming the helper when its body
    ///   throws; cancellation is rethrown unchanged.
    func invokeNativeHelper(
        _ helper: ATLNativeHelper, receiver: (any EcoreValue)?, arguments: [(any EcoreValue)?]
    ) async throws -> (any EcoreValue)? {
        do {
            return try await helper.body(receiver, arguments)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw ATLExecutionError.runtimeError(
                "Native helper '\(helper.name)' failed: \(error)")
        }
    }

    /// Adds a native helper, replacing one with the same name, context and arity.
    ///
    /// - Parameter helper: The helper to add.
    func addNativeHelper(_ helper: ATLNativeHelper) {
        nativeHelpers.removeAll {
            $0.name == helper.name && $0.contextType == helper.contextType
                && $0.parameterTypes.count == helper.parameterTypes.count
        }
        nativeHelpers.append(helper)
    }
}
