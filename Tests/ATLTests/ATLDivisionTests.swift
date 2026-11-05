//
//  ATLDivisionTests.swift
//  ATLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import ATL

/// Tests for the `/`, `div` and `mod` operators on Integer and Real operands.
@Suite("ATL Division Tests")
@MainActor
struct ATLDivisionTests {

    // MARK: - Options

    @Test("The standard options divide integers into a Real, the legacy options truncate")
    func presets() {
        #expect(ATLOptions.standard.integerDivision == .real)
        #expect(ATLOptions().integerDivision == .real)
        #expect(ATLOptions.legacy.integerDivision == .truncating)
        #expect(ATLOptions(integerDivision: .truncating).integerDivision == .truncating)
        #expect(ATLOptions(semantics: .standard).integerDivision == .real)
        #expect(ATLOptions(semantics: .legacy).integerDivision == .truncating)
    }

    @Test("The integer division modes are spelt as on a command line")
    func spellings() {
        #expect(ATLIntegerDivision.real.rawValue == "real")
        #expect(ATLIntegerDivision.truncating.rawValue == "truncating")
        #expect(ATLIntegerDivision.allCases == [.real, .truncating])
    }

    // MARK: - Integer / Integer

    @Test(
        "With the standard options, / on two Integers yields a Real",
        arguments: [
            ("7 / 2", 3.5), ("8 / 2", 4.0), ("-7 / 2", -3.5), ("7 / -2", -3.5), ("1 / 4", 0.25),
            ("0 / 5", 0.0),
        ])
    func realQuotient(expression: String, expected: Double) async throws {
        let result = try await LanguageHarness.evaluate(expression, options: .standard)
        #expect(result as? Double == expected, "\(expression)")
    }

    @Test("A Real quotient of two Integers compares with Integers by value")
    func realQuotientComparisons() async throws {
        #expect(try await LanguageHarness.evaluate("8 / 2 = 4", options: .standard) as? Bool == true)
        #expect(try await LanguageHarness.evaluate("7 / 2 > 3", options: .standard) as? Bool == true)
        #expect(try await LanguageHarness.evaluate("(7 / 2).toString()", options: .standard) as? String == "3.5")
        #expect(try await LanguageHarness.evaluate("(7 / 2).floor()", options: .standard) as? Int == 3)
    }

    @Test(
        "With the legacy options, / on two Integers truncates as in swift-atl 0.6",
        arguments: [("7 / 2", 3), ("8 / 2", 4), ("-7 / 2", -3), ("7 / -2", -3), ("1 / 4", 0)])
    func truncatedQuotient(expression: String, expected: Int) async throws {
        #expect(try await LanguageHarness.evaluate(expression, options: .legacy) as? Int == expected)
        #expect(try await LanguageHarness.evaluate(expression) as? Int == expected)
    }

    // MARK: - Real operands

    @Test(
        "/ with a Real operand yields a Real under either options",
        arguments: [
            ("7.0 / 2", 3.5), ("7 / 2.0", 3.5), ("7.5 / 2.5", 3.0), ("-7.0 / 2", -3.5),
            ("1 / 0.5", 2.0),
        ])
    func realOperands(expression: String, expected: Double) async throws {
        for options in [ATLOptions.standard, .legacy] {
            let result = try await LanguageHarness.evaluate(expression, options: options)
            #expect(result as? Double == expected, "\(expression) with \(options)")
        }
    }

    @Test(
        "Division by zero is an error under either options",
        arguments: ["7 / 0", "7.0 / 0", "7 / 0.0", "0 / 0", "7 mod 0", "7.mod(0)", "7 div 0"])
    func divisionByZero(expression: String) async {
        for options in [ATLOptions.standard, .legacy] {
            await #expect {
                _ = try await LanguageHarness.evaluate(expression, options: options)
            } throws: { error in
                if case ATLExecutionError.divisionByZero = error { return true }
                return false
            }
        }
    }

    // MARK: - div and mod

    @Test(
        "div truncates towards zero and mod takes the sign of the dividend",
        arguments: [
            ("7 div 2", 3), ("(-7) div 2", -3), ("7 div (-2)", -3), ("(-7) div (-2)", 3),
            ("7 mod 2", 1), ("(-7) mod 2", -1), ("7 mod (-2)", 1), ("(-7) mod (-2)", -1),
            ("(-7).div(2)", -3), ("(-7).mod(2)", -1), ("7.mod(-2)", 1), ("6 mod 3", 0),
        ])
    func integerDivisionAndRemainder(expression: String, expected: Int) async throws {
        for options in [ATLOptions.standard, .legacy] {
            let result = try await LanguageHarness.evaluate(expression, options: options)
            #expect(result as? Int == expected, "\(expression) with \(options)")
        }
    }

    @Test("div and mod satisfy the OCL identity for every sign")
    func divModIdentity() async throws {
        let identity = """
            Sequence{-7, -6, -1, 0, 1, 6, 7}->forAll(a | Sequence{-3, -2, -1, 1, 2, 3}->forAll(b | \
            a = (a div b) * b + (a mod b)))
            """
        #expect(try await LanguageHarness.evaluate(identity, options: .standard) as? Bool == true)
    }

    @Test("div and mod require Integer operands", arguments: ["7.5 mod 2", "7 mod 2.0", "7.5 div 2", "7 div 2.0"])
    func integerOperandsRequired(expression: String) async {
        await #expect(throws: ATLExecutionError.self) {
            _ = try await LanguageHarness.evaluate(expression, options: .standard)
        }
    }

    // MARK: - Virtual machine

    @Test("A virtual machine created with options divides as they select")
    func virtualMachineOptions() async throws {
        let unit = try await ATLParser(options: .standard).parseContent("query Q = 7 / 2;")
        let standard = ATLVirtualMachine(module: unit, options: .standard)
        #expect(standard.options == .standard)
        #expect(try await standard.evaluateQuery(sources: [:]) as? Double == 3.5)
        let legacy = ATLVirtualMachine(module: unit, options: .legacy)
        #expect(try await legacy.evaluateQuery(sources: [:]) as? Int == 3)
    }

    @Test("A virtual machine created without options truncates as in swift-atl 0.6")
    func virtualMachineWithoutOptions() async throws {
        let unit = try await ATLParser(options: .standard).parseContent("query Q = 7 / 2;")
        let machine = ATLVirtualMachine(module: unit)
        #expect(machine.options == .legacy)
        #expect(try await machine.evaluateQuery(sources: [:]) as? Int == 3)
    }

    @Test("An execution context created without options truncates as in swift-atl 0.6")
    func contextDefault() async throws {
        let harness = try await LanguageHarness.make(expression: "7 / 2")
        #expect(harness.context.options == .legacy)
        let module = harness.module
        let context = ATLExecutionContext(module: module, executionEngine: ECoreExecutionEngine(models: [:]))
        #expect(context.options == .legacy)
        context.options = .standard
        let quotient = ATLBinaryExpression(
            left: ATLLiteralExpression(value: 7), operator: .divide, right: ATLLiteralExpression(value: 2))
        #expect(try await quotient.evaluate(in: context) as? Double == 3.5)
    }
}
