//
//  ATLStringOperationTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import ATL

/// Tests for the ATL string and number operations.
@Suite("ATL String and Number Operation Tests")
@MainActor
struct ATLStringOperationTests {

    @Test(
        "Operations that yield strings",
        arguments: [
            ("'abc'.concat('def')", "abcdef"),
            ("'abcdef'.substring(2, 4)", "bcd"),
            ("'abcdef'.substring(1, 6)", "abcdef"),
            ("'abcdef'.substring(4)", "def"),
            ("'abc'.toUpper()", "ABC"),
            ("'abc'.toUpperCase()", "ABC"),
            ("'ABC'.toLower()", "abc"),
            ("'ABC'.toLowerCase()", "abc"),
            ("'  padded \\n'.trim()", "padded"),
            ("'a-b-c'.replaceAll('-', '+')", "a+b+c"),
            ("'a1b22c'.regexReplaceAll('[0-9]+', '#')", "a#b#c"),
            ("'John Smith'.regexReplaceAll('(\\\\w+) (\\\\w+)', '$2, $1')", "Smith, John"),
            ("'abc'.reverse()", "cba"),
            ("'abc' + 'def'", "abcdef"),
            ("5.toString()", "5"),
            ("#Name.toLower()", "name"),
        ])
    func stringResults(expression: String, expected: String) async throws {
        #expect(try await LanguageHarness.evaluate(expression) as? String == expected)
    }

    @Test(
        "Operations that yield integers",
        arguments: [
            ("'abc'.size()", 3),
            ("'hello'.indexOf('l')", 3),
            ("'hello'.indexOf('z')", 0),
            ("'hello'.lastIndexOf('l')", 4),
            ("'hello'.lastIndexOf('z')", 0),
            ("'42'.toInteger()", 42),
            ("' 42 '.toInteger()", 42),
            ("'-7'.toInteger()", -7),
            ("(-5).abs()", 5),
            ("3.7.floor()", 3),
            ("3.5.round()", 4),
            ("(-3.5).round()", -4),
            ("4.round()", 4),
            ("4.floor()", 4),
            ("3.max(8)", 8),
            ("3.min(8)", 3),
            ("8.max(3)", 8),
            ("2.power(10)", 1024),
        ])
    func integerResults(expression: String, expected: Int) async throws {
        #expect(try await LanguageHarness.evaluate(expression) as? Int == expected)
    }

    @Test("Real conversions and number results")
    func realResults() async throws {
        #expect(try await LanguageHarness.evaluate("'2.5'.toReal()") as? Double == 2.5)
        #expect(try await LanguageHarness.evaluate("(-2.5).abs()") as? Double == 2.5)
        #expect(try await LanguageHarness.evaluate("1.5.max(2)") as? Int == 2)
        #expect(try await LanguageHarness.evaluate("1.5.min(2)") as? Double == 1.5)
    }

    @Test("Failed numeric conversions yield the undefined value")
    func failedConversions() async throws {
        #expect(try await LanguageHarness.evaluate("'abc'.toInteger()") == nil)
        #expect(try await LanguageHarness.evaluate("'abc'.toReal()") == nil)
    }

    @Test(
        "Operations that yield booleans",
        arguments: [
            ("'hello'.startsWith('he')", true), ("'hello'.startsWith('lo')", false),
            ("'hello'.endsWith('lo')", true), ("'hello'.endsWith('he')", false),
            ("''.isEmpty()", true), ("'x'.notEmpty()", true),
        ])
    func booleanResults(expression: String, expected: Bool) async throws {
        #expect(try await LanguageHarness.evaluate(expression) as? Bool == expected)
    }

    @Test("toSequence yields one-character strings")
    func toSequence() async throws {
        #expect(try await LanguageHarness.evaluate("'abc'.toSequence()").strings == ["a", "b", "c"])
    }

    @Test(
        "split uses a regular expression and drops trailing empty parts",
        arguments: [
            ("'a,b,c'.split(',')", ["a", "b", "c"]),
            ("'a1b22c'.split('[0-9]+')", ["a", "b", "c"]),
            ("'a,b,,'.split(',')", ["a", "b"]),
            ("'abc'.split(',')", ["abc"]),
            ("'a,,b'.split(',')", ["a", "", "b"]),
            ("',a'.split(',')", ["", "a"]),
        ])
    func split(expression: String, expected: [String]) async throws {
        #expect(try await LanguageHarness.evaluate(expression).strings == expected)
    }

    @Test(
        "Invalid string operations are reported",
        arguments: [
            "'abc'.substring(0, 2)", "'abc'.substring(2, 9)", "'abc'.substring(3, 2)",
            "'abc'.concat(1)", "'abc'.startsWith(1)", "'abc'.split('(')",
            "'abc'.regexReplaceAll('(', 'x')", "3.max('a')",
        ])
    func invalidOperations(expression: String) async {
        await #expect(throws: ATLExecutionError.self) {
            _ = try await LanguageHarness.evaluate(expression)
        }
    }

    @Test("An empty search string leaves replaceAll unchanged")
    func emptyReplaceTarget() async throws {
        #expect(try await LanguageHarness.evaluate("'abc'.replaceAll('', 'x')") as? String == "abc")
    }
}
