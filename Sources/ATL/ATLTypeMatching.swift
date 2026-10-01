//
//  ATLTypeMatching.swift
//  ATL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation

/// Conformance of runtime values to ATL type names.
///
/// Type names appear in contextual helper declarations (`helper context Ecore!EClass def : ...`)
/// and as arguments of `oclIsKindOf`, `oclIsTypeOf` and `oclAsType`. A type name
/// may be qualified with a metamodel name (`MM!Class`) and may carry type
/// arguments (`Sequence(Integer)`); only the unqualified base name takes part
/// in matching.
enum ATLTypeMatching {

    /// The distance assigned to the top type `OclAny`, which is less specific than any other match.
    static let anyDistance = 1000

    /// Reduces a type name to its unqualified base name.
    ///
    /// - Parameter typeName: A type name such as `MM!Class` or `Sequence(Integer)`.
    /// - Returns: The base name, such as `Class` or `Sequence`.
    static func baseName(_ typeName: String) -> String {
        var name = Substring(typeName)
        if let parenthesis = name.firstIndex(of: "(") {
            name = name[..<parenthesis]
        }
        if let separator = name.lastIndex(of: ATLLanguage.metamodelSeparator) {
            name = name[name.index(after: separator)...]
        }
        return name.trimmingCharacters(in: .whitespaces)
    }

    /// Measures how far a value's type is from a named type.
    ///
    /// The distance is zero when the value's own type is the named type, grows by
    /// one for each step up the supertype hierarchy, and is ``anyDistance`` for
    /// `OclAny`. Contextual helper dispatch selects the smallest distance.
    ///
    /// - Parameters:
    ///   - value: The value, or `nil` for the undefined value.
    ///   - typeName: The (possibly qualified) type name.
    /// - Returns: The distance, or `nil` when the value does not conform to the type.
    static func distance(of value: (any EcoreValue)?, to typeName: String) -> Int? {
        let name = baseName(typeName)

        guard let value else {
            let undefinedNames = [ATLLanguage.SpecialType.undefined, ATLLanguage.SpecialType.void]
            return undefinedNames.contains(name) ? 0 : nil
        }
        if name == ATLLanguage.SpecialType.any { return anyDistance }

        if let object = value as? any EObject {
            guard let eClass = object.eClass as? EClass else { return nil }
            return classDistance(of: eClass, to: name)
        }
        return primitiveOrCollectionDistance(of: value, to: name)
    }

    /// Whether the value conforms to the named type, including through supertypes.
    ///
    /// - Parameters:
    ///   - value: The value to test.
    ///   - typeName: The (possibly qualified) type name.
    /// - Returns: `true` when the value is of the type or of a subtype.
    static func isKind(_ value: (any EcoreValue)?, of typeName: String) -> Bool {
        distance(of: value, to: typeName) != nil
    }

    /// Whether the value's own type is exactly the named type.
    ///
    /// - Parameters:
    ///   - value: The value to test.
    ///   - typeName: The (possibly qualified) type name.
    /// - Returns: `true` when the value's type, and no supertype, is the named type.
    static func isType(_ value: (any EcoreValue)?, of typeName: String) -> Bool {
        distance(of: value, to: typeName) == 0
    }

    /// The name of the type of a value, as reported by `oclType()` for non-model values.
    ///
    /// - Parameter value: The value to describe.
    /// - Returns: The ATL type name of the value.
    static func typeName(of value: (any EcoreValue)?) -> String {
        switch value {
        case nil: return ATLLanguage.SpecialType.undefined
        case is String: return ATLLanguage.PrimitiveType.string.rawValue
        case is Int: return ATLLanguage.PrimitiveType.integer.rawValue
        case is Double: return ATLLanguage.PrimitiveType.real.rawValue
        case is Bool: return ATLLanguage.PrimitiveType.boolean.rawValue
        case let collection? where ATLCollections.isCollection(collection):
            return ATLCollections.kind(of: collection)?.rawValue ?? ATLLanguage.SpecialType.collection
        case let object as any EObject: return (object.eClass as? EClass)?.name ?? ATLLanguage.SpecialType.any
        default: return ATLLanguage.SpecialType.any
        }
    }

    // MARK: - Private

    /// Breadth-first search up the supertype hierarchy.
    private static func classDistance(of eClass: EClass, to name: String) -> Int? {
        var level: [EClass] = [eClass]
        var visited: Set<String> = []
        var distance = 0
        while !level.isEmpty {
            if level.contains(where: { $0.name == name }) { return distance }
            var next: [EClass] = []
            for current in level where visited.insert(current.name).inserted {
                next.append(contentsOf: current.eSuperTypes)
            }
            level = next
            distance += 1
        }
        return nil
    }

    private static func primitiveOrCollectionDistance(of value: any EcoreValue, to name: String)
        -> Int?
    {
        typealias Primitive = ATLLanguage.PrimitiveType
        let collection = ATLLanguage.SpecialType.collection

        switch value {
        case is String:
            return name == Primitive.string.rawValue ? 0 : nil
        case is Bool:
            return name == Primitive.boolean.rawValue ? 0 : nil
        case is Int:
            if name == Primitive.integer.rawValue { return 0 }
            return name == Primitive.real.rawValue ? 1 : nil
        case is Double:
            return name == Primitive.real.rawValue ? 0 : nil
        default:
            guard let kind = ATLCollections.kind(of: value) else { return nil }
            if name == kind.rawValue { return 0 }
            return name == collection ? 1 : nil
        }
    }
}
