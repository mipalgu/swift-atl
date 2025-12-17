//
//  ATLExpressionRoundTripTests.swift
//  ATL
//
//  Created by Claude on 10/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
//  Tests round-trip serialization/parsing of ATL/OCL expressions.
//
import Foundation
import Testing
@testable import ATL

/// Tests for ATL expression XMI round-trip (serialize → parse → verify).
///
/// These tests verify that all expression types can be serialized to Eclipse ATL XMI
/// format and then parsed back to equivalent expression trees.
@Suite("ATL Expression Round-Trip Tests")
struct ATLExpressionRoundTripTests {

    let serializer = ATLExpressionXMISerializer()
    let parser = ATLExpressionXMIParser()

    // MARK: - Literal Expression Tests

    @Test("Integer literal round-trip")
    func integerLiteralRoundTrip() throws {
        // Given: An integer literal
        let original = ATLLiteralExpression(value: 42)

        // When: Serialize to XMI and parse back
        let xmi = serializer.serialize(original)
        let parsed = try parser.parse(wrapExpression(xmi))

        // Then: Should be equivalent
        guard let parsedLiteral = parsed as? ATLLiteralExpression,
              let value = parsedLiteral.value as? Int else {
            Issue.record("Parsed expression should be integer literal")
            return
        }
        #expect(value == 42)
    }

    @Test("Real literal round-trip")
    func realLiteralRoundTrip() throws {
        // Given: A real literal
        let original = ATLLiteralExpression(value: 3.14159)

        // When: Serialize to XMI and parse back
        let xmi = serializer.serialize(original)
        let parsed = try parser.parse(wrapExpression(xmi))

        // Then: Should be equivalent
        guard let parsedLiteral = parsed as? ATLLiteralExpression,
              let value = parsedLiteral.value as? Double else {
            Issue.record("Parsed expression should be real literal")
            return
        }
        #expect(abs(value - 3.14159) < 0.00001)
    }

    @Test("String literal round-trip")
    func stringLiteralRoundTrip() throws {
        // Given: A string literal
        let original = ATLLiteralExpression(value: "Hello, World!")

        // When: Serialize to XMI and parse back
        let xmi = serializer.serialize(original)
        let parsed = try parser.parse(wrapExpression(xmi))

        // Then: Should be equivalent
        guard let parsedLiteral = parsed as? ATLLiteralExpression,
              let value = parsedLiteral.value as? String else {
            Issue.record("Parsed expression should be string literal")
            return
        }
        #expect(value == "Hello, World!")
    }

    @Test("Boolean literal round-trip")
    func booleanLiteralRoundTrip() throws {
        // Given: A boolean literal
        let original = ATLLiteralExpression(value: true)

        // When: Serialize to XMI and parse back
        let xmi = serializer.serialize(original)
        let parsed = try parser.parse(wrapExpression(xmi))

        // Then: Should be equivalent
        guard let parsedLiteral = parsed as? ATLLiteralExpression,
              let value = parsedLiteral.value as? Bool else {
            Issue.record("Parsed expression should be boolean literal")
            return
        }
        #expect(value == true)
    }

    @Test("Undefined literal round-trip")
    func undefinedLiteralRoundTrip() throws {
        // Given: An undefined literal
        let original = ATLLiteralExpression(value: nil)

        // When: Serialize to XMI and parse back
        let xmi = serializer.serialize(original)
        let parsed = try parser.parse(wrapExpression(xmi))

        // Then: Should be equivalent
        guard let parsedLiteral = parsed as? ATLLiteralExpression else {
            Issue.record("Parsed expression should be literal")
            return
        }
        #expect(parsedLiteral.value == nil)
    }

    @Test("Type literal round-trip")
    func typeLiteralRoundTrip() throws {
        // Given: A type literal
        let original = ATLTypeLiteralExpression(typeName: "String")

        // When: Serialize to XMI and parse back
        let xmi = serializer.serialize(original)
        let parsed = try parser.parse(wrapExpression(xmi))

        // Then: Should be equivalent
        guard let parsedType = parsed as? ATLTypeLiteralExpression else {
            Issue.record("Parsed expression should be type literal")
            return
        }
        #expect(parsedType.typeName == "String")
    }

    // MARK: - Variable Expression Tests

    @Test("Variable round-trip")
    func variableRoundTrip() throws {
        // Given: A variable reference
        let original = ATLVariableExpression(name: "sourceElement")

        // When: Serialize to XMI and parse back
        let xmi = serializer.serialize(original)
        let parsed = try parser.parse(wrapExpression(xmi))

        // Then: Should be equivalent
        guard let parsedVar = parsed as? ATLVariableExpression else {
            Issue.record("Parsed expression should be variable")
            return
        }
        #expect(parsedVar.name == "sourceElement")
    }

    // MARK: - Binary Operation Tests

    @Test("Binary operation round-trip")
    func binaryOperationRoundTrip() throws {
        // Given: A binary operation (x + 10)
        let left = ATLVariableExpression(name: "x")
        let right = ATLLiteralExpression(value: 10)
        let original = ATLBinaryExpression(
            left: left,
            operator: .plus,
            right: right
        )

        // When: Serialize to XMI and parse back
        let xmi = serializer.serialize(original)
        let parsed = try parser.parse(wrapExpression(xmi))

        // Then: Should be equivalent
        guard let parsedBinary = parsed as? ATLBinaryExpression else {
            Issue.record("Parsed expression should be binary operation")
            return
        }
        #expect(parsedBinary.operator == .plus)

        guard let parsedLeft = parsedBinary.left as? ATLVariableExpression else {
            Issue.record("Left operand should be variable")
            return
        }
        #expect(parsedLeft.name == "x")

        guard let parsedRight = parsedBinary.right as? ATLLiteralExpression,
              let rightValue = parsedRight.value as? Int else {
            Issue.record("Right operand should be integer literal")
            return
        }
        #expect(rightValue == 10)
    }

    @Test("Comparison operation round-trip")
    func comparisonOperationRoundTrip() throws {
        // Given: A comparison (age >= 18)
        let left = ATLVariableExpression(name: "age")
        let right = ATLLiteralExpression(value: 18)
        let original = ATLBinaryExpression(
            left: left,
            operator: .greaterThanOrEqual,
            right: right
        )

        // When: Serialize to XMI and parse back
        let xmi = serializer.serialize(original)
        let parsed = try parser.parse(wrapExpression(xmi))

        // Then: Should be equivalent
        guard let parsedBinary = parsed as? ATLBinaryExpression else {
            Issue.record("Parsed expression should be binary operation")
            return
        }
        #expect(parsedBinary.operator == .greaterThanOrEqual)
    }

    // MARK: - Unary Operation Tests

    @Test("Unary operation round-trip")
    func unaryOperationRoundTrip() throws {
        // Given: A unary operation (not x)
        let operand = ATLVariableExpression(name: "x")
        let original = ATLUnaryExpression(
            operator: .not,
            operand: operand
        )

        // When: Serialize to XMI and parse back
        let xmi = serializer.serialize(original)
        let parsed = try parser.parse(wrapExpression(xmi))

        // Then: Should be equivalent
        guard let parsedUnary = parsed as? ATLUnaryExpression else {
            Issue.record("Parsed expression should be unary operation")
            return
        }
        #expect(parsedUnary.operator == .not)

        guard let parsedOperand = parsedUnary.operand as? ATLVariableExpression else {
            Issue.record("Operand should be variable")
            return
        }
        #expect(parsedOperand.name == "x")
    }

    // MARK: - Navigation Expression Tests

    @Test("Navigation round-trip")
    func navigationRoundTrip() throws {
        // Given: A navigation expression (person.name)
        let source = ATLVariableExpression(name: "person")
        let original = ATLNavigationExpression(source: source, property: "name")

        // When: Serialize to XMI and parse back
        let xmi = serializer.serialize(original)
        let parsed = try parser.parse(wrapExpression(xmi))

        // Then: Should be equivalent
        guard let parsedNav = parsed as? ATLNavigationExpression else {
            Issue.record("Parsed expression should be navigation")
            return
        }
        #expect(parsedNav.property == "name")

        guard let parsedSource = parsedNav.source as? ATLVariableExpression else {
            Issue.record("Source should be variable")
            return
        }
        #expect(parsedSource.name == "person")
    }

    // MARK: - Method Call Tests

    @Test("Method call round-trip")
    func methodCallRoundTrip() throws {
        // Given: A method call (str.concat('!'))
        let receiver = ATLVariableExpression(name: "str")
        let arg = ATLLiteralExpression(value: "!")
        let original = ATLMethodCallExpression(
            receiver: receiver,
            methodName: "concat",
            arguments: [arg]
        )

        // When: Serialize to XMI and parse back
        let xmi = serializer.serialize(original)
        let parsed = try parser.parse(wrapExpression(xmi))

        // Then: Should be equivalent
        guard let parsedCall = parsed as? ATLMethodCallExpression else {
            Issue.record("Parsed expression should be method call")
            return
        }
        #expect(parsedCall.methodName == "concat")
        #expect(parsedCall.arguments.count == 1)

        guard let parsedReceiver = parsedCall.receiver as? ATLVariableExpression else {
            Issue.record("Receiver should be variable")
            return
        }
        #expect(parsedReceiver.name == "str")

        guard let parsedArg = parsedCall.arguments[0] as? ATLLiteralExpression,
              let argValue = parsedArg.value as? String else {
            Issue.record("Argument should be string literal")
            return
        }
        #expect(argValue == "!")
    }

    // MARK: - Conditional Expression Tests

    @Test("Conditional round-trip")
    func conditionalRoundTrip() throws {
        // Given: A conditional (if x > 0 then 1 else -1)
        let condition = ATLBinaryExpression(
            left: ATLVariableExpression(name: "x"),
            operator: .greaterThan,
            right: ATLLiteralExpression(value: 0)
        )
        let thenBranch = ATLLiteralExpression(value: 1)
        let elseBranch = ATLLiteralExpression(value: -1)
        let original = ATLConditionalExpression(
            condition: condition,
            thenExpression: thenBranch,
            elseExpression: elseBranch
        )

        // When: Serialize to XMI and parse back
        let xmi = serializer.serialize(original)
        let parsed = try parser.parse(wrapExpression(xmi))

        // Then: Should be equivalent
        guard let parsedCond = parsed as? ATLConditionalExpression else {
            Issue.record("Parsed expression should be conditional, got \(type(of: parsed))")
            return
        }

        // Verify condition
        guard let parsedCondition = parsedCond.condition as? ATLBinaryExpression else {
            Issue.record("Condition should be binary operation")
            return
        }
        #expect(parsedCondition.operator == .greaterThan)

        // Verify then branch
        guard let parsedThen = parsedCond.thenExpression as? ATLLiteralExpression,
              let thenValue = parsedThen.value as? Int else {
            Issue.record("Then branch should be integer literal")
            return
        }
        #expect(thenValue == 1)

        // Verify else branch
        guard let parsedElse = parsedCond.elseExpression as? ATLLiteralExpression,
              let elseValue = parsedElse.value as? Int else {
            Issue.record("Else branch should be integer literal")
            return
        }
        #expect(elseValue == -1)
    }

    // MARK: - Collection Literal Tests

    @Test("Collection literal round-trip")
    func collectionLiteralRoundTrip() throws {
        // Given: A collection literal Sequence{1, 2, 3}
        let elements = [
            ATLLiteralExpression(value: 1),
            ATLLiteralExpression(value: 2),
            ATLLiteralExpression(value: 3)
        ]
        let original = ATLCollectionLiteralExpression(
            collectionType: "Sequence",
            elements: elements
        )

        // When: Serialize to XMI and parse back
        let xmi = serializer.serialize(original)
        let parsed = try parser.parse(wrapExpression(xmi))

        // Then: Should be equivalent
        guard let parsedColl = parsed as? ATLCollectionLiteralExpression else {
            Issue.record("Parsed expression should be collection literal")
            return
        }
        #expect(parsedColl.collectionType == "Sequence")
        #expect(parsedColl.elements.count == 3)

        for (index, element) in parsedColl.elements.enumerated() {
            guard let literal = element as? ATLLiteralExpression,
                  let value = literal.value as? Int else {
                Issue.record("Element \(index) should be integer literal")
                return
            }
            #expect(value == index + 1)
        }
    }

    // MARK: - Collection Expression Tests

    @Test("Collection select round-trip")
    func collectionSelectRoundTrip() throws {
        // Given: A select operation (list->select(e | e > 5))
        let source = ATLVariableExpression(name: "list")
        let body = ATLBinaryExpression(
            left: ATLVariableExpression(name: "e"),
            operator: .greaterThan,
            right: ATLLiteralExpression(value: 5)
        )
        let original = ATLCollectionExpression(
            source: source,
            operation: .select,
            iterator: "e",
            body: body
        )

        // When: Serialize to XMI and parse back
        let xmi = serializer.serialize(original)
        print("=== Collection Select XMI ===")
        print(wrapExpression(xmi))
        print("=== End XMI ===")
        let parsed = try parser.parse(wrapExpression(xmi))
        print("Parsed type: \(type(of: parsed))")

        // Then: Should be equivalent
        guard let parsedColl = parsed as? ATLCollectionExpression else {
            Issue.record("Parsed expression should be collection expression")
            return
        }
        #expect(parsedColl.operation == .select)
        #expect(parsedColl.iterator == "e")

        guard let parsedSource = parsedColl.source as? ATLVariableExpression else {
            Issue.record("Source should be variable")
            return
        }
        #expect(parsedSource.name == "list")

        guard let parsedBody = parsedColl.body as? ATLBinaryExpression else {
            Issue.record("Body should be binary operation")
            return
        }
        #expect(parsedBody.operator == .greaterThan)
    }

    // MARK: - Let Expression Tests

    @Test("Let expression round-trip")
    func letExpressionRoundTrip() throws {
        // Given: A let expression (let x : Integer = 42 in x + 1)
        let initExpr = ATLLiteralExpression(value: 42)
        let inExpr = ATLBinaryExpression(
            left: ATLVariableExpression(name: "x"),
            operator: .plus,
            right: ATLLiteralExpression(value: 1)
        )
        let original = ATLLetExpression(
            variableName: "x",
            variableType: "Integer",
            initExpression: initExpr,
            inExpression: inExpr
        )

        // When: Serialize to XMI and parse back
        let xmi = serializer.serialize(original)
        let parsed = try parser.parse(wrapExpression(xmi))

        // Then: Should be equivalent
        guard let parsedLet = parsed as? ATLLetExpression else {
            Issue.record("Parsed expression should be let expression")
            return
        }
        #expect(parsedLet.variableName == "x")
        #expect(parsedLet.variableType == "Integer")

        guard let parsedInit = parsedLet.initExpression as? ATLLiteralExpression,
              let initValue = parsedInit.value as? Int else {
            Issue.record("Init expression should be integer literal")
            return
        }
        #expect(initValue == 42)

        guard let parsedIn = parsedLet.inExpression as? ATLBinaryExpression else {
            Issue.record("In expression should be binary operation")
            return
        }
        #expect(parsedIn.operator == .plus)
    }

    // MARK: - Lambda Expression Tests

    @Test("Lambda expression round-trip")
    func lambdaExpressionRoundTrip() throws {
        // Given: A lambda expression (e | e * 2)
        let body = ATLBinaryExpression(
            left: ATLVariableExpression(name: "e"),
            operator: .multiply,
            right: ATLLiteralExpression(value: 2)
        )
        let original = ATLLambdaExpression(parameter: "e", body: body)

        // When: Serialize to XMI and parse back
        let xmi = serializer.serialize(original)
        let parsed = try parser.parse(wrapExpression(xmi))

        // Then: Should be equivalent
        guard let parsedLambda = parsed as? ATLLambdaExpression else {
            Issue.record("Parsed expression should be lambda expression")
            return
        }
        #expect(parsedLambda.parameter == "e")

        guard let parsedBody = parsedLambda.body as? ATLBinaryExpression else {
            Issue.record("Body should be binary operation")
            return
        }
        #expect(parsedBody.operator == .multiply)
    }

    // MARK: - Iterate Expression Tests

    @Test("Iterate expression round-trip")
    func iterateExpressionRoundTrip() throws {
        // Given: An iterate expression (list->iterate(e; acc : Integer = 0 | acc + e))
        let source = ATLVariableExpression(name: "list")
        let defaultValue = ATLLiteralExpression(value: 0)
        let body = ATLBinaryExpression(
            left: ATLVariableExpression(name: "acc"),
            operator: .plus,
            right: ATLVariableExpression(name: "e")
        )
        let original = ATLIterateExpression(
            source: source,
            parameter: "e",
            accumulator: "acc",
            accumulatorType: "Integer",
            defaultValue: defaultValue,
            body: body
        )

        // When: Serialize to XMI and parse back
        let xmi = serializer.serialize(original)
        let parsed = try parser.parse(wrapExpression(xmi))

        // Then: Should be equivalent
        guard let parsedIterate = parsed as? ATLIterateExpression else {
            Issue.record("Parsed expression should be iterate expression")
            return
        }
        #expect(parsedIterate.parameter == "e")
        #expect(parsedIterate.accumulator == "acc")

        guard let parsedSource = parsedIterate.source as? ATLVariableExpression else {
            Issue.record("Source should be variable")
            return
        }
        #expect(parsedSource.name == "list")

        guard let parsedDefault = parsedIterate.defaultValue as? ATLLiteralExpression,
              let defaultVal = parsedDefault.value as? Int else {
            Issue.record("Default value should be integer literal")
            return
        }
        #expect(defaultVal == 0)

        guard let parsedBody = parsedIterate.body as? ATLBinaryExpression else {
            Issue.record("Body should be binary operation")
            return
        }
        #expect(parsedBody.operator == .plus)
    }

    // MARK: - Tuple Expression Tests

    @Test("Tuple expression round-trip")
    func tupleExpressionRoundTrip() throws {
        // Given: A tuple expression Tuple{name='John', age=30}
        let nameField = (name: "name", type: Optional("String"), value: ATLLiteralExpression(value: "John") as any ATLExpression)
        let ageField = (name: "age", type: Optional("Integer"), value: ATLLiteralExpression(value: 30) as any ATLExpression)
        let original = ATLTupleExpression(fields: [nameField, ageField])

        // When: Serialize to XMI and parse back
        let xmi = serializer.serialize(original)
        let parsed = try parser.parse(wrapExpression(xmi))

        // Then: Should be equivalent
        guard let parsedTuple = parsed as? ATLTupleExpression else {
            Issue.record("Parsed expression should be tuple expression")
            return
        }
        #expect(parsedTuple.fields.count == 2)

        // Verify name field
        let parsedName = parsedTuple.fields[0]
        #expect(parsedName.name == "name")
        #expect(parsedName.type == "String")
        guard let nameValue = parsedName.value as? ATLLiteralExpression,
              let nameStr = nameValue.value as? String else {
            Issue.record("Name value should be string literal")
            return
        }
        #expect(nameStr == "John")

        // Verify age field
        let parsedAge = parsedTuple.fields[1]
        #expect(parsedAge.name == "age")
        #expect(parsedAge.type == "Integer")
        guard let ageValue = parsedAge.value as? ATLLiteralExpression,
              let ageInt = ageValue.value as? Int else {
            Issue.record("Age value should be integer literal")
            return
        }
        #expect(ageInt == 30)
    }

    // MARK: - Helper Call Tests

    @Test("Helper call round-trip")
    func helperCallRoundTrip() throws {
        // Given: A helper call (myHelper(arg1, arg2))
        let arg1 = ATLLiteralExpression(value: 42)
        let arg2 = ATLVariableExpression(name: "x")
        let original = ATLHelperCallExpression(
            helperName: "myHelper",
            arguments: [arg1, arg2]
        )

        // When: Serialize to XMI and parse back
        let xmi = serializer.serialize(original)
        print("=== Helper Call XMI ===")
        print(wrapExpression(xmi))
        print("=== End XMI ===")
        let parsed = try parser.parse(wrapExpression(xmi))
        print("Parsed helper: \(type(of: parsed))")

        // Then: Should be equivalent
        guard let parsedCall = parsed as? ATLHelperCallExpression else {
            Issue.record("Parsed expression should be helper call")
            return
        }
        print("Arguments count: \(parsedCall.arguments.count)")
        #expect(parsedCall.helperName == "myHelper")
        #expect(parsedCall.arguments.count == 2)

        guard let parsedArg1 = parsedCall.arguments[0] as? ATLLiteralExpression,
              let arg1Value = parsedArg1.value as? Int else {
            Issue.record("First argument should be integer literal")
            return
        }
        #expect(arg1Value == 42)

        guard let parsedArg2 = parsedCall.arguments[1] as? ATLVariableExpression else {
            Issue.record("Second argument should be variable")
            return
        }
        #expect(parsedArg2.name == "x")
    }

    // MARK: - Complex Nested Expression Tests

    @Test("Complex nested expression round-trip")
    func complexNestedExpressionRoundTrip() throws {
        // Given: A complex nested expression
        // if list->select(e | e > 0)->size() > 0 then 'positive' else 'none'

        // list->select(e | e > 0)
        let selectBody = ATLBinaryExpression(
            left: ATLVariableExpression(name: "e"),
            operator: .greaterThan,
            right: ATLLiteralExpression(value: 0)
        )
        let selectExpr = ATLCollectionExpression(
            source: ATLVariableExpression(name: "list"),
            operation: .select,
            iterator: "e",
            body: selectBody
        )

        // ->size()
        let sizeExpr = ATLMethodCallExpression(
            receiver: selectExpr,
            methodName: "size",
            arguments: []
        )

        // size() > 0
        let condition = ATLBinaryExpression(
            left: sizeExpr,
            operator: .greaterThan,
            right: ATLLiteralExpression(value: 0)
        )

        let original = ATLConditionalExpression(
            condition: condition,
            thenExpression: ATLLiteralExpression(value: "positive"),
            elseExpression: ATLLiteralExpression(value: "none")
        )

        // When: Serialize to XMI and parse back
        let xmi = serializer.serialize(original)
        let parsed = try parser.parse(wrapExpression(xmi))

        // Then: Should be equivalent (verify structure)
        guard let parsedCond = parsed as? ATLConditionalExpression else {
            Issue.record("Parsed expression should be conditional")
            return
        }

        // Verify condition is binary operation
        guard let parsedCondition = parsedCond.condition as? ATLBinaryExpression else {
            Issue.record("Condition should be binary operation")
            return
        }
        #expect(parsedCondition.operator == .greaterThan)

        // Verify left side of condition is method call (size())
        guard let parsedSize = parsedCondition.left as? ATLMethodCallExpression else {
            Issue.record("Left operand should be method call")
            return
        }
        #expect(parsedSize.methodName == "size")

        // Verify receiver of size() is collection expression (select)
        guard let parsedSelect = parsedSize.receiver as? ATLCollectionExpression else {
            Issue.record("Receiver should be collection expression")
            return
        }
        #expect(parsedSelect.operation == .select)

        // Verify then/else branches
        guard let parsedThen = parsedCond.thenExpression as? ATLLiteralExpression,
              let thenValue = parsedThen.value as? String else {
            Issue.record("Then branch should be string literal")
            return
        }
        #expect(thenValue == "positive")

        guard let parsedElse = parsedCond.elseExpression as? ATLLiteralExpression,
              let elseValue = parsedElse.value as? String else {
            Issue.record("Else branch should be string literal")
            return
        }
        #expect(elseValue == "none")
    }

    // MARK: - Utility Methods

    /// Wraps an expression XMI snippet in a minimal XML document for parsing.
    private func wrapExpression(_ expressionXMI: String) -> String {
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <root xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
              xmlns:ocl="http://www.eclipse.org/ocl/1.1.0/Ecore"
              xmlns:atl="http://www.eclipse.org/gmt/2005/ATL">
        \(expressionXMI)</root>
        """
    }
}
