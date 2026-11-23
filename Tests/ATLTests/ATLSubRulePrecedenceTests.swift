//
//  ATLSubRulePrecedenceTests.swift
//  ATLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ATL

/// Tests that a rule and the rules extending it that match the same element are chosen
/// between as ``ATLOptions/subRulePrecedence`` selects: in the order of Eclipse ATL, in
/// which a rule with a guard comes before the rules extending it that have none, or with
/// the extending rule always taking precedence.
@Suite("ATL Sub-Rule Precedence Tests")
@MainActor
struct ATLSubRulePrecedenceTests {

    private let fixture = ReportFixture()

    /// Both precedences.
    nonisolated static let precedences = ATLSubRulePrecedence.allCases

    /// The rule that creates the document of the project.
    private let projectRule = """
        rule P {
            from s : Project!Project
            to t : Report!Document (name <- s.name, highlights <- s.tasks)
        }
        """

    /// A rule with a guard and a rule without one that extends it.
    private let guardedParent = """
        rule Base {
            from s : Project!Task (s.priority > 5)
            to t : Report!Summary (title <- s.name, rank <- 1)
        }
        rule Plain extends Base {
            from s : Project!Task
            to t : Report!Summary (rank <- 0)
        }
        """

    /// A rule with a guard and two rules without one that extend it.
    private let guardedParentOfTwo = """
        rule Base {
            from s : Project!Task (s.priority > 5)
            to t : Report!Summary (title <- s.name, rank <- 1)
        }
        rule First extends Base {
            from s : Project!Task
            to t : Report!Summary (rank <- 2)
        }
        rule Second extends Base {
            from s : Project!Task
            to t : Report!Summary (rank <- 3)
        }
        """

    /// Options with a precedence of sub-rules.
    ///
    /// - Parameters:
    ///   - precedence: The precedence of sub-rules.
    ///   - conflicts: What sibling sub-rules that match one element give.
    /// - Returns: The standard options with `precedence` and `conflicts`.
    private func options(
        _ precedence: ATLSubRulePrecedence, conflicts: ATLSiblingRuleConflicts = .warning
    ) -> ATLOptions {
        ATLOptions(siblingRuleConflicts: conflicts, subRulePrecedence: precedence)
    }

    /// The rank of the summary of each task, by title.
    ///
    /// - Parameter elements: The summaries.
    /// - Returns: The rank of each summary, by title; `-1` for an unset rank.
    private func ranks(_ elements: [DynamicEObject]) -> [String: Int] {
        var result: [String: Int] = [:]
        for summary in elements {
            if let title = summary.eGet("title") as? String { result[title] = summary.eGet("rank") as? Int ?? -1 }
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

    /// Runs rules and returns the rank of each summary and the warnings of the run.
    ///
    /// - Parameters:
    ///   - rules: The rules, without the rule that creates the document.
    ///   - priorities: The priority of each task.
    ///   - options: The options of the run.
    /// - Returns: The rank of each summary, by title, and the warnings.
    private func outcome(_ rules: String, priorities: [Int], options: ATLOptions) async throws
        -> (ranks: [String: Int], warnings: [String])
    {
        let run = try await fixture.run(rules + projectRule, priorities: priorities, options: options)
        return (ranks(await run.elements("Summary")), run.machine.getStatistics().warnings)
    }

    // MARK: - Options

    @Test("The default options follow Eclipse ATL and the legacy options let the extending rule win")
    func defaults() {
        #expect(ATLOptions().subRulePrecedence == .eclipse)
        #expect(ATLOptions.standard.subRulePrecedence == .eclipse)
        #expect(ATLOptions(semantics: .standard).subRulePrecedence == .eclipse)
        #expect(ATLOptions.legacy.subRulePrecedence == .extendingRule)
        #expect(ATLOptions(semantics: .legacy).subRulePrecedence == .extendingRule)
    }

    @Test("The precedences are spelt as on a command line and can be set when the options are created")
    func spellings() {
        #expect(ATLSubRulePrecedence.allCases.map(\.rawValue) == ["eclipse", "extending-rule"])
        #expect(ATLSubRulePrecedence(rawValue: "extending-rule") == .extendingRule)
        let options = ATLOptions(subRulePrecedence: .extendingRule)
        #expect(options.subRulePrecedence == .extendingRule)
        #expect(options.siblingRuleConflicts == ATLOptions.standard.siblingRuleConflicts)
        #expect(options != .standard)
        var changed = ATLOptions.standard
        changed.subRulePrecedence = .extendingRule
        #expect(changed == options)
    }

    // MARK: - A Rule and the Rules Extending It

    @Test("A rule with a guard comes before a rule extending it without one, unless the extending rule wins")
    func guardedParentUnguardedChild() async throws {
        let eclipse = try await outcome(guardedParent, priorities: [8, 3], options: options(.eclipse))
        #expect(eclipse.ranks == ["t1": 1])
        #expect(eclipse.warnings.isEmpty)
        let extending = try await outcome(guardedParent, priorities: [8, 3], options: options(.extendingRule))
        #expect(extending.ranks == ["t1": 0])
        #expect(extending.warnings.isEmpty)
    }

    @Test("A rule with a guard and a rule extending it with a guard apply the extending rule", arguments: precedences)
    func guardedParentGuardedChild(precedence: ATLSubRulePrecedence) async throws {
        let result = try await outcome(
            """
            rule Base {
                from s : Project!Task (s.priority > 2)
                to t : Report!Summary (title <- s.name, rank <- 1)
            }
            rule Urgent extends Base {
                from s : Project!Task (s.priority > 5)
                to t : Report!Summary (rank <- 2)
            }
            """, priorities: [8, 4, 1], options: options(precedence))
        #expect(result.ranks == ["t1": 2, "t2": 1])
        #expect(result.warnings.isEmpty)
    }

    @Test("A rule without a guard and a rule extending it apply the extending rule", arguments: precedences)
    func unguardedParent(precedence: ATLSubRulePrecedence) async throws {
        let guardedChild = try await outcome(
            """
            rule Base {
                from s : Project!Task
                to t : Report!Summary (title <- s.name, rank <- 1)
            }
            rule Urgent extends Base {
                from s : Project!Task (s.priority > 5)
                to t : Report!Summary (rank <- 2)
            }
            """, priorities: [8, 3], options: options(precedence))
        #expect(guardedChild.ranks == ["t1": 2, "t2": 1])
        #expect(guardedChild.warnings.isEmpty)

        let plainChild = try await outcome(
            """
            rule Base {
                from s : Project!Task
                to t : Report!Summary (title <- s.name, rank <- 1)
            }
            rule Plain extends Base {
                from s : Project!Task
                to t : Report!Summary (rank <- 0)
            }
            """, priorities: [8, 3], options: options(precedence))
        #expect(plainChild.ranks == ["t1": 0, "t2": 0])
    }

    @Test("An abstract rule with a guard lets a rule extending it without one apply", arguments: precedences)
    func abstractGuardedParent(precedence: ATLSubRulePrecedence) async throws {
        let result = try await outcome(
            """
            abstract rule Base {
                from s : Project!Task (s.priority > 5)
                to t : Report!Summary (title <- s.name, rank <- 1)
            }
            rule Plain extends Base {
                from s : Project!Task
                to t : Report!Summary (rank <- 0)
            }
            """, priorities: [8, 3], options: options(precedence))
        #expect(result.ranks == ["t1": 0])
        #expect(result.warnings.isEmpty)
    }

    @Test("A rule with a guard comes after the rules extending it with a guard and before those without one")
    func guardedAndUnguardedChildren() async throws {
        let rules = """
            rule Base {
                from s : Project!Task (s.priority > 2)
                to t : Report!Summary (title <- s.name, rank <- 1)
            }
            rule Plain extends Base {
                from s : Project!Task
                to t : Report!Summary (rank <- 0)
            }
            rule Urgent extends Base {
                from s : Project!Task (s.priority > 7)
                to t : Report!Summary (rank <- 2)
            }
            """
        let eclipse = try await outcome(rules, priorities: [9, 5, 1], options: options(.eclipse))
        #expect(eclipse.ranks == ["t1": 2, "t2": 1])
        #expect(eclipse.warnings.isEmpty)
        let extending = try await outcome(rules, priorities: [9, 5, 1], options: options(.extendingRule))
        #expect(extending.ranks == ["t1": 2, "t2": 0])
        #expect(extending.warnings.count == 1)
        let warning = try #require(extending.warnings.first)
        #expect(warning.contains("'Urgent'") && warning.contains("'Plain'") && warning.contains("Task 't1'"))
        #expect(warning.contains("only 'Urgent' is applied"))
    }

    @Test("Several rules without a guard that extend a rule with one never apply under Eclipse ATL's order")
    func guardedParentOfSiblings() async throws {
        let eclipse = try await outcome(guardedParentOfTwo, priorities: [8, 3], options: options(.eclipse))
        #expect(eclipse.ranks == ["t1": 1])
        #expect(eclipse.warnings.isEmpty)
        let extending = try await outcome(guardedParentOfTwo, priorities: [8, 3], options: options(.extendingRule))
        #expect(extending.ranks == ["t1": 2])
        #expect(extending.warnings.count == 1)
        #expect(extending.warnings.first?.contains("only 'First' is applied") == true)
    }

    @Test("Only the sub-rules tried before a rule with a guard are named in the warning")
    func shadowedSiblingsNotNamed() async throws {
        let rules = """
            rule Base {
                from s : Project!Task (s.priority > 2)
                to t : Report!Summary (title <- s.name, rank <- 1)
            }
            rule Plain extends Base {
                from s : Project!Task
                to t : Report!Summary (rank <- 0)
            }
            rule Urgent extends Base {
                from s : Project!Task (s.priority > 7)
                to t : Report!Summary (rank <- 2)
            }
            rule Critical extends Base {
                from s : Project!Task (s.priority > 8)
                to t : Report!Summary (rank <- 3)
            }
            """
        let eclipse = try await outcome(rules, priorities: [9], options: options(.eclipse))
        #expect(eclipse.ranks == ["t1": 2])
        let warning = try #require(eclipse.warnings.first)
        #expect(eclipse.warnings.count == 1)
        #expect(warning.contains("Rules 'Urgent' and 'Critical'") && !warning.contains("'Plain'"))
        #expect(warning.contains("only 'Urgent' is applied"))

        let extending = try await outcome(rules, priorities: [9], options: options(.extendingRule))
        #expect(extending.ranks == ["t1": 2])
        #expect(extending.warnings.first?.contains("Rules 'Urgent', 'Critical' and 'Plain'") == true)
    }

    // MARK: - Several Levels

    @Test("Each level of an inheritance hierarchy tries a rule with a guard before its sub-rules without one")
    func severalLevels() async throws {
        let rules = """
            rule Base {
                from s : Project!Task
                to t : Report!Summary (title <- s.name, rank <- 0)
            }
            rule Mid extends Base {
                from s : Project!Task (s.priority > 5)
                to t : Report!Summary (rank <- 1)
            }
            rule Leaf extends Mid {
                from s : Project!Task
                to t : Report!Summary (rank <- 2)
            }
            rule Top extends Leaf {
                from s : Project!Task (s.priority > 7)
                to t : Report!Summary (rank <- 3)
            }
            """
        let eclipse = try await outcome(rules, priorities: [9, 6, 3], options: options(.eclipse))
        #expect(eclipse.ranks == ["t1": 1, "t2": 1, "t3": 0])
        #expect(eclipse.warnings.isEmpty)
        let extending = try await outcome(rules, priorities: [9, 6, 3], options: options(.extendingRule))
        #expect(extending.ranks == ["t1": 3, "t2": 2, "t3": 0])
        #expect(extending.warnings.isEmpty)
    }

    /// An abstract rule extended by an abstract rule with a guard, whose only sub-rule has a
    /// stricter guard, and by a rule with a weaker guard declared after it.
    private let abstractMidLevelRules = """
        abstract rule Base {
            from s : Project!Task
            to t : Report!Summary (title <- s.name)
        }
        abstract rule Mid extends Base {
            from s : Project!Task (s.priority > 5)
            to t : Report!Summary (rank <- 1)
        }
        rule Top extends Mid {
            from s : Project!Task (s.priority > 7)
            to t : Report!Summary (rank <- 2)
        }
        rule Other extends Base {
            from s : Project!Task (s.priority > 1)
            to t : Report!Summary (rank <- 3)
        }
        """

    @Test(
        "An abstract sub-rule whose own sub-rules do not match lets the next rule apply when abstract rules are skipped",
        arguments: precedences)
    func abstractMidLevel(precedence: ATLSubRulePrecedence) async throws {
        var skipping = options(precedence)
        skipping.abstractRuleMatching = .skip
        let result = try await outcome(abstractMidLevelRules, priorities: [6], options: skipping)
        #expect(result.ranks == ["t1": 3])
        #expect(result.warnings.isEmpty)
    }

    @Test(
        "An abstract sub-rule that matches keeps the next rule from applying when its own sub-rules do not match",
        arguments: precedences)
    func abstractMidLevelEclipse(precedence: ATLSubRulePrecedence) async throws {
        let result = try await outcome(abstractMidLevelRules, priorities: [6], options: options(precedence))
        #expect(result.ranks.isEmpty)
        #expect(result.warnings.isEmpty)
    }

    // MARK: - Several Source Elements

    @Test("A rule with several source elements and a guard comes before a rule extending it without one")
    func severalSourceElements() async throws {
        let rules = """
            rule Base {
                from s : Project!Task, p : Project!Project (s.priority > 5)
                to t : Report!Summary (title <- p.name + '/' + s.name, rank <- 1)
            }
            rule Plain extends Base {
                from p : Project!Project, s : Project!Task
                to t : Report!Summary (rank <- 0)
            }
            """
        let eclipse = try await outcome(rules, priorities: [8, 3], options: options(.eclipse))
        #expect(eclipse.ranks == ["p/t1": 1])
        #expect(eclipse.warnings.isEmpty)
        let extending = try await outcome(rules, priorities: [8, 3], options: options(.extendingRule))
        #expect(extending.ranks == ["p/t1": 0])
        #expect(extending.warnings.isEmpty)
    }

    // MARK: - Sibling Rule Conflicts

    @Test("Strict sibling conflicts stop the run only for sub-rules that the precedence lets compete")
    func strictSiblingConflicts() async throws {
        let eclipse = try await outcome(
            guardedParentOfTwo, priorities: [8, 3], options: options(.eclipse, conflicts: .error))
        #expect(eclipse.ranks == ["t1": 1])
        let message = try #require(
            await thrownDescription {
                _ = try await outcome(
                    guardedParentOfTwo, priorities: [8, 3], options: options(.extendingRule, conflicts: .error))
            })
        #expect(message.contains("'First'") && message.contains("'Second'") && message.contains("Task 't1'"))

        let mixed = """
            rule Base {
                from s : Project!Task (s.priority > 2)
                to t : Report!Summary (title <- s.name, rank <- 1)
            }
            rule Plain extends Base {
                from s : Project!Task
                to t : Report!Summary (rank <- 0)
            }
            rule Urgent extends Base {
                from s : Project!Task (s.priority > 7)
                to t : Report!Summary (rank <- 2)
            }
            rule Critical extends Base {
                from s : Project!Task (s.priority > 8)
                to t : Report!Summary (rank <- 3)
            }
            """
        let below = try await outcome(mixed, priorities: [8, 5], options: options(.eclipse, conflicts: .error))
        #expect(below.ranks == ["t1": 2, "t2": 1])
        let competing = try #require(
            await thrownDescription {
                _ = try await outcome(mixed, priorities: [9], options: options(.eclipse, conflicts: .error))
            })
        #expect(competing.contains("'Urgent'") && competing.contains("'Critical'") && !competing.contains("'Plain'"))
        let extending = try #require(
            await thrownDescription {
                _ = try await outcome(mixed, priorities: [8], options: options(.extendingRule, conflicts: .error))
            })
        #expect(extending.contains("'Urgent'") && extending.contains("'Plain'"))
    }

    @Test("Strict sibling conflicts follow the precedence at every level of a hierarchy", arguments: precedences)
    func strictSeveralLevels(precedence: ATLSubRulePrecedence) async throws {
        let rules = """
            rule Base {
                from s : Project!Task
                to t : Report!Summary (title <- s.name, rank <- 0)
            }
            rule Mid extends Base {
                from s : Project!Task (s.priority > 5)
                to t : Report!Summary (rank <- 1)
            }
            rule Leaf extends Mid {
                from s : Project!Task
                to t : Report!Summary (rank <- 2)
            }
            rule Top extends Leaf {
                from s : Project!Task (s.priority > 7)
                to t : Report!Summary (rank <- 3)
            }
            """
        let result = try await outcome(rules, priorities: [9, 6, 3], options: options(precedence, conflicts: .error))
        #expect(result.ranks == (precedence == .eclipse ? ["t1": 1, "t2": 1, "t3": 0] : ["t1": 3, "t2": 2, "t3": 0]))
    }

    // MARK: - Incremental Transformations

    @Test("An incremental transformation chooses as a run does, in its execution and its updates", arguments: precedences)
    func incremental(precedence: ATLSubRulePrecedence) async throws {
        let options = options(precedence)
        let module = try await fixture.module(guardedParent, options: options)
        let source = await fixture.projectModel(priorities: [3])
        let target = await ResourceSet().createResource(uri: ReportFixture.targetURI)
        let transformation = ATLIncrementalTransformation(module: module, options: options)
        try await transformation.execute(sources: ["IN": source], targets: ["OUT": target])
        #expect(ranks(await summaries(of: target)).isEmpty)

        let task = try #require(await source.getAllObjects().first { $0.eClass.name == "Task" })
        try await source.eSetWithChanges(objectId: task.id, feature: "priority", value: 9)
        let report = try await transformation.update()
        #expect(!report.reexecuted)
        #expect(ranks(await summaries(of: target)) == ["t1": precedence == .eclipse ? 1 : 0])
        #expect(report.warnings.isEmpty)
        let batch = try await fixture.run(guardedParent, priorities: [9], options: options)
        #expect(ranks(await batch.elements("Summary")) == ranks(await summaries(of: target)))

        try await source.eSetWithChanges(objectId: task.id, feature: "priority", value: 2)
        _ = try await transformation.update()
        #expect(ranks(await summaries(of: target)).isEmpty)

        let initial = await ResourceSet().createResource(uri: ReportFixture.targetURI)
        let executed = ATLIncrementalTransformation(module: module, options: options)
        try await executed.execute(
            sources: ["IN": await fixture.projectModel(priorities: [8])], targets: ["OUT": initial])
        #expect(ranks(await summaries(of: initial)) == ["t1": precedence == .eclipse ? 1 : 0])
    }

    @Test("An incremental update reports sibling sub-rules only where the precedence lets them compete", arguments: precedences)
    func incrementalSiblings(precedence: ATLSubRulePrecedence) async throws {
        let module = try await fixture.module(guardedParentOfTwo, options: options(precedence))
        let source = await fixture.projectModel(priorities: [3])
        let target = await ResourceSet().createResource(uri: ReportFixture.targetURI)
        let transformation = ATLIncrementalTransformation(module: module, options: options(precedence))
        try await transformation.execute(sources: ["IN": source], targets: ["OUT": target])
        let task = try #require(await source.getAllObjects().first { $0.eClass.name == "Task" })
        try await source.eSetWithChanges(objectId: task.id, feature: "priority", value: 9)
        let report = try await transformation.update()
        #expect(ranks(await summaries(of: target)) == ["t1": precedence == .eclipse ? 1 : 2])
        #expect(report.warnings.count == (precedence == .eclipse ? 0 : 1))

        let strictSource = await fixture.projectModel(priorities: [3])
        let strictTarget = await ResourceSet().createResource(uri: ReportFixture.targetURI)
        let strict = ATLIncrementalTransformation(module: module, options: options(precedence, conflicts: .error))
        try await strict.execute(sources: ["IN": strictSource], targets: ["OUT": strictTarget])
        let strictTask = try #require(await strictSource.getAllObjects().first { $0.eClass.name == "Task" })
        try await strictSource.eSetWithChanges(objectId: strictTask.id, feature: "priority", value: 9)
        let message = await thrownDescription { _ = try await strict.update() }
        if precedence == .eclipse {
            #expect(message == nil)
            #expect(ranks(await summaries(of: strictTarget)) == ["t1": 1])
        } else {
            #expect(message?.contains("'First'") == true && message?.contains("'Second'") == true)
        }
    }
}
