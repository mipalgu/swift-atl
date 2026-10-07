//
//  ATLMetamodelBindingTests.swift
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

/// Tests for `@nsURI` directives and binding metamodels through a caller-supplied registry.
@Suite("ATL Metamodel Binding Tests")
@MainActor
struct ATLMetamodelBindingTests {

    private let fixture = ShapeFixture()

    private func package(name: String, nsURI: String) -> EPackage {
        EPackage(name: name, nsURI: nsURI, eClassifiers: [EClass(name: "Thing")])
    }

    // MARK: - Registry

    @Test("A registry finds packages by namespace URI and by name")
    func registryLookup() {
        let registry = ATLMetamodelRegistry(packages: [fixture.package])
        #expect(registry.package(nsURI: ShapeFixture.namespaceURI)?.name == "Shapes")
        #expect(registry.package(named: "Shapes")?.nsURI == ShapeFixture.namespaceURI)
        #expect(registry.package(nsURI: "http://unknown") == nil)
        #expect(registry.package(named: "Unknown") == nil)
    }

    @Test("Name lookup ignores letter case when the match is unique")
    func registryCaseInsensitive() {
        let registry = ATLMetamodelRegistry(packages: [
            package(name: "genmodel", nsURI: "http://example.org/gen")
        ])
        #expect(registry.package(named: "GenModel")?.name == "genmodel")
    }

    @Test("Name lookup refuses ambiguous case-insensitive matches but prefers exact ones")
    func registryAmbiguity() {
        let registry = ATLMetamodelRegistry(packages: [
            package(name: "Model", nsURI: "http://example.org/a"),
            package(name: "model", nsURI: "http://example.org/b"),
        ])
        #expect(registry.package(named: "MODEL") == nil)
        #expect(registry.package(named: "Model")?.nsURI == "http://example.org/a")
        #expect(registry.package(named: "model")?.nsURI == "http://example.org/b")
    }

    @Test("A registry built from a table honours the table's namespace URIs")
    func registryFromTable() {
        let registry = ATLMetamodelRegistry(packagesByNSURI: [
            "http://alias.example.org/shapes": fixture.package
        ])
        #expect(registry.package(nsURI: "http://alias.example.org/shapes")?.name == "Shapes")
        #expect(registry.package(nsURI: ShapeFixture.namespaceURI) == nil)
    }

    @Test("A package can be registered under an additional namespace URI")
    func registerAlias() {
        var registry = ATLMetamodelRegistry.empty
        registry.register(fixture.package, nsURI: "http://alias.example.org/shapes")
        #expect(registry.package(nsURI: "http://alias.example.org/shapes") != nil)
    }

    @Test("The resolver is consulted for namespace URIs that are not registered")
    func registryResolver() {
        let shapes = fixture.package
        let registry = ATLMetamodelRegistry(resolver: { nsURI in
            nsURI == "http://lazy.example.org/shapes" ? shapes : nil
        })
        #expect(registry.package(nsURI: "http://lazy.example.org/shapes")?.name == "Shapes")
        #expect(registry.package(nsURI: "http://other") == nil)
    }

    // MARK: - @nsURI directive

    private let nsURIHeader = """
        -- @nsURI Shapes=http://example.org/shapes
        module Bound;
        create OUT : Shapes from IN : Shapes;
        """

    @Test("An @nsURI directive binds the metamodel to the registered package")
    func nsURIDirective() async throws {
        let registry = ATLMetamodelRegistry(packages: [fixture.package])
        let module = try await ATLParser().parseContent(nsURIHeader, metamodelRegistry: registry)
        #expect(module.sourceMetamodels["IN"]?.nsURI == ShapeFixture.namespaceURI)
        #expect(module.targetMetamodels["OUT"]?.eClassifiers.count == 6)
        #expect(module.sourceMetamodels["IN"]?.getClassifier("Circle") is EClass)
    }

    @Test("An @nsURI directive can bind a metamodel name that differs from the package name")
    func nsURIDirectiveWithDifferentName() async throws {
        let source = """
            -- @nsURI Figures=http://example.org/shapes
            module Bound;
            create OUT : Figures from IN : Figures;
            rule R { from s : Figures!Circle to t : Figures!Circle ( name <- s.name ) }
            """
        let registry = ATLMetamodelRegistry(packages: [fixture.package])
        let module = try await ATLParser().parseContent(source, metamodelRegistry: registry)
        #expect(module.sourceMetamodels["IN"]?.name == "Shapes")
        #expect(module.declaredMetamodelNames["IN"] == "Figures")
        #expect(module.sourceAlias(forMetamodel: "Figures") == "IN")
        #expect(module.sourceAlias(forMetamodel: "Shapes") == "IN")
        #expect(module.targetAlias(forMetamodel: "Figures") == "OUT")
        #expect(module.sourceAlias(forMetamodel: "Missing") == nil)
    }

    @Test("A bound module transforms models of the bound package")
    func boundModuleRuns() async throws {
        let source = """
            -- @nsURI Figures=http://example.org/shapes
            module Copy;
            create OUT : Figures from IN : Figures;
            rule Circle2Circle {
                from s : Figures!Circle
                to t : Figures!Circle ( name <- s.name )
            }
            """
        let registry = ATLMetamodelRegistry(packages: [fixture.package])
        let module = try await ATLParser().parseContent(source, metamodelRegistry: registry)

        let input = Resource(uri: "test://in")
        await input.add(fixture.make(fixture.circle, ["name": "round"]))
        let output = Resource(uri: "test://out")
        try await ATLVirtualMachine(module: module).execute(
            sources: ["IN": input], targets: ["OUT": output])

        let created = await output.getAllInstancesOf(fixture.circle)
        #expect(created.count == 1)
        #expect((created.first as? DynamicEObject)?.eGet("name") as? String == "round")
    }

    @Test("An unresolved @nsURI is an error when errors are fatal")
    func unresolvedNSURIIsFatal() async {
        await #expect(throws: ATLParseError.self) {
            _ = try await ATLParser().parseContent(
                self.nsURIHeader, continueAfterErrors: false,
                metamodelRegistry: ATLMetamodelRegistry(packages: []))
        }
    }

    @Test("An unresolved @nsURI keeps the placeholder metamodel when errors are tolerated")
    func unresolvedNSURIFallsBack() async throws {
        let module = try await ATLParser().parseContent(nsURIHeader)
        #expect(module.sourceMetamodels["IN"]?.eClassifiers.isEmpty == true)
    }

    @Test("A malformed @nsURI directive is reported")
    func malformedNSURI() async {
        await #expect(throws: ATLParseError.self) {
            _ = try await ATLParser().parseContent(
                "-- @nsURI Shapes\nmodule M;\ncreate OUT : Shapes from IN : Shapes;")
        }
    }

    @Test("The directive may use whitespace around the equals sign")
    func directiveWhitespace() async throws {
        let source = """
            --    @nsURI   Shapes  =  http://example.org/shapes
            module Bound;
            create OUT : Shapes from IN : Shapes;
            """
        let registry = ATLMetamodelRegistry(packages: [fixture.package])
        let module = try await ATLParser().parseContent(source, metamodelRegistry: registry)
        #expect(module.sourceMetamodels["IN"]?.eClassifiers.count == 6)
    }

    @Test("Separate directives bind source and target metamodels separately")
    func separateBindings() async throws {
        let other = EPackage(
            name: "Other", nsURI: "http://example.org/other", eClassifiers: [EClass(name: "Thing")])
        let source = """
            -- @nsURI Shapes=http://example.org/shapes
            -- @nsURI Other=http://example.org/other
            module Bound;
            create OUT : Other from IN : Shapes;
            """
        let registry = ATLMetamodelRegistry(packages: [fixture.package, other])
        let module = try await ATLParser().parseContent(source, metamodelRegistry: registry)
        #expect(module.sourceMetamodels["IN"]?.name == "Shapes")
        #expect(module.targetMetamodels["OUT"]?.name == "Other")
    }

    // MARK: - Lookup by name

    @Test("A metamodel without a directive is found in the registry by name")
    func lookupByName() async throws {
        let source = """
            module Named;
            create OUT : Shapes from IN : Shapes;
            """
        let registry = ATLMetamodelRegistry(packages: [fixture.package])
        let module = try await ATLParser().parseContent(
            source, continueAfterErrors: false, metamodelRegistry: registry)
        #expect(module.sourceMetamodels["IN"]?.nsURI == ShapeFixture.namespaceURI)
    }

    @Test("A built-in style metamodel is bound although its package name differs in case")
    func lookupByNameIgnoringCase() async throws {
        let ecore = EPackage(
            name: "ecore", nsURI: "http://www.eclipse.org/emf/2002/Ecore",
            eClassifiers: [EClass(name: "EClass")])
        let genModel = EPackage(
            name: "genmodel", nsURI: "http://www.eclipse.org/emf/2002/GenModel",
            eClassifiers: [EClass(name: "GenClass")])
        let source = """
            module Ecore2GenModel;
            create OUT : GenModel from IN : Ecore;
            rule C2G {
                from c : Ecore!EClass
                to g : GenModel!GenClass ( )
            }
            """
        let registry = ATLMetamodelRegistry(packages: [ecore, genModel])
        let module = try await ATLParser().parseContent(
            source, continueAfterErrors: false, metamodelRegistry: registry)
        #expect(module.sourceMetamodels["IN"]?.name == "ecore")
        #expect(module.targetMetamodels["OUT"]?.name == "genmodel")
        #expect(module.sourceAlias(forMetamodel: "Ecore") == "IN")
        #expect(module.targetAlias(forMetamodel: "GenModel") == "OUT")

        // The rule runs although the header names differ from the package names
        let input = Resource(uri: "test://in")
        let eClass = try #require(ecore.getClassifier("EClass") as? EClass)
        await input.add(DynamicEObject(eClass: eClass))
        let output = Resource(uri: "test://out")
        try await ATLVirtualMachine(module: module).execute(
            sources: ["IN": input], targets: ["OUT": output])
        let genClass = try #require(genModel.getClassifier("GenClass") as? EClass)
        #expect(await output.getAllInstancesOf(genClass).count == 1)
    }

    @Test("A path directive suppresses the lookup by name")
    func pathDirectiveSuppressesNameLookup() async throws {
        let source = """
            -- @path Shapes=/does/not/exist/Shapes.ecore
            module Named;
            create OUT : Shapes from IN : Shapes;
            """
        let registry = ATLMetamodelRegistry(packages: [fixture.package])
        let module = try await ATLParser().parseContent(source, metamodelRegistry: registry)
        #expect(module.sourceMetamodels["IN"]?.eClassifiers.isEmpty == true)
    }

    @Test("An unknown name without directive keeps the placeholder")
    func unknownNameKeepsPlaceholder() async throws {
        let source = """
            module Named;
            create OUT : Elsewhere from IN : Elsewhere;
            """
        let registry = ATLMetamodelRegistry(packages: [fixture.package])
        let module = try await ATLParser().parseContent(source, metamodelRegistry: registry)
        #expect(module.sourceMetamodels["IN"]?.name == "Elsewhere")
    }

    @Test("Parsing a file passes the registry through")
    func parseFileWithRegistry() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "ATLBinding-\(UUID().uuidString).atl")
        try nsURIHeader.write(to: url, atomically: testWritesAtomically, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let registry = ATLMetamodelRegistry(packages: [fixture.package])
        let module = try await ATLParser().parse(url, metamodelRegistry: registry)
        #expect(module.sourceMetamodels["IN"]?.nsURI == ShapeFixture.namespaceURI)
    }

    @Test("Rebinding a module keeps its helpers, rules and parameters")
    func rebindingKeepsMembers() async throws {
        let source = """
            -- @param limit : Integer = 3
            module Keep;
            create OUT : Shapes from IN : Shapes;
            helper context Shapes!Circle def : label() : String = 'circle';
            helper context Shapes!Square def : label() : String = 'square';
            """
        let registry = ATLMetamodelRegistry(packages: [fixture.package])
        let module = try await ATLParser().parseContent(source, metamodelRegistry: registry)
        let rebound = module.withMetamodels(
            source: module.sourceMetamodels, target: module.targetMetamodels)
        #expect(rebound.helperOverloads["label"]?.count == 2)
        #expect(rebound.parameters.count == 1)
        #expect(rebound.declaredMetamodelNames == module.declaredMetamodelNames)
        #expect(rebound.withParameters([]).parameters.isEmpty)
    }
}
