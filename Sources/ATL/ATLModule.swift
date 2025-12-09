//
//  ATLModule.swift
//  ATL
//
//  Created by Rene Hexel on 6/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import ECore
import Foundation
import OrderedCollections

/// Represents an ATL (Atlas Transformation Language) module.
///
/// An ATL module is the root container for a transformation specification, containing
/// source and target metamodels, helper functions, transformation rules, and module-level
/// configuration. ATL modules define unidirectional transformations from source models
/// to target models using declarative matched rules and imperative called rules.
///
/// ## Overview
///
/// ATL modules follow a structured approach to model transformation:
/// - **Source models**: Read-only input models conforming to source metamodels
/// - **Target models**: Write-only output models conforming to target metamodels
/// - **Helpers**: Reusable functions that extend OCL with custom operations
/// - **Matched rules**: Declarative transformation rules triggered automatically
/// - **Called rules**: Imperative transformation rules invoked explicitly
///
/// ## Example Usage
///
/// ```swift
/// let module = ATLModule(
///     name: "Families2Persons",
///     sourceMetamodels: ["Families": familiesPackage],
///     targetMetamodels: ["Persons": personsPackage],
///     helpers: ["familyName": familyNameHelper],
///     matchedRules: [member2MaleRule, member2FemaleRule]
/// )
/// ```
///
/// - Note: ATL modules are designed as immutable value types to enable safe concurrent
///   processing and transformation execution across multiple actors.
public struct ATLModule: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The name of the ATL module.
    ///
    /// Module names must be valid identifiers and are used for namespace resolution
    /// and debugging purposes during transformation execution.
    public let name: String

    /// Source metamodels indexed by their namespace aliases.
    ///
    /// Source metamodels define the structure of input models that will be transformed.
    /// Each metamodel is associated with an alias used in ATL expressions for type
    /// references and navigation operations.
    public let sourceMetamodels: OrderedDictionary<String, EPackage>

    /// Target metamodels indexed by their namespace aliases.
    ///
    /// Target metamodels define the structure of output models that will be created
    /// during transformation execution. Each metamodel is associated with an alias
    /// used in ATL rules for element creation and property assignment.
    public let targetMetamodels: OrderedDictionary<String, EPackage>

    /// Helper functions indexed by their names.
    ///
    /// Helpers extend the OCL standard library with custom operations that can be
    /// invoked from transformation rules and other helpers. They support both
    /// context-dependent and context-independent implementations.
    public let helpers: OrderedDictionary<String, any ATLHelperType>

    /// Matched rules for automatic transformation execution.
    ///
    /// Matched rules are executed automatically for all source elements that match
    /// their input patterns and satisfy their guard conditions. They form the
    /// declarative backbone of ATL transformations.
    public let matchedRules: [ATLMatchedRule]

    /// Called rules indexed by their names.
    ///
    /// Called rules are executed explicitly through rule invocation expressions.
    /// They support parameterised transformations and imperative control flow
    /// within the otherwise declarative ATL framework.
    public let calledRules: OrderedDictionary<String, ATLCalledRule>

    // MARK: - Initialisation

    /// Creates a new ATL module with the specified configuration.
    ///
    /// - Parameters:
    ///   - name: The module name, used for identification and debugging
    ///   - sourceMetamodels: Source metamodels indexed by namespace aliases
    ///   - targetMetamodels: Target metamodels indexed by namespace aliases
    ///   - helpers: Helper functions indexed by their names (default: empty)
    ///   - matchedRules: Matched rules for automatic execution (default: empty)
    ///   - calledRules: Called rules indexed by their names (default: empty)
    ///
    /// - Precondition: The module name must be a non-empty string
    /// - Precondition: At least one source metamodel must be specified
    /// - Precondition: At least one target metamodel must be specified
    public init(
        name: String,
        sourceMetamodels: OrderedDictionary<String, EPackage>,
        targetMetamodels: OrderedDictionary<String, EPackage>,
        helpers: OrderedDictionary<String, any ATLHelperType> = [:],
        matchedRules: [ATLMatchedRule] = [],
        calledRules: OrderedDictionary<String, ATLCalledRule> = [:]
    ) {
        precondition(!name.isEmpty, "Module name must not be empty")
        precondition(!sourceMetamodels.isEmpty, "At least one source metamodel must be specified")
        precondition(!targetMetamodels.isEmpty, "At least one target metamodel must be specified")

        self.name = name
        self.sourceMetamodels = sourceMetamodels
        self.targetMetamodels = targetMetamodels
        self.helpers = helpers
        self.matchedRules = matchedRules
        self.calledRules = calledRules
    }

    // MARK: - Hashable

    // MARK: - Equatable

    public static func == (lhs: ATLModule, rhs: ATLModule) -> Bool {
        return lhs.name == rhs.name
            && areMetamodelsEqual(lhs.sourceMetamodels, rhs.sourceMetamodels)
            && areMetamodelsEqual(lhs.targetMetamodels, rhs.targetMetamodels)
            && lhs.helpers.keys == rhs.helpers.keys
            && lhs.helpers.allSatisfy { key, lhsHelper in
                if let rhsHelper = rhs.helpers[key] {
                    return lhsHelper.isEqual(to: rhsHelper)
                }
                return false
            }
            && lhs.matchedRules == rhs.matchedRules
            && lhs.calledRules == rhs.calledRules
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(sourceMetamodels.keys.sorted())
        hasher.combine(targetMetamodels.keys.sorted())
        // Hash metamodel content semantically
        for (key, package) in sourceMetamodels.sorted(by: { $0.key < $1.key }) {
            hasher.combine(key)
            hashEPackageSemantics(package, into: &hasher)
        }
        for (key, package) in targetMetamodels.sorted(by: { $0.key < $1.key }) {
            hasher.combine(key)
            hashEPackageSemantics(package, into: &hasher)
        }
        for (key, helper) in helpers.sorted(by: { $0.key < $1.key }) {
            hasher.combine(key)
            hasher.combine(helper.hashValue())
        }
        hasher.combine(matchedRules)
        hasher.combine(calledRules.keys.sorted())
    }
}

// MARK: - Semantic Equality Helpers

/// Compare two metamodel dictionaries for semantic equality.
private func areMetamodelsEqual(
    _ lhs: OrderedDictionary<String, EPackage>,
    _ rhs: OrderedDictionary<String, EPackage>
) -> Bool {
    guard lhs.count == rhs.count else { return false }

    for (key, lhsPackage) in lhs {
        guard let rhsPackage = rhs[key] else { return false }
        if !areEPackagesEqual(lhsPackage, rhsPackage) {
            return false
        }
    }
    return true
}

/// Compare two EPackages for semantic equality (ignoring unique IDs).
private func areEPackagesEqual(_ lhs: EPackage, _ rhs: EPackage) -> Bool {
    return lhs.name == rhs.name
        && lhs.nsURI == rhs.nsURI
        && lhs.nsPrefix == rhs.nsPrefix
        && lhs.eClassifiers.count == rhs.eClassifiers.count
        && lhs.eSubpackages.count == rhs.eSubpackages.count
}

/// Hash an EPackage based on semantic content (ignoring unique IDs).
private func hashEPackageSemantics(_ package: EPackage, into hasher: inout Hasher) {
    hasher.combine(package.name)
    hasher.combine(package.nsURI)
    hasher.combine(package.nsPrefix)
    hasher.combine(package.eClassifiers.count)
    hasher.combine(package.eSubpackages.count)
}

// MARK: - ATL Helper Type Protocol

/// Protocol for type-erased ATL helper storage.
///
/// This protocol allows ATL helpers with different body expression types
/// to be stored together in collections while maintaining type safety
/// at the individual helper level.
public protocol ATLHelperType: Sendable {
    /// The name of the helper function.
    var name: String { get }

    /// The context type for contextual helpers, or `nil` for context-free helpers.
    var contextType: String? { get }

    /// The return type of the helper function.
    var returnType: String { get }

    /// The parameters accepted by the helper function.
    var parameters: [ATLParameter] { get }

    /// Check if two helpers are equal for their identifying properties
    func isEqual(to other: any ATLHelperType) -> Bool

    /// Get hash value for the helper's identifying properties
    func hashValue() -> Int
}

// MARK: - ATL Helper

/// Represents an ATL helper function.
///
/// ATL helpers extend the OCL standard library with custom operations that can be
/// reused across transformation rules and other helpers. They support both contextual
/// helpers (associated with a specific type) and contextual-free helpers (global functions).
///
/// ## Overview
///
/// Helpers in ATL serve multiple purposes:
/// - **Code reuse**: Complex expressions can be encapsulated and reused
/// - **Type extension**: New operations can be added to existing types
/// - **Modularity**: Complex transformations can be broken down into manageable functions
/// - **Testing**: Individual helper functions can be tested independently
///
/// ## Example Usage
///
/// ```swift
/// // Contextual helper for Family!Member
/// let familyNameHelper = ATLHelper(
///     name: "familyName",
///     contextType: "Families!Member",
///     returnType: "String",
///     parameters: [],
///     body: navigationExpression
/// )
///
/// // Context-free helper
/// let utilityHelper = ATLHelper(
///     name: "formatName",
///     contextType: nil,
///     returnType: "String",
///     parameters: [firstNameParam, lastNameParam],
///     body: concatenationExpression
/// )
/// ```
public struct ATLHelper<BodyExpression: ATLExpression>: ATLHelperType, Sendable, Equatable, Hashable
{

    // MARK: - Properties

    /// The name of the helper function.
    ///
    /// Helper names must be valid identifiers and are used for invocation
    /// from ATL expressions and other helpers.
    public let name: String

    /// The context type for contextual helpers, or `nil` for context-free helpers.
    ///
    /// Contextual helpers are associated with a specific type and can access
    /// the `self` variable. Context-free helpers operate as global functions
    /// and receive all data through explicit parameters.
    public let contextType: String?

    /// The return type of the helper function.
    ///
    /// Return types are specified using ATL type expressions, supporting
    /// both primitive types and metamodel element types.
    public let returnType: String

    /// The parameters accepted by the helper function.
    ///
    /// Parameters enable helpers to accept additional inputs beyond the
    /// contextual `self` variable for contextual helpers.
    public let parameters: [ATLParameter]

    /// The body expression that defines the helper's computation.
    ///
    /// The body expression is evaluated to compute the helper's return value.
    /// It has access to the contextual `self` variable (for contextual helpers)
    /// and all declared parameters.
    public let body: BodyExpression

    // MARK: - Initialisation

    /// Creates a new ATL helper function.
    ///
    /// - Parameters:
    ///   - name: The helper name for invocation
    ///   - contextType: The context type, or `nil` for context-free helpers
    ///   - returnType: The return type specification
    ///   - parameters: The parameter list (default: empty)
    ///   - body: The expression that computes the helper's result
    ///
    /// - Precondition: The helper name must be a non-empty string
    /// - Precondition: The return type must be a non-empty string
    public init(
        name: String,
        contextType: String? = nil,
        returnType: String,
        parameters: [ATLParameter] = [],
        body: BodyExpression
    ) {
        precondition(!name.isEmpty, "Helper name must not be empty")
        precondition(!returnType.isEmpty, "Return type must not be empty")

        self.name = name
        self.contextType = contextType
        self.returnType = returnType
        self.parameters = parameters
        self.body = body
    }

    // MARK: - Equatable

    public static func == (lhs: ATLHelper<BodyExpression>, rhs: ATLHelper<BodyExpression>) -> Bool {
        return lhs.name == rhs.name && lhs.contextType == rhs.contextType
            && lhs.returnType == rhs.returnType && lhs.parameters == rhs.parameters
            && lhs.body == rhs.body
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(contextType)
        hasher.combine(returnType)
        hasher.combine(parameters)
        hasher.combine(body)
    }

    // MARK: - ATLHelperType

    public func isEqual(to other: any ATLHelperType) -> Bool {
        guard let other = other as? ATLHelper<BodyExpression> else {
            return false
        }
        return self == other
    }

    public func hashValue() -> Int {
        var hasher = Hasher()
        hash(into: &hasher)
        return hasher.finalize()
    }
}

// MARK: - ATL Parameter

/// Represents a parameter for ATL helpers and called rules.
///
/// Parameters define the interface for data passing into ATL functions and rules.
/// They specify both the parameter name for binding and the expected type for
/// validation during transformation compilation and execution.
///
/// ## Example Usage
///
/// ```swift
/// let nameParameter = ATLParameter(name: "firstName", type: "String")
/// let elementParameter = ATLParameter(name: "sourceElement", type: "Families!Member")
/// ```
public struct ATLParameter: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The name of the parameter.
    ///
    /// Parameter names are used for variable binding within the scope of
    /// helper functions and called rules.
    public let name: String

    /// The type of the parameter.
    ///
    /// Parameter types are specified using ATL type expressions, supporting
    /// both primitive types and metamodel element types.
    public let type: String

    // MARK: - Initialisation

    /// Creates a new ATL parameter.
    ///
    /// - Parameters:
    ///   - name: The parameter name for variable binding
    ///   - type: The parameter type specification
    ///
    /// - Precondition: The parameter name must be a non-empty string
    /// - Precondition: The parameter type must be a non-empty string
    public init(name: String, type: String) {
        precondition(!name.isEmpty, "Parameter name must not be empty")
        precondition(!type.isEmpty, "Parameter type must not be empty")

        self.name = name
        self.type = type
    }
}

// MARK: - Type-Erased Helper Wrapper

/// Type-erased wrapper for ATL helpers to enable parser instantiation.
///
/// This wrapper allows the parser to create helpers without specifying concrete
/// expression types, while maintaining ATL compliance and type safety at runtime.
public struct ATLHelperWrapper: ATLHelperType, Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The name of the helper function.
    public let name: String

    /// The optional context type for contextual helpers.
    public let contextType: String?

    /// The return type of the helper function.
    public let returnType: String

    /// The parameters accepted by the helper function.
    public let parameters: [ATLParameter]

    /// The body expression (stored as any ATLExpression).
    public let bodyExpression: any ATLExpression

    // MARK: - Initialisation

    /// Creates a type-erased helper wrapper.
    ///
    /// - Parameters:
    ///   - name: The helper function name
    ///   - contextType: Optional context type for contextual helpers
    ///   - returnType: The return type specification
    ///   - parameters: The parameter list
    ///   - body: The body expression
    public init(
        name: String,
        contextType: String? = nil,
        returnType: String,
        parameters: [ATLParameter] = [],
        body: any ATLExpression
    ) {
        self.name = name
        self.contextType = contextType
        self.returnType = returnType
        self.parameters = parameters
        self.bodyExpression = body
    }

    // MARK: - ATLHelperType Conformance

    @MainActor
    public func evaluate(with arguments: [(any EcoreValue)?], in context: ATLExecutionContext)
        async throws -> (any EcoreValue)?
    {
        // Set up parameter bindings in execution context
        context.pushScope()

        defer {
            context.popScope()
        }

        for (parameter, argument) in zip(parameters, arguments) {
            context.setVariable(parameter.name, value: argument)
        }

        // Evaluate the body expression
        return try await bodyExpression.evaluate(in: context)
    }

    public func isEqual(to other: any ATLHelperType) -> Bool {
        guard let otherWrapper = other as? ATLHelperWrapper else {
            return false
        }
        return self == otherWrapper
    }

    public func hashValue() -> Int {
        var hasher = Hasher()
        self.hash(into: &hasher)
        return hasher.finalize()
    }

    // MARK: - Equatable

    public static func == (lhs: ATLHelperWrapper, rhs: ATLHelperWrapper) -> Bool {
        return lhs.name == rhs.name
            && lhs.contextType == rhs.contextType
            && lhs.returnType == rhs.returnType
            && lhs.parameters == rhs.parameters
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(contextType)
        hasher.combine(returnType)
        hasher.combine(parameters)
    }
}
