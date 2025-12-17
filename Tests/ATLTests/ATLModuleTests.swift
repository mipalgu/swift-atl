//
//  ATLModuleTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 6/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//

import Foundation
import OrderedCollections
import Testing

@testable import ATL
@testable import ECore

/// Test suite for ATL module functionality.
///
/// Tests the core module structure used in Atlas Transformation Language,
/// including module creation, helper functions, rules, and metamodel specifications.
@Suite("ATL Module Tests")
struct ATLModuleTests {

    // MARK: - Basic Construction Tests

    @Test("Module construction with basic parameters")
    func testModuleConstruction() async throws {
        // Given
        let moduleName = "TestModule"
        let sourcePackage = EPackage(name: "Source", nsURI: "http://test.example/source")
        let targetPackage = EPackage(name: "Target", nsURI: "http://test.example/target")
        let sourceMetamodels: OrderedDictionary<String, EPackage> = ["Source": sourcePackage]
        let targetMetamodels: OrderedDictionary<String, EPackage> = ["Target": targetPackage]

        // When
        let module = ATLModule(
            name: moduleName,
            sourceMetamodels: sourceMetamodels,
            targetMetamodels: targetMetamodels
        )

        // Then
        #expect(module.name == moduleName)
        #expect(module.sourceMetamodels.count == 1)
        #expect(module.targetMetamodels.count == 1)
        #expect(module.sourceMetamodels["Source"] != nil)
        #expect(module.targetMetamodels["Target"] != nil)
        #expect(module.helpers.isEmpty)
        #expect(module.matchedRules.isEmpty)
        #expect(module.calledRules.isEmpty)
    }

    @Test("Module with helpers construction")
    func testModuleWithHelpers() async throws {
        // Given
        let helper = ATLHelper(
            name: "testHelper",
            returnType: "String",
            parameters: [],
            body: ATLLiteralExpression(value: "test")
        )

        // When
        let sourcePackage = EPackage(name: "Source", nsURI: "http://test.example/source")
        let targetPackage = EPackage(name: "Target", nsURI: "http://test.example/target")

        let module = ATLModule(
            name: "TestModule",
            sourceMetamodels: ["Source": sourcePackage],
            targetMetamodels: ["Target": targetPackage],
            helpers: [helper.name: helper]
        )

        // Then
        #expect(module.helpers.count == 1)
        #expect(module.helpers["testHelper"] != nil)
    }

    @Test("Module with matched rules construction")
    func testModuleWithMatchedRules() async throws {
        // Given
        let sourcePattern = ATLSourcePattern(
            variableName: "src",
            type: "SourceType"
        )
        let targetPattern = ATLTargetPattern(
            variableName: "tgt",
            type: "TargetType"
        )
        let rule = ATLMatchedRule(
            name: "TestRule",
            sourcePattern: sourcePattern,
            targetPatterns: [targetPattern]
        )

        // When
        let sourcePackage = EPackage(name: "Source", nsURI: "http://test.example/source")
        let targetPackage = EPackage(name: "Target", nsURI: "http://test.example/target")

        let module = ATLModule(
            name: "TestModule",
            sourceMetamodels: ["Source": sourcePackage],
            targetMetamodels: ["Target": targetPackage],
            matchedRules: [rule]
        )

        // Then
        #expect(module.matchedRules.count == 1)
        #expect(module.matchedRules[0].name == "TestRule")
    }

    @Test("Module with called rules construction")
    func testModuleWithCalledRules() async throws {
        // Given
        let parameter = ATLParameter(name: "input", type: "String")
        let targetPattern = ATLTargetPattern(
            variableName: "output",
            type: "OutputType"
        )
        let rule = ATLCalledRule(
            name: "TestCalledRule",
            parameters: [parameter],
            targetPatterns: [targetPattern]
        )

        // When
        let sourcePackage = EPackage(name: "Source", nsURI: "http://test.example/source")
        let targetPackage = EPackage(name: "Target", nsURI: "http://test.example/target")

        let module = ATLModule(
            name: "TestModule",
            sourceMetamodels: ["Source": sourcePackage],
            targetMetamodels: ["Target": targetPackage],
            calledRules: [rule.name: rule]
        )

        // Then
        #expect(module.calledRules.count == 1)
        #expect(module.calledRules["TestCalledRule"] != nil)
    }

    // MARK: - Helper Tests

    @Test("Helper construction")
    func testHelperConstruction() async throws {
        // Given
        let helperName = "upperCase"
        let parameter = ATLParameter(name: "input", type: "String")
        let body = ATLLiteralExpression(value: "UPPERCASE")

        // When
        let helper = ATLHelper(
            name: helperName,
            returnType: "String",
            parameters: [parameter],
            body: body
        )

        // Then
        #expect(helper.name == helperName)
        #expect(helper.parameters.count == 1)
        #expect(helper.parameters[0].name == "input")
        #expect(helper.returnType == "String")
    }

    @Test("Parameter construction")
    func testParameterConstruction() async throws {
        // Given
        let paramName = "testParam"
        let paramType = "String"

        // When
        let parameter = ATLParameter(name: paramName, type: paramType)

        // Then
        #expect(parameter.name == paramName)
        #expect(parameter.type == paramType)
    }

    // MARK: - Rule Tests

    @Test("Source pattern construction")
    func testSourcePatternConstruction() async throws {
        // Given
        let patternName = "source"
        let patternType = "SourceClass"

        // When
        let pattern = ATLSourcePattern(
            variableName: patternName,
            type: patternType
        )

        // Then
        #expect(pattern.variableName == patternName)
        #expect(pattern.type == patternType)
    }

    @Test("Target pattern construction")
    func testTargetPatternConstruction() async throws {
        // Given
        let patternName = "target"
        let patternType = "TargetClass"

        // When
        let pattern = ATLTargetPattern(
            variableName: patternName,
            type: patternType
        )

        // Then
        #expect(pattern.variableName == patternName)
        #expect(pattern.type == patternType)
        #expect(pattern.bindings.isEmpty)
    }

    @Test("Matched rule construction")
    func testMatchedRuleConstruction() async throws {
        // Given
        let ruleName = "TestMatchedRule"
        let sourcePattern = ATLSourcePattern(variableName: "src", type: "Source")
        let targetPattern = ATLTargetPattern(variableName: "tgt", type: "Target")

        // When
        let rule = ATLMatchedRule(
            name: ruleName,
            sourcePattern: sourcePattern,
            targetPatterns: [targetPattern]
        )

        // Then
        #expect(rule.name == ruleName)
        #expect(rule.sourcePattern.variableName == "src")
        #expect(rule.targetPatterns.count == 1)
        #expect(rule.targetPatterns[0].variableName == "tgt")
    }

    @Test("Called rule construction")
    func testCalledRuleConstruction() async throws {
        // Given
        let ruleName = "TestCalledRule"
        let parameter = ATLParameter(name: "input", type: "String")
        let targetPattern = ATLTargetPattern(variableName: "output", type: "Output")

        // When
        let rule = ATLCalledRule(
            name: ruleName,
            parameters: [parameter],
            targetPatterns: [targetPattern]
        )

        // Then
        #expect(rule.name == ruleName)
        #expect(rule.parameters.count == 1)
        #expect(rule.parameters[0].name == "input")
        #expect(rule.targetPatterns.count == 1)
        #expect(rule.targetPatterns[0].variableName == "output")
    }

    // MARK: - Equality Tests

    @Test("Module equality")
    func testModuleEquality() async throws {
        // Given
        let sourcePackage = EPackage(name: "Source", nsURI: "http://test.example/source")
        let targetPackage = EPackage(name: "Target", nsURI: "http://test.example/target")

        let module1 = ATLModule(
            name: "Test", sourceMetamodels: ["Source": sourcePackage],
            targetMetamodels: ["Target": targetPackage])
        let module2 = ATLModule(
            name: "Test", sourceMetamodels: ["Source": sourcePackage],
            targetMetamodels: ["Target": targetPackage])
        let module3 = ATLModule(
            name: "Different", sourceMetamodels: ["Source": sourcePackage],
            targetMetamodels: ["Target": targetPackage])

        // Then
        #expect(module1 == module2)
        #expect(module1 != module3)
    }

    @Test("Helper equality")
    func testHelperEquality() async throws {
        // Given
        let body = ATLLiteralExpression(value: "test")
        let helper1 = ATLHelper(name: "test", returnType: "String", parameters: [], body: body)
        let helper2 = ATLHelper(name: "test", returnType: "String", parameters: [], body: body)
        let helper3 = ATLHelper(name: "other", returnType: "String", parameters: [], body: body)

        // Then
        #expect(helper1 == helper2)
        #expect(helper1 != helper3)
    }

    @Test("Parameter equality")
    func testParameterEquality() async throws {
        // Given
        let param1 = ATLParameter(name: "test", type: "String")
        let param2 = ATLParameter(name: "test", type: "String")
        let param3 = ATLParameter(name: "test", type: "Int")
        let param4 = ATLParameter(name: "other", type: "String")

        // Then
        #expect(param1 == param2)
        #expect(param1 != param3)
        #expect(param1 != param4)
    }

    // MARK: - Hash Tests

    @Test("Component hash consistency")
    func testComponentHashConsistency() async throws {
        // Given
        let sourcePackage = EPackage(name: "Source", nsURI: "http://test.example/source")
        let targetPackage = EPackage(name: "Target", nsURI: "http://test.example/target")

        let module = ATLModule(
            name: "Test", sourceMetamodels: ["Source": sourcePackage],
            targetMetamodels: ["Target": targetPackage])
        let helper = ATLHelper(
            name: "test",
            returnType: "String",
            parameters: [],
            body: ATLLiteralExpression(value: "test")
        )
        let parameter = ATLParameter(name: "param", type: "String")

        // When
        let moduleHash1 = module.hashValue
        let moduleHash2 = module.hashValue
        let helperHash1 = helper.hashValue
        let helperHash2 = helper.hashValue
        let paramHash1 = parameter.hashValue
        let paramHash2 = parameter.hashValue

        // Then
        #expect(moduleHash1 == moduleHash2)
        #expect(helperHash1 == helperHash2)
        #expect(paramHash1 == paramHash2)
    }
}

// MARK: - Test Helper Functions

extension ATLModuleTests {

    /// Creates a basic test module for common test scenarios.
    private func createTestModule() -> ATLModule {
        let sourcePackage = EPackage(name: "Source", nsURI: "http://test.example/source")
        let targetPackage = EPackage(name: "Target", nsURI: "http://test.example/target")

        return ATLModule(
            name: "TestModule",
            sourceMetamodels: ["Source": sourcePackage],
            targetMetamodels: ["Target": targetPackage]
        )
    }

    // MARK: - Guard Expression Tests

    @Test("Parse matched rule with guard condition")
    func testParseRuleWithGuard() async throws {
        // Given - ATL with guard condition
        let atlContent = """
        module TestGuard;
        create OUT: Target from IN: Source;

        rule FilteredRule {
            from
                s: Source!Element (s.value > 10)
            to
                t: Target!Result (
                    name <- s.name
                )
        }
        """

        // When
        let parser = ATLParser()
        let module = try await parser.parseContent(atlContent)

        // Then
        #expect(module.matchedRules.count == 1)
        let rule = module.matchedRules[0]
        #expect(rule.name == "FilteredRule")

        // Critical: Verify guard is present and parsed
        #expect(rule.guard != nil, "Guard expression should be parsed from source pattern")

        // Verify the guard is a binary operation (s.value > 10)
        guard let guardExpr = rule.guard as? ATLBinaryExpression else {
            Issue.record("Guard should be a binary expression")
            return
        }
        #expect(guardExpr.operator == .greaterThan)
    }

    @Test("Parse matched rule without guard condition")
    func testParseRuleWithoutGuard() async throws {
        // Given - ATL without guard
        let atlContent = """
        module TestNoGuard;
        create OUT: Target from IN: Source;

        rule UnfilteredRule {
            from
                s: Source!Element
            to
                t: Target!Result (
                    name <- s.name
                )
        }
        """

        // When
        let parser = ATLParser()
        let module = try await parser.parseContent(atlContent)

        // Then
        #expect(module.matchedRules.count == 1)
        let rule = module.matchedRules[0]
        #expect(rule.name == "UnfilteredRule")

        // Verify guard is nil when not specified
        #expect(rule.guard == nil, "Guard should be nil when not specified in source pattern")
    }

    @Test("Parse multiple rules with different guards")
    func testParseMultipleRulesWithGuards() async throws {
        // Given - ATL with multiple rules having different guards
        let atlContent = """
        module TestMultipleGuards;
        create OUT: Target from IN: Source;

        rule PositiveFilter {
            from
                s: Source!Element (s.value > 0)
            to
                t: Target!Positive (
                    value <- s.value
                )
        }

        rule NegativeFilter {
            from
                s: Source!Element (s.value < 0)
            to
                t: Target!Negative (
                    value <- s.value
                )
        }

        rule AllElements {
            from
                s: Source!Element
            to
                t: Target!All (
                    value <- s.value
                )
        }
        """

        // When
        let parser = ATLParser()
        let module = try await parser.parseContent(atlContent)

        // Then
        #expect(module.matchedRules.count == 3)

        let positiveRule = module.matchedRules[0]
        #expect(positiveRule.name == "PositiveFilter")
        #expect(positiveRule.guard != nil, "PositiveFilter should have guard")

        let negativeRule = module.matchedRules[1]
        #expect(negativeRule.name == "NegativeFilter")
        #expect(negativeRule.guard != nil, "NegativeFilter should have guard")

        let allRule = module.matchedRules[2]
        #expect(allRule.name == "AllElements")
        #expect(allRule.guard == nil, "AllElements should not have guard")
    }

    @Test("Parse rule with complex guard expression")
    func testParseRuleWithComplexGuard() async throws {
        // Given - ATL with complex guard using NOT and method call
        let atlContent = """
        module TestComplexGuard;
        create OUT: Target from IN: Source;

        helper context Source!Element def: isValid(): Boolean =
            self.value > 0;

        rule FilterInvalid {
            from
                s: Source!Element (not s.isValid())
            to
                t: Target!Invalid (
                    value <- s.value
                )
        }
        """

        // When
        let parser = ATLParser()
        let module = try await parser.parseContent(atlContent)

        // Then
        #expect(module.matchedRules.count == 1)
        let rule = module.matchedRules[0]
        #expect(rule.name == "FilterInvalid")

        // Verify guard is present
        #expect(rule.guard != nil, "Complex guard should be parsed")

        // The guard expression type checking is flexible - just verify it's not nil
        // since the exact expression structure may vary based on parser implementation
    }
}
