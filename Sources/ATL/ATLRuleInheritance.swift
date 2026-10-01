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
struct ATLEffectiveMatchedRule {

    /// The rule itself, the leaf of the inheritance chain.
    let rule: ATLMatchedRule

    /// The inheritance chain from the root rule to ``rule``.
    let chain: [ATLMatchedRule]

    /// The merged target patterns of the chain.
    let targetPatterns: [ATLEffectiveTargetPattern]

    /// The names of all rules in the chain.
    var chainNames: [String] { chain.map(\.name) }

    /// The local variables of the chain in evaluation order.
    var localVariables: [ATLLocalVariable] { chain.flatMap(\.localVariables) }

    /// The imperative statements of the chain in execution order.
    var doStatements: [any ATLStatement] { chain.flatMap(\.doStatements) }
}

// MARK: - Rule Inheritance

/// Resolves the `extends` relationships between the matched rules of a module.
enum ATLRuleInheritance {

    /// Computes the effective rules for all non-abstract matched rules of a module.
    ///
    /// - Parameters:
    ///   - rules: The matched rules of the module in declaration order
    ///   - conforms: Decides whether the source type of the first rule conforms to that
    ///     of the second rule, as the sub-rule must match a subtype of its super rule
    /// - Returns: The effective rules, in declaration order
    /// - Throws: ``ATLExecutionError/invalidOperation(_:)`` if a rule extends an unknown
    ///   rule, the `extends` relationships are circular, or a sub-rule's source type does
    ///   not conform to the source type of its super rule
    static func effectiveRules(
        for rules: [ATLMatchedRule],
        conforms: (ATLSourcePattern, ATLSourcePattern) throws -> Bool
    ) throws -> [ATLEffectiveMatchedRule] {
        let rulesByName = Dictionary(rules.map { ($0.name, $0) }) { first, _ in first }
        var effective: [ATLEffectiveMatchedRule] = []

        for rule in rules {
            var chain = [rule]
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
                guard try conforms(current.sourcePattern, superRule.sourcePattern) else {
                    throw ATLExecutionError.typeError(
                        "Source type '\(current.sourcePattern.type)' of rule '\(current.name)' does not conform to '\(superRule.sourcePattern.type)' of the rule it extends"
                    )
                }
                chain.insert(superRule, at: 0)
                current = superRule
            }
            guard !rule.isAbstract else { continue }
            effective.append(
                ATLEffectiveMatchedRule(
                    rule: rule, chain: chain, targetPatterns: mergedTargetPatterns(of: chain)))
        }
        return effective
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
