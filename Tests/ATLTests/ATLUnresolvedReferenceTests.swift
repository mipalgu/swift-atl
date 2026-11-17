//
//  ATLUnresolvedReferenceTests.swift
//  ATLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ATL

/// Tests for source elements that no rule transforms in values bound to references.
@Suite("ATL Unresolved Reference Tests")
@MainActor
struct ATLUnresolvedReferenceTests {

    private let fixture = ReportFixture()

    /// A rule that transforms the tasks whose priority exceeds five, and a rule that binds
    /// all tasks of a project to references of its document.
    private func rules(_ bindings: String) -> String {
        """
        rule T {
            from s : Project!Task (s.priority > 5)
            to t : Report!Summary (title <- s.name)
        }
        rule P {
            from s : Project!Project
            to t : Report!Document (name <- s.name, \(bindings))
        }
        """
    }

    /// The summaries of a run by title.
    private func summaries(of run: ReportRun) async -> [String: EUUID] {
        var result: [String: EUUID] = [:]
        for summary in await run.elements("Summary") {
            if let title = await run.value("title", of: summary) as? String { result[title] = summary.id }
        }
        return result
    }

    /// Checks that the written documents hold no internal descriptions or source locations.
    private func expectWellFormed(_ run: ReportRun) async throws {
        for xml in try await run.documents() {
            #expect(!xml.contains("EcoreValueArray"))
            #expect(!xml.contains("ResourceProxy"))
            #expect(!xml.contains(ReportFixture.sourceURI))
            #expect(!xml.contains("summaries=\""))
        }
    }

    // MARK: - Containment References

    @Test("Resolved and unresolved tasks in a containment binding keep only the resolved summaries")
    func mixedContainment() async throws {
        let capture = ConsoleCapture()
        let run = try await fixture.run(rules("summaries <- s.tasks"), priorities: [8, 3, 9], capture: capture)
        let titles = await summaries(of: run)
        let stored = await run.value("summaries", of: try await run.document())
        #expect(stored as? [EUUID] == [try #require(titles["t1"]), try #require(titles["t3"])])
        try await expectWellFormed(run)
        for xml in try await run.documents() {
            #expect(xml.components(separatedBy: "<summaries").count - 1 == 2)
        }
    }

    @Test("A dropped element is reported as a warning naming the element, the feature and the class")
    func mixedContainmentWarning() async throws {
        let capture = ConsoleCapture()
        let run = try await fixture.run(rules("summaries <- s.tasks"), priorities: [8, 3, 9], capture: capture)
        let warnings = run.machine.getStatistics().warnings
        #expect(warnings.count == 1)
        let warning = try #require(warnings.first)
        #expect(warning.contains("Task 't2'"))
        #expect(warning.contains("summaries"))
        #expect(warning.contains("Document"))
        #expect(!warning.contains(ReportFixture.sourceURI))
        #expect(capture.errors.count == 1)
        #expect(capture.errors.first?.contains(warning) == true)
        #expect(capture.output.isEmpty)
        #expect(run.machine.getStatistics().summary().contains(warning))
    }

    @Test("Unresolved tasks in a containment binding are all dropped and each is reported")
    func unresolvedContainment() async throws {
        let capture = ConsoleCapture()
        let run = try await fixture.run(rules("summaries <- s.tasks"), priorities: [1, 2], capture: capture)
        let stored = await run.value("summaries", of: try await run.document())
        #expect((stored as? [EUUID])?.isEmpty ?? (stored == nil))
        let warnings = run.machine.getStatistics().warnings
        #expect(warnings.count == 2)
        #expect(warnings.contains { $0.contains("Task 't1'") })
        #expect(warnings.contains { $0.contains("Task 't2'") })
        #expect(capture.errors.count == 2)
        try await expectWellFormed(run)
    }

    @Test("Resolved tasks in a containment binding are kept without a warning")
    func resolvedContainment() async throws {
        let capture = ConsoleCapture()
        let run = try await fixture.run(rules("summaries <- s.tasks"), priorities: [8, 9], capture: capture)
        let titles = await summaries(of: run)
        let stored = await run.value("summaries", of: try await run.document())
        #expect(stored as? [EUUID] == [try #require(titles["t1"]), try #require(titles["t2"])])
        #expect(run.machine.getStatistics().warnings.isEmpty)
        #expect(capture.errors.isEmpty)
        try await expectWellFormed(run)
    }

    @Test("An unresolved task bound to a single-valued containment reference leaves it unset")
    func unresolvedSingleContainment() async throws {
        let capture = ConsoleCapture()
        let run = try await fixture.run(
            rules("main <- s.tasks->first()"), priorities: [3, 9], capture: capture)
        #expect(await run.value("main", of: try await run.document()) == nil)
        #expect(run.machine.getStatistics().warnings.count == 1)
        #expect(run.machine.getStatistics().warnings.first?.contains("main") == true)
        #expect(capture.errors.count == 1)
        try await expectWellFormed(run)
    }

    @Test("An assignment in a do section drops unresolved elements from a containment reference")
    func imperativeContainment() async throws {
        let capture = ConsoleCapture()
        let run = try await fixture.run(
            """
            rule T {
                from s : Project!Task (s.priority > 5)
                to t : Report!Summary (title <- s.name)
            }
            rule P {
                from s : Project!Project
                to t : Report!Document (name <- s.name)
                do { t.summaries <- s.tasks; }
            }
            """, priorities: [8, 3], capture: capture)
        let titles = await summaries(of: run)
        let stored = await run.value("summaries", of: try await run.document())
        #expect(stored as? [EUUID] == [try #require(titles["t1"])])
        #expect(run.machine.getStatistics().warnings.count == 1)
    }

    @Test("A new run starts without the warnings of the previous run")
    func warningsReset() async throws {
        let module = try await fixture.module(rules("summaries <- s.tasks"))
        let machine = ATLVirtualMachine(module: module, options: .standard)
        let capture = ConsoleCapture()
        machine.executionContext.console = capture.console
        for _ in 0..<2 {
            let target = await ResourceSet().createResource(uri: ReportFixture.targetURI)
            try await machine.execute(
                sources: ["IN": await fixture.projectModel(priorities: [8, 3])], targets: ["OUT": target])
            #expect(machine.getStatistics().warnings.count == 1)
        }
        #expect(capture.errors.count == 2)
    }

    // MARK: - Non-containment References

    @Test("Unresolved tasks in a non-containment binding remain references into the source model")
    func nonContainmentKeepsReferences() async throws {
        let capture = ConsoleCapture()
        let run = try await fixture.run(rules("highlights <- s.tasks"), priorities: [1, 2], capture: capture)
        let proxies = try #require(
            await run.value("highlights", of: try await run.document()) as? [ResourceProxy])
        #expect(proxies.map(\.uri) == [ReportFixture.sourceURI, ReportFixture.sourceURI])
        #expect(run.machine.getStatistics().warnings.isEmpty)
        #expect(capture.errors.isEmpty)
    }
}
