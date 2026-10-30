//
//  ATLOptions.swift
//  ATL
//
//  Created by Rene Hexel on 30/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//

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

/// Options that choose between the current behaviour of ATL processing and the
/// behaviour of swift-atl 0.6.
///
/// Each property selects one behaviour. The default options, also available as
/// ``standard``, give the current behaviour; ``legacy`` gives the behaviour of
/// swift-atl 0.6. APIs that existed in swift-atl 0.6 and take no options use
/// ``legacy``.
///
/// ```swift
/// let parser = ATLParser(options: .standard)
/// let module = try await parser.parse(url)
/// let xmi = try ATLXMISerializer(options: ATLOptions(collectionRangeEncoding: .portable))
///     .serialize(module)
/// ```
public struct ATLOptions: Sendable, Hashable {
    /// Whether ATL source may write integer ranges in collection literals.
    public var collectionRangeSyntax: ATLCollectionRangeSyntax

    /// How collection ranges are written to XMI.
    public var collectionRangeEncoding: ATLCollectionRangeEncoding

    /// Creates a set of options.
    ///
    /// - Parameters:
    ///   - collectionRangeSyntax: Whether ATL source may write integer ranges in collection literals.
    ///   - collectionRangeEncoding: How collection ranges are written to XMI.
    public init(
        collectionRangeSyntax: ATLCollectionRangeSyntax = .ocl,
        collectionRangeEncoding: ATLCollectionRangeEncoding = .collectionRange
    ) {
        self.collectionRangeSyntax = collectionRangeSyntax
        self.collectionRangeEncoding = collectionRangeEncoding
    }

    /// The current behaviour, which the default initialiser also gives.
    ///
    /// Collection literals accept OCL integer ranges, and ranges are written to XMI
    /// as OCL collection ranges.
    public static let standard = ATLOptions()

    /// The behaviour of swift-atl 0.6.
    ///
    /// Collection ranges are rejected as syntax errors, as swift-atl 0.6 rejected them.
    /// Ranges built in code are written to XMI as OCL collection ranges, because
    /// swift-atl 0.6 had no ranges that it could write.
    public static let legacy = ATLOptions(collectionRangeSyntax: .eclipse)
}
