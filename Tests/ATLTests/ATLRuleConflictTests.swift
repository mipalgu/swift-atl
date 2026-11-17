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

    // MARK: - What Counts as the Same Match

    @Test(
        "Two rules with one source element conflict whatever their variables are called",
        arguments: [ATLOptions.standard, ATLOptions.legacy])
    func singleElementDifferentNames(options: ATLOptions) async throws {
        let message = try #require(
            await conflict(
                """
                rule A {
                    from s : Project!Task
                    to t : Report!Summary (title <- s.name)
                }
                rule B {
                    from x : Project!Task (x.priority > 5)
                    to t : Report!Summary (title <- x.name)
                }
                """ + projectRule, options: options))
        #expect(message.contains("'A'") && message.contains("'B'"))
        #expect(message.contains("Task 't1'"))
        #expect(!message.contains("s = ") && !message.contains("x = "))
    }

    @Test(
        "Two rules binding the same elements in the same order to other variables do not conflict",
        arguments: [ATLOptions.standard, ATLOptions.legacy])
    func sameOrderDifferentNames(options: ATLOptions) async throws {
        let run = try await fixture.run(
            """
            rule First {
                from s : Project!Task, p : Project!Project
                to t : Report!Summary (title <- 'first ' + s.name)
            }
            rule Second {
                from x : Project!Task, y : Project!Project
                to t : Report!Summary (title <- 'second ' + x.name)
            }
            """ + projectRule, priorities: [8], options: options)
        let titles = await run.elements("Summary").compactMap { $0.eGet("title") as? String }
        #expect(Set(titles) == ["first t1", "second t1"])
    }

    @Test(
        "Two rules binding the same elements to the same variables in another order conflict",
        arguments: [ATLOptions.standard, ATLOptions.legacy])
    func reversedOrderSameNames(options: ATLOptions) async throws {
        let message = try #require(
            await conflict(
                """
                rule First {
                    from s : Project!Task, p : Project!Project
                    to t : Report!Summary (title <- s.name)
                }
                rule Second {
                    from p : Project!Project, s : Project!Task
                    to t : Report!Summary (title <- p.name)
                }
                """ + projectRule, priorities: [8], options: options))
        #expect(message.contains("'First'") && message.contains("'Second'"))
        #expect(message.contains("s = Task 't1'"))
        #expect(message.contains("p = Project 'p'"))
    }

    @Test(
        "Two rules binding the same elements in another order to other variables do not conflict",
        arguments: [ATLOptions.standard, ATLOptions.legacy])
    func reversedOrderDifferentNames(options: ATLOptions) async throws {
        let run = try await fixture.run(
            """
            rule First {
                from s : Project!Task, p : Project!Project
                to t : Report!Summary (title <- 'first ' + s.name)
            }
            rule Second {
                from q : Project!Project, u : Project!Task
                to t : Report!Summary (title <- 'second ' + u.name)
            }
            """ + projectRule, priorities: [8], options: options)
        #expect(await run.elements("Summary").count == 2)
    }

    @Test(
        "Two rules matching elements of one class in one order under swapped variables do not conflict",
        arguments: [ATLOptions.standard, ATLOptions.legacy])
    func swappedNames(options: ATLOptions) async throws {
        let run = try await fixture.run(
            """
            rule Ahead {
                from a : Project!Task, b : Project!Task (a.priority > b.priority)
                to t : Report!Summary (title <- a.name + '>' + b.name)
            }
            rule Behind {
                from b : Project!Task, a : Project!Task (b.priority > a.priority)
                to t : Report!Summary (title <- a.name + '<' + b.name)
            }
            """ + projectRule, priorities: [8, 3], options: options)
        let titles = await run.elements("Summary").compactMap { $0.eGet("title") as? String }
        #expect(Set(titles) == ["t1>t2", "t2<t1"])
    }

    @Test(
        "Two rules matching elements of one class under the same variables in another order conflict",
        arguments: [ATLOptions.standard, ATLOptions.legacy])
    func sameBindingsInOtherOrder(options: ATLOptions) async throws {
        let message = try #require(
            await conflict(
                """
                rule Ahead {
                    from a : Project!Task, b : Project!Task (a.priority > b.priority)
                    to t : Report!Summary (title <- a.name)
                }
                rule Behind {
                    from b : Project!Task, a : Project!Task (a.priority > b.priority)
                    to t : Report!Summary (title <- b.name)
                }
                """ + projectRule, priorities: [8, 3], options: options))
        #expect(message.contains("'Ahead'") && message.contains("'Behind'"))
        #expect(message.contains("a = Task 't1'"))
        #expect(message.contains("b = Task 't2'"))
    }

    @Test("A rule matching two elements of one class in both orders does not conflict with itself")
    func bothOrdersOfOneRule() async throws {
        let run = try await fixture.run(
            """
            rule Pair {
                from a : Project!Task, b : Project!Task (a <> b)
                to t : Report!Summary (title <- a.name + '/' + b.name)
            }
            """ + projectRule, priorities: [8, 3])
        let titles = await run.elements("Summary").compactMap { $0.eGet("title") as? String }
        #expect(Set(titles) == ["t1/t2", "t2/t1"])
    }

    @Test(
        "A rule with one source element and a rule with several that share it do not conflict",
        arguments: [ATLOptions.standard, ATLOptions.legacy])
    func singleAndPairShareElement(options: ATLOptions) async throws {
        let run = try await fixture.run(
            """
            rule Single {
                from p : Project!Project
                to t : Report!Summary (title <- p.name)
            }
            rule Pair {
                from p : Project!Project, s : Project!Task
                to t : Report!Summary (title <- p.name + '/' + s.name)
            }
            rule Other {
                from s : Project!Task
                to t : Report!Summary (title <- s.name)
            }
            """, priorities: [8], options: options)
        let titles = await run.elements("Summary").compactMap { $0.eGet("title") as? String }
        #expect(Set(titles) == ["p", "p/t1", "t1"])
    }

    @Test("resolveTemp with a sequence uses the first rule matching the elements in that order")
    func resolveTempOfSharedOrder() async throws {
        let run = try await fixture.run(
            """
            rule First {
                from s : Project!Task, p : Project!Project
                to t : Report!Summary (title <- 'first')
            }
            rule Second {
                from x : Project!Task, y : Project!Project
                to t : Report!Summary (title <- 'second')
            }
            rule P {
                from s : Project!Project
                to t : Report!Document (
                    name <- s.name, lead <- thisModule.resolveTemp(Sequence{s.tasks->first(), s}, 't'))
            }
            """, priorities: [8])
        let lead = try #require(await run.value("lead", of: try await run.document()) as? EUUID)
        #expect(await run.target.eGet(objectId: lead, feature: "title") as? String == "first")
    }

    // MARK: - Rule Inheritance

    @Test(
        "A rule extending a rule with several source elements transforms the elements once",
        arguments: [ATLOptions.standard, ATLOptions.legacy])
    func pairInheritance(options: ATLOptions) async throws {
        let run = try await fixture.run(
            """
            rule Base {
                from s : Project!Task, p : Project!Project
                to t : Report!Summary (title <- 'base ' + s.name)
            }
            rule Urgent extends Base {
                from s : Project!Task, p : Project!Project (s.priority > 5)
                to t : Report!Summary (title <- 'urgent ' + s.name)
            }
            """ + projectRule, priorities: [8, 3], options: options)
        let titles = await run.elements("Summary").compactMap { $0.eGet("title") as? String }
        #expect(Set(titles) == ["urgent t1", "base t2"])
    }

    @Test(
        "An extending rule and another rule binding the same elements to the same variables conflict",
        arguments: [ATLOptions.standard, ATLOptions.legacy])
    func inheritedRuleAgainstSameNames(options: ATLOptions) async throws {
        let message = try #require(
            await conflict(
                """
                rule Base {
                    from s : Project!Task, p : Project!Project
                    to t : Report!Summary (title <- s.name)
                }
                rule Urgent extends Base {
                    from s : Project!Task, p : Project!Project (s.priority > 5)
                    to t : Report!Summary (rank <- 1)
                }
                rule Other {
                    from p : Project!Project, s : Project!Task (s.priority > 5)
                    to t : Report!Summary (title <- p.name)
                }
                """ + projectRule, options: options))
        #expect(message.contains("'Urgent'") && message.contains("'Other'"))
        #expect(!message.contains("'Base'"))
        #expect(message.contains("s = Task 't1'"))
    }

    @Test(
        "An extending rule and another rule binding the same elements to other variables do not conflict",
        arguments: [ATLOptions.standard, ATLOptions.legacy])
    func inheritedRuleAgainstOtherNames(options: ATLOptions) async throws {
        let run = try await fixture.run(
            """
            rule Base {
                from s : Project!Task, p : Project!Project
                to t : Report!Summary (title <- 'base ' + s.name)
            }
            rule Urgent extends Base {
                from s : Project!Task, p : Project!Project (s.priority > 5)
                to t : Report!Summary (title <- 'urgent ' + s.name)
            }
            rule Other {
                from x : Project!Task, y : Project!Project (x.priority > 5)
                to t : Report!Summary (title <- 'other ' + x.name)
            }
            """ + projectRule, priorities: [8, 3], options: options)
        let titles = await run.elements("Summary").compactMap { $0.eGet("title") as? String }
        #expect(Set(titles) == ["urgent t1", "base t2", "other t1"])
    }

    // MARK: - Refining Mode

    @Test("Two refining rules binding the same elements to the same variables in another order conflict")
    func refiningReversedOrder() async throws {
        var refining = RefiningFixture()
        await refining.populate()
        let message = try #require(
            await thrownDescription {
                try await refining.run(
                    """
                    rule One {
                        from x : Graph!Node, y : Graph!Node (x.next = y)
                        to m : Graph!Marker (text <- 'one')
                    }
                    rule Two {
                        from y : Graph!Node, x : Graph!Node (x.next = y)
                        to m : Graph!Marker (text <- 'two')
                    }
                    """)
            })
        #expect(message.contains("'One'") && message.contains("'Two'"))
        #expect(message.contains("x = Node 'a'") && message.contains("y = Node 'b'"))
    }

    @Test("Two refining rules binding the same elements in one order to other variables do not conflict")
    func refiningDifferentNames() async throws {
        var refining = RefiningFixture()
        await refining.populate()
        try await refining.run(
            """
            rule One {
                from x : Graph!Node, y : Graph!Node (x.next = y)
                to m : Graph!Marker (text <- 'one ' + x.name + y.name)
            }
            rule Two {
                from p : Graph!Node, q : Graph!Node (p.next = q)
                to m : Graph!Marker (text <- 'two ' + p.name + q.name)
            }
            """)
        let texts = Set(await refining.targets("Marker").compactMap { $0.eGet("text") as? String })
        #expect(texts == ["one ab", "one bc", "two ab", "two bc"])
    }

    // MARK: - Incremental Updates

    /// Executes rules incrementally over one task of priority 6, then raises its priority to 9.
    ///
    /// - Parameters:
    ///   - rules: The rules of the module.
    ///   - options: The options of the parser and the transformation.
    /// - Returns: The target model after the update.
    /// - Throws: Errors raised by the execution or the update.
    private func raisePriority(_ rules: String, options: ATLOptions) async throws -> Resource {
        let module = try await fixture.module(rules, options: options)
        let source = await fixture.projectModel(priorities: [6])
        let target = await ResourceSet().createResource(uri: ReportFixture.targetURI)
        let transformation = ATLIncrementalTransformation(module: module, options: options)
        try await transformation.execute(sources: ["IN": source], targets: ["OUT": target])
        let task = try #require(await source.getAllObjects().first { $0.eClass.name == "Task" })
        try await source.eSetWithChanges(objectId: task.id, feature: "priority", value: 9)
        _ = try await transformation.update()
        return target
    }

    @Test(
        "An update that makes rules bind the same elements to the same variables in another order reports the conflict",
        arguments: [ATLOptions.standard, ATLOptions.legacy])
    func incrementalReversedOrder(options: ATLOptions) async throws {
        let message = try #require(
            await thrownDescription {
                _ = try await raisePriority(
                    """
                    rule High {
                        from s : Project!Task, p : Project!Project (s.priority > 5)
                        to t : Report!Summary (title <- s.name)
                    }
                    rule Top {
                        from p : Project!Project, s : Project!Task (s.priority > 7)
                        to t : Report!Summary (title <- s.name + '!')
                    }
                    """, options: options)
            })
        #expect(message.contains("'High'") && message.contains("'Top'"))
    }

    @Test(
        "An update that makes rules bind the same elements in one order to other variables applies both",
        arguments: [ATLOptions.standard, ATLOptions.legacy])
    func incrementalDifferentNames(options: ATLOptions) async throws {
        let target = try await raisePriority(
            """
            rule High {
                from s : Project!Task, p : Project!Project (s.priority > 5)
                to t : Report!Summary (title <- 'high ' + s.name)
            }
            rule Top {
                from x : Project!Task, y : Project!Project (x.priority > 7)
                to t : Report!Summary (title <- 'top ' + x.name)
            }
            """, options: options)
        var titles: Set<String> = []
        for element in await target.getAllObjects() where element.eClass.name == "Summary" {
            if let title = await target.eGet(objectId: element.id, feature: "title") as? String {
                titles.insert(title)
            }
        }
        #expect(titles == ["high t1", "top t1"])
    }

    @Test(
        "An incremental transformation reports rules binding the same elements in another order in its first execution",
        arguments: [ATLOptions.standard, ATLOptions.legacy])
    func incrementalExecutionReversedOrder(options: ATLOptions) async throws {
        let module = try await fixture.module(
            """
            rule A { from s : Project!Task, p : Project!Project to t : Report!Summary (title <- s.name) }
            rule B { from p : Project!Project, s : Project!Task to t : Report!Summary (title <- s.name) }
            """, options: options)
        let target = await ResourceSet().createResource(uri: ReportFixture.targetURI)
        let transformation = ATLIncrementalTransformation(module: module, options: options)
        let message = try #require(
            await thrownDescription {
                try await transformation.execute(
                    sources: ["IN": await fixture.projectModel(priorities: [1])], targets: ["OUT": target])
            })
        #expect(message.contains("'A'") && message.contains("'B'"))
    }
}
