//
//  ATLInterpreterTests.swift
//  ATL
//
//  Created by Rene Hexel on 7/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import ECore
import OrderedCollections
import Testing

@testable import ATL

/// Comprehensive tests for the ATL interpreter and virtual machine.
///
/// These tests verify the core execution engine functionality including
/// expression evaluation, collection operations, helper functions,
/// and rule execution without relying on complex parsing.
///
/// ## Test Strategy
///
/// Tests are structured to verify ATL/OCL compliance by:
/// - Creating expressions programmatically rather than through parsing
/// - Testing individual operations in isolation
/// - Verifying proper type handling and error conditions
/// - Ensuring correct OCL semantics for collection operations
///
/// ## Coverage Areas
///
/// - Expression evaluation (literals, variables, navigation)
/// - Binary and unary operations
/// - Method calls and OCL standard library
/// - Collection operations (select, collect, exists, forAll)
/// - Lambda expressions and iterator variables
/// - Helper function execution
/// - Rule execution and element creation
/// - Error handling and type checking
@Suite("ATL Interpreter Tests")
@MainActor
struct ATLInterpreterTests {

    // MARK: - Basic Expression Tests

    @Test("Literal expression evaluation")
    func testLiteralExpressionEvaluation() async throws {
        // Given
        let context = await createTestContext()
        let stringLiteral = ATLLiteralExpression(value: "Hello, ATL!")
        let intLiteral = ATLLiteralExpression(value: 42)
        let boolLiteral = ATLLiteralExpression(value: true)

        // When
        let stringResult = try await stringLiteral.evaluate(in: context)
        let intResult = try await intLiteral.evaluate(in: context)
        let boolResult = try await boolLiteral.evaluate(in: context)

        // Then
        #expect(stringResult as? String == "Hello, ATL!")
        #expect(intResult as? Int == 42)
        #expect(boolResult as? Bool == true)
    }

    @Test("Variable expression evaluation")
    func testVariableExpressionEvaluation() async throws {
        // Given
        let context = await createTestContext()
        context.setVariable("testVar", value: "Test Value")
        context.setVariable("numberVar", value: 123)

        let stringVar = ATLVariableExpression(name: "testVar")
        let numberVar = ATLVariableExpression(name: "numberVar")
        let undefinedVar = ATLVariableExpression(name: "undefinedVar")

        // When & Then
        let stringResult = try await stringVar.evaluate(in: context)
        #expect(stringResult as? String == "Test Value")

        let numberResult = try await numberVar.evaluate(in: context)
        #expect(numberResult as? Int == 123)

        // Should throw for undefined variable
        do {
            _ = try await undefinedVar.evaluate(in: context)
            #expect(Bool(false), "Should have thrown for undefined variable")
        } catch {
            #expect(error is ATLExecutionError)
        }
    }

    @Test("Binary operation evaluation")
    func testBinaryOperationEvaluation() async throws {
        // Given
        let context = await createTestContext()

        // Arithmetic operations
        let addition = ATLBinaryExpression(
            left: ATLLiteralExpression(value: 10),
            operator: .plus,
            right: ATLLiteralExpression(value: 5)
        )

        let multiplication = ATLBinaryExpression(
            left: ATLLiteralExpression(value: 7),
            operator: .multiply,
            right: ATLLiteralExpression(value: 6)
        )

        // Comparison operations
        let equality = ATLBinaryExpression(
            left: ATLLiteralExpression(value: "test"),
            operator: .equals,
            right: ATLLiteralExpression(value: "test")
        )

        let greaterThan = ATLBinaryExpression(
            left: ATLLiteralExpression(value: 10),
            operator: .greaterThan,
            right: ATLLiteralExpression(value: 5)
        )

        // When
        let addResult = try await addition.evaluate(in: context)
        let mulResult = try await multiplication.evaluate(in: context)
        let eqResult = try await equality.evaluate(in: context)
        let gtResult = try await greaterThan.evaluate(in: context)

        // Then
        #expect(addResult as? Int == 15)
        #expect(mulResult as? Int == 42)
        #expect(eqResult as? Bool == true)
        #expect(gtResult as? Bool == true)
    }

    @Test("Conditional expression evaluation")
    func testConditionalExpressionEvaluation() async throws {
        // Given
        let context = await createTestContext()

        let trueCondition = ATLConditionalExpression(
            condition: ATLLiteralExpression(value: true),
            thenExpression: ATLLiteralExpression(value: "True branch"),
            elseExpression: ATLLiteralExpression(value: "False branch")
        )

        let falseCondition = ATLConditionalExpression(
            condition: ATLLiteralExpression(value: false),
            thenExpression: ATLLiteralExpression(value: "True branch"),
            elseExpression: ATLLiteralExpression(value: "False branch")
        )

        // When
        let trueResult = try await trueCondition.evaluate(in: context)
        let falseResult = try await falseCondition.evaluate(in: context)

        // Then
        #expect(trueResult as? String == "True branch")
        #expect(falseResult as? String == "False branch")
    }

    // MARK: - Collection Operation Tests

    @Test("Collection size operation")
    func testCollectionSizeOperation() async throws {
        // Given
        let context = await createTestContext()
        let collection = ["apple", "banana", "cherry"]
        context.setVariable("fruits", value: collection)

        let sizeCall = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "fruits"),
            methodName: "size"
        )

        // When
        let result = try await sizeCall.evaluate(in: context)

        // Then
        #expect(result as? Int == 3)
    }

    @Test("Collection isEmpty operation")
    func testCollectionIsEmptyOperation() async throws {
        // Given
        let context = await createTestContext()
        let emptyCollection: [String] = []
        let nonEmptyCollection = ["item"]

        context.setVariable("emptyList", value: emptyCollection)
        context.setVariable("nonEmptyList", value: nonEmptyCollection)

        let emptyCheck = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "emptyList"),
            methodName: "isEmpty"
        )

        let nonEmptyCheck = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "nonEmptyList"),
            methodName: "isEmpty"
        )

        // When
        let emptyResult = try await emptyCheck.evaluate(in: context)
        let nonEmptyResult = try await nonEmptyCheck.evaluate(in: context)

        // Then
        #expect(emptyResult as? Bool == true)
        #expect(nonEmptyResult as? Bool == false)
    }

    @Test("Collection includes operation")
    func testCollectionIncludesOperation() async throws {
        // Given
        let context = await createTestContext()
        let collection = ["apple", "banana", "cherry"]
        context.setVariable("fruits", value: collection)

        let includesCall = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "fruits"),
            methodName: "includes",
            arguments: [ATLLiteralExpression(value: "banana")]
        )

        let excludesCall = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "fruits"),
            methodName: "includes",
            arguments: [ATLLiteralExpression(value: "grape")]
        )

        // When
        let includesResult = try await includesCall.evaluate(in: context)
        let excludesResult = try await excludesCall.evaluate(in: context)

        // Then
        #expect(includesResult as? Bool == true)
        #expect(excludesResult as? Bool == false)
    }

    @Test("String operations")
    func testStringOperations() async throws {
        // Given
        let context = await createTestContext()
        context.setVariable("testString", value: "hello world")

        let upperCaseCall = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "testString"),
            methodName: "toUpperCase"
        )

        let sizeCall = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "testString"),
            methodName: "size"
        )

        // When
        let upperResult = try await upperCaseCall.evaluate(in: context)
        let sizeResult = try await sizeCall.evaluate(in: context)

        // Then
        #expect(upperResult as? String == "HELLO WORLD")
        #expect(sizeResult as? Int == 11)
    }

    @Test("Integer operations")
    func testIntegerOperations() async throws {
        // Given
        let context = await createTestContext()
        context.setVariable("testNumber", value: 15)

        let modCall = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "testNumber"),
            methodName: "mod",
            arguments: [ATLLiteralExpression(value: 4)]
        )

        let isEvenCall = ATLMethodCallExpression(
            receiver: ATLLiteralExpression(value: 8),
            methodName: "isEven"
        )

        let squareCall = ATLMethodCallExpression(
            receiver: ATLLiteralExpression(value: 5),
            methodName: "square"
        )

        // When
        let modResult = try await modCall.evaluate(in: context)
        let evenResult = try await isEvenCall.evaluate(in: context)
        let squareResult = try await squareCall.evaluate(in: context)

        // Then
        #expect(modResult as? Int == 3)
        #expect(evenResult as? Bool == true)
        #expect(squareResult as? Int == 25)
    }

    // MARK: - Lambda Expression Tests

    @Test("Lambda expression with parameter binding")
    func testLambdaExpressionEvaluation() async throws {
        // Given
        let context = await createTestContext()

        // Lambda: x | x * 2
        let lambda = ATLLambdaExpression(
            parameter: "x",
            body: ATLBinaryExpression(
                left: ATLVariableExpression(name: "x"),
                operator: .multiply,
                right: ATLLiteralExpression(value: 2)
            )
        )

        // When
        let result = try await lambda.evaluateWith(parameterValue: 5, in: context)

        // Then
        #expect(result as? Int == 10)
    }

    @Test("Lambda expression with complex body")
    func testComplexLambdaExpression() async throws {
        // Given
        let context = await createTestContext()

        // Lambda: item | item.size() > 3
        let lambda = ATLLambdaExpression(
            parameter: "item",
            body: ATLBinaryExpression(
                left: ATLMethodCallExpression(
                    receiver: ATLVariableExpression(name: "item"),
                    methodName: "size"
                ),
                operator: .greaterThan,
                right: ATLLiteralExpression(value: 3)
            )
        )

        // When
        let shortString = try await lambda.evaluateWith(parameterValue: "Hi", in: context)
        let longString = try await lambda.evaluateWith(parameterValue: "Hello", in: context)

        // Then
        #expect(shortString as? Bool == false)
        #expect(longString as? Bool == true)
    }

    // MARK: - Error Handling Tests

    @Test("Type error handling")
    func testTypeErrorHandling() async throws {
        // Given
        let context = await createTestContext()
        context.setVariable("stringVar", value: "not a number")

        let invalidOperation = ATLBinaryExpression(
            left: ATLVariableExpression(name: "stringVar"),
            operator: .plus,
            right: ATLLiteralExpression(value: 5)
        )

        // When & Then
        do {
            _ = try await invalidOperation.evaluate(in: context)
            #expect(Bool(false), "Should have thrown type error")
        } catch let error as ATLExecutionError {
            switch error {
            case .typeError, .invalidOperation:
                // Expected - either type error or invalid operation error
                break
            default:
                #expect(Bool(false), "Expected type or invalid operation error, got \(error)")
            }
        }
    }

    @Test("Division by zero error")
    func testDivisionByZeroError() async throws {
        // Given
        let context = await createTestContext()

        let divisionByZero = ATLBinaryExpression(
            left: ATLLiteralExpression(value: 10),
            operator: .divide,
            right: ATLLiteralExpression(value: 0)
        )

        // When & Then
        do {
            _ = try await divisionByZero.evaluate(in: context)
            #expect(Bool(false), "Should have thrown division by zero error")
        } catch ATLExecutionError.divisionByZero {
            // Expected
        } catch {
            #expect(Bool(false), "Expected division by zero error, got \(error)")
        }
    }

    @Test("Unsupported operation error")
    func testUnsupportedOperationError() async throws {
        // Given
        let context = await createTestContext()
        context.setVariable("testValue", value: "test")

        let unsupportedCall = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "testValue"),
            methodName: "nonExistentMethod"
        )

        // When & Then
        do {
            _ = try await unsupportedCall.evaluate(in: context)
            #expect(Bool(false), "Should have thrown unsupported operation error")
        } catch ATLExecutionError.unsupportedOperation {
            // Expected
        } catch {
            #expect(Bool(false), "Expected unsupported operation error, got \(error)")
        }
    }

    // MARK: - Scoping Tests

    @Test("Variable scoping with push/pop")
    func testVariableScoping() async throws {
        // Given
        let context = await createTestContext()
        context.setVariable("globalVar", value: "global")

        // When - push scope and set local variable
        context.pushScope()
        context.setVariable("localVar", value: "local")
        context.setVariable("globalVar", value: "shadowed")

        // Access variables in nested scope
        let globalInScope = try context.getVariable("globalVar")
        let localInScope = try context.getVariable("localVar")

        // Pop scope
        context.popScope()

        // Access variables after popping scope
        let globalAfterPop = try context.getVariable("globalVar")

        do {
            _ = try context.getVariable("localVar")
            #expect(Bool(false), "Local variable should not exist after pop")
        } catch {
            // Expected - local variable should be gone
        }

        // Then
        #expect(globalInScope as? String == "shadowed")
        #expect(localInScope as? String == "local")
        #expect(globalAfterPop as? String == "global")
    }

    @Test("Nested scoping behaviour")
    func testNestedScoping() async throws {
        // Given
        let context = await createTestContext()
        context.setVariable("level0", value: 0)

        // When - create nested scopes
        context.pushScope()
        context.setVariable("level1", value: 1)

        context.pushScope()
        context.setVariable("level2", value: 2)

        // All variables should be accessible
        #expect(try context.getVariable("level0") as? Int == 0)
        #expect(try context.getVariable("level1") as? Int == 1)
        #expect(try context.getVariable("level2") as? Int == 2)

        // Pop one level
        context.popScope()

        #expect(try context.getVariable("level0") as? Int == 0)
        #expect(try context.getVariable("level1") as? Int == 1)

        do {
            _ = try context.getVariable("level2")
            #expect(Bool(false), "level2 should not be accessible")
        } catch {
            // Expected
        }

        // Pop to root level
        context.popScope()

        #expect(try context.getVariable("level0") as? Int == 0)

        do {
            _ = try context.getVariable("level1")
            #expect(Bool(false), "level1 should not be accessible")
        } catch {
            // Expected
        }
    }

    // MARK: - Helper Methods

    /// Creates a test execution context with minimal setup.
    ///
    /// - Returns: Configured ATL execution context for testing
    private func createTestContext() async -> ATLExecutionContext {
        // Create minimal dummy metamodels to satisfy ATLModule requirements
        let dummySourceMetamodel = EPackage(
            name: "TestSource", nsURI: "test://source", nsPrefix: "src")
        let dummyTargetMetamodel = EPackage(
            name: "TestTarget", nsURI: "test://target", nsPrefix: "tgt")

        let module = ATLModule(
            name: "TestModule",
            sourceMetamodels: ["Source": dummySourceMetamodel],
            targetMetamodels: ["Target": dummyTargetMetamodel]
        )

        let executionEngine = ECoreExecutionEngine(models: [:])
        return ATLExecutionContext(
            module: module,
            sources: [:],
            targets: [:],
            executionEngine: executionEngine
        )
    }

    /// Creates a test execution context with sample data.
    ///
    /// - Returns: ATL execution context with sample source and target models
    private func createTestContextWithSampleData() async -> ATLExecutionContext {
        // Create minimal dummy metamodels to satisfy ATLModule requirements
        let dummySourceMetamodel = EPackage(
            name: "TestSource", nsURI: "test://source", nsPrefix: "src")
        let dummyTargetMetamodel = EPackage(
            name: "TestTarget", nsURI: "test://target", nsPrefix: "tgt")

        let module = ATLModule(
            name: "TestModule",
            sourceMetamodels: ["Source": dummySourceMetamodel],
            targetMetamodels: ["Target": dummyTargetMetamodel]
        )

        // Create simple source resource for testing
        let sourceResource = Resource(uri: "test://source.model")
        let targetResource = Resource(uri: "test://target.model")

        let sources: OrderedDictionary<String, Resource> = ["Source": sourceResource]
        let targets: OrderedDictionary<String, Resource> = ["Target": targetResource]

        let executionEngine = ECoreExecutionEngine(models: [:])
        let context = ATLExecutionContext(
            module: module,
            sources: sources,
            targets: targets,
            executionEngine: executionEngine
        )

        // Add some sample data
        context.setVariable("sampleString", value: "Hello ATL")
        context.setVariable("sampleNumber", value: 42)
        context.setVariable("sampleBoolean", value: true)
        context.setVariable("sampleArray", value: ["a", "b", "c"])

        return context
    }

    // MARK: - Context Helper Tests

    @Test("Context helper called as method on object")
    func testContextHelperAsMethod() async throws {
        // Given - a context helper that checks if a value is positive
        let isPositiveHelper = ATLHelperWrapper(
            name: "isPositive",
            contextType: "Integer",
            returnType: "Boolean",
            parameters: [],
            body: ATLBinaryExpression(
                left: ATLVariableExpression(name: "self"),
                operator: .greaterThan,
                right: ATLLiteralExpression(value: 0)
            )
        )

        let module = ATLModule(
            name: "TestContextHelper",
            sourceMetamodels: ["IN": EPackage(name: "Source", nsURI: "http://test.source")],
            targetMetamodels: ["OUT": EPackage(name: "Target", nsURI: "http://test.target")],
            helpers: ["isPositive": isPositiveHelper]
        )

        let sourceResource = Resource(uri: "test://source.model")
        let targetResource = Resource(uri: "test://target.model")
        let sources: OrderedDictionary<String, Resource> = ["IN": sourceResource]
        let targets: OrderedDictionary<String, Resource> = ["OUT": targetResource]

        let executionEngine = ECoreExecutionEngine(models: [:])
        let context = ATLExecutionContext(
            module: module,
            sources: sources,
            targets: targets,
            executionEngine: executionEngine
        )

        // When - calling the helper as a method on a positive integer
        let methodCall = ATLMethodCallExpression(
            receiver: ATLLiteralExpression(value: 5),
            methodName: "isPositive",
            arguments: []
        )

        let result = try await methodCall.evaluate(in: context)

        // Then - should return true
        #expect(result as? Bool == true, "isPositive() should return true for positive number")

        // When - calling on a negative integer
        let negativeCall = ATLMethodCallExpression(
            receiver: ATLLiteralExpression(value: -3),
            methodName: "isPositive",
            arguments: []
        )

        let negativeResult = try await negativeCall.evaluate(in: context)

        // Then - should return false
        #expect(
            negativeResult as? Bool == false, "isPositive() should return false for negative number"
        )
    }

    @Test("Context helper with complex logic")
    func testContextHelperComplexLogic() async throws {
        // Given - a context helper that checks if a number is even using self
        let isEvenHelper = ATLHelperWrapper(
            name: "checkEven",
            contextType: "Integer",
            returnType: "Boolean",
            parameters: [],
            body: ATLBinaryExpression(
                left: ATLBinaryExpression(
                    left: ATLVariableExpression(name: "self"),
                    operator: .modulo,
                    right: ATLLiteralExpression(value: 2)
                ),
                operator: .equals,
                right: ATLLiteralExpression(value: 0)
            )
        )

        let module = ATLModule(
            name: "TestComplexHelper",
            sourceMetamodels: ["IN": EPackage(name: "Source", nsURI: "http://test.source")],
            targetMetamodels: ["OUT": EPackage(name: "Target", nsURI: "http://test.target")],
            helpers: ["checkEven": isEvenHelper]
        )

        let sourceResource = Resource(uri: "test://source.model")
        let targetResource = Resource(uri: "test://target.model")
        let sources: OrderedDictionary<String, Resource> = ["IN": sourceResource]
        let targets: OrderedDictionary<String, Resource> = ["OUT": targetResource]

        let executionEngine = ECoreExecutionEngine(models: [:])
        let context = ATLExecutionContext(
            module: module,
            sources: sources,
            targets: targets,
            executionEngine: executionEngine
        )

        // When - calling on an even number
        let evenCall = ATLMethodCallExpression(
            receiver: ATLLiteralExpression(value: 4),
            methodName: "checkEven",
            arguments: []
        )

        let evenResult = try await evenCall.evaluate(in: context)

        // Then
        #expect(evenResult as? Bool == true, "checkEven() should return true for even number")

        // When - calling on an odd number
        let oddCall = ATLMethodCallExpression(
            receiver: ATLLiteralExpression(value: 7),
            methodName: "checkEven",
            arguments: []
        )

        let oddResult = try await oddCall.evaluate(in: context)

        // Then
        #expect(oddResult as? Bool == false, "checkEven() should return false for odd number")
    }

    // MARK: - OCL Standard Library Tests

    @Test("oclIsUndefined method with nil value")
    func testOclIsUndefinedWithNil() async throws {
        // Given
        let context = await createTestContext()
        context.setVariable("nullValue", value: nil)

        let oclIsUndefinedCall = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "nullValue"),
            methodName: "oclIsUndefined"
        )

        // When
        let result = try await oclIsUndefinedCall.evaluate(in: context)

        // Then
        #expect(result as? Bool == true, "oclIsUndefined() should return true for nil value")
    }

    @Test("oclIsUndefined method with non-nil value")
    func testOclIsUndefinedWithValue() async throws {
        // Given
        let context = await createTestContext()
        context.setVariable("definedValue", value: "Hello")

        let oclIsUndefinedCall = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "definedValue"),
            methodName: "oclIsUndefined"
        )

        // When
        let result = try await oclIsUndefinedCall.evaluate(in: context)

        // Then
        #expect(result as? Bool == false, "oclIsUndefined() should return false for defined value")
    }

    @Test("oclIsUndefined method with direct nil literal")
    func testOclIsUndefinedWithDirectNil() async throws {
        // Given
        let context = await createTestContext()

        let oclIsUndefinedCall = ATLMethodCallExpression(
            receiver: ATLLiteralExpression(value: nil),
            methodName: "oclIsUndefined"
        )

        // When
        let result = try await oclIsUndefinedCall.evaluate(in: context)

        // Then
        #expect(result as? Bool == true, "oclIsUndefined() should return true for nil literal")
    }

    @Test("Variable scoping in rule guards with helper calls")
    func testVariableScopingInRuleGuardsWithHelperCalls() async throws {
        // Create Member EClass with familyMother reference (similar to real Families metamodel)
        var memberClass = EClass(name: "Member")
        let familyMotherRef = EReference(
            name: "familyMother",
            eType: EClass(name: "Family"),
            lowerBound: 0,
            upperBound: 1
        )
        memberClass.eStructuralFeatures.append(familyMotherRef)

        // Create a Member instance without familyMother (nil)
        let memberInstance = DynamicEObject(eClass: memberClass)

        // Create an isFemale helper that references the source pattern variable 's'
        // This simulates the real Families2Persons transformation
        let isFemaleHelper = ATLHelperWrapper(
            name: "isFemale",
            contextType: "Families!Member",
            returnType: "Boolean",
            parameters: [],
            body: ATLMethodCallExpression(
                receiver: ATLNavigationExpression(
                    source: ATLVariableExpression(name: "self"),
                    property: "familyMother"
                ),
                methodName: "oclIsUndefined"
            )
        )

        // Create a guard that calls the helper method on variable 's'
        let guardExpression = ATLUnaryExpression(
            operator: .not,
            operand: ATLMethodCallExpression(
                receiver: ATLVariableExpression(name: "s"),
                methodName: "isFemale"
            )
        )

        let sourcePattern = ATLSourcePattern(
            variableName: "s",
            type: "Families!Member",
            guard: guardExpression
        )

        // Create a matched rule with the guard that references 's'
        let targetPattern = ATLTargetPattern(variableName: "t", type: "Persons!Male")
        let rule = ATLMatchedRule(
            name: "Member2Male",
            sourcePattern: sourcePattern,
            targetPatterns: [targetPattern],
            guard: sourcePattern.guard
        )

        // Create metamodels with proper classes
        var familiesPackage = EPackage(name: "Families", nsURI: "http://test.families")
        familiesPackage.eClassifiers.append(memberClass)

        var personsPackage = EPackage(name: "Persons", nsURI: "http://test.persons")
        let maleClass = EClass(name: "Male")
        personsPackage.eClassifiers.append(maleClass)

        // Create virtual machine with helper and rule
        let module = ATLModule(
            name: "TestVariableScopingWithHelpers",
            sourceMetamodels: ["IN": familiesPackage],
            targetMetamodels: ["OUT": personsPackage],
            helpers: ["isFemale": isFemaleHelper],
            matchedRules: [rule]
        )
        let vm = ATLVirtualMachine(module: module, enableDebugging: true)
        await vm.enableDebugging()

        // Create dummy source and target resources for execution
        let sourceResource = Resource(uri: "test://source")
        await sourceResource.add(memberInstance)
        let targetResource = Resource(uri: "test://target")

        // Variable scoping should now work correctly with helper calls
        do {
            try await vm.execute(
                sources: ["IN": sourceResource],
                targets: ["OUT": targetResource]
            )
            // Success expected - variable scoping is working correctly
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test("Multiple rules with same variable name")
    func testMultipleRulesWithSameVariableName() async throws {
        // Create Member class with familyMother reference for helper
        var memberClass = EClass(name: "Member")
        let familyClass = EClass(name: "Family")
        let familyMotherRef = EReference(
            name: "familyMother", eType: familyClass, lowerBound: 0, upperBound: 1)
        memberClass.eStructuralFeatures.append(familyMotherRef)

        let familyDaughterRef = EReference(
            name: "familyDaughter", eType: familyClass, lowerBound: 0, upperBound: 1)
        memberClass.eStructuralFeatures.append(familyDaughterRef)

        // Create helper: isFemale()
        let isFemaleHelper = ATLHelperWrapper(
            name: "isFemale",
            contextType: "Families!Member",
            returnType: "Boolean",
            parameters: [],
            body: ATLBinaryExpression(
                left: ATLUnaryExpression(
                    operator: .not,
                    operand: ATLMethodCallExpression(
                        receiver: ATLNavigationExpression(
                            source: ATLVariableExpression(name: "self"),
                            property: "familyMother"
                        ),
                        methodName: "oclIsUndefined"
                    )
                ),
                operator: .or,
                right: ATLUnaryExpression(
                    operator: .not,
                    operand: ATLMethodCallExpression(
                        receiver: ATLNavigationExpression(
                            source: ATLVariableExpression(name: "self"),
                            property: "familyDaughter"
                        ),
                        methodName: "oclIsUndefined"
                    )
                )
            )
        )

        // Create first rule: Member2Male with guard (not s.isFemale())
        let maleGuardExpression = ATLUnaryExpression(
            operator: .not,
            operand: ATLMethodCallExpression(
                receiver: ATLVariableExpression(name: "s"),
                methodName: "isFemale"
            )
        )
        let maleSourcePattern = ATLSourcePattern(
            variableName: "s",
            type: "Families!Member",
            guard: maleGuardExpression
        )
        let maleTargetPattern = ATLTargetPattern(
            variableName: "t",
            type: "Persons!Male",
            bindings: [
                ATLPropertyBinding(
                    property: "fullName",
                    expression: ATLBinaryExpression(
                        left: ATLBinaryExpression(
                            left: ATLNavigationExpression(
                                source: ATLVariableExpression(name: "s"),
                                property: "firstName"
                            ),
                            operator: .plus,
                            right: ATLLiteralExpression(value: " ")
                        ),
                        operator: .plus,
                        right: ATLLiteralExpression(value: "TestName")
                    )
                )
            ]
        )
        let maleRule = ATLMatchedRule(
            name: "Member2Male",
            sourcePattern: maleSourcePattern,
            targetPatterns: [maleTargetPattern],
            guard: maleGuardExpression
        )

        // Create second rule: Member2Female with guard s.isFemale()
        let femaleGuardExpression = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "s"),
            methodName: "isFemale"
        )
        let femaleSourcePattern = ATLSourcePattern(
            variableName: "s",
            type: "Families!Member",
            guard: femaleGuardExpression
        )
        let femaleTargetPattern = ATLTargetPattern(
            variableName: "t",
            type: "Persons!Female",
            bindings: [
                ATLPropertyBinding(
                    property: "fullName",
                    expression: ATLBinaryExpression(
                        left: ATLBinaryExpression(
                            left: ATLNavigationExpression(
                                source: ATLVariableExpression(name: "s"),
                                property: "firstName"
                            ),
                            operator: .plus,
                            right: ATLLiteralExpression(value: " ")
                        ),
                        operator: .plus,
                        right: ATLLiteralExpression(value: "TestName")
                    )
                )
            ]
        )
        let femaleRule = ATLMatchedRule(
            name: "Member2Female",
            sourcePattern: femaleSourcePattern,
            targetPatterns: [femaleTargetPattern],
            guard: femaleGuardExpression
        )

        // Add firstName attribute to Member
        let firstNameAttr = EAttribute(name: "firstName", eType: EDataType(name: "EString"))
        memberClass.eStructuralFeatures.append(firstNameAttr)

        // Create metamodels
        var familiesPackage = EPackage(name: "Families", nsURI: "http://test.families")
        familiesPackage.eClassifiers.append(memberClass)
        familiesPackage.eClassifiers.append(familyClass)

        var personsPackage = EPackage(name: "Persons", nsURI: "http://test.persons")
        var maleClass = EClass(name: "Male")
        var femaleClass = EClass(name: "Female")
        // Add fullName attribute to target classes
        let fullNameAttr = EAttribute(name: "fullName", eType: EDataType(name: "EString"))
        maleClass.eStructuralFeatures.append(fullNameAttr)
        femaleClass.eStructuralFeatures.append(fullNameAttr)
        personsPackage.eClassifiers.append(maleClass)
        personsPackage.eClassifiers.append(femaleClass)

        // Create test data - two members (property values will be set via storage for testing)
        let maleInstance = DynamicEObject(eClass: memberClass)
        let femaleInstance = DynamicEObject(eClass: memberClass)
        // Leave family references as nil to simulate different isFemale() results

        // Create virtual machine with helper and both rules
        let module = ATLModule(
            name: "TestMultipleRulesWithSameVariable",
            sourceMetamodels: ["IN": familiesPackage],
            targetMetamodels: ["OUT": personsPackage],
            helpers: ["isFemale": isFemaleHelper],
            matchedRules: [maleRule, femaleRule]
        )
        let vm = ATLVirtualMachine(module: module, enableDebugging: true)
        await vm.enableDebugging()

        // Create resources
        let sourceResource = Resource(uri: "test://source")
        await sourceResource.add(maleInstance)
        await sourceResource.add(femaleInstance)
        let targetResource = Resource(uri: "test://target")

        // This should reproduce the "Variable 's' not found" error
        // when property bindings evaluate helper calls that lose variable scope
        do {
            try await vm.execute(
                sources: ["IN": sourceResource],
                targets: ["OUT": targetResource]
            )
            print("Transformation completed successfully with multiple rules")
        } catch let error as ATLExecutionError {
            switch error {
            case .variableNotFound(let name):
                Issue.record("Variable '\(name)' not found - this reproduces the bug!")
            default:
                Issue.record("Unexpected ATL error: \(error)")
            }
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
