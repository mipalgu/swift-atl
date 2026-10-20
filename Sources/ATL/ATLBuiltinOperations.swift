//
//  ATLBuiltinOperations.swift
//  ATL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// The built-in operations that are evaluated without iterator variables.
///
/// The raw value is the operation name as written in ATL expressions.
enum ATLOperation: String {
    // Collections
    case count, sum, at, append, prepend, insertAt, subSequence, subOrderedSet
    case including, excluding, union, intersection, includes, excludes, includesAll, excludesAll
    case indexOf, lastIndexOf, asSet, asOrderedSet, asSequence, asBag
    case flatten, first, last, reverse
    case max, min
    case symmetricDifference, includingAll, includingRange, excludingAll

    // Strings
    case concat, substring, toInteger, toReal, toUpper, toLower, toUpperCase, toLowerCase
    case toSequence, trim, startsWith, endsWith, split, replaceAll, regexReplaceAll

    // Numbers
    case abs, floor, round, div, longValue
    case sqrt, exp, log, sin, cos, tan, asin, acos, atan, toDegrees, toRadians

    // Models
    case allInstances, allInstancesFrom
}

/// Evaluation of the built-in operations of the ATL and OCL standard libraries.
///
/// These operations are consulted before the generic OCL engine, because they
/// implement ATL semantics: collections keep their elements and order, the
/// undefined value is a legitimate result, single values convert implicitly to
/// one-element collections, and contextual helpers declared for a specific
/// type take precedence over built-in operations of the same name. Helpers
/// declared for `OclAny` take precedence over the reflective operations of
/// ``ATLReflectiveOperations``, which ATL defines for `OclAny` as well.
@MainActor
enum ATLBuiltinOperations {

    /// Evaluates an operation call.
    ///
    /// - Parameters:
    ///   - methodName: The operation name.
    ///   - receiver: The evaluated receiver, or `nil` for the undefined value.
    ///   - arguments: The evaluated arguments.
    ///   - context: The execution context.
    /// - Returns: The result, or `nil` when this type does not implement the operation.
    /// - Throws: ``ATLExecutionError`` when the receiver or the arguments are invalid.
    static func evaluate(
        methodName: String,
        receiver: (any EcoreValue)?,
        arguments: [(any EcoreValue)?],
        context: ATLExecutionContext
    ) async throws -> ATLBuiltinResult? {
        if let receiver,
            let helper = context.bestContextHelper(
                named: methodName, receiver: receiver, argumentCount: arguments.count,
                includingOclAny: false)
        {
            return ATLBuiltinResult(
                value: try await context.invokeContextHelper(
                    helper, receiver: receiver, arguments: arguments))
        }

        if let operation = ATLOperation(rawValue: methodName),
            let result = try await evaluate(
                operation, receiver: receiver, arguments: arguments, context: context)
        {
            return result
        }

        if let receiver,
            let helper = context.bestContextHelper(
                named: methodName, receiver: receiver, argumentCount: arguments.count,
                includingOclAny: true)
        {
            return ATLBuiltinResult(
                value: try await context.invokeContextHelper(
                    helper, receiver: receiver, arguments: arguments))
        }
        return try await ATLReflectiveOperations.evaluate(
            methodName: methodName, receiver: receiver, arguments: arguments, context: context)
    }

    /// The largest number of integers that `includingRange` adds in one call.
    ///
    /// A longer range is reported as an error rather than built, so that a
    /// transformation cannot exhaust the memory of the process with one call.
    nonisolated static let maximumRangeLength = 1_000_000

    // MARK: - Dispatch

    private static func evaluate(
        _ operation: ATLOperation,
        receiver: (any EcoreValue)?,
        arguments: [(any EcoreValue)?],
        context: ATLExecutionContext
    ) async throws -> ATLBuiltinResult? {
        if let text = receiver as? String,
            let result = try stringOperation(operation, text, arguments)
        {
            return result
        }
        if let result = try numberOperation(operation, receiver, arguments) {
            return result
        }
        switch operation {
        case .allInstances where arguments.isEmpty:
            return try await allInstances(of: receiver, context: context)
        case .allInstancesFrom where arguments.count == 1:
            return try await allInstances(of: receiver, from: arguments[0], context: context)
        default:
            return try collectionOperation(operation, receiver, arguments)
        }
    }

    private static func result(_ value: (any EcoreValue)?) -> ATLBuiltinResult {
        ATLBuiltinResult(value: value)
    }

    // MARK: - Collections

    /// Evaluates a collection operation without iterator variables.
    ///
    /// The result has the kind of the receiver, with one exception:
    /// `symmetricDifference` is a set operation, so on a Sequence or a Bag
    /// receiver it yields a Set (an ordered set receiver yields an ordered set).
    ///
    /// - Parameters:
    ///   - operation: The operation.
    ///   - receiver: The receiver; a single value acts as a one-element collection
    ///     and the undefined value as an empty one.
    ///   - arguments: The evaluated arguments.
    /// - Returns: The result, or `nil` when the operation does not take that many
    ///   arguments or does not apply to the receiver.
    /// - Throws: ``ATLExecutionError`` when an argument is invalid.
    private static func collectionOperation(
        _ operation: ATLOperation, _ receiver: (any EcoreValue)?, _ arguments: [(any EcoreValue)?]
    ) throws -> ATLBuiltinResult? {
        let items = ATLCollections.elements(of: receiver)
        let kind = ATLCollections.kind(of: receiver) ?? .sequence
        let isOrdered = kind == .sequence || kind == .orderedSet

        switch (operation, arguments.count) {
        case (.first, 0):
            return result(items.first)
        case (.last, 0):
            return result(items.last)
        case (.count, 1):
            return result(items.filter { ATLValues.areEqual($0, arguments[0]) }.count)
        case (.sum, 0):
            return result(try sum(items))
        case (.max, 0), (.min, 0):
            return result(try extreme(of: items, largest: operation == .max))
        case (.at, 1):
            guard isOrdered else { return nil }
            let index = try integer(arguments[0], operation)
            return result(items.indices.contains(index - 1) ? items[index - 1] : nil)
        case (.indexOf, 1):
            let position = items.firstIndex { ATLValues.areEqual($0, arguments[0]) }
            return result(position.map { $0 + 1 } ?? 0)
        case (.lastIndexOf, 1):
            let position = items.lastIndex { ATLValues.areEqual($0, arguments[0]) }
            return result(position.map { $0 + 1 } ?? 0)
        case (.append, 1):
            return result(ATLCollections.make(kind: kind, ordered(items, appending: arguments[0], kind)))
        case (.prepend, 1):
            return result(ATLCollections.make(kind: kind, ordered(items, prepending: arguments[0], kind)))
        case (.insertAt, 2):
            return result(try insert(items, at: arguments[0], element: arguments[1], kind: kind))
        case (.subSequence, 2), (.subOrderedSet, 2):
            return result(try slice(items, arguments[0], arguments[1], kind: kind))
        case (.including, 1):
            guard let element = arguments[0] else { return result(receiver) }
            if kind.isUnique && ATLValues.contains(items, element) { return result(receiver) }
            return result(ATLCollections.make(kind: kind, items + [element]))
        case (.excluding, 1):
            return result(
                ATLCollections.make(
                    kind: kind, items.filter { !ATLValues.areEqual($0, arguments[0]) }))
        case (.union, 1):
            return result(
                ATLCollections.make(kind: kind, items + ATLCollections.elements(of: arguments[0])))
        case (.intersection, 1):
            let other = ATLCollections.elements(of: arguments[0])
            return result(
                ATLCollections.make(kind: kind, items.filter { ATLValues.contains(other, $0) }))
        case (.includes, 1):
            return result(ATLValues.contains(items, arguments[0]))
        case (.excludes, 1):
            return result(!ATLValues.contains(items, arguments[0]))
        case (.includesAll, 1):
            return result(
                ATLCollections.elements(of: arguments[0]).allSatisfy { ATLValues.contains(items, $0) })
        case (.excludesAll, 1):
            return result(
                !ATLCollections.elements(of: arguments[0]).contains { ATLValues.contains(items, $0) })
        case (.asSet, 0):
            // A plain collection becomes a duplicate-free array, which is what model features store
            let deduplicated = ATLValues.removingDuplicates(items)
            return result(
                receiver is ATLCollectionValue
                    ? ATLCollectionValue(kind: .set, values: deduplicated)
                    : EcoreValueArray(deduplicated))
        case (.asOrderedSet, 0):
            return result(ATLCollections.make(kind: .orderedSet, items))
        case (.asSequence, 0):
            return result(ATLCollections.make(kind: .sequence, items))
        case (.asBag, 0):
            return result(ATLCollections.make(kind: .bag, items))
        case (.flatten, 0):
            return result(ATLCollections.make(kind: kind, flattened(items)))
        case (.reverse, 0):
            return result(ATLCollections.make(kind: kind, Array(items.reversed())))
        case (.symmetricDifference, 1):
            let other = ATLCollections.elements(of: arguments[0])
            let difference =
                items.filter { !ATLValues.contains(other, $0) }
                + other.filter { !ATLValues.contains(items, $0) }
            return result(
                ATLCollections.make(
                    kind: kind.isUnique ? kind : .set, ATLValues.removingDuplicates(difference)))
        case (.includingAll, 1):
            let additions = ATLCollections.elements(of: arguments[0])
            return result(ATLCollections.make(kind: kind, including(additions, in: items, kind)))
        case (.includingAll, 2):
            let additions = ATLCollections.elements(of: arguments[0])
            return result(try inserting(additions, into: items, at: arguments[1], kind: kind))
        case (.includingRange, 2):
            let range = try integerRange(arguments[0], arguments[1])
            return result(ATLCollections.make(kind: kind, including(range, in: items, kind)))
        case (.excludingAll, 1):
            let removals = ATLCollections.elements(of: arguments[0])
            return result(
                ATLCollections.make(kind: kind, items.filter { !ATLValues.contains(removals, $0) }))
        default:
            return nil
        }
    }

    /// Appends elements to the elements of a collection.
    ///
    /// A collection that permits duplicates receives every addition. A set or an
    /// ordered set receives only the additions it does not already hold, so that
    /// it stays free of duplicates and keeps the position of its existing elements.
    ///
    /// - Parameters:
    ///   - additions: The elements to append, in order.
    ///   - items: The elements of the receiving collection.
    ///   - kind: The kind of the receiving collection.
    /// - Returns: The elements of the extended collection.
    private static func including(
        _ additions: [any EcoreValue], in items: [any EcoreValue], _ kind: ATLCollectionKind
    ) -> [any EcoreValue] {
        guard kind.isUnique else { return items + additions }
        var result = items
        for element in additions where !ATLValues.contains(result, element) {
            result.append(element)
        }
        return result
    }

    /// Appends a range of integers to the elements of a collection.
    ///
    /// A set or an ordered set receives only the integers it does not already
    /// hold, compared numerically as ``ATLValues/areEqual(_:_:)`` compares them.
    ///
    /// - Parameters:
    ///   - range: The integers to append, in ascending order and without duplicates.
    ///   - items: The elements of the receiving collection.
    ///   - kind: The kind of the receiving collection.
    /// - Returns: The elements of the extended collection.
    private static func including(
        _ range: ClosedRange<Int>?, in items: [any EcoreValue], _ kind: ATLCollectionKind
    ) -> [any EcoreValue] {
        guard let range else { return items }
        guard kind.isUnique else { return items + range.map { $0 as any EcoreValue } }
        let held = Set(
            items.compactMap { item -> Int? in
                if let integer = item as? Int { return integer }
                return (item as? Double).flatMap { Int(exactly: $0) }
            })
        return items + range.filter { !held.contains($0) }.map { $0 as any EcoreValue }
    }

    /// The range of integers from a lower to an upper bound, both included.
    ///
    /// - Parameters:
    ///   - lower: The first integer of the range.
    ///   - upper: The last integer of the range.
    /// - Returns: The range, or `nil` when `upper` is less than `lower`.
    /// - Throws: ``ATLExecutionError`` when a bound is not an Integer or the range holds
    ///   more than ``maximumRangeLength`` integers.
    private static func integerRange(_ lower: (any EcoreValue)?, _ upper: (any EcoreValue)?) throws
        -> ClosedRange<Int>?
    {
        let low = try integer(lower, .includingRange)
        let high = try integer(upper, .includingRange)
        guard low <= high else { return nil }
        let (span, overflow) = high.subtractingReportingOverflow(low)
        guard !overflow, span < maximumRangeLength else {
            throw ATLExecutionError.runtimeError(
                "\(ATLOperation.includingRange.rawValue)(\(low), \(high)) would add more than \(maximumRangeLength) integers")
        }
        return low...high
    }

    /// Inserts elements into a collection at a one-based position.
    ///
    /// The elements are inserted in order before the element at `position`; the
    /// position after the last element appends them. A set or an ordered set
    /// receives only the additions it does not already hold.
    ///
    /// - Parameters:
    ///   - additions: The elements to insert, in order.
    ///   - items: The elements of the receiving collection.
    ///   - position: The one-based position of the first inserted element.
    ///   - kind: The kind of the receiving collection.
    /// - Returns: The extended collection, of the receiver's kind.
    /// - Throws: ``ATLExecutionError`` when the position is not an Integer within
    ///   `1...(items.count + 1)`.
    private static func inserting(
        _ additions: [any EcoreValue], into items: [any EcoreValue], at position: (any EcoreValue)?,
        kind: ATLCollectionKind
    ) throws -> any EcoreValue {
        let index = try integer(position, .includingAll)
        guard (1...(items.count + 1)).contains(index) else {
            throw ATLExecutionError.runtimeError(
                "includingAll() index \(index) is outside 1...\(items.count + 1)")
        }
        let inserted =
            kind.isUnique
            ? including(additions, in: [], kind).filter { !ATLValues.contains(items, $0) }
            : additions
        var result = items
        result.insert(contentsOf: inserted, at: index - 1)
        return ATLCollections.make(kind: kind, result)
    }

    private static func ordered(
        _ items: [any EcoreValue], appending element: (any EcoreValue)?, _ kind: ATLCollectionKind
    ) -> [any EcoreValue] {
        guard let element else { return items }
        let remaining =
            kind.isUnique ? items.filter { !ATLValues.areEqual($0, element) } : items
        return remaining + [element]
    }

    private static func ordered(
        _ items: [any EcoreValue], prepending element: (any EcoreValue)?, _ kind: ATLCollectionKind
    ) -> [any EcoreValue] {
        guard let element else { return items }
        let remaining =
            kind.isUnique ? items.filter { !ATLValues.areEqual($0, element) } : items
        return [element] + remaining
    }

    private static func insert(
        _ items: [any EcoreValue], at position: (any EcoreValue)?, element: (any EcoreValue)?,
        kind: ATLCollectionKind
    ) throws -> any EcoreValue {
        let index = try integer(position, .insertAt)
        guard (1...(items.count + 1)).contains(index) else {
            throw ATLExecutionError.runtimeError(
                "insertAt() index \(index) is outside 1...\(items.count + 1)")
        }
        guard let element else { return ATLCollections.make(kind: kind, items) }
        var result = kind.isUnique ? items.filter { !ATLValues.areEqual($0, element) } : items
        result.insert(element, at: min(index - 1, result.count))
        return ATLCollections.make(kind: kind, result)
    }

    private static func slice(
        _ items: [any EcoreValue], _ lower: (any EcoreValue)?, _ upper: (any EcoreValue)?,
        kind: ATLCollectionKind
    ) throws -> any EcoreValue {
        let low = try integer(lower, .subSequence)
        let high = try integer(upper, .subSequence)
        guard 1 <= low, low <= high, high <= items.count else {
            throw ATLExecutionError.runtimeError(
                "subSequence(\(low), \(high)) is outside the bounds 1...\(items.count)")
        }
        return ATLCollections.make(kind: kind, Array(items[(low - 1)..<high]))
    }

    private static func flattened(_ items: [any EcoreValue]) -> [any EcoreValue] {
        items.flatMap { item -> [any EcoreValue] in
            ATLCollections.isCollection(item) ? flattened(ATLCollections.elements(of: item)) : [item]
        }
    }

    private static func sum(_ items: [any EcoreValue]) throws -> any EcoreValue {
        var integerTotal = 0
        var realTotal = 0.0
        var isReal = false
        for item in items {
            switch item {
            case let value as Int:
                integerTotal += value
                realTotal += Double(value)
            case let value as Double:
                isReal = true
                realTotal += value
            default:
                throw ATLExecutionError.typeError("sum() requires numeric elements but found \(type(of: item))")
            }
        }
        return isReal ? realTotal : integerTotal
    }

    private static func extreme(of items: [any EcoreValue], largest: Bool) throws -> (any EcoreValue)? {
        guard !items.isEmpty else { return nil }
        for item in items where !(item is Int || item is Double) {
            throw ATLExecutionError.typeError("max() and min() require numeric elements but found \(type(of: item))")
        }
        return items.dropFirst().reduce(items[0]) { best, candidate in
            let candidateWins =
                largest
                ? ATLValues.isOrderedBefore(best, candidate)
                : ATLValues.isOrderedBefore(candidate, best)
            return candidateWins ? candidate : best
        }
    }

    private static func integer(_ value: (any EcoreValue)?, _ operation: ATLOperation) throws -> Int {
        guard let integer = value as? Int else {
            throw ATLExecutionError.typeError("\(operation.rawValue)() requires an Integer argument")
        }
        return integer
    }

    // MARK: - Numbers

    private static func numberOperation(
        _ operation: ATLOperation, _ receiver: (any EcoreValue)?, _ arguments: [(any EcoreValue)?]
    ) throws -> ATLBuiltinResult? {
        guard let real = (receiver as? Int).map(Double.init) ?? (receiver as? Double) else {
            return nil
        }

        switch (operation, arguments.count) {
        case (.abs, 0):
            if let value = receiver as? Int { return result(Swift.abs(value)) }
            return result(Swift.abs(receiver as! Double))
        case (.floor, 0):
            if let value = receiver as? Int { return result(value) }
            return result(Int((receiver as! Double).rounded(.down)))
        case (.round, 0):
            if let value = receiver as? Int { return result(value) }
            return result(Int((receiver as! Double).rounded(.toNearestOrAwayFromZero)))
        case (.max, 1), (.min, 1):
            guard arguments[0] is Int || arguments[0] is Double else {
                throw ATLExecutionError.typeError("\(operation.rawValue)() requires a numeric argument")
            }
            let receiverWins =
                operation == .max
                ? !ATLValues.isOrderedBefore(receiver, arguments[0])
                : ATLValues.isOrderedBefore(receiver, arguments[0])
            return result(receiverWins ? receiver : arguments[0])
        case (.div, 1):
            return result(try ATLOperatorSemantics.integerDivide(receiver, arguments[0]))
        case (.longValue, 0):
            if let value = receiver as? Int { return result(value) }
            return result(try truncated(real))
        default:
            guard arguments.isEmpty, let function = realFunction(operation) else { return nil }
            return result(function(real))
        }
    }

    /// Converts a real to an integer by discarding its fractional part.
    ///
    /// - Parameter value: The real to convert.
    /// - Returns: The integer part of `value`.
    /// - Throws: ``ATLExecutionError/runtimeError(_:)`` when `value` is not a number or
    ///   lies outside the range of Integer.
    private static func truncated(_ value: Double) throws -> Int {
        guard let integer = Int(exactly: value.rounded(.towardZero)) else {
            throw ATLExecutionError.runtimeError(
                "\(ATLOperation.longValue.rawValue)() cannot represent \(value) as an Integer")
        }
        return integer
    }

    /// The function computed by a Real operation of the ATL standard library.
    ///
    /// The functions follow the Java `Math` library that ATL builds on: `log` is the
    /// natural logarithm, the trigonometric functions use radians, and arguments
    /// outside a function's domain yield not-a-number.
    ///
    /// - Parameter operation: The operation.
    /// - Returns: The function, or `nil` when `operation` is not a Real function.
    private static func realFunction(_ operation: ATLOperation) -> ((Double) -> Double)? {
        switch operation {
        case .sqrt: return { $0.squareRoot() }
        case .exp: return { exp($0) }
        case .log: return { log($0) }
        case .sin: return { sin($0) }
        case .cos: return { cos($0) }
        case .tan: return { tan($0) }
        case .asin: return { asin($0) }
        case .acos: return { acos($0) }
        case .atan: return { atan($0) }
        case .toDegrees: return { $0 * 180 / .pi }
        case .toRadians: return { $0 * .pi / 180 }
        default: return nil
        }
    }

    // MARK: - Strings

    private static func stringOperation(
        _ operation: ATLOperation, _ text: String, _ arguments: [(any EcoreValue)?]
    ) throws -> ATLBuiltinResult? {
        switch (operation, arguments.count) {
        case (.concat, 1):
            return result(text + (try string(arguments[0], operation)))
        case (.substring, 1):
            let lower = try integer(arguments[0], operation)
            return result(try substring(text, lower, text.count))
        case (.substring, 2):
            return result(
                try substring(
                    text, try integer(arguments[0], operation), try integer(arguments[1], operation)))
        case (.toInteger, 0):
            return result(Int(text.trimmingCharacters(in: .whitespaces)))
        case (.toReal, 0):
            return result(Double(text.trimmingCharacters(in: .whitespaces)))
        case (.toUpper, 0), (.toUpperCase, 0):
            return result(text.uppercased())
        case (.toLower, 0), (.toLowerCase, 0):
            return result(text.lowercased())
        case (.toSequence, 0):
            return result(EcoreValueArray(text.map { String($0) }))
        case (.trim, 0):
            return result(text.trimmingCharacters(in: .whitespacesAndNewlines))
        case (.startsWith, 1):
            return result(text.hasPrefix(try string(arguments[0], operation)))
        case (.endsWith, 1):
            return result(text.hasSuffix(try string(arguments[0], operation)))
        case (.indexOf, 1):
            let needle = try string(arguments[0], operation)
            guard let range = text.range(of: needle) else { return result(0) }
            return result(text.distance(from: text.startIndex, to: range.lowerBound) + 1)
        case (.lastIndexOf, 1):
            let needle = try string(arguments[0], operation)
            guard let range = text.range(of: needle, options: .backwards) else { return result(0) }
            return result(text.distance(from: text.startIndex, to: range.lowerBound) + 1)
        case (.split, 1):
            return result(
                EcoreValueArray(try split(text, pattern: try string(arguments[0], operation))))
        case (.replaceAll, 2):
            let target = try string(arguments[0], operation)
            guard !target.isEmpty else { return result(text) }
            return result(
                text.replacingOccurrences(of: target, with: try string(arguments[1], operation)))
        case (.regexReplaceAll, 2):
            return result(
                try regexReplace(
                    text, pattern: try string(arguments[0], operation),
                    template: try string(arguments[1], operation)))
        case (.reverse, 0):
            return result(String(text.reversed()))
        default:
            return nil
        }
    }

    private static func string(_ value: (any EcoreValue)?, _ operation: ATLOperation) throws -> String {
        guard let string = value as? String else {
            throw ATLExecutionError.typeError("\(operation.rawValue)() requires a String argument")
        }
        return string
    }

    private static func substring(_ text: String, _ lower: Int, _ upper: Int) throws -> String {
        guard 1 <= lower, lower <= upper, upper <= text.count else {
            throw ATLExecutionError.runtimeError(
                "substring(\(lower), \(upper)) is outside the bounds 1...\(text.count)")
        }
        let start = text.index(text.startIndex, offsetBy: lower - 1)
        let end = text.index(text.startIndex, offsetBy: upper)
        return String(text[start..<end])
    }

    private static func expression(_ pattern: String) throws -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            throw ATLExecutionError.runtimeError("Invalid regular expression '\(pattern)'")
        }
    }

    private static func split(_ text: String, pattern: String) throws -> [String] {
        let expression = try expression(pattern)
        let matches = expression.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var pieces: [String] = []
        var segmentStart = text.startIndex
        for match in matches {
            guard let range = Range(match.range, in: text) else { continue }
            if range.isEmpty && range.lowerBound == text.startIndex { continue }
            pieces.append(String(text[segmentStart..<range.lowerBound]))
            segmentStart = range.upperBound
        }
        guard !pieces.isEmpty else { return [text] }
        pieces.append(String(text[segmentStart...]))
        while pieces.last?.isEmpty == true { pieces.removeLast() }
        return pieces
    }

    private static func regexReplace(_ text: String, pattern: String, template: String) throws
        -> String
    {
        try expression(pattern).stringByReplacingMatches(
            in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    // MARK: - Model queries

    private static func allInstances(of typeValue: (any EcoreValue)?, context: ATLExecutionContext)
        async throws -> ATLBuiltinResult
    {
        guard let typeName = typeValue as? String else {
            throw ATLExecutionError.typeError("allInstances() requires a type as its receiver")
        }
        let separator = ATLLanguage.metamodelSeparator
        let components = typeName.split(separator: separator, maxSplits: 1).map(String.init)
        let metamodelName = components.count == 2 ? components[0] : nil
        let className = components.last ?? typeName

        var aliases: [(alias: String, isSource: Bool)] = []
        if let metamodelName {
            if let source = context.module.sourceAlias(forMetamodel: metamodelName) {
                aliases.append((source, true))
            } else if let target = context.module.targetAlias(forMetamodel: metamodelName) {
                aliases.append((target, false))
            } else {
                throw ATLExecutionError.invalidOperation(
                    "No model found for metamodel '\(metamodelName)'")
            }
        } else {
            aliases =
                context.module.sourceMetamodels.keys.map { ($0, true) }
                + context.module.targetMetamodels.keys.map { ($0, false) }
        }
        return try await instances(className: className, in: aliases, context: context)
    }

    private static func allInstances(
        of typeValue: (any EcoreValue)?, from modelName: (any EcoreValue)?,
        context: ATLExecutionContext
    ) async throws -> ATLBuiltinResult {
        guard let typeName = typeValue as? String else {
            throw ATLExecutionError.typeError("allInstancesFrom() requires a type as its receiver")
        }
        guard let alias = modelName as? String else {
            throw ATLExecutionError.typeError("allInstancesFrom() requires a model name")
        }
        let isSource = context.module.sourceMetamodels[alias] != nil
        guard isSource || context.module.targetMetamodels[alias] != nil else {
            throw ATLExecutionError.invalidOperation("Model '\(alias)' is not declared by the module")
        }
        let className = typeName.split(separator: ATLLanguage.metamodelSeparator).last.map(String.init) ?? typeName
        return try await instances(className: className, in: [(alias, isSource)], context: context)
    }

    private static func instances(
        className: String, in aliases: [(alias: String, isSource: Bool)],
        context: ATLExecutionContext
    ) async throws -> ATLBuiltinResult {
        var found: [any EcoreValue] = []
        var classFound = false
        for (alias, isSource) in aliases {
            let package =
                isSource
                ? context.module.sourceMetamodels[alias] : context.module.targetMetamodels[alias]
            guard let eClass = package?.getClassifier(className) as? EClass else { continue }
            classFound = true
            let resource = isSource ? context.getSource(alias) : context.getTarget(alias)
            guard let resource else { continue }
            found.append(contentsOf: await resource.getAllInstancesOf(eClass).map { $0 as any EcoreValue })
        }
        guard classFound else {
            throw ATLExecutionError.typeError("Class '\(className)' not found in the metamodels of the module")
        }
        return result(EcoreValueArray(found))
    }
}

/// Operations that take iterator variables, such as `select(e | ...)`.
enum ATLLambdaOperation: String {
    case select, reject, collect, exists, forAll, one, any, isUnique, sortedBy
}

/// Evaluation of the iterator operations of the OCL collection library.
///
/// The receiver may be any collection; a single value is treated as a collection
/// of one element and the undefined value as an empty collection.
@MainActor
enum ATLLambdaOperations {

    /// Evaluates an iterator operation.
    ///
    /// - Parameters:
    ///   - methodName: The operation name.
    ///   - receiver: The evaluated receiver.
    ///   - lambda: The iterator expression, with one variable (two or more for `exists` and `forAll`).
    ///   - context: The execution context.
    /// - Returns: The result, or `nil` when `methodName` is not an iterator operation.
    /// - Throws: ``ATLExecutionError`` when evaluating the iterator body fails.
    static func evaluate(
        methodName: String, receiver: (any EcoreValue)?, lambda: ATLLambdaExpression,
        context: ATLExecutionContext
    ) async throws -> ATLBuiltinResult? {
        guard let operation = ATLLambdaOperation(rawValue: methodName) else { return nil }
        let items = ATLCollections.elements(of: receiver)
        let kind = ATLCollections.kind(of: receiver) ?? .sequence

        switch operation {
        case .exists, .forAll:
            let wantsAny = operation == .exists
            return ATLBuiltinResult(
                value: try await quantify(items, lambda, wantsAny: wantsAny, context: context))
        case .select, .reject:
            let keep = operation == .select
            var selected: [any EcoreValue] = []
            for item in items {
                if try await holds(lambda, [item], context) == keep { selected.append(item) }
            }
            return ATLBuiltinResult(value: ATLCollections.make(kind: kind, selected))
        case .collect:
            var collected: [any EcoreValue] = []
            for item in items {
                guard let value = try await lambda.evaluate(binding: [item], in: context) else {
                    continue
                }
                collected.append(contentsOf: ATLCollections.isCollection(value) ? ATLCollections.elements(of: value) : [value])
            }
            let collectedKind: ATLCollectionKind = (kind == .set || kind == .bag) ? .bag : .sequence
            return ATLBuiltinResult(value: ATLCollections.make(kind: collectedKind, collected))
        case .one:
            var matches = 0
            for item in items {
                if try await holds(lambda, [item], context) { matches += 1 }
            }
            return ATLBuiltinResult(value: matches == 1)
        case .any:
            for item in items {
                if try await holds(lambda, [item], context) { return ATLBuiltinResult(value: item) }
            }
            return ATLBuiltinResult(value: nil)
        case .isUnique:
            var keys: [(any EcoreValue)?] = []
            for item in items {
                let key = try await lambda.evaluate(binding: [item], in: context)
                if keys.contains(where: { ATLValues.areEqual($0, key) }) {
                    return ATLBuiltinResult(value: false)
                }
                keys.append(key)
            }
            return ATLBuiltinResult(value: true)
        case .sortedBy:
            var keyed: [(item: any EcoreValue, key: (any EcoreValue)?, position: Int)] = []
            for (position, item) in items.enumerated() {
                keyed.append((item, try await lambda.evaluate(binding: [item], in: context), position))
            }
            keyed.sort {
                if ATLValues.isOrderedBefore($0.key, $1.key) { return true }
                if ATLValues.isOrderedBefore($1.key, $0.key) { return false }
                return $0.position < $1.position
            }
            let sortedKind: ATLCollectionKind = kind.isUnique ? .orderedSet : .sequence
            return ATLBuiltinResult(value: ATLCollections.make(kind: sortedKind, keyed.map(\.item)))
        }
    }

    private static func holds(
        _ lambda: ATLLambdaExpression, _ values: [any EcoreValue], _ context: ATLExecutionContext
    ) async throws -> Bool {
        (try await lambda.evaluate(binding: values, in: context) as? Bool) == true
    }

    /// Evaluates `exists` or `forAll` over the cartesian product of the iterator variables.
    private static func quantify(
        _ items: [any EcoreValue], _ lambda: ATLLambdaExpression, wantsAny: Bool,
        context: ATLExecutionContext
    ) async throws -> Bool {
        var tuples: [[any EcoreValue]] = [[]]
        for _ in lambda.parameters {
            tuples = tuples.flatMap { prefix in items.map { prefix + [$0] } }
        }
        for tuple in tuples {
            let satisfied = try await holds(lambda, tuple, context)
            if wantsAny && satisfied { return true }
            if !wantsAny && !satisfied { return false }
        }
        return !wantsAny
    }
}

extension ATLLambdaExpression {

    /// Evaluates the body with the iterator variables bound to values.
    ///
    /// - Parameters:
    ///   - values: One value per iterator variable, in declaration order.
    ///   - context: The execution context.
    /// - Returns: The value of the body.
    /// - Throws: ``ATLExecutionError`` when the body fails.
    @MainActor
    func evaluate(binding values: [any EcoreValue], in context: ATLExecutionContext) async throws
        -> (any EcoreValue)?
    {
        context.pushScope()
        defer { context.popScope() }
        for (name, value) in zip(parameters, values) {
            context.setVariable(name, value: value)
        }
        return try await body.evaluate(in: context)
    }
}

/// Operations that take type names as arguments: `oclIsKindOf`, `oclIsTypeOf`, `oclAsType` and `oclType`.
@MainActor
enum ATLTypeOperations {

    /// Evaluates a type operation.
    ///
    /// - Parameters:
    ///   - methodName: The operation name.
    ///   - receiver: The evaluated receiver.
    ///   - arguments: The unevaluated argument expressions; a type is written as `MM!Class`,
    ///     as a primitive type name or as a bare class name.
    ///   - context: The execution context.
    /// - Returns: The result, or `nil` when `methodName` is not a type operation.
    /// - Throws: ``ATLExecutionError`` when the argument is not a type or a cast fails.
    static func evaluate(
        methodName: String, receiver: (any EcoreValue)?, arguments: [any ATLExpression],
        context: ATLExecutionContext
    ) async throws -> ATLBuiltinResult? {
        switch (methodName, arguments.count) {
        case ("oclIsKindOf", 1):
            let name = try await typeName(arguments[0], context)
            return ATLBuiltinResult(value: ATLTypeMatching.isKind(receiver, of: name))
        case ("oclIsTypeOf", 1):
            let name = try await typeName(arguments[0], context)
            return ATLBuiltinResult(value: ATLTypeMatching.isType(receiver, of: name))
        case ("oclAsType", 1):
            let name = try await typeName(arguments[0], context)
            return ATLBuiltinResult(value: try cast(receiver, to: name))
        case ("oclType", 0):
            return ATLBuiltinResult(value: modelType(of: receiver))
        default:
            return nil
        }
    }

    private static func typeName(_ expression: any ATLExpression, _ context: ATLExecutionContext)
        async throws -> String
    {
        switch expression {
        case let literal as ATLTypeLiteralExpression:
            return literal.typeName
        case let literal as ATLLiteralExpression where literal.value == nil:
            return ATLLanguage.SpecialType.undefined
        case let variable as ATLVariableExpression:
            if let bound = (try? context.getVariable(variable.name)) as? String { return bound }
            return variable.name
        default:
            guard let name = try await expression.evaluate(in: context) as? String else {
                throw ATLExecutionError.typeError("Expected a type name as argument")
            }
            return name
        }
    }

    private static func cast(_ value: (any EcoreValue)?, to typeName: String) throws
        -> (any EcoreValue)?
    {
        guard let value else { return nil }
        if let integer = value as? Int,
            ATLTypeMatching.baseName(typeName) == ATLLanguage.PrimitiveType.real.rawValue
        {
            return Double(integer)
        }
        guard ATLTypeMatching.isKind(value, of: typeName) else {
            throw ATLExecutionError.typeError(
                "Cannot cast a value of type '\(ATLTypeMatching.typeName(of: value))' to '\(typeName)'")
        }
        return value
    }

    private static func modelType(of value: (any EcoreValue)?) -> any EcoreValue {
        if let object = value as? any EObject, let eClass = object.eClass as? EClass {
            return eClass
        }
        return ATLTypeMatching.typeName(of: value)
    }
}

/// The reflective, console and creation operations of the ATL standard library.
///
/// The raw value is the operation name as written in ATL expressions.
enum ATLReflectiveOperation: String {
    /// `refImmediateComposite()`: the element that directly contains the receiver.
    case refImmediateComposite

    /// `refGetValue(name)`: the value of the named feature of the receiver.
    case refGetValue

    /// `refSetValue(name, value)`: sets the named feature of a target element.
    case refSetValue

    /// `refUnsetValue(name)`: resets the named feature of a target element.
    case refUnsetValue

    /// `refInvokeOperation(name, arguments)`: calls the named helper on the receiver.
    case refInvokeOperation

    /// `debug(message)`: writes the message and the receiver to standard error.
    case debug

    /// `println()`: writes a string to standard output.
    case println

    /// `MM!Class.newInstance()`: creates an element in a target model.
    case newInstance
}

/// The destinations of the text written by the console operations of a transformation.
///
/// `debug` writes to the error destination and `println` to the output destination,
/// so that diagnostic text never mixes with text a transformation generates.
struct ATLConsole {
    /// Writes one line of text to the output destination.
    let writeOutput: @MainActor (String) -> Void

    /// Writes one line of text to the error destination.
    let writeError: @MainActor (String) -> Void

    /// The console that writes to the standard output and standard error of the process.
    static var system: ATLConsole { writing(errorsTo: .standardError) }

    /// A console that prints output lines and writes error lines to a file handle.
    ///
    /// Output lines are printed, so that they keep their order with other text the
    /// process prints. A line that cannot be written to the error destination, for
    /// example because it has been closed, is dropped.
    ///
    /// - Parameter errors: The destination of the error lines.
    /// - Returns: The console.
    static func writing(errorsTo errors: FileHandle) -> ATLConsole {
        ATLConsole(
            writeOutput: { print($0) },
            writeError: { try? errors.write(contentsOf: Data(($0 + "\n").utf8)) })
    }
}

/// Evaluation of the reflective operations that ATL defines for every value.
///
/// These operations read and change model elements by feature name, navigate
/// the containment structure, invoke helpers by name, write to the console and
/// create target elements. Writing operations apply only to target elements,
/// because source models are read-only in ATL.
@MainActor
enum ATLReflectiveOperations {

    /// Evaluates a reflective operation.
    ///
    /// The method forms `eContainer()`, `eContainingFeature()`, `eContents()` and
    /// `eAllContents()` of the containment properties are evaluated here as well.
    ///
    /// - Parameters:
    ///   - methodName: The operation name.
    ///   - receiver: The evaluated receiver, or `nil` for the undefined value.
    ///   - arguments: The evaluated arguments.
    ///   - context: The execution context.
    /// - Returns: The result, or `nil` when the operation does not apply to the receiver
    ///   and the number of arguments.
    /// - Throws: ``ATLExecutionError`` when an argument has the wrong type, a source
    ///   element would be changed, or the operation itself fails.
    static func evaluate(
        methodName: String,
        receiver: (any EcoreValue)?,
        arguments: [(any EcoreValue)?],
        context: ATLExecutionContext
    ) async throws -> ATLBuiltinResult? {
        if arguments.isEmpty, let property = EObjectNavigationProperty(rawValue: methodName),
            let object = receiver as? any EObject
        {
            return result(try await context.navigate(from: object, property: property.rawValue))
        }
        guard let operation = ATLReflectiveOperation(rawValue: methodName) else { return nil }

        switch (operation, arguments.count) {
        case (.debug, 1):
            let message = try string(arguments[0], operation)
            context.console.writeError("\(message): \(render(receiver))")
            return result(receiver)
        case (.println, 0):
            guard let text = receiver as? String else { return nil }
            context.console.writeOutput(text)
            return result(text)
        case (.newInstance, 0):
            guard let typeName = receiver as? String else { return nil }
            return result(try await newInstance(of: typeName, context: context))
        case (.refInvokeOperation, 2):
            guard let receiver else { return nil }
            let name = try string(arguments[0], operation)
            return result(
                try await invoke(
                    name, on: receiver, arguments: ATLCollections.elements(of: arguments[1]),
                    context: context))
        default:
            break
        }

        guard let object = receiver as? any EObject else { return nil }
        switch (operation, arguments.count) {
        case (.refImmediateComposite, 0):
            return result(
                try await context.navigate(
                    from: object, property: EObjectNavigationProperty.eContainer.rawValue))
        case (.refGetValue, 1):
            let name = try string(arguments[0], operation)
            return result(try await context.navigate(from: object, property: name))
        case (.refSetValue, 2):
            let name = try string(arguments[0], operation)
            let target = try await writableTarget(object, feature: name, operation, context)
            try await context.assignFeature(on: target, feature: name, value: arguments[1])
            return result(object)
        case (.refUnsetValue, 1):
            let name = try string(arguments[0], operation)
            let target = try await writableTarget(object, feature: name, operation, context)
            try await context.assignFeature(
                on: target, feature: name, value: unsetValue(of: name, in: target))
            return result(object)
        default:
            return nil
        }
    }

    /// Renders a value as the console operations write it.
    ///
    /// Strings are quoted, the undefined value is written as `OclUndefined`,
    /// collections are written as collection literals such as `Sequence{1, 2}`,
    /// and model elements by their class followed by their quoted name, if they
    /// have one.
    ///
    /// - Parameter value: The value to render, or `nil` for the undefined value.
    /// - Returns: The text that represents the value.
    static func render(_ value: (any EcoreValue)?) -> String {
        let quote = ATLLanguage.stringDelimiter
        if let kind = ATLCollections.kind(of: value) {
            let elements = ATLCollections.elements(of: value).map { render($0) }
            return "\(kind.rawValue){\(elements.joined(separator: ", "))}"
        }
        switch value {
        case nil:
            return ATLLanguage.UndefinedLiteral.oclUndefined
        case let text as String:
            return "\(quote)\(text)\(quote)"
        case let object as any EObject:
            let classifier: any EClassifier = object.eClass
            guard let name = elementName(of: object) else { return classifier.name }
            return "\(classifier.name) \(quote)\(name)\(quote)"
        case let value?:
            return "\(value)"
        }
    }

    // MARK: - Implementation

    /// Wraps the value of an operation that applies.
    ///
    /// - Parameter value: The value, or `nil` for the undefined value.
    /// - Returns: The result that marks the operation as evaluated.
    private static func result(_ value: (any EcoreValue)?) -> ATLBuiltinResult {
        ATLBuiltinResult(value: value)
    }

    /// The String value of an argument.
    ///
    /// - Parameters:
    ///   - value: The argument.
    ///   - operation: The operation the argument is passed to.
    /// - Returns: The string.
    /// - Throws: ``ATLExecutionError/typeError(_:)`` when the argument is not a String.
    private static func string(_ value: (any EcoreValue)?, _ operation: ATLReflectiveOperation)
        throws -> String
    {
        guard let string = value as? String else {
            throw ATLExecutionError.typeError("\(operation.rawValue)() requires a String argument")
        }
        return string
    }

    /// The name of a model element, if it has one.
    ///
    /// - Parameter object: The model element.
    /// - Returns: The value of its name feature, or `nil` when it has none.
    private static func elementName(of object: any EObject) -> String? {
        if let named = object as? any ENamedElement { return named.name }
        return (object as? DynamicEObject)?.eGet(ATLLanguage.namePropertyName) as? String
    }

    /// The current state of a target element that an operation is about to change.
    ///
    /// - Parameters:
    ///   - object: The element to change.
    ///   - feature: The name of the feature to change.
    ///   - operation: The changing operation.
    ///   - context: The execution context.
    /// - Returns: The element as currently held by its target model.
    /// - Throws: ``ATLExecutionError/invalidOperation(_:)`` when the element is not part
    ///   of a target model, as source models are read-only.
    private static func writableTarget(
        _ object: any EObject, feature: String, _ operation: ATLReflectiveOperation,
        _ context: ATLExecutionContext
    ) async throws -> any EObject {
        guard let target = await context.findTargetObject(object.id) else {
            throw ATLExecutionError.invalidOperation(
                "\(operation.rawValue)() cannot change '\(feature)': the element is not part of a target model, and source models are read-only"
            )
        }
        return target
    }

    /// The value that resets a feature of an element.
    ///
    /// A many-valued feature is reset to an empty collection. A single-valued
    /// attribute is reset to its default value or, without one, to the default of
    /// its type, such as zero or `false`; any other feature is reset to the
    /// undefined value.
    ///
    /// - Parameters:
    ///   - name: The feature name.
    ///   - object: The element that owns the feature.
    /// - Returns: The resetting value, or `nil` when the element has no such feature.
    private static func unsetValue(of name: String, in object: any EObject) -> (any EcoreValue)? {
        let classifier: any EClassifier = object.eClass
        guard let feature = (classifier as? EClass)?.getStructuralFeature(name: name) else {
            return nil
        }
        return EcoreDefaultValue.value(for: feature)
    }

    /// Calls a helper by name on a receiver.
    ///
    /// The contextual helper whose context type is closest to the receiver's type
    /// is preferred, including one declared for `OclAny`. Otherwise a context-free
    /// helper of that name is called with `self` bound to the receiver.
    ///
    /// - Parameters:
    ///   - name: The helper name.
    ///   - receiver: The receiver value.
    ///   - arguments: The arguments of the helper.
    ///   - context: The execution context.
    /// - Returns: The value of the helper.
    /// - Throws: ``ATLExecutionError/helperNotFound(_:)`` when no helper of that name
    ///   applies, or the error of the helper body.
    private static func invoke(
        _ name: String, on receiver: any EcoreValue, arguments: [any EcoreValue],
        context: ATLExecutionContext
    ) async throws -> (any EcoreValue)? {
        let values = arguments.map { Optional($0) }
        if let helper = context.bestContextHelper(
            named: name, receiver: receiver, argumentCount: values.count, includingOclAny: true)
        {
            return try await context.invokeContextHelper(helper, receiver: receiver, arguments: values)
        }
        guard context.globalHelper(named: name) != nil else {
            throw ATLExecutionError.helperNotFound(name)
        }
        context.pushScope()
        defer { context.popScope() }
        context.setVariable(ATLLanguage.selfVariable, value: receiver)
        return try await context.callHelper(name, arguments: values)
    }

    /// Creates an element of a qualified class in the target model of its metamodel.
    ///
    /// When several target models share the metamodel, the element is created in
    /// the first of them, which is the default target model of that metamodel.
    ///
    /// - Parameters:
    ///   - typeName: The class qualified by its metamodel, such as `MM!Class`.
    ///   - context: The execution context.
    /// - Returns: The created element.
    /// - Throws: ``ATLExecutionError`` when the type is not qualified, its metamodel is
    ///   not the metamodel of a target model, or the class does not exist.
    private static func newInstance(of typeName: String, context: ATLExecutionContext)
        async throws -> any EObject
    {
        let components = typeName.split(separator: ATLLanguage.metamodelSeparator, maxSplits: 1)
        guard components.count == 2 else {
            throw ATLExecutionError.typeError(
                "\(ATLReflectiveOperation.newInstance.rawValue)() requires a class qualified by its metamodel, such as MM\(ATLLanguage.metamodelSeparator)Class, but found '\(typeName)'"
            )
        }
        return try await context.createElement(type: typeName, in: String(components[0]))
    }
}
