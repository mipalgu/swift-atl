//
//  ATLLanguageConstants.swift
//  ATL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// The authoritative names of ATL language constructs.
///
/// Every keyword, directive, literal name and built-in type name that carries
/// meaning in the ATL syntax or in the evaluation of ATL expressions is defined
/// here exactly once, so that the lexer, the parser and the evaluator agree.
enum ATLLanguage {

    /// The header comment directives understood by the parser.
    ///
    /// A directive is a line comment whose text starts with the directive name,
    /// for example `-- @nsURI Ecore=http://www.eclipse.org/emf/2002/Ecore`.
    enum Directive {
        /// Binds a metamodel name to a file: `-- @path Name=/path/to/Name.ecore`.
        static let path = "@path"

        /// Binds a metamodel name to a registered namespace URI: `-- @nsURI Name=http://...`.
        static let namespaceURI = "@nsURI"

        /// Declares a module parameter: `-- @param name : Type = default`.
        static let parameter = "@param"
    }

    /// The names of the undefined literal.
    enum UndefinedLiteral {
        /// The standard OCL name of the undefined value.
        static let oclUndefined = "OclUndefined"

        /// The conventional alias for the undefined value.
        static let null = "null"
    }

    /// The prefix that introduces an enumeration literal, as in `#Editable`.
    static let enumerationLiteralPrefix: Character = "#"

    /// Infix keywords that are lexed as identifiers.
    enum InfixKeyword: String {
        case implies
        case xor
        case div
        case mod
    }

    /// The name of the pseudo-variable that gives access to module-level members.
    static let thisModule = "thisModule"

    /// The name of the implicit receiver variable in contextual helpers.
    static let selfVariable = "self"

    /// The qualifier separator between a metamodel name and a classifier name.
    static let metamodelSeparator: Character = "!"

    /// The primitive type names of the ATL type system.
    enum PrimitiveType: String, CaseIterable {
        case string = "String"
        case integer = "Integer"
        case boolean = "Boolean"
        case real = "Real"
    }

    /// The top type and the undefined type names.
    enum SpecialType {
        /// The supertype of every defined value.
        static let any = "OclAny"

        /// The type of the undefined value.
        static let undefined = "OclUndefined"

        /// The alternative name of the type of the undefined value.
        static let void = "OclVoid"

        /// The name of the abstract collection type.
        static let collection = "Collection"

        /// The name of the tuple type.
        static let tuple = "TupleType"
    }

    /// The escape sequences recognised inside string literals.
    enum StringEscape {
        /// The character that introduces an escape sequence.
        static let introducer: Character = "\\"

        /// The mapping from the character after the introducer to the decoded character.
        static let simple: [Character: Character] = [
            "n": "\n", "r": "\r", "t": "\t", "b": "\u{08}", "f": "\u{0C}",
            "'": "'", "\"": "\"", "\\": "\\",
        ]

        /// The character introducing a four-digit hexadecimal Unicode escape.
        static let unicode: Character = "u"
    }
}

/// The kinds of OCL collections that ATL distinguishes.
///
/// The kind decides whether a collection is ordered and whether it may hold
/// duplicate elements. Sequences and bags are represented by
/// `EcoreValueArray`; sets and ordered sets by ``ATLCollectionValue``.
public enum ATLCollectionKind: String, Sendable, CaseIterable, Hashable {
    /// An ordered collection that permits duplicates.
    case sequence = "Sequence"

    /// An ordered collection without duplicates.
    case orderedSet = "OrderedSet"

    /// An unordered collection without duplicates.
    case set = "Set"

    /// An unordered collection that permits duplicates.
    case bag = "Bag"

    /// Whether the collection rejects duplicate elements.
    public var isUnique: Bool {
        self == .set || self == .orderedSet
    }
}
