//
//  ATLCollectionTextTests.swift
//  ATLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import ATL

/// Tests that `toString()` writes collections as the console operations and query results do.
@Suite("ATL Collection Text Tests")
@MainActor
struct ATLCollectionTextTests {

    @Test(
        "toString writes every collection kind as a collection literal",
        arguments: [
            ("Sequence{30, 10}.toString()", "Sequence{30, 10}"),
            ("Sequence{30, 10}->toString()", "Sequence{30, 10}"),
            ("Set{1}.toString()", "Set{1}"),
            ("OrderedSet{2, 3}->toString()", "OrderedSet{2, 3}"),
            ("Bag{1, 1}.toString()", "Bag{1, 1}"),
            ("Sequence{}.toString()", "Sequence{}"),
            ("Sequence{'a', 2.5, true, OclUndefined}.toString()", "Sequence{'a', 2.5, true}"),
            (
                "Sequence{Sequence{1, 2}, Set{'a'}, Sequence{}}.toString()",
                "Sequence{Sequence{1, 2}, Set{'a'}, Sequence{}}"
            ),
            ("Sequence{1..3}->collect(i | i * 10)->toString()", "Sequence{10, 20, 30}"),
            ("'Totals: ' + Sequence{1, 2}.toString()", "Totals: Sequence{1, 2}"),
        ])
    func collectionText(expression: String, expected: String) async throws {
        #expect(try await LanguageHarness.evaluate(expression, options: .standard) as? String == expected)
    }

    @Test(
        "toString of a collection is the text that query results and debug show",
        arguments: [
            "Sequence{30, 10}", "Set{'x'}", "OrderedSet{1, 2}", "Bag{2, 2}",
            "Sequence{Sequence{1}, OrderedSet{Set{2}}}",
        ])
    func matchesRendering(literal: String) async throws {
        let value = try await LanguageHarness.evaluate(literal, options: .standard)
        let text = try await LanguageHarness.evaluate("\(literal).toString()", options: .standard)
        #expect(text as? String == ATLValueText.render(value))
    }

    @Test("toString writes a Bag as a Sequence with the legacy options, as it holds one")
    func legacyBag() async throws {
        #expect(try await LanguageHarness.evaluate("Bag{1, 1}.toString()") as? String == "Sequence{1, 1}")
    }

    @Test(
        "toString of a single value is unchanged",
        arguments: [
            ("'abc'.toString()", "abc"), ("5.toString()", "5"), ("2.5.toString()", "2.5"),
            ("true.toString()", "true"),
        ])
    func singleValues(expression: String, expected: String) async throws {
        #expect(try await LanguageHarness.evaluate(expression, options: .standard) as? String == expected)
    }
}
