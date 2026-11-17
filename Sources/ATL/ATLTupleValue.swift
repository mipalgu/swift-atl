//
//  ATLTupleValue.swift
//  ATL
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// An OCL tuple value produced by ATL expressions.
///
/// A tuple literal such as `Tuple{name = 'a', size = 3}` evaluates to a tuple with one
/// named part per field. Its parts are read by name, as in `t.name`, and may be
/// undefined. Two tuples are equal when they have parts of the same names whose values
/// are equal, in whatever order the parts were written, as in OCL and Eclipse ATL. A
/// tuple whose parts are source elements identifies the match of a rule with several
/// source pattern elements that binds each element to the variable of the same name, as
/// `resolveTemp` and the bindings of references use it.
///
/// ## Example Usage
///
/// ```swift
/// let tuple = ATLTupleValue(parts: [("name", "a"), ("size", 3)])
/// print(tuple["size"] as? Int ?? 0)  // 3
/// ```
public struct ATLTupleValue: EcoreValue, Sendable, Equatable, Hashable {

    /// The parts of the tuple, in the order in which they were written.
    ///
    /// The value of a part is `nil` when the part is undefined.
    public let parts: [(name: String, value: (any EcoreValue)?)]

    /// Creates a tuple.
    ///
    /// A part whose name repeats that of an earlier part replaces the value of the
    /// earlier part, which keeps its position.
    ///
    /// - Parameter parts: The name and value of each part, `nil` for an undefined value.
    public init(parts: [(name: String, value: (any EcoreValue)?)]) {
        var unique: [(name: String, value: (any EcoreValue)?)] = []
        unique.reserveCapacity(parts.count)
        for part in parts {
            if let index = unique.firstIndex(where: { $0.name == part.name }) {
                unique[index].value = part.value
            } else {
                unique.append(part)
            }
        }
        self.parts = unique
    }

    /// The names of the parts, in the order in which they were written.
    public var names: [String] { parts.map(\.name) }

    /// Whether the tuple has a part of a name.
    ///
    /// - Parameter name: The name of the part.
    /// - Returns: `true` when the tuple has the part, even if its value is undefined.
    public func hasPart(_ name: String) -> Bool {
        parts.contains { $0.name == name }
    }

    /// The value of a part.
    ///
    /// - Parameter name: The name of the part.
    /// - Returns: The value, or `nil` when the part is undefined or the tuple has no part
    ///   of that name.
    public subscript(name: String) -> (any EcoreValue)? {
        parts.first { $0.name == name }?.value
    }

    /// Compares two tuples as OCL compares them.
    ///
    /// - Parameters:
    ///   - lhs: The first tuple.
    ///   - rhs: The second tuple.
    /// - Returns: `true` when the tuples have parts of the same names with equal values.
    public static func == (lhs: ATLTupleValue, rhs: ATLTupleValue) -> Bool {
        ATLValues.areEqual(lhs, rhs)
    }

    /// Hashes the names of the parts, which is consistent with equality.
    ///
    /// - Parameter hasher: The hasher to feed.
    public func hash(into hasher: inout Hasher) {
        hasher.combine(Set(names))
    }

    /// Whether another tuple has parts of the same names with equal values.
    ///
    /// - Parameter other: The other tuple.
    /// - Returns: `true` when the tuples are equal as OCL compares them.
    func hasSameParts(as other: ATLTupleValue) -> Bool {
        guard parts.count == other.parts.count else { return false }
        return parts.allSatisfy { part in
            other.hasPart(part.name) && ATLValues.areEqual(part.value, other[part.name])
        }
    }
}
