//
//  ATLModule.swift
//  ATL
//
//  Created by Rene Hexel on 6/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
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

    /// Every helper definition, grouped by helper name.
    ///
    /// Contextual helpers may share a name when their context types differ, so
    /// ``helpers`` (which holds one helper per name) cannot represent them all.
    /// This table holds every definition; contextual helpers are selected from
    /// it by the dynamic type of the receiver, and context-free helpers have a
    /// `nil` context type. Helpers supplied only through ``helpers`` are added
    /// to this table on creation.
    public let helperOverloads: OrderedDictionary<String, [any ATLHelperType]>

    /// The parameters declared by `-- @param` header comments.
    ///
    /// Values for these parameters are supplied when the transformation is
    /// executed and are read in the transformation as `thisModule.<name>`.
    public let parameters: [ATLModuleParameter]

    /// The metamodel names as written in the module header, indexed by model alias.
    ///
    /// Type references in rules and expressions (`Ecore!EClass`) use the name
    /// declared in the header, which need not equal the name of the bound package.
    public let declaredMetamodelNames: [String: String]

    // MARK: - Initialisation

    /// The source range the node was parsed from, if it was parsed.
    ///
    /// The origin never takes part in equality or hashing, so nodes that differ only
    /// in where they were written compare equal.
    public let origin: SourceOrigin

    /// Creates a new ATL module with the specified configuration.
    ///
    /// - Parameters:
    ///   - name: The module name, used for identification and debugging
    ///   - sourceMetamodels: Source metamodels indexed by namespace aliases
    ///   - targetMetamodels: Target metamodels indexed by namespace aliases
    ///   - helpers: Helper functions indexed by their names (default: empty)
    ///   - matchedRules: Matched rules for automatic execution (default: empty)
    ///   - calledRules: Called rules indexed by their names (default: empty)
    ///   - helperOverloads: Every helper definition grouped by name (default: derived from `helpers`)
    ///   - parameters: The declared module parameters (default: none)
    ///   - declaredMetamodelNames: The header metamodel names by alias (default: the package names)
    ///   - origin: The source range the node was parsed from.
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
        calledRules: OrderedDictionary<String, ATLCalledRule> = [:],
        helperOverloads: OrderedDictionary<String, [any ATLHelperType]> = [:],
        parameters: [ATLModuleParameter] = [],
        declaredMetamodelNames: [String: String]? = nil,
        origin: SourceOrigin = .init()
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
        self.helperOverloads = Self.mergingOverloads(helperOverloads, with: helpers)
        self.parameters = parameters
        self.declaredMetamodelNames =
            declaredMetamodelNames
            ?? Dictionary(
                Array(sourceMetamodels).map { ($0.key, $0.value.name) }
                    + Array(targetMetamodels).map { ($0.key, $0.value.name) },
                uniquingKeysWith: { first, _ in first })
        self.origin = origin
    }

    /// Returns a copy of this module bound to different metamodel packages.
    ///
    /// All other members, including the declared metamodel names, are kept.
    ///
    /// - Parameters:
    ///   - sourceMetamodels: The new source metamodels indexed by alias.
    ///   - targetMetamodels: The new target metamodels indexed by alias.
    /// - Returns: The rebound module.
    public func withMetamodels(
        source sourceMetamodels: OrderedDictionary<String, EPackage>,
        target targetMetamodels: OrderedDictionary<String, EPackage>
    ) -> ATLModule {
        ATLModule(
            name: name,
            sourceMetamodels: sourceMetamodels,
            targetMetamodels: targetMetamodels,
            helpers: helpers,
            matchedRules: matchedRules,
            calledRules: calledRules,
            helperOverloads: helperOverloads,
            parameters: parameters,
            declaredMetamodelNames: declaredMetamodelNames,
            origin: origin
        )
    }

    /// Returns a copy of this module with the given declared parameters.
    ///
    /// - Parameter parameters: The module parameters.
    /// - Returns: The module with its parameters replaced.
    public func withParameters(_ parameters: [ATLModuleParameter]) -> ATLModule {
        ATLModule(
            name: name,
            sourceMetamodels: sourceMetamodels,
            targetMetamodels: targetMetamodels,
            helpers: helpers,
            matchedRules: matchedRules,
            calledRules: calledRules,
            helperOverloads: helperOverloads,
            parameters: parameters,
            declaredMetamodelNames: declaredMetamodelNames,
            origin: origin
        )
    }

    // MARK: - Metamodel Lookup

    /// Finds the alias of the source model whose metamodel has the given name.
    ///
    /// The name is compared with the name declared in the module header first
    /// and with the name of the bound package second.
    ///
    /// - Parameter metamodelName: The metamodel name used in a type reference.
    /// - Returns: The model alias, or `nil` when no source metamodel matches.
    public func sourceAlias(forMetamodel metamodelName: String) -> String? {
        Self.alias(forMetamodel: metamodelName, in: sourceMetamodels, declared: declaredMetamodelNames)
    }

    /// Finds the alias of the target model whose metamodel has the given name.
    ///
    /// The name is compared with the name declared in the module header first
    /// and with the name of the bound package second.
    ///
    /// - Parameter metamodelName: The metamodel name used in a type reference.
    /// - Returns: The model alias, or `nil` when no target metamodel matches.
    public func targetAlias(forMetamodel metamodelName: String) -> String? {
        Self.alias(forMetamodel: metamodelName, in: targetMetamodels, declared: declaredMetamodelNames)
    }

    private static func alias(
        forMetamodel metamodelName: String,
        in metamodels: OrderedDictionary<String, EPackage>,
        declared: [String: String]
    ) -> String? {
        metamodels.first(where: { declared[$0.key] == metamodelName })?.key
            ?? metamodels.first(where: { $0.value.name == metamodelName })?.key
    }

    private static func mergingOverloads(
        _ overloads: OrderedDictionary<String, [any ATLHelperType]>,
        with helpers: OrderedDictionary<String, any ATLHelperType>
    ) -> OrderedDictionary<String, [any ATLHelperType]> {
        var merged = overloads
        for (name, helper) in helpers {
            let existing = merged[name] ?? []
            if !existing.contains(where: { $0.contextType == helper.contextType }) {
                merged[name] = existing + [helper]
            }
        }
        return merged
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

    /// The source range the node was parsed from, or an empty origin for a node built in code.
    var origin: SourceOrigin { get }

    /// Check if two helpers are equal for their identifying properties
    func isEqual(to other: any ATLHelperType) -> Bool

    /// Get hash value for the helper's identifying properties
    func hashValue() -> Int
}

extension ATLHelperType {
    /// The source range the node was parsed from, or an empty origin for a node built in code.
    public var origin: SourceOrigin { SourceOrigin() }
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

    /// The source range the node was parsed from, if it was parsed.
    ///
    /// The origin never takes part in equality or hashing, so nodes that differ only
    /// in where they were written compare equal.
    public let origin: SourceOrigin

    /// Creates a new ATL helper function.
    ///
    /// - Parameters:
    ///   - name: The helper name for invocation
    ///   - contextType: The context type, or `nil` for context-free helpers
    ///   - returnType: The return type specification
    ///   - parameters: The parameter list (default: empty)
    ///   - body: The expression that computes the helper's result
    ///   - origin: The source range the node was parsed from.
    ///
    /// - Precondition: The helper name must be a non-empty string
    /// - Precondition: The return type must be a non-empty string
    public init(
        name: String,
        contextType: String? = nil,
        returnType: String,
        parameters: [ATLParameter] = [],
        body: BodyExpression,
        origin: SourceOrigin = .init()
    ) {
        precondition(!name.isEmpty, "Helper name must not be empty")
        precondition(!returnType.isEmpty, "Return type must not be empty")

        self.name = name
        self.contextType = contextType
        self.returnType = returnType
        self.parameters = parameters
        self.body = body
        self.origin = origin
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

    /// The source range the node was parsed from, if it was parsed.
    ///
    /// The origin never takes part in equality or hashing, so nodes that differ only
    /// in where they were written compare equal.
    public let origin: SourceOrigin

    /// Creates a new ATL parameter.
    ///
    /// - Parameters:
    ///   - name: The parameter name for variable binding
    ///   - type: The parameter type specification
    ///   - origin: The source range the node was parsed from.
    ///
    /// - Precondition: The parameter name must be a non-empty string
    /// - Precondition: The parameter type must be a non-empty string
    public init(name: String, type: String, origin: SourceOrigin = .init()) {
        precondition(!name.isEmpty, "Parameter name must not be empty")
        precondition(!type.isEmpty, "Parameter type must not be empty")

        self.name = name
        self.type = type
        self.origin = origin
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

    /// Whether the helper was declared as an attribute, that is without a parameter list.
    ///
    /// The value of an attribute helper is computed once per receiver and then
    /// reused, as ATL does. Helpers declared with a (possibly empty) parameter
    /// list are operations and are evaluated on every call.
    public let isAttribute: Bool

    // MARK: - Initialisation

    /// The source range the node was parsed from, if it was parsed.
    ///
    /// The origin never takes part in equality or hashing, so nodes that differ only
    /// in where they were written compare equal.
    public let origin: SourceOrigin

    /// Creates a type-erased helper wrapper.
    ///
    /// - Parameters:
    ///   - name: The helper function name
    ///   - contextType: Optional context type for contextual helpers
    ///   - returnType: The return type specification
    ///   - parameters: The parameter list
    ///   - body: The body expression
    ///   - isAttribute: Whether the helper is an attribute whose value is cached per receiver
    ///   - origin: The source range the node was parsed from.
    public init(
        name: String,
        contextType: String? = nil,
        returnType: String,
        parameters: [ATLParameter] = [],
        body: any ATLExpression,
        isAttribute: Bool = false,
        origin: SourceOrigin = .init()
    ) {
        self.name = name
        self.contextType = contextType
        self.returnType = returnType
        self.parameters = parameters
        self.bodyExpression = body
        self.isAttribute = isAttribute
        self.origin = origin
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
            && lhs.isAttribute == rhs.isAttribute
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(contextType)
        hasher.combine(returnType)
        hasher.combine(parameters)
        hasher.combine(isAttribute)
    }
}

// MARK: - Module Parameters

/// The types that a module parameter may have.
public enum ATLParameterType: String, Sendable, CaseIterable, Hashable {
    /// A character string.
    case string = "String"

    /// A whole number.
    case integer = "Integer"

    /// A truth value.
    case boolean = "Boolean"

    /// A floating-point number.
    case real = "Real"
}

/// A value for a module parameter.
public enum ATLParameterValue: Sendable, Hashable {
    /// A string value.
    case string(String)

    /// An integer value.
    case integer(Int)

    /// A boolean value.
    case boolean(Bool)

    /// A real value.
    case real(Double)

    /// The value as it is seen by transformation expressions.
    public var ecoreValue: any EcoreValue {
        switch self {
        case .string(let value): return value
        case .integer(let value): return value
        case .boolean(let value): return value
        case .real(let value): return value
        }
    }
}

/// A module parameter declared with a `-- @param name : Type = default` header comment.
///
/// A parameter without a default value is required: executing the module
/// without a value for it fails with ``ATLExecutionError/missingParameter(_:)``.
///
/// ## Example Usage
///
/// ```swift
/// // -- @param basePackage : String = 'org.example'
/// // -- @param generateTests : Boolean = false
/// // -- @param projectName : String
/// ```
public struct ATLModuleParameter: Sendable, Equatable, Hashable {

    /// The parameter name, used as `thisModule.<name>`.
    public let name: String

    /// The declared type of the parameter.
    public let type: ATLParameterType

    /// The value used when the caller supplies none, or `nil` for a required parameter.
    public let defaultValue: ATLParameterValue?

    /// Whether the caller must supply a value.
    public var isRequired: Bool { defaultValue == nil }

    /// Creates a module parameter.
    ///
    /// - Parameters:
    ///   - name: The parameter name.
    ///   - type: The declared type.
    ///   - defaultValue: The default value, or `nil` to make the parameter required.
    public init(name: String, type: ATLParameterType, defaultValue: ATLParameterValue? = nil) {
        self.name = name
        self.type = type
        self.defaultValue = defaultValue
    }

    /// Converts the text of a value to this parameter's type.
    ///
    /// Strings are taken verbatim; the other types are parsed. This is the
    /// conversion command line tools use for `--param name=value`.
    ///
    /// - Parameter text: The textual value.
    /// - Returns: The typed value.
    /// - Throws: ``ATLExecutionError/typeError(_:)`` when the text is not a valid value of the type.
    public func value(fromText text: String) throws -> ATLParameterValue {
        switch type {
        case .string:
            return .string(text)
        case .integer:
            guard let value = Int(text) else {
                throw ATLExecutionError.typeError(
                    "Parameter '\(name)' expects an Integer but was given '\(text)'")
            }
            return .integer(value)
        case .boolean:
            switch text.lowercased() {
            case "true": return .boolean(true)
            case "false": return .boolean(false)
            default:
                throw ATLExecutionError.typeError(
                    "Parameter '\(name)' expects a Boolean but was given '\(text)'")
            }
        case .real:
            guard let value = Double(text) else {
                throw ATLExecutionError.typeError(
                    "Parameter '\(name)' expects a Real but was given '\(text)'")
            }
            return .real(value)
        }
    }

    /// Checks a supplied value against this parameter's type.
    ///
    /// Integers are accepted for real parameters and converted.
    ///
    /// - Parameter value: The value supplied by the caller.
    /// - Returns: The value in the representation of the declared type.
    /// - Throws: ``ATLExecutionError/typeError(_:)`` when the value has the wrong type.
    public func validated(_ value: any EcoreValue) throws -> any EcoreValue {
        switch (type, value) {
        case (.string, is String), (.integer, is Int), (.boolean, is Bool), (.real, is Double):
            return value
        case (.real, let integer as Int):
            return Double(integer)
        default:
            throw ATLExecutionError.typeError(
                "Parameter '\(name)' expects a \(type.rawValue) but was given \(Swift.type(of: value))")
        }
    }
}

extension ATLModule {

    /// Converts textual parameter values to the types the module declares.
    ///
    /// - Parameter text: The textual values by parameter name.
    /// - Returns: The typed values by parameter name.
    /// - Throws: ``ATLExecutionError/unknownParameter(_:)`` for undeclared names and
    ///   ``ATLExecutionError/typeError(_:)`` for malformed values.
    public func parameterValues(fromText text: [String: String]) throws -> [String: any EcoreValue] {
        var values: [String: any EcoreValue] = [:]
        for (name, raw) in text {
            guard let declaration = parameters.first(where: { $0.name == name }) else {
                throw ATLExecutionError.unknownParameter(name)
            }
            values[name] = try declaration.value(fromText: raw).ecoreValue
        }
        return values
    }
}
