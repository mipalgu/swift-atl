//
//  ATLAbstractRuleTests.swift
//  ATLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ATL

/// Tests that abstract rules match source elements as ``ATLOptions/abstractRuleMatching``
/// and ``ATLOptions/abstractLeafRules`` select.
///
/// Eclipse ATL tries an abstract rule like any other sub-rule: once it matches an element,
/// only the rules extending it can transform that element. An abstract rule that no rule
/// extends still matches, and the run then fails, because such a rule cannot be applied.
@Suite("ATL Abstract Rule Tests")
@MainActor
struct ATLAbstractRuleTests {

    private let fixture = ReportFixture()

    /// Both precedences of sub-rules.
    nonisolated static let precedences = ATLSubRulePrecedence.allCases

    /// The rule that creates the document of the project.
    private let projectRule = """
        rule P {
            from s : Project!Project
            to t : Report!Document (name <- s.name, highlights <- s.tasks)
        }
        """

    /// An abstract rule extended by an abstract rule with a guard, whose only sub-rule has a
    /// stricter guard, and by a rule with a weaker guard declared after it.
    private let abstractMiddle = """
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

    /// An abstract rule with a guard that no rule extends.
    private let loneAbstract = """
        abstract rule Lone {
            from s : Project!Task (s.priority > 5)
            to t : Report!Summary (title <- s.name, rank <- 1)
        }
        """

    /// A rule extended by an abstract rule with a guard that no rule extends.
    private let abstractLeaf = """
        rule Base {
            from s : Project!Task
            to t : Report!Summary (title <- s.name, rank <- 0)
        }
        abstract rule Leaf extends Base {
            from s : Project!Task (s.priority > 5)
            to t : Report!Summary (rank <- 1)
        }
        """

    /// Options that choose how abstract rules match.
    ///
    /// - Parameters:
    ///   - matching: What an abstract rule whose sub-rules do not match gives.
    ///   - leaves: What an abstract rule that no rule extends gives.
    ///   - precedence: The precedence of sub-rules.
    ///   - conflicts: What sibling sub-rules that match one element give.
    /// - Returns: The standard options with the given choices.
    private func options(
        matching: ATLAbstractRuleMatching = .eclipse, leaves: ATLAbstractLeafRules = .error,
        precedence: ATLSubRulePrecedence = .eclipse, conflicts: ATLSiblingRuleConflicts = .warning
    ) -> ATLOptions {
        var options = ATLOptions(siblingRuleConflicts: conflicts, subRulePrecedence: precedence)
        options.abstractRuleMatching = matching
        options.abstractLeafRules = leaves
        return options
    }

    /// The rank of each summary of a target model, by title.
    ///
    /// - Parameter target: The target model.
    /// - Returns: The rank of each summary, by title; `-1` for an unset rank.
    private func ranks(of target: Resource) async -> [String: Int] {
        var result: [String: Int] = [:]
        for case let summary as DynamicEObject in await target.getAllObjects() where summary.eClass.name == "Summary" {
            if let title = summary.eGet("title") as? String { result[title] = summary.eGet("rank") as? Int ?? -1 }
        }
        return result
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
        return (await ranks(of: run.target), run.machine.getStatistics().warnings)
    }

    // MARK: - Options

    @Test("The default options follow Eclipse ATL and the legacy options keep the earlier behaviour")
    func defaults() {
        #expect(ATLOptions().abstractRuleMatching == .eclipse)
        #expect(ATLOptions().abstractLeafRules == .error)
        #expect(ATLOptions.standard.abstractRuleMatching == .eclipse)
        #expect(ATLOptions.standard.abstractLeafRules == .error)
        #expect(ATLOptions(semantics: .standard) == .standard)
        #expect(ATLOptions.legacy.abstractRuleMatching == .skip)
        #expect(ATLOptions.legacy.abstractLeafRules == .ignore)
        #expect(ATLOptions(semantics: .legacy) == .legacy)
    }

    @Test("The choices are spelt as on a command line and can be set when the options are created")
    func spellings() {
        #expect(ATLAbstractRuleMatching.allCases.map(\.rawValue) == ["eclipse", "skip"])
        #expect(ATLAbstractLeafRules.allCases.map(\.rawValue) == ["error", "ignore"])
        #expect(ATLAbstractRuleMatching(rawValue: "skip") == .skip)
        #expect(ATLAbstractLeafRules(rawValue: "ignore") == .ignore)
        let options = ATLOptions(abstractRuleMatching: .skip, abstractLeafRules: .ignore)
        #expect(options.abstractRuleMatching == .skip)
        #expect(options.abstractLeafRules == .ignore)
        #expect(options.subRulePrecedence == ATLOptions.standard.subRulePrecedence)
        #expect(options != .standard)
        var changed = ATLOptions.standard
        changed.abstractRuleMatching = .skip
        changed.abstractLeafRules = .ignore
        #expect(changed == options)
    }

    // MARK: - An Abstract Rule Whose Sub-Rules Do Not Match

    @Test(
        "An abstract rule that matches keeps the next rule from applying when none of its sub-rules match",
        arguments: precedences)
    func abstractMiddleStops(precedence: ATLSubRulePrecedence) async throws {
        let eclipse = try await outcome(
            abstractMiddle, priorities: [6, 9, 3], options: options(precedence: precedence))
        #expect(eclipse.ranks == ["t2": 2, "t3": 3])
        #expect(eclipse.warnings.count == 1)
        #expect(eclipse.warnings.first?.contains("Task 't2'") == true)
        let skipping = try await outcome(
            abstractMiddle, priorities: [6, 9, 3], options: options(matching: .skip, precedence: precedence))
        #expect(skipping.ranks == ["t1": 3, "t2": 2, "t3": 3])
        #expect(skipping.warnings.count == 1)
        #expect(skipping.warnings.first?.contains("Task 't2'") == true)
    }

    @Test("An abstract root rule whose sub-rules do not match transforms nothing", arguments: precedences)
    func abstractRootWithoutMatchingSubRule(precedence: ATLSubRulePrecedence) async throws {
        let rules = """
            abstract rule Base {
                from s : Project!Task (s.priority > 2)
                to t : Report!Summary (title <- s.name, rank <- 1)
            }
            rule Urgent extends Base {
                from s : Project!Task (s.priority > 7)
                to t : Report!Summary (rank <- 2)
            }
            """
        for matching in ATLAbstractRuleMatching.allCases {
            let result = try await outcome(
                rules, priorities: [9, 5, 1], options: options(matching: matching, precedence: precedence))
            #expect(result.ranks == ["t1": 2])
        }
    }

    @Test("An abstract rule that matches does not stop an unrelated rule from applying")
    func abstractRuleAndUnrelatedRule() async throws {
        let rules = """
            abstract rule Base {
                from s : Project!Task (s.priority > 5)
                to t : Report!Summary (title <- s.name, rank <- 1)
            }
            rule Urgent extends Base {
                from s : Project!Task (s.priority > 7)
                to t : Report!Summary (rank <- 2)
            }
            rule Low {
                from s : Project!Task (s.priority < 7)
                to t : Report!Summary (title <- s.name, rank <- 0)
            }
            """
        for conflicts in ATLSiblingRuleConflicts.allCases {
            let result = try await outcome(rules, priorities: [9, 6, 1], options: options(conflicts: conflicts))
            #expect(result.ranks == ["t1": 2, "t2": 0, "t3": 0])
        }
    }

    @Test("An abstract rule that matches does not keep its own sub-rules from applying")
    func abstractRuleWithMatchingSubRule() async throws {
        let result = try await outcome(abstractMiddle, priorities: [9], options: options())
        #expect(result.ranks == ["t1": 2])
        let warning = try #require(result.warnings.first)
        #expect(result.warnings.count == 1)
        #expect(warning.contains("'Mid'") && warning.contains("'Other'") && warning.contains("only 'Mid' is applied"))
    }

    @Test("Strict sibling conflicts count an abstract sub-rule that matches")
    func strictSiblingConflicts() async throws {
        let message = try #require(
            await thrownDescription {
                _ = try await outcome(abstractMiddle, priorities: [6], options: options(conflicts: .error))
            })
        #expect(message.contains("'Mid'") && message.contains("'Other'") && message.contains("Task 't1'"))
        let skipping = try await outcome(
            abstractMiddle, priorities: [6], options: options(matching: .skip, conflicts: .error))
        #expect(skipping.ranks == ["t1": 3])
        let below = try await outcome(abstractMiddle, priorities: [3], options: options(conflicts: .error))
        #expect(below.ranks == ["t1": 3])
    }

    // MARK: - An Abstract Rule That No Rule Extends

    @Test("An abstract rule that no rule extends stops the run once it matches")
    func loneAbstractRule() async throws {
        let message = try #require(
            await thrownDescription {
                _ = try await outcome(loneAbstract, priorities: [8, 3], options: options())
            })
        #expect(message.contains("'Lone'") && message.contains("Task 't1'"))
        #expect(!message.contains("Task 't2'"))
        let ignored = try await outcome(loneAbstract, priorities: [8, 3], options: options(leaves: .ignore))
        #expect(ignored.ranks.isEmpty)
        let unmatched = try await outcome(loneAbstract, priorities: [3], options: options())
        #expect(unmatched.ranks.isEmpty)
    }

    @Test("An abstract sub-rule that no rule extends stops the run once it is chosen", arguments: precedences)
    func abstractLeafSubRule(precedence: ATLSubRulePrecedence) async throws {
        let message = try #require(
            await thrownDescription {
                _ = try await outcome(abstractLeaf, priorities: [8, 3], options: options(precedence: precedence))
            })
        #expect(message.contains("'Leaf'") && message.contains("Task 't1'"))
        let ignored = try await outcome(
            abstractLeaf, priorities: [8, 3], options: options(leaves: .ignore, precedence: precedence))
        #expect(ignored.ranks == ["t1": 0, "t2": 0])
        let unmatched = try await outcome(abstractLeaf, priorities: [3], options: options(precedence: precedence))
        #expect(unmatched.ranks == ["t1": 0])
    }

    @Test("The two choices about abstract rules are independent")
    func independentChoices() async throws {
        let skipping = try #require(
            await thrownDescription {
                _ = try await outcome(loneAbstract, priorities: [8], options: options(matching: .skip))
            })
        #expect(skipping.contains("'Lone'"))
        let ignoring = try await outcome(
            abstractMiddle, priorities: [6], options: options(leaves: .ignore))
        #expect(ignoring.ranks.isEmpty)
    }

    // MARK: - Incremental Transformations

    @Test(
        "An incremental transformation lets an abstract rule stop the next rule, as a run does",
        arguments: ATLAbstractRuleMatching.allCases)
    func incrementalAbstractMiddle(matching: ATLAbstractRuleMatching) async throws {
        let options = options(matching: matching)
        let module = try await fixture.module(abstractMiddle + projectRule, options: options)
        let source = await fixture.projectModel(priorities: [3])
        let target = await ResourceSet().createResource(uri: ReportFixture.targetURI)
        let transformation = ATLIncrementalTransformation(module: module, options: options)
        try await transformation.execute(sources: ["IN": source], targets: ["OUT": target])
        #expect(await ranks(of: target) == ["t1": 3])

        let task = try #require(await source.getAllObjects().first { $0.eClass.name == "Task" })
        try await source.eSetWithChanges(objectId: task.id, feature: "priority", value: 6)
        let report = try await transformation.update()
        #expect(!report.reexecuted)
        let expected: [String: Int] = matching == .eclipse ? [:] : ["t1": 3]
        #expect(await ranks(of: target) == expected)
        let batch = try await fixture.run(abstractMiddle + projectRule, priorities: [6], options: options)
        #expect(await ranks(of: batch.target) == expected)

        try await source.eSetWithChanges(objectId: task.id, feature: "priority", value: 9)
        _ = try await transformation.update()
        #expect(await ranks(of: target) == ["t1": 2])
    }

    @Test(
        "An incremental update fails once an abstract rule that no rule extends matches",
        arguments: ATLAbstractLeafRules.allCases)
    func incrementalLoneAbstract(leaves: ATLAbstractLeafRules) async throws {
        let options = options(leaves: leaves)
        let module = try await fixture.module(loneAbstract + projectRule, options: options)
        let source = await fixture.projectModel(priorities: [3])
        let target = await ResourceSet().createResource(uri: ReportFixture.targetURI)
        let transformation = ATLIncrementalTransformation(module: module, options: options)
        try await transformation.execute(sources: ["IN": source], targets: ["OUT": target])
        #expect(await ranks(of: target).isEmpty)

        let task = try #require(await source.getAllObjects().first { $0.eClass.name == "Task" })
        try await source.eSetWithChanges(objectId: task.id, feature: "priority", value: 8)
        let message = await thrownDescription { _ = try await transformation.update() }
        if leaves == .error {
            #expect(message?.contains("'Lone'") == true)
        } else {
            #expect(message == nil)
            #expect(await ranks(of: target).isEmpty)
        }
    }
}
