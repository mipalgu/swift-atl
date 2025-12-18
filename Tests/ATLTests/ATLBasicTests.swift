//
//  ATLBasicTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 6/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation
import Testing

@testable import ATL
@testable import ECore
@testable import EMFBase

/// Basic test suite for ATL components without async operations.
///
/// Tests basic construction and equality of ATL components to verify
/// compilation without complex async operations that might cause hanging.
@Suite("ATL Basic Tests")
struct ATLBasicTests {

    // MARK: - Expression Construction Tests

    @Test("Variable expression construction")
    func testVariableExpressionConstruction() {
        // Given
        let variableName = "testVar"

        // When
        let expression = ATLVariableExpression(name: variableName)

        // Then
        #expect(expression.name == variableName)
    }

    @Test("Literal expression construction")
    func testLiteralExpressionConstruction() {
        // Given
        let stringValue = "test"
        let intValue = 42
        let boolValue = true
        let nilValue: (any EcoreValue)? = nil

        // When
        let stringExpr = ATLLiteralExpression(value: stringValue)
        let intExpr = ATLLiteralExpression(value: intValue)
        let boolExpr = ATLLiteralExpression(value: boolValue)
        let nilExpr = ATLLiteralExpression(value: nilValue)

        // Then
        #expect(stringExpr.value as? String == stringValue)
        #expect(intExpr.value as? Int == intValue)
        #expect(boolExpr.value as? Bool == boolValue)
        #expect(nilExpr.value == nil)
    }

    @Test("Binary operation expression construction")
    func testBinaryOperationExpressionConstruction() {
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
    }

    // MARK: - Module Construction Tests

    @Test("Module construction")
    func testModuleConstruction() {
        // Given
        let moduleName = "TestModule"
        let sourcePackage = EPackage(name: "Source", nsURI: "http://test.example/source")
        let targetPackage = EPackage(name: "Target", nsURI: "http://test.example/target")

        // When
        let module = ATLModule(
            name: moduleName,
            sourceMetamodels: ["Source": sourcePackage],
            targetMetamodels: ["Target": targetPackage]
        )

        // Then
        #expect(module.name == moduleName)
        #expect(module.sourceMetamodels.count == 1)
        #expect(module.targetMetamodels.count == 1)
        #expect(module.helpers.isEmpty)
        #expect(module.matchedRules.isEmpty)
        #expect(module.calledRules.isEmpty)
    }

    @Test("Helper construction")
    func testHelperConstruction() {
        // Given
        let helperName = "testHelper"
        let returnType = "String"
        let body = ATLLiteralExpression(value: "test")

        // When
        let helper = ATLHelper(
            name: helperName,
            returnType: returnType,
            body: body
        )

        // Then
        #expect(helper.name == helperName)
        #expect(helper.returnType == returnType)
        #expect(helper.parameters.isEmpty)
    }

    @Test("Parameter construction")
    func testParameterConstruction() {
        // Given
        let paramName = "testParam"
        let paramType = "String"

        // When
        let parameter = ATLParameter(name: paramName, type: paramType)

        // Then
        #expect(parameter.name == paramName)
        #expect(parameter.type == paramType)
    }

    // MARK: - Equality Tests

    @Test("Expression equality")
    func testExpressionEquality() {
        // Given
        let expr1 = ATLVariableExpression(name: "test")
        let expr2 = ATLVariableExpression(name: "test")
        let expr3 = ATLVariableExpression(name: "different")

        // Then
        #expect(expr1 == expr2)
        #expect(expr1 != expr3)
    }

    @Test("Literal expression equality")
    func testLiteralExpressionEquality() {
        // Given
        let expr1 = ATLLiteralExpression(value: "test")
        let expr2 = ATLLiteralExpression(value: "test")
        let expr3 = ATLLiteralExpression(value: "different")

        // Then
        #expect(expr1 == expr2)
        #expect(expr1 != expr3)
    }

    @Test("Parameter equality")
    func testParameterEquality() {
        // Given
        let param1 = ATLParameter(name: "test", type: "String")
        let param2 = ATLParameter(name: "test", type: "String")
        let param3 = ATLParameter(name: "different", type: "String")

        // Then
        #expect(param1 == param2)
        #expect(param1 != param3)
    }

    // MARK: - Hash Consistency Tests

    @Test("Hash consistency")
    func testHashConsistency() {
        // Given
        let varExpr = ATLVariableExpression(name: "test")
        let literalExpr = ATLLiteralExpression(value: "test")
        let param = ATLParameter(name: "param", type: "String")

        // When
        let varHash1 = varExpr.hashValue
        let varHash2 = varExpr.hashValue
        let literalHash1 = literalExpr.hashValue
        let literalHash2 = literalExpr.hashValue
        let paramHash1 = param.hashValue
        let paramHash2 = param.hashValue

        // Then
        #expect(varHash1 == varHash2)
        #expect(literalHash1 == literalHash2)
        #expect(paramHash1 == paramHash2)
    }

    // MARK: - Operator Tests

    @Test("Binary operators availability")
    func testBinaryOperators() {
        // Given & When
        let allOperators = ATLBinaryOperator.allCases

        // Then
        #expect(allOperators.contains(.plus))
        #expect(allOperators.contains(.minus))
        #expect(allOperators.contains(.multiply))
        #expect(allOperators.contains(.divide))
        #expect(allOperators.contains(.equals))
        #expect(allOperators.contains(.notEquals))
        #expect(allOperators.contains(.and))
        #expect(allOperators.contains(.or))
    }

    @Test("Operator string values")
    func testOperatorStringValues() {
        // Then
        #expect(ATLBinaryOperator.plus.rawValue == "+")
        #expect(ATLBinaryOperator.minus.rawValue == "-")
        #expect(ATLBinaryOperator.multiply.rawValue == "*")
        #expect(ATLBinaryOperator.divide.rawValue == "/")
        #expect(ATLBinaryOperator.equals.rawValue == "=")
        #expect(ATLBinaryOperator.notEquals.rawValue == "<>")
        #expect(ATLBinaryOperator.and.rawValue == "and")
        #expect(ATLBinaryOperator.or.rawValue == "or")
    }
}
