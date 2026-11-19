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
/// in matching. A tuple conforms to `TupleType(...)`, whatever its parts, and to `Tuple`,
/// the name of its type.
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
    /// `OclAny`. Ecore's `EObject` is a supertype of every model object, one step beyond
    /// its most distant other supertype. Contextual helper dispatch selects the smallest
    /// distance.
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
        case is ATLTupleValue: return ATLLanguage.tupleLiteral
        case let object as any EObject: return (object.eClass as? EClass)?.name ?? ATLLanguage.SpecialType.any
        default: return ATLLanguage.SpecialType.any
        }
    }

    /// Whether instances of a class are instances of another class.
    ///
    /// A class conforms to itself, to each of its supertypes and to Ecore's `EObject`.
    /// As ATL names types by metamodel and class name, a class also conforms to a class
    /// that has the name of the class or of one of its supertypes.
    ///
    /// - Parameters:
    ///   - eClass: The class to test, such as the class of a source element.
    ///   - type: The class to test against, such as the type of a source pattern.
    /// - Returns: `true` when instances of `eClass` are instances of `type`.
    static func conforms(_ eClass: EClass, to type: EClass) -> Bool {
        eClass.conforms(to: type) || eClass.name == type.name
            || eClass.allSuperTypes.contains { $0.name == type.name }
    }

    /// The instances of a class in a model, in document order.
    ///
    /// - Parameters:
    ///   - type: The class whose instances to list.
    ///   - resource: The model to search.
    /// - Returns: The objects of `resource` whose class conforms to `type`.
    static func instances(of type: EClass, in resource: Resource) async -> [any EObject] {
        await resource.getAllObjectsIncludingContents().filter { object in
            (object.eClass as? EClass).map { conforms($0, to: type) } ?? false
        }
    }

    // MARK: - Private

    /// Breadth-first search up the supertype hierarchy.
    ///
    /// `EObject` lies one level beyond the most distant other supertype, so that every
    /// other supertype is nearer.
    private static func classDistance(of eClass: EClass, to name: String) -> Int? {
        let toEObject = name == EcoreClassifier.eObject.rawValue
        if eClass.isEObject { return toEObject ? 0 : nil }
        var level: [EClass] = [eClass]
        var visited: Set<String> = []
        var distance = 0
        while !level.isEmpty {
            if !toEObject, level.contains(where: { $0.name == name }) { return distance }
            var next: [EClass] = []
            for current in level where visited.insert(current.name).inserted {
                next.append(contentsOf: current.eSuperTypes.filter { !$0.isEObject })
            }
            level = next
            distance += 1
        }
        return toEObject ? min(distance, anyDistance - 1) : nil
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
        case is ATLTupleValue:
            return name == ATLLanguage.tupleLiteral || name == ATLLanguage.SpecialType.tuple ? 0 : nil
        default:
            guard let kind = ATLCollections.kind(of: value) else { return nil }
            if name == kind.rawValue { return 0 }
            return name == collection ? 1 : nil
        }
    }
}
