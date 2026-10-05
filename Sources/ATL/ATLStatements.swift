//
//  ATLStatements.swift
//  ATL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

// MARK: - Expression Statement

/// A statement that evaluates an expression for its effects.
///
/// Expression statements invoke called or lazy rules and helpers from an
/// imperative `do` block. The value of the expression is discarded.
///
/// ## Example Usage
///
/// ```swift
/// let call = ATLExpressionStatement(
///     expression: ATLMethodCallExpression(
///         receiver: ATLVariableExpression(name: "thisModule"),
///         methodName: "CreateItem"
///     )
/// )
/// ```
public struct ATLExpressionStatement: ATLStatement {

    /// The expression to evaluate.
    public let expression: any ATLExpression

    /// The source range the node was parsed from, if it was parsed.
    ///
    /// The origin never takes part in equality or hashing, so nodes that differ only
    /// in where they were written compare equal.
    public let origin: SourceOrigin

    /// Creates an expression statement.
    ///
    /// - Parameters:
    ///   - expression: The expression to evaluate
    ///   - origin: The source range the node was parsed from.
    public init(expression: any ATLExpression, origin: SourceOrigin = .init()) {
        self.expression = expression
        self.origin = origin
    }

    /// Evaluates the expression and discards its value.
    ///
    /// - Parameter context: The execution context
    /// - Throws: Any error raised while evaluating the expression
    @MainActor
    public func execute(in context: ATLExecutionContext) async throws {
        _ = try await expression.evaluate(in: context)
    }
}

// MARK: - Variable Declaration Statement

/// A statement that declares a local variable in the current scope.
///
/// The variable is visible to the remaining statements of the enclosing block
/// and of any nested block. Without an initialising expression the variable
/// starts out undefined.
public struct ATLVariableDeclarationStatement: ATLStatement {

    /// The variable name.
    public let name: String

    /// The declared type, if one was given.
    public let type: String?

    /// The initialising expression, if any.
    public let initialiser: (any ATLExpression)?

    /// The source range the node was parsed from, if it was parsed.
    ///
    /// The origin never takes part in equality or hashing, so nodes that differ only
    /// in where they were written compare equal.
    public let origin: SourceOrigin

    /// Creates a variable declaration.
    ///
    /// - Parameters:
    ///   - name: The variable name
    ///   - type: The declared type, if any
    ///   - initialiser: The initialising expression, if any
    ///   - origin: The source range the node was parsed from.
    public init(name: String, type: String? = nil, initialiser: (any ATLExpression)? = nil, origin: SourceOrigin = .init()) {
        self.name = name
        self.type = type
        self.initialiser = initialiser
        self.origin = origin
    }

    /// Evaluates the initialiser and binds the variable in the current scope.
    ///
    /// - Parameter context: The execution context
    /// - Throws: Any error raised while evaluating the initialiser
    @MainActor
    public func execute(in context: ATLExecutionContext) async throws {
        let value = try await initialiser?.evaluate(in: context)
        context.setVariable(name, value: value)
    }
}

// MARK: - Assignment Statement

/// The left-hand side of an assignment statement.
public enum ATLAssignmentTarget: Sendable {

    /// A previously declared variable.
    case variable(String)

    /// A feature of the object an expression evaluates to.
    case feature(owner: any ATLExpression, name: String)
}

/// A statement that assigns a value to a variable or to a feature of a target element.
///
/// The statement `t.name <- expression;` evaluates the owner expression to a
/// target element and sets its `name` feature. Source elements assigned to
/// reference features are replaced by the target elements they were
/// transformed into, exactly as in target pattern bindings. The statement
/// `v <- expression;` rebinds an existing variable.
public struct ATLAssignmentStatement: ATLStatement {

    /// The assignment target.
    public let target: ATLAssignmentTarget

    /// The expression computing the assigned value.
    public let value: any ATLExpression

    /// The source range the node was parsed from, if it was parsed.
    ///
    /// The origin never takes part in equality or hashing, so nodes that differ only
    /// in where they were written compare equal.
    public let origin: SourceOrigin

    /// Creates an assignment statement.
    ///
    /// - Parameters:
    ///   - target: The variable or feature to assign
    ///   - value: The expression computing the value
    ///   - origin: The source range the node was parsed from.
    public init(target: ATLAssignmentTarget, value: any ATLExpression, origin: SourceOrigin = .init()) {
        self.target = target
        self.value = value
        self.origin = origin
    }

    /// Evaluates the value and performs the assignment.
    ///
    /// - Parameter context: The execution context
    /// - Throws: ``ATLExecutionError`` if the variable is undeclared, the owner is
    ///   not a target element, or the feature does not exist
    @MainActor
    public func execute(in context: ATLExecutionContext) async throws {
        switch target {
        case .variable(let name):
            let newValue = try await value.evaluate(in: context)
            try context.assignVariable(name, value: newValue)
        case .feature(let owner, let name):
            guard let ownerValue = try await owner.evaluate(in: context) else {
                throw ATLExecutionError.runtimeError(
                    "Cannot assign feature '\(name)' of an undefined element")
            }
            guard let ownerObject = ownerValue as? (any EObject) else {
                throw ATLExecutionError.typeError(
                    "Cannot assign feature '\(name)' of a value that is not a model element")
            }
            let newValue = try await value.evaluate(in: context)
            try await context.assignFeature(on: ownerObject, feature: name, value: newValue)
        }
    }
}

// MARK: - Conditional Statement

/// A statement that executes one of two blocks depending on a condition.
///
/// A condition that evaluates to anything other than `true` selects the
/// `else` block.
public struct ATLConditionalStatement: ATLStatement {

    /// The boolean condition.
    public let condition: any ATLExpression

    /// The statements executed when the condition holds.
    public let thenStatements: [any ATLStatement]

    /// The statements executed otherwise.
    public let elseStatements: [any ATLStatement]

    /// The source range the node was parsed from, if it was parsed.
    ///
    /// The origin never takes part in equality or hashing, so nodes that differ only
    /// in where they were written compare equal.
    public let origin: SourceOrigin

    /// Creates a conditional statement.
    ///
    /// - Parameters:
    ///   - condition: The boolean condition
    ///   - thenStatements: The statements for a true condition
    ///   - elseStatements: The statements for any other outcome
    ///   - origin: The source range the node was parsed from.
    public init(
        condition: any ATLExpression,
        thenStatements: [any ATLStatement],
        elseStatements: [any ATLStatement] = [],
        origin: SourceOrigin = .init()
    ) {
        self.condition = condition
        self.thenStatements = thenStatements
        self.elseStatements = elseStatements
        self.origin = origin
    }

    /// Evaluates the condition and executes the selected block.
    ///
    /// - Parameter context: The execution context
    /// - Throws: Any error raised by the condition or the executed statements
    @MainActor
    public func execute(in context: ATLExecutionContext) async throws {
        let outcome = try await condition.evaluate(in: context) as? Bool ?? false
        for statement in outcome ? thenStatements : elseStatements {
            try await statement.execute(in: context)
        }
    }
}

// MARK: - For Statement

/// A statement that executes a block once for each element of a collection.
///
/// The loop variable is visible in the body only. An undefined collection
/// yields no iterations and a value that is not a collection is treated as a
/// collection of one element.
public struct ATLForStatement: ATLStatement {

    /// The name of the loop variable.
    public let variable: String

    /// The expression yielding the collection to iterate.
    public let collection: any ATLExpression

    /// The statements executed for each element.
    public let body: [any ATLStatement]

    /// The source range the node was parsed from, if it was parsed.
    ///
    /// The origin never takes part in equality or hashing, so nodes that differ only
    /// in where they were written compare equal.
    public let origin: SourceOrigin

    /// Creates a for statement.
    ///
    /// - Parameters:
    ///   - variable: The loop variable name
    ///   - collection: The expression yielding the collection
    ///   - body: The statements executed per element
    ///   - origin: The source range the node was parsed from.
    public init(variable: String, collection: any ATLExpression, body: [any ATLStatement], origin: SourceOrigin = .init()) {
        self.variable = variable
        self.collection = collection
        self.body = body
        self.origin = origin
    }

    /// Iterates the collection and executes the body for each element.
    ///
    /// - Parameter context: The execution context
    /// - Throws: Any error raised by the collection expression or the body
    @MainActor
    public func execute(in context: ATLExecutionContext) async throws {
        let elements = ATLCollectionValues.elements(of: try await collection.evaluate(in: context))
        context.pushScope()
        defer { context.popScope() }
        for element in elements {
            context.setVariable(variable, value: element)
            for statement in body {
                try await statement.execute(in: context)
            }
        }
    }
}

// MARK: - Collection Values

/// Helpers for treating evaluated values uniformly as collections.
enum ATLCollectionValues {

    /// Returns the elements of a value viewed as a collection.
    ///
    /// Arrays yield their elements, an undefined value yields none, and any
    /// other value yields itself as the only element.
    ///
    /// - Parameter value: The evaluated value
    /// - Returns: The elements of the value
    static func elements(of value: (any EcoreValue)?) -> [any EcoreValue] {
        guard let value else { return [] }
        if let array = value as? EcoreValueArray { return array.values }
        if let anyArray = value as? [Any] {
            return anyArray.compactMap { $0 as? (any EcoreValue) }
        }
        return [value]
    }
}
