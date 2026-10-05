//
//  ATLProgressTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import OrderedCollections
import Testing

@testable import ATL

/// Collects progress snapshots delivered on the main actor.
@MainActor
private final class ProgressLog {
    var snapshots: [ATLProgress] = []
}

/// Tests for progress reporting, cancellation and cooperative yielding.
@Suite("ATL Progress Tests")
@MainActor
struct ATLProgressTests {

    private let fixture = ShapeFixture()

    private static let moduleText = """
        module Copy;
        create OUT : Shapes from IN : Shapes;
        entrypoint rule Start() {
            to t : Shapes!Square ( name <- 'start' )
        }
        rule Circle2Circle {
            from s : Shapes!Circle
            to t : Shapes!Circle ( name <- s.name, radius <- s.radius )
        }
        endpoint rule Finish() {
            to t : Shapes!Square ( name <- 'finish' )
        }
        """

    private func makeMachine() async throws -> ATLVirtualMachine {
        let registry = ATLMetamodelRegistry(packages: [fixture.package])
        let module = try await ATLParser().parseContent(
            Self.moduleText, metamodelRegistry: registry)
        return ATLVirtualMachine(module: module)
    }

    private func makeSource(count: Int) async -> Resource {
        let source = Resource(uri: "test://in")
        for index in 0..<count {
            await source.add(fixture.make(fixture.circle, ["name": "c\(index)", "radius": 1.0]))
        }
        return source
    }

    @Test("Progress is monotonic, ordered by phase and ends in finished")
    func progressSequence() async throws {
        let machine = try await makeMachine()
        let log = ProgressLog()
        let target = Resource(uri: "test://out")
        try await machine.execute(
            sources: ["IN": await makeSource(count: 12)], targets: ["OUT": target],
            parameters: [:], progress: { log.snapshots.append($0) })

        let snapshots = log.snapshots
        #expect(snapshots.last?.phase == .finished)
        #expect(snapshots.filter { $0.phase == .finished }.count == 1)
        #expect(snapshots.map(\.phase) == snapshots.map(\.phase).sorted())
        let phases = Set(snapshots.map(\.phase))
        #expect(phases == Set(ATLProgressPhase.allCases))
        for phase in ATLProgressPhase.allCases {
            let completed = snapshots.filter { $0.phase == phase }.map(\.completed)
            #expect(completed == completed.sorted())
        }
        let applying = snapshots.filter { $0.phase == .applying }
        #expect(applying.last?.completed == 12)
        #expect(applying.last?.total == 12)
        #expect(applying.last?.fractionCompleted == 1)
        #expect(applying.first?.currentRule == "Circle2Circle")
        #expect(snapshots.first(where: { $0.phase == .matching })?.currentRule == "Circle2Circle")
        #expect(snapshots.first(where: { $0.phase == .entrypoint })?.total == 1)
        #expect(snapshots.first(where: { $0.phase == .endpoint })?.total == 1)
    }

    @Test("The existing execute signature still works")
    func existingSignature() async throws {
        let machine = try await makeMachine()
        let target = Resource(uri: "test://out")
        try await machine.execute(
            sources: ["IN": await makeSource(count: 3)], targets: ["OUT": target])
        #expect(machine.statistics.successful)
        #expect(await target.getAllInstancesOf(fixture.circle).count == 3)
    }

    @Test("A cancelled run throws CancellationError and leaves the targets partly populated")
    func cancellationMidRun() async throws {
        let machine = try await makeMachine()
        let target = Resource(uri: "test://out")
        let source = await makeSource(count: 10)
        let log = ProgressLog()
        let run = Task { @MainActor in
            try await machine.execute(
                sources: ["IN": source], targets: ["OUT": target], parameters: [:],
                progress: { progress in
                    log.snapshots.append(progress)
                    if progress.phase == .applying && progress.completed == 3 {
                        withUnsafeCurrentTask { $0?.cancel() }
                    }
                })
        }
        await #expect(throws: CancellationError.self) { try await run.value }

        #expect(log.snapshots.contains { $0.phase == .applying })
        #expect(!log.snapshots.contains { $0.phase == .finished })
        #expect(!machine.statistics.successful)
        let circles = await target.getAllInstancesOf(fixture.circle)
        #expect(circles.count == 10)
        let named = circles.filter { (($0 as? DynamicEObject)?.eGet("name") as? String) != nil }
        #expect(named.count == 3)
    }

    @Test("A task cancelled before the run starts throws immediately")
    func cancelledBeforeStart() async throws {
        let machine = try await makeMachine()
        let target = Resource(uri: "test://out")
        let source = await makeSource(count: 5)
        let run = Task { @MainActor in
            withUnsafeCurrentTask { $0?.cancel() }
            try await machine.execute(sources: ["IN": source], targets: ["OUT": target])
        }
        await #expect(throws: CancellationError.self) { try await run.value }
        #expect(await target.getAllInstancesOf(fixture.circle).isEmpty)
    }

    @Test("A long run lets a concurrent main-actor task make progress")
    func longRunStaysResponsive() async throws {
        let machine = try await makeMachine()
        let source = await makeSource(count: 400)
        let target = Resource(uri: "test://out")
        var finished = false
        let counter = Counter()
        let ticker = Task { @MainActor in
            while !finished {
                counter.value += 1
                await Task.yield()
            }
        }
        try await machine.execute(sources: ["IN": source], targets: ["OUT": target])
        finished = true
        await ticker.value
        #expect(counter.value > 1)
    }

    @Test("A checkpoint suspends once the time budget is used")
    func checkpointYields() async throws {
        let monitor = ATLRunMonitor(handler: nil, budget: .milliseconds(1))
        let counter = Counter()
        var finished = false
        let ticker = Task { @MainActor in
            while !finished {
                counter.value += 1
                await Task.yield()
            }
        }
        let start = ContinuousClock.now
        while ContinuousClock.now - start < .milliseconds(5) {}
        let before = counter.value
        try await monitor.checkpoint()
        #expect(counter.value > before)
        finished = true
        await ticker.value
    }

    @Test("A checkpoint within budget does not suspend")
    func checkpointWithinBudget() async throws {
        let monitor = ATLRunMonitor(handler: nil, budget: .seconds(60))
        let counter = Counter()
        let ticker = Task { @MainActor in counter.value += 1 }
        try await monitor.checkpoint()
        #expect(counter.value == 0)
        await ticker.value
    }

    @Test("Fractions handle unknown and empty totals")
    func fractions() {
        #expect(ATLProgress(phase: .matching, completed: 1).fractionCompleted == nil)
        #expect(ATLProgress(phase: .matching, completed: 0, total: 0).fractionCompleted == 1)
        #expect(ATLProgress(phase: .applying, completed: 1, total: 4).fractionCompleted == 0.25)
    }
}

/// A mutable counter confined to the main actor.
@MainActor
private final class Counter {
    var value = 0
}
