//
//  ATLExpression.swift
//  ATL
//
//  Created by Rene Hexel on 6/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import ECore
import Foundation
import OrderedCollections

// MARK: - Async Utilities

extension Array {
    /// Asynchronously maps over the array elements using a throwing transform function.
    func asyncMap<T>(_ transform: (Element) async throws -> T) async rethrows -> [T] {
        var results: [T] = []
        results.reserveCapacity(count)

        for element in self {
            let result = try await transform(element)
            results.append(result)
        }

        return results
    }

    /// Asynchronously maps over the array elements using a MainActor transform function.
    @MainActor
    func asyncMapMainActor<T>(_ transform: @MainActor (Element) async throws -> T) async rethrows
        -> [T]
    {
        var results: [T] = []
        results.reserveCapacity(count)

        for element in self {
            let result = try await transform(element)
            results.append(result)
        }

        return results
    }
}

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
    /// - Throws: ATL execution errors if expression evaluation failures
    @MainActor
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

    @MainActor
    public func evaluate(in context: ATLExecutionContext) async throws -> (any EcoreValue)? {
        return try context.getVariable(name)
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
public struct ATLNavigationExpression: ATLExpression, Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The source expression to navigate from.
    ///
    /// The source expression is evaluated first, and its result serves as the
    /// starting point for property navigation.
    public let source: any ATLExpression

    /// The property name to navigate to.
    ///
    /// Property names must correspond to valid features defined in the source
    /// object's metamodel class specification.
    public let property: String

    // MARK: - Initialisation

    /// Creates a new navigation expression.
    ///
    /// - Parameters:
    ///   - source: The source expression to navigate from
    ///   - property: The property name to navigate to
    ///
    /// - Precondition: The property name must be a non-empty string
    public init(source: any ATLExpression, property: String) {
        precondition(!property.isEmpty, "Property name must not be empty")
        self.source = source
        self.property = property
    }

    // MARK: - Expression Evaluation

    @MainActor
    public func evaluate(in context: ATLExecutionContext) async throws -> (any EcoreValue)? {
        guard let sourceObject = try await source.evaluate(in: context) else {
            return nil
        }

        return try await context.navigate(from: sourceObject, property: property)
    }

    // MARK: - Equatable

    public static func == (lhs: ATLNavigationExpression, rhs: ATLNavigationExpression) -> Bool {
        return lhs.property == rhs.property && AnyHashable(lhs.source) == AnyHashable(rhs.source)
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

    @MainActor
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

    @MainActor
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

// MARK: - Type Literal Expression

/// Represents type literal expressions in ATL/OCL.
///
/// Type literals represent references to types that can be used in operations like
/// `oclIsKindOf()` or as generic type parameters. They support both simple types
/// and metamodel-qualified types.
///
/// ## Overview
///
/// Type literals can represent:
/// - **Simple types**: `String`, `Integer`, `Boolean`
/// - **Metamodel-qualified types**: `Class!Class`, `UML!Package`
/// - **Generic types**: `Sequence(Integer)`, `Set(String)`
///
/// ## Example Usage
///
/// ```swift
/// // Simple type literal
/// let stringType = ATLTypeLiteralExpression(typeName: "String")
///
/// // Metamodel-qualified type literal
/// let classType = ATLTypeLiteralExpression(typeName: "Class!Class")
///
/// // Generic type literal
/// let seqType = ATLTypeLiteralExpression(typeName: "Sequence(Integer)")
/// ```
public struct ATLTypeLiteralExpression: ATLExpression, Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The type name represented by this expression.
    ///
    /// This can be a simple type name, a metamodel-qualified type (Model!Type),
    /// or a generic type with parameters.
    public let typeName: String

    // MARK: - Initialisation

    /// Creates a new type literal expression.
    ///
    /// - Parameter typeName: The type name to represent
    public init(typeName: String) {
        precondition(!typeName.isEmpty, "Type name must not be empty")
        self.typeName = typeName
    }

    // MARK: - Expression Evaluation

    @MainActor
    public func evaluate(in context: ATLExecutionContext) async throws -> (any EcoreValue)? {
        // Type literals evaluate to their string representation
        // This allows them to be used in type-checking operations
        return typeName
    }

    // MARK: - Equatable & Hashable

    public static func == (lhs: ATLTypeLiteralExpression, rhs: ATLTypeLiteralExpression) -> Bool {
        return lhs.typeName == rhs.typeName
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(typeName)
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
/// let addition = ATLBinaryExpression(
///     left: ATLVariableExpression(name: "x"),
///     operator: .plus,
///     right: ATLLiteralExpression(value: 10)
/// )
///
/// // Comparison operation
/// let comparison = ATLBinaryExpression(
///     left: ATLVariableExpression(name: "age"),
///     operator: .greaterThan,
///     right: ATLLiteralExpression(value: 18)
/// )
/// ```
public struct ATLBinaryExpression: ATLExpression, Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The left operand expression.
    public let left: any ATLExpression

    /// The binary operator to apply.
    public let `operator`: ATLBinaryOperator

    /// The right operand expression.
    public let right: any ATLExpression

    // MARK: - Initialisation

    /// Creates a new binary operation expression.
    ///
    /// - Parameters:
    ///   - left: The left operand expression
    ///   - operator: The binary operator to apply
    ///   - right: The right operand expression
    public init(left: any ATLExpression, `operator`: ATLBinaryOperator, right: any ATLExpression) {
        self.left = left
        self.`operator` = `operator`
        self.right = right
    }

    // MARK: - Expression Evaluation

    @MainActor
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

    public static func == (lhs: ATLBinaryExpression, rhs: ATLBinaryExpression)
        -> Bool
    {
        return lhs.`operator` == rhs.`operator`
            && AnyHashable(lhs.left) == AnyHashable(rhs.left)
            && AnyHashable(lhs.right) == AnyHashable(rhs.right)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(`operator`)
        hasher.combine(AnyHashable(left))
        hasher.combine(AnyHashable(right))
    }
}

// MARK: - Additional Expression Types

/// Conditional expression for if-then-else constructs.
public struct ATLConditionalExpression: ATLExpression, Sendable, Equatable, Hashable {
    /// The condition expression to evaluate.
    public let condition: any ATLExpression

    /// The expression to evaluate if condition is true.
    public let thenExpression: any ATLExpression

    /// The expression to evaluate if condition is false.
    public let elseExpression: any ATLExpression

    /// Creates a conditional expression.
    ///
    /// - Parameters:
    ///   - condition: Expression that evaluates to a boolean
    ///   - thenExpression: Expression for true condition
    ///   - elseExpression: Expression for false condition
    public init(
        condition: any ATLExpression, thenExpression: any ATLExpression,
        elseExpression: any ATLExpression
    ) {
        self.condition = condition
        self.thenExpression = thenExpression
        self.elseExpression = elseExpression
    }

    @MainActor
    public func evaluate(in context: ATLExecutionContext) async throws -> (any EcoreValue)? {
        let conditionValue = try await condition.evaluate(in: context)
        let conditionBool = (conditionValue as? Bool) ?? false

        if conditionBool {
            return try await thenExpression.evaluate(in: context)
        } else {
            return try await elseExpression.evaluate(in: context)
        }
    }

    public static func == (lhs: ATLConditionalExpression, rhs: ATLConditionalExpression) -> Bool {
        return AnyHashable(lhs.condition) == AnyHashable(rhs.condition)
            && AnyHashable(lhs.thenExpression) == AnyHashable(rhs.thenExpression)
            && AnyHashable(lhs.elseExpression) == AnyHashable(rhs.elseExpression)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(AnyHashable(condition))
        hasher.combine(AnyHashable(thenExpression))
        hasher.combine(AnyHashable(elseExpression))
    }
}

/// Unary operation expression for not, minus, etc.
public struct ATLUnaryExpression: ATLExpression, Sendable, Equatable, Hashable {
    /// The unary operator.
    public let `operator`: ATLUnaryOperator

    /// The operand expression.
    public let operand: any ATLExpression

    /// Creates a unary operation expression.
    ///
    /// - Parameters:
    ///   - operator: The unary operator
    ///   - operand: The operand expression
    public init(`operator`: ATLUnaryOperator, operand: any ATLExpression) {
        self.`operator` = `operator`
        self.operand = operand
    }

    @MainActor
    public func evaluate(in context: ATLExecutionContext) async throws -> (any EcoreValue)? {
        let operandValue = try await operand.evaluate(in: context)

        switch `operator` {
        case .not:
            if let boolValue = operandValue as? Bool {
                return !boolValue
            } else {
                throw ATLExecutionError.typeError("Cannot apply 'not' to non-boolean value")
            }
        case .minus:
            if let intValue = operandValue as? Int {
                return -intValue
            } else if let doubleValue = operandValue as? Double {
                return -doubleValue
            } else {
                throw ATLExecutionError.typeError("Cannot apply unary minus to non-numeric value")
            }
        }
    }

    public static func == (lhs: ATLUnaryExpression, rhs: ATLUnaryExpression)
        -> Bool
    {
        return lhs.`operator` == rhs.`operator`
            && AnyHashable(lhs.operand) == AnyHashable(rhs.operand)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(`operator`)
        hasher.combine(AnyHashable(operand))
    }
}

// MARK: - Let Expression

/// Represents let expressions in ATL/OCL for local variable bindings.
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
/// let letExpr = ATLLetExpression(
///     variableName: "avgPages",
///     variableType: "Real",
///     initExpression: ATLBinaryExpression(...),
///     inExpression: bodyExpression
/// )
/// ```
public struct ATLLetExpression: ATLExpression, Sendable, Equatable, Hashable {
    /// The variable name for the let binding.
    public let variableName: String

    /// The optional type annotation for the variable.
    public let variableType: String?

    /// The initialisation expression for the variable.
    public let initExpression: any ATLExpression

    /// The body expression evaluated with the variable binding in scope.
    public let inExpression: any ATLExpression

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
        initExpression: any ATLExpression,
        inExpression: any ATLExpression
    ) {
        precondition(!variableName.isEmpty, "Variable name must not be empty")
        self.variableName = variableName
        self.variableType = variableType
        self.initExpression = initExpression
        self.inExpression = inExpression
    }

    @MainActor
    public func evaluate(in context: ATLExecutionContext) async throws -> (any EcoreValue)? {
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

    public static func == (lhs: ATLLetExpression, rhs: ATLLetExpression) -> Bool {
        return lhs.variableName == rhs.variableName
            && lhs.variableType == rhs.variableType
            && AnyHashable(lhs.initExpression) == AnyHashable(rhs.initExpression)
            && AnyHashable(lhs.inExpression) == AnyHashable(rhs.inExpression)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(variableName)
        hasher.combine(variableType)
        hasher.combine(AnyHashable(initExpression))
        hasher.combine(AnyHashable(inExpression))
    }
}

// MARK: - Tuple Expression

/// Represents an ATL/OCL tuple expression with typed fields.
///
/// Tuple expressions create structured composite values with named fields,
/// following the OCL syntax:
/// ```
/// Tuple{field1 : Type1 = value1, field2 : Type2 = value2, ...}
/// ```
///
/// ## Example Usage
///
/// ```swift
/// let tupleExpr = ATLTupleExpression(
///     fields: [
///         ("author", "String", ATLNavigationExpression(...)),
///         ("pages", "Integer", ATLNavigationExpression(...))
///     ]
/// )
/// ```
public struct ATLTupleExpression: ATLExpression, Sendable, Equatable, Hashable {
    /// Tuple field definition.
    public typealias TupleField = (name: String, type: String?, value: any ATLExpression)

    /// The fields of the tuple.
    public let fields: [TupleField]

    /// Creates a new tuple expression.
    ///
    /// - Parameter fields: The tuple fields with names, optional types, and value expressions
    public init(fields: [TupleField]) {
        self.fields = fields
    }

    @MainActor
    public func evaluate(in context: ATLExecutionContext) async throws -> (any EcoreValue)? {
        var result: OrderedDictionary<String, any EcoreValue> = [:]

        for field in fields {
            let value = try await field.value.evaluate(in: context)
            if let value = value {
                result[field.name] = value
            }
        }

        // Return as a dictionary-like structure
        return result as? (any EcoreValue)
    }

    public static func == (lhs: ATLTupleExpression, rhs: ATLTupleExpression) -> Bool {
        guard lhs.fields.count == rhs.fields.count else { return false }

        for (lField, rField) in zip(lhs.fields, rhs.fields) {
            guard lField.name == rField.name && lField.type == rField.type else {
                return false
            }
            guard AnyHashable(lField.value) == AnyHashable(rField.value) else {
                return false
            }
        }

        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(fields.count)
        for field in fields {
            hasher.combine(field.name)
            hasher.combine(field.type)
            hasher.combine(AnyHashable(field.value))
        }
    }
}

/// Method call expression for OCL-style method invocations.
public struct ATLMethodCallExpression: ATLExpression, Sendable, Equatable, Hashable {
    /// The receiver expression.
    public let receiver: any ATLExpression

    /// The method name.
    public let methodName: String

    /// The method arguments.
    public let arguments: [any ATLExpression]

    /// Creates a method call expression.
    ///
    /// - Parameters:
    ///   - receiver: The object on which to call the method
    ///   - methodName: The name of the method
    ///   - arguments: The method arguments
    public init(
        receiver: any ATLExpression, methodName: String, arguments: [any ATLExpression] = []
    ) {
        self.receiver = receiver
        self.methodName = methodName
        self.arguments = arguments
    }

    @MainActor
    public func evaluate(in context: ATLExecutionContext) async throws -> (any EcoreValue)? {
        let receiverValue = try await receiver.evaluate(in: context)

        // For collection operations that need lambda expressions, pass them directly
        if isCollectionOperation(methodName) && arguments.count == 1 {
            if let lambdaArg = arguments[0] as? ATLLambdaExpression {
                return try await dispatchCollectionMethod(
                    methodName: methodName,
                    receiver: receiverValue,
                    lambdaExpression: lambdaArg,
                    context: context
                )
            }
        }

        let argumentValues = try await evaluateArguments(in: context)

        // Handle built-in OCL methods with proper overloading support
        return try await dispatchMethod(
            methodName: methodName,
            receiver: receiverValue,
            arguments: argumentValues,
            context: context
        )
    }

    private func evaluateArguments(in context: ATLExecutionContext) async throws -> [(
        any EcoreValue
    )?] {
        var results: [(any EcoreValue)?] = []
        for arg in arguments {
            results.append(try await arg.evaluate(in: context))
        }
        return results
    }

    /// Check if a method name is a collection operation that requires lambda expressions.
    private func isCollectionOperation(_ methodName: String) -> Bool {
        return ["select", "reject", "collect", "exists", "forAll", "one"].contains(methodName)
    }

    /// Dispatch collection methods that work with lambda expressions directly.
    private func dispatchCollectionMethod(
        methodName: String,
        receiver: (any EcoreValue)?,
        lambdaExpression: ATLLambdaExpression,
        context: ATLExecutionContext
    ) async throws -> (any EcoreValue)? {
        switch methodName {
        case "select":
            return try await handleSelectWithLambda(receiver, lambdaExpression, context)
        case "reject":
            return try await handleRejectWithLambda(receiver, lambdaExpression, context)
        case "collect":
            return try await handleCollectWithLambda(receiver, lambdaExpression, context)
        case "exists":
            return try await handleExistsWithLambda(receiver, lambdaExpression, context)
        case "forAll":
            return try await handleForAllWithLambda(receiver, lambdaExpression, context)
        case "one":
            return try await handleOneWithLambda(receiver, lambdaExpression, context)
        default:
            throw ATLExecutionError.invalidOperation("Unknown collection operation: \(methodName)")
        }
    }

    /// Dispatches method calls with proper ATL/OCL overloading support.
    ///
    /// This method handles method resolution based on both method name and argument types,
    /// ensuring compliance with ATL/OCL method overloading semantics.
    private func dispatchMethod(
        methodName: String,
        receiver: (any EcoreValue)?,
        arguments: [(any EcoreValue)?],
        context: ATLExecutionContext
    ) async throws -> (any EcoreValue)? {

        // Method signature: methodName + argument count + argument types
        let signature = createMethodSignature(methodName: methodName, arguments: arguments)

        switch signature {
        // Collection query operations
        case let sig where sig.starts(with: "allInstances"):
            return try await handleAllInstances(receiver, in: context)
        case let sig where sig.starts(with: "size"):
            return try handleSize(receiver)
        case let sig where sig.starts(with: "isEmpty"):
            return try handleIsEmpty(receiver)
        case let sig where sig.starts(with: "includes") && arguments.count == 1:
            return try handleIncludes(receiver, arguments[0])
        case let sig where sig.starts(with: "excludes") && arguments.count == 1:
            return try handleExcludes(receiver, arguments[0])
        case let sig where sig.starts(with: "first"):
            return try handleFirst(receiver)
        case let sig where sig.starts(with: "last"):
            return try handleLast(receiver)

        // Collection filtering operations
        case let sig where sig.starts(with: "select") && arguments.count == 1:
            return try await handleSelect(receiver, arguments[0], context)
        case let sig where sig.starts(with: "reject") && arguments.count == 1:
            return try await handleReject(receiver, arguments[0], context)
        case let sig where sig.starts(with: "collect") && arguments.count == 1:
            return try await handleCollect(receiver, arguments[0], context)

        // Collection aggregate operations
        case let sig where sig.starts(with: "exists") && arguments.count == 1:
            return try await handleExists(receiver, arguments[0], context)
        case let sig where sig.starts(with: "forAll") && arguments.count == 1:
            return try await handleForAll(receiver, arguments[0], context)
        case let sig where sig.starts(with: "one") && arguments.count == 1:
            return try await handleOne(receiver, arguments[0], context)
        case let sig where sig.starts(with: "iterate") && arguments.count == 2:
            return try await handleIterate(receiver, arguments[0], arguments[1], context)

        // Collection type conversion
        case let sig where sig.starts(with: "asSequence"):
            return try handleAsSequence(receiver)
        case let sig where sig.starts(with: "asSet"):
            return try handleAsSet(receiver)
        case let sig where sig.starts(with: "asBag"):
            return try handleAsBag(receiver)
        case let sig where sig.starts(with: "asOrderedSet"):
            return try handleAsOrderedSet(receiver)

        // Collection manipulation
        case let sig where sig.starts(with: "union") && arguments.count == 1:
            return try handleUnion(receiver, arguments[0])
        case let sig where sig.starts(with: "intersection") && arguments.count == 1:
            return try handleIntersection(receiver, arguments[0])
        case let sig where sig.starts(with: "flatten"):
            return try handleFlatten(receiver)
        case let sig where sig.starts(with: "sortedBy") && arguments.count == 1:
            return try await handleSortedBy(receiver, arguments[0], context)

        // Arithmetic operations
        case let sig where sig.starts(with: "mod") && arguments.count == 1:
            return try handleMod(receiver, arguments[0])
        case let sig where sig.starts(with: "power") && arguments.count == 1:
            return try handlePower(receiver, arguments[0])
        case let sig where sig.starts(with: "isEven"):
            return try handleIsEven(receiver)
        case let sig where sig.starts(with: "square"):
            return try handleSquare(receiver)

        // String operations
        case let sig where sig.starts(with: "toString"):
            return try handleToString(receiver)
        case let sig where sig.starts(with: "toUpperCase"):
            return try handleToUpperCase(receiver)
        case let sig where sig.starts(with: "reverse"):
            return try handleReverse(receiver)

        default:
            throw ATLExecutionError.unsupportedOperation(
                "Method signature '\(signature)' not supported")
        }
    }

    /// Creates a method signature string for proper overloading resolution.
    private func createMethodSignature(methodName: String, arguments: [(any EcoreValue)?]) -> String
    {
        let argTypes = arguments.map { arg in
            guard let arg = arg else { return "OclVoid" }
            switch arg {
            case is String: return "String"
            case is Int: return "Integer"
            case is Double: return "Real"
            case is Bool: return "Boolean"
            case is [Any]: return "Collection"
            default: return "OclAny"
            }
        }

        return "\(methodName)(\(argTypes.joined(separator: ",")))"
    }

    @MainActor
    private func handleAllInstances(
        _ receiverValue: (any EcoreValue)?, in context: ATLExecutionContext
    ) async throws -> (any EcoreValue)? {
        // Extract type name from receiver (should be a type reference)
        guard let typeName = receiverValue as? String else {
            throw ATLExecutionError.typeError("allInstances() requires type name as receiver")
        }

        // Parse type specification (e.g., "MyMetamodel!MyClass")
        let typeComponents = typeName.split(separator: "!")
        guard typeComponents.count == 2 else {
            throw ATLExecutionError.typeError(
                "Invalid type specification for allInstances(): '\(typeName)'"
            )
        }

        let metamodelName = String(typeComponents[0])
        let className = String(typeComponents[1])

        // Find the model alias that uses this metamodel
        guard let modelAlias = context.module.sourceMetamodels.first(where: { $0.value.name == metamodelName })?.key else {
            throw ATLExecutionError.invalidOperation("No source model found for metamodel '\(metamodelName)'")
        }

        // Get the source resource for the specified model
        guard let sourceResource = context.getSource(modelAlias) else {
            throw ATLExecutionError.invalidOperation("Source model '\(modelAlias)' not found")
        }

        // Get the module to access metamodels
        guard let sourceMetamodel = context.module.sourceMetamodels[modelAlias] else {
            throw ATLExecutionError.invalidOperation("Source metamodel '\(modelAlias)' not found")
        }

        // Find the specified class in the metamodel
        guard let eClass = sourceMetamodel.getClassifier(className) as? EClass else {
            throw ATLExecutionError.typeError(
                "Class '\(className)' not found in metamodel '\(modelAlias)'"
            )
        }

        // Get all instances of this class from the source resource
        let instances = await sourceResource.getAllInstancesOf(eClass)

        // Convert instances to a format suitable for ATL processing
        // For now, return the count as an integer (placeholder implementation)
        return instances.count
    }

    private func handleSize(_ receiverValue: (any EcoreValue)?) throws -> (any EcoreValue)? {
        if let stringValue = receiverValue as? String {
            return stringValue.count
        } else if let arrayValue = receiverValue as? [Any] {
            return arrayValue.count
        } else {
            return 0
        }
    }

    private func handleIsEmpty(_ receiverValue: (any EcoreValue)?) throws -> (any EcoreValue)? {
        if let stringValue = receiverValue as? String {
            return stringValue.isEmpty
        } else if let arrayValue = receiverValue as? [Any] {
            return arrayValue.isEmpty
        } else {
            return true
        }
    }

    private func handleMod(_ receiverValue: (any EcoreValue)?, _ argument: (any EcoreValue)?) throws
        -> (any EcoreValue)?
    {
        guard let leftInt = receiverValue as? Int,
            let rightInt = argument as? Int
        else {
            throw ATLExecutionError.typeError("Modulo requires integer operands")
        }

        guard rightInt != 0 else {
            throw ATLExecutionError.divisionByZero
        }

        return leftInt % rightInt
    }

    // MARK: - Additional OCL Method Implementations

    private func handleToString(_ receiverValue: (any EcoreValue)?) throws -> (any EcoreValue)? {
        guard let value = receiverValue else {
            return "null"
        }
        return "\(value)"
    }

    private func handleToUpperCase(_ receiverValue: (any EcoreValue)?) throws -> (any EcoreValue)? {
        guard let stringValue = receiverValue as? String else {
            throw ATLExecutionError.typeError("toUpperCase() requires String receiver")
        }
        return stringValue.uppercased()
    }

    private func handleReverse(_ receiverValue: (any EcoreValue)?) throws -> (any EcoreValue)? {
        guard let stringValue = receiverValue as? String else {
            throw ATLExecutionError.typeError("reverse() requires String receiver")
        }
        return String(stringValue.reversed())
    }

    private func handlePower(_ receiverValue: (any EcoreValue)?, _ argument: (any EcoreValue)?)
        throws -> (any EcoreValue)?
    {
        guard let base = receiverValue as? Int,
            let exponent = argument as? Int
        else {
            throw ATLExecutionError.typeError("power() requires Integer operands")
        }

        guard exponent >= 0 else {
            throw ATLExecutionError.typeError("power() requires non-negative exponent")
        }

        return Int(pow(Double(base), Double(exponent)))
    }

    private func handleIsEven(_ receiverValue: (any EcoreValue)?) throws -> (any EcoreValue)? {
        guard let intValue = receiverValue as? Int else {
            throw ATLExecutionError.typeError("isEven() requires Integer receiver")
        }
        return intValue % 2 == 0
    }

    private func handleSquare(_ receiverValue: (any EcoreValue)?) throws -> (any EcoreValue)? {
        guard let intValue = receiverValue as? Int else {
            throw ATLExecutionError.typeError("square() requires Integer receiver")
        }
        return intValue * intValue
    }

    // MARK: - OCL Collection Operations

    /// Handles collection `includes` operation.
    private func handleIncludes(_ receiverValue: (any EcoreValue)?, _ element: (any EcoreValue)?)
        throws -> (any EcoreValue)?
    {
        guard let collection = receiverValue as? [Any] else {
            throw ATLExecutionError.typeError("includes() requires Collection receiver")
        }

        return collection.contains { item in
            return areValuesEqual(item as? (any EcoreValue), element)
        }
    }

    /// Handles collection `excludes` operation.
    private func handleExcludes(_ receiverValue: (any EcoreValue)?, _ element: (any EcoreValue)?)
        throws -> (any EcoreValue)?
    {
        guard let includes = try handleIncludes(receiverValue, element) as? Bool else {
            return false
        }
        return !includes
    }

    /// Handles collection `first` operation.
    private func handleFirst(_ receiverValue: (any EcoreValue)?) throws -> (any EcoreValue)? {
        guard let collection = receiverValue as? [Any], !collection.isEmpty else {
            throw ATLExecutionError.runtimeError("first() on empty collection")
        }
        return collection.first as? (any EcoreValue)
    }

    /// Handles collection `last` operation.
    private func handleLast(_ receiverValue: (any EcoreValue)?) throws -> (any EcoreValue)? {
        guard let collection = receiverValue as? [Any], !collection.isEmpty else {
            throw ATLExecutionError.runtimeError("last() on empty collection")
        }
        return collection.last as? (any EcoreValue)
    }

    /// Handles collection `select` operation with lambda expression.
    private func handleSelectWithLambda(
        _ receiverValue: (any EcoreValue)?,
        _ lambdaExpression: ATLLambdaExpression,
        _ context: ATLExecutionContext
    ) async throws -> (any EcoreValue)? {
        guard let collection = receiverValue as? [Any] else {
            throw ATLExecutionError.typeError("select() requires Collection receiver")
        }

        var results: [Any] = []

        for item in collection {
            let result = try await lambdaExpression.evaluateWith(
                parameterValue: item as? (any EcoreValue),
                in: context
            )

            if let boolResult = result as? Bool, boolResult {
                results.append(item)
            }
        }

        return results as? (any EcoreValue)
    }

    /// Handles collection `select` operation with fallback for non-lambda expressions.
    @MainActor
    private func handleSelect(
        _ receiverValue: (any EcoreValue)?,
        _ predicate: (any EcoreValue)?,
        _ context: ATLExecutionContext
    ) async throws -> (any EcoreValue)? {
        guard let collection = receiverValue as? [Any] else {
            throw ATLExecutionError.typeError("select() requires Collection receiver")
        }

        var results: [Any] = []

        // This is for fallback cases where we have an evaluated expression result
        // In most cases, we should use handleSelectWithLambda instead
        context.pushScope()
        defer {
            context.popScope()
        }

        for item in collection {
            context.setVariable("self", value: item as? (any EcoreValue))
            // For now, we can't re-evaluate a predicate result
            // This would need a different approach
            results.append(item)
        }

        return results as? (any EcoreValue)
    }

    /// Handles collection `reject` operation with lambda expression.
    private func handleRejectWithLambda(
        _ receiverValue: (any EcoreValue)?,
        _ lambdaExpression: ATLLambdaExpression,
        _ context: ATLExecutionContext
    ) async throws -> (any EcoreValue)? {
        guard let collection = receiverValue as? [Any] else {
            throw ATLExecutionError.typeError("reject() requires Collection receiver")
        }

        var results: [Any] = []

        for item in collection {
            let result = try await lambdaExpression.evaluateWith(
                parameterValue: item as? (any EcoreValue),
                in: context
            )

            if let boolResult = result as? Bool, !boolResult {
                results.append(item)
            }
        }

        return results as? (any EcoreValue)
    }

    /// Handles collection `reject` operation with fallback for non-lambda expressions.
    @MainActor
    private func handleReject(
        _ receiverValue: (any EcoreValue)?,
        _ predicate: (any EcoreValue)?,
        _ context: ATLExecutionContext
    ) async throws -> (any EcoreValue)? {
        guard let collection = receiverValue as? [Any] else {
            throw ATLExecutionError.typeError("reject() requires Collection receiver")
        }

        var results: [Any] = []

        // This is for fallback cases where we have an evaluated expression result
        context.pushScope()
        defer {
            context.popScope()
        }

        for item in collection {
            context.setVariable("self", value: item as? (any EcoreValue))
            results.append(item)
        }

        return results as? (any EcoreValue)
    }

    /// Handles collection `collect` operation with fallback for non-lambda expressions.
    @MainActor
    private func handleCollect(
        _ receiverValue: (any EcoreValue)?,
        _ transformer: (any EcoreValue)?,
        _ context: ATLExecutionContext
    ) async throws -> (any EcoreValue)? {
        guard let collection = receiverValue as? [Any] else {
            throw ATLExecutionError.typeError("collect() requires Collection receiver")
        }

        var results: [Any] = []

        // This is for fallback cases where we have an evaluated expression result
        context.pushScope()
        defer {
            context.popScope()
        }

        for item in collection {
            context.setVariable("self", value: item as? (any EcoreValue))
            results.append(item)
        }

        return results as? (any EcoreValue)
    }

    /// Handles collection `collect` operation with lambda expression.
    private func handleCollectWithLambda(
        _ receiverValue: (any EcoreValue)?,
        _ lambdaExpression: ATLLambdaExpression,
        _ context: ATLExecutionContext
    ) async throws -> (any EcoreValue)? {
        guard let collection = receiverValue as? [Any] else {
            throw ATLExecutionError.typeError("collect() requires Collection receiver")
        }

        var results: [Any] = []

        for item in collection {
            let result = try await lambdaExpression.evaluateWith(
                parameterValue: item as? (any EcoreValue),
                in: context
            )

            if let transformedValue = result {
                results.append(transformedValue)
            }
        }

        return results as? (any EcoreValue)
    }

    /// Handles collection `exists` operation with lambda expression.
    private func handleExistsWithLambda(
        _ receiverValue: (any EcoreValue)?,
        _ lambdaExpression: ATLLambdaExpression,
        _ context: ATLExecutionContext
    ) async throws -> (any EcoreValue)? {
        guard let collection = receiverValue as? [Any] else {
            throw ATLExecutionError.typeError("exists() requires Collection receiver")
        }

        for item in collection {
            let result = try await lambdaExpression.evaluateWith(
                parameterValue: item as? (any EcoreValue),
                in: context
            )

            if let boolResult = result as? Bool, boolResult {
                return true
            }
        }

        return false
    }

    /// Handles collection `exists` operation with fallback.
    @MainActor
    private func handleExists(
        _ receiverValue: (any EcoreValue)?,
        _ predicate: (any EcoreValue)?,
        _ context: ATLExecutionContext
    ) async throws -> (any EcoreValue)? {
        guard let collection = receiverValue as? [Any] else {
            throw ATLExecutionError.typeError("exists() requires Collection receiver")
        }

        return !collection.isEmpty
    }

    /// Handles collection `forAll` operation with lambda expression.
    private func handleForAllWithLambda(
        _ receiverValue: (any EcoreValue)?,
        _ lambdaExpression: ATLLambdaExpression,
        _ context: ATLExecutionContext
    ) async throws -> (any EcoreValue)? {
        guard let collection = receiverValue as? [Any] else {
            throw ATLExecutionError.typeError("forAll() requires Collection receiver")
        }

        for item in collection {
            let result = try await lambdaExpression.evaluateWith(
                parameterValue: item as? (any EcoreValue),
                in: context
            )

            if let boolResult = result as? Bool, !boolResult {
                return false
            }
        }

        return true
    }

    /// Handles collection `forAll` operation with fallback.
    @MainActor
    private func handleForAll(
        _ receiverValue: (any EcoreValue)?,
        _ predicate: (any EcoreValue)?,
        _ context: ATLExecutionContext
    ) async throws -> (any EcoreValue)? {
        guard receiverValue as? [Any] != nil else {
            throw ATLExecutionError.typeError("forAll() requires Collection receiver")
        }

        return true  // Fallback assumes all pass
    }

    /// Handles collection `one` operation with lambda expression.
    private func handleOneWithLambda(
        _ receiverValue: (any EcoreValue)?,
        _ lambdaExpression: ATLLambdaExpression,
        _ context: ATLExecutionContext
    ) async throws -> (any EcoreValue)? {
        guard let collection = receiverValue as? [Any] else {
            throw ATLExecutionError.typeError("one() requires Collection receiver")
        }

        var matchCount = 0

        for item in collection {
            let result = try await lambdaExpression.evaluateWith(
                parameterValue: item as? (any EcoreValue),
                in: context
            )

            if let boolResult = result as? Bool, boolResult {
                matchCount += 1
                if matchCount > 1 {
                    return false
                }
            }
        }

        return matchCount == 1
    }

    /// Handles collection `one` operation with fallback.
    @MainActor
    private func handleOne(
        _ receiverValue: (any EcoreValue)?,
        _ predicate: (any EcoreValue)?,
        _ context: ATLExecutionContext
    ) async throws -> (any EcoreValue)? {
        guard let collection = receiverValue as? [Any] else {
            throw ATLExecutionError.typeError("one() requires Collection receiver")
        }

        return collection.count == 1
    }

    /// Handles collection `iterate` operation.
    @MainActor
    private func handleIterate(
        _ receiverValue: (any EcoreValue)?,
        _ accumulator: (any EcoreValue)?,
        _ iterator: (any EcoreValue)?,
        _ context: ATLExecutionContext
    ) async throws -> (any EcoreValue)? {
        guard let collection = receiverValue as? [Any] else {
            throw ATLExecutionError.typeError("iterate() requires Collection receiver")
        }

        guard let iteratorExpr = iterator as? any ATLExpression else {
            throw ATLExecutionError.typeError("iterate() requires expression argument")
        }

        var accValue = accumulator

        context.pushScope()
        defer {
            context.popScope()
        }

        for item in collection {
            context.setVariable("it", value: item as? (any EcoreValue))
            context.setVariable("acc", value: accValue)
            accValue = try await iteratorExpr.evaluate(in: context)
        }

        return accValue
    }

    /// Handles collection type conversion to Sequence.
    private func handleAsSequence(_ receiverValue: (any EcoreValue)?) throws -> (any EcoreValue)? {
        guard let collection = receiverValue as? [Any] else {
            throw ATLExecutionError.typeError("asSequence() requires Collection receiver")
        }
        return collection.compactMap { $0 as? String }  // Convert to string array
    }

    /// Handles collection type conversion to Set.
    private func handleAsSet(_ receiverValue: (any EcoreValue)?) throws -> (any EcoreValue)? {
        guard let collection = receiverValue as? [Any] else {
            throw ATLExecutionError.typeError("asSet() requires Collection receiver")
        }

        // Remove duplicates while preserving order
        var seen = Set<String>()
        var uniqueItems: [Any] = []

        for item in collection {
            let key = String(describing: item)
            if !seen.contains(key) {
                seen.insert(key)
                uniqueItems.append(item)
            }
        }

        return uniqueItems.compactMap { $0 as? String }
    }

    /// Handles collection type conversion to Bag.
    private func handleAsBag(_ receiverValue: (any EcoreValue)?) throws -> (any EcoreValue)? {
        guard let collection = receiverValue as? [Any] else {
            throw ATLExecutionError.typeError("asBag() requires Collection receiver")
        }
        return collection.compactMap { $0 as? String }  // Convert to string array
    }

    /// Handles collection type conversion to OrderedSet.
    private func handleAsOrderedSet(_ receiverValue: (any EcoreValue)?) throws -> (any EcoreValue)? {
        guard let collection = receiverValue as? [Any] else {
            throw ATLExecutionError.typeError("asOrderedSet() requires Collection receiver")
        }

        // Remove duplicates while preserving order
        var seen = Set<String>()
        var uniqueItems: [Any] = []

        for item in collection {
            let key = String(describing: item)
            if !seen.contains(key) {
                seen.insert(key)
                uniqueItems.append(item)
            }
        }

        return uniqueItems.compactMap { $0 as? String }
    }

    /// Handles collection `union` operation.
    private func handleUnion(_ receiverValue: (any EcoreValue)?, _ other: (any EcoreValue)?)
        throws -> (any EcoreValue)?
    {
        guard let collection1 = receiverValue as? [Any],
            let collection2 = other as? [Any]
        else {
            throw ATLExecutionError.typeError("union() requires Collection operands")
        }

        return (collection1 + collection2).compactMap { $0 as? String }
    }

    /// Handles collection `intersection` operation.
    private func handleIntersection(_ receiverValue: (any EcoreValue)?, _ other: (any EcoreValue)?)
        throws -> (any EcoreValue)?
    {
        guard let collection1 = receiverValue as? [Any],
            let collection2 = other as? [Any]
        else {
            throw ATLExecutionError.typeError("intersection() requires Collection operands")
        }

        var intersection: [Any] = []

        for item in collection1 {
            if collection2.contains(where: { otherItem in
                areValuesEqual(item as? (any EcoreValue), otherItem as? (any EcoreValue))
            }) {
                intersection.append(item)
            }
        }

        return intersection.compactMap { $0 as? String }
    }

    /// Handles collection `flatten` operation.
    private func handleFlatten(_ receiverValue: (any EcoreValue)?) throws -> (any EcoreValue)? {
        guard let collection = receiverValue as? [Any] else {
            throw ATLExecutionError.typeError("flatten() requires Collection receiver")
        }

        var flattened: [Any] = []

        for item in collection {
            if let nestedCollection = item as? [Any] {
                flattened.append(contentsOf: nestedCollection)
            } else {
                flattened.append(item)
            }
        }

        return flattened.compactMap { $0 as? String }
    }

    /// Handles collection `sortedBy` operation.
    @MainActor
    private func handleSortedBy(
        _ receiverValue: (any EcoreValue)?,
        _ keySelector: (any EcoreValue)?,
        _ context: ATLExecutionContext
    ) async throws -> (any EcoreValue)? {
        guard let collection = receiverValue as? [Any] else {
            throw ATLExecutionError.typeError("sortedBy() requires Collection receiver")
        }

        guard let keySelectorExpr = keySelector as? any ATLExpression else {
            throw ATLExecutionError.typeError("sortedBy() requires expression argument")
        }

        context.pushScope()
        defer {
            context.popScope()
        }

        // Evaluate sort keys for all items
        var itemsWithKeys: [(item: Any, key: Any)] = []

        for item in collection {
            context.setVariable("it", value: item as? (any EcoreValue))
            let key = try await keySelectorExpr.evaluate(in: context)
            itemsWithKeys.append((item: item, key: key as Any))
        }

        // Sort by computed keys
        let sortedItems = itemsWithKeys.sorted { lhs, rhs in
            return compareAnyValues(lhs.key, rhs.key) < 0
        }

        return sortedItems.compactMap { $0.item as? String }
    }

    // MARK: - Utility Methods

    /// Compares two values for equality, handling different types appropriately.
    private func areValuesEqual(_ left: (any EcoreValue)?, _ right: (any EcoreValue)?) -> Bool {
        switch (left, right) {
        case (nil, nil):
            return true
        case (nil, _), (_, nil):
            return false
        case (let l as String, let r as String):
            return l == r
        case (let l as Int, let r as Int):
            return l == r
        case (let l as Double, let r as Double):
            return l == r
        case (let l as Bool, let r as Bool):
            return l == r
        default:
            return false
        }
    }

    /// Compares two Any values for sorting purposes.
    private func compareAnyValues(_ left: Any, _ right: Any) -> Int {
        switch (left, right) {
        case (let l as String, let r as String):
            return l < r ? -1 : (l > r ? 1 : 0)
        case (let l as Int, let r as Int):
            return l < r ? -1 : (l > r ? 1 : 0)
        case (let l as Double, let r as Double):
            return l < r ? -1 : (l > r ? 1 : 0)
        default:
            return String(describing: left) < String(describing: right) ? -1 : 1
        }
    }

    public static func == (lhs: ATLMethodCallExpression, rhs: ATLMethodCallExpression) -> Bool {
        guard
            AnyHashable(lhs.receiver) == AnyHashable(rhs.receiver)
                && lhs.methodName == rhs.methodName
                && lhs.arguments.count == rhs.arguments.count
        else {
            return false
        }

        // Compare each argument for full ATL/OCL method signature compliance
        for (lhsArg, rhsArg) in zip(lhs.arguments, rhs.arguments) {
            if AnyHashable(lhsArg) != AnyHashable(rhsArg) {
                return false
            }
        }

        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(AnyHashable(receiver))
        hasher.combine(methodName)
        hasher.combine(arguments.count)
        // Include argument hashes for proper ATL method overloading support
        for argument in arguments {
            hasher.combine(AnyHashable(argument))
        }
    }
}

/// Unary operators supported in ATL expressions.
public enum ATLUnaryOperator: String, Sendable, CaseIterable, Equatable {
    case not = "not"
    case minus = "-"
}

// MARK; - Helper Types

/// A phantom type representing an ATL expression that can never be instantiated.
///
/// This type is used for generic contexts where an optional expression type
/// is needed but no actual expression will be present (e.g., matched rules
/// without guard expressions).
public enum ATLExpressionNever: ATLExpression {
    // This enum has no cases and can never be instantiated

    @MainActor
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

/// ATL Lambda Expression for OCL iterator operations.
///
/// Lambda expressions represent function-like constructs used in OCL collection
/// operations such as `select`, `collect`, `exists`, and `forAll`. They encapsulate
/// both parameter binding and expression evaluation within iterator contexts.
///
/// ## Overview
///
/// Lambda expressions in ATL follow OCL semantics where an iterator variable
/// is bound to each collection element during evaluation. The lambda body
/// is evaluated once for each element with the parameter bound to that element.
///
/// ## Example Usage
///
/// ```swift
/// // Equivalent to OCL: collection->select(item | item.age > 18)
/// let lambda = ATLLambdaExpression(
///     parameter: "item",
///     body: ATLNavigationExpression(
///         source: ATLVariableExpression(name: "item"),
///         property: "age"
///     )
/// )
/// ```
public struct ATLLambdaExpression: ATLExpression, Sendable, Equatable, Hashable {
    /// The parameter name for the lambda variable.
    public let parameter: String

    /// The expression body of the lambda.
    public let body: any ATLExpression

    /// Creates a lambda expression.
    ///
    /// - Parameters:
    ///   - parameter: The name of the lambda parameter
    ///   - body: The expression to evaluate with the parameter bound
    public init(parameter: String, body: any ATLExpression) {
        self.parameter = parameter
        self.body = body
    }

    /// Evaluates the lambda expression in the standard context.
    ///
    /// This method provides compatibility with the general ATLExpression protocol
    /// but lambda expressions are typically evaluated using `evaluateWith` instead.
    ///
    /// - Parameter context: The execution context
    /// - Returns: The evaluation result
    /// - Throws: ATL execution errors
    @MainActor
    public func evaluate(in context: ATLExecutionContext) async throws -> (any EcoreValue)? {
        // Lambda expressions need parameter binding, so this is typically not used directly
        return try await body.evaluate(in: context)
    }

    /// Evaluates the lambda expression with a parameter value bound.
    ///
    /// This is the primary evaluation method for lambda expressions, used by
    /// collection operations to bind the iterator variable to collection elements.
    ///
    /// - Parameters:
    ///   - parameterValue: The value to bind to the lambda parameter
    ///   - context: The execution context
    /// - Parameter context: The execution context
    /// - Returns: The evaluation result
    /// - Throws: ATL execution errors
    @MainActor
    public func evaluateWith(
        parameterValue: (any EcoreValue)?,
        in context: ATLExecutionContext
    ) async throws -> (any EcoreValue)? {
        // Create new scope and bind parameter
        context.pushScope()
        defer {
            context.popScope()
        }

        context.setVariable(parameter, value: parameterValue)
        return try await body.evaluate(in: context)
    }

    public static func == (lhs: ATLLambdaExpression, rhs: ATLLambdaExpression) -> Bool {
        return lhs.parameter == rhs.parameter && areATLExpressionsEqual(lhs.body, rhs.body)
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(parameter)
        hashATLExpression(body, into: &hasher)
    }
}

// MARK: - ATL Operation Expression

/// Represents an ATL operation call expression.
///
/// Operation expressions handle both contextual and context-free operation calls,
/// supporting the full range of ATL/OCL operations including helper functions,
/// built-in operations, and metamodel-specific operations.
///
/// ## Example Usage
///
/// ```swift
/// // Context-free operation call
/// let helperCall = ATLOperationExpression(
///     source: nil,
///     operationName: "myHelper",
///     arguments: [ATLLiteralExpression(value: "test")]
/// )
///
/// // Contextual operation call
/// let methodCall = ATLOperationExpression(
///     source: ATLVariableExpression(name: "self"),
///     operationName: "toString",
///     arguments: []
/// )
/// ```
public struct ATLOperationExpression: ATLExpression, Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The source expression (receiver) for the operation call.
    ///
    /// For contextual operations, this is the object on which the operation
    /// is invoked. For context-free operations, this may be `nil`.
    public let source: (any ATLExpression)?

    /// The name of the operation to invoke.
    public let operationName: String

    /// The argument expressions for the operation call.
    public let arguments: [any ATLExpression]

    // MARK: - Initialisation

    /// Creates a new operation expression.
    ///
    /// - Parameters:
    ///   - source: The source expression (receiver)
    ///   - operationName: The operation name
    ///   - arguments: The operation arguments
    public init(source: (any ATLExpression)?, operationName: String, arguments: [any ATLExpression])
    {
        self.source = source
        self.operationName = operationName
        self.arguments = arguments
    }

    // MARK: - Expression Evaluation

    @MainActor
    public func evaluate(in context: ATLExecutionContext) async throws -> (any EcoreValue)? {
        let sourceValue = try await source?.evaluate(in: context)

        let argumentValues = try await arguments.asyncMapMainActor { arg in
            try await arg.evaluate(in: context)
        }

        // For now, delegate to navigation if source exists, otherwise treat as helper call
        if sourceValue != nil {
            // This would need proper OCL operation implementation
            return nil  // Placeholder
        } else {
            // Context-free operation - treat as helper call
            return try await context.callHelper(operationName, arguments: argumentValues)
        }
    }

    public static func == (lhs: ATLOperationExpression, rhs: ATLOperationExpression) -> Bool {
        // Compare operation names
        guard lhs.operationName == rhs.operationName else { return false }

        // Compare source expressions
        switch (lhs.source, rhs.source) {
        case (nil, nil):
            break
        case (let lhsSource?, let rhsSource?):
            guard type(of: lhsSource) == type(of: rhsSource) else { return false }
            // Use ATLExpression equality (both conform to Equatable)
            guard areATLExpressionsEqual(lhsSource, rhsSource) else { return false }
        default:
            return false
        }

        // Compare arguments
        guard lhs.arguments.count == rhs.arguments.count else { return false }
        for (lhsArg, rhsArg) in zip(lhs.arguments, rhs.arguments) {
            guard type(of: lhsArg) == type(of: rhsArg) else { return false }
            guard areATLExpressionsEqual(lhsArg, rhsArg) else { return false }
        }

        return true
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(operationName)

        // Hash source using string representation
        if let source = source {
            hasher.combine(String(describing: type(of: source)))
            hashATLExpression(source, into: &hasher)
        } else {
            hasher.combine("nil")
        }

        // Hash arguments using string representation
        hasher.combine(arguments.count)
        for arg in arguments {
            hasher.combine(String(describing: type(of: arg)))
            hashATLExpression(arg, into: &hasher)
        }
    }
}

// MARK: - ATL Iterate Expression

/// Represents an ATL iterate expression with complex syntax.
///
/// The iterate expression supports the OCL-style iterate syntax:
/// ```
/// collection->iterate(param; accumulator : Type = defaultValue | body_expression)
/// ```
///
/// ## Example Usage
///
/// ```swift
/// let iterateExpr = ATLIterateExpression(
///     source: ATLVariableExpression(name: "numbers"),
///     parameter: "n",
///     accumulator: "sum",
///     accumulatorType: "Integer",
///     defaultValue: ATLLiteralExpression(value: 0),
///     body: ATLBinaryExpression(
///         left: ATLVariableExpression(name: "sum"),
///         operator: .add,
///         right: ATLVariableExpression(name: "n")
///     )
/// )
/// ```
public struct ATLIterateExpression: ATLExpression, Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The source collection expression.
    public let source: any ATLExpression

    /// The iteration parameter name.
    public let parameter: String

    /// The accumulator variable name.
    public let accumulator: String

    /// The accumulator type (optional).
    public let accumulatorType: String?

    /// The default value for the accumulator.
    public let defaultValue: any ATLExpression

    /// The body expression that computes the new accumulator value.
    public let body: any ATLExpression

    // MARK: - Initialization

    /// Creates a new iterate expression.
    ///
    /// - Parameters:
    ///   - source: The source collection expression
    ///   - parameter: The iteration parameter name
    ///   - accumulator: The accumulator variable name
    ///   - accumulatorType: The accumulator type (optional)
    ///   - defaultValue: The default value for the accumulator
    ///   - body: The body expression
    public init(
        source: any ATLExpression,
        parameter: String,
        accumulator: String,
        accumulatorType: String? = nil,
        defaultValue: any ATLExpression,
        body: any ATLExpression
    ) {
        self.source = source
        self.parameter = parameter
        self.accumulator = accumulator
        self.accumulatorType = accumulatorType
        self.defaultValue = defaultValue
        self.body = body
    }

    // MARK: - ATLExpression Protocol

    /// Evaluates the iterate expression in the given execution context.
    ///
    /// - Parameter context: The execution context
    /// - Returns: The final accumulator value after iteration
    /// - Throws: ATLExecutionError if evaluation fails
    @MainActor
    public func evaluate(in context: ATLExecutionContext) async throws -> (any EcoreValue)? {
        // Evaluate the source collection
        guard let sourceValue = try await source.evaluate(in: context) else {
            throw ATLExecutionError.typeError("iterate() requires non-nil collection")
        }

        guard let collection = sourceValue as? [Any] else {
            throw ATLExecutionError.typeError("iterate() requires Collection receiver")
        }

        // Evaluate the default accumulator value
        var accValue = try await defaultValue.evaluate(in: context)

        // Create a new scope for iteration
        context.pushScope()
        defer {
            context.popScope()
        }

        // Iterate over the collection
        for item in collection {
            // Set the iteration parameter
            context.setVariable(parameter, value: item as? (any EcoreValue))
            // Set the accumulator variable
            context.setVariable(accumulator, value: accValue)
            // Evaluate the body expression to get the new accumulator value
            accValue = try await body.evaluate(in: context)
        }

        return accValue
    }

    // MARK: - Equatable

    public static func == (lhs: ATLIterateExpression, rhs: ATLIterateExpression) -> Bool {
        return areATLExpressionsEqual(lhs.source, rhs.source) && lhs.parameter == rhs.parameter
            && lhs.accumulator == rhs.accumulator && lhs.accumulatorType == rhs.accumulatorType
            && areATLExpressionsEqual(lhs.defaultValue, rhs.defaultValue)
            && areATLExpressionsEqual(lhs.body, rhs.body)
    }

    // MARK: - Hashable

    public func hash(into hasher: inout Hasher) {
        hashATLExpression(source, into: &hasher)
        hasher.combine(parameter)
        hasher.combine(accumulator)
        hasher.combine(accumulatorType)
        hashATLExpression(defaultValue, into: &hasher)
        hashATLExpression(body, into: &hasher)
    }
}

// MARK: - ATL Collection Expression

/// Represents an ATL collection operation expression.
///
/// Collection expressions handle OCL-style collection operations such as select,
/// collect, exists, forAll, and other iterator-based operations on collections.
/// They support both simple operations and complex iterator expressions.
///
/// ## Example Usage
///
/// ```swift
/// // Simple collection operation
/// let sizeExpr = ATLCollectionExpression(
///     source: ATLVariableExpression(name: "items"),
///     operation: .size
/// )
///
/// // Iterator-based operation
/// let selectExpr = ATLCollectionExpression(
///     source: ATLVariableExpression(name: "numbers"),
///     operation: .select,
///     iterator: "n",
///     body: ATLBinaryExpression(
///         left: ATLVariableExpression(name: "n"),
///         operator: .greaterThan,
///         right: ATLLiteralExpression(value: 0)
///     )
/// )
/// ```
public struct ATLCollectionExpression: ATLExpression, Sendable, Equatable, Hashable {

    // MARK: - Properties

    /// The source collection expression.
    public let source: any ATLExpression

    /// The collection operation to perform.
    public let operation: ATLCollectionOperation

    /// The iterator variable name for operations that require one.
    public let iterator: String?

    /// The body expression for iterator-based operations.
    public let body: (any ATLExpression)?

    // MARK: - Initialisation

    /// Creates a new collection expression.
    ///
    /// - Parameters:
    ///   - source: The source collection
    ///   - operation: The collection operation
    ///   - iterator: Optional iterator variable name
    ///   - body: Optional body expression for iterator operations
    public init(
        source: any ATLExpression,
        operation: ATLCollectionOperation,
        iterator: String? = nil,
        body: (any ATLExpression)? = nil
    ) {
        self.source = source
        self.operation = operation
        self.iterator = iterator
        self.body = body
    }

    // MARK: - Expression Evaluation

    @MainActor
    public func evaluate(in context: ATLExecutionContext) async throws -> (any EcoreValue)? {
        let sourceValue = try await source.evaluate(in: context)

        // For now, return placeholder - full implementation would handle each operation type
        switch operation {
        case .size:
            if let collection = sourceValue as? [any EcoreValue] {
                return collection.count
            } else if let string = sourceValue as? String {
                return string.count
            }
            return 0

        case .isEmpty:
            if let collection = sourceValue as? [any EcoreValue] {
                return collection.isEmpty
            } else if let string = sourceValue as? String {
                return string.isEmpty
            }
            return true

        case .notEmpty:
            if let collection = sourceValue as? [any EcoreValue] {
                return !collection.isEmpty
            } else if let string = sourceValue as? String {
                return !string.isEmpty
            }
            return false

        default:
            // Complex operations would need full iterator support
            return nil
        }
    }

    public static func == (lhs: ATLCollectionExpression, rhs: ATLCollectionExpression) -> Bool {
        // Compare operations and iterators
        guard lhs.operation == rhs.operation && lhs.iterator == rhs.iterator else { return false }

        // Compare source expressions (non-optional)
        guard type(of: lhs.source) == type(of: rhs.source) else { return false }
        guard areATLExpressionsEqual(lhs.source, rhs.source) else { return false }

        // Compare body expressions (optional)
        switch (lhs.body, rhs.body) {
        case (nil, nil):
            return true
        case (let lhsBody?, let rhsBody?):
            guard type(of: lhsBody) == type(of: rhsBody) else { return false }
            return areATLExpressionsEqual(lhsBody, rhsBody)
        default:
            return false
        }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(operation)
        hasher.combine(iterator)

        // Hash source using string representation (non-optional)
        hasher.combine(String(describing: type(of: source)))
        hashATLExpression(source, into: &hasher)

        // Hash body using string representation (optional)
        if let body = body {
            hasher.combine(String(describing: type(of: body)))
            hashATLExpression(body, into: &hasher)
        } else {
            hasher.combine("nil")
        }
    }
}

/// Collection operations supported by ATL expressions.
public enum ATLCollectionOperation: String, Sendable, CaseIterable, Equatable, Hashable {
    case select, reject, collect, exists, forAll, any, one, iterate
    case size, isEmpty, notEmpty, first, last
    case union, intersection, difference
    case asSet, asSequence, asBag, flatten
    case including, excluding
    case sortedBy
}

// MARK: - Collection Literal Expression

/// Represents an ATL collection literal expression.
///
/// Collection literals create collections with explicit element values,
/// supporting the standard OCL collection types: Sequence, Set, and Bag.
///
/// In ATL, collection literals are expressed using the syntax:
/// - `Sequence{elements}` for ordered collections
/// - `Set{elements}` for unique collections
/// - `Bag{elements}` for multiset collections
///
/// This expression evaluates to the appropriate Swift collection type
/// with the evaluated element values.
public struct ATLCollectionLiteralExpression: ATLExpression, Sendable, Equatable, Hashable {
    /// The type of collection (e.g., "Sequence", "Set", "Bag").
    public let collectionType: String

    /// The expressions for the collection elements.
    public let elements: [any ATLExpression]

    /// Creates a new collection literal expression.
    /// - Parameters:
    ///   - collectionType: The collection type identifier
    ///   - elements: The element expressions
    public init(collectionType: String, elements: [any ATLExpression]) {
        self.collectionType = collectionType
        self.elements = elements
    }

    /// Evaluates the collection literal by creating the appropriate collection type
    /// and evaluating all element expressions.
    @MainActor
    public func evaluate(in context: ATLExecutionContext) async throws -> (any EcoreValue)? {
        // Evaluate all element expressions
        var evaluatedElements: [String] = []
        for elementExpr in elements {
            if let value = try await elementExpr.evaluate(in: context) {
                evaluatedElements.append("\(value)")
            }
        }

        // Create the appropriate collection type
        switch collectionType {
        case "Sequence":
            return evaluatedElements
        case "Set":
            return Array(Set(evaluatedElements))
        case "Bag":
            return evaluatedElements  // Bags allow duplicates like sequences
        default:
            throw ATLExecutionError.unsupportedOperation(
                "Unknown collection type: \(collectionType)")
        }
    }

    /// Equality comparison for collection literal expressions.
    public static func == (lhs: ATLCollectionLiteralExpression, rhs: ATLCollectionLiteralExpression)
        -> Bool
    {
        guard lhs.collectionType == rhs.collectionType && lhs.elements.count == rhs.elements.count
        else {
            return false
        }

        for (leftElement, rightElement) in zip(lhs.elements, rhs.elements) {
            if type(of: leftElement) != type(of: rightElement) {
                return false
            }
        }
        return true
    }

    /// Hash computation for collection literal expressions.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(collectionType)
        hasher.combine(elements.count)
        for element in elements {
            hasher.combine(ObjectIdentifier(type(of: element)))
        }
    }
}

// MARK: - ATL Expression Utilities

/// Safely compares two ATL expressions for equality
internal func areATLExpressionsEqual(_ lhs: any ATLExpression, _ rhs: any ATLExpression) -> Bool {
    // Compare types first
    guard type(of: lhs) == type(of: rhs) else { return false }

    // Use type erasure to compare - all ATLExpression types are Equatable
    switch (lhs, rhs) {
    case (let l as ATLLiteralExpression, let r as ATLLiteralExpression):
        return l == r
    case (let l as ATLVariableExpression, let r as ATLVariableExpression):
        return l == r
    case (let l as ATLNavigationExpression, let r as ATLNavigationExpression):
        return l == r
    case (let l as ATLHelperCallExpression, let r as ATLHelperCallExpression):
        return l == r
    case (let l as ATLBinaryExpression, let r as ATLBinaryExpression):
        return l == r
    case (let l as ATLConditionalExpression, let r as ATLConditionalExpression):
        return l == r
    case (let l as ATLUnaryExpression, let r as ATLUnaryExpression):
        return l == r
    case (let l as ATLMethodCallExpression, let r as ATLMethodCallExpression):
        return l == r
    case (let l as ATLLambdaExpression, let r as ATLLambdaExpression):
        return l == r
    case (let l as ATLOperationExpression, let r as ATLOperationExpression):
        return l == r
    case (let l as ATLCollectionExpression, let r as ATLCollectionExpression):
        return l == r
    case (let l as ATLCollectionLiteralExpression, let r as ATLCollectionLiteralExpression):
        return l == r
    default:
        return false
    }
}

/// Safely hashes an ATL expression
internal func hashATLExpression(_ expression: any ATLExpression, into hasher: inout Hasher) {
    // Hash based on concrete type
    switch expression {
    case let expr as ATLLiteralExpression:
        expr.hash(into: &hasher)
    case let expr as ATLVariableExpression:
        expr.hash(into: &hasher)
    case let expr as ATLNavigationExpression:
        expr.hash(into: &hasher)
    case let expr as ATLHelperCallExpression:
        expr.hash(into: &hasher)
    case let expr as ATLBinaryExpression:
        expr.hash(into: &hasher)
    case let expr as ATLConditionalExpression:
        expr.hash(into: &hasher)
    case let expr as ATLUnaryExpression:
        expr.hash(into: &hasher)
    case let expr as ATLMethodCallExpression:
        expr.hash(into: &hasher)
    case let expr as ATLLambdaExpression:
        expr.hash(into: &hasher)
    case let expr as ATLOperationExpression:
        expr.hash(into: &hasher)
    case let expr as ATLCollectionExpression:
        expr.hash(into: &hasher)
    case let expr as ATLCollectionLiteralExpression:
        expr.hash(into: &hasher)
    default:
        // Fallback to type information
        hasher.combine(String(describing: type(of: expression)))
    }
}
