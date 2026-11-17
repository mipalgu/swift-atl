//
//  ATLCollectNestedTests.swift
//  ATLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Testing

@testable import ATL

/// Tests for the `collectNested` iterator operation and for unknown iterator operations.
@Suite("ATL collectNested Tests")
@MainActor
struct ATLCollectNestedTests {

    /// Evaluates an expression and renders its value.
    private func text(_ expression: String, options: ATLOptions? = .standard) async throws -> String {
        ATLValueText.render(try await LanguageHarness.evaluate(expression, options: options))
    }

    @Test("collectNested keeps the collections that its body yields")
    func keepsNesting() async throws {
        #expect(
            try await text("Sequence{1, 2, 3}->collectNested(x | Sequence{x, x})")
                == "Sequence{Sequence{1, 1}, Sequence{2, 2}, Sequence{3, 3}}")
        #expect(try await text("Sequence{1, 2, 3}->collectNested(x | Sequence{x, x})->size()") == "3")
    }

    @Test("collect still flattens the collections that its body yields by one level")
    func collectFlattens() async throws {
        #expect(
            try await text("Sequence{1, 2}->collect(x | Sequence{x, x})") == "Sequence{1, 1, 2, 2}")
        #expect(
            try await text("Sequence{1, 2}->collect(x | Sequence{Sequence{x}})")
                == "Sequence{Sequence{1}, Sequence{2}}")
    }

    @Test(
        "collectNested gives a Bag for a Set or a Bag and a Sequence otherwise",
        arguments: [
            ("Sequence{1, 2}->collectNested(x | x * 2)", "Sequence{2, 4}"),
            ("OrderedSet{1, 2}->collectNested(x | x * 2)", "Sequence{2, 4}"),
            ("Set{1}->collectNested(x | Set{x})", "Bag{Set{1}}"),
            ("Bag{1, 1}->collectNested(x | x)", "Bag{1, 1}"),
        ])
    func resultKinds(expression: String, expected: String) async throws {
        #expect(try await text(expression) == expected)
    }

    @Test("collectNested gives a Sequence for a Set with the legacy options")
    func legacyKind() async throws {
        #expect(try await text("Set{1}->collectNested(x | Set{x})", options: nil) == "Sequence{Set{1}}")
    }

    @Test("collectNested leaves out undefined values and treats a single value as a collection")
    func undefinedAndSingleValues() async throws {
        #expect(
            try await text("Sequence{1, 2}->collectNested(x | if x = 1 then OclUndefined else x endif)")
                == "Sequence{2}")
        #expect(try await text("OclUndefined->collectNested(x | x)") == "Sequence{}")
        #expect(try await text("4->collectNested(x | Sequence{x})") == "Sequence{Sequence{4}}")
    }

    @Test("collectNested bodies can use the iterator variables of enclosing iterators")
    func enclosingIterators() async throws {
        #expect(
            try await text("Sequence{1, 2}->collectNested(x | Sequence{3}->collectNested(y | x * y))")
                == "Sequence{Sequence{3}, Sequence{6}}")
    }

    @Test("An unknown iterator operation is reported as unknown, not by its iterator variable")
    func unknownIterator() async throws {
        let message = try #require(
            await thrownDescription {
                try await LanguageHarness.evaluate("Sequence{1, 2}->frobnicate(x | x)", options: .standard)
            })
        #expect(message.contains("frobnicate"))
        #expect(!message.contains("Variable"))
        await #expect {
            try await LanguageHarness.evaluate("Sequence{1}->frobnicate(x | x)", options: .standard)
        } throws: { error in
            guard case ATLExecutionError.unsupportedOperation = error else { return false }
            return true
        }
    }

    @Test("An unknown iterator operation is reported even when a variable of its iterator name exists")
    func unknownIteratorWithOuterVariable() async throws {
        let message = try #require(
            await thrownDescription {
                try await LanguageHarness.evaluate(
                    "let x : Integer = 5 in Sequence{1}->frobnicate(x | x)", options: .standard)
            })
        #expect(message.contains("frobnicate"))
    }
}
