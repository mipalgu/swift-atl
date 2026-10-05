//
//  ATLDiagnosingParserTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ATL

/// Tests for diagnosing parsing, recovery, outlines and node origins.
@Suite("ATL Diagnosing Parser Tests")
struct ATLDiagnosingParserTests {

    /// The text a range covers, read by UTF-8 offsets.
    static func slice(_ range: SourceRange?, of source: String) -> String? {
        guard let range else { return nil }
        let bytes = Array(source.utf8)
        return String(
            decoding: bytes[range.start.utf8Offset..<range.end.utf8Offset], as: UTF8.self)
    }

    static let wellFormed = """
        module Shapes2Shapes;
        create OUT : Shapes from IN : Shapes;
        helper context Shapes!Circle def : area() : Real = self.radius * 2;
        helper def : twice(n : Integer) : Integer = n + n;
        helper def : unit : Integer = 1;
        query Total = 42;
        rule Circle2Circle {
            from s : Shapes!Circle (s.radius > 0)
            to t : Shapes!Circle (
                name <- s.name,
                radius <- s.radius * 2
            )
            do {
                t.name <- t.name + '!';
            }
        }
        lazy rule Make {
            from s : Shapes!Square
            to t : Shapes!Square (name <- s.name)
        }
        rule Entry(count : Integer) {
            to t : Shapes!Circle (radius <- count)
        }
        """

    static let broken = """
        module Broken;
        create OUT : Shapes from IN : Shapes;
        helper def : good() : Integer = 1;
        helper def : bad( : Integer = 2;
        rule First {
            from s : Shapes!Circle
            to t : Shapes!Circle (
                name <- s.name,
                radius <- ,
                radius <- s.radius
            )
        }
        rule Second {
            from s : Shapes!Square
            to t : Shapes!Square ( side <- ( )
        }
        helper def : after() : Integer = 3;
        query Q = 5;
        """

    private let registry = ATLMetamodelRegistry(packages: [ShapeFixture().package])

    private func parse(_ source: String) async -> ATLParseResult {
        await ATLParser().parseDiagnosing(source, name: "test.atl", metamodelRegistry: registry)
    }

    @Test("Well-formed source yields a module and no diagnostics")
    func wellFormed() async throws {
        let result = await parse(Self.wellFormed)
        #expect(result.diagnostics.isEmpty)
        let module = try #require(result.module)
        #expect(module.name == "Shapes2Shapes")
        #expect(module.matchedRules.count == 1)
        #expect(module.calledRules.count == 2)
        #expect(!result.tokens.isEmpty)
    }

    @Test("Recovery reports several problems in one file")
    func recovery() async throws {
        let result = await parse(Self.broken)
        #expect(result.diagnostics.count == 3)
        let codes = Set(ATLDiagnosticCode.allCases.map(\.rawValue))
        for diagnostic in result.diagnostics {
            #expect(diagnostic.severity == .error)
            #expect(codes.contains(diagnostic.code))
            #expect(diagnostic.range != nil)
            #expect(!diagnostic.message.isEmpty)
        }
        let lines = result.diagnostics.compactMap { $0.range?.start.line }
        #expect(lines == [4, 9, 15])
        #expect(lines == lines.sorted())

        let module = try #require(result.module)
        #expect(module.helpers["good"] != nil)
        #expect(module.helpers["bad"] == nil)
        #expect(module.helpers["after"] != nil)
        #expect(module.helpers["Q"] != nil)
        let first = try #require(module.matchedRules.first { $0.name == "First" })
        #expect(first.targetPatterns.first?.bindings.map(\.property) == ["name", "radius"])
        #expect(!module.matchedRules.contains { $0.name == "Second" })
    }

    @Test("A diagnostic points at the offending token")
    func diagnosticRange() async throws {
        let result = await parse(Self.broken)
        let first = try #require(result.diagnostics.first)
        #expect(Self.slice(first.range, of: Self.broken) == ":")
        #expect(first.code == ATLDiagnosticCode.invalidSyntax.rawValue)
        let binding = try #require(result.diagnostics.dropFirst().first)
        #expect(Self.slice(binding.range, of: Self.broken) == ",")
    }

    @Test("Stray top-level tokens are reported once per run")
    func strayTokens() async throws {
        let source = "module M;\n) ; )\nhelper def : f() : Integer = 1;\n}\n"
        let result = await parse(source)
        #expect(result.diagnostics.map(\.code) == ["atl.unexpectedToken", "atl.unexpectedToken"])
        #expect(Self.slice(result.diagnostics[0].range, of: source) == ") ; )")
        #expect(Self.slice(result.diagnostics[1].range, of: source) == "}")
        #expect(result.module?.helpers["f"] != nil)
    }

    @Test("A missing module declaration is reported and declarations are still outlined")
    func missingModule() async {
        let result = await parse("helper def : f() : Integer = 1;")
        #expect(result.module == nil)
        #expect(result.diagnostics.first?.code == ATLDiagnosticCode.missingModule.rawValue)
        #expect(result.outline.map(\.kind) == [ATLOutlineKind.helper])
    }

    @Test("Lexical problems and malformed directives become diagnostics")
    func lexicalProblems() async throws {
        let source = "-- @nsURI broken\nmodule M;\nhelper def : f() : String = 'open"
        let result = await parse(source)
        let codes = result.diagnostics.map(\.code)
        #expect(codes.contains(ATLDiagnosticCode.invalidDirective.rawValue))
        #expect(codes.contains(ATLDiagnosticCode.unterminatedString.rawValue))
        let directive = try #require(
            result.diagnostics.first { $0.code == ATLDiagnosticCode.invalidDirective.rawValue })
        #expect(directive.range?.start.line == 1)
        let string = try #require(
            result.diagnostics.first { $0.code == ATLDiagnosticCode.unterminatedString.rawValue })
        #expect(Self.slice(string.range, of: source) == "'open")
        #expect(result.tokens.contains { $0.kind == .invalid })
    }

    @Test("Unexpected characters are reported with their position")
    func unexpectedCharacter() async throws {
        let source = "module M;\nhelper def : f() : Integer = 1 ^ 2;\nhelper def : g() : Integer = 2;"
        let result = await parse(source)
        let diagnostic = try #require(
            result.diagnostics.first { $0.code == ATLDiagnosticCode.unexpectedCharacter.rawValue })
        #expect(diagnostic.range?.start.line == 2)
        #expect(diagnostic.range?.start.column == 32)
        #expect(result.module?.helpers["g"] != nil)
    }

    @Test("Diagnosing and throwing parses agree on well-formed source")
    func agreesWithThrowingParse() async throws {
        let throwing = try await ATLParser().parseContent(
            Self.wellFormed, filename: "test.atl", metamodelRegistry: registry)
        let diagnosing = try #require(await parse(Self.wellFormed).module)
        #expect(throwing == diagnosing)
    }

    @Test("A metamodel without a package is reported as a warning")
    func unboundMetamodel() async throws {
        let source = "module M;\ncreate OUT : Missing from IN : Shapes;\n"
        let result = await parse(source)
        let warning = try #require(result.diagnostics.first)
        #expect(result.diagnostics.count == 1)
        #expect(warning.severity == .warning)
        #expect(warning.code == ATLDiagnosticCode.metamodelNotFound.rawValue)
        #expect(Self.slice(warning.range, of: source) == "Missing")
        #expect(result.module != nil)
    }

    @Test("Parsing a file with CRLF line ends gives the same diagnostics")
    func crlf() async {
        let reference = await parse(Self.broken)
        let crlf = await parse(Self.broken.replacingOccurrences(of: "\n", with: "\r\n"))
        #expect(reference.diagnostics.map(\.code) == crlf.diagnostics.map(\.code))
        #expect(
            reference.diagnostics.compactMap { $0.range?.start.line }
                == crlf.diagnostics.compactMap { $0.range?.start.line })
    }

    // MARK: - Outline

    @Test("The outline lists the module with its declarations")
    func outline() async throws {
        let source = Self.wellFormed
        let result = await parse(source)
        let root = try #require(result.outline.first)
        #expect(result.outline.count == 1)
        #expect(root.kind == ATLOutlineKind.module)
        #expect(root.name == "Shapes2Shapes")
        #expect(Self.slice(root.selectionRange, of: source) == "Shapes2Shapes")
        let summary = root.children.map { "\($0.kind) \($0.name)" }
        #expect(
            summary == [
                "helper area", "helper twice", "attribute unit", "query Total",
                "matchedRule Circle2Circle", "lazyRule Make", "calledRule Entry",
            ])
        let area = root.children[0]
        #expect(area.detail == "Shapes!Circle -> Real")
        #expect(Self.slice(area.selectionRange, of: source) == "area")
        #expect(Self.slice(area.range, of: source)?.hasPrefix("helper context") == true)
        #expect(Self.slice(area.range, of: source)?.hasSuffix("* 2;") == true)
        #expect(root.children[1].detail == "-> Integer")
        let rule = root.children[4]
        #expect(rule.detail == "Shapes!Circle -> Shapes!Circle")
        #expect(rule.children.map(\.kind) == [ATLOutlineKind.sourcePattern, ATLOutlineKind.targetPattern])
        #expect(rule.children.map(\.name) == ["s", "t"])
        #expect(rule.children.map(\.detail) == ["Shapes!Circle", "Shapes!Circle"])
        #expect(root.children[5].detail == "Shapes!Square -> Shapes!Square")
        #expect(root.children[6].detail == "(count : Integer) -> Shapes!Circle")
        #expect(root.range.contains(rule.range))
    }

    @Test("Outline identifiers are unique and stable")
    func outlineIdentifiers() async {
        let source = """
            module M;
            helper context String def : f() : Integer = 1;
            helper context Integer def : f() : Integer = 2;
            """
        let first = await parse(source).outline
        let second = await parse(source).outline
        func identifiers(_ nodes: [OutlineNode]) -> [String] {
            nodes.flatMap { [$0.id] + identifiers($0.children) }
        }
        let ids = identifiers(first)
        #expect(Set(ids).count == ids.count)
        #expect(ids == identifiers(second))
    }

    @Test("Declarations that fail to parse are still outlined")
    func outlineOfBrokenDeclarations() async throws {
        let result = await parse(Self.broken)
        let root = try #require(result.outline.first)
        let names = root.children.map(\.name)
        #expect(names == ["good", "bad", "First", "Second", "after", "Q"])
        let second = root.children[3]
        #expect(Self.slice(second.range, of: Self.broken)?.hasPrefix("rule Second") == true)
    }

    // MARK: - Origins

    @Test("Declarations carry the range they were written in")
    func declarationOrigins() async throws {
        let source = Self.wellFormed
        let module = try #require(await parse(source).module)
        #expect(Self.slice(module.origin.range, of: source)?.hasPrefix("module Shapes2Shapes;") == true)
        #expect(Self.slice(module.origin.range, of: source)?.hasSuffix("}") == true)

        let area = try #require(module.helpers["area"])
        #expect(
            Self.slice(area.origin.range, of: source)
                == "helper context Shapes!Circle def : area() : Real = self.radius * 2;")
        let total = try #require(module.helpers["Total"])
        #expect(Self.slice(total.origin.range, of: source) == "query Total = 42;")

        let rule = try #require(module.matchedRules.first)
        #expect(Self.slice(rule.origin.range, of: source)?.hasPrefix("rule Circle2Circle {") == true)
        #expect(Self.slice(rule.origin.range, of: source)?.hasSuffix("}") == true)
        #expect(Self.slice(rule.sourcePattern.origin.range, of: source) == "s : Shapes!Circle (s.radius > 0)")
        let target = try #require(rule.targetPatterns.first)
        #expect(Self.slice(target.origin.range, of: source)?.hasPrefix("t : Shapes!Circle (") == true)
        #expect(Self.slice(target.bindings[0].origin.range, of: source) == "name <- s.name")
        #expect(Self.slice(target.bindings[1].origin.range, of: source) == "radius <- s.radius * 2")

        let lazy = try #require(module.calledRules["Make"])
        #expect(Self.slice(lazy.origin.range, of: source)?.hasPrefix("lazy rule Make") == true)
    }

    @Test("Expressions and statements carry the range of their text")
    func expressionOrigins() async throws {
        let source = Self.wellFormed
        let module = try #require(await parse(source).module)
        let area = try #require(module.helpers["area"] as? ATLHelperWrapper)
        let body = area.bodyExpression
        #expect(Self.slice(body.origin.range, of: source) == "self.radius * 2")
        let binary = try #require(body as? ATLBinaryExpression)
        #expect(Self.slice(binary.left.origin.range, of: source) == "self.radius")
        #expect(Self.slice(binary.right.origin.range, of: source) == "2")
        let navigation = try #require(binary.left as? ATLNavigationExpression)
        #expect(Self.slice(navigation.source.origin.range, of: source) == "self")

        let rule = try #require(module.matchedRules.first)
        let statement = try #require(rule.doStatements.first)
        #expect(Self.slice(statement.origin.range, of: source) == "t.name <- t.name + '!';")
        let guardExpression = try #require(rule.sourcePattern.guard)
        #expect(Self.slice(guardExpression.origin.range, of: source) == "s.radius > 0")
    }

    @Test("Origins do not affect equality")
    func originsAreEqualityNeutral() async throws {
        let compact = "module M;create OUT:A from IN:B;helper def:f():Integer=1+2;"
        let spaced = "module  M;\n\ncreate OUT : A from IN : B;\n\nhelper def : f() : Integer = 1 + 2;\n"
        let first = try #require(await parse(compact).module)
        let second = try #require(await parse(spaced).module)
        #expect(first == second)
        #expect(first.helpers["f"]?.origin.range != second.helpers["f"]?.origin.range)
        #expect(ATLVariableExpression(name: "x") == ATLVariableExpression(name: "x", origin: SourceOrigin(.init(start: .start, end: .start))))
    }

    @Test("Nodes built in code have no origin")
    func builtNodes() {
        #expect(ATLVariableExpression(name: "x").origin.range == nil)
        #expect(ATLAssignmentStatement(target: .variable("x"), value: ATLVariableExpression(name: "y")).origin.range == nil)
    }

    @Test("The throwing parser keeps origins")
    func throwingParserOrigins() async throws {
        let module = try await ATLParser().parseContent(Self.wellFormed)
        #expect(module.helpers["twice"]?.origin.range != nil)
    }
}
