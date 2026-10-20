//
//  ATLCollectionOperationTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import OrderedCollections
import Testing

@testable import ATL

/// Tests for the OCL collection library as implemented by ATL.
@Suite("ATL Collection Operation Tests")
@MainActor
struct ATLCollectionOperationTests {

    // MARK: - Integer-valued results

    @Test(
        "Operations that yield integers",
        arguments: [
            ("Sequence{1, 2, 3}->sum()", 6),
            ("Sequence{}->sum()", 0),
            ("Sequence{1, 2, 2, 3}->count(2)", 2),
            ("Sequence{1, 2, 3}->count(9)", 0),
            ("Sequence{10, 20, 30}->at(2)", 20),
            ("Sequence{10, 20, 30}->at(1)", 10),
            ("Sequence{10, 20, 30}->at(3)", 30),
            ("Sequence{10, 20, 30}->indexOf(30)", 3),
            ("Sequence{10, 20, 30}->indexOf(99)", 0),
            ("Sequence{1, 2, 1}->lastIndexOf(1)", 3),
            ("Sequence{1, 2, 3}->size()", 3),
            ("Sequence{4, 9, 2}->max()", 9),
            ("Sequence{4, 9, 2}->min()", 2),
            ("Sequence{1, 2, 3, 4}->select(e | e > 2)->size()", 2),
            ("OrderedSet{5, 6}->at(2)", 6),
            ("Sequence{1, 2, 3}->collect(e | e * e)->sum()", 14),
            ("Sequence{Sequence{1, 2}, Sequence{3}}->collect(e | e)->size()", 3),
        ])
    func integerResults(expression: String, expected: Int) async throws {
        #expect(try await LanguageHarness.evaluate(expression) as? Int == expected)
    }

    @Test("sum of reals and mixed numbers is real")
    func realSum() async throws {
        #expect(try await LanguageHarness.evaluate("Sequence{1.5, 2.5}->sum()") as? Double == 4.0)
        #expect(try await LanguageHarness.evaluate("Sequence{1, 2.5}->sum()") as? Double == 3.5)
    }

    @Test("sum rejects non-numeric elements")
    func sumTypeError() async {
        await #expect(throws: ATLExecutionError.self) {
            _ = try await LanguageHarness.evaluate("Sequence{'a'}->sum()")
        }
    }

    // MARK: - Undefined results

    @Test(
        "Out-of-range and empty accesses yield the undefined value",
        arguments: [
            "Sequence{}->first()", "Sequence{}->last()", "Sequence{1}->at(2)", "Sequence{1}->at(0)",
            "Sequence{}->any(e | e > 1)", "Sequence{1}->any(e | e > 1)", "Sequence{}->max()",
            "OrderedSet{}->first()",
        ])
    func undefinedResults(expression: String) async throws {
        #expect(try await LanguageHarness.evaluate(expression) == nil)
    }

    @Test("first and last return the end elements")
    func firstAndLast() async throws {
        #expect(try await LanguageHarness.evaluate("Sequence{7, 8, 9}->first()") as? Int == 7)
        #expect(try await LanguageHarness.evaluate("Sequence{7, 8, 9}->last()") as? Int == 9)
    }

    @Test("any returns the first matching element")
    func anyOperation() async throws {
        #expect(try await LanguageHarness.evaluate("Sequence{1, 5, 9}->any(e | e > 3)") as? Int == 5)
    }

    // MARK: - Collection-valued results

    @Test(
        "Operations that yield integer collections",
        arguments: [
            ("Sequence{1, 2}->append(3)", [1, 2, 3]),
            ("Sequence{1, 2}->prepend(0)", [0, 1, 2]),
            ("Sequence{1, 2}->append(1)", [1, 2, 1]),
            ("Sequence{1, 3}->insertAt(2, 2)", [1, 2, 3]),
            ("Sequence{2, 3}->insertAt(1, 1)", [1, 2, 3]),
            ("Sequence{1, 2}->insertAt(3, 3)", [1, 2, 3]),
            ("Sequence{1, 2, 3, 4, 5}->subSequence(2, 4)", [2, 3, 4]),
            ("Sequence{1, 2, 3}->subSequence(1, 3)", [1, 2, 3]),
            ("Sequence{1, 2}->including(3)", [1, 2, 3]),
            ("Sequence{1, 2, 1}->including(1)", [1, 2, 1, 1]),
            ("Sequence{1, 2, 1, 3}->excluding(1)", [2, 3]),
            ("Sequence{1, 2}->union(Sequence{2, 3})", [1, 2, 2, 3]),
            ("Sequence{1, 2, 3}->intersection(Sequence{2, 3, 4})", [2, 3]),
            ("Sequence{3, 1, 2}->reverse()", [2, 1, 3]),
            ("Sequence{3, 1, 2}->sortedBy(e | e)", [1, 2, 3]),
            ("Sequence{3, 1, 2}->sortedBy(e | -e)", [3, 2, 1]),
            ("Sequence{1, 2, 3, 4}->select(e | e mod 2 = 0)", [2, 4]),
            ("Sequence{1, 2, 3, 4}->reject(e | e mod 2 = 0)", [1, 3]),
            ("Sequence{1, 2, 3}->collect(e | e + 1)", [2, 3, 4]),
            ("Sequence{1, 2, 3}->asSequence()", [1, 2, 3]),
            ("Sequence{1, 1, 2}->asSet()", [1, 2]),
            ("Sequence{3, 1, 3, 2}->asOrderedSet()", [3, 1, 2]),
            ("Sequence{1, 1, 2}->asBag()", [1, 1, 2]),
            ("Sequence{Sequence{1}, Sequence{Sequence{2}, 3}}->flatten()", [1, 2, 3]),
            ("Sequence{1, 2}->including(OclUndefined)", [1, 2]),
            ("Sequence{1, 2}->append(OclUndefined)", [1, 2]),
        ])
    func integerCollections(expression: String, expected: [Int]) async throws {
        #expect(try await LanguageHarness.evaluate(expression).integers == expected)
    }

    @Test("sortedBy sorts strings lexicographically and keeps ties stable")
    func sortedByStrings() async throws {
        let sorted = try await LanguageHarness.evaluate("Sequence{'pear', 'fig', 'apple'}->sortedBy(s | s)")
        #expect(sorted.strings == ["apple", "fig", "pear"])
        let byLength = try await LanguageHarness.evaluate(
            "Sequence{'bb', 'a', 'cc', 'd'}->sortedBy(s | s.size())")
        #expect(byLength.strings == ["a", "d", "bb", "cc"])
    }

    // MARK: - Ordered sets and sets

    @Test(
        "Set and ordered set operations keep elements unique",
        arguments: [
            ("OrderedSet{1, 2}->union(OrderedSet{2, 3})", [1, 2, 3]),
            ("OrderedSet{1, 2}->including(2)", [1, 2]),
            ("OrderedSet{1, 2}->including(3)", [1, 2, 3]),
            ("OrderedSet{1, 2, 3}->append(1)", [2, 3, 1]),
            ("OrderedSet{1, 2, 3}->prepend(3)", [3, 1, 2]),
            ("OrderedSet{1, 2, 3}->excluding(2)", [1, 3]),
            ("OrderedSet{1, 2, 3}->insertAt(1, 3)", [3, 1, 2]),
            ("OrderedSet{1, 2, 3, 4}->subOrderedSet(2, 3)", [2, 3]),
            ("OrderedSet{1, 2, 3}->reverse()", [3, 2, 1]),
            ("OrderedSet{3, 1, 2}->sortedBy(e | e)", [1, 2, 3]),
            ("Set{1, 2}->union(Set{2, 3})", [1, 2, 3]),
            ("Set{1, 2}->including(2)", [1, 2]),
            ("Set{1, 2, 3}->intersection(Set{2, 3, 4})", [2, 3]),
            ("Set{1, 2, 3}->select(e | e > 1)", [2, 3]),
        ])
    func uniqueCollections(expression: String, expected: [Int]) async throws {
        #expect(try await LanguageHarness.evaluate(expression).integers == expected)
    }

    @Test("Ordered set results keep their kind through chained operations")
    func kindIsPreserved() async throws {
        let result = try await LanguageHarness.evaluate(
            "OrderedSet{1, 2}->union(OrderedSet{2, 3})->including(3)->union(OrderedSet{1, 4})")
        #expect(result.integers == [1, 2, 3, 4])
        #expect((result as? ATLCollectionValue)?.kind == .orderedSet)
    }

    @Test("asOrderedSet yields a set-kind value whose union stays unique")
    func asOrderedSetUnion() async throws {
        let result = try await LanguageHarness.evaluate(
            "Sequence{1, 2, 2}->asOrderedSet()->union(Sequence{2, 3}->asOrderedSet())")
        #expect(result.integers == [1, 2, 3])
    }

    // MARK: - Bulk inclusion and exclusion

    @Test(
        "Bulk operations add and remove several elements",
        arguments: [
            ("Set{1, 2, 3}->symmetricDifference(Set{2, 3, 4})", [1, 4]),
            ("Set{1, 2}->symmetricDifference(Set{1, 2})", []),
            ("Set{1, 2}->symmetricDifference(Set{})", [1, 2]),
            ("Sequence{1, 2, 2}->symmetricDifference(Sequence{2, 5, 5})", [1, 5]),
            ("Sequence{1, 2}->includingAll(Sequence{2, 3})", [1, 2, 2, 3]),
            ("Sequence{1}->includingAll(OclUndefined)", [1]),
            ("OrderedSet{1, 2}->includingAll(Sequence{2, 3, 3})", [1, 2, 3]),
            ("Set{1, 2}->includingAll(Set{2, 3})", [1, 2, 3]),
            ("Sequence{1, 4}->includingAll(Sequence{2, 3}, 2)", [1, 2, 3, 4]),
            ("Sequence{2}->includingAll(Sequence{1}, 1)", [1, 2]),
            ("Sequence{1, 2}->includingAll(Sequence{3}, 3)", [1, 2, 3]),
            ("OrderedSet{1, 4}->includingAll(Sequence{4, 2, 2}, 1)", [2, 1, 4]),
            ("Sequence{0}->includingRange(1, 3)", [0, 1, 2, 3]),
            ("Sequence{}->includingRange(2, 2)", [2]),
            ("Sequence{9}->includingRange(3, 1)", [9]),
            ("OrderedSet{2}->includingRange(1, 3)", [2, 1, 3]),
            ("Sequence{1, 2, 1, 3, 2}->excludingAll(Sequence{1, 2})", [3]),
            ("OrderedSet{1, 2, 3}->excludingAll(Set{2, 9})", [1, 3]),
            ("Sequence{1, 2}->excludingAll(OclUndefined)", [1, 2]),
        ])
    func bulkOperations(expression: String, expected: [Int]) async throws {
        #expect(try await LanguageHarness.evaluate(expression).integers == expected, "\(expression)")
    }

    @Test("Bulk operations keep the kind of their receiver")
    func bulkOperationKinds() async throws {
        let kinds: [(String, ATLCollectionKind)] = [
            ("Set{1}->symmetricDifference(Set{2})", .set),
            ("OrderedSet{1}->symmetricDifference(Set{2})", .orderedSet),
            ("Sequence{1}->symmetricDifference(Sequence{2})", .set),
            ("OrderedSet{1}->includingAll(Sequence{2})", .orderedSet),
            ("OrderedSet{1}->includingAll(Sequence{2}, 1)", .orderedSet),
            ("OrderedSet{1}->includingRange(2, 3)", .orderedSet),
            ("Set{1, 2}->excludingAll(Set{2})", .set),
        ]
        for (expression, kind) in kinds {
            let result = try await LanguageHarness.evaluate(expression)
            #expect((result as? ATLCollectionValue)?.kind == kind, "\(expression)")
        }
        let sequence = try await LanguageHarness.evaluate("Sequence{1}->includingAll(Sequence{1})")
        #expect(sequence is EcoreValueArray)
    }

    @Test("includingRange accepts ranges up to the maximum length")
    func includingRangeAtMaximum() async throws {
        let maximum = ATLBuiltinOperations.maximumRangeLength
        let sequence = try await LanguageHarness.evaluate(
            "Sequence{}->includingRange(1, \(maximum))->size()")
        #expect(sequence as? Int == maximum)
    }

    @Test("includingRange skips integers a unique collection already holds, compared numerically")
    func includingRangeIntoUniqueCollection() async throws {
        let result = try await LanguageHarness.evaluate("OrderedSet{1, 2.0, 'a'}->includingRange(1, 4)")
        let elements = try #require(result.collectionElements)
        #expect(elements.count == 5)
        #expect(elements.dropFirst(3).compactMap { $0 as? Int } == [3, 4])
        #expect((result as? ATLCollectionValue)?.kind == .orderedSet)
    }

    @Test(
        "includingRange rejects ranges longer than the maximum length",
        arguments: [
            (1, ATLBuiltinOperations.maximumRangeLength + 1), (1, 1_000_000_000), (Int.min, Int.max),
        ])
    func includingRangeTooLong(lower: Int, upper: Int) async throws {
        let harness = try await LanguageHarness.make(expression: "Sequence{}->includingRange(lo, hi)")
        harness.context.setVariable("lo", value: lower)
        harness.context.setVariable("hi", value: upper)
        await #expect {
            _ = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        } throws: { error in
            guard case ATLExecutionError.runtimeError(let message) = error else { return false }
            return message.contains("includingRange")
        }
    }

    @Test(
        "Bulk operations reject invalid positions and bounds",
        arguments: [
            "Sequence{1}->includingAll(Sequence{2}, 3)",
            "Sequence{1}->includingAll(Sequence{2}, 0)",
            "Sequence{1}->includingAll(Sequence{2}, 'x')",
            "Sequence{}->includingRange('a', 2)",
            "Sequence{}->includingRange(1, 2.5)",
        ])
    func bulkOperationErrors(expression: String) async {
        await #expect(throws: ATLExecutionError.self, "\(expression)") {
            _ = try await LanguageHarness.evaluate(expression)
        }
    }

    // MARK: - Boolean results

    @Test(
        "Operations that yield booleans",
        arguments: [
            ("Sequence{1, 2, 3}->includes(2)", true),
            ("Sequence{1, 2, 3}->includes(9)", false),
            ("Sequence{1, 2, 3}->excludes(9)", true),
            ("Sequence{1, 2, 3}->includesAll(Sequence{1, 3})", true),
            ("Sequence{1, 2, 3}->includesAll(Sequence{1, 9})", false),
            ("Sequence{1, 2, 3}->excludesAll(Sequence{8, 9})", true),
            ("Sequence{1, 2, 3}->exists(e | e > 2)", true),
            ("Sequence{1, 2, 3}->exists(e | e > 3)", false),
            ("Sequence{}->exists(e | true)", false),
            ("Sequence{1, 2, 3}->forAll(e | e > 0)", true),
            ("Sequence{1, 2, 3}->forAll(e | e > 1)", false),
            ("Sequence{}->forAll(e | false)", true),
            ("Sequence{1, 2, 3}->one(e | e > 2)", true),
            ("Sequence{1, 2, 3}->one(e | e > 1)", false),
            ("Sequence{1, 2, 3}->isUnique(e | e)", true),
            ("Sequence{1, 2, 3}->isUnique(e | e mod 2)", false),
            ("Sequence{1, 2, 3}->isEmpty()", false),
            ("Sequence{}->isEmpty()", true),
            ("Sequence{1}->notEmpty()", true),
            ("Sequence{1, 2}->exists(a, b | a + b = 3)", true),
            ("Sequence{1, 2}->exists(a, b | a = b)", true),
            ("Sequence{1, 2}->forAll(a, b | a + b > 1)", true),
            ("Sequence{1, 2}->forAll(a, b | a < b)", false),
            ("Sequence{1, 2, 3}->exists(e : Integer | e = 2)", true),
        ])
    func booleanResults(expression: String, expected: Bool) async throws {
        #expect(try await LanguageHarness.evaluate(expression) as? Bool == expected)
    }

    // MARK: - Objects

    @Test("Operations compare model objects by identity")
    func objectIdentity() async throws {
        let fixture = ShapeFixture()
        let first = fixture.make(fixture.circle, ["name": "a"])
        let second = fixture.make(fixture.circle, ["name": "a"])
        let harness = try await LanguageHarness.make(
            expression: "Sequence{p, q}->includes(p)", fixture: fixture)
        harness.context.setVariable("p", value: first)
        harness.context.setVariable("q", value: second)

        let includes = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        #expect(includes as? Bool == true)

        let count = try await ATLMethodCallExpression(
            receiver: ATLCollectionLiteralExpression(
                collectionType: "Sequence",
                elements: [
                    ATLVariableExpression(name: "p"), ATLVariableExpression(name: "q"),
                    ATLVariableExpression(name: "p"),
                ]),
            methodName: "count", arguments: [ATLVariableExpression(name: "p")]
        ).evaluate(in: harness.context)
        #expect(count as? Int == 2)

        let asSet = try await ATLMethodCallExpression(
            receiver: ATLCollectionLiteralExpression(
                collectionType: "Sequence",
                elements: [
                    ATLVariableExpression(name: "p"), ATLVariableExpression(name: "q"),
                    ATLVariableExpression(name: "p"),
                ]),
            methodName: "asSet", arguments: []
        ).evaluate(in: harness.context)
        #expect(asSet.collectionElements?.count == 2)
    }

    @Test("Iterators work over objects and navigate their features")
    func iteratorsOverObjects() async throws {
        let fixture = ShapeFixture()
        let objects = [
            fixture.make(fixture.circle, ["name": "b", "radius": 2.0]),
            fixture.make(fixture.circle, ["name": "a", "radius": 1.0]),
            fixture.make(fixture.square, ["name": "c", "side": 3.0]),
        ]
        let harness = try await LanguageHarness.make(
            expression: "shapes->sortedBy(s | s.name)->collect(s | s.name)", fixture: fixture)
        harness.context.setVariable("shapes", value: EcoreValueArray(objects))
        let names = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        #expect(names.strings == ["a", "b", "c"])
    }

    // MARK: - Implicit collection conversion

    @Test("Single values act as one-element collections and undefined as empty")
    func implicitConversion() async throws {
        #expect(try await LanguageHarness.evaluate("5->size()") as? Int == 1)
        #expect(try await LanguageHarness.evaluate("OclUndefined->size()") as? Int == 0)
        #expect(try await LanguageHarness.evaluate("OclUndefined->isEmpty()") as? Bool == true)
        #expect(try await LanguageHarness.evaluate("5->including(6)").integers == [5, 6])
        #expect(try await LanguageHarness.evaluate("OclUndefined->asSequence()").integers == [])
        #expect(try await LanguageHarness.evaluate("5->asSet()").integers == [5])
        #expect(try await LanguageHarness.evaluate("5->first()") as? Int == 5)
    }

    // MARK: - Errors

    @Test(
        "Invalid bounds are reported",
        arguments: [
            "Sequence{1, 2}->subSequence(0, 1)", "Sequence{1, 2}->subSequence(2, 1)",
            "Sequence{1, 2}->subSequence(1, 3)", "Sequence{1, 2}->insertAt(4, 9)",
            "Sequence{1, 2}->at('x')",
        ])
    func invalidBounds(expression: String) async {
        await #expect(throws: ATLExecutionError.self) {
            _ = try await LanguageHarness.evaluate(expression)
        }
    }

    @Test("Operations called with unsupported argument counts are not silently accepted")
    func unsupportedArity() async {
        await #expect(throws: ATLExecutionError.self) {
            _ = try await LanguageHarness.evaluate("Sequence{1, 2}->first(1)")
        }
    }

    @Test("max and min reject non-numeric elements")
    func extremeTypeError() async {
        await #expect(throws: ATLExecutionError.self) {
            _ = try await LanguageHarness.evaluate("Sequence{'a', 'b'}->max()")
        }
    }

    @Test("collect drops undefined results")
    func collectDropsUndefined() async throws {
        let result = try await LanguageHarness.evaluate(
            "Sequence{1, 2, 3}->collect(e | if e = 2 then OclUndefined else e endif)")
        #expect(result.integers == [1, 3])
    }

    @Test("Collect on sets and bags yields bags, on ordered collections sequences")
    func collectKinds() async throws {
        #expect(try await LanguageHarness.evaluate("Set{1, 2}->collect(e | 7)").integers == [7, 7])
        #expect(try await LanguageHarness.evaluate("OrderedSet{1, 2}->collect(e | 7)").integers == [7, 7])
    }

    @Test("Model objects never equal plain values")
    func objectsDifferFromValues() async throws {
        let fixture = ShapeFixture()
        let harness = try await LanguageHarness.make(expression: "obj = 1 or 1 = obj", fixture: fixture)
        harness.context.setVariable("obj", value: fixture.make(fixture.circle))
        let result = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        #expect(result as? Bool == false)
    }

    // MARK: - Iterate and the legacy fallbacks

    @Test("iterate sums the integer elements of a literal")
    func iterateOverLiteral() async throws {
        let result = try await LanguageHarness.evaluate(
            "Sequence{1, 2, 3}->iterate(n; acc : Integer = 0 | acc + n)")
        #expect(result as? Int == 6)
    }

    @Test("iterate works over sets and ordered sets")
    func iterateOverSet() async throws {
        let result = try await LanguageHarness.evaluate(
            "OrderedSet{1, 2, 2}->iterate(n; acc : Integer = 0 | acc + n)")
        #expect(result as? Int == 3)
    }

    @Test("Lambda parameters with several variables compare structurally")
    func multiParameterLambda() {
        let one = ATLLambdaExpression(parameters: ["a", "b"], body: ATLLiteralExpression(value: true))
        let same = ATLLambdaExpression(parameters: ["a", "b"], body: ATLLiteralExpression(value: true))
        let different = ATLLambdaExpression(parameter: "a", body: ATLLiteralExpression(value: true))
        #expect(one == same)
        #expect(one != different)
        #expect(one.parameters == ["a", "b"])
        #expect(one.hashValue == same.hashValue)
    }

    // MARK: - Collection values

    @Test("Collection values compare and convert")
    func collectionValue() {
        let orderedSet = ATLCollectionValue(kind: .orderedSet, values: [1, 2, 1])
        #expect(orderedSet.values.count == 2)
        #expect(orderedSet.asEcoreValueArray.values.count == 2)
        #expect(orderedSet == ATLCollectionValue(kind: .orderedSet, values: [1, 2]))
        #expect(orderedSet != ATLCollectionValue(kind: .orderedSet, values: [2, 1]))
        #expect(ATLCollectionValue(kind: .set, values: [1, 2]) == ATLCollectionValue(kind: .set, values: [2, 1]))
        #expect(orderedSet.hashValue == ATLCollectionValue(kind: .orderedSet, values: [1, 2]).hashValue)
        let bag = ATLCollectionValue(kind: .bag, values: [1, 1])
        #expect(bag.values.count == 2)
    }

    @Test("Values compare numerically and order consistently")
    func valueSemantics() {
        #expect(ATLValues.areEqual(1, 1.0))
        #expect(ATLValues.areEqual(2.0, 2))
        #expect(!ATLValues.areEqual(1, "1"))
        #expect(!ATLValues.areEqual(nil, 1))
        #expect(ATLValues.isOrderedBefore(1, 2.5))
        #expect(ATLValues.isOrderedBefore(1.5, 2))
        #expect(ATLValues.isOrderedBefore(false, true))
        #expect(ATLValues.isOrderedBefore(nil, 1))
        #expect(!ATLValues.isOrderedBefore(1, nil))
        #expect(!ATLValues.isOrderedBefore(nil, nil))
        #expect(ATLValues.isOrderedBefore("a", "b"))
        #expect(ATLValues.removingDuplicates([1, 2, 1, 3, 2]).count == 3)
    }
}
