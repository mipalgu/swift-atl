//
//  ATLSourceSupport.swift
//  ATL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// Decoding of escape sequences inside ATL string literals.
enum ATLStringEscapes {

    /// Decodes the escape sequences in the raw text between a literal's quotes.
    ///
    /// Recognised sequences are the single-character escapes of
    /// ``ATLLanguage/StringEscape/simple``, `\uXXXX` with four hexadecimal
    /// digits, and octal escapes of up to three digits. A backslash followed
    /// by any other character is kept as it was written, so that regular
    /// expressions such as `\s+` survive unchanged.
    ///
    /// - Parameter raw: The text between the quotes, with escapes still encoded.
    /// - Returns: The decoded string value.
    static func decode(_ raw: String) -> String {
        guard raw.contains(ATLLanguage.StringEscape.introducer) else { return raw }

        var result = ""
        let characters = Array(raw)
        var index = 0
        while index < characters.count {
            let character = characters[index]
            guard character == ATLLanguage.StringEscape.introducer, index + 1 < characters.count
            else {
                result.append(character)
                index += 1
                continue
            }

            let escaped = characters[index + 1]
            if let simple = ATLLanguage.StringEscape.simple[escaped] {
                result.append(simple)
                index += 2
            } else if escaped == ATLLanguage.StringEscape.unicode,
                index + 5 < characters.count,
                let scalar = unicodeScalar(hex: characters[(index + 2)...(index + 5)])
            {
                result.unicodeScalars.append(scalar)
                index += 6
            } else if let (scalar, length) = octalScalar(characters, from: index + 1) {
                result.unicodeScalars.append(scalar)
                index += 1 + length
            } else {
                result.append(character)
                result.append(escaped)
                index += 2
            }
        }
        return result
    }

    private static func unicodeScalar(hex digits: ArraySlice<Character>) -> Unicode.Scalar? {
        guard digits.count == 4, let value = UInt32(String(digits), radix: 16) else { return nil }
        return Unicode.Scalar(value)
    }

    private static func octalScalar(_ characters: [Character], from start: Int)
        -> (Unicode.Scalar, Int)?
    {
        guard let first = characters[start].wholeNumberValue, (0...7).contains(first) else {
            return nil
        }
        let maximumLength = first <= 3 ? 3 : 2
        var value = 0
        var length = 0
        while length < maximumLength, start + length < characters.count,
            let digit = characters[start + length].wholeNumberValue, (0...7).contains(digit)
        {
            value = value * 8 + digit
            length += 1
        }
        guard let scalar = Unicode.Scalar(UInt32(value)) else { return nil }
        return (scalar, length)
    }
}

/// The header directives collected from comments while lexing.
///
/// Directives are comments of the form `-- @path`, `-- @nsURI` and `-- @param`.
/// Malformed directives are reported through ``errors`` so that the parser can
/// fail with a clear message instead of ignoring them.
struct ATLDirectives {

    /// Metamodel names bound to file paths.
    var paths: [String: String] = [:]

    /// Metamodel names bound to namespace URIs.
    var namespaceURIs: [String: String] = [:]

    /// The declared module parameters in declaration order.
    var parameters: [ATLModuleParameter] = []

    /// Descriptions of malformed directives.
    var errors: [String] = []

    /// Records the directive in a comment, if the comment contains one.
    ///
    /// - Parameter comment: The comment text without the leading `--`.
    mutating func record(comment: String) {
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        if let body = Self.body(of: trimmed, directive: ATLLanguage.Directive.path) {
            recordBinding(body, into: \.paths)
        } else if let body = Self.body(of: trimmed, directive: ATLLanguage.Directive.namespaceURI) {
            recordBinding(body, into: \.namespaceURIs, reportingErrors: true)
        } else if let body = Self.body(of: trimmed, directive: ATLLanguage.Directive.parameter) {
            recordParameter(body)
        }
    }

    private static func body(of comment: String, directive: String) -> String? {
        guard comment.hasPrefix(directive + " ") else { return nil }
        return String(comment.dropFirst(directive.count + 1))
    }

    private mutating func recordBinding(
        _ body: String, into keyPath: WritableKeyPath<ATLDirectives, [String: String]>,
        reportingErrors: Bool = false
    ) {
        let components = body.split(separator: "=", maxSplits: 1)
        guard components.count == 2 else {
            if reportingErrors {
                errors.append("Malformed directive '\(body)': expected Name=value")
            }
            return
        }
        let name = String(components[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let value = String(components[1]).trimmingCharacters(in: .whitespacesAndNewlines)
        self[keyPath: keyPath][name] = value
    }

    private mutating func recordParameter(_ body: String) {
        let nameAndRest = body.split(separator: ":", maxSplits: 1)
        guard nameAndRest.count == 2 else {
            errors.append("Malformed @param '\(body)': expected 'name : Type = default'")
            return
        }
        let name = String(nameAndRest[0]).trimmingCharacters(in: .whitespacesAndNewlines)
        let typeAndDefault = nameAndRest[1].split(
            separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
        let typeName = String(typeAndDefault[0]).trimmingCharacters(in: .whitespacesAndNewlines)

        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }) else {
            errors.append("Malformed @param '\(body)': invalid parameter name '\(name)'")
            return
        }
        guard let type = ATLParameterType(rawValue: typeName) else {
            let supported = ATLParameterType.allCases.map(\.rawValue).joined(separator: ", ")
            errors.append(
                "Malformed @param '\(name)': unsupported type '\(typeName)' (supported: \(supported))"
            )
            return
        }
        guard !parameters.contains(where: { $0.name == name }) else {
            errors.append("Duplicate @param '\(name)'")
            return
        }

        var defaultValue: ATLParameterValue?
        if typeAndDefault.count == 2 {
            let text = String(typeAndDefault[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard let value = Self.defaultValue(text, of: type) else {
                errors.append("Malformed @param '\(name)': '\(text)' is not a valid \(typeName)")
                return
            }
            defaultValue = value
        }
        parameters.append(ATLModuleParameter(name: name, type: type, defaultValue: defaultValue))
    }

    private static func defaultValue(_ text: String, of type: ATLParameterType)
        -> ATLParameterValue?
    {
        switch type {
        case .string:
            if text.count >= 2, text.hasPrefix("'"), text.hasSuffix("'") {
                return .string(ATLStringEscapes.decode(String(text.dropFirst().dropLast())))
            }
            return .string(text)
        case .integer:
            return Int(text).map(ATLParameterValue.integer)
        case .boolean:
            switch text.lowercased() {
            case "true": return .boolean(true)
            case "false": return .boolean(false)
            default: return nil
            }
        case .real:
            return Double(text).map(ATLParameterValue.real)
        }
    }
}
