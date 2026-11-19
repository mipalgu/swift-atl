//
//  ATLRuleInheritance.swift
//  ATL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

// MARK: - Effective Target Pattern

/// A target pattern after rule inheritance has been applied.
///
/// A target pattern that a sub-rule redeclares under the same name as one of
/// its super rule takes the sub-rule's type and carries the super rule's
/// bindings, overridden property by property by the sub-rule's own.
struct ATLEffectiveTargetPattern {

    /// The target pattern variable name.
    let variableName: String

    /// The qualified type of the element to create.
    let type: String

    /// The bindings to apply, in application order.
    let bindings: [ATLPropertyBinding]
}

// MARK: - Effective Matched Rule

/// A matched rule together with everything it inherits.
///
/// The effective rule lists the target patterns of the whole inheritance chain,
/// super rule patterns first, so that the default target element of a source
/// element is the first target pattern of the root rule.
///
/// Each rule of the chain binds the matched source elements to its own source pattern
/// variables. A variable of a rule extending another stands for the variable of the same
/// name of the rule it extends; the variables whose names the two rules do not share
/// stand for each other in declaration order.
struct ATLEffectiveMatchedRule {

    /// The rule itself, the leaf of the inheritance chain.
    let rule: ATLMatchedRule

    /// The inheritance chain from the root rule to ``rule``.
    let chain: [ATLMatchedRule]

    /// The merged target patterns of the chain.
    let targetPatterns: [ATLEffectiveTargetPattern]

    /// For each rule of ``chain``, the position among the source elements of ``rule`` of
    /// the element bound to each of its source pattern variables, in declaration order.
    let sourcePositions: [[Int]]

    /// The names of the source pattern variables of the root rule of ``chain`` that the
    /// source elements of ``rule`` are bound to, in the order of the elements.
    let identityVariables: [String]

    /// Creates the effective rule of an inheritance chain.
    ///
    /// - Parameters:
    ///   - rule: The leaf of the chain.
    ///   - chain: The rules from the root of the chain to `rule`.
    ///   - targetPatterns: The merged target patterns of the chain.
    ///   - sourcePositions: For each rule of `chain`, the position among the source elements
    ///     of `rule` of the element bound to each of its source pattern variables.
    init(
        rule: ATLMatchedRule, chain: [ATLMatchedRule], targetPatterns: [ATLEffectiveTargetPattern],
        sourcePositions: [[Int]]
    ) {
        self.rule = rule
        self.chain = chain
        self.targetPatterns = targetPatterns
        self.sourcePositions = sourcePositions
        var names = rule.sourcePatterns.map(\.variableName)
        if let root = chain.first, let positions = sourcePositions.first {
            for (pattern, position) in zip(root.sourcePatterns, positions) where names.indices.contains(position) {
                names[position] = pattern.variableName
            }
        }
        identityVariables = names
    }

    /// The names of all rules in the chain.
    var chainNames: [String] { chain.map(\.name) }

    /// The local variables of the chain in evaluation order.
    var localVariables: [ATLLocalVariable] { chain.flatMap(\.localVariables) }

    /// The imperative statements of the chain in execution order.
    var doStatements: [any ATLStatement] { chain.flatMap(\.doStatements) }

    /// The source pattern variables of the chain and the elements bound to them.
    ///
    /// - Parameter sources: The matched source elements, in the order in which ``rule``
    ///   declares its source pattern elements.
    /// - Returns: Each variable of each rule of ``chain`` with its element, the variables of
    ///   the root rule first and those of ``rule`` last, so that binding them in order
    ///   leaves the variables of ``rule`` in force.
    func sourceBindings<Element>(of sources: [Element]) -> [(name: String, value: Element)] {
        var bindings: [(name: String, value: Element)] = []
        for (member, positions) in zip(chain, sourcePositions) {
            for (pattern, position) in zip(member.sourcePatterns, positions) where sources.indices.contains(position) {
                bindings.append((pattern.variableName, sources[position]))
            }
        }
        return bindings
    }

    /// Identifies a match of the rule among the matches of all matched rules.
    ///
    /// The elements of a match of several source elements are identified by the variables
    /// of the root rule of ``chain`` they are bound to, so that a rule and the rules
    /// extending it identify the same elements alike.
    ///
    /// - Parameter sources: The identifiers of the matched source elements, in the order
    ///   in which ``rule`` declares its source pattern elements.
    /// - Returns: The identity of the match.
    func matchIdentity(of sources: [EUUID]) -> ATLMatchIdentity {
        ATLMatchIdentity(variables: identityVariables, sources: sources)
    }
}

extension ATLMatchedRule {

    /// Whether the rule has a guard, on its source pattern as a whole or on one of its
    /// source pattern elements.
    var hasGuard: Bool {
        self.guard != nil || additionalSourcePatterns.contains { $0.guard != nil }
    }
}

// MARK: - Match Identity

/// What identifies the match of a matched rule, as Eclipse ATL identifies it.
///
/// A source element, or a tuple of source elements, is transformed by at most one matched
/// rule, so two matches with the same identity are a conflict. A match of a rule with one
/// source pattern element is identified by that element alone, whatever its variable is
/// called. A match of a rule with several source pattern elements is identified by the
/// variable that each element is bound to: two rules that bind the same elements to the
/// same variables match the same tuple even when they declare the variables in different
/// orders, and two rules that bind the same elements to different variables do not.
enum ATLMatchIdentity: Hashable {

    /// The match of a rule with one source pattern element.
    ///
    /// - Parameter element: The identifier of the matched element.
    case element(EUUID)

    /// The match of a rule with several source pattern elements.
    ///
    /// - Parameter elements: The identifier of each matched element, indexed by the name
    ///   of the variable it is bound to.
    case tuple([String: EUUID])

    /// Creates the identity of a match.
    ///
    /// - Parameters:
    ///   - variables: The names of the source pattern variables, in declaration order.
    ///   - sources: The identifiers of the matched elements, parallel to `variables`.
    init(variables: [String], sources: [EUUID]) {
        if sources.count == 1, let element = sources.first {
            self = .element(element)
        } else {
            self = .tuple(Dictionary(zip(variables, sources)) { _, last in last })
        }
    }
}

// MARK: - Match Selection

/// Sub-rules of one rule that make the same match, and the one of them that is applied.
struct ATLSiblingChoice: Equatable {

    /// The position, among the candidate matches, of the match that is made.
    let position: Int

    /// The name of the rule that the sub-rules extend.
    let parent: String

    /// The names of the sub-rules that make the match, in the order in which they are tried.
    let siblings: [String]

    /// The name of the sub-rule that is applied, the first of ``siblings``.
    let applied: String
}

/// Two matches with the same ``ATLMatchIdentity`` that rule inheritance does not decide
/// between.
struct ATLMatchConflict: Error, Equatable {

    /// The name of the rule of the match made first.
    let first: String

    /// The name of the rule of the other match.
    let second: String

    /// The position, among the candidate matches, of the other match.
    let position: Int
}

/// Decides which candidate matches of the matched rules are made.
///
/// Matches with different ``ATLMatchIdentity`` values never affect each other. Among the
/// matches with one identity, a match of a rule is not made when a rule extending it,
/// directly or through other rules, makes the match too, except that under
/// ``ATLSubRulePrecedence/eclipse`` a match of a rule with a guard is made instead of the
/// matches of the rules extending it without a guard, and of the rules extending those. Of
/// two sub-rules of one rule that make the match, the sub-rule that Eclipse ATL tries
/// first is applied: sub-rules with a guard before those without one, each in declaration
/// order. With ``ATLSiblingRuleConflicts/error``, such sub-rules are a conflict instead, as
/// are, under every option, two rules that do not extend a common rule.
struct ATLMatchSelection {

    /// The positions of the matches that are made, in ascending order.
    let selected: [Int]

    /// The choices between sub-rules that decided which matches are made, in the order
    /// of the matches made.
    let choices: [ATLSiblingChoice]

    /// The number of times a candidate match was examined while deciding.
    let comparisons: Int

    /// Decides which candidate matches are made.
    ///
    /// - Parameters:
    ///   - rules: The rule of each candidate match, in candidate order.
    ///   - identities: The identity of each candidate match, parallel to `rules`.
    ///   - declarationOrder: The position of each matched rule of the module, abstract rules
    ///     included, by name.
    ///   - conflicts: What two sub-rules of one rule that make the same match give.
    ///   - precedence: Which of a rule and the rules extending it that make the same match
    ///     is applied.
    /// - Throws: ``ATLMatchConflict`` for the first two matches, in candidate order, with the
    ///   same identity that are both made.
    init(
        rules: [ATLEffectiveMatchedRule], identities: [ATLMatchIdentity], declarationOrder: [String: Int],
        conflicts: ATLSiblingRuleConflicts, precedence: ATLSubRulePrecedence
    ) throws(ATLMatchConflict) {
        var comparisons = 0
        var made = Set<Int>()
        var choices: [ATLSiblingChoice] = []
        let groups = Dictionary(grouping: rules.indices) { identities[$0] }
        for positions in groups.values {
            switch conflicts {
            case .error:
                // Every match that no match of another rule takes precedence over is made
                for position in positions {
                    let hidden = positions.contains { other in
                        comparisons += 1
                        return Self.precedes(rules[other], over: rules[position], precedence: precedence)
                    }
                    if !hidden { made.insert(position) }
                }
            case .warning:
                let hierarchies = Dictionary(grouping: positions) { rules[$0].chain[0].name }
                for members in hierarchies.values {
                    let (winner, choice) = Self.firstMatch(
                        among: members, rules: rules, declarationOrder: declarationOrder, precedence: precedence,
                        comparisons: &comparisons)
                    made.insert(winner)
                    if let choice { choices.append(choice) }
                }
            }
        }
        var selected: [Int] = []
        var ruleByMatch: [ATLMatchIdentity: String] = [:]
        for position in made.sorted() {
            let name = rules[position].rule.name
            if let first = ruleByMatch.updateValue(name, forKey: identities[position]) {
                throw ATLMatchConflict(first: first, second: name, position: position)
            }
            selected.append(position)
        }
        self.selected = selected
        self.choices = choices.sorted { $0.position < $1.position }
        self.comparisons = comparisons
    }

    /// Decides whether the match of one rule takes precedence over the match of another
    /// with the same identity.
    ///
    /// - Parameters:
    ///   - rule: The rule of the match that may take precedence.
    ///   - other: The rule of the other match.
    ///   - precedence: Which of a rule and the rules extending it is applied.
    /// - Returns: `true` if `rule` extends `other`, directly or through other rules, and,
    ///   under ``ATLSubRulePrecedence/eclipse``, `other` has no guard or `rule` extends it
    ///   through a rule with a guard that extends `other` directly; also `true` under
    ///   ``ATLSubRulePrecedence/eclipse`` if `other` extends `rule` through a rule without
    ///   a guard that extends `rule` directly, and `rule` has a guard.
    private static func precedes(
        _ rule: ATLEffectiveMatchedRule, over other: ATLEffectiveMatchedRule, precedence: ATLSubRulePrecedence
    ) -> Bool {
        /// Whether a rule with a guard comes before the sub-rule that leads to a rule extending it.
        func guardFirst(_ base: ATLMatchedRule, in chain: [ATLMatchedRule], at level: Int) -> Bool {
            precedence == .eclipse && base.hasGuard && chain.indices.contains(level + 1)
                && !chain[level + 1].hasGuard
        }
        guard rule.rule.name != other.rule.name else { return false }
        if let level = rule.chainNames.firstIndex(of: other.rule.name) {
            return !guardFirst(other.rule, in: rule.chain, at: level)
        }
        if let level = other.chainNames.firstIndex(of: rule.rule.name) {
            return guardFirst(rule.rule, in: other.chain, at: level)
        }
        return false
    }

    /// Finds the match that Eclipse ATL makes among matches of one rule hierarchy.
    ///
    /// Starting at the root rule, the sub-rules whose matches are among `members` are tried
    /// in order, and the first is descended into, until a rule with no such sub-rule is
    /// reached. Under ``ATLSubRulePrecedence/eclipse``, a rule with a guard whose own match
    /// is among `members` is applied before its sub-rules without a guard are tried.
    ///
    /// - Parameters:
    ///   - members: The positions of the candidate matches with one identity whose rules
    ///     share a root rule.
    ///   - rules: The rule of each candidate match.
    ///   - declarationOrder: The position of each matched rule of the module, by name.
    ///   - precedence: Which of a rule and the rules extending it is applied.
    ///   - comparisons: The number of candidate matches examined, increased by those
    ///     examined here.
    /// - Returns: The position of the match made, and the first choice between sub-rules
    ///   that decided it, if any.
    private static func firstMatch(
        among members: [Int], rules: [ATLEffectiveMatchedRule], declarationOrder: [String: Int],
        precedence: ATLSubRulePrecedence, comparisons: inout Int
    ) -> (winner: Int, choice: ATLSiblingChoice?) {
        var remaining = members
        var depth = 0
        var parent = rules[members[0]].chain[0]
        var choice: (parent: String, siblings: [String], applied: String)?
        while true {
            comparisons += remaining.count
            var branches: [String: (rule: ATLMatchedRule, members: [Int])] = [:]
            for member in remaining where rules[member].chain.count > depth + 1 {
                let child = rules[member].chain[depth + 1]
                branches[child.name, default: (child, [])].members.append(member)
            }
            let own = remaining.first { rules[$0].chain.count == depth + 1 }
            let tried = branches.values.map(\.rule).filter {
                // Eclipse ATL applies a matching rule with a guard before its sub-rules without one
                precedence == .extendingRule || own == nil || !parent.hasGuard || $0.hasGuard
            }.sorted {
                ($0.hasGuard ? 0 : 1, declarationOrder[$0.name] ?? .max)
                    < ($1.hasGuard ? 0 : 1, declarationOrder[$1.name] ?? .max)
            }
            guard let next = tried.first, let nextMembers = branches[next.name]?.members else {
                let winner = own ?? remaining[0]
                let made = choice.map {
                    ATLSiblingChoice(position: winner, parent: $0.parent, siblings: $0.siblings, applied: $0.applied)
                }
                return (winner, made)
            }
            if choice == nil, tried.count > 1 {
                choice = (parent.name, tried.map(\.name), next.name)
            }
            parent = next
            remaining = nextMembers
            depth += 1
        }
    }
}

// MARK: - Rule Inheritance

/// Resolves the `extends` relationships between the matched rules of a module.
enum ATLRuleInheritance {

    /// Computes the effective rules for all non-abstract matched rules of a module.
    ///
    /// A rule extending another must declare as many source pattern elements as the rule
    /// it extends. Each of its variables stands for the variable of the same name of the
    /// rule it extends, as in Eclipse ATL, in whatever order the two rules declare them;
    /// the variables whose names the two rules do not share stand for each other in
    /// declaration order. The type of each variable must conform to the type of the
    /// variable it stands for.
    ///
    /// - Parameters:
    ///   - rules: The matched rules of the module in declaration order
    ///   - conforms: Decides whether the type of the first source pattern element, of a
    ///     sub-rule, conforms to that of the second, of the rule it extends, as the
    ///     sub-rule must match a subtype of its super rule
    /// - Returns: The effective rules, in declaration order
    /// - Throws: ``ATLExecutionError/invalidOperation(_:)`` if a rule extends an unknown
    ///   rule, the `extends` relationships are circular, or a sub-rule declares fewer or more
    ///   source pattern elements than the rule it extends, and
    ///   ``ATLExecutionError/typeError(_:)`` if the type of a source pattern element of a
    ///   sub-rule does not conform to the type of the element it stands for
    static func effectiveRules(
        for rules: [ATLMatchedRule],
        conforms: (ATLSourcePattern, ATLSourcePattern) throws -> Bool
    ) throws -> [ATLEffectiveMatchedRule] {
        let rulesByName = Dictionary(rules.map { ($0.name, $0) }) { first, _ in first }
        var effective: [ATLEffectiveMatchedRule] = []

        for rule in rules {
            var chain = [rule]
            var positions = [Array(rule.sourcePatterns.indices)]
            var visited: Set<String> = [rule.name]
            var current = rule
            while let superName = current.superRuleName {
                guard let superRule = rulesByName[superName] else {
                    throw ATLExecutionError.invalidOperation(
                        "Rule '\(current.name)' extends unknown rule '\(superName)'")
                }
                guard visited.insert(superName).inserted else {
                    throw ATLExecutionError.invalidOperation(
                        "Rule '\(rule.name)' has a circular 'extends' relationship")
                }
                let pairing = try variablePairing(of: current, with: superRule, conforms: conforms)
                positions.insert(pairing.map { positions[0][$0] }, at: 0)
                chain.insert(superRule, at: 0)
                current = superRule
            }
            guard !rule.isAbstract else { continue }
            effective.append(
                ATLEffectiveMatchedRule(
                    rule: rule, chain: chain, targetPatterns: mergedTargetPatterns(of: chain),
                    sourcePositions: positions))
        }
        return effective
    }

    /// Pairs the source pattern variables of a rule with those of the rule it extends.
    ///
    /// - Parameters:
    ///   - sub: The rule extending `base`.
    ///   - base: The rule that `sub` extends.
    ///   - conforms: Decides whether the type of a source pattern element of `sub` conforms
    ///     to the type of an element of `base`.
    /// - Returns: For each source pattern variable of `base`, in declaration order, the
    ///   position of the variable of `sub` that stands for it.
    /// - Throws: ``ATLExecutionError/invalidOperation(_:)`` when `sub` declares fewer or more
    ///   source pattern elements than `base`, and ``ATLExecutionError/typeError(_:)`` when
    ///   the type of an element of `sub` does not conform to the type of the element of
    ///   `base` it stands for.
    private static func variablePairing(
        of sub: ATLMatchedRule, with base: ATLMatchedRule,
        conforms: (ATLSourcePattern, ATLSourcePattern) throws -> Bool
    ) throws -> [Int] {
        let subPatterns = sub.sourcePatterns
        let basePatterns = base.sourcePatterns
        let subNames = Set(subPatterns.map(\.variableName))
        let baseNames = Set(basePatterns.map(\.variableName))
        if subPatterns.count < basePatterns.count {
            throw ATLExecutionError.invalidOperation(
                ATLExecutionMessage.missingSourceVariables(
                    basePatterns.map(\.variableName).filter { !subNames.contains($0) }, rule: sub.name,
                    extended: base.name))
        }
        if subPatterns.count > basePatterns.count {
            throw ATLExecutionError.invalidOperation(
                ATLExecutionMessage.extraSourceVariables(
                    subPatterns.map(\.variableName).filter { !baseNames.contains($0) }, rule: sub.name,
                    extended: base.name))
        }
        var pairing: [Int?] = basePatterns.map { pattern in
            subPatterns.firstIndex { $0.variableName == pattern.variableName }
        }
        let paired = Set(pairing.compactMap { $0 })
        var unpaired = subPatterns.indices.filter { !paired.contains($0) }.makeIterator()
        for index in pairing.indices where pairing[index] == nil {
            pairing[index] = unpaired.next()
        }
        let positions = pairing.compactMap { $0 }
        for (basePattern, position) in zip(basePatterns, positions) {
            let subPattern = subPatterns[position]
            guard try conforms(subPattern, basePattern) else {
                throw ATLExecutionError.typeError(
                    ATLExecutionMessage.nonConformingSourceVariable(
                        subPattern.variableName, type: subPattern.type, rule: sub.name,
                        extendedVariable: basePattern.variableName, extendedType: basePattern.type,
                        extended: base.name))
            }
        }
        return positions
    }

    /// Merges the target patterns of an inheritance chain.
    ///
    /// - Parameter chain: The rules from the root to the leaf
    /// - Returns: The merged patterns, in order of first declaration
    private static func mergedTargetPatterns(of chain: [ATLMatchedRule])
        -> [ATLEffectiveTargetPattern]
    {
        var merged: [ATLEffectiveTargetPattern] = []
        for rule in chain {
            for pattern in rule.targetPatterns {
                if let index = merged.firstIndex(where: { $0.variableName == pattern.variableName }) {
                    merged[index] = ATLEffectiveTargetPattern(
                        variableName: pattern.variableName,
                        type: pattern.type,
                        bindings: overriding(merged[index].bindings, with: pattern.bindings))
                } else {
                    merged.append(
                        ATLEffectiveTargetPattern(
                            variableName: pattern.variableName,
                            type: pattern.type,
                            bindings: pattern.bindings))
                }
            }
        }
        return merged
    }

    /// Replaces the bindings of inherited properties with the redeclared ones.
    ///
    /// - Parameters:
    ///   - inherited: The bindings of the super rule
    ///   - declared: The bindings of the sub-rule
    /// - Returns: The inherited bindings with redeclared ones replaced in place and
    ///   new ones appended
    private static func overriding(
        _ inherited: [ATLPropertyBinding], with declared: [ATLPropertyBinding]
    ) -> [ATLPropertyBinding] {
        var result = inherited
        for binding in declared {
            if let index = result.firstIndex(where: { $0.property == binding.property }) {
                result[index] = binding
            } else {
                result.append(binding)
            }
        }
        return result
    }
}
