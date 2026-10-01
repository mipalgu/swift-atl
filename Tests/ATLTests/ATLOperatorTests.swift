//
//  ATLOperatorTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import ATL

/// Tests for the infix operators `implies`, `xor`, `div` and `mod`, and their precedence.
@Suite("ATL Operator Tests")
@MainActor
struct ATLOperatorTests {

    // MARK: - implies

    @Test(
        "implies follows the truth table",
        arguments: [
            ("true implies true", true), ("true implies false", false),
            ("false implies true", true), ("false implies false", true),
        ])
    func impliesTruthTable(expression: String, expected: Bool) async throws {
        #expect(try await LanguageHarness.evaluate(expression) as? Bool == expected)
    }

    @Test("implies does not evaluate its right operand when the left is false")
    func impliesShortCircuits() async throws {
        let result = try await LanguageHarness.evaluate("false implies (1 div 0 = 1)")
        #expect(result as? Bool == true)
    }

    @Test("implies binds more weakly than or, and, and comparison")
    func impliesPrecedence() async throws {
        // (false or true) implies (1 = 2) is false; if or bound weaker than implies it would be true.
        #expect(try await LanguageHarness.evaluate("false or true implies 1 = 2") as? Bool == false)
        #expect(try await LanguageHarness.evaluate("true and false implies false") as? Bool == true)
    }

    // MARK: - xor

    @Test(
        "xor follows the truth table",
        arguments: [
            ("true xor true", false), ("true xor false", true),
            ("false xor true", true), ("false xor false", false),
        ])
    func xorTruthTable(expression: String, expected: Bool) async throws {
        #expect(try await LanguageHarness.evaluate(expression) as? Bool == expected)
    }

    @Test("xor binds like or and more weakly than and")
    func xorPrecedence() async throws {
        // true xor (false and false) = true; (true xor false) and false = false
        #expect(try await LanguageHarness.evaluate("true xor false and false") as? Bool == true)
        #expect(try await LanguageHarness.evaluate("false or true xor true") as? Bool == false)
    }

    // MARK: - Three-valued logic

    @Test(
        "Undefined operands follow three-valued logic",
        arguments: [
            ("OclUndefined and false", false as Bool?), ("false and OclUndefined", false),
            ("OclUndefined and true", nil), ("OclUndefined or true", true),
            ("true or OclUndefined", true), ("OclUndefined or false", nil),
            ("OclUndefined implies true", true), ("OclUndefined implies false", nil),
            ("true implies OclUndefined", nil), ("OclUndefined xor true", nil),
        ])
    func threeValuedLogic(expression: String, expected: Bool?) async throws {
        let result = try await LanguageHarness.evaluate(expression)
        #expect(result as? Bool == expected)
        if expected == nil { #expect(result == nil) }
    }

    @Test("Logical operators reject non-boolean operands")
    func logicalTypeError() async {
        await #expect(throws: ATLExecutionError.self) {
            _ = try await LanguageHarness.evaluate("1 xor true")
        }
        await #expect(throws: ATLExecutionError.self) {
            _ = try await LanguageHarness.evaluate("true and 'x'")
        }
    }

    @Test("A guard on an undefined value short-circuits the dereference")
    func guardPattern() async throws {
        let result = try await LanguageHarness.evaluate(
            "not OclUndefined.oclIsUndefined() and OclUndefined.foo = 1")
        #expect(result as? Bool == false)
    }

    // MARK: - div and mod

    @Test("div is integer division", arguments: [("7 div 2", 3), ("8 div 2", 4), ("-7 div 2", -3), ("1 div 3", 0)])
    func integerDivision(expression: String, expected: Int) async throws {
        #expect(try await LanguageHarness.evaluate(expression) as? Int == expected)
    }

    @Test("mod works infix and as a method", arguments: [("7 mod 3", 1), ("7.mod(3)", 1), ("9 mod 3", 0)])
    func modulo(expression: String, expected: Int) async throws {
        #expect(try await LanguageHarness.evaluate(expression) as? Int == expected)
    }

    @Test("div by zero is an error")
    func divisionByZero() async {
        await #expect {
            _ = try await LanguageHarness.evaluate("1 div 0")
        } throws: { error in
            if case ATLExecutionError.divisionByZero = error { return true }
            return false
        }
    }

    @Test("div requires integers")
    func divTypeError() async {
        await #expect(throws: ATLExecutionError.self) {
            _ = try await LanguageHarness.evaluate("1.5 div 2")
        }
    }

    @Test("div and mod bind like multiplication")
    func multiplicativePrecedence() async throws {
        #expect(try await LanguageHarness.evaluate("1 + 7 div 2 * 2") as? Int == 7)
        #expect(try await LanguageHarness.evaluate("2 * 7 mod 4") as? Int == 2)
        #expect(try await LanguageHarness.evaluate("10 - 7 mod 4") as? Int == 7)
    }

    // MARK: - Round trip through the expression model

    @Test("The new operators survive XMI serialisation")
    func operatorRoundTrip() throws {
        for op in [ATLBinaryOperator.xor, .implies, .integerDivide, .modulo] {
            let original = ATLBinaryExpression(
                left: ATLLiteralExpression(value: 1), operator: op,
                right: ATLLiteralExpression(value: 2))
            let serializer = ATLExpressionXMISerializer()
            let xmi = serializer.serialize(original)
            #expect(xmi.contains("operationName=\"\(op.rawValue)\""))
            #expect(ATLBinaryOperator(rawValue: op.rawValue) == op)
        }
    }
}
