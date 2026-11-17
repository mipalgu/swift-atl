//
//  ATLMultiRootReferenceTests.swift
//  ATLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ATL

/// Tests that references from a target model into a source model with several root
/// elements locate each element as the Eclipse Modeling Framework does.
@Suite("ATL Multi-Root Reference Tests")
@MainActor
struct ATLMultiRootReferenceTests {

    private let fixture = ReportFixture()

    /// The names of the projects at the roots of the source model, with the names of their tasks.
    private static let projects: [(name: String, tasks: [String])] = [
        ("a", ["a1"]), ("b", ["b1", "b2"]), ("c", ["c1"]),
    ]

    /// Creates a source model with one root project per entry of ``projects``.
    ///
    /// - Parameters:
    ///   - uri: The URI of the source model.
    ///   - resourceSet: The resource set that holds the model and its metamodel, if any.
    /// - Returns: The model.
    private func multiRootModel(uri: String = ReportFixture.sourceURI, in resourceSet: ResourceSet? = nil) async
        -> Resource
    {
        let resource: Resource
        if let resourceSet {
            await resourceSet.registerMetamodel(fixture.project, uri: fixture.project.nsURI)
            resource = await resourceSet.createResource(uri: uri)
        } else {
            resource = Resource(uri: uri)
        }
        for (name, tasks) in Self.projects {
            var project = DynamicEObject(eClass: fixture.projectClass)
            project.eSet("name", value: name)
            var taskIDs: [EUUID] = []
            for (index, taskName) in tasks.enumerated() {
                var task = DynamicEObject(eClass: fixture.taskClass)
                task.eSet("name", value: taskName)
                task.eSet("priority", value: index)
                await resource.register(task)
                taskIDs.append(task.id)
            }
            await resource.register(project)
            await resource.add(project)
            await resource.eSet(objectId: project.id, feature: "tasks", value: taskIDs)
        }
        return resource
    }

    /// The element of a resource with a name.
    ///
    /// - Parameters:
    ///   - name: The name.
    ///   - resource: The resource.
    /// - Returns: The element.
    /// - Throws: When the resource holds no element of that name.
    private func element(named name: String, in resource: Resource) async throws -> any EObject {
        try #require(await resource.getAllObjects().first { ($0 as? DynamicEObject)?.eGet("name") as? String == name })
    }

    /// The rule that creates a document per project and refers to its untransformed tasks.
    private let rules = """
        rule P {
            from s : Project!Project
            to t : Report!Document (name <- s.name, highlights <- s.tasks)
        }
        """

    // MARK: - Fragments

    @Test("Each root of a resource with several roots is addressed by its position")
    func rootFragments() async throws {
        let source = await multiRootModel()
        var fragments: [String] = []
        for root in await source.getRootObjects() {
            fragments.append(await ATLReferenceStorage.fragment(for: root, in: source))
        }
        #expect(fragments == ["/0", "/1", "/2"])
    }

    @Test("The contents of a root of a resource with several roots are addressed below that root")
    func contentFragments() async throws {
        let source = await multiRootModel()
        var fragments: [String: String] = [:]
        for name in ["a1", "b1", "b2", "c1"] {
            fragments[name] = await ATLReferenceStorage.fragment(for: try await element(named: name, in: source), in: source)
        }
        #expect(fragments == ["a1": "/0/@tasks.0", "b1": "/1/@tasks.0", "b2": "/1/@tasks.1", "c1": "/2/@tasks.0"])
    }

    @Test("The only root of a resource and its contents keep their fragments")
    func singleRootFragments() async throws {
        let source = await fixture.projectModel(priorities: [1, 2])
        let root = try #require(await source.getRootObjects().first)
        #expect(await ATLReferenceStorage.fragment(for: root, in: source) == "/")
        let second = try await element(named: "t2", in: source)
        #expect(await ATLReferenceStorage.fragment(for: second, in: source) == "//@tasks.1")
    }

    @Test("The packages of an Ecore resource with several roots, and their classes, are located below their root")
    func ecoreRootFragments() async throws {
        let resource = Resource(uri: "test://packages.ecore")
        let first = EPackage(name: "first", nsURI: "http://example.org/first", nsPrefix: "first",
                             eClassifiers: [EClass(name: "Book")])
        let second = EPackage(name: "second", nsURI: "http://example.org/second", nsPrefix: "second",
                              eClassifiers: [EClass(name: "Book"), EClass(name: "Shelf")])
        await resource.add(first)
        await resource.add(second)
        #expect(await ATLReferenceStorage.fragment(for: first, in: resource) == "/0")
        #expect(await ATLReferenceStorage.fragment(for: second, in: resource) == "/1")
        let book = try #require(second.getEClass("Book"))
        let shelf = try #require(second.getEClass("Shelf"))
        #expect(await ATLReferenceStorage.fragment(for: book, in: resource) == "/1/Book")
        #expect(await ATLReferenceStorage.fragment(for: shelf, in: resource) == "/1/Shelf")
    }

    // MARK: - Transformations

    @Test("References to the contents of each root of a source model carry the fragment of that root", arguments: [ATLOptions.standard, ATLOptions.legacy])
    func proxies(options: ATLOptions) async throws {
        let module = try await fixture.module(rules, options: options)
        let source = await multiRootModel()
        let target = await ResourceSet().createResource(uri: ReportFixture.targetURI)
        try await ATLVirtualMachine(module: module, options: options).execute(
            sources: ["IN": source], targets: ["OUT": target])
        var fragments: [String: [String]] = [:]
        for case let document as DynamicEObject in await target.getAllObjects() where document.eClass.name == "Document" {
            let name = try #require(document.eGet("name") as? String)
            let proxies = await target.eGet(objectId: document.id, feature: "highlights") as? [ResourceProxy]
            fragments[name] = proxies?.map(\.fragment)
        }
        #expect(fragments == ["a": ["/0/@tasks.0"], "b": ["/1/@tasks.0", "/1/@tasks.1"], "c": ["/2/@tasks.0"]])
    }

    @Test("A written target model refers to the elements of each root of its source model")
    func loadsBack() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("atl-multi-root-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appendingPathComponent("projects.xmi")
        let targetURL = directory.appendingPathComponent("reports.xmi")

        let source = await multiRootModel(uri: sourceURL.absoluteString, in: ResourceSet())
        try await XMISerializer().serialize(source, to: sourceURL)
        let target = await ResourceSet().createResource(uri: targetURL.absoluteString)
        try await ATLVirtualMachine(module: try await fixture.module(rules), options: .standard).execute(
            sources: ["IN": source], targets: ["OUT": target])
        try await XMISerializer().serialize(target, to: targetURL)

        let resourceSet = ResourceSet()
        await resourceSet.registerMetamodel(fixture.project, uri: fixture.project.nsURI)
        await resourceSet.registerMetamodel(fixture.report, uri: fixture.report.nsURI)
        let loaded = try await XMIParser(resourceSet: resourceSet).parse(targetURL)
        var highlights: [String: [String]] = [:]
        for case let document as DynamicEObject in await loaded.getAllObjects() where document.eClass.name == "Document" {
            let name = try #require(document.eGet("name") as? String)
            let value = await loaded.eGet(objectId: document.id, feature: "highlights")
            var names: [String] = []
            for reference in ATLCollections.elements(of: value) {
                let task: (any EObject)?
                if let proxy = reference as? ResourceProxy {
                    task = await proxy.resolveObject(in: resourceSet)
                } else if let id = reference as? EUUID {
                    task = await resourceSet.resolve(id)?.object
                } else {
                    task = nil
                }
                names.append(try #require((task as? DynamicEObject)?.eGet("name") as? String))
            }
            highlights[name] = names
        }
        #expect(highlights == ["a": ["a1"], "b": ["b1", "b2"], "c": ["c1"]])
    }
}
