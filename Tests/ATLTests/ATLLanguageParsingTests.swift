//
//  ATLLanguageParsingTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ATL

/// Tests for the syntax support code: escapes, directives, parsed structure and XMI round trips.
@Suite("ATL Language Parsing Tests")
@MainActor
struct ATLLanguageParsingTests {

    private let serializer = ATLExpressionXMISerializer()
    private let parser = ATLExpressionXMIParser()

    private func body(of source: String) async throws -> any ATLExpression {
        let module = try await ATLParser().parseContent(
            "module T;\nhelper def : probe() : OclAny = \(source);")
        return try #require((module.helpers["probe"] as? ATLHelperWrapper)?.bodyExpression)
    }

    // MARK: - Escapes

    @Test(
        "Escape decoding handles edge cases",
        arguments: [
            ("plain", "plain"), ("trailing\\", "trailing\\"), ("\\u12", "\\u12"),
            ("\\uZZZZ", "\\uZZZZ"), ("\\0", "\u{0}"), ("\\377", "\u{FF}"), ("\\8", "\\8"),
            ("\\u00e9", "é"), ("\\\\n", "\\n"), ("a\\tb\\nc", "a\tb\nc"), ("\\b\\f", "\u{08}\u{0C}"),
        ])
    func escapeDecoding(raw: String, expected: String) {
        #expect(ATLStringEscapes.decode(raw) == expected)
    }

    // MARK: - Directives

    @Test("Directives are recorded from comment text")
    func directiveRecording() {
        var directives = ATLDirectives()
        directives.record(comment: " @path Families=/Families2Persons/Families.ecore")
        directives.record(comment: " @nsURI Ecore = http://www.eclipse.org/emf/2002/Ecore")
        directives.record(comment: " @param limit : Integer = 5")
        directives.record(comment: " an ordinary comment")
        directives.record(comment: " @pathological")
        #expect(directives.paths == ["Families": "/Families2Persons/Families.ecore"])
        #expect(directives.namespaceURIs == ["Ecore": "http://www.eclipse.org/emf/2002/Ecore"])
        #expect(directives.parameters.count == 1)
        #expect(directives.errors.isEmpty)
    }

    @Test("A malformed @path directive is ignored, as it always was")
    func malformedPathIgnored() {
        var directives = ATLDirectives()
        directives.record(comment: " @path NoEquals")
        #expect(directives.paths.isEmpty)
        #expect(directives.errors.isEmpty)
    }

    @Test("An @nsURI value may itself contain an equals sign")
    func nsURIWithEquals() {
        var directives = ATLDirectives()
        directives.record(comment: " @nsURI A=http://example.org/x?a=b")
        #expect(directives.namespaceURIs["A"] == "http://example.org/x?a=b")
    }

    // MARK: - Parsed structure

    @Test("Infix keywords build the expected tree")
    func precedenceTree() async throws {
        let impliesTree = try await body(of: "a or b implies c and d")
        let implies = try #require(impliesTree as? ATLBinaryExpression)
        #expect(implies.operator == .implies)
        #expect((implies.left as? ATLBinaryExpression)?.operator == .or)
        #expect((implies.right as? ATLBinaryExpression)?.operator == .and)

        let xorTree = try await body(of: "a xor b and c")
        let xor = try #require(xorTree as? ATLBinaryExpression)
        #expect(xor.operator == .xor)
        #expect((xor.right as? ATLBinaryExpression)?.operator == .and)

        let divTree = try await body(of: "a + b div c mod d")
        let sum = try #require(divTree as? ATLBinaryExpression)
        #expect(sum.operator == .plus)
        let remainder = try #require(sum.right as? ATLBinaryExpression)
        #expect(remainder.operator == .modulo)
        #expect((remainder.left as? ATLBinaryExpression)?.operator == .integerDivide)
    }

    @Test("Literals parse to the expected expression types")
    func literalTypes() async throws {
        #expect((try await body(of: "1") as? ATLLiteralExpression)?.value as? Int == 1)
        #expect((try await body(of: "1.5") as? ATLLiteralExpression)?.value as? Double == 1.5)
        #expect(try await body(of: "#Lit") as? ATLEnumLiteralExpression == ATLEnumLiteralExpression(name: "Lit"))
        #expect((try await body(of: "OclUndefined") as? ATLLiteralExpression)?.value == nil)
        #expect(try await body(of: "Integer") as? ATLTypeLiteralExpression == ATLTypeLiteralExpression(typeName: "Integer"))
        #expect(try await body(of: "Sequence(Integer)") as? ATLTypeLiteralExpression == ATLTypeLiteralExpression(typeName: "Sequence(Integer)"))
        #expect((try await body(of: "OrderedSet{1}") as? ATLCollectionLiteralExpression)?.collectionType == "OrderedSet")
    }

    @Test("Iterator lambdas accept several and typed variables")
    func lambdaForms() async throws {
        let multi = try await body(of: "c->exists(a, b | a = b)")
        let call = try #require(multi as? ATLMethodCallExpression)
        let lambda = try #require(call.arguments.first as? ATLLambdaExpression)
        #expect(lambda.parameters == ["a", "b"])

        let typed = try await body(of: "c->select(e : Integer | e > 1)")
        let typedLambda = try #require((typed as? ATLMethodCallExpression)?.arguments.first as? ATLLambdaExpression)
        #expect(typedLambda.parameters == ["e"])

        let plain = try await body(of: "f(a, b)")
        let helperCall = try #require(plain as? ATLHelperCallExpression)
        #expect(helperCall.arguments.count == 2)
        #expect(helperCall.arguments.allSatisfy { $0 is ATLVariableExpression })
    }

    @Test("A lambda is accepted as an argument of an unqualified call")
    func lambdaInFunctionCall() async throws {
        let call = try await body(of: "apply(e | e + 1)")
        let helperCall = try #require(call as? ATLHelperCallExpression)
        #expect(helperCall.arguments.first is ATLLambdaExpression)
    }

    @Test("A colon inside call arguments that is not a typed iterator is a syntax error")
    func strayColon() async {
        await #expect(throws: ATLParseError.self) {
            _ = try await self.body(of: "f(a : 1)")
        }
    }

    @Test("Expression hashing covers enumeration literals")
    func enumerationHashing() {
        var first = Hasher()
        var second = Hasher()
        hashATLExpression(ATLEnumLiteralExpression(name: "A"), into: &first)
        hashATLExpression(ATLEnumLiteralExpression(name: "A"), into: &second)
        #expect(first.finalize() == second.finalize())
    }

    @Test("Operators and keywords that are not infix still work as names")
    func namesStayUsable() async throws {
        let call = try await body(of: "x.div(2)")
        #expect((call as? ATLMethodCallExpression)?.methodName == "div")
        let navigation = try await body(of: "x.xor")
        #expect((navigation as? ATLNavigationExpression)?.property == "xor")
    }

    @Test("Large integer literals fall back to reals instead of failing")
    func hugeInteger() async throws {
        let literal = try await body(of: "99999999999999999999")
        #expect((literal as? ATLLiteralExpression)?.value as? Double == 99999999999999999999.0)
    }

    // MARK: - XMI round trips

    @Test("Enumeration literals round-trip through XMI")
    func enumerationRoundTrip() throws {
        let original = ATLEnumLiteralExpression(name: "Editable")
        let xmi = serializer.serialize(original)
        #expect(xmi.contains("EnumLiteralExp"))
        let parsed = try parser.parse(wrapExpression(xmi))
        #expect(parsed as? ATLEnumLiteralExpression == original)
    }

    @Test("Lambdas with several variables round-trip through XMI")
    func multiLambdaRoundTrip() throws {
        let original = ATLLambdaExpression(
            parameters: ["a", "b"], body: ATLVariableExpression(name: "a"))
        let parsed = try parser.parse(wrapExpression(serializer.serialize(original)))
        #expect((parsed as? ATLLambdaExpression)?.parameters == ["a", "b"])
    }

    private func wrapExpression(_ xmi: String) -> String {
        "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<root xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\">\n\(xmi)</root>"
    }
}
