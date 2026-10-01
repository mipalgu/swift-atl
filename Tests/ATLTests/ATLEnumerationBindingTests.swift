//
//  ATLEnumerationBindingTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import OrderedCollections
import Testing

@testable import ATL

/// Tests for binding enumeration literals and converted values into target models.
@Suite("ATL Enumeration Binding Tests")
@MainActor
struct ATLEnumerationBindingTests {

    private let fixture = ShapeFixture()

    private func transform(_ rules: String, input: [DynamicEObject]) async throws -> Resource {
        let source = """
            module Shapes2Shapes;
            create OUT : Shapes from IN : Shapes;
            \(rules)
            """
        let registry = ATLMetamodelRegistry(packages: [fixture.package])
        let module = try await ATLParser().parseContent(source, metamodelRegistry: registry)
        let inputResource = Resource(uri: "test://in")
        for object in input { await inputResource.add(object) }
        let output = Resource(uri: "test://out")
        try await ATLVirtualMachine(module: module).execute(
            sources: ["IN": inputResource], targets: ["OUT": output])
        return output
    }

    private func circleRule(_ visibilityExpression: String) -> String {
        """
        rule Circle2Circle {
            from s : Shapes!Circle
            to t : Shapes!Circle (
                name <- s.name,
                visibility <- \(visibilityExpression),
                radius <- 2
            )
        }
        """
    }

    // MARK: - Serialisation

    @Test("An enumeration literal binding serialises as the literal name")
    func serialisedLiteral() async throws {
        let output = try await transform(
            circleRule("#Private"), input: [fixture.make(fixture.circle, ["name": "c1"])])
        let xml = try await XMISerializer().serialize(output)
        #expect(xml.contains("visibility=\"Private\""))
        #expect(xml.contains("name=\"c1\""))
        #expect(xml.contains("radius=\"2.0\""))
    }

    @Test("The serialised enumeration value loads back as the same literal")
    func roundTrip() async throws {
        let output = try await transform(
            circleRule("#Public"), input: [fixture.make(fixture.circle, ["name": "c1"])])
        let xml = try await XMISerializer().serialize(output)

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "enum-\(UUID().uuidString).xmi")
        try xml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let resourceSet = ResourceSet()
        await resourceSet.registerMetamodel(fixture.package, uri: ShapeFixture.namespaceURI)
        let loaded = try await XMIParser(resourceSet: resourceSet).parse(url)
        let roots = await loaded.getRootObjects()
        let circle = try #require(roots.first as? DynamicEObject)
        #expect(circle.eGet("visibility") as? String == "Public")
        #expect(circle.eGet("name") as? String == "c1")
    }

    @Test("The stored value is a literal of the enumeration")
    func storedValue() async throws {
        let output = try await transform(
            circleRule("#Private"), input: [fixture.make(fixture.circle, ["name": "c1"])])
        let created = try #require(await output.getAllInstancesOf(fixture.circle).first as? DynamicEObject)
        let stored = try #require(created.eGet("visibility") as? String)
        #expect(fixture.visibility.getLiteral(name: stored) != nil)
    }

    @Test("A literal copied from the source keeps its representation")
    func copiedLiteral() async throws {
        let output = try await transform(
            circleRule("s.visibility"),
            input: [fixture.make(fixture.circle, ["name": "c1", "visibility": "Private"])])
        let xml = try await XMISerializer().serialize(output)
        #expect(xml.contains("visibility=\"Private\""))
    }

    @Test("Literals select values in conditional expressions")
    func conditionalLiteral() async throws {
        let output = try await transform(
            circleRule("if s.visibility = #Private then #Public else #Private endif"),
            input: [fixture.make(fixture.circle, ["name": "c1", "visibility": "Private"])])
        let created = try #require(await output.getAllInstancesOf(fixture.circle).first as? DynamicEObject)
        #expect(created.eGet("visibility") as? String == "Public")
    }

    // MARK: - Validation

    @Test("A literal that the enumeration does not declare is an error")
    func invalidLiteral() async throws {
        await #expect {
            _ = try await self.transform(
                self.circleRule("#Bogus"), input: [self.fixture.make(self.fixture.circle, ["name": "c"])])
        } throws: { error in
            guard case ATLExecutionError.invalidEnumerationLiteral(let message) = error else {
                return false
            }
            return message.contains("Bogus") && message.contains("Visibility")
                && message.contains("Public, Private")
        }
    }

    @Test("A string value is checked against the enumeration")
    func invalidStringValue() async throws {
        await #expect(throws: ATLExecutionError.self) {
            _ = try await self.transform(
                self.circleRule("'nonsense'"),
                input: [self.fixture.make(self.fixture.circle, ["name": "c"])])
        }
    }

    @Test("An integer selects the literal with that value")
    func integerLiteralValue() async throws {
        let output = try await transform(
            circleRule("1"), input: [fixture.make(fixture.circle, ["name": "c"])])
        let created = try #require(await output.getAllInstancesOf(fixture.circle).first as? DynamicEObject)
        #expect(created.eGet("visibility") as? String == "Private")
    }

    // MARK: - Value conversion

    @Test("Conversion unwraps set values and coerces numbers")
    func conversion() throws {
        let nameFeature = try #require(fixture.shape.getStructuralFeature(name: "name"))
        let radius = try #require(fixture.circle.getStructuralFeature(name: "radius"))

        let set = ATLCollectionValue(kind: .orderedSet, values: ["a", "b", "a"])
        let unwrapped = try ATLValueConversion.prepare(set, for: nameFeature)
        #expect((unwrapped as? EcoreValueArray)?.values.count == 2)

        #expect(try ATLValueConversion.prepare(3, for: radius) as? Double == 3.0)
        #expect(try ATLValueConversion.prepare(3.5, for: radius) as? Double == 3.5)
        #expect(try ATLValueConversion.prepare(nil, for: radius) == nil)
        #expect(try ATLValueConversion.prepare("text", for: nameFeature) as? String == "text")
    }

    @Test("Conversion checks every element of a many-valued enumeration attribute")
    func manyValuedEnumeration() throws {
        let visibility = EAttribute(name: "modes", eType: fixture.visibility, upperBound: -1)
        let ok = try ATLValueConversion.prepare(
            ATLCollectionValue(kind: .orderedSet, values: ["Public", 1]), for: visibility)
        #expect((ok as? EcoreValueArray)?.values.compactMap { $0 as? String } == ["Public", "Private"])
        #expect(throws: ATLExecutionError.self) {
            _ = try ATLValueConversion.prepare(EcoreValueArray(["Public", "Nope"]), for: visibility)
        }
    }

    @Test("Conversion by property name falls back to plain unwrapping for unknown features")
    func conversionByName() throws {
        let object = fixture.make(fixture.circle)
        let known = try ATLValueConversion.prepare("Private", property: "visibility", of: object)
        #expect(known as? String == "Private")
        let unknown = try ATLValueConversion.prepare(
            ATLCollectionValue(kind: .set, values: [1]), property: "nothing", of: object)
        #expect(unknown is EcoreValueArray)
        #expect(try ATLValueConversion.prepare(7, property: "nothing", of: object) as? Int == 7)
        #expect(throws: ATLExecutionError.self) {
            _ = try ATLValueConversion.prepare("Bad", property: "visibility", of: object)
        }
    }

    @Test("Lazy bindings convert enumeration values as well")
    func lazyBindingConversion() async throws {
        let module = ATLModule(
            name: "Lazy", sourceMetamodels: ["IN": fixture.package],
            targetMetamodels: ["OUT": fixture.package])
        let target = Resource(uri: "test://out")
        let object = fixture.make(fixture.circle, ["name": "c"])
        await target.add(object)
        let context = ATLExecutionContext(
            module: module, sources: [:], targets: ["OUT": target],
            executionEngine: ECoreExecutionEngine(models: [:]))

        let binding = ATLLazyBinding(
            targetElement: object.id, property: "visibility",
            expression: ATLEnumLiteralExpression(name: "Nope"))
        await #expect(throws: ATLExecutionError.self) {
            try await binding.resolve(in: context)
        }
    }

    @Test("Descriptions of the new errors name the offending item")
    func errorDescriptions() {
        #expect(
            ATLExecutionError.missingParameter("p").errorDescription?.contains("'p'") == true)
        #expect(
            ATLExecutionError.unknownParameter("q").errorDescription?.contains("'q'") == true)
        #expect(
            ATLExecutionError.invalidEnumerationLiteral("bad").errorDescription?.contains("bad")
                == true)
    }
}
