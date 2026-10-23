//
//  ATLManyValuedAttributeBindingTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 23/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import OrderedCollections
import Testing

@testable import ATL

/// Tests for binding many-valued attributes navigated from the source model.
@Suite("ATL Many-Valued Attribute Binding Tests")
@MainActor
struct ATLManyValuedAttributeBindingTests {

    private let namespaceURI = "http://example.org/labels"
    private let metamodelName = "Labels"
    private let package: EPackage
    private let holder: EClass

    init() {
        let string = EDataType(name: "EString")
        let holder = EClass(
            name: "Holder",
            eStructuralFeatures: [
                EAttribute(name: "name", eType: string),
                EAttribute(name: "labels", eType: string, upperBound: -1),
                EAttribute(name: "others", eType: string, upperBound: -1),
            ])
        self.holder = holder
        self.package = EPackage(
            name: metamodelName, nsURI: namespaceURI, nsPrefix: "lbl", eClassifiers: [holder])
    }

    private func labels(bound expression: String, from labels: [String]) async throws -> any EcoreValue {
        let source = """
            module Labels2Labels;
            create OUT : Labels from IN : Labels;
            rule Holder2Holder {
                from s : Labels!Holder
                to t : Labels!Holder (
                    name <- s.name,
                    labels <- \(expression)
                )
            }
            """
        let registry = ATLMetamodelRegistry(packages: [package])
        let module = try await ATLParser().parseContent(source, metamodelRegistry: registry)
        let input = Resource(uri: "test://in")
        var object = DynamicEObject(eClass: holder)
        object.eSet("name", value: "h")
        object.eSet("labels", value: labels)
        object.eSet("others", value: ["x", "y"])
        await input.add(object)
        let output = Resource(uri: "test://out")
        try await ATLVirtualMachine(module: module).execute(
            sources: ["IN": input], targets: ["OUT": output])
        let roots = await output.getRootObjects()
        let result = try #require(roots.first as? DynamicEObject)
        return try #require(result.eGet("labels"))
    }

    private func strings(_ value: any EcoreValue) -> [String]? {
        if let strings = value as? [String] { return strings }
        return (value as? EcoreValueArray)?.values as? [String]
    }

    @Test("A navigated many-valued string attribute is bound flat")
    func navigatedAttributeIsFlat() async throws {
        let value = try await labels(bound: "s.labels", from: ["a", "b", "c"])
        #expect(strings(value) == ["a", "b", "c"])
    }

    @Test("A sequence of a navigated attribute is bound flat")
    func sequenceIsFlat() async throws {
        let value = try await labels(bound: "s.labels->asSequence()", from: ["a", "b"])
        #expect(strings(value) == ["a", "b"])
    }

    @Test("Nested collections from collect are flattened one level")
    func collectedCollectionsAreFlattened() async throws {
        let value = try await labels(
            bound: "Sequence{s, s}->collect(e | e.labels)", from: ["a", "b"])
        #expect(strings(value) == ["a", "b", "a", "b"])
    }

    @Test("A single string is bound as a one-element list")
    func singleValue() async throws {
        let value = try await labels(bound: "s.name", from: [])
        #expect(strings(value) == ["h"])
    }

    @Test("An empty navigated attribute is bound as an empty list")
    func emptyAttribute() async throws {
        let value = try await labels(bound: "s.labels", from: [])
        #expect(strings(value) == [])
    }
}
