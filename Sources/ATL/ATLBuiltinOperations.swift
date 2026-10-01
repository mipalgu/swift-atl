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

    // Strings
    case concat, substring, toInteger, toReal, toUpper, toLower, toUpperCase, toLowerCase
    case toSequence, trim, startsWith, endsWith, split, replaceAll, regexReplaceAll

    // Numbers
    case abs, floor, round

    // Models
    case allInstances, allInstancesFrom
}

/// Evaluation of the built-in operations of the ATL and OCL standard libraries.
///
/// These operations are consulted before the generic OCL engine, because they
/// implement ATL semantics: collections keep their elements and order, the
/// undefined value is a legitimate result, single values convert implicitly to
/// one-element collections, and contextual helpers declared for a specific
/// type take precedence over built-in operations of the same name.
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
        return nil
    }

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
        default:
            return nil
        }
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
        guard receiver is Int || receiver is Double else { return nil }

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
        default:
            return nil
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
