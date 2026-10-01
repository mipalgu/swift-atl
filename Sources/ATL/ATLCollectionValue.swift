//
//  ATLCollectionValue.swift
//  ATL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// A set or ordered set value produced by ATL expressions.
///
/// ATL distinguishes four collection kinds. Sequences and bags are carried as
/// `EcoreValueArray`, which is also what model navigation produces. Sets and
/// ordered sets are carried by this type so that operations such as `union`,
/// `including` and `append` keep their elements unique. The elements keep the
/// order in which they were first added, and the wrapper is converted to an
/// `EcoreValueArray` whenever a value is stored into a model.
///
/// ## Example Usage
///
/// ```swift
/// let names = ATLCollectionValue(kind: .orderedSet, values: ["a", "b", "a"])
/// print(names.values.count)  // 2
/// ```
public struct ATLCollectionValue: EcoreValue, Sendable, Equatable, Hashable {

    /// The kind of this collection, either ``ATLCollectionKind/set`` or ``ATLCollectionKind/orderedSet``.
    public let kind: ATLCollectionKind

    /// The elements in insertion order, without duplicates for unique kinds.
    public let values: [any EcoreValue]

    /// Creates a collection of the given kind.
    ///
    /// Elements that are duplicates of earlier elements are dropped when the
    /// kind does not permit duplicates.
    ///
    /// - Parameters:
    ///   - kind: The collection kind.
    ///   - values: The elements to hold.
    public init(kind: ATLCollectionKind, values: [any EcoreValue]) {
        self.kind = kind
        self.values = kind.isUnique ? ATLValues.removingDuplicates(values) : values
    }

    /// The elements as an `EcoreValueArray`, suitable for storing into a model.
    public var asEcoreValueArray: EcoreValueArray {
        EcoreValueArray(values)
    }

    /// Compares two collections for equality.
    ///
    /// Sets are equal when they hold the same elements in any order; ordered
    /// sets are equal when they hold the same elements in the same order.
    public static func == (lhs: ATLCollectionValue, rhs: ATLCollectionValue) -> Bool {
        ATLValues.areEqual(lhs, rhs)
    }

    /// Hashes the number of elements, which is consistent with equality.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(values.count)
    }
}

/// Helpers for treating the different collection representations uniformly.
enum ATLCollections {

    /// Returns the elements of a value, converting single values to one-element collections.
    ///
    /// The undefined value yields an empty collection, which follows the OCL
    /// rule for implicit conversion of single values in collection operations.
    ///
    /// - Parameter value: The value to convert.
    /// - Returns: The elements of the value.
    static func elements(of value: (any EcoreValue)?) -> [any EcoreValue] {
        guard let value else { return [] }
        if let collection = value as? ATLCollectionValue { return collection.values }
        if let array = value as? EcoreValueArray { return array.values }
        if let anyArray = value as? [Any] {
            return anyArray.compactMap { $0 as? (any EcoreValue) }
        }
        return [value]
    }

    /// Whether the value is a collection rather than a single value.
    ///
    /// - Parameter value: The value to inspect.
    /// - Returns: `true` for sequences, bags, sets and ordered sets.
    static func isCollection(_ value: (any EcoreValue)?) -> Bool {
        value is ATLCollectionValue || value is EcoreValueArray || value is [Any]
    }

    /// The kind of a collection value.
    ///
    /// - Parameter value: The value to inspect.
    /// - Returns: The kind, or `nil` when the value is not a collection.
    static func kind(of value: (any EcoreValue)?) -> ATLCollectionKind? {
        if let collection = value as? ATLCollectionValue { return collection.kind }
        if value is EcoreValueArray || value is [Any] { return .sequence }
        return nil
    }

    /// Builds a collection value of the given kind.
    ///
    /// - Parameters:
    ///   - kind: The collection kind.
    ///   - values: The elements of the collection.
    /// - Returns: An `EcoreValueArray` for sequences and bags, an ``ATLCollectionValue`` otherwise.
    static func make(kind: ATLCollectionKind, _ values: [any EcoreValue]) -> any EcoreValue {
        switch kind {
        case .sequence, .bag:
            return EcoreValueArray(values)
        case .set, .orderedSet:
            return ATLCollectionValue(kind: kind, values: values)
        }
    }
}

/// Value comparison with ATL semantics.
enum ATLValues {

    /// Compares two possibly undefined values.
    ///
    /// Model objects are equal when their identifiers are equal, integers and
    /// reals compare numerically, and collections compare element-wise (without
    /// regard to order when both are unique collections).
    ///
    /// - Parameters:
    ///   - lhs: The first value.
    ///   - rhs: The second value.
    /// - Returns: `true` when the values are equal.
    static func areEqual(_ lhs: (any EcoreValue)?, _ rhs: (any EcoreValue)?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case (nil, _), (_, nil):
            return false
        case (let left?, let right?):
            return areEqualDefined(left, right)
        }
    }

    private static func areEqualDefined(_ left: any EcoreValue, _ right: any EcoreValue) -> Bool {
        if let l = left as? any EObject, let r = right as? any EObject {
            return l.id == r.id
        }
        if left is any EObject || right is any EObject {
            return false
        }
        if ATLCollections.isCollection(left) && ATLCollections.isCollection(right) {
            let l = ATLCollections.elements(of: left)
            let r = ATLCollections.elements(of: right)
            guard l.count == r.count else { return false }
            let bothUnique =
                (ATLCollections.kind(of: left)?.isUnique ?? false)
                && (ATLCollections.kind(of: right)?.isUnique ?? false)
            let isUnordered =
                bothUnique
                && (ATLCollections.kind(of: left) == .set || ATLCollections.kind(of: right) == .set)
            if isUnordered {
                return l.allSatisfy { element in r.contains { areEqualDefined(element, $0) } }
            }
            return zip(l, r).allSatisfy { areEqualDefined($0, $1) }
        }
        if let l = left as? Int, let r = right as? Double { return Double(l) == r }
        if let l = left as? Double, let r = right as? Int { return l == Double(r) }
        return EMFBase.areEqual(left, right)
    }

    /// Whether a collection of values contains an element equal to a candidate.
    ///
    /// - Parameters:
    ///   - values: The values to search.
    ///   - candidate: The value to look for.
    /// - Returns: `true` when an equal element exists.
    static func contains(_ values: [any EcoreValue], _ candidate: (any EcoreValue)?) -> Bool {
        values.contains { areEqual($0, candidate) }
    }

    /// Drops every value that equals an earlier value, keeping first occurrences.
    ///
    /// - Parameter values: The values to filter.
    /// - Returns: The values without duplicates, in their original order.
    static func removingDuplicates(_ values: [any EcoreValue]) -> [any EcoreValue] {
        var result: [any EcoreValue] = []
        result.reserveCapacity(values.count)
        for value in values where !contains(result, value) {
            result.append(value)
        }
        return result
    }

    /// Orders two defined values for sorting.
    ///
    /// Numbers order numerically, strings lexicographically, booleans with
    /// `false` first; other values order by their description.
    ///
    /// - Parameters:
    ///   - lhs: The first value.
    ///   - rhs: The second value.
    /// - Returns: `true` when `lhs` sorts before `rhs`.
    static func isOrderedBefore(_ lhs: (any EcoreValue)?, _ rhs: (any EcoreValue)?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil): return false
        case (nil, _): return true
        case (_, nil): return false
        case (let l as Int, let r as Int): return l < r
        case (let l as Double, let r as Double): return l < r
        case (let l as Int, let r as Double): return Double(l) < r
        case (let l as Double, let r as Int): return l < Double(r)
        case (let l as String, let r as String): return l < r
        case (let l as Bool, let r as Bool): return !l && r
        default: return String(describing: lhs!) < String(describing: rhs!)
        }
    }
}
