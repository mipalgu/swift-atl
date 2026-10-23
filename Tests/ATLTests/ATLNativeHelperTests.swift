//
//  ATLNativeHelperTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 23/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import OrderedCollections
import Testing

@testable import ATL

/// Tests for helpers implemented in Swift and called from ATL expressions.
@Suite("ATL Native Helper Tests")
@MainActor
struct ATLNativeHelperTests {

    private let fixture = ShapeFixture()

    private static let render = ATLNativeHelper(
        name: "render", contextType: "Shapes!Shape", parameterTypes: ["String"],
        returnType: "String"
    ) { receiver, arguments in
        let name = (receiver as? DynamicEObject)?.eGet("name") as? String ?? "?"
        return "\(name)-\(arguments.first.flatMap { $0 as? String } ?? "")"
    }

    private static let greet = ATLNativeHelper(
        name: "greet", contextType: nil, parameterTypes: ["String"], returnType: "String"
    ) { _, arguments in
        "hello \(arguments.first.flatMap { $0 as? String } ?? "")"
    }

    private func transform(
        binding: String, declarations: String = "", helpers: [ATLNativeHelper] = [],
        registering later: [ATLNativeHelper] = []
    ) async throws -> String? {
        let source = """
            module Shapes2Shapes;
            create OUT : Shapes from IN : Shapes;
            \(declarations)
            rule Circle2Circle {
                from s : Shapes!Circle
                to t : Shapes!Circle ( name <- \(binding), radius <- 1 )
            }
            """
        let registry = ATLMetamodelRegistry(packages: [fixture.package])
        let module = try await ATLParser().parseContent(source, metamodelRegistry: registry)
        let input = Resource(uri: "test://in")
        await input.add(fixture.make(fixture.circle, ["name": "c1"]))
        let output = Resource(uri: "test://out")
        let machine = ATLVirtualMachine(module: module, nativeHelpers: helpers)
        for helper in later { machine.register(helper) }
        try await machine.execute(sources: ["IN": input], targets: ["OUT": output])
        let roots = await output.getRootObjects()
        return (roots.first as? DynamicEObject)?.eGet("name") as? String
    }

    @Test("A native contextual helper is called on a source element")
    func contextualHelper() async throws {
        let result = try await transform(binding: "s.render('x')", helpers: [Self.render])
        #expect(result == "c1-x")
    }

    @Test("A native module-level helper is called through thisModule")
    func moduleHelperThroughThisModule() async throws {
        let result = try await transform(binding: "thisModule.greet('a')", helpers: [Self.greet])
        #expect(result == "hello a")
    }

    @Test("A native module-level helper is called by plain name")
    func moduleHelperByName() async throws {
        let result = try await transform(binding: "greet('a')", helpers: [Self.greet])
        #expect(result == "hello a")
    }

    @Test("A native helper registered after creation is called")
    func registeredAfterInit() async throws {
        let result = try await transform(binding: "s.render('y')", registering: [Self.render])
        #expect(result == "c1-y")
    }

    @Test("A native contextual helper does not apply to receivers of another type")
    func contextMismatch() async throws {
        let square = ATLNativeHelper(
            name: "render", contextType: "Shapes!Square", parameterTypes: ["String"],
            returnType: "String"
        ) { _, _ in "square" }
        await #expect(throws: (any Error).self) {
            _ = try await transform(binding: "s.render('x')", helpers: [square])
        }
    }

    @Test("A native helper wins over a module helper of the same name")
    func nativeWinsOverModuleHelper() async throws {
        let declarations = "helper def : greet(p : String) : String = 'module ' + p;"
        let moduleOnly = try await transform(
            binding: "thisModule.greet('a')", declarations: declarations)
        #expect(moduleOnly == "module a")
        let withNative = try await transform(
            binding: "thisModule.greet('a')", declarations: declarations, helpers: [Self.greet])
        #expect(withNative == "hello a")
    }

    @Test("A native contextual helper wins over a module helper for the same context")
    func nativeWinsOverContextualModuleHelper() async throws {
        let declarations =
            "helper context Shapes!Circle def : render(p : String) : String = 'module ' + p;"
        let result = try await transform(
            binding: "s.render('x')", declarations: declarations, helpers: [Self.render])
        #expect(result == "c1-x")
    }

    @Test("A throwing native helper produces an error naming the helper")
    func throwingHelper() async throws {
        struct Failure: Error {}
        let failing = ATLNativeHelper(
            name: "explode", contextType: nil, parameterTypes: [], returnType: "String"
        ) { _, _ in throw Failure() }
        do {
            _ = try await transform(binding: "thisModule.explode()", helpers: [failing])
            Issue.record("Expected the transformation to fail")
        } catch {
            #expect("\(error)".contains("explode"))
        }
    }

    @Test("A native helper exposes its signature as a helper")
    func signature() {
        let helper = Self.render
        #expect(helper.name == "render")
        #expect(helper.contextType == "Shapes!Shape")
        #expect(helper.returnType == "String")
        #expect(helper.parameters.map(\.type) == ["String"])
    }
}
