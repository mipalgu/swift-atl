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

        /// Every directive name.
        static let all = [path, namespaceURI, parameter]
    }

    /// The words that the lexer reads as keywords.
    static let keywords: Set<String> = [
        "module", "create", "from", "helper", "def", "context", "rule", "query",
        "if", "then", "else", "endif", "and", "or", "not", "true", "false",
        "let", "in", "do", "to", "self", "lazy",
        "Integer", "String", "Boolean", "Real",
    ]

    /// Words that the lexer reads as identifiers but that have a fixed meaning in a declaration.
    static let contextualKeywords: Set<String> = [
        ATLReservedNames.abstract, ATLReservedNames.unique, ATLReservedNames.entrypoint,
        ATLReservedNames.endpoint, ATLReservedNames.extends, ATLReservedNames.using,
        ATLReservedNames.forLoop,
        InfixKeyword.implies.rawValue, InfixKeyword.xor.rawValue, InfixKeyword.div.rawValue,
        InfixKeyword.mod.rawValue,
    ]

    /// The operators made of two characters, which the lexer must try before single characters.
    static let multiCharacterOperators: [String] = ["<>", "<=", "<-", ">=", "->"]

    /// Every operator, whether it is made of one or of several characters.
    static let operators: Set<String> = Set(multiCharacterOperators).union([
        "+", "-", "*", "/", "=", "<", ">", ".", ":", "!",
    ])

    /// The punctuation characters.
    static let punctuation: Set<String> = ["(", ")", "{", "}", "[", "]", ";", ",", "|"]

    /// The prefix that starts a line comment.
    static let lineCommentPrefix = "--"

    /// The character that opens and closes a string literal.
    static let stringDelimiter: Character = "'"

    /// The names of types that the lexical highlighter shows as type names.
    static let typeNames: Set<String> = Set(PrimitiveType.allCases.map(\.rawValue))
        .union(genericTypeNames)
        .union([
            SpecialType.any, SpecialType.undefined, SpecialType.void, SpecialType.tuple,
        ])

    /// Words of the full ATL language that this implementation does not support.
    ///
    /// Each is reported as an unsupported construct instead of being skipped or
    /// misread as something else.
    enum UnsupportedKeyword {
        /// Introduces a library, as in `library Helpers;`.
        static let library = "library"

        /// Imports a library, as in `uses Helpers;`.
        static let uses = "uses"

        /// Selects refining mode, as in `create OUT : M refining IN : M;`.
        static let refining = "refining"

        /// Marks a rule that is not applied by default.
        static let nodefault = "nodefault"

        /// Marks the elements created by an iterated target pattern as distinct.
        static let distinct = "distinct"

        /// Starts an iterated target pattern.
        static let foreach = "foreach"
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

    /// The name of the feature that names a model element.
    static let namePropertyName = "name"

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

    /// The names of types that take a type argument, as in `Sequence(Integer)`.
    static let genericTypeNames: Set<String> =
        Set(ATLCollectionKind.allCases.map(\.rawValue)).union([SpecialType.collection])

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
