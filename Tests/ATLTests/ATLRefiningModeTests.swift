//
//  ATLRefiningModeTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 5/11/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import OrderedCollections
import Testing

@testable import ATL

// MARK: - Fixture

/// A small graph metamodel and model for exercising refining mode.
///
/// The model holds one graph named `g` with the nodes `a`, `b` and `c`, where `a` and
/// `b` point to their successor through `next`, and the edges `ab` (from `a` to `b`)
/// and `bc` (from `b` to `c`).
@MainActor
struct RefiningFixture {
    let package: EPackage
    let sourceResource = Resource(uri: "test://graph-in")
    let targetResource = Resource(uri: "test://graph-out")

    var graph: DynamicEObject!
    var a: DynamicEObject!
    var b: DynamicEObject!
    var c: DynamicEObject!
    var ab: DynamicEObject!
    var bc: DynamicEObject!

    /// The header of a refining module over the graph metamodel.
    static let header = "module Refine;\ncreate OUT : Graph refining IN : Graph;\n"

    init() {
        let string = EDataType(name: "EString")
        let integer = EDataType(name: "EInt")

        var node = EClass(name: "Node")
        node.eStructuralFeatures.append(EAttribute(name: "name", eType: string))
        node.eStructuralFeatures.append(EAttribute(name: "weight", eType: integer))
        node.eStructuralFeatures.append(EAttribute(name: "label", eType: string))
        node.eStructuralFeatures.append(EReference(name: "next", eType: EClass(name: "Node")))

        var edge = EClass(name: "Edge")
        edge.eStructuralFeatures.append(EAttribute(name: "weight", eType: integer))
        edge.eStructuralFeatures.append(EReference(name: "source", eType: node))
        edge.eStructuralFeatures.append(EReference(name: "target", eType: node))

        var marker = EClass(name: "Marker")
        marker.eStructuralFeatures.append(EAttribute(name: "text", eType: string))
        marker.eStructuralFeatures.append(EReference(name: "node", eType: node))

        var graph = EClass(name: "Graph")
        graph.eStructuralFeatures.append(EAttribute(name: "name", eType: string))
        graph.eStructuralFeatures.append(
            EReference(name: "nodes", eType: node, upperBound: -1, containment: true))
        graph.eStructuralFeatures.append(
            EReference(name: "edges", eType: edge, upperBound: -1, containment: true))
        graph.eStructuralFeatures.append(
            EReference(name: "markers", eType: marker, upperBound: -1, containment: true))

        var package = EPackage(name: "Graph", nsURI: "http://example.org/graph", nsPrefix: "graph")
        package.eClassifiers.append(contentsOf: [graph, node, edge, marker])
        self.package = package
    }

    /// Creates the source model.
    mutating func populate() async {
        func object(_ className: String) -> DynamicEObject {
            DynamicEObject(eClass: (package.getClassifier(className) as? EClass)!)
        }
        func node(_ name: String, weight: Int) -> DynamicEObject {
            var element = object("Node")
            element.eSet("name", value: name)
            element.eSet("weight", value: weight)
            return element
        }
        var graph = object("Graph")
        graph.eSet("name", value: "g")
        self.graph = graph
        a = node("a", weight: 1)
        b = node("b", weight: 2)
        var c = node("c", weight: 3)
        c.eSet("label", value: "end")
        self.c = c
        var ab = object("Edge")
        ab.eSet("weight", value: 12)
        self.ab = ab
        var bc = object("Edge")
        bc.eSet("weight", value: 23)
        self.bc = bc

        for element in [a!, b!, c, ab, bc] {
            await sourceResource.register(element)
        }
        await sourceResource.add(graph)
        await set(graph, "nodes", [a.id, b.id, c.id])
        await set(graph, "edges", [ab.id, bc.id])
        await set(a, "next", b.id)
        await set(b, "next", c.id)
        await set(ab, "source", a.id)
        await set(ab, "target", b.id)
        await set(bc, "source", b.id)
        await set(bc, "target", c.id)
    }

    func set(_ element: DynamicEObject, _ feature: String, _ value: any EcoreValue) async {
        await sourceResource.eSet(objectId: element.id, feature: feature, value: value)
    }

    /// Parses a refining module from rules and binds the graph metamodel.
    func module(_ declarations: String, header: String = Self.header) async throws -> ATLModule {
        let parsed = try await ATLParser().parseContent(header + declarations)
        return parsed.withMetamodels(source: ["IN": package], target: ["OUT": package])
    }

    /// Runs a module over the source model.
    func run(_ module: ATLModule) async throws {
        let machine = ATLVirtualMachine(module: module)
        try await machine.execute(sources: ["IN": sourceResource], targets: ["OUT": targetResource])
    }

    /// Parses and runs refining rules over the source model.
    func run(_ declarations: String) async throws {
        try await run(try await module(declarations))
    }

    /// The target elements of a class, in creation order.
    func targets(_ className: String) async -> [DynamicEObject] {
        await targetResource.getAllObjects().compactMap { $0 as? DynamicEObject }
            .filter { $0.eClass.name == className }
    }

    /// The target element of a class with the given name.
    func target(_ className: String, named name: String) async -> DynamicEObject? {
        await targets(className).first { $0.eGet("name") as? String == name }
    }

    /// The target edge whose weight is the given value.
    func edge(weight: Int) async -> DynamicEObject? {
        await targets("Edge").first { $0.eGet("weight") as? Int == weight }
    }

    /// The current state of a source element.
    func source(_ element: DynamicEObject) async -> DynamicEObject? {
        await sourceResource.resolve(element.id) as? DynamicEObject
    }
}

// MARK: - Parsing

@Suite("ATL Refining Mode Parsing")
@MainActor
struct ATLRefiningModeParsingTests {

    @Test("A refining header declares a refining module")
    func refiningHeader() async throws {
        let module = try await ATLParser().parseContent(RefiningFixture.header)
        #expect(module.isRefining)
        #expect(Array(module.targetMetamodels.keys) == ["OUT"])
        #expect(Array(module.sourceMetamodels.keys) == ["IN"])
        #expect(module.declaredMetamodelNames == ["OUT": "Graph", "IN": "Graph"])
    }

    @Test("A refining header may declare several models")
    func severalModels() async throws {
        let module = try await ATLParser().parseContent(
            "module M;\ncreate OUT1 : A, OUT2 : B refining IN1 : A, IN2 : B;\n")
        #expect(module.isRefining)
        #expect(Array(module.targetMetamodels.keys) == ["OUT1", "OUT2"])
        #expect(Array(module.sourceMetamodels.keys) == ["IN1", "IN2"])
        #expect(module.declaredMetamodelNames["IN2"] == "B")
    }

    @Test("A header with 'from' declares an ordinary module")
    func fromHeader() async throws {
        let module = try await ATLParser().parseContent(
            "module M;\ncreate OUT : Graph from IN : Graph;\n")
        #expect(!module.isRefining)
    }

    @Test("The diagnosing parser accepts a refining header without diagnostics")
    func diagnosingParser() async throws {
        let source = RefiningFixture.header + "rule R { from s : Graph!Node to t : Graph!Node (name <- 'x') }\n"
        let result = await ATLParser().parseDiagnosing(source, name: "refine.atl")
        #expect(result.diagnostics.filter { $0.severity == .error }.isEmpty)
        #expect(result.module?.isRefining == true)
        #expect(result.module?.matchedRules.count == 1)
    }

    @Test("A malformed refining model declaration is rejected")
    func malformedRefiningHeader() async {
        await #expect(throws: ATLParseError.self) {
            try await ATLParser().parseContent("module M;\ncreate OUT : Graph refining IN Graph;\n")
        }
    }

    @Test("Refining mode can be requested for a module whose header uses 'from'")
    func requestRefining() async throws {
        let module = try await ATLParser().parseContent(
            """
            -- @param suffix : String = '!'
            module M;
            create OUT : Graph from IN : Graph;
            helper def : twice(n : Integer) : Integer = n * 2;
            rule R { from s : Graph!Node to t : Graph!Node (name <- s.name + thisModule.suffix) }
            """)
        let refined = module.refining()
        #expect(refined.isRefining)
        #expect(!module.isRefining)
        #expect(refined.name == module.name)
        #expect(Array(refined.sourceMetamodels.keys) == Array(module.sourceMetamodels.keys))
        #expect(Array(refined.targetMetamodels.keys) == Array(module.targetMetamodels.keys))
        #expect(Array(refined.helpers.keys) == Array(module.helpers.keys))
        #expect(refined.helperOverloads.keys == module.helperOverloads.keys)
        #expect(refined.matchedRules == module.matchedRules)
        #expect(refined.calledRules == module.calledRules)
        #expect(refined.parameters == module.parameters)
        #expect(refined.declaredMetamodelNames == module.declaredMetamodelNames)
        #expect(refined.origin.range == module.origin.range)
        #expect(refined.queryBody == nil)
        #expect(refined != module)
        #expect(refined.refining(false) == module)
        #expect(!refined.refining(false).isRefining)
    }

    @Test("Copies of a refining module stay in refining mode")
    func copiesKeepRefining() async throws {
        let module = try await ATLParser().parseContent(RefiningFixture.header)
        let fixture = RefiningFixture()
        #expect(
            module.withMetamodels(source: ["IN": fixture.package], target: ["OUT": fixture.package])
                .isRefining)
        #expect(module.withParameters([]).isRefining)
        #expect(module.declaringSourceModels(["IN": "Graph"]).isRefining)
    }
}

// MARK: - Execution

@Suite("ATL Refining Mode Execution")
@MainActor
struct ATLRefiningModeExecutionTests {

    @Test("Elements that no rule matches are copied with their values and references")
    func unmatchedElementsAreCopied() async throws {
        var fixture = RefiningFixture()
        await fixture.populate()
        try await fixture.run("")

        #expect(await fixture.targetResource.count() == 6)
        let sourceIDs = Set(await fixture.sourceResource.getAllObjects().map(\.id))
        let targetIDs = Set(await fixture.targetResource.getAllObjects().map(\.id))
        #expect(sourceIDs.isDisjoint(with: targetIDs))

        let graph = try #require(await fixture.target("Graph", named: "g"))
        let a = try #require(await fixture.target("Node", named: "a"))
        let b = try #require(await fixture.target("Node", named: "b"))
        let c = try #require(await fixture.target("Node", named: "c"))
        #expect(a.eGet("weight") as? Int == 1)
        #expect(c.eGet("label") as? String == "end")
        #expect(a.eGet("next") as? EUUID == b.id)
        #expect(b.eGet("next") as? EUUID == c.id)
        #expect(c.eGet("next") == nil)
        #expect(graph.eGet("nodes") as? [EUUID] == [a.id, b.id, c.id])
        let ab = try #require(await fixture.edge(weight: 12))
        #expect(ab.eGet("source") as? EUUID == a.id)
        #expect(ab.eGet("target") as? EUUID == b.id)
        #expect((graph.eGet("edges") as? [EUUID])?.count == 2)

        let roots = await fixture.targetResource.getRootObjects()
        #expect(roots.map(\.id) == [graph.id])
    }

    @Test("The source model is not modified")
    func sourceIsUnchanged() async throws {
        var fixture = RefiningFixture()
        await fixture.populate()
        try await fixture.run(
            "rule R { from s : Graph!Node to t : Graph!Node (name <- s.name + '!', next <- OclUndefined) }")

        #expect(await fixture.sourceResource.count() == 6)
        let a = try #require(await fixture.source(fixture.a))
        #expect(a.eGet("name") as? String == "a")
        #expect(a.eGet("next") as? EUUID == fixture.b.id)
        #expect(await fixture.sourceResource.getRootObjects().map(\.id) == [fixture.graph.id])
    }

    @Test("A matched element is modified in place, keeping its unbound features")
    func matchedElementIsModifiedInPlace() async throws {
        var fixture = RefiningFixture()
        await fixture.populate()
        try await fixture.run("rule R { from s : Graph!Node (s.name = 'a') to t : Graph!Node (name <- 'A') }")

        #expect(await fixture.targets("Node").count == 3)
        #expect(await fixture.target("Node", named: "a") == nil)
        let a = try #require(await fixture.target("Node", named: "A"))
        let b = try #require(await fixture.target("Node", named: "b"))
        #expect(a.eGet("weight") as? Int == 1)
        #expect(a.eGet("next") as? EUUID == b.id)
        let graph = try #require(await fixture.target("Graph", named: "g"))
        #expect((graph.eGet("nodes") as? [EUUID])?.first == a.id)
        let ab = try #require(await fixture.edge(weight: 12))
        #expect(ab.eGet("source") as? EUUID == a.id)
    }

    @Test("Other output pattern elements create new elements")
    func otherOutputElementsAreCreated() async throws {
        var fixture = RefiningFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule R {
                from s : Graph!Node
                to t : Graph!Node (label <- 'seen'),
                   m : Graph!Marker (text <- s.name, node <- t)
            }
            """)

        let nodes = await fixture.targets("Node")
        #expect(nodes.count == 3)
        #expect(nodes.allSatisfy { $0.eGet("label") as? String == "seen" })
        let markers = await fixture.targets("Marker")
        #expect(markers.count == 3)
        for marker in markers {
            let text = try #require(marker.eGet("text") as? String)
            let node = try #require(await fixture.target("Node", named: text))
            #expect(marker.eGet("node") as? EUUID == node.id)
        }
    }

    @Test("Values that refer to source elements resolve to their copies")
    func sourceReferencesResolveToCopies() async throws {
        var fixture = RefiningFixture()
        await fixture.populate()
        try await fixture.run(
            "rule Reverse { from e : Graph!Edge to t : Graph!Edge (source <- e.target, target <- e.source) }")

        let a = try #require(await fixture.target("Node", named: "a"))
        let b = try #require(await fixture.target("Node", named: "b"))
        let ab = try #require(await fixture.edge(weight: 12))
        #expect(ab.eGet("source") as? EUUID == b.id)
        #expect(ab.eGet("target") as? EUUID == a.id)
        #expect(await fixture.targets("Edge").count == 2)
    }

    @Test("Rules match and navigate the unmodified source model")
    func matchingReadsTheSource() async throws {
        var fixture = RefiningFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule Concatenate {
                from s : Graph!Node (s.name <> 'b')
                to t : Graph!Node (
                    name <- if s.next.oclIsUndefined() then s.name else s.name + s.next.name endif)
            }
            rule RenameB {
                from s : Graph!Node (s.name = 'b')
                to t : Graph!Node (name <- 'a', weight <- 20)
            }
            """)

        let names = Set(await fixture.targets("Node").compactMap { $0.eGet("name") as? String })
        #expect(names == ["ab", "a", "c"])
        let renamed = try #require(await fixture.target("Node", named: "a"))
        #expect(renamed.eGet("weight") as? Int == 20)
        let first = try #require(await fixture.target("Node", named: "ab"))
        #expect(first.eGet("weight") as? Int == 1)
    }

    @Test("Helpers, lazy rules and called rules work in refining mode")
    func helpersAndRules() async throws {
        var fixture = RefiningFixture()
        await fixture.populate()
        try await fixture.run(
            """
            helper context Graph!Node def : doubled : Integer = self.weight * 2;
            lazy rule Mark { from n : Graph!Node to m : Graph!Marker (text <- n.name, node <- n) }
            endpoint rule Done() { to m : Graph!Marker (text <- 'done') }
            rule Nodes { from s : Graph!Node to t : Graph!Node (weight <- s.doubled) }
            rule Graphs {
                from g : Graph!Graph
                to t : Graph!Graph (markers <- g.nodes->collect(n | thisModule.Mark(n)))
            }
            """)

        let weights = await fixture.targets("Node").compactMap { $0.eGet("weight") as? Int }
        #expect(weights.sorted() == [2, 4, 6])
        let graph = try #require(await fixture.target("Graph", named: "g"))
        let markerIDs = try #require(graph.eGet("markers") as? [EUUID])
        #expect(markerIDs.count == 3)
        for id in markerIDs {
            let marker = try #require(await fixture.targetResource.resolve(id) as? DynamicEObject)
            let text = try #require(marker.eGet("text") as? String)
            let node = try #require(await fixture.target("Node", named: text))
            #expect(marker.eGet("node") as? EUUID == node.id)
        }
        #expect(await fixture.targets("Marker").contains { $0.eGet("text") as? String == "done" })
        #expect(graph.eGet("nodes") as? [EUUID] != nil)
        #expect((graph.eGet("edges") as? [EUUID])?.count == 2)
    }

    @Test("resolveTemp finds an element modified in place")
    func resolveTempFindsInPlaceElement() async throws {
        var fixture = RefiningFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule Nodes { from s : Graph!Node to t : Graph!Node (label <- 'x') }
            rule Edges {
                from e : Graph!Edge
                to t : Graph!Edge (target <- thisModule.resolveTemp(e.source, 't'))
            }
            """)

        let a = try #require(await fixture.target("Node", named: "a"))
        let ab = try #require(await fixture.edge(weight: 12))
        #expect(ab.eGet("target") as? EUUID == a.id)
    }

    @Test("A rule whose output type differs creates new elements and keeps the copy")
    func differentOutputTypeKeepsCopy() async throws {
        var fixture = RefiningFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule Describe {
                from e : Graph!Edge
                to m : Graph!Marker (text <- e.source.name + '->' + e.target.name)
            }
            """)

        #expect(await fixture.targets("Edge").count == 2)
        let texts = Set(await fixture.targets("Marker").compactMap { $0.eGet("text") as? String })
        #expect(texts == ["a->b", "b->c"])
    }

    @Test("Refining mode requested for a 'from' module refines the source model")
    func requestedRefining() async throws {
        var fixture = RefiningFixture()
        await fixture.populate()
        let module = try await fixture.module(
            "rule R { from s : Graph!Node (s.name = 'a') to t : Graph!Node (name <- 'A') }",
            header: "module Refine;\ncreate OUT : Graph from IN : Graph;\n")
        try await fixture.run(module.refining())

        #expect(await fixture.targets("Node").count == 3)
        #expect(await fixture.targets("Graph").count == 1)
        let a = try #require(await fixture.target("Node", named: "A"))
        #expect(a.eGet("weight") as? Int == 1)
    }

    @Test("Each target model refines the source model in the same position")
    func severalModelPairs() async throws {
        var graphs = RefiningFixture()
        await graphs.populate()
        var semantics = SemanticsFixture()
        await semantics.populate()
        let parsed = try await ATLParser().parseContent(
            """
            module Refine;
            create OUT1 : Graph, OUT2 : Src refining IN1 : Graph, IN2 : Src;
            rule Graphs { from s : Graph!Node (s.name = 'a') to t : Graph!Node (name <- 'A') }
            rule Sources { from s : Src!Node (s.name = 'beta') to t : Src!Node (name <- 'BETA') }
            """)
        let module = parsed.withMetamodels(
            source: ["IN1": graphs.package, "IN2": semantics.source],
            target: ["OUT1": graphs.package, "OUT2": semantics.source])
        try await ATLVirtualMachine(module: module).execute(
            sources: ["IN1": graphs.sourceResource, "IN2": semantics.sourceResource],
            targets: ["OUT1": graphs.targetResource, "OUT2": semantics.targetResource])

        #expect(await graphs.targetResource.count() == 6)
        #expect(await graphs.target("Node", named: "A") != nil)
        #expect(await semantics.targetResource.count() == 7)
        let beta = try #require(await semantics.target("Node", named: "BETA"))
        #expect(beta.eGet("age") as? Int == 20)
        let alpha = try #require(await semantics.target("Node", named: "alpha"))
        #expect(alpha.eGet("next") as? EUUID == beta.id)
    }

    @Test("Refining mode requires as many target models as source models")
    func unequalModelCounts() async throws {
        var fixture = RefiningFixture()
        await fixture.populate()
        let parsed = try await ATLParser().parseContent(
            "module Refine;\ncreate OUT : Graph refining IN1 : Graph, IN2 : Graph;\n")
        let module = parsed.withMetamodels(
            source: ["IN1": fixture.package, "IN2": fixture.package], target: ["OUT": fixture.package])
        let other = Resource(uri: "test://other")
        await #expect {
            try await ATLVirtualMachine(module: module).execute(
                sources: ["IN1": fixture.sourceResource, "IN2": other],
                targets: ["OUT": fixture.targetResource])
        } throws: { error in
            guard case ATLExecutionError.invalidOperation(let message) = error else { return false }
            return message.lowercased().contains("refining") && message.contains("2") && message.contains("1")
        }
    }

    @Test("Refining mode requires each target model to conform to the metamodel it refines")
    func differentMetamodels() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        let parsed = try await ATLParser().parseContent(
            "module Refine;\ncreate OUT : Tgt refining IN : Src;\n")
        let module = parsed.withMetamodels(source: ["IN": fixture.source], target: ["OUT": fixture.target])
        await #expect {
            try await ATLVirtualMachine(module: module).execute(
                sources: ["IN": fixture.sourceResource], targets: ["OUT": fixture.targetResource])
        } throws: { error in
            guard case ATLExecutionError.invalidOperation(let message) = error else { return false }
            return message.contains("Tgt") && message.contains("Src")
        }
        #expect(await fixture.targetResource.count() == 0)
    }

    @Test("Refining mode rejects source elements that it cannot copy")
    func nativeElementsAreRejected() async throws {
        var fixture = RefiningFixture()
        await fixture.populate()
        await fixture.sourceResource.add(EClass(name: "Native"))
        await #expect {
            try await fixture.run("")
        } throws: { error in
            guard case ATLExecutionError.unsupportedOperation(let message) = error else { return false }
            return message.contains("EClass")
        }
    }
}
