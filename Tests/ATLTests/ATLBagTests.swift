//
//  ATLBagTests.swift
//  ATLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ATL

/// Tests for Bag values: unordered collections that keep duplicates.
///
/// With ``ATLOptions/standard``, a Bag is a collection kind of its own, as in OCL
/// and the Eclipse ATL EMFTVM: `Bag{...}` literals, `asBag()` and the operations
/// whose result is a Bag produce Bag values that keep their duplicates, report
/// their type as `Bag` and compare by element counts regardless of order. With
/// ``ATLOptions/legacy``, a Bag is a Sequence, as in swift-atl 0.6.
@Suite("ATL Bag Tests")
@MainActor
struct ATLBagTests {

    /// Evaluates an expression with the standard options.
    ///
    /// - Parameters:
    ///   - expression: The expression to evaluate.
    ///   - declarations: The helper declarations of the module.
    /// - Returns: The value of the expression.
    private func evaluate(_ expression: String, declarations: String = "") async throws
        -> (any EcoreValue)?
    {
        try await LanguageHarness.evaluate(expression, declarations: declarations, options: .standard)
    }

    /// Evaluates an expression with the legacy options of swift-atl 0.6.
    ///
    /// - Parameters:
    ///   - expression: The expression to evaluate.
    ///   - declarations: The helper declarations of the module.
    /// - Returns: The value of the expression.
    private func evaluateLegacy(_ expression: String, declarations: String = "") async throws
        -> (any EcoreValue)?
    {
        try await LanguageHarness.evaluate(expression, declarations: declarations, options: .legacy)
    }

    // MARK: - Options

    @Test("The standard options keep Bags distinct and the legacy options make them Sequences")
    func options() {
        #expect(ATLOptions.standard.bagRepresentation == .bag)
        #expect(ATLOptions().bagRepresentation == .bag)
        #expect(ATLOptions.legacy.bagRepresentation == .sequence)
        #expect(ATLOptions(bagRepresentation: .sequence).bagRepresentation == .sequence)
        #expect(ATLOptions(semantics: .standard).bagRepresentation == .bag)
        #expect(ATLOptions(semantics: .legacy).bagRepresentation == .sequence)
        #expect(ATLOptions(bagRepresentation: .sequence) != .standard)
    }

    @Test("Each Bag representation is spelt as on a command line")
    func spellings() {
        #expect(ATLBagRepresentation.allCases == [.bag, .sequence])
        #expect(ATLBagRepresentation.allCases.map(\.rawValue) == ["bag", "sequence"])
        #expect(ATLBagRepresentation(rawValue: "sequence") == .sequence)
    }

    @Test("The legacy representation turns the Bag kind into the Sequence kind only")
    func representationKinds() {
        #expect(ATLBagRepresentation.bag.kind(for: .bag) == .bag)
        #expect(ATLBagRepresentation.sequence.kind(for: .bag) == .sequence)
        for kind in [ATLCollectionKind.sequence, .set, .orderedSet] {
            #expect(ATLBagRepresentation.sequence.kind(for: kind) == kind)
            #expect(ATLBagRepresentation.bag.kind(for: kind) == kind)
        }
    }

    // MARK: - Representation

    @Test("A Bag literal is a Bag that keeps its duplicates in the order written")
    func literal() async throws {
        let value = try await evaluate("Bag{2, 1, 2}")
        #expect(ATLCollections.kind(of: value) == .bag)
        #expect(value.integers == [2, 1, 2])
    }

    @Test("An empty Bag literal is an empty Bag")
    func emptyLiteral() async throws {
        let value = try await evaluate("Bag{}")
        #expect(ATLCollections.kind(of: value) == .bag)
        #expect(value.collectionElements?.isEmpty == true)
    }

    @Test("A Bag value from code is recognised by its kind")
    func bagFromCode() {
        let bag = EcoreValueArray([1, 1], kind: .bag)
        #expect(ATLCollections.kind(of: bag) == .bag)
        #expect(ATLCollections.kind(of: EcoreValueArray([1, 1])) == .sequence)
        #expect(ATLCollections.elements(of: bag).count == 2)
    }

    @Test("A Bag range literal is a Bag")
    func rangeLiteral() async throws {
        let value = try await evaluate("Bag{1..2, 2}")
        #expect(ATLCollections.kind(of: value) == .bag)
        #expect(value.integers == [1, 2, 2])
    }

    // MARK: - Operation results

    @Test(
        "Operations give the collection kind that the Eclipse ATL EMFTVM gives",
        arguments: [
            ("Sequence{1, 1, 2}->asBag()", ATLCollectionKind.bag, [1, 1, 2]),
            ("Set{1, 2}->asBag()", .bag, [1, 2]),
            ("Bag{1, 2}->asBag()", .bag, [1, 2]),
            ("Bag{1, 2}->including(1)", .bag, [1, 2, 1]),
            ("Bag{1, 2, 1}->excluding(1)", .bag, [2]),
            ("Bag{1}->union(Bag{1, 2})", .bag, [1, 1, 2]),
            ("Bag{1}->union(Set{1, 2})", .bag, [1, 1, 2]),
            ("Set{1}->union(Bag{1, 1})", .bag, [1, 1, 1]),
            ("OrderedSet{1}->union(Bag{2, 2})", .bag, [1, 2, 2]),
            ("Bag{1, 2, 3, 2}->select(e | e > 1)", .bag, [2, 3, 2]),
            ("Bag{1, 2, 3, 2}->reject(e | e > 2)", .bag, [1, 2, 2]),
            ("Bag{1, 2, 3}->collect(e | e mod 2)", .bag, [1, 0, 1]),
            ("Set{1, 3}->collect(e | e mod 2)", .bag, [1, 1]),
            ("OrderedSet{1, 3}->collect(e | e mod 2)", .sequence, [1, 1]),
            ("Sequence{1, 3}->collect(e | e mod 2)", .sequence, [1, 1]),
            ("Bag{Bag{1}, Sequence{1, 2}}->flatten()", .bag, [1, 1, 2]),
            ("Bag{3, 1, 2}->sortedBy(e | e)", .sequence, [1, 2, 3]),
            ("Bag{2, 1, 2}->asSequence()", .sequence, [2, 1, 2]),
            ("Bag{2, 1, 2}->asOrderedSet()", .orderedSet, [2, 1]),
            ("Bag{2, 1, 2}->asSet()", .set, [2, 1]),
            ("Bag{1, 2}->includingAll(Sequence{2, 3})", .bag, [1, 2, 2, 3]),
            ("Bag{1, 2, 2, 3}->excludingAll(Set{2})", .bag, [1, 3]),
        ])
    func operationKinds(expression: String, kind: ATLCollectionKind, expected: [Int]) async throws {
        let value = try await evaluate(expression)
        #expect(ATLCollections.kind(of: value) == kind)
        #expect(value.integers == expected)
    }

    @Test(
        "The intersection of a Bag holds each element as often as the operand that holds it least",
        arguments: [
            ("Bag{1, 1, 2, 3}->intersection(Bag{1, 3, 3, 4})", ATLCollectionKind.bag, [1, 3]),
            ("Bag{1, 1, 2}->intersection(Bag{2, 1, 1, 1})", .bag, [1, 1, 2]),
            ("Bag{1, 1, 2}->intersection(Set{1, 3})", .set, [1]),
            ("Set{1, 2}->intersection(Bag{2, 2, 3})", .set, [2]),
        ])
    func intersection(expression: String, kind: ATLCollectionKind, expected: [Int]) async throws {
        let value = try await evaluate(expression)
        #expect(ATLCollections.kind(of: value) == kind)
        #expect(value.integers?.sorted() == expected)
    }

    @Test(
        "Queries treat a Bag as a collection with duplicates",
        arguments: [
            ("Bag{1, 2, 1}->size()", 3),
            ("Bag{1, 2, 1}->count(1)", 2),
            ("Bag{1, 2, 1}->sum()", 4),
            ("Bag{1, 2, 1}->iterate(e; acc : Integer = 0 | acc + e)", 4),
            ("Bag{3, 1, 2}->first()", 3),
            ("Bag{3, 1, 2}->last()", 2),
        ])
    func queries(expression: String, expected: Int) async throws {
        #expect(try await evaluate(expression) as? Int == expected)
    }

    @Test("Iterator and query operations see every element of a Bag")
    func iteratedByOperations() async throws {
        #expect(try await evaluate("Bag{1, 2, 1}->includes(2)") as? Bool == true)
        #expect(try await evaluate("Bag{1, 2, 1}->forAll(e | e < 3)") as? Bool == true)
        #expect(try await evaluate("Bag{1, 2, 1}->exists(e | e = 2)") as? Bool == true)
        #expect(try await evaluate("Bag{1, 2, 1}->isEmpty()") as? Bool == false)
        #expect(try await evaluate("Bag{1, 2, 1}->isUnique(e | e)") as? Bool == false)
    }

    // MARK: - Conversions

    @Test(
        "Conversions to a Set or an OrderedSet give that kind for every receiver",
        arguments: [
            ("Sequence{1, 1, 2}->asSet()", ATLCollectionKind.set, [1, 2]),
            ("Bag{1, 1, 2}->asSet()", .set, [1, 2]),
            ("OrderedSet{2, 1}->asSet()", .set, [2, 1]),
            ("Set{1, 2}->asSet()", .set, [1, 2]),
            ("5->asSet()", .set, [5]),
            ("Sequence{1, 1, 2}->asOrderedSet()", .orderedSet, [1, 2]),
            ("Bag{2, 1, 2}->asOrderedSet()", .orderedSet, [2, 1]),
            ("Set{1, 2}->asOrderedSet()", .orderedSet, [1, 2]),
        ])
    func conversionKinds(expression: String, kind: ATLCollectionKind, expected: [Int]) async throws {
        let value = try await evaluate(expression)
        #expect(ATLCollections.kind(of: value) == kind)
        #expect(value.integers == expected)
    }

    @Test("A Sequence converted to a Set is a Set whose collect gives a Bag")
    func sequenceAsSet() async throws {
        #expect(try await evaluate("Sequence{1, 1, 2}->asSet()->oclType()") as? String == "Set")
        #expect(try await evaluate("Sequence{1, 1, 2}->asSet()->oclIsKindOf(Set(Integer))") as? Bool == true)
        let collected = try await evaluate("Sequence{1, 1, 2}->asSet()->collect(e | e)")
        #expect(ATLCollections.kind(of: collected) == .bag)
        #expect(collected.integers == [1, 2])
        #expect(try await evaluate("Sequence{1, 2}->asSet() = Set{2, 1}") as? Bool == true)
    }

    @Test("A many-valued feature converted to a Set is a Set")
    func featureAsSet() async throws {
        let fixture = ShapeFixture()
        var drawing = fixture.make(fixture.drawing)
        let square = fixture.make(fixture.square, ["name": "s"])
        drawing.eSet("shapes", value: EcoreValueArray([square, square]))
        let harness = try await LanguageHarness.make(
            expression: "drawing.shapes->asSet()", fixture: fixture, options: .standard)
        harness.context.setVariable("drawing", value: drawing)
        let value = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        #expect(ATLCollections.kind(of: value) == .set)
        #expect(value.collectionElements?.count == 1)
    }

    @Test("The legacy options convert a plain Sequence to a duplicate-free Sequence, as swift-atl 0.6 did")
    func legacyAsSet() async throws {
        let value = try await evaluateLegacy("Sequence{1, 1, 2}->asSet()")
        #expect(value is EcoreValueArray)
        #expect(ATLCollections.kind(of: value) == .sequence)
        #expect(value.integers == [1, 2])
        #expect(try await evaluateLegacy("Sequence{1, 1, 2}->asSet()->oclType()") as? String == "Sequence")
        #expect(ATLCollections.kind(of: try await evaluateLegacy("Set{1}->asSet()")) == .set)
    }

    @Test(
        "at applies to Sequences and OrderedSets only",
        arguments: ["Set{1, 2}->at(1)", "Bag{1, 2}->at(1)"])
    func atOnUnorderedCollection(expression: String) async throws {
        await #expect(throws: (any Error).self) { try await evaluate(expression) }
        #expect(try await evaluate("Sequence{1, 2}->at(2)") as? Int == 2)
        #expect(try await evaluate("OrderedSet{1, 2}->at(2)") as? Int == 2)
    }

    // MARK: - Navigation over collections

    /// Navigates `name` over a collection of shapes of the given kind.
    ///
    /// - Parameters:
    ///   - kind: The kind of the receiving collection.
    ///   - options: The options of the execution context.
    /// - Returns: The navigated value.
    private func navigateNames(over kind: ATLCollectionKind, options: ATLOptions) async throws
        -> (any EcoreValue)?
    {
        let fixture = ShapeFixture()
        let shapes: [any EcoreValue] = [
            fixture.make(fixture.square, ["name": "s"]),
            fixture.make(fixture.circle, ["name": "c"]),
        ]
        let harness = try await LanguageHarness.make(
            expression: "list.name", fixture: fixture, options: options)
        harness.context.setVariable("list", value: ATLCollections.make(kind: kind, shapes))
        return try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
    }

    @Test(
        "Navigating a feature over a collection gives the kind that collect gives",
        arguments: [
            (ATLCollectionKind.bag, ATLCollectionKind.bag),
            (.set, .bag),
            (.orderedSet, .sequence),
            (.sequence, .sequence),
        ])
    func navigationKinds(receiver: ATLCollectionKind, expected: ATLCollectionKind) async throws {
        let value = try await navigateNames(over: receiver, options: .standard)
        #expect(ATLCollections.kind(of: value) == expected)
        #expect(value.strings == ["s", "c"])
    }

    @Test(
        "Navigating a feature over a collection agrees with collect",
        arguments: ["Bag{'ab', 'c'}", "Set{'ab', 'c'}", "OrderedSet{'ab', 'c'}", "Sequence{'ab', 'c'}"])
    func navigationMatchesCollect(receiver: String) async throws {
        let declarations = "helper context String def : twice : String = self + self;"
        let navigated = try await evaluate("\(receiver).twice", declarations: declarations)
        let collected = try await evaluate("\(receiver)->collect(e | e.twice)", declarations: declarations)
        #expect(ATLCollections.kind(of: navigated) == ATLCollections.kind(of: collected))
        #expect(ATLValues.areEqual(navigated, collected))
    }

    @Test(
        "The legacy options navigate a feature over any collection to a Sequence",
        arguments: [ATLCollectionKind.bag, .set, .orderedSet, .sequence])
    func legacyNavigationKinds(receiver: ATLCollectionKind) async throws {
        let value = try await navigateNames(over: receiver, options: .legacy)
        #expect(ATLCollections.kind(of: value) == .sequence)
        #expect(value.strings == ["s", "c"])
    }

    // MARK: - Equality

    @Test(
        "Bags are equal when they hold each element equally often, in any order",
        arguments: [
            ("Bag{1, 2, 1} = Bag{1, 1, 2}", true),
            ("Bag{} = Bag{}", true),
            ("Bag{1, 2} = Bag{1, 2, 2}", false),
            ("Bag{1, 1, 2} = Bag{1, 2, 2}", false),
            ("Bag{1, 2} <> Bag{2, 1}", false),
            ("Bag{1, 2} <> Bag{1, 3}", true),
            ("Bag{1, 2.0} = Bag{2, 1}", true),
            ("Bag{2, 1} = Sequence{1, 2}", true),
            ("Sequence{1, 2} = Bag{2, 1}", true),
            ("Bag{1, 1} = Sequence{1}", false),
            ("Bag{2, 1} = Set{1, 2}", true),
            ("Set{1, 2} = Bag{2, 1}", true),
            ("Bag{1, 1} = Set{1}", false),
        ])
    func equality(expression: String, expected: Bool) async throws {
        #expect(try await evaluate(expression) as? Bool == expected)
    }

    @Test("A Bag compares with ATLValues by element counts")
    func valueEquality() {
        let bag = EcoreValueArray([1, 2, 1], kind: .bag)
        #expect(ATLValues.areEqual(bag, EcoreValueArray([2, 1, 1], kind: .bag)))
        #expect(!ATLValues.areEqual(bag, EcoreValueArray([2, 2, 1], kind: .bag)))
        #expect(ATLValues.contains([bag], EcoreValueArray([1, 1, 2], kind: .bag)))
    }

    // MARK: - Types

    @Test(
        "Type operations report a Bag as a Bag and as a Collection",
        arguments: [
            ("Bag{1}->oclIsKindOf(Bag(Integer))", true),
            ("Bag{1}->oclIsKindOf(Collection(Integer))", true),
            ("Bag{1}->oclIsKindOf(OclAny)", true),
            ("Bag{1}->oclIsKindOf(Sequence(Integer))", false),
            ("Bag{1}->oclIsKindOf(Set(Integer))", false),
            ("Bag{1}->oclIsTypeOf(Bag(Integer))", true),
            ("Bag{1}->oclIsTypeOf(Collection(Integer))", false),
            ("Bag{1}->oclIsTypeOf(Sequence(Integer))", false),
            ("Sequence{1}->oclIsKindOf(Bag(Integer))", false),
            ("Set{1}->collect(e | e)->oclIsKindOf(Bag(Integer))", true),
            ("Sequence{1}->asBag()->oclIsTypeOf(Bag(Integer))", true),
        ])
    func typeChecks(expression: String, expected: Bool) async throws {
        #expect(try await evaluate(expression) as? Bool == expected)
    }

    @Test("oclType names the Bag type")
    func oclType() async throws {
        #expect(try await evaluate("Bag{1, 2}->oclType()") as? String == "Bag")
        #expect(try await evaluate("Set{1}->collect(e | e)->oclType()") as? String == "Bag")
    }

    @Test("oclAsType casts a Bag to Bag and Collection but not to Sequence")
    func oclAsType() async throws {
        let bag = try await evaluate("Bag{1, 1}->oclAsType(Collection(Integer))")
        #expect(ATLCollections.kind(of: bag) == .bag)
        await #expect(throws: ATLExecutionError.self) {
            try await evaluate("Bag{1, 1}->oclAsType(Sequence(Integer))")
        }
    }

    @Test("A Bag is written as a Bag literal")
    func rendering() async throws {
        #expect(ATLValueText.render(try await evaluate("Bag{1, 'a', 1}")) == "Bag{1, 'a', 1}")
        #expect(ATLValueText.render(try await evaluate("Set{1, 2}->collect(e | 0)")) == "Bag{0, 0}")
    }

    @Test("debug writes a Bag as a Bag literal")
    func debugOutput() async throws {
        let harness = try await LanguageHarness.make(
            expression: "Bag{2, 2}->debug('bag')", options: .standard)
        let capture = ConsoleCapture()
        harness.context.console = capture.console
        _ = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        #expect(capture.errors == ["bag: Bag{2, 2}"])
    }

    // MARK: - Storing into models

    @Test("A Bag bound to a many-valued attribute stores all of its elements")
    func binding() async throws {
        let string = EDataType(name: "EString")
        let holder = EClass(
            name: "Holder",
            eStructuralFeatures: [
                EAttribute(name: "name", eType: string),
                EAttribute(name: "labels", eType: string, upperBound: -1),
                EAttribute(name: "label", eType: string),
            ])
        let package = EPackage(
            name: "Labels", nsURI: "http://example.org/labels", nsPrefix: "lbl",
            eClassifiers: [holder])
        let source = """
            module Labels2Labels;
            create OUT : Labels from IN : Labels;
            rule Holder2Holder {
                from s : Labels!Holder
                to t : Labels!Holder (
                    name <- s.name,
                    labels <- Bag{s.name, 'b', s.name}
                )
            }
            """
        let registry = ATLMetamodelRegistry(packages: [package])
        let module = try await ATLParser(options: .standard)
            .parseContent(source, metamodelRegistry: registry)
        let input = Resource(uri: "test://in")
        var object = DynamicEObject(eClass: holder)
        object.eSet("name", value: "a")
        await input.add(object)
        let output = Resource(uri: "test://out")
        try await ATLVirtualMachine(module: module, options: .standard)
            .execute(sources: ["IN": input], targets: ["OUT": output])
        let result = try #require(await output.getRootObjects().first as? DynamicEObject)
        let labels = try #require(result.eGet("labels"))
        let stored = (labels as? [String]) ?? ((labels as? EcoreValueArray)?.values as? [String])
        #expect(stored == ["a", "b", "a"])
    }

    /// Transforms one holder whose labels and friends are bound to a collection
    /// literal of the given kind, and serialises the target model.
    ///
    /// - Parameters:
    ///   - kind: The kind of the bound collection literals.
    ///   - options: The options of the parser and the virtual machine.
    /// - Returns: The labels and friends stored in the target, and the XMI and JSON text of the target.
    private func transformHolder(binding kind: ATLCollectionKind, options: ATLOptions) async throws
        -> (labels: (any EcoreValue)?, friends: (any EcoreValue)?, xmi: String, json: String)
    {
        let string = EDataType(name: "EString")
        let holder = EClass(
            name: "Holder",
            eStructuralFeatures: [
                EAttribute(name: "name", eType: string),
                EAttribute(name: "labels", eType: string, upperBound: -1),
                EReference(name: "friends", eType: EClass(name: "Holder"), upperBound: -1),
            ])
        let package = EPackage(
            name: "Labels", nsURI: "http://example.org/labels", nsPrefix: "lbl",
            eClassifiers: [holder])
        let source = """
            module Labels2Labels;
            create OUT : Labels from IN : Labels;
            rule Holder2Holder {
                from s : Labels!Holder
                to t : Labels!Holder (
                    name <- s.name,
                    labels <- \(kind.rawValue){s.name, 'b', s.name},
                    friends <- \(kind.rawValue){s, s}
                )
            }
            """
        let registry = ATLMetamodelRegistry(packages: [package])
        let module = try await ATLParser(options: options)
            .parseContent(source, metamodelRegistry: registry)
        let input = Resource(uri: "test://in")
        var object = DynamicEObject(eClass: holder)
        object.eSet("name", value: "a")
        await input.add(object)
        let output = Resource(uri: "test://out")
        try await ATLVirtualMachine(module: module, options: options)
            .execute(sources: ["IN": input], targets: ["OUT": output])
        let result = try #require(await output.getRootObjects().first as? DynamicEObject)
        let xmi = try await XMISerializer().serialize(output)
        let json = try await JSONSerializer().serialize(output)
        return (result.eGet("labels"), result.eGet("friends"), xmi, json)
    }

    @Test(
        "A Bag is stored and serialised as the Sequence of its elements",
        arguments: [ATLOptions.standard, .legacy])
    func storedAndSerialised(options: ATLOptions) async throws {
        let bag = try await transformHolder(binding: .bag, options: options)
        let sequence = try await transformHolder(binding: .sequence, options: options)
        let labels = (bag.labels as? [String]) ?? ((bag.labels as? EcoreValueArray)?.values as? [String])
        #expect(labels == ["a", "b", "a"])
        #expect(ATLCollections.kind(of: bag.labels) == .sequence)
        #expect(ATLCollections.elements(of: bag.friends).count == 1)
        #expect(ATLCollections.kind(of: bag.friends) == .sequence)
        #expect(bag.xmi == sequence.xmi)
        #expect(bag.json == sequence.json)
        #expect(!bag.xmi.contains("Bag"))
        #expect(!bag.json.contains("Bag"))
    }

    @Test("A Bag prepared for a feature is stored as a plain list")
    func prepared() throws {
        let string = EDataType(name: "EString")
        let attribute = EAttribute(name: "label", eType: string)
        let bag = EcoreValueArray(["a", "a"], kind: .bag)
        let stored = try #require(try ATLValueConversion.prepare(bag, for: attribute) as? EcoreValueArray)
        #expect(stored.kind == .sequence)
        #expect(stored.values.count == 2)
        let holder = EClass(name: "Holder")
        let unknown = try #require(
            try ATLValueConversion.prepare(bag, property: "other", of: DynamicEObject(eClass: holder))
                as? EcoreValueArray)
        #expect(unknown.kind == .sequence)
        #expect(unknown.values.count == 2)
    }

    // MARK: - Legacy behaviour

    @Test(
        "The legacy options make Bags Sequences, as in swift-atl 0.6",
        arguments: [
            "Bag{1, 1}", "Sequence{1, 1}->asBag()", "Set{1, 3}->collect(e | e mod 2)",
            "Bag{1, 3}->collect(e | e mod 2)", "Bag{1, 1}->including(1)",
            "Bag{1, 1}->intersection(Bag{1})",
        ])
    func legacyKinds(expression: String) async throws {
        let value = try await evaluateLegacy(expression)
        #expect(ATLCollections.kind(of: value) == .sequence)
    }

    @Test("The legacy options keep 0.6 results for Set unions and Bag intersections")
    func legacyResults() async throws {
        let union = try await evaluateLegacy("Set{1}->union(Bag{1, 1})")
        #expect(ATLCollections.kind(of: union) == .set)
        #expect(union.integers == [1])
        #expect(try await evaluateLegacy("Bag{1, 1}->intersection(Bag{1})").integers == [1, 1])
        #expect(try await evaluateLegacy("Bag{1, 1}->intersection(Set{1})").integers == [1, 1])
    }

    @Test(
        "The legacy options type and compare Bags as Sequences",
        arguments: [
            ("Bag{1}->oclIsKindOf(Sequence(Integer))", true),
            ("Bag{1}->oclIsTypeOf(Sequence(Integer))", true),
            ("Bag{1}->oclIsKindOf(Bag(Integer))", false),
            ("Bag{1, 2} = Bag{2, 1}", false),
            ("Bag{1, 2} = Bag{1, 2}", true),
        ])
    func legacyTypes(expression: String, expected: Bool) async throws {
        #expect(try await evaluateLegacy(expression) as? Bool == expected)
    }

    @Test("The legacy options name and write Bags as Sequences")
    func legacyNames() async throws {
        #expect(try await evaluateLegacy("Bag{1}->oclType()") as? String == "Sequence")
        #expect(ATLValueText.render(try await evaluateLegacy("Bag{1, 1}")) == "Sequence{1, 1}")
    }

    @Test("The legacy options apply Sequence helpers to Bags")
    func legacyHelpers() async throws {
        let declarations = "helper context Sequence(String) def : size() : Integer = 99;"
        #expect(try await evaluateLegacy("Bag{'a'}->size()", declarations: declarations) as? Int == 99)
    }
}
