//
//  ATLDefaultValueTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 20/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import OrderedCollections
import Testing

@testable import ATL

/// A source metamodel whose attributes are left unset, and a target metamodel that records
/// what the transformation read from them.
///
/// `Cfg!Item` has a name, a Boolean `flag`, an integer `size`, a real `weight`, an integer
/// `level` with the default value literal `3` and a string `note`. `Out!Report` has one
/// attribute per value read.
@MainActor
struct DefaultValueFixture {
    /// The namespace URI of the source metamodel.
    static let sourceURI = "http://example.org/cfg"

    /// The source metamodel.
    let source: EPackage

    /// The target metamodel.
    let target: EPackage

    /// The class of the source elements.
    let item: EClass

    init() {
        let string = EDataType(name: "EString")
        let boolean = EDataType(name: "EBoolean")
        let integer = EDataType(name: "EInt")
        let real = EDataType(name: "EDouble")
        let item = EClass(
            name: "Item",
            eStructuralFeatures: [
                EAttribute(name: "name", eType: string),
                EAttribute(name: "flag", eType: boolean),
                EAttribute(name: "size", eType: integer),
                EAttribute(name: "weight", eType: real),
                EAttribute(name: "level", eType: integer, defaultValueLiteral: "3"),
                EAttribute(name: "note", eType: string),
            ])
        let holder = EClass(
            name: "Items",
            eStructuralFeatures: [
                EReference(name: "items", eType: item, upperBound: -1, containment: true)
            ])
        let report = EClass(
            name: "Report",
            eStructuralFeatures: [
                EAttribute(name: "name", eType: string),
                EAttribute(name: "open", eType: boolean),
                EAttribute(name: "size", eType: integer),
                EAttribute(name: "weight", eType: real),
                EAttribute(name: "level", eType: integer),
                EAttribute(name: "noteMissing", eType: boolean),
            ])
        self.item = item
        self.source = EPackage(
            name: "Cfg", nsURI: Self.sourceURI, nsPrefix: "cfg", eClassifiers: [item, holder])
        self.target = EPackage(
            name: "Out", nsURI: "http://example.org/out", nsPrefix: "out", eClassifiers: [report])
    }

    /// The transformation, whose guard and bindings read the unset attributes.
    static let transformation = """
        module Defaults;
        create OUT : Out from IN : Cfg;
        rule Item2Report {
            from i : Cfg!Item (not i.flag)
            to r : Out!Report (
                name <- i.name,
                open <- not i.flag,
                size <- i.size,
                weight <- i.weight,
                level <- i.level,
                noteMissing <- i.note.oclIsUndefined()
            )
        }
        """

    /// Runs a transformation over a source model.
    ///
    /// - Parameters:
    ///   - sourceResource: The source model.
    ///   - mode: How the virtual machine reads unset features.
    ///   - text: The transformation to run.
    /// - Returns: The reports created by the transformation.
    func run(
        over sourceResource: Resource, mode: UnsetFeatureReads = .defaults,
        transformation text: String = transformation
    ) async throws -> [DynamicEObject] {
        let parsed = try await ATLParser().parseContent(text)
        let module = ATLModule(
            name: parsed.name, sourceMetamodels: ["IN": source], targetMetamodels: ["OUT": target],
            helpers: parsed.helpers, matchedRules: parsed.matchedRules)
        let targetResource = Resource(uri: "test://out")
        try await ATLVirtualMachine(module: module, unsetFeatureReads: mode).execute(
            sources: ["IN": sourceResource], targets: ["OUT": targetResource])
        return await targetResource.getAllObjects().compactMap { $0 as? DynamicEObject }
    }

    /// Checks that a report holds the values that unset source attributes read as.
    ///
    /// - Parameters:
    ///   - reports: The reports created by the transformation.
    ///   - name: The name of the source item.
    func expectDefaults(in reports: [DynamicEObject], named name: String) throws {
        let report = try #require(reports.first)
        #expect(reports.count == 1)
        #expect(report.eGet("name") as? String == name)
        #expect(report.eGet("open") as? Bool == true)
        #expect(report.eGet("size") as? Int == 0)
        #expect(report.eGet("weight") as? Double == 0.0)
        #expect(report.eGet("level") as? Int == 3)
        #expect(report.eGet("noteMissing") as? Bool == true)
    }
}

/// Tests that navigation reads unset attributes as their defaults, as EMF does.
@Suite("ATL Default Value Tests")
@MainActor
struct ATLDefaultValueTests {

    @Test("Unset attributes of an element built in code read as their defaults")
    func elementBuiltInCode() async throws {
        let fixture = DefaultValueFixture()
        var item = DynamicEObject(eClass: fixture.item)
        item.eSet("name", value: "built")
        let resource = Resource(uri: "test://cfg")
        await resource.add(item)
        try fixture.expectDefaults(in: try await fixture.run(over: resource), named: "built")
    }

    @Test("Unset attributes of an element loaded from XMI read as their defaults")
    func elementLoadedFromXMI() async throws {
        let fixture = DefaultValueFixture()
        let resourceSet = ResourceSet()
        await resourceSet.registerMetamodel(fixture.source, uri: DefaultValueFixture.sourceURI)
        let resource = try await XMIParser(resourceSet: resourceSet).parse(
            """
            <?xml version="1.0" encoding="UTF-8"?>
            <cfg:Items xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:cfg="\(DefaultValueFixture.sourceURI)">
              <items name="loaded"/>
            </cfg:Items>
            """, uri: "test://cfg.xmi")
        let loaded = await resource.getAllObjects().compactMap { $0 as? DynamicEObject }
            .filter { $0.eClass.name == "Item" }
        #expect(loaded.count == 1)
        #expect(loaded.first?.eGet("flag") == nil)
        try fixture.expectDefaults(in: try await fixture.run(over: resource), named: "loaded")
    }

    @Test("Set attributes read as stored rather than as their defaults")
    func setAttributesWin() async throws {
        let fixture = DefaultValueFixture()
        var item = DynamicEObject(eClass: fixture.item)
        for (name, value) in [
            ("name", "set"), ("flag", false), ("size", 4), ("level", 9), ("note", "x"),
        ] as [(String, any EcoreValue)] {
            item.eSet(name, value: value)
        }
        let resource = Resource(uri: "test://cfg")
        await resource.add(item)
        let report = try #require(try await fixture.run(over: resource).first)
        #expect(report.eGet("size") as? Int == 4)
        #expect(report.eGet("level") as? Int == 9)
        #expect(report.eGet("noteMissing") as? Bool == false)
    }

    @Test("Expressions in the language harness read unset attributes as their defaults")
    func harnessReadsDefaults() async throws {
        let fixture = ShapeFixture()
        let harness = try await LanguageHarness.make(
            expression: "Sequence{c.radius, c.name.oclIsUndefined()}", fixture: fixture)
        harness.context.setVariable("c", value: fixture.make(fixture.circle))
        let result = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        let elements = try #require(result.collectionElements)
        #expect(elements.first as? Double == 0.0)
        #expect(elements.last as? Bool == true)
    }

    @Test("The virtual machine reports how it reads unset features")
    func modeProperty() {
        let fixture = DefaultValueFixture()
        let module = ATLModule(
            name: "Empty", sourceMetamodels: ["IN": fixture.source],
            targetMetamodels: ["OUT": fixture.target])
        #expect(ATLVirtualMachine(module: module).unsetFeatureReads == .defaults)
        #expect(
            ATLVirtualMachine(module: module, unsetFeatureReads: .undefined).unsetFeatureReads
                == .undefined)
        #expect(
            ATLVirtualMachine(module: module, enableDebugging: true, unsetFeatureReads: .defaults)
                .unsetFeatureReads == .defaults)
    }

    @Test("The undefined mode reads an unset attribute as OclUndefined")
    func undefinedModeReadsUndefined() async throws {
        let fixture = DefaultValueFixture()
        var item = DynamicEObject(eClass: fixture.item)
        item.eSet("name", value: "built")
        let resource = Resource(uri: "test://cfg")
        await resource.add(item)
        let reports = try await fixture.run(
            over: resource, mode: .undefined,
            transformation: """
                module Undefined;
                create OUT : Out from IN : Cfg;
                rule Item2Report {
                    from i : Cfg!Item
                    to r : Out!Report (
                        name <- i.name,
                        open <- i.flag.oclIsUndefined(),
                        noteMissing <- i.note.oclIsUndefined()
                    )
                }
                """)
        let report = try #require(reports.first)
        #expect(report.eGet("open") as? Bool == true)
        #expect(report.eGet("noteMissing") as? Bool == true)
    }

    @Test("The undefined mode rejects a guard that negates an unset Boolean")
    func undefinedModeGuard() async throws {
        let fixture = DefaultValueFixture()
        var item = DynamicEObject(eClass: fixture.item)
        item.eSet("name", value: "built")
        let resource = Resource(uri: "test://cfg")
        await resource.add(item)
        await #expect(throws: ATLExecutionError.self) {
            try await fixture.run(over: resource, mode: .undefined)
        }
    }
}
