//
//  ATLRuleConflictTests.swift
//  ATLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ATL

/// Tests that a source element, or a tuple of source elements, is transformed by at most
/// one matched rule, as Eclipse ATL requires.
@Suite("ATL Rule Conflict Tests")
@MainActor
struct ATLRuleConflictTests {

    private let fixture = ReportFixture()

    /// The rule that creates the document of the project.
    private let projectRule = """
        rule P {
            from s : Project!Project
            to t : Report!Document (name <- s.name, highlights <- s.tasks)
        }
        """

    /// The description of the error that running the rules raises.
    private func conflict(
        _ rules: String, priorities: [Int] = [8, 3], options: ATLOptions = .standard
    ) async -> String? {
        await thrownDescription {
            _ = try await fixture.run(rules, priorities: priorities, options: options)
        }
    }

    @Test(
        "Two matched rules that match one element are an error naming both rules and the element",
        arguments: [ATLOptions.standard, ATLOptions.legacy])
    func twoRules(options: ATLOptions) async throws {
        let message = try #require(
            await conflict(
                """
                rule A {
                    from s : Project!Task
                    to t : Report!Summary (title <- s.name)
                }
                rule B {
                    from s : Project!Task (s.priority > 5)
                    to t : Report!Summary (title <- s.name + '!')
                }
                """ + projectRule, options: options))
        #expect(message.contains("'A'"))
        #expect(message.contains("'B'"))
        #expect(message.contains("Task 't1'"))
        #expect(!message.contains("Task 't2'"))
        #expect(!message.contains(ReportFixture.sourceURI))
    }

    @Test("The conflict is raised as an invalid operation before any binding is applied")
    func errorKind() async throws {
        let module = try await fixture.module(
            """
            rule A { from s : Project!Task to t : Report!Summary (title <- s.name) }
            rule B { from s : Project!Task to t : Report!Summary (title <- s.name) }
            """)
        let target = await ResourceSet().createResource(uri: ReportFixture.targetURI)
        await #expect {
            try await ATLVirtualMachine(module: module, options: .standard).execute(
                sources: ["IN": await fixture.projectModel(priorities: [1])], targets: ["OUT": target])
        } throws: { error in
            guard case ATLExecutionError.invalidOperation = error else { return false }
            return true
        }
        for summary in await target.getAllObjects() {
            #expect(await target.eGet(objectId: summary.id, feature: "title") == nil)
        }
    }

    @Test("Rules whose guards select different elements are not in conflict")
    func disjointGuards() async throws {
        let run = try await fixture.run(
            """
            rule High {
                from s : Project!Task (s.priority > 5)
                to t : Report!Summary (title <- 'high ' + s.name)
            }
            rule Low {
                from s : Project!Task (s.priority <= 5)
                to t : Report!Summary (title <- 'low ' + s.name)
            }
            """ + projectRule, priorities: [8, 3])
        #expect(await run.elements("Summary").count == 2)
    }

    @Test("A rule and the rule extending it that both match an element transform it once")
    func ruleInheritance() async throws {
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
            """ + projectRule, priorities: [8, 3])
        #expect(await run.elements("Summary").count == 2)
    }

    @Test("Two rules extending one rule that both match an element are an error")
    func siblingRules() async throws {
        let message = try #require(
            await conflict(
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
                """ + projectRule))
        #expect(message.contains("'Urgent'"))
        #expect(message.contains("'Important'"))
        #expect(message.contains("Task 't1'"))
    }

    @Test("A rule matching an element and a rule matching it with another element are not in conflict")
    func differentTuples() async throws {
        let run = try await fixture.run(
            """
            rule Single {
                from s : Project!Task
                to t : Report!Summary (title <- s.name)
            }
            rule Pair {
                from s : Project!Task, p : Project!Project
                to t : Report!Summary (title <- p.name + '/' + s.name)
            }
            """ + projectRule, priorities: [8])
        #expect(await run.elements("Summary").count == 2)
    }

    @Test("Two rules matching the same tuple of elements are an error")
    func sameTuple() async throws {
        let message = try #require(
            await conflict(
                """
                rule First {
                    from s : Project!Task, p : Project!Project
                    to t : Report!Summary (title <- s.name)
                }
                rule Second {
                    from s : Project!Task, p : Project!Project
                    to t : Report!Summary (title <- p.name)
                }
                """ + projectRule, priorities: [8]))
        #expect(message.contains("'First'"))
        #expect(message.contains("'Second'"))
        #expect(message.contains("Task 't1'"))
        #expect(message.contains("Project 'p'"))
    }

    @Test("Two rules that refine one element are an error in refining mode")
    func refining() async throws {
        var refining = RefiningFixture()
        await refining.populate()
        let message = try #require(
            await thrownDescription {
                try await refining.run(
                    """
                    rule One { from s : Graph!Node to t : Graph!Node (label <- 'one') }
                    rule Two { from s : Graph!Node (s.weight = 2) to t : Graph!Node (label <- 'two') }
                    """)
            })
        #expect(message.contains("'One'"))
        #expect(message.contains("'Two'"))
        #expect(message.contains("Node 'b'"))
    }

    @Test("An incremental update that makes two rules match one element reports the conflict")
    func incrementalUpdate() async throws {
        let module = try await fixture.module(
            """
            rule High {
                from s : Project!Task (s.priority > 5)
                to t : Report!Summary (title <- s.name)
            }
            rule Top {
                from s : Project!Task (s.priority > 7)
                to t : Report!Summary (title <- s.name + '!')
            }
            """)
        let source = await fixture.projectModel(priorities: [6])
        let target = await ResourceSet().createResource(uri: ReportFixture.targetURI)
        let transformation = ATLIncrementalTransformation(module: module, options: .standard)
        try await transformation.execute(sources: ["IN": source], targets: ["OUT": target])
        let task = try #require(await source.getAllObjects().first { $0.eClass.name == "Task" })
        try await source.eSetWithChanges(objectId: task.id, feature: "priority", value: 9)
        let message = try #require(await thrownDescription { _ = try await transformation.update() })
        #expect(message.contains("'High'"))
        #expect(message.contains("'Top'"))
    }

    @Test("An incremental transformation reports a conflict in its first execution")
    func incrementalExecution() async throws {
        let module = try await fixture.module(
            """
            rule A { from s : Project!Task to t : Report!Summary (title <- s.name) }
            rule B { from s : Project!Task to t : Report!Summary (title <- s.name) }
            """)
        let target = await ResourceSet().createResource(uri: ReportFixture.targetURI)
        let transformation = ATLIncrementalTransformation(module: module, options: .standard)
        let message = try #require(
            await thrownDescription {
                try await transformation.execute(
                    sources: ["IN": await fixture.projectModel(priorities: [1])], targets: ["OUT": target])
            })
        #expect(message.contains("'A'") && message.contains("'B'"))
    }
}
