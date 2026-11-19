//
//  ATLOptions.swift
//  ATL
//
//  Created by Rene Hexel on 30/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import Foundation

/// Whether ATL source may write integer ranges in collection literals.
///
/// OCL 2.4 lets a collection literal hold integer ranges `first..last`, as in
/// `Sequence{1..3}` or `Sequence{0, 2..4, 9}`. The grammar of Eclipse ATL has no
/// ranges, so a transformation that uses them does not compile with Eclipse ATL.
/// The raw value of each case is its spelling on a command line.
public enum ATLCollectionRangeSyntax: String, Sendable, CaseIterable, Hashable {
    /// Collection literals accept OCL integer ranges.
    ///
    /// A range contributes every integer from its first to its last value to the
    /// literal. This is the default.
    case ocl

    /// Collection ranges are rejected, as Eclipse ATL and swift-atl 0.6 reject them.
    ///
    /// A range is reported as a syntax error whose message names the portable
    /// alternatives: listing the integers, or calling `includingRange`, which the
    /// Eclipse ATL EMFTVM provides. Source text is also split into tokens as
    /// swift-atl 0.6 split it, so `..` is two `.` tokens.
    case eclipse
}

/// How collection ranges are written to XMI.
///
/// A range has no counterpart among the OCL expression classes of Eclipse ATL,
/// and swift-atl 0.6 cannot read it back from XMI. Ranges can therefore be written
/// either as they are or with expressions that those readers know. The raw value
/// of each case is its spelling on a command line.
public enum ATLCollectionRangeEncoding: String, Sendable, CaseIterable, Hashable {
    /// Each range is written as an OCL `CollectionRange` part with `first` and `last` bounds.
    ///
    /// Reading the XMI back yields the identical expression. This is the default.
    case collectionRange = "collection-range"

    /// Ranges are written with expressions that swift-atl 0.6 and Eclipse ATL also know.
    ///
    /// A range whose bounds are integer literals is written as the integers it spans,
    /// as in `Sequence{1, 2, 3}` for `Sequence{1..3}`, unless it is longer than a
    /// range may be. Any other range is written as a call of `includingRange` on the
    /// items before it, and the items after it are added with `includingAll`, so
    /// `Sequence{0, 1..n, 9}` becomes
    /// `Sequence{0}->includingRange(1, n)->includingAll(Sequence{9})`.
    /// Reading the XMI back yields an equivalent expression without ranges. Eclipse ATL
    /// provides these operations only in its EMFTVM, which reports an error where a
    /// range would be empty because its first value is greater than its last.
    case portable
}

/// What the `/` operator yields for two Integer operands.
///
/// In OCL and in Eclipse ATL, `/` divides as Reals, so `7 / 2` is `3.5` even when
/// both operands are Integers, and `div` is the operator of integer division.
/// swift-atl 0.6 instead truncated the quotient of two Integers to an Integer.
/// A Real operand makes the quotient a Real either way. The raw value of each case
/// is its spelling on a command line.
public enum ATLIntegerDivision: String, Sendable, CaseIterable, Hashable {
    /// The quotient of two Integers is a Real, as in OCL and Eclipse ATL.
    ///
    /// `7 / 2` is `3.5` and `8 / 2` is `4.0`. This is the default.
    case real

    /// The quotient of two Integers is truncated towards zero, as in swift-atl 0.6.
    ///
    /// `7 / 2` is `3` and `-7 / 2` is `-3`, the result of `div`.
    case truncating
}

/// What a Bag value is when ATL expressions evaluate.
///
/// In OCL and in the Eclipse ATL EMFTVM, a Bag is an unordered collection that keeps
/// duplicates and is a collection kind of its own: it is neither a Sequence nor a Set.
/// swift-atl 0.6 evaluated `Bag{...}` literals, `asBag()` and the operations whose
/// result is a Bag to Sequences. The raw value of each case is its spelling on a
/// command line.
public enum ATLBagRepresentation: String, Sendable, CaseIterable, Hashable {
    /// Bags are a collection kind of their own, as in OCL and the Eclipse ATL EMFTVM.
    ///
    /// A Bag keeps its duplicates, conforms to `Bag(T)` and `Collection(T)` but not to
    /// `Sequence(T)`, reports its type as `Bag`, is written as `Bag{...}`, is the receiver
    /// of helpers declared for `Bag(T)` rather than `Sequence(T)`, and equals another
    /// collection that holds each element equally often, in any order. `collect` over a
    /// Set or a Bag gives a Bag, and so does navigating a feature over one, as in
    /// `classes.name` for a Set `classes`; over a Sequence or an OrderedSet, both give a
    /// Sequence. `asSet()` gives a Set for every receiver. This is the default.
    case bag

    /// Bags are Sequences, as in swift-atl 0.6.
    ///
    /// `Bag{...}` literals, `asBag()` and the operations whose result is a Bag, such as
    /// `collect` on a Set, give Sequences, which keep their order, conform to `Sequence(T)`
    /// and compare element by element. Navigating a feature over any collection gives a
    /// Sequence. `asSet()` on a Sequence or a single value gives a Sequence without
    /// duplicates rather than a Set, also as in swift-atl 0.6.
    case sequence

    /// The collection kind that an evaluation produces for a requested kind.
    ///
    /// Only the Bag kind depends on the representation: ``sequence`` replaces it with the
    /// Sequence kind, and every other kind is produced as requested.
    ///
    /// - Parameter kind: The kind that the OCL or ATL semantics of an operation call for.
    /// - Returns: The kind of collection to produce.
    public func kind(for kind: ATLCollectionKind) -> ATLCollectionKind {
        self == .sequence && kind == .bag ? .sequence : kind
    }
}

/// What a source element that two sub-rules of the same rule both match gives.
///
/// Two rules that extend the same rule, directly or through other rules, can both match
/// a source element, or the same tuple of source elements. Eclipse ATL then applies only
/// the first of them that matches, trying the sub-rules of a rule that have a guard
/// before those that have none, each in declaration order, and descending into the
/// sub-rules of the one it applies. The raw value of each case is its spelling on a
/// command line.
public enum ATLSiblingRuleConflicts: String, Sendable, CaseIterable, Hashable {
    /// The first matching sub-rule transforms the element, as in Eclipse ATL, and the run
    /// reports a warning.
    ///
    /// The warning names the element, the sub-rules that match it and the rule they extend,
    /// and says which sub-rule is applied. This is the default.
    case warning

    /// The run stops with an error naming two of the sub-rules and the element, before any
    /// rule creates a target element.
    ///
    /// The error is ``ATLExecutionError/invalidOperation(_:)``, as for two unrelated rules
    /// that match the same element.
    case error
}

/// Which rule transforms a source element that a rule and a rule extending it both match.
///
/// A rule and the rules that extend it, directly or through other rules, can all match a
/// source element, or the same tuple of source elements, and only one of them transforms
/// it. Eclipse ATL usually applies the rule that extends the other, but tries a rule that
/// has a guard and is not abstract before the rules extending it that have none, so that
/// those rules never transform an element that it matches. The raw value of each case is
/// its spelling on a command line.
public enum ATLSubRulePrecedence: String, Sendable, CaseIterable, Hashable {
    /// The rules are tried in the order of Eclipse ATL.
    ///
    /// For a rule that matches an element, the rules extending it that have a guard are
    /// tried first, then the rule itself if it has a guard, then the rules extending it that
    /// have none, and last the rule itself if it has none, each group in declaration order;
    /// an abstract rule is never itself applied. The first of them that matches transforms
    /// the element, and when it is a rule extending the other, the rules extending it are
    /// tried in turn in the same way. A rule extending another without a guard therefore
    /// never transforms an element that the other matches with its guard. This is the
    /// default.
    case eclipse

    /// A rule that extends another always takes precedence over it, as in swift-atl 0.6.
    ///
    /// A rule transforms an element only when none of the rules extending it match the
    /// element. Of several rules extending one rule that match it, those with a guard are
    /// tried before those without one, each in declaration order, as under ``eclipse``.
    case extendingRule = "extending-rule"
}

/// Options that choose between the current behaviour of ATL processing and the
/// behaviour of swift-atl 0.6.
///
/// Each property selects one behaviour. The default options, also available as
/// ``standard``, give the current behaviour; ``legacy`` gives the behaviour of
/// swift-atl 0.6. APIs that existed in swift-atl 0.6 and take no options use
/// ``legacy``. Under ``standard``, a rule and the rules extending it are tried in the order
/// of Eclipse ATL; under ``legacy``, a rule extending another always takes precedence over
/// it, and ``subRulePrecedence`` chooses between the two. Both presets report two sub-rules
/// that match the same element with a warning; ``siblingRuleConflicts`` makes that an
/// error:
///
/// ```swift
/// let parser = ATLParser(options: .standard)
/// let module = try await parser.parse(url)
/// let xmi = try ATLXMISerializer(options: ATLOptions(collectionRangeEncoding: .portable))
///     .serialize(module)
/// var strict = ATLOptions.standard
/// strict.siblingRuleConflicts = .error
/// try await ATLVirtualMachine(module: module, options: strict)
///     .execute(sources: ["IN": source], targets: ["OUT": target])
/// ```
public struct ATLOptions: Sendable, Hashable {
    /// Whether ATL source may write integer ranges in collection literals.
    public var collectionRangeSyntax: ATLCollectionRangeSyntax

    /// How collection ranges are written to XMI.
    public var collectionRangeEncoding: ATLCollectionRangeEncoding

    /// What the `/` operator yields for two Integer operands.
    ///
    /// The virtual machine and the execution context that are given the options
    /// divide as this selects.
    public var integerDivision: ATLIntegerDivision

    /// What a Bag value is when ATL expressions evaluate.
    ///
    /// The virtual machine and the execution context that are given the options
    /// produce Bags as this selects.
    public var bagRepresentation: ATLBagRepresentation

    /// What a source element that two sub-rules of the same rule both match gives.
    ///
    /// The virtual machine and the incremental transformation that are given the options
    /// apply the first matching sub-rule with a warning, or stop with an error, as this
    /// selects. Two rules that do not extend the same rule and match the same element are
    /// an error whatever this selects.
    public var siblingRuleConflicts: ATLSiblingRuleConflicts

    /// Which rule transforms a source element that a rule and a rule extending it both match.
    ///
    /// The virtual machine and the incremental transformation that are given the options
    /// choose between a rule and the rules extending it as this selects. This also decides
    /// which sub-rules of one rule compete for an element, and so which of them
    /// ``siblingRuleConflicts`` reports: under ``ATLSubRulePrecedence/eclipse``, the rules
    /// without a guard that extend a matching rule with one do not compete.
    public var subRulePrecedence: ATLSubRulePrecedence

    /// Creates a set of options.
    ///
    /// - Parameters:
    ///   - collectionRangeSyntax: Whether ATL source may write integer ranges in collection literals.
    ///   - collectionRangeEncoding: How collection ranges are written to XMI.
    ///   - integerDivision: What the `/` operator yields for two Integer operands.
    ///   - bagRepresentation: What a Bag value is when ATL expressions evaluate.
    ///   - siblingRuleConflicts: What a source element that two sub-rules of the same rule
    ///     both match gives.
    ///   - subRulePrecedence: Which rule transforms a source element that a rule and a rule
    ///     extending it both match.
    public init(
        collectionRangeSyntax: ATLCollectionRangeSyntax = .ocl,
        collectionRangeEncoding: ATLCollectionRangeEncoding = .collectionRange,
        integerDivision: ATLIntegerDivision = .real,
        bagRepresentation: ATLBagRepresentation = .bag,
        siblingRuleConflicts: ATLSiblingRuleConflicts = .warning,
        subRulePrecedence: ATLSubRulePrecedence = .eclipse
    ) {
        self.collectionRangeSyntax = collectionRangeSyntax
        self.collectionRangeEncoding = collectionRangeEncoding
        self.integerDivision = integerDivision
        self.bagRepresentation = bagRepresentation
        self.siblingRuleConflicts = siblingRuleConflicts
        self.subRulePrecedence = subRulePrecedence
    }

    /// The current behaviour, which the default initialiser also gives.
    ///
    /// Collection literals accept OCL integer ranges, ranges are written to XMI
    /// as OCL collection ranges, `/` divides two Integers into a Real, Bags are
    /// a collection kind of their own, a rule and the rules extending it are tried in the
    /// order of Eclipse ATL, and the first of two sub-rules that match the same element
    /// transforms it, with a warning.
    public static let standard = ATLOptions()

    /// The behaviour of swift-atl 0.6.
    ///
    /// Collection ranges are rejected as syntax errors, as swift-atl 0.6 rejected them.
    /// Ranges built in code are written to XMI as OCL collection ranges, because
    /// swift-atl 0.6 had no ranges that it could write. `/` truncates the quotient of
    /// two Integers to an Integer, Bags are Sequences, and a rule that extends another
    /// always takes precedence over it. As swift-atl 0.6 did not stop a run for two
    /// sub-rules that match the same element, the first of them transforms it, with a
    /// warning, as under ``standard``.
    public static let legacy = ATLOptions(
        collectionRangeSyntax: .eclipse, integerDivision: .truncating, bagRepresentation: .sequence,
        subRulePrecedence: .extendingRule)

    /// Creates the options that a choice of semantics selects.
    ///
    /// `ModellingSemantics/standard` selects ``standard`` and
    /// `ModellingSemantics/legacy` selects ``legacy``.
    ///
    /// - Parameter semantics: The semantics to follow.
    public init(semantics: ModellingSemantics) {
        switch semantics {
        case .standard: self = .standard
        case .legacy: self = .legacy
        }
    }

    /// Creates the options that an environment selects.
    ///
    /// The `SWIFT_MODELLING_SEMANTICS` variable (`ModellingSemantics/environmentVariable`)
    /// selects ``standard`` or ``legacy`` by its value, `standard` or `legacy`. Without the
    /// variable, or with an empty value, the options are ``standard``. A parser can take its
    /// options from the environment of the process once, when it is created:
    ///
    /// ```swift
    /// let parser = ATLParser(options: try ATLOptions.fromEnvironment())
    /// ```
    ///
    /// - Parameter environment: The environment variables to read; by default those of the
    ///   current process.
    /// - Returns: The selected options.
    /// - Throws: `ModellingSemanticsError/invalidValue(_:variable:)` if the variable holds
    ///   any other value.
    public static func fromEnvironment(
        _ environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws(ModellingSemanticsError) -> ATLOptions {
        ATLOptions(semantics: try ModellingSemantics.fromEnvironment(environment) ?? .standard)
    }
}
