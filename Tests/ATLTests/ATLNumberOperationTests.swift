//
//  ATLNumberOperationTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 20/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ATL

/// Tests for the Integer and Real operations of the ATL standard library.
@Suite("ATL Number Operation Tests")
@MainActor
struct ATLNumberOperationTests {

    @Test(
        "Integer division and truncation yield integers",
        arguments: [
            ("7.div(2)", 3),
            ("(-7).div(2)", -3),
            ("6.div(3)", 2),
            ("0.div(5)", 0),
            ("3.9.longValue()", 3),
            ("(-3.9).longValue()", -3),
            ("4.longValue()", 4),
            ("(-4).longValue()", -4),
        ])
    func integerResults(expression: String, expected: Int) async throws {
        #expect(try await LanguageHarness.evaluate(expression) as? Int == expected, "\(expression)")
    }

    @Test("The div operation agrees with the div operator")
    func divMatchesOperator() async throws {
        let agrees = try await LanguageHarness.evaluate("Sequence{7, -7, 9}->forAll(n | n.div(4) = n div 4)")
        #expect(agrees as? Bool == true)
    }

    @Test(
        "Real functions accept Integer and Real receivers and yield reals",
        arguments: [
            ("4.sqrt()", 2.0),
            ("2.25.sqrt()", 1.5),
            ("0.exp()", 1.0),
            ("1.exp()", exp(1.0)),
            ("1.log()", 0.0),
            ("2.718281828459045.log()", 1.0),
            ("0.sin()", 0.0),
            ("1.5707963267948966.sin()", 1.0),
            ("0.cos()", 1.0),
            ("0.tan()", 0.0),
            ("0.7853981633974483.tan()", 1.0),
            ("1.asin()", Double.pi / 2),
            ("1.acos()", 0.0),
            ("1.atan()", Double.pi / 4),
            ("180.toRadians()", Double.pi),
            ("90.0.toRadians()", Double.pi / 2),
            ("3.141592653589793.toDegrees()", 180.0),
            ("1.toDegrees()", 180.0 / Double.pi),
        ])
    func realFunctions(expression: String, expected: Double) async throws {
        let result = try #require(try await LanguageHarness.evaluate(expression) as? Double)
        #expect(Swift.abs(result - expected) < 1e-12, "\(expression) = \(result)")
    }

    @Test("Real functions outside their domain yield not-a-number as in ATL")
    func outsideDomain() async throws {
        let root = try #require(try await LanguageHarness.evaluate("(-1).sqrt()") as? Double)
        #expect(root.isNaN)
        let arcSine = try #require(try await LanguageHarness.evaluate("2.asin()") as? Double)
        #expect(arcSine.isNaN)
        #expect(try await LanguageHarness.evaluate("0.log()") as? Double == -Double.infinity)
    }

    @Test("Integer division by zero is reported")
    func divisionByZero() async {
        await #expect {
            _ = try await LanguageHarness.evaluate("7.div(0)")
        } throws: { error in
            guard case ATLExecutionError.divisionByZero = error else { return false }
            return true
        }
    }

    @Test(
        "Integer division requires Integer operands",
        arguments: ["7.div('a')", "7.5.div(2)", "7.div(2.0)", "7.div()"])
    func divisionTypeErrors(expression: String) async {
        await #expect(throws: ATLExecutionError.self, "\(expression)") {
            _ = try await LanguageHarness.evaluate(expression)
        }
    }

    @Test(
        "longValue reports reals that are not representable as integers",
        arguments: ["'nan'.toReal().longValue()", "'1e300'.toReal().longValue()"])
    func unrepresentableLongValue(expression: String) async {
        await #expect {
            _ = try await LanguageHarness.evaluate(expression)
        } throws: { error in
            guard case ATLExecutionError.runtimeError(let message) = error else { return false }
            return message.contains("longValue")
        }
    }

    @Test("Real functions are not offered for strings")
    func realFunctionsNeedNumbers() async {
        await #expect(throws: ATLExecutionError.self) {
            _ = try await LanguageHarness.evaluate("'4'.sqrt()")
        }
    }
}
