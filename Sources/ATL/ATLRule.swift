//
//  ATLRule.swift
//  ATL
//
//  Created by Rene Hexel on 6/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

// MARK: - ATL Matched Rule

/// Represents an ATL matched rule for declarative transformation.
///
/// Matched rules form the core of ATL's declarative transformation approach. They are
/// automatically executed for all source elements that match their input patterns and
/// satisfy their optional guard conditions. Each matched rule transforms source elements
/// into one or more target elements through pattern-based specifications.
///
/// ## Overview
///
/// Matched rules operate through several key components:
/// - **Source pattern**: Defines the input element type and optional variable binding
/// - **Guard condition**: Optional boolean expression for conditional rule execution
/// - **Target patterns**: Specify the output elements and their property bindings
/// - **Implicit execution**: Rules are triggered automatically by the ATL virtual machine
///
/// ## Example Usage
///
/// ```swift
/// let member2MaleRule = ATLMatchedRule(
///     name: "Member2Male",
///     sourcePattern: ATLSourcePattern(
///         variableName: "s",
///         type: "Families!Member"
///     ),
///     targetPatterns: [
///         ATLTargetPattern(
///             variableName: "t",
///             type: "Persons!Male",
///             bindings: ["fullName": concatenationExpression]
///         )
///     ],
///     guard: genderCheckExpression
/// )
/// ```
///
/// - Note: Matched rules maintain immutability to enable safe concurrent execution
///   across multiple transformation threads and ensure deterministic results.
public struct ATLMatchedRule: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The name of the matched rule.
    ///
    /// Rule names are used for identification, debugging, and trace link generation
    /// during transformation execution. Names must be unique within a module.
    public let name: String

    /// The source pattern that defines the input specification.
    ///
    /// The source pattern specifies the type of source elements this rule
    /// transforms and provides variable binding for rule expressions.
    public let sourcePattern: ATLSourcePattern

    /// The target patterns that define the output specifications.
    ///
    /// Target patterns specify the types and property bindings for elements
    /// created by this rule. Multiple target patterns enable one-to-many
    /// transformations within a single rule.
    public let targetPatterns: [ATLTargetPattern]

    /// The optional guard condition for conditional rule execution.
    ///
    /// Guard expressions are boolean conditions evaluated for each potential
    /// source element. Only elements satisfying the guard condition will
    /// trigger rule execution. `nil` indicates unconditional execution.
    public let `guard`: (any ATLExpression)?

    // MARK: - Initialisation

    /// Creates a new ATL matched rule.
    ///
    /// - Parameters:
    ///   - name: The rule name for identification and debugging
    ///   - sourcePattern: The input pattern specification
    ///   - targetPatterns: The output pattern specifications
    ///   - guard: Optional boolean expression for conditional execution
    ///
    /// - Precondition: The rule name must be a non-empty string
    /// - Precondition: At least one target pattern must be specified
    public init(
        name: String,
        sourcePattern: ATLSourcePattern,
        targetPatterns: [ATLTargetPattern],
        `guard`: (any ATLExpression)? = nil
    ) {
        precondition(!name.isEmpty, "Rule name must not be empty")
        precondition(!targetPatterns.isEmpty, "At least one target pattern must be specified")

        self.name = name
        self.sourcePattern = sourcePattern
        self.targetPatterns = targetPatterns
        self.`guard` = `guard`
    }

    // MARK: - Equatable

    public static func == (lhs: ATLMatchedRule, rhs: ATLMatchedRule) -> Bool {
        // Compare basic properties
        guard
            lhs.name == rhs.name && lhs.sourcePattern == rhs.sourcePattern
                && lhs.targetPatterns == rhs.targetPatterns
        else {
            return false
        }

        // Compare guard expressions
        switch (lhs.`guard`, rhs.`guard`) {
        case (nil, nil):
            return true
        case (let lhsGuard?, let rhsGuard?):
            // Both have guards - use safe ATL expression comparison
            return areATLExpressionsEqual(lhsGuard, rhsGuard)
        default:
            return false  // One has guard, other doesn't
        }
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(sourcePattern)
        hasher.combine(targetPatterns)
        if let guardExpression = `guard` {
            hashATLExpression(guardExpression, into: &hasher)
        }
    }

}

// MARK: - ATL Called Rule

/// Represents an ATL called rule for imperative transformation.
///
/// Called rules provide imperative control flow within ATL's primarily declarative
/// framework. They are executed explicitly through rule invocation expressions and
/// support parameterised transformations that cannot be expressed through pattern
/// matching alone.
///
/// ## Overview
///
/// Called rules offer several capabilities:
/// - **Explicit invocation**: Called through rule invocation expressions
/// - **Parameterisation**: Accept multiple input parameters beyond pattern matching
/// - **Flexible output**: Can create multiple target elements with complex relationships
/// - **Imperative logic**: Support sequential statement execution and control structures
///
/// ## Example Usage
///
/// ```swift
/// let createPersonRule = ATLCalledRule(
///     name: "CreatePerson",
///     parameters: [
///         ATLParameter(name: "member", type: "Families!Member"),
///         ATLParameter(name: "isMale", type: "Boolean")
///     ],
///     targetPatterns: [
///         ATLTargetPattern(
///             variableName: "person",
///             type: "Persons!Person",
///             bindings: ["name": nameExpression]
///         )
///     ],
///     body: [assignmentStatement, conditionalStatement]
/// )
/// ```
public struct ATLCalledRule: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The name of the called rule.
    ///
    /// Rule names are used for explicit invocation from expressions and other
    /// rules. Names must be unique within a module's called rule namespace.
    public let name: String

    /// The parameters accepted by the called rule.
    ///
    /// Parameters enable called rules to receive inputs beyond the implicit
    /// context available in matched rules. They support flexible and reusable
    /// transformation patterns.
    public let parameters: [ATLParameter]

    /// The target patterns that define the output specifications.
    ///
    /// Target patterns specify the types and property bindings for elements
    /// created by this rule. Called rules can create multiple related elements
    /// through coordinated target patterns.
    public let targetPatterns: [ATLTargetPattern]

    /// The imperative statements executed by the called rule.
    ///
    /// The rule body contains a sequence of statements that perform the actual
    /// transformation logic, including element creation, property assignment,
    /// and control flow operations.
    public let body: [any ATLStatement]

    // MARK: - Initialisation

    /// Creates a new ATL called rule.
    ///
    /// - Parameters:
    ///   - name: The rule name for invocation
    ///   - parameters: The parameter specifications
    ///   - targetPatterns: The output pattern specifications
    ///   - body: The imperative statements to execute
    ///
    /// - Precondition: The rule name must be a non-empty string
    public init(
        name: String,
        parameters: [ATLParameter] = [],
        targetPatterns: [ATLTargetPattern] = [],
        body: [any ATLStatement] = []
    ) {
        precondition(!name.isEmpty, "Rule name must not be empty")

        self.name = name
        self.parameters = parameters
        self.targetPatterns = targetPatterns
        self.body = body
    }

    // MARK: - Equatable

    public static func == (lhs: ATLCalledRule, rhs: ATLCalledRule) -> Bool {
        return lhs.name == rhs.name && lhs.parameters == rhs.parameters
            && lhs.targetPatterns.count == rhs.targetPatterns.count
            && lhs.body.count == rhs.body.count
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(parameters)
        hasher.combine(targetPatterns.count)
        hasher.combine(body.count)
    }
}

// MARK: - ATL Source Pattern

/// Represents the source pattern of an ATL matched rule.
///
/// Source patterns define the input specification for matched rules, including the
/// type of source elements to match, the variable name for binding within the
/// rule's scope, and optional guard expressions for conditional matching.
///
/// ## Example Usage
///
/// ```swift
/// let memberPattern = ATLSourcePattern(
///     variableName: "sourceMember",
///     type: "Families!Member",
///     guard: ageCheckExpression
/// )
/// ```
public struct ATLSourcePattern: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The variable name for binding the matched source element.
    ///
    /// This variable name is used throughout the rule's expressions to reference
    /// the matched source element and access its properties.
    public let variableName: String

    /// The type of source elements matched by this pattern.
    ///
    /// Type specifications use ATL's type syntax, supporting both primitive types
    /// and metamodel element types with namespace prefixes.
    public let type: String

    /// The optional guard condition for conditional pattern matching.
    ///
    /// Guard expressions are boolean conditions evaluated for each potential
    /// source element. Only elements satisfying the guard condition will
    /// match this pattern. `nil` indicates unconditional matching.
    public let `guard`: (any ATLExpression)?

    // MARK: - Initialisation

    /// Creates a new ATL source pattern.
    ///
    /// - Parameters:
    ///   - variableName: The variable name for element binding
    ///   - type: The type specification for pattern matching
    ///   - guard: Optional boolean expression for conditional matching
    ///
    /// - Precondition: The variable name must be a non-empty string
    /// - Precondition: The type specification must be a non-empty string
    public init(variableName: String, type: String, `guard`: (any ATLExpression)? = nil) {
        precondition(!variableName.isEmpty, "Variable name must not be empty")
        precondition(!type.isEmpty, "Type specification must not be empty")

        self.variableName = variableName
        self.type = type
        self.`guard` = `guard`
    }

    // MARK: - Equatable

    public static func == (lhs: ATLSourcePattern, rhs: ATLSourcePattern) -> Bool {
        guard lhs.variableName == rhs.variableName && lhs.type == rhs.type else {
            return false
        }

        // Compare guard expressions
        switch (lhs.`guard`, rhs.`guard`) {
        case (nil, nil):
            return true
        case (let lhsGuard?, let rhsGuard?):
            return AnyHashable(lhsGuard) == AnyHashable(rhsGuard)
        default:
            return false
        }
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(variableName)
        hasher.combine(type)
        if let guardExpression = `guard` {
            hasher.combine(AnyHashable(guardExpression))
        }
    }
}

// MARK: - ATL Target Pattern

/// Represents a target pattern for element creation in ATL rules.
///
/// Target patterns define the output specifications for both matched and called rules.
/// They specify the type of target elements to create, variable binding for reference
/// within the rule, and property bindings that define the relationships and values
/// for the created elements.
///
/// ## Overview
///
/// Target patterns support several key features:
/// - **Element creation**: Automatic instantiation of target metamodel elements
/// - **Property binding**: Declarative specification of property values
/// - **Reference resolution**: Automatic handling of cross-references and containment
/// - **Variable scoping**: Local variables accessible to other patterns and expressions
///
/// ## Example Usage
///
/// ```swift
/// let personPattern = ATLTargetPattern(
///     variableName: "targetPerson",
///     type: "Persons!Person",
///     bindings: [
///         "fullName": ATLVariableExpression(name: "s.firstName"),
///         "gender": ATLHelperCallExpression(helperName: "determineGender", arguments: [])
///     ]
/// )
/// ```
public struct ATLTargetPattern: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The variable name for binding the created target element.
    ///
    /// This variable name is used for referencing the created element within
    /// the rule's scope and from other target patterns.
    public let variableName: String

    /// The type of target element to create.
    ///
    /// Type specifications use ATL's type syntax, referencing target metamodel
    /// element types with appropriate namespace prefixes.
    public let type: String

    /// Property bindings that define values for the created element.
    ///
    /// Bindings specify how properties of the created element are initialized
    /// with values computed from expressions. They support both attribute
    /// assignment and reference establishment.
    public let bindings: [ATLPropertyBinding]

    // MARK: - Initialisation

    /// Creates a new ATL target pattern.
    ///
    /// - Parameters:
    ///   - variableName: The variable name for element binding
    ///   - type: The type specification for element creation
    ///   - bindings: Property bindings for element initialisation
    ///
    /// - Precondition: The variable name must be a non-empty string
    /// - Precondition: The type specification must be a non-empty string
    public init(
        variableName: String,
        type: String,
        bindings: [ATLPropertyBinding] = []
    ) {
        precondition(!variableName.isEmpty, "Variable name must not be empty")
        precondition(!type.isEmpty, "Type specification must not be empty")

        self.variableName = variableName
        self.type = type
        self.bindings = bindings
    }

    // MARK: - Equatable

    public static func == (lhs: ATLTargetPattern, rhs: ATLTargetPattern) -> Bool {
        return lhs.variableName == rhs.variableName && lhs.type == rhs.type
            && lhs.bindings == rhs.bindings
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(variableName)
        hasher.combine(type)
        hasher.combine(bindings)
    }
}

// MARK: - ATL Parameter

/// Represents a parameter in ATL helper functions and called rules.
///
/// Parameters define typed inputs for ATL constructs that accept arguments.
/// They provide both the parameter name for binding and the type specification
/// for validation and code generation purposes.
///
/// ## Example Usage
///
/// ```swift
/// let memberParameter = ATLParameter(
///     name: "member",
///     type: "Families!Member"
/// )
/// ```

// MARK: - ATL Property Binding

/// Represents a property binding in ATL target patterns.
///
/// Property bindings define how properties of created target elements
/// are initialized with values computed from expressions. They form the
/// core mechanism for transferring data between source and target models.
///
/// ## Example Usage
///
/// ```swift
/// let nameBinding = ATLPropertyBinding(
///     property: "fullName",
///     expression: ATLVariableExpression(name: "s.firstName")
/// )
/// ```
public struct ATLPropertyBinding: Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The property name to bind.
    ///
    /// This must correspond to a valid property in the target element's
    /// metamodel class definition.
    public let property: String

    /// The expression that computes the property value.
    ///
    /// The expression is evaluated during rule execution to determine
    /// the value assigned to the property.
    public let expression: any ATLExpression

    // MARK: - Initialisation

    /// Creates a new ATL property binding.
    ///
    /// - Parameters:
    ///   - property: The property name to bind
    ///   - expression: The value expression
    ///
    /// - Precondition: The property name must be a non-empty string
    public init(property: String, expression: any ATLExpression) {
        precondition(!property.isEmpty, "Property name must not be empty")

        self.property = property
        self.expression = expression
    }

    // MARK: - Equatable

    public static func == (lhs: ATLPropertyBinding, rhs: ATLPropertyBinding) -> Bool {
        return lhs.property == rhs.property
            && AnyHashable(lhs.expression) == AnyHashable(rhs.expression)
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hasher.combine(property)
        hasher.combine(AnyHashable(expression))
    }
}

// MARK: - ATL Rule Type Protocol

/// Protocol for ATL rule types (matched and called rules).
///
/// This protocol provides a common interface for different types of ATL rules,
/// enabling polymorphic handling in the parser and execution engine.
public protocol ATLRuleType: Sendable {
    /// The name of the rule.
    var name: String { get }
}

// MARK: - ATL Statement Protocol

/// Protocol for imperative statements in ATL called rules.
///
/// ATL statements provide imperative control flow within the otherwise declarative
/// ATL framework. They are primarily used within called rules to perform sequential
/// operations that cannot be expressed through pattern-based transformations.
///
/// ## Overview
///
/// Statement types include:
/// - **Assignment statements**: Variable and property assignments
/// - **Conditional statements**: If-then-else control structures
/// - **Loop statements**: Iteration over collections
/// - **Expression statements**: Standalone expression evaluation
///
/// ## Implementation Notes
///
/// Statements maintain Sendable conformance to enable safe concurrent execution
/// within ATL virtual machines operating across multiple actors.
public protocol ATLStatement: Sendable {

    /// Executes the statement within the specified execution context.
    ///
    /// - Parameter context: The execution context providing variable bindings and model access
    /// - Throws: ATL execution errors if statement execution failures
    func execute(in context: ATLExecutionContext) async throws
}

// MARK: - Rule Type Conformance

extension ATLMatchedRule: ATLRuleType {}
extension ATLCalledRule: ATLRuleType {}
