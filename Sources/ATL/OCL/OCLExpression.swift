//
//  OCLExpression.swift
//  OCL
//
//  Created by Rene Hexel on 9/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
//  Core OCL expression protocol and fundamental expression types.
//  Based on the Eclipse ATL OCL metamodel structure.
//
import ECore
import Foundation

// MARK: - OCL Expression Protocol

/// Protocol for OCL expressions that can be evaluated within execution contexts.
///
/// OCL (Object Constraint Language) expressions form the computational foundation
/// of model transformation and constraint evaluation. This protocol defines the
/// core evaluation interface used throughout the ATL/OCL system.
///
/// ## Overview
///
/// All OCL expressions must conform to `Sendable` to enable safe concurrent
/// evaluation within Swift's modern concurrency model. Expression evaluation
/// is asynchronous to support complex model traversals and queries.
///
/// ## Example Usage
///
/// ```swift
/// let expr = OCLVariableExpression(name: "self")
/// let result = try await expr.evaluate(in: executionContext)
/// ```
public protocol OCLExpression: Sendable, Equatable, Hashable {
    /// Evaluates the expression within the specified execution context.
    ///
    /// - Parameter context: The execution context providing model access and variable bindings
    /// - Returns: The result of evaluating the expression, or `nil` if undefined
    /// - Throws: Execution errors if expression evaluation fails
    @MainActor
    func evaluate(in context: OCLExecutionContext) async throws -> (any EcoreValue)?
}

// MARK: - OCL Execution Context Protocol

/// Protocol defining the execution context interface required by OCL expressions.
///
/// This protocol abstracts the execution environment, allowing OCL expressions
/// to be evaluated in different contexts (ATL transformations, standalone OCL
/// evaluation, etc.) without coupling to specific implementations.
public protocol OCLExecutionContext: AnyObject {
    /// Retrieves a variable value from the current scope.
    ///
    /// - Parameter name: The variable name
    /// - Returns: The variable value, or throws if not found
    /// - Throws: `OCLExecutionError.variableNotFound` if the variable doesn't exist
    @MainActor
    func getVariable(_ name: String) throws -> (any EcoreValue)?

    /// Sets a variable value in the current scope.
    ///
    /// - Parameters:
    ///   - name: The variable name
    ///   - value: The value to bind
    @MainActor
    func setVariable(_ name: String, value: (any EcoreValue)?)

    /// Pushes a new variable scope onto the scope stack.
    @MainActor
    func pushScope()

    /// Pops the current variable scope from the scope stack.
    @MainActor
    func popScope()

    /// Navigates from a source object to a property.
    ///
    /// - Parameters:
    ///   - source: The source object
    ///   - property: The property name to navigate to
    /// - Returns: The navigation result
    /// - Throws: Execution errors if navigation fails
    @MainActor
    func navigate(from source: any EcoreValue, property: String) async throws -> (any EcoreValue)?

    /// Calls a helper function with the given arguments.
    ///
    /// - Parameters:
    ///   - name: The helper function name
    ///   - arguments: The evaluated arguments
    /// - Returns: The helper result
    /// - Throws: Execution errors if the helper call fails
    @MainActor
    func callHelper(_ name: String, arguments: [(any EcoreValue)?]) async throws -> (any EcoreValue)?
}

// MARK: - Variable Expression

/// Represents a variable reference expression in OCL.
///
/// Variable expressions provide access to named variables within the current execution
/// scope, including parameters, local bindings, and contextual variables like `self`.
///
/// ## Example Usage
///
/// ```swift
/// let selfRef = OCLVariableExpression(name: "self")
/// let paramRef = OCLVariableExpression(name: "x")
/// ```
public struct OCLVariableExpression: OCLExpression {
    /// The name of the variable to reference.
    public let name: String

    /// Creates a new variable reference expression.
    ///
    /// - Parameter name: The variable name to reference
    /// - Precondition: The variable name must be a non-empty string
    public init(name: String) {
        precondition(!name.isEmpty, "Variable name must not be empty")
        self.name = name
    }

    /// Evaluates the variable expression by retrieving its value from the execution context.
    ///
    /// - Parameter context: The execution context containing variable bindings
    /// - Returns: The value bound to the variable name
    /// - Throws: `OCLExecutionError.variableNotFound` if the variable is not in scope
    @MainActor
    public func evaluate(in context: OCLExecutionContext) async throws -> (any EcoreValue)? {
        return try context.getVariable(name)
    }

    /// Tests equality between two variable expressions.
    ///
    /// - Parameters:
    ///   - lhs: The left-hand side expression
    ///   - rhs: The right-hand side expression
    /// - Returns: `true` if both expressions reference the same variable name
    public static func == (lhs: OCLVariableExpression, rhs: OCLVariableExpression) -> Bool {
        return lhs.name == rhs.name
    }

    /// Hashes the variable expression into the given hasher.
    ///
    /// - Parameter hasher: The hasher to use for combining values
    public func hash(into hasher: inout Hasher) {
        hasher.combine(name)
    }
}

// MARK: - Literal Expression

/// Represents literal value expressions in OCL.
///
/// Literal expressions provide direct access to constant values including
/// primitive types, strings, and null values.
///
/// ## Example Usage
///
/// ```swift
/// let stringLit = OCLLiteralExpression(value: "Hello")
/// let numberLit = OCLLiteralExpression(value: 42)
/// let boolLit = OCLLiteralExpression(value: true)
/// ```
public struct OCLLiteralExpression: OCLExpression {
    /// The literal value represented by this expression.
    public let value: (any EcoreValue)?

    /// Creates a new literal expression.
    ///
    /// - Parameter value: The literal value to represent
    public init(value: (any EcoreValue)?) {
        self.value = value
    }

    /// Evaluates the literal expression by returning its value.
    ///
    /// - Parameter context: The execution context (unused for literals)
    /// - Returns: The literal value
    @MainActor
    public func evaluate(in context: OCLExecutionContext) async throws -> (any EcoreValue)? {
        return value
    }

    /// Tests equality between two literal expressions.
    ///
    /// - Parameters:
    ///   - lhs: The left-hand side expression
    ///   - rhs: The right-hand side expression
    /// - Returns: `true` if both expressions represent equal values
    public static func == (lhs: OCLLiteralExpression, rhs: OCLLiteralExpression) -> Bool {
        guard let lhsValue = lhs.value, let rhsValue = rhs.value else {
            return lhs.value == nil && rhs.value == nil
        }
        return String(describing: lhsValue) == String(describing: rhsValue)
    }

    /// Hashes the literal expression into the given hasher.
    ///
    /// - Parameter hasher: The hasher to use for combining values
    public func hash(into hasher: inout Hasher) {
        if let value = value {
            hasher.combine(String(describing: value))
        } else {
            hasher.combine("nil")
        }
    }
}

// MARK: - Navigation Expression

/// Represents property navigation expressions in OCL.
///
/// Navigation expressions enable traversal of object properties and references
/// according to metamodel specifications, supporting both single-valued and
/// multi-valued property access.
///
/// ## Example Usage
///
/// ```swift
/// let nameExpr = OCLNavigationExpression(
///     source: OCLVariableExpression(name: "person"),
///     property: "firstName"
/// )
/// ```
public struct OCLNavigationExpression: OCLExpression {
    /// The source expression to navigate from.
    public let source: any OCLExpression

    /// The property name to navigate to.
    public let property: String

    /// Creates a new navigation expression.
    ///
    /// - Parameters:
    ///   - source: The source expression to navigate from
    ///   - property: The property name to navigate to
    /// - Precondition: The property name must be a non-empty string
    public init(source: any OCLExpression, property: String) {
        precondition(!property.isEmpty, "Property name must not be empty")
        self.source = source
        self.property = property
    }

    /// Evaluates the navigation expression by traversing from the source to the property.
    ///
    /// - Parameter context: The execution context providing navigation capabilities
    /// - Returns: The value of the property, or `nil` if the source evaluates to `nil`
    /// - Throws: Navigation errors if the property cannot be accessed
    @MainActor
    public func evaluate(in context: OCLExecutionContext) async throws -> (any EcoreValue)? {
        guard let sourceObject = try await source.evaluate(in: context) else {
            return nil
        }
        return try await context.navigate(from: sourceObject, property: property)
    }

    /// Tests equality between two navigation expressions.
    ///
    /// - Parameters:
    ///   - lhs: The left-hand side expression
    ///   - rhs: The right-hand side expression
    /// - Returns: `true` if both expressions navigate the same property from equal sources
    public static func == (lhs: OCLNavigationExpression, rhs: OCLNavigationExpression) -> Bool {
        return lhs.property == rhs.property && areOCLExpressionsEqual(lhs.source, rhs.source)
    }

    /// Hashes the navigation expression into the given hasher.
    ///
    /// - Parameter hasher: The hasher to use for combining values
    public func hash(into hasher: inout Hasher) {
        hasher.combine(property)
        hashOCLExpression(source, into: &hasher)
    }
}

// MARK: - Conditional Expression (If-Then-Else)

/// Represents conditional (if-then-else) expressions in OCL.
///
/// Conditional expressions provide branching logic based on boolean conditions,
/// following standard OCL if-then-else-endif syntax.
///
/// ## Example Usage
///
/// ```swift
/// let conditional = OCLConditionalExpression(
///     condition: OCLBinaryOperationExpression(
///         left: OCLVariableExpression(name: "age"),
///         operator: .greaterThan,
///         right: OCLLiteralExpression(value: 18)
///     ),
///     thenExpression: OCLLiteralExpression(value: "adult"),
///     elseExpression: OCLLiteralExpression(value: "minor")
/// )
/// ```
public struct OCLConditionalExpression: OCLExpression {
    /// The condition expression to evaluate.
    public let condition: any OCLExpression

    /// The expression to evaluate if condition is true.
    public let thenExpression: any OCLExpression

    /// The expression to evaluate if condition is false.
    public let elseExpression: any OCLExpression

    /// Creates a conditional expression.
    ///
    /// - Parameters:
    ///   - condition: Expression that evaluates to a boolean
    ///   - thenExpression: Expression for true condition
    ///   - elseExpression: Expression for false condition
    public init(
        condition: any OCLExpression,
        thenExpression: any OCLExpression,
        elseExpression: any OCLExpression
    ) {
        self.condition = condition
        self.thenExpression = thenExpression
        self.elseExpression = elseExpression
    }

    /// Evaluates the conditional expression based on the condition's boolean value.
    ///
    /// - Parameter context: The execution context for evaluating sub-expressions
    /// - Returns: The value of the then-expression if condition is true, otherwise the else-expression
    @MainActor
    public func evaluate(in context: OCLExecutionContext) async throws -> (any EcoreValue)? {
        let conditionValue = try await condition.evaluate(in: context)
        let conditionBool = (conditionValue as? Bool) ?? false

        if conditionBool {
            return try await thenExpression.evaluate(in: context)
        } else {
            return try await elseExpression.evaluate(in: context)
        }
    }

    /// Tests equality between two conditional expressions.
    ///
    /// - Parameters:
    ///   - lhs: The left-hand side expression
    ///   - rhs: The right-hand side expression
    /// - Returns: `true` if all three components (condition, then, else) are equal
    public static func == (lhs: OCLConditionalExpression, rhs: OCLConditionalExpression) -> Bool {
        return areOCLExpressionsEqual(lhs.condition, rhs.condition)
            && areOCLExpressionsEqual(lhs.thenExpression, rhs.thenExpression)
            && areOCLExpressionsEqual(lhs.elseExpression, rhs.elseExpression)
    }

    /// Hashes the conditional expression into the given hasher.
    ///
    /// - Parameter hasher: The hasher to use for combining values
    public func hash(into hasher: inout Hasher) {
        hashOCLExpression(condition, into: &hasher)
        hashOCLExpression(thenExpression, into: &hasher)
        hashOCLExpression(elseExpression, into: &hasher)
    }
}

// MARK: - Binary Operation Expression

/// Binary operators supported in OCL expressions.
public enum OCLBinaryOperator: String, Sendable, CaseIterable, Equatable {
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

/// Represents binary operation expressions in OCL.
///
/// Binary operations support arithmetic, logical, comparison, and collection
/// operations between two operand expressions.
///
/// ## Example Usage
///
/// ```swift
/// let addition = OCLBinaryOperationExpression(
///     left: OCLVariableExpression(name: "x"),
///     operator: .plus,
///     right: OCLLiteralExpression(value: 10)
/// )
/// ```
public struct OCLBinaryOperationExpression: OCLExpression {
    /// The left operand expression.
    public let left: any OCLExpression

    /// The binary operator to apply.
    public let `operator`: OCLBinaryOperator

    /// The right operand expression.
    public let right: any OCLExpression

    /// Creates a new binary operation expression.
    ///
    /// - Parameters:
    ///   - left: The left operand expression
    ///   - operator: The binary operator to apply
    ///   - right: The right operand expression
    public init(left: any OCLExpression, `operator`: OCLBinaryOperator, right: any OCLExpression) {
        self.left = left
        self.`operator` = `operator`
        self.right = right
    }

    /// Evaluates the binary operation by applying the operator to the left and right operands.
    ///
    /// - Parameter context: The execution context for evaluating operands
    /// - Returns: The result of the binary operation
    /// - Throws: Type or arithmetic errors if the operation cannot be performed
    @MainActor
    public func evaluate(in context: OCLExecutionContext) async throws -> (any EcoreValue)? {
        let leftValue = try await left.evaluate(in: context)
        let rightValue = try await right.evaluate(in: context)

        return try evaluateOperation(leftValue, self.`operator`, rightValue)
    }

    /// Evaluates the binary operation with the given operands.
    ///
    /// - Parameters:
    ///   - leftValue: The evaluated left operand
    ///   - operator: The binary operator to apply
    ///   - rightValue: The evaluated right operand
    /// - Returns: The result of applying the operator
    /// - Throws: Execution errors for unsupported or invalid operations
    private func evaluateOperation(
        _ leftValue: (any EcoreValue)?,
        _ operator: OCLBinaryOperator,
        _ rightValue: (any EcoreValue)?
    ) throws -> (any EcoreValue)? {
        switch `operator` {
        case .plus:
            return try OCLArithmeticOperations.add(leftValue, rightValue)
        case .minus:
            return try OCLArithmeticOperations.subtract(leftValue, rightValue)
        case .multiply:
            return try OCLArithmeticOperations.multiply(leftValue, rightValue)
        case .divide:
            return try OCLArithmeticOperations.divide(leftValue, rightValue)
        case .equals:
            return OCLComparisonOperations.areEqual(leftValue, rightValue)
        case .notEquals:
            return !OCLComparisonOperations.areEqual(leftValue, rightValue)
        case .lessThan:
            return try OCLComparisonOperations.compare(leftValue, rightValue) < 0
        case .lessThanOrEqual:
            return try OCLComparisonOperations.compare(leftValue, rightValue) <= 0
        case .greaterThan:
            return try OCLComparisonOperations.compare(leftValue, rightValue) > 0
        case .greaterThanOrEqual:
            return try OCLComparisonOperations.compare(leftValue, rightValue) >= 0
        case .and:
            return try OCLLogicalOperations.and(leftValue, rightValue)
        case .or:
            return try OCLLogicalOperations.or(leftValue, rightValue)
        default:
            throw OCLExecutionError.unsupportedOperation(
                "Binary operator '\(`operator`.rawValue)' is not yet implemented")
        }
    }

    /// Tests equality between two binary operation expressions.
    ///
    /// - Parameters:
    ///   - lhs: The left-hand side expression
    ///   - rhs: The right-hand side expression
    /// - Returns: `true` if the operator and both operands are equal
    public static func == (lhs: OCLBinaryOperationExpression, rhs: OCLBinaryOperationExpression) -> Bool {
        return lhs.`operator` == rhs.`operator`
            && areOCLExpressionsEqual(lhs.left, rhs.left)
            && areOCLExpressionsEqual(lhs.right, rhs.right)
    }

    /// Hashes the binary operation expression into the given hasher.
    ///
    /// - Parameter hasher: The hasher to use for combining values
    public func hash(into hasher: inout Hasher) {
        hasher.combine(`operator`)
        hashOCLExpression(left, into: &hasher)
        hashOCLExpression(right, into: &hasher)
    }
}

// MARK: - Unary Operation Expression

/// Unary operators supported in OCL expressions.
public enum OCLUnaryOperator: String, Sendable, CaseIterable, Equatable {
    case not = "not"
    case minus = "-"
}

/// Represents unary operation expressions in OCL.
///
/// Unary operations support logical negation and numeric negation.
///
/// ## Example Usage
///
/// ```swift
/// let negation = OCLUnaryOperationExpression(
///     operator: .not,
///     operand: OCLVariableExpression(name: "flag")
/// )
/// ```
public struct OCLUnaryOperationExpression: OCLExpression {
    /// The unary operator.
    public let `operator`: OCLUnaryOperator

    /// The operand expression.
    public let operand: any OCLExpression

    /// Creates a unary operation expression.
    ///
    /// - Parameters:
    ///   - operator: The unary operator
    ///   - operand: The operand expression
    public init(`operator`: OCLUnaryOperator, operand: any OCLExpression) {
        self.`operator` = `operator`
        self.operand = operand
    }

    /// Evaluates the unary operation by applying the operator to the operand.
    ///
    /// - Parameter context: The execution context for evaluating the operand
    /// - Returns: The result of the unary operation
    /// - Throws: Type errors if the operator cannot be applied to the operand value
    @MainActor
    public func evaluate(in context: OCLExecutionContext) async throws -> (any EcoreValue)? {
        let operandValue = try await operand.evaluate(in: context)

        switch `operator` {
        case .not:
            if let boolValue = operandValue as? Bool {
                return !boolValue
            } else {
                throw OCLExecutionError.typeError("Cannot apply 'not' to non-boolean value")
            }
        case .minus:
            if let intValue = operandValue as? Int {
                return -intValue
            } else if let doubleValue = operandValue as? Double {
                return -doubleValue
            } else {
                throw OCLExecutionError.typeError("Cannot apply unary minus to non-numeric value")
            }
        }
    }

    /// Tests equality between two unary operation expressions.
    ///
    /// - Parameters:
    ///   - lhs: The left-hand side expression
    ///   - rhs: The right-hand side expression
    /// - Returns: `true` if the operator and operand are equal
    public static func == (lhs: OCLUnaryOperationExpression, rhs: OCLUnaryOperationExpression) -> Bool {
        return lhs.`operator` == rhs.`operator` && areOCLExpressionsEqual(lhs.operand, rhs.operand)
    }

    /// Hashes the unary operation expression into the given hasher.
    ///
    /// - Parameter hasher: The hasher to use for combining values
    public func hash(into hasher: inout Hasher) {
        hasher.combine(`operator`)
        hashOCLExpression(operand, into: &hasher)
    }
}

// MARK: - Let Expression

/// Represents let expressions in OCL for local variable bindings.
///
/// Let expressions introduce local variable bindings that are visible within
/// the `in` expression scope, following the OCL syntax:
/// ```
/// let varName : Type = initExpression in bodyExpression
/// ```
///
/// ## Example Usage
///
/// ```swift
/// let letExpr = OCLLetExpression(
///     variableName: "avgPages",
///     variableType: "Real",
///     initExpression: OCLBinaryOperationExpression(
///         left: helperCall,
///         operator: .divide,
///         right: sizeCall
///     ),
///     inExpression: bodyExpression
/// )
/// ```
public struct OCLLetExpression: OCLExpression {
    /// The variable name for the let binding.
    public let variableName: String

    /// The optional type annotation for the variable.
    public let variableType: String?

    /// The initialisation expression for the variable.
    public let initExpression: any OCLExpression

    /// The body expression evaluated with the variable binding in scope.
    public let inExpression: any OCLExpression

    /// Creates a let expression.
    ///
    /// - Parameters:
    ///   - variableName: The name of the variable to bind
    ///   - variableType: Optional type annotation
    ///   - initExpression: Expression to initialise the variable
    ///   - inExpression: Expression evaluated with the binding in scope
    public init(
        variableName: String,
        variableType: String? = nil,
        initExpression: any OCLExpression,
        inExpression: any OCLExpression
    ) {
        precondition(!variableName.isEmpty, "Variable name must not be empty")
        self.variableName = variableName
        self.variableType = variableType
        self.initExpression = initExpression
        self.inExpression = inExpression
    }

    /// Evaluates the let expression by binding the variable and evaluating the body.
    ///
    /// Creates a new scope, evaluates the initialisation expression, binds the variable
    /// to the result, and then evaluates the body expression within that scope.
    ///
    /// - Parameter context: The execution context for evaluation
    /// - Returns: The result of evaluating the body expression
    /// - Throws: Execution errors if initialisation or body evaluation fails
    @MainActor
    public func evaluate(in context: OCLExecutionContext) async throws -> (any EcoreValue)? {
        // Evaluate the initialisation expression
        let initValue = try await initExpression.evaluate(in: context)

        // Create new scope for the let binding
        context.pushScope()
        defer {
            context.popScope()
        }

        // Bind the variable in the new scope
        context.setVariable(variableName, value: initValue)

        // Evaluate the in expression with the binding
        return try await inExpression.evaluate(in: context)
    }

    /// Tests equality between two let expressions.
    ///
    /// - Parameters:
    ///   - lhs: The left-hand side expression
    ///   - rhs: The right-hand side expression
    /// - Returns: `true` if all components (name, type, init, body) are equal
    public static func == (lhs: OCLLetExpression, rhs: OCLLetExpression) -> Bool {
        return lhs.variableName == rhs.variableName
            && lhs.variableType == rhs.variableType
            && areOCLExpressionsEqual(lhs.initExpression, rhs.initExpression)
            && areOCLExpressionsEqual(lhs.inExpression, rhs.inExpression)
    }

    /// Hashes the let expression into the given hasher.
    ///
    /// - Parameter hasher: The hasher to use for combining values
    public func hash(into hasher: inout Hasher) {
        hasher.combine(variableName)
        hasher.combine(variableType)
        hashOCLExpression(initExpression, into: &hasher)
        hashOCLExpression(inExpression, into: &hasher)
    }
}

// MARK: - OCL Execution Error

/// Errors that can occur during OCL expression evaluation.
public enum OCLExecutionError: Error, LocalizedError, Sendable {
    case variableNotFound(String)
    case helperNotFound(String)
    case invalidOperation(String)
    case unsupportedOperation(String)
    case divisionByZero
    case typeError(String)
    case runtimeError(String)

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
        case .runtimeError(let message):
            return "Runtime error: \(message)"
        }
    }
}

// MARK: - OCL Arithmetic Operations

/// Arithmetic operations for OCL expressions.
public enum OCLArithmeticOperations {
    /// Adds two values, supporting numeric and string concatenation.
    ///
    /// - Parameters:
    ///   - left: The left operand
    ///   - right: The right operand
    /// - Returns: The sum of the values
    /// - Throws: `OCLExecutionError.invalidOperation` if the values cannot be added
    public static func add(_ left: (any EcoreValue)?, _ right: (any EcoreValue)?) throws -> (any EcoreValue)? {
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
            throw OCLExecutionError.invalidOperation(
                "Cannot add values of types \(type(of: left)) and \(type(of: right))")
        }
    }

    /// Subtracts one numeric value from another.
    ///
    /// - Parameters:
    ///   - left: The left operand
    ///   - right: The right operand
    /// - Returns: The difference of the values
    /// - Throws: `OCLExecutionError.invalidOperation` if the values cannot be subtracted
    public static func subtract(_ left: (any EcoreValue)?, _ right: (any EcoreValue)?) throws -> (any EcoreValue)? {
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
            throw OCLExecutionError.invalidOperation(
                "Cannot subtract values of types \(type(of: left)) and \(type(of: right))")
        }
    }

    /// Multiplies two numeric values.
    ///
    /// - Parameters:
    ///   - left: The left operand
    ///   - right: The right operand
    /// - Returns: The product of the values
    /// - Throws: `OCLExecutionError.invalidOperation` if the values cannot be multiplied
    public static func multiply(_ left: (any EcoreValue)?, _ right: (any EcoreValue)?) throws -> (any EcoreValue)? {
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
            throw OCLExecutionError.invalidOperation(
                "Cannot multiply values of types \(type(of: left)) and \(type(of: right))")
        }
    }

    /// Divides one numeric value by another.
    ///
    /// - Parameters:
    ///   - left: The dividend
    ///   - right: The divisor
    /// - Returns: The quotient of the values
    /// - Throws: `OCLExecutionError.divisionByZero` if the divisor is zero, or `OCLExecutionError.invalidOperation` if the values cannot be divided
    public static func divide(_ left: (any EcoreValue)?, _ right: (any EcoreValue)?) throws -> (any EcoreValue)? {
        switch (left, right) {
        case (let l as Int, let r as Int):
            guard r != 0 else { throw OCLExecutionError.divisionByZero }
            return l / r
        case (let l as Double, let r as Double):
            guard r != 0.0 else { throw OCLExecutionError.divisionByZero }
            return l / r
        case (let l as Int, let r as Double):
            guard r != 0.0 else { throw OCLExecutionError.divisionByZero }
            return Double(l) / r
        case (let l as Double, let r as Int):
            guard r != 0 else { throw OCLExecutionError.divisionByZero }
            return l / Double(r)
        default:
            throw OCLExecutionError.invalidOperation(
                "Cannot divide values of types \(type(of: left)) and \(type(of: right))")
        }
    }
}

// MARK: - OCL Comparison Operations

/// Comparison operations for OCL expressions.
public enum OCLComparisonOperations {
    /// Tests equality between two values.
    ///
    /// - Parameters:
    ///   - left: The left value
    ///   - right: The right value
    /// - Returns: `true` if the values are equal
    public static func areEqual(_ left: (any EcoreValue)?, _ right: (any EcoreValue)?) -> Bool {
        switch (left, right) {
        case (nil, nil):
            return true
        case (nil, _), (_, nil):
            return false
        default:
            return String(describing: left) == String(describing: right)
        }
    }

    /// Compares two values for ordering.
    ///
    /// - Parameters:
    ///   - left: The left value
    ///   - right: The right value
    /// - Returns: -1 if left < right, 0 if equal, 1 if left > right
    /// - Throws: `OCLExecutionError.invalidOperation` if the values cannot be compared
    public static func compare(_ left: (any EcoreValue)?, _ right: (any EcoreValue)?) throws -> Int {
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
            throw OCLExecutionError.invalidOperation(
                "Cannot compare values of types \(type(of: left)) and \(type(of: right))")
        }
    }
}

// MARK: - OCL Logical Operations

/// Logical operations for OCL expressions.
public enum OCLLogicalOperations {
    /// Performs logical AND on two boolean values.
    ///
    /// - Parameters:
    ///   - left: The left boolean value
    ///   - right: The right boolean value
    /// - Returns: The result of the logical AND operation
    /// - Throws: `OCLExecutionError.invalidOperation` if either value is not a boolean
    public static func and(_ left: (any EcoreValue)?, _ right: (any EcoreValue)?) throws -> Bool {
        guard let leftBool = left as? Bool, let rightBool = right as? Bool else {
            throw OCLExecutionError.invalidOperation("Logical AND requires boolean operands")
        }
        return leftBool && rightBool
    }

    /// Performs logical OR on two boolean values.
    ///
    /// - Parameters:
    ///   - left: The left boolean value
    ///   - right: The right boolean value
    /// - Returns: The result of the logical OR operation
    /// - Throws: `OCLExecutionError.invalidOperation` if either value is not a boolean
    public static func or(_ left: (any EcoreValue)?, _ right: (any EcoreValue)?) throws -> Bool {
        guard let leftBool = left as? Bool, let rightBool = right as? Bool else {
            throw OCLExecutionError.invalidOperation("Logical OR requires boolean operands")
        }
        return leftBool || rightBool
    }
}

// MARK: - OCL Expression Utilities

/// Safely compares two OCL expressions for equality.
///
/// - Parameters:
///   - lhs: The left-hand side expression
///   - rhs: The right-hand side expression
/// - Returns: `true` if the expressions are equal
public func areOCLExpressionsEqual(_ lhs: any OCLExpression, _ rhs: any OCLExpression) -> Bool {
    guard type(of: lhs) == type(of: rhs) else { return false }

    switch (lhs, rhs) {
    case (let l as OCLLiteralExpression, let r as OCLLiteralExpression):
        return l == r
    case (let l as OCLVariableExpression, let r as OCLVariableExpression):
        return l == r
    case (let l as OCLNavigationExpression, let r as OCLNavigationExpression):
        return l == r
    case (let l as OCLConditionalExpression, let r as OCLConditionalExpression):
        return l == r
    case (let l as OCLBinaryOperationExpression, let r as OCLBinaryOperationExpression):
        return l == r
    case (let l as OCLUnaryOperationExpression, let r as OCLUnaryOperationExpression):
        return l == r
    case (let l as OCLLetExpression, let r as OCLLetExpression):
        return l == r
    default:
        return false
    }
}

/// Safely hashes an OCL expression.
///
/// - Parameters:
///   - expression: The expression to hash
///   - hasher: The hasher to combine values into
public func hashOCLExpression(_ expression: any OCLExpression, into hasher: inout Hasher) {
    switch expression {
    case let expr as OCLLiteralExpression:
        expr.hash(into: &hasher)
    case let expr as OCLVariableExpression:
        expr.hash(into: &hasher)
    case let expr as OCLNavigationExpression:
        expr.hash(into: &hasher)
    case let expr as OCLConditionalExpression:
        expr.hash(into: &hasher)
    case let expr as OCLBinaryOperationExpression:
        expr.hash(into: &hasher)
    case let expr as OCLUnaryOperationExpression:
        expr.hash(into: &hasher)
    case let expr as OCLLetExpression:
        expr.hash(into: &hasher)
    default:
        hasher.combine(String(describing: type(of: expression)))
    }
}
