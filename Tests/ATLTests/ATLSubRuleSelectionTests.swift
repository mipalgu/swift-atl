//
//  ATLSubRuleSelectionTests.swift
//  ATLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ATL

/// Tests that the first matching sub-rule transforms an element that several sub-rules of
/// one rule match, as in Eclipse ATL, with a warning, and that strict options make it an error.
@Suite("ATL Sub-Rule Selection Tests")
@MainActor
struct ATLSubRuleSelectionTests {

    private let fixture = ReportFixture()

    /// The presets, which both report sibling sub-rules with a warning.
    nonisolated static let presets = [ATLOptions.standard, ATLOptions.legacy]

    /// The rule that creates the document of the project.
    private let projectRule = """
        rule P {
            from s : Project!Project
            to t : Report!Document (name <- s.name, highlights <- s.tasks)
        }
        """

    /// Options that make sibling sub-rules matching one element an error.
    ///
    /// - Parameter options: The options to start from.
    /// - Returns: The options with ``ATLSiblingRuleConflicts/error``.
    private func strict(_ options: ATLOptions) -> ATLOptions {
        var strict = options
        strict.siblingRuleConflicts = .error
        return strict
    }

    /// The rank of the summary of each task, by title.
    ///
    /// - Parameter elements: The summaries.
    /// - Returns: The rank of each summary, by title; `0` for an unset rank.
    private func ranks(_ elements: [DynamicEObject]) -> [String: Int] {
        var result: [String: Int] = [:]
        for summary in elements {
            if let title = summary.eGet("title") as? String { result[title] = summary.eGet("rank") as? Int ?? 0 }
        }
        return result
    }

    /// The summaries of a target model.
    ///
    /// - Parameter target: The target model.
    /// - Returns: The summaries, in creation order.
    private func summaries(of target: Resource) async -> [DynamicEObject] {
        await target.getAllObjects().compactMap { $0 as? DynamicEObject }.filter { $0.eClass.name == "Summary" }
    }

    // MARK: - Options

    @Test("Both presets and the default options report sibling sub-rules with a warning")
    func presetsWarn() {
        #expect(ATLOptions().siblingRuleConflicts == .warning)
        #expect(ATLOptions.standard.siblingRuleConflicts == .warning)
        #expect(ATLOptions.legacy.siblingRuleConflicts == .warning)
        #expect(ATLOptions(semantics: .legacy).siblingRuleConflicts == .warning)
    }

    @Test("The choices are spelt as on a command line and can be set when the options are created")
    func spellings() {
        #expect(ATLSiblingRuleConflicts.allCases.map(\.rawValue) == ["warning", "error"])
        #expect(ATLSiblingRuleConflicts(rawValue: "error") == .error)
        let options = ATLOptions(siblingRuleConflicts: .error)
        #expect(options.siblingRuleConflicts == .error)
        #expect(options.integerDivision == ATLOptions.standard.integerDivision)
        #expect(options != .standard)
    }

    // MARK: - Order

    @Test("A sub-rule with a guard is tried before an earlier sub-rule without one", arguments: presets)
    func guardedBeforeUnguarded(options: ATLOptions) async throws {
        let rules =
            """
            abstract rule Base {
                from s : Project!Task
                to t : Report!Summary (title <- s.name)
            }
            rule Plain extends Base {
                from s : Project!Task
                to t : Report!Summary (rank <- 0)
            }
            rule Urgent extends Base {
                from s : Project!Task (s.priority > 5)
                to t : Report!Summary (rank <- 1)
            }
            """ + projectRule
        let run = try await fixture.run(rules, priorities: [8, 3], options: options)
        #expect(ranks(await run.elements("Summary")) == ["t1": 1, "t2": 0])
        let warnings = run.machine.getStatistics().warnings
        #expect(warnings.count == 1)
        let warning = try #require(warnings.first)
        #expect(warning.contains("'Plain'") && warning.contains("'Urgent'") && warning.contains("'Base'"))
        #expect(warning.contains("Task 't1'") && !warning.contains("Task 't2'"))
        #expect(warning.contains("only 'Urgent' is applied"))

        let message = try #require(
            await thrownDescription {
                _ = try await fixture.run(rules, priorities: [8, 3], options: strict(options))
            })
        #expect(message.contains("'Plain'") && message.contains("'Urgent'") && message.contains("Task 't1'"))
    }

    @Test("Of two sub-rules without guards the one declared first applies", arguments: presets)
    func declarationOrder(options: ATLOptions) async throws {
        let run = try await fixture.run(
            """
            abstract rule Base {
                from s : Project!Task
                to t : Report!Summary (title <- s.name)
            }
            rule First extends Base {
                from s : Project!Task
                to t : Report!Summary (rank <- 1)
            }
            rule Second extends Base {
                from s : Project!Task
                to t : Report!Summary (rank <- 2)
            }
            """ + projectRule, priorities: [8, 3], options: options)
        #expect(ranks(await run.elements("Summary")) == ["t1": 1, "t2": 1])
        let warnings = run.machine.getStatistics().warnings
        #expect(warnings.count == 2)
        #expect(warnings.allSatisfy { $0.contains("only 'First' is applied") && $0.contains("'Second'") })
    }

    @Test("The sub-rules of a matching sub-rule are tried in turn, and the warning names the first siblings")
    func nestedSubRules() async throws {
        let run = try await fixture.run(
            """
            abstract rule Base {
                from s : Project!Task
                to t : Report!Summary (title <- s.name)
            }
            rule Mid extends Base {
                from s : Project!Task (s.priority > 5)
                to t : Report!Summary (rank <- 1)
            }
            rule Top extends Mid {
                from s : Project!Task (s.priority > 7)
                to t : Report!Summary (rank <- 2)
            }
            rule Other extends Base {
                from s : Project!Task (s.priority > 6)
                to t : Report!Summary (rank <- 3)
            }
            """ + projectRule, priorities: [8, 6, 1])
        #expect(ranks(await run.elements("Summary")) == ["t1": 2, "t2": 1])
        let warnings = run.machine.getStatistics().warnings
        #expect(warnings.count == 1)
        let warning = try #require(warnings.first)
        #expect(warning.contains("'Mid'") && warning.contains("'Other'") && warning.contains("Task 't1'"))
        #expect(warning.contains("only 'Mid' is applied"))
    }

    @Test("A rule and a sub-rule that both match an element apply the sub-rule without a warning")
    func parentAndChild() async throws {
        let capture = ConsoleCapture()
        let run = try await fixture.run(
            """
            rule Base {
                from s : Project!Task
                to t : Report!Summary (title <- s.name)
            }
            rule Urgent extends Base {
                from s : Project!Task (s.priority > 5)
                to t : Report!Summary (rank <- 1)
            }
            """ + projectRule, priorities: [8, 3], capture: capture)
        #expect(ranks(await run.elements("Summary")) == ["t1": 1, "t2": 0])
        #expect(run.machine.getStatistics().warnings.isEmpty)
        #expect(capture.errors.isEmpty)
    }

    @Test("Three sub-rules that match one element are all named in the warning")
    func threeSiblings() async throws {
        let run = try await fixture.run(
            """
            abstract rule Base {
                from s : Project!Task
                to t : Report!Summary (title <- s.name)
            }
            rule A extends Base { from s : Project!Task (s.priority > 1) to t : Report!Summary (rank <- 1) }
            rule B extends Base { from s : Project!Task (s.priority > 2) to t : Report!Summary (rank <- 2) }
            rule C extends Base { from s : Project!Task (s.priority > 3) to t : Report!Summary (rank <- 3) }
            """ + projectRule, priorities: [8])
        let warning = try #require(run.machine.getStatistics().warnings.first)
        #expect(warning.contains("Rules 'A', 'B' and 'C'"))
        #expect(warning.contains("all match"))
        #expect(warning.contains("only 'A' is applied"))
    }

    @Test("Sub-rules with several source elements that match the same tuple name the elements by variable")
    func siblingTuples() async throws {
        let rules =
            """
            abstract rule Base {
                from s : Project!Task, p : Project!Project
                to t : Report!Summary (title <- p.name + '/' + s.name)
            }
            rule Urgent extends Base {
                from s : Project!Task, p : Project!Project (s.priority > 5)
                to t : Report!Summary (rank <- 1)
            }
            rule Important extends Base {
                from s : Project!Task, p : Project!Project (s.priority > 7)
                to t : Report!Summary (rank <- 2)
            }
            """ + projectRule
        let run = try await fixture.run(rules, priorities: [8])
        #expect(ranks(await run.elements("Summary")) == ["p/t1": 1])
        let warning = try #require(run.machine.getStatistics().warnings.first)
        #expect(warning.contains("s = Task 't1'") && warning.contains("p = Project 'p'"))
        let message = try #require(
            await thrownDescription { _ = try await fixture.run(rules, priorities: [8], options: strict(.standard)) })
        #expect(message.contains("'Urgent'") && message.contains("'Important'"))
    }

    @Test("A sub-rule and an unrelated rule that match one element are an error under every option", arguments: presets)
    func siblingAndUnrelatedRule(options: ATLOptions) async throws {
        let message = try #require(
            await thrownDescription {
                _ = try await fixture.run(
                    """
                    abstract rule Base {
                        from s : Project!Task
                        to t : Report!Summary (title <- s.name)
                    }
                    rule Urgent extends Base {
                        from s : Project!Task (s.priority > 5)
                        to t : Report!Summary (rank <- 1)
                    }
                    rule Important extends Base {
                        from s : Project!Task (s.priority > 7)
                        to t : Report!Summary (rank <- 2)
                    }
                    rule Lone {
                        from s : Project!Task (s.priority > 7)
                        to t : Report!Summary (title <- 'lone')
                    }
                    """ + projectRule, priorities: [8], options: options)
            })
        #expect(message.contains("'Urgent'") && message.contains("'Lone'"))
        #expect(message.contains("Task 't1'"))
    }

    @Test("References to an element resolve to the target of the sub-rule that transforms it")
    func referencesResolveToWinner() async throws {
        let run = try await fixture.run(
            """
            abstract rule Base {
                from s : Project!Task
                to t : Report!Summary (title <- s.name)
            }
            rule Urgent extends Base {
                from s : Project!Task (s.priority > 5)
                to t : Report!Summary (rank <- 1)
            }
            rule Important extends Base {
                from s : Project!Task (s.priority > 7)
                to t : Report!Summary (rank <- 2)
            }
            rule P {
                from s : Project!Project
                to t : Report!Document (name <- s.name, lead <- s.tasks->first())
            }
            """, priorities: [8])
        let lead = try #require(await run.value("lead", of: try await run.document()) as? EUUID)
        #expect(await run.target.eGet(objectId: lead, feature: "rank") as? Int == 1)
    }

    // MARK: - Refining Mode

    @Test("Sibling sub-rules that refine one element apply the first with a warning, or are an error when strict")
    func refining() async throws {
        let rules = """
            abstract rule Base { from s : Graph!Node to t : Graph!Node }
            rule Heavy extends Base { from s : Graph!Node (s.weight > 1) to t : Graph!Node (label <- 'heavy') }
            rule Heavier extends Base { from s : Graph!Node (s.weight > 2) to t : Graph!Node (label <- 'heavier') }
            """
        var refining = RefiningFixture()
        await refining.populate()
        let capture = ConsoleCapture()
        let machine = ATLVirtualMachine(module: try await refining.module(rules), options: .standard)
        machine.executionContext.console = capture.console
        try await machine.execute(sources: ["IN": refining.sourceResource], targets: ["OUT": refining.targetResource])
        #expect(await refining.target("Node", named: "c")?.eGet("label") as? String == "heavy")
        #expect(await refining.target("Node", named: "b")?.eGet("label") as? String == "heavy")
        let warnings = machine.getStatistics().warnings
        #expect(warnings.count == 1)
        #expect(warnings.first?.contains("Node 'c'") == true)
        #expect(warnings.first?.contains("only 'Heavy' is applied") == true)

        var strictRun = RefiningFixture()
        await strictRun.populate()
        let strictMachine = ATLVirtualMachine(module: try await strictRun.module(rules), options: strict(.standard))
        let message = try #require(
            await thrownDescription {
                try await strictMachine.execute(
                    sources: ["IN": strictRun.sourceResource], targets: ["OUT": strictRun.targetResource])
            })
        #expect(message.contains("'Heavy'") && message.contains("'Heavier'") && message.contains("Node 'c'"))
    }

    // MARK: - Incremental Transformations

    /// Rules with an unguarded sub-rule declared before a guarded one.
    private let plainAndUrgent = """
        abstract rule Base {
            from s : Project!Task
            to t : Report!Summary (title <- s.name)
        }
        rule Plain extends Base {
            from s : Project!Task
            to t : Report!Summary (rank <- 0)
        }
        rule Urgent extends Base {
            from s : Project!Task (s.priority > 5)
            to t : Report!Summary (rank <- 1)
        }
        """

    @Test("An incremental transformation reports sibling sub-rules in its first execution", arguments: presets)
    func incrementalExecution(options: ATLOptions) async throws {
        let module = try await fixture.module(plainAndUrgent, options: options)
        let target = await ResourceSet().createResource(uri: ReportFixture.targetURI)
        let transformation = ATLIncrementalTransformation(module: module, options: options)
        try await transformation.execute(
            sources: ["IN": await fixture.projectModel(priorities: [8])], targets: ["OUT": target])
        #expect(ranks(await summaries(of: target)) == ["t1": 1])
        #expect(transformation.statistics.warnings.count == 1)
        #expect(transformation.statistics.warnings.first?.contains("only 'Urgent' is applied") == true)

        let strictTarget = await ResourceSet().createResource(uri: ReportFixture.targetURI)
        let strictTransformation = ATLIncrementalTransformation(module: module, options: strict(options))
        let message = try #require(
            await thrownDescription {
                try await strictTransformation.execute(
                    sources: ["IN": await fixture.projectModel(priorities: [8])], targets: ["OUT": strictTarget])
            })
        #expect(message.contains("'Plain'") && message.contains("'Urgent'"))
    }

    @Test(
        "An update that makes a second sub-rule match applies the first in order and reports the warning",
        arguments: presets)
    func incrementalUpdate(options: ATLOptions) async throws {
        let module = try await fixture.module(plainAndUrgent, options: options)
        let source = await fixture.projectModel(priorities: [3])
        let target = await ResourceSet().createResource(uri: ReportFixture.targetURI)
        let transformation = ATLIncrementalTransformation(module: module, options: options)
        try await transformation.execute(sources: ["IN": source], targets: ["OUT": target])
        #expect(ranks(await summaries(of: target)) == ["t1": 0])
        #expect(transformation.statistics.warnings.isEmpty)

        let task = try #require(await source.getAllObjects().first { $0.eClass.name == "Task" })
        try await source.eSetWithChanges(objectId: task.id, feature: "priority", value: 9)
        let report = try await transformation.update()
        #expect(!report.reexecuted)
        #expect(ranks(await summaries(of: target)) == ["t1": 1])
        #expect(report.warnings.count == 1)
        #expect(report.warnings.first?.contains("only 'Urgent' is applied") == true)
        #expect(report.warnings.first?.contains("'Plain'") == true)

        // A further change that keeps both sub-rules matching reports nothing new
        try await source.eSetWithChanges(objectId: task.id, feature: "priority", value: 10)
        let unchanged = try await transformation.update()
        #expect(unchanged.warnings.isEmpty)

        // The batch run over the changed model agrees
        let batch = try await fixture.run(plainAndUrgent, priorities: [10], options: options)
        #expect(ranks(await batch.elements("Summary")) == ranks(await summaries(of: target)))
    }

    @Test("An update that makes a second sub-rule match is an error when strict", arguments: presets)
    func incrementalUpdateStrict(options: ATLOptions) async throws {
        let module = try await fixture.module(plainAndUrgent, options: options)
        let source = await fixture.projectModel(priorities: [3])
        let target = await ResourceSet().createResource(uri: ReportFixture.targetURI)
        let transformation = ATLIncrementalTransformation(module: module, options: strict(options))
        try await transformation.execute(sources: ["IN": source], targets: ["OUT": target])
        let task = try #require(await source.getAllObjects().first { $0.eClass.name == "Task" })
        try await source.eSetWithChanges(objectId: task.id, feature: "priority", value: 9)
        let message = try #require(await thrownDescription { _ = try await transformation.update() })
        #expect(message.contains("'Plain'") && message.contains("'Urgent'"))
    }

    @Test("An update that executes the module again reports the warnings of that execution")
    func reexecutionWarnings() async throws {
        // The imperative section makes every update execute the module again
        let module = try await fixture.module(
            plainAndUrgent + "\nrule Stamp { from s : Project!Project to t : Report!Document do { t.name <- s.name; } }")
        let source = await fixture.projectModel(priorities: [3])
        let target = await ResourceSet().createResource(uri: ReportFixture.targetURI)
        let transformation = ATLIncrementalTransformation(module: module, options: .standard)
        try await transformation.execute(sources: ["IN": source], targets: ["OUT": target])
        #expect(transformation.statistics.warnings.isEmpty)
        let task = try #require(await source.getAllObjects().first { $0.eClass.name == "Task" })
        try await source.eSetWithChanges(objectId: task.id, feature: "priority", value: 9)
        let report = try await transformation.update()
        #expect(report.reexecuted)
        #expect(report.warnings.count == 1)
        #expect(report.warnings.first?.contains("only 'Urgent' is applied") == true)
        #expect(ranks(await summaries(of: target)) == ["t1": 1])
    }
}
