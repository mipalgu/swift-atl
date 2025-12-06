//
//  ATLExpression.swift
//  ATL
//
//  Created by Rene Hexel on 6/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import ECore
import Foundation

// MARK: - ATL Expression Protocol

/// Protocol for ATL expressions that can be evaluated within transformation contexts.
///
/// ATL expressions form the computational foundation of the Atlas Transformation Language,
/// providing a rich expression system built upon OCL (Object Constraint Language) with
/// extensions for model transformation. Expressions are evaluated within execution contexts
/// that provide access to source and target models, variables, and helper functions.
///
/// ## Overview
///
/// ATL expressions support multiple evaluation paradigms:
/// - **Navigation expressions**: Property access and reference traversal
/// - **Operation calls**: Method invocation on objects and collections
/// - **Helper invocations**: Custom function calls defined in ATL modules
/// - **Literal values**: Constants and primitive data
/// - **Collection operations**: OCL-style collection manipulation
/// - **Conditional logic**: If-then-else expressions for branching
///
/// ## Implementation Notes
///
/// All expressions conform to `Sendable` to enable safe concurrent evaluation within
/// the ATL virtual machine's actor-based architecture. Expression evaluation is
/// asynchronous to support complex model traversals and transformation operations.
///
/// ## Example Usage
///
/// ```swift
/// let navigationExpr = ATLNavigationExpression(
///     source: ATLVariableExpression(name: "self"),
///     property: "firstName"
/// )
///
/// let result = try await navigationExpr.evaluate(in: executionContext)
/// ```
public protocol ATLExpression: Sendable, Equatable, Hashable {

    /// Evaluates the expression within the specified execution context.
    ///
    /// - Parameter context: The execution context providing model access and variable bindings
    /// - Returns: The result of evaluating the expression, or `nil` if undefined
    /// - Throws: ATL execution errors if expression evaluation fails
    func evaluate(in context: ATLExecutionContext) async throws -> (any EcoreValue)?
}

// MARK: - Variable Expression

/// Represents a variable reference expression in ATL.
///
/// Variable expressions provide access to named variables within the current execution
/// scope, including rule parameters, pattern variables, helper parameters, and local
/// variable bindings. They form the foundation for data flow within ATL transformations.
///
/// ## Example Usage
///
/// ```swift
/// // Reference to source pattern variable
/// let sourceRef = ATLVariableExpression(name: "s")
///
/// // Reference to helper parameter
/// let paramRef = ATLVariableExpression(name: "inputValue")
/// ```
public struct ATLVariableExpression: ATLExpression, Equatable, Hashable {

    // MARK: - Properties

    /// The name of the variable to reference.
    ///
    /// Variable names must correspond to valid bindings within the current
    /// execution context, including pattern variables, parameters, and local bindings.
    public let name: String

    // MARK: - Initialisation

    /// Creates a new variable reference expression.
    ///
    /// - Parameter name: The variable name to reference
    /// - Precondition: The variable name must be a non-empty string
    public init(name: String) {
        precondition(!name.isEmpty, "Variable name must not be empty")
        self.name = name
    }

    // MARK: - Expression Evaluation

    public func evaluate(in context: ATLExecutionContext) async throws -> (any EcoreValue)? {
        return try await context.getVariable(name)
    }
}

// MARK: - Navigation Expression

/// Represents property navigation expressions in ATL.
///
/// Navigation expressions provide access to object properties and references, enabling
/// traversal of model structures according to metamodel specifications. They support
/// both single-valued and multi-valued property access with automatic collection handling.
///
/// ## Overview
///
/// Navigation expressions handle several navigation patterns:
/// - **Attribute access**: Simple property value retrieval
/// - **Reference navigation**: Traversal of object relationships
/// - **Collection navigation**: Access to multi-valued properties
/// - **Opposite navigation**: Reverse reference traversal
/// - **Meta-property access**: Reflection-based property queries
///
/// ## Example Usage
///
/// ```swift
/// // Navigate to firstName property
/// let firstNameExpr = ATLNavigationExpression(
///     source: ATLVariableExpression(name: "member"),
///     property: "firstName"
/// )
///
/// // Navigate to family reference
/// let familyExpr = ATLNavigationExpression(
///     source: ATLVariableExpression(name: "member"),
///     property: "family"
/// )
/// ```
public struct ATLNavigationExpression<SourceExpression: ATLExpression>: ATLExpression, Equatable,
    Hashable
{

    // MARK: - Properties

    /// The source expression to navigate from.
    ///
    /// The source expression is evaluated first, and its result serves as the
    /// starting point for property navigation.
    public let source: SourceExpression

    /// The property name to navigate to.
    ///
    /// Property names must correspond to valid features defined in the source
    /// object's metamodel class specification.
    public let property: String

    // MARK: - Initialisation

    /// Creates a new navigation expression.
    ///
    /// - Parameters:
    ///   - source: The source expression for navigation
    ///   - property: The property name to navigate to
    ///
    /// - Precondition: The property name must be a non-empty string
    public init(source: SourceExpression, property: String) {
        precondition(!property.isEmpty, "Property name must not be empty")
        self.source = source
        self.property = property
    }

    // MARK: - Expression Evaluation

    public func evaluate(in context: ATLExecutionContext) async throws -> (any EcoreValue)? {
        guard let sourceObject = try await source.evaluate(in: context) else {
            return nil
        }

        return try await context.navigate(from: sourceObject, property: property)
    }

    // MARK: - Equatable

    public static func == (lhs: ATLNavigationExpression, rhs: ATLNavigationExpression) -> Bool {
        return lhs.property == rhs.property && lhs.source.hashValue == rhs.source.hashValue
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(property)
        hasher.combine(AnyHashable(source))
    }
}

// MARK: - Helper Call Expression

/// Represents helper function invocation expressions in ATL.
///
/// Helper call expressions enable invocation of custom functions defined within ATL
/// modules, providing extensibility beyond the standard OCL library. They support
/// both contextual and context-free helper invocation with parameter passing.
///
/// ## Example Usage
///
/// ```swift
/// // Call context-free helper
/// let utilityCall = ATLHelperCallExpression(
///     helperName: "formatName",
///     arguments: [firstNameExpr, lastNameExpr]
/// )
///
/// // Call contextual helper (context provided by execution environment)
/// let contextualCall = ATLHelperCallExpression(
///     helperName: "familyName",
///     arguments: []
/// )
/// ```
public struct ATLHelperCallExpression: ATLExpression, Equatable, Hashable {

    // MARK: - Properties

    /// The name of the helper function to invoke.
    ///
    /// Helper names must correspond to valid helper definitions within the
    /// current ATL module's helper registry.
    public let helperName: String

    /// The argument expressions to pass to the helper function.
    ///
    /// Arguments are evaluated in order and passed to the helper function
    /// according to its parameter specification.
    public let arguments: [any ATLExpression]

    // MARK: - Initialisation

    /// Creates a new helper call expression.
    ///
    /// - Parameters:
    ///   - helperName: The name of the helper function to invoke
    ///   - arguments: The argument expressions to pass
    ///
    /// - Precondition: The helper name must be a non-empty string
    public init(helperName: String, arguments: [any ATLExpression] = []) {
        precondition(!helperName.isEmpty, "Helper name must not be empty")
        self.helperName = helperName
        self.arguments = arguments
    }

    // MARK: - Expression Evaluation

    public func evaluate(in context: ATLExecutionContext) async throws -> (any EcoreValue)? {
        // Evaluate all arguments
        var evaluatedArgs: [(any EcoreValue)?] = []
        for argument in arguments {
            let value = try await argument.evaluate(in: context)
            evaluatedArgs.append(value)
        }

        return try await context.callHelper(helperName, arguments: evaluatedArgs)
    }

    // MARK: - Equatable

    public static func == (lhs: ATLHelperCallExpression, rhs: ATLHelperCallExpression) -> Bool {
        guard lhs.helperName == rhs.helperName && lhs.arguments.count == rhs.arguments.count else {
            return false
        }

        // Compare each argument using proper Equatable conformance
        for (leftArg, rightArg) in zip(lhs.arguments, rhs.arguments) {
            if AnyHashable(leftArg) != AnyHashable(rightArg) {
                return false
            }
        }

        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(helperName)
        hasher.combine(arguments.count)
        for argument in arguments {
            hasher.combine(AnyHashable(argument))
        }
    }
}

// MARK: - Literal Expression

/// Represents literal value expressions in ATL.
///
/// Literal expressions provide direct access to constant values within ATL transformations,
/// including primitive types, strings, collections, and special values like `null`.
/// They form the foundation for constant data within transformation specifications.
///
/// ## Example Usage
///
/// ```swift
/// // String literal
/// let stringLiteral = ATLLiteralExpression(value: "Hello, World!")
///
/// // Number literal
/// let numberLiteral = ATLLiteralExpression(value: 42)
///
/// // Boolean literal
/// let boolLiteral = ATLLiteralExpression(value: true)
///
/// // Null literal
/// let nullLiteral = ATLLiteralExpression(value: nil)
/// ```
public struct ATLLiteralExpression: ATLExpression, Equatable, Hashable {

    // MARK: - Properties

    /// The literal value represented by this expression.
    ///
    /// Supported literal types include `String`, `Int`, `Double`, `Bool`,
    /// and `nil` for null values. Complex literals like collections are
    /// handled through specialised expression types.
    public let value: (any EcoreValue)?

    // MARK: - Initialisation

    /// Creates a new literal expression.
    ///
    /// - Parameter value: The literal value to represent
    public init(value: (any EcoreValue)?) {
        self.value = value
    }

    // MARK: - Expression Evaluation

    public func evaluate(in context: ATLExecutionContext) async throws -> (any EcoreValue)? {
        return value
    }

    // MARK: - Equatable

    public static func == (lhs: ATLLiteralExpression, rhs: ATLLiteralExpression) -> Bool {
        // Handle nil cases
        guard let lhsValue = lhs.value, let rhsValue = rhs.value else {
            return lhs.value == nil && rhs.value == nil
        }

        // Use string representation for comparison of arbitrary types
        return String(describing: lhsValue) == String(describing: rhsValue)
    }

    public func hash(into hasher: inout Hasher) {
        if let value = value {
            hasher.combine(String(describing: value))
        } else {
            hasher.combine("nil")
        }
    }
}

// MARK: - Binary Operation Expression

/// Represents binary operation expressions in ATL.
///
/// Binary operation expressions support arithmetic, logical, comparison, and collection
/// operations between two operand expressions. They provide the computational foundation
/// for complex transformation logic and conditional evaluation.
///
/// ## Overview
///
/// Supported operation categories include:
/// - **Arithmetic**: Addition, subtraction, multiplication, division, modulo
/// - **Comparison**: Equality, inequality, relational comparisons
/// - **Logical**: Boolean AND, OR operations
/// - **Collection**: Union, intersection, difference operations
/// - **String**: Concatenation and pattern matching
///
/// ## Example Usage
///
/// ```swift
/// // Arithmetic operation
/// let addition = ATLBinaryOperationExpression(
///     left: ATLVariableExpression(name: "x"),
///     operator: .plus,
///     right: ATLLiteralExpression(value: 10)
/// )
///
/// // Comparison operation
/// let comparison = ATLBinaryOperationExpression(
///     left: ATLVariableExpression(name: "age"),
///     operator: .greaterThan,
///     right: ATLLiteralExpression(value: 18)
/// )
/// ```
public struct ATLBinaryOperationExpression<
    LeftExpression: ATLExpression, RightExpression: ATLExpression
>:
    ATLExpression, Equatable, Hashable
{

    // MARK: - Properties

    /// The left operand expression.
    public let left: LeftExpression

    /// The binary operator to apply.
    public let `operator`: ATLBinaryOperator

    /// The right operand expression.
    public let right: RightExpression

    // MARK: - Initialisation

    /// Creates a new binary operation expression.
    ///
    /// - Parameters:
    ///   - left: The left operand expression
    ///   - operator: The binary operator to apply
    ///   - right: The right operand expression
    public init(left: LeftExpression, `operator`: ATLBinaryOperator, right: RightExpression) {
        self.left = left
        self.`operator` = `operator`
        self.right = right
    }

    // MARK: - Expression Evaluation

    public func evaluate(in context: ATLExecutionContext) async throws -> (any EcoreValue)? {
        let leftValue = try await left.evaluate(in: context)
        let rightValue = try await right.evaluate(in: context)

        return try await evaluateOperation(leftValue, self.`operator`, rightValue)
    }

    /// Evaluates the binary operation with the given operands.
    ///
    /// - Parameters:
    ///   - leftValue: The evaluated left operand
    ///   - operator: The binary operator
    ///   - rightValue: The evaluated right operand
    /// - Returns: The result of the operation
    /// - Throws: ATL execution errors for invalid operations
    private func evaluateOperation(
        _ leftValue: (any EcoreValue)?, _ operator: ATLBinaryOperator,
        _ rightValue: (any EcoreValue)?
    )
        async throws -> (any EcoreValue)?
    {
        switch `operator` {
        case .plus:
            return try addValues(leftValue, rightValue)
        case .minus:
            return try subtractValues(leftValue, rightValue)
        case .multiply:
            return try multiplyValues(leftValue, rightValue)
        case .divide:
            return try divideValues(leftValue, rightValue)
        case .equals:
            return areEqual(leftValue, rightValue)
        case .notEquals:
            return !areEqual(leftValue, rightValue)
        case .lessThan:
            return try compareValues(leftValue, rightValue) < 0
        case .lessThanOrEqual:
            return try compareValues(leftValue, rightValue) <= 0
        case .greaterThan:
            return try compareValues(leftValue, rightValue) > 0
        case .greaterThanOrEqual:
            return try compareValues(leftValue, rightValue) >= 0
        case .and:
            return try logicalAnd(leftValue, rightValue)
        case .or:
            return try logicalOr(leftValue, rightValue)
        default:
            throw ATLExecutionError.unsupportedOperation(
                "Binary operator '\(`operator`.rawValue)' is not yet implemented")
        }
    }

    // MARK: - Operation Implementations

    private func addValues(_ left: (any EcoreValue)?, _ right: (any EcoreValue)?) throws -> (
        any EcoreValue
    )? {
        switch (left, right) {
        case (let l as Int, let r as Int):
            return l + r
        case (let l as Double, let r as Double):
            return l + r
        case (let l as String, let r as String):
            return l + r
        case (let l as Int, let r as Double):
            return Double(l) + r
        case (let l as Double, let r as Int):
            return l + Double(r)
        default:
            throw ATLExecutionError.invalidOperation(
                "Cannot add values of types \(type(of: left)) and \(type(of: right))")
        }
    }

    private func subtractValues(_ left: (any EcoreValue)?, _ right: (any EcoreValue)?) throws -> (
        any EcoreValue
    )? {
        switch (left, right) {
        case (let l as Int, let r as Int):
            return l - r
        case (let l as Double, let r as Double):
            return l - r
        case (let l as Int, let r as Double):
            return Double(l) - r
        case (let l as Double, let r as Int):
            return l - Double(r)
        default:
            throw ATLExecutionError.invalidOperation(
                "Cannot subtract values of types \(type(of: left)) and \(type(of: right))")
        }
    }

    private func multiplyValues(_ left: (any EcoreValue)?, _ right: (any EcoreValue)?) throws -> (
        any EcoreValue
    )? {
        switch (left, right) {
        case (let l as Int, let r as Int):
            return l * r
        case (let l as Double, let r as Double):
            return l * r
        case (let l as Int, let r as Double):
            return Double(l) * r
        case (let l as Double, let r as Int):
            return l * Double(r)
        default:
            throw ATLExecutionError.invalidOperation(
                "Cannot multiply values of types \(type(of: left)) and \(type(of: right))")
        }
    }

    private func divideValues(_ left: (any EcoreValue)?, _ right: (any EcoreValue)?) throws -> (
        any EcoreValue
    )? {
        switch (left, right) {
        case (let l as Int, let r as Int):
            guard r != 0 else { throw ATLExecutionError.divisionByZero }
            return l / r
        case (let l as Double, let r as Double):
            guard r != 0.0 else { throw ATLExecutionError.divisionByZero }
            return l / r
        case (let l as Int, let r as Double):
            guard r != 0.0 else { throw ATLExecutionError.divisionByZero }
            return Double(l) / r
        case (let l as Double, let r as Int):
            guard r != 0 else { throw ATLExecutionError.divisionByZero }
            return l / Double(r)
        default:
            throw ATLExecutionError.invalidOperation(
                "Cannot divide values of types \(type(of: left)) and \(type(of: right))")
        }
    }

    private func areEqual(_ left: (any EcoreValue)?, _ right: (any EcoreValue)?) -> Bool {
        switch (left, right) {
        case (nil, nil):
            return true
        case (nil, _), (_, nil):
            return false
        default:
            return String(describing: left) == String(describing: right)
        }
    }

    private func compareValues(_ left: (any EcoreValue)?, _ right: (any EcoreValue)?) throws -> Int
    {
        switch (left, right) {
        case (let l as Int, let r as Int):
            return l < r ? -1 : (l > r ? 1 : 0)
        case (let l as Double, let r as Double):
            return l < r ? -1 : (l > r ? 1 : 0)
        case (let l as String, let r as String):
            return l.compare(r).rawValue
        case (let l as Int, let r as Double):
            let ld = Double(l)
            return ld < r ? -1 : (ld > r ? 1 : 0)
        case (let l as Double, let r as Int):
            let rd = Double(r)
            return l < rd ? -1 : (l > rd ? 1 : 0)
        default:
            throw ATLExecutionError.invalidOperation(
                "Cannot compare values of types \(type(of: left)) and \(type(of: right))")
        }
    }

    private func logicalAnd(_ left: (any EcoreValue)?, _ right: (any EcoreValue)?) throws -> Bool {
        guard let leftBool = left as? Bool, let rightBool = right as? Bool else {
            throw ATLExecutionError.invalidOperation("Logical AND requires boolean operands")
        }
        return leftBool && rightBool
    }

    private func logicalOr(_ left: (any EcoreValue)?, _ right: (any EcoreValue)?) throws -> Bool {
        guard let leftBool = left as? Bool, let rightBool = right as? Bool else {
            throw ATLExecutionError.invalidOperation("Logical OR requires boolean operands")
        }
        return leftBool || rightBool
    }

    // MARK: - Equatable

    public static func == (
        lhs: ATLBinaryOperationExpression<LeftExpression, RightExpression>,
        rhs: ATLBinaryOperationExpression<LeftExpression, RightExpression>
    )
        -> Bool
    {
        return lhs.`operator` == rhs.`operator`
            && lhs.left == rhs.left
            && lhs.right == rhs.right
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(`operator`)
        hasher.combine(left)
        hasher.combine(right)
    }
}

// MARK; - Helper Types

/// A phantom type representing an ATL expression that can never be instantiated.
///
/// This type is used for generic contexts where an optional expression type
/// is needed but no actual expression will be present (e.g., matched rules
/// without guard expressions).
public enum ATLExpressionNever: ATLExpression {
    // This enum has no cases and can never be instantiated
    
    public func evaluate(in context: ATLExecutionContext) async throws -> (any EcoreValue)? {
        // This can never be called since no instances can exist
        fatalError("ATLExpressionNever cannot be evaluated")
    }
}

/// Binary operators supported in ATL expressions.
public enum ATLBinaryOperator: String, Sendable, CaseIterable, Equatable {
    // Arithmetic operators
    case plus = "+"
    case minus = "-"
    case multiply = "*"
    case divide = "/"
    case modulo = "mod"
    
    // Comparison operators
    case equals = "="
    case notEquals = "<>"
    case lessThan = "<"
    case lessThanOrEqual = "<="
    case greaterThan = ">"
    case greaterThanOrEqual = ">="
    
    // Logical operators
    case and = "and"
    case or = "or"
    case implies = "implies"
    
    // Collection operators
    case union = "union"
    case intersection = "intersection"
    case difference = "--"
    case includes = "includes"
    case excludes = "excludes"
}

// MARK: - ATL Execution Error

/// Errors that can occur during ATL expression evaluation.
public enum ATLExecutionError: Error, LocalizedError, Sendable {
    case variableNotFound(String)
    case helperNotFound(String)
    case invalidOperation(String)
    case unsupportedOperation(String)
    case divisionByZero
    case typeError(String)

    public var errorDescription: String? {
        switch self {
        case .variableNotFound(let name):
            return "Variable '\(name)' not found in execution context"
        case .helperNotFound(let name):
            return "Helper '\(name)' not found in module"
        case .invalidOperation(let message):
            return "Invalid operation: \(message)"
        case .unsupportedOperation(let message):
            return "Unsupported operation: \(message)"
        case .divisionByZero:
            return "Division by zero"
        case .typeError(let message):
            return "Type error: \(message)"
        }
    }
}
