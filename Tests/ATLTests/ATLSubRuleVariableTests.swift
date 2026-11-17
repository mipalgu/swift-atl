//
//  ATLSubRuleVariableTests.swift
//  ATLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ATL

/// Tests that a rule extending another matches its source pattern variables to those of
/// the rule it extends by name, as Eclipse ATL does.
@Suite("ATL Sub-Rule Variable Tests")
@MainActor
struct ATLSubRuleVariableTests {

    private let fixture = ReportFixture()

    /// The presets.
    nonisolated static let presets = [ATLOptions.standard, ATLOptions.legacy]

    /// The rule that creates the document of the project.
    private let projectRule = """
        rule P {
            from s : Project!Project
            to t : Report!Document (name <- s.name, highlights <- s.tasks)
        }
        """

    /// The rank of each summary, by title.
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

    /// A rule with two source elements, and a rule extending it that lists them in the
    /// other order.
    private let reordered = """
        rule Base {
            from s : Project!Task, p : Project!Project (s.priority > 2)
            to t : Report!Summary (title <- p.name + '/' + s.name)
        }
        rule Urgent extends Base {
            from p : Project!Project, s : Project!Task (s.priority > 5)
            to t : Report!Summary (rank <- 1)
        }
        """

    @Test("A sub-rule that lists the variables of the rule it extends in another order matches them by name", arguments: presets)
    func reorderedVariables(options: ATLOptions) async throws {
        let run = try await fixture.run(reordered + projectRule, priorities: [8, 3, 1], options: options)
        #expect(ranks(await run.elements("Summary")) == ["p/t1": 1, "p/t2": 0])
        #expect(run.machine.getStatistics().warnings.isEmpty)
    }

    @Test("The bindings and guards of the rule extended see the elements under their own variable names")
    func renamedVariables() async throws {
        let run = try await fixture.run(
            """
            rule Base {
                from s : Project!Task, p : Project!Project (s.priority > 2)
                to t : Report!Summary (title <- p.name + '/' + s.name)
            }
            rule Urgent extends Base {
                from p : Project!Project, x : Project!Task (x.priority > 5)
                to t : Report!Summary (rank <- 1)
            }
            """ + projectRule, priorities: [8, 3, 1])
        #expect(ranks(await run.elements("Summary")) == ["p/t1": 1, "p/t2": 0])
    }

    @Test("A rule extending a sub-rule with reordered variables matches through the whole chain")
    func reorderedChain() async throws {
        let run = try await fixture.run(
            reordered + """
                rule Top extends Urgent {
                    from s : Project!Task, p : Project!Project (s.priority > 7)
                    to t : Report!Summary (rank <- 2)
                }
                """ + projectRule, priorities: [8, 6, 3])
        #expect(ranks(await run.elements("Summary")) == ["p/t1": 2, "p/t2": 1, "p/t3": 0])
    }

    @Test("A sub-rule missing a variable of the rule it extends is an error naming both rules and the variable", arguments: presets)
    func missingVariable(options: ATLOptions) async throws {
        let module = try await fixture.module(
            """
            rule Base {
                from s : Project!Task, p : Project!Project
                to t : Report!Summary (title <- s.name)
            }
            rule Urgent extends Base {
                from s : Project!Task (s.priority > 5)
                to t : Report!Summary (rank <- 1)
            }
            """, options: options)
        let target = await ResourceSet().createResource(uri: ReportFixture.targetURI)
        await #expect {
            try await ATLVirtualMachine(module: module, options: options).execute(
                sources: ["IN": await fixture.projectModel(priorities: [8])], targets: ["OUT": target])
        } throws: { error in
            guard case ATLExecutionError.invalidOperation(let message) = error else { return false }
            return message.contains("'Urgent'") && message.contains("'Base'") && message.contains("'p'")
        }
    }

    @Test("A sub-rule declaring a variable that the rule it extends does not declare is an error")
    func extraVariable() async throws {
        let message = try #require(
            await thrownDescription {
                _ = try await fixture.run(
                    """
                    rule Base {
                        from s : Project!Task
                        to t : Report!Summary (title <- s.name)
                    }
                    rule Urgent extends Base {
                        from s : Project!Task, p : Project!Project (s.priority > 5)
                        to t : Report!Summary (rank <- 1)
                    }
                    """, priorities: [8])
            })
        #expect(message.contains("'Urgent'") && message.contains("'Base'") && message.contains("'p'"))
    }

    @Test("A sub-rule whose variable is not of a subtype of the variable of that name is a type error", arguments: presets)
    func nonConformingVariable(options: ATLOptions) async throws {
        let module = try await fixture.module(
            """
            rule Base {
                from s : Project!Task, p : Project!Project
                to t : Report!Summary (title <- s.name)
            }
            rule Urgent extends Base {
                from p : Project!Task, s : Project!Project
                to t : Report!Summary (rank <- 1)
            }
            """, options: options)
        let target = await ResourceSet().createResource(uri: ReportFixture.targetURI)
        await #expect {
            try await ATLVirtualMachine(module: module, options: options).execute(
                sources: ["IN": await fixture.projectModel(priorities: [8])], targets: ["OUT": target])
        } throws: { error in
            guard case ATLExecutionError.typeError(let message) = error else { return false }
            return message.contains("'Urgent'") && message.contains("'Base'") && message.contains("'s'")
                && message.contains("Project!Project") && message.contains("Project!Task")
        }
    }

    @Test("A sub-rule with one variable of another name still extends a rule with one variable")
    func renamedSingleVariable() async throws {
        let run = try await fixture.run(
            """
            rule Base {
                from s : Project!Task
                to t : Report!Summary (title <- s.name)
            }
            rule Urgent extends Base {
                from u : Project!Task (u.priority > 5)
                to t : Report!Summary (rank <- 1)
            }
            """ + projectRule, priorities: [8, 3])
        #expect(ranks(await run.elements("Summary")) == ["t1": 1, "t2": 0])
    }

    @Test("A sub-rule with reordered variables is applied by an incremental update", arguments: presets)
    func incrementalReordered(options: ATLOptions) async throws {
        let module = try await fixture.module(reordered, options: options)
        let source = await fixture.projectModel(priorities: [3])
        let target = await ResourceSet().createResource(uri: ReportFixture.targetURI)
        let transformation = ATLIncrementalTransformation(module: module, options: options)
        try await transformation.execute(sources: ["IN": source], targets: ["OUT": target])
        let task = try #require(await source.getAllObjects().first { $0.eClass.name == "Task" })
        try await source.eSetWithChanges(objectId: task.id, feature: "priority", value: 9)
        let report = try await transformation.update()
        #expect(!report.reexecuted)
        let summaries = await target.getAllObjects().compactMap { $0 as? DynamicEObject }
            .filter { $0.eClass.name == "Summary" }
        #expect(ranks(summaries) == ["p/t1": 1])
    }

    @Test("resolveTemp with a tuple finds the target of a sub-rule with reordered variables by their names")
    func resolveTempReordered() async throws {
        let run = try await fixture.run(
            reordered + """
                rule P {
                    from s : Project!Project
                    to t : Report!Document (
                        name <- s.name,
                        lead <- thisModule.resolveTemp(Tuple{p = s, s = s.tasks->first()}, 't'))
                }
                """, priorities: [8])
        let lead = try #require(await run.value("lead", of: try await run.document()) as? EUUID)
        #expect(await run.target.eGet(objectId: lead, feature: "rank") as? Int == 1)
    }
}
