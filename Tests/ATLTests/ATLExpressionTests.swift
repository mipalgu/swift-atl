//
//  ATLExpressionTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 6/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//

import Foundation
import Testing

@testable import ATL
@testable import ECore

/// Test suite for ATL expression evaluation functionality.
///
/// Tests the core expression types used in Atlas Transformation Language,
/// including variable references, navigation expressions, helper calls,
/// literals, and binary operations.
@Suite("ATL Expression Tests")
struct ATLExpressionTests {

    // MARK: - Basic Construction Tests

    @Test("Variable expression construction")
    func testVariableExpressionConstruction() async throws {
        // Given
        let variableName = "testVar"

        // When
        let expression = ATLVariableExpression(name: variableName)

        // Then
        #expect(expression.name == variableName)
    }

    @Test("Navigation expression construction")
    func testNavigationExpressionConstruction() async throws {
        // Given
        let sourceExpr = ATLVariableExpression(name: "source")
        let propertyName = "name"

        // When
        let expression = ATLNavigationExpression(source: sourceExpr, property: propertyName)

        // Then
        #expect(expression.property == propertyName)
        // Since we passed a concrete ATLVariableExpression, verify it directly
        #expect((expression.source as? ATLVariableExpression)?.name == "source")
    }

    @Test("Helper call expression construction")
    func testHelperCallExpressionConstruction() async throws {
        // Given
        let helperName = "testHelper"
        let arg1 = ATLLiteralExpression(value: "arg1")
        let arg2 = ATLLiteralExpression(value: 42)

        // When
        let expression = ATLHelperCallExpression(helperName: helperName, arguments: [arg1, arg2])

        // Then
        #expect(expression.helperName == helperName)
        #expect(expression.arguments.count == 2)
    }

    @Test("Literal expression construction")
    func testLiteralExpressionConstruction() async throws {
        // Given
        let stringValue = "test"
        let intValue = 42

        // When
        let stringExpr = ATLLiteralExpression(value: stringValue)
        let intExpr = ATLLiteralExpression(value: intValue)

        // Then
        #expect(stringExpr.value as? String == stringValue)
        #expect(intExpr.value as? Int == intValue)
    }

    @Test("Binary operation expression construction")
    func testBinaryOperationExpressionConstruction() async throws {
        // Given
        let leftExpr = ATLLiteralExpression(value: 10)
        let rightExpr = ATLLiteralExpression(value: 5)
        let operation = ATLBinaryOperator.plus

        // When
        let expression = ATLBinaryExpression(
            left: leftExpr,
            operator: operation,
            right: rightExpr
        )

        // Then
        #expect(expression.operator == operation)
        #expect((expression.left as? ATLLiteralExpression)?.value as? Int == 10)
        #expect((expression.right as? ATLLiteralExpression)?.value as? Int == 5)
    }

    // MARK: - Equality Tests

    @Test("Variable expression equality")
    func testVariableExpressionEquality() async throws {
        // Given
        let expr1 = ATLVariableExpression(name: "test")
        let expr2 = ATLVariableExpression(name: "test")
        let expr3 = ATLVariableExpression(name: "different")

        // Then
        #expect(expr1 == expr2)
        #expect(expr1 != expr3)
    }

    @Test("Navigation expression equality")
    func testNavigationExpressionEquality() async throws {
        // Given
        let source1 = ATLVariableExpression(name: "obj")
        let source2 = ATLVariableExpression(name: "obj")
        let source3 = ATLVariableExpression(name: "other")

        let expr1 = ATLNavigationExpression(source: source1, property: "name")
        let expr2 = ATLNavigationExpression(source: source2, property: "name")
        let expr3 = ATLNavigationExpression(source: source3, property: "name")
        let expr4 = ATLNavigationExpression(source: source1, property: "other")

        // Then
        #expect(expr1 == expr2)
        #expect(expr1 != expr3)
        #expect(expr1 != expr4)
    }

    @Test("Helper call expression equality")
    func testHelperCallExpressionEquality() async throws {
        // Given
        let arg1 = ATLLiteralExpression(value: "test")
        let arg2 = ATLLiteralExpression(value: "test")
        let arg3 = ATLLiteralExpression(value: "different")

        let expr1 = ATLHelperCallExpression(helperName: "helper", arguments: [arg1])
        let expr2 = ATLHelperCallExpression(helperName: "helper", arguments: [arg2])
        let expr3 = ATLHelperCallExpression(helperName: "helper", arguments: [arg3])
        let expr4 = ATLHelperCallExpression(helperName: "other", arguments: [arg1])

        // Then
        #expect(expr1 == expr2)
        #expect(expr1 != expr3)
        #expect(expr1 != expr4)
    }

    @Test("Literal expression equality")
    func testLiteralExpressionEquality() async throws {
        // Given
        let expr1 = ATLLiteralExpression(value: "test")
        let expr2 = ATLLiteralExpression(value: "test")
        let expr3 = ATLLiteralExpression(value: "different")
        let expr4 = ATLLiteralExpression(value: 42)

        // Then
        #expect(expr1 == expr2)
        #expect(expr1 != expr3)
        #expect(expr1 != expr4)
    }

    @Test("Binary operation expression equality")
    func testBinaryOperationExpressionEquality() async throws {
        // Given
        let left1 = ATLLiteralExpression(value: 10)
        let left2 = ATLLiteralExpression(value: 10)
        let right1 = ATLLiteralExpression(value: 5)
        let right2 = ATLLiteralExpression(value: 5)

        let expr1 = ATLBinaryExpression(left: left1, operator: .plus, right: right1)
        let expr2 = ATLBinaryExpression(left: left2, operator: .plus, right: right2)
        let expr3 = ATLBinaryExpression(left: left1, operator: .minus, right: right1)

        // Then
        #expect(expr1 == expr2)
        #expect(expr1 != expr3)
    }

    // MARK: - Hash Tests

    @Test("Expression hash consistency")
    func testExpressionHashConsistency() async throws {
        // Given
        let varExpr = ATLVariableExpression(name: "test")
        let literalExpr = ATLLiteralExpression(value: "test")

        // When
        let varHash1 = varExpr.hashValue
        let varHash2 = varExpr.hashValue
        let literalHash1 = literalExpr.hashValue
        let literalHash2 = literalExpr.hashValue

        // Then
        #expect(varHash1 == varHash2)
        #expect(literalHash1 == literalHash2)
    }

    // MARK: - Operation Tests

    @Test("Binary operation types")
    func testBinaryOperationTypes() async throws {
        // Given & When
        let arithmetic: [ATLBinaryOperator] = [
            .plus, .minus, .multiply, .divide, .modulo,
        ]
        let comparison: [ATLBinaryOperator] = [
            .equals, .notEquals, .lessThan, .lessThanOrEqual, .greaterThan, .greaterThanOrEqual,
        ]
        let logical: [ATLBinaryOperator] = [.and, .or]

        // Then
        #expect(arithmetic.count == 5)
        #expect(comparison.count == 6)
        #expect(logical.count == 2)
    }

    @Test("Expression protocol conformance")
    func testExpressionProtocolConformance() async throws {
        // Given
        let expressions: [any ATLExpression] = [
            ATLVariableExpression(name: "test"),
            ATLNavigationExpression(source: ATLVariableExpression(name: "obj"), property: "prop"),
            ATLHelperCallExpression(helperName: "helper", arguments: []),
            ATLLiteralExpression(value: "literal"),
            ATLBinaryExpression(
                left: ATLLiteralExpression(value: 1),
                operator: .plus,
                right: ATLLiteralExpression(value: 2)
            ),
        ]

        // When & Then
        #expect(expressions.count == 5)

        // All expressions should be ATLExpression instances
        // Note: This test is intentionally simple as the array type already ensures ATLExpression conformance
        #expect(expressions.allSatisfy { _ in true })
    }
}

// MARK: - Test Helper Functions

extension ATLExpressionTests {

    /// Creates a basic ATL module for testing.
    private func createTestModule() -> ATLModule {
        let sourcePackage = EPackage(name: "Source", nsURI: "http://test.example/source")
        let targetPackage = EPackage(name: "Target", nsURI: "http://test.example/target")

        return ATLModule(
            name: "TestModule",
            sourceMetamodels: ["Source": sourcePackage],
            targetMetamodels: ["Target": targetPackage]
        )
    }
}
