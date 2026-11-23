//
//  ATLCurrentTimeTests.swift
//  ATLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ATL

/// Tests the built-in module operation `getCurrentTime()` and the clock it reads.
@Suite("ATL Current Time Tests")
@MainActor
struct ATLCurrentTimeTests {

    private let fixture = ReportFixture()

    /// Creates an execution context for helpers over an empty project.
    ///
    /// - Parameter declarations: The helpers of the module.
    /// - Returns: The context.
    private func context(_ declarations: String) async throws -> ATLExecutionContext {
        let module = try await fixture.module(declarations)
        return ATLExecutionContext(
            module: module, sources: ["IN": await fixture.projectModel(priorities: [])], targets: [:],
            executionEngine: ECoreExecutionEngine(models: [:]))
    }

    @Test("getCurrentTime returns the milliseconds of the clock of the context")
    func fixedClock() async throws {
        let context = try await context("helper def : now : Integer = thisModule.getCurrentTime();")
        context.clock = .fixed(1_234_567)
        #expect(try await context.callHelper("now", arguments: []) as? Int == 1_234_567)
        #expect(try await context.callHelper(ATLReservedNames.getCurrentTime, arguments: []) as? Int == 1_234_567)
    }

    @Test("The system clock counts the milliseconds since the Unix epoch")
    func systemClock() async throws {
        let context = try await context("helper def : now : Integer = thisModule.getCurrentTime();")
        let before = Int((Date().timeIntervalSince1970 * 1000).rounded(.down))
        let now = try #require(try await context.callHelper("now", arguments: []) as? Int)
        let after = Int((Date().timeIntervalSince1970 * 1000).rounded(.up))
        #expect(before <= now && now <= after)
        #expect(ATLClock.system.millisecondsSinceEpoch() >= before)
    }

    @Test("A helper of the module called getCurrentTime takes precedence over the operation")
    func moduleHelperWins() async throws {
        let context = try await context(
            """
            helper def : getCurrentTime() : Integer = 7;
            helper def : now : Integer = thisModule.getCurrentTime();
            """)
        context.clock = .fixed(99)
        #expect(try await context.callHelper("now", arguments: []) as? Int == 7)
    }

    @Test("getCurrentTime takes no arguments")
    func noArguments() async throws {
        let context = try await context("helper def : now : Integer = thisModule.getCurrentTime(1);")
        await #expect(throws: ATLExecutionError.self) { _ = try await context.callHelper("now", arguments: []) }
    }

    @Test("A virtual machine and an incremental transformation give rules the clock they are set to")
    func machineClock() async throws {
        let rules = """
            rule P {
                from s : Project!Project
                to t : Report!Document (name <- s.name, total <- thisModule.getCurrentTime())
            }
            """
        let module = try await fixture.module(rules)
        let target = await ResourceSet().createResource(uri: ReportFixture.targetURI)
        let machine = ATLVirtualMachine(module: module, options: .standard)
        machine.clock = .fixed(42)
        #expect(machine.clock.millisecondsSinceEpoch() == 42)
        try await machine.execute(
            sources: ["IN": await fixture.projectModel(priorities: [])], targets: ["OUT": target])
        let document = try #require(await target.getAllObjects().first as? DynamicEObject)
        #expect((document.eGet("total") as? Int) == 42 || (document.eGet("total") as? Int64) == 42)

        let incrementalTarget = await ResourceSet().createResource(uri: ReportFixture.targetURI)
        let transformation = ATLIncrementalTransformation(module: module, options: .standard)
        transformation.clock = .fixed(43)
        #expect(transformation.clock.millisecondsSinceEpoch() == 43)
        try await transformation.execute(
            sources: ["IN": await fixture.projectModel(priorities: [])], targets: ["OUT": incrementalTarget])
        let incremental = try #require(await incrementalTarget.getAllObjects().first as? DynamicEObject)
        #expect((incremental.eGet("total") as? Int) == 43 || (incremental.eGet("total") as? Int64) == 43)
    }
}
