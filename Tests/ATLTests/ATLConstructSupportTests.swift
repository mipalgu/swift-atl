//
//  ATLConstructSupportTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ATL

/// Tests that every ATL construct either parses and runs or is rejected loudly.
@Suite("ATL Construct Support Tests")
@MainActor
struct ATLConstructSupportTests {

    /// What a construct is expected to do.
    enum Outcome: Sendable {
        /// The construct parses and creates this many target elements of a class.
        case runs(className: String, count: Int)

        /// The construct is rejected as unsupported at the given text and line.
        case unsupported(text: String, line: Int)
    }

    /// One ATL construct with its expected outcome.
    struct Construct: Sendable, CustomTestStringConvertible {
        let name: String
        let source: String
        let outcome: Outcome

        var testDescription: String { name }

        init(_ name: String, _ declarations: String, _ outcome: Outcome) {
            self.name = name
            self.source = Self.header + declarations
            self.outcome = outcome
        }

        init(_ name: String, whole source: String, _ outcome: Outcome) {
            self.name = name
            self.source = source
            self.outcome = outcome
        }

        static let header = "module Test;\ncreate OUT : Tgt from IN : Src;\n"
    }

    nonisolated static let constructs: [Construct] = [
        Construct(
            "lazy rule",
            """
            lazy rule Copy { from s : Src!Node to t : Tgt!Marker (label <- s.name) }
            rule H2T {
                from h : Src!Holder
                to t : Tgt!TNode (name <- 'h', kids <- h.items->collect(i | thisModule.Copy(i)))
            }
            """, .runs(className: "Marker", count: 4)),
        Construct(
            "unique lazy rule",
            """
            unique lazy rule Copy { from s : Src!Node to t : Tgt!Marker (label <- s.name) }
            rule H2T {
                from h : Src!Holder
                to t : Tgt!TNode (name <- 'h', kids <- h.items->collect(i | thisModule.Copy(i)))
            }
            rule H2U {
                from h : Src!Holder
                to t : Tgt!TNode (name <- 'u', kids <- h.items->collect(i | thisModule.Copy(i)))
            }
            """, .runs(className: "Marker", count: 4)),
        Construct(
            "called rule with parameters",
            """
            rule Make(n : String) { to t : Tgt!Marker (label <- n) }
            rule H2T {
                from h : Src!Holder
                to t : Tgt!TNode (name <- 'h')
                do { thisModule.Make('x'); }
            }
            """, .runs(className: "Marker", count: 1)),
        Construct(
            "entrypoint rule",
            "entrypoint rule Start() { to m : Tgt!Marker (label <- 'start') }",
            .runs(className: "Marker", count: 1)),
        Construct(
            "endpoint rule",
            "endpoint rule Finish() { to m : Tgt!Marker (label <- 'end') }",
            .runs(className: "Marker", count: 1)),
        Construct(
            "do block",
            """
            rule N2T {
                from s : Src!Node (s.name = 'alpha')
                to t : Tgt!TNode (name <- s.name)
                do { t.tag <- 'done'; }
            }
            """, .runs(className: "TNode", count: 1)),
        Construct(
            "iterate",
            """
            helper def : total() : Integer =
                Src!Node.allInstances()->iterate(n; acc : Integer = 0 | acc + n.age);
            rule H2T {
                from h : Src!Holder
                to t : Tgt!TNode (count <- thisModule.total())
            }
            """, .runs(className: "TNode", count: 1)),
        Construct(
            "helper attribute",
            """
            helper context Src!Node def : label : String = self.name + '!';
            rule N2T {
                from s : Src!Node (s.name = 'alpha')
                to t : Tgt!TNode (name <- s.label)
            }
            """, .runs(className: "TNode", count: 1)),
        Construct(
            "rule inheritance",
            """
            abstract rule Base {
                from s : Src!Node
                to t : Tgt!TNode (name <- s.name)
            }
            rule Sub extends Base {
                from sp : Src!Special
                to t : Tgt!TNode (tag <- 'special')
            }
            """, .runs(className: "TNode", count: 1)),
        Construct(
            "abstract rule",
            "abstract rule Base { from s : Src!Node to t : Tgt!TNode (name <- s.name) }",
            .runs(className: "TNode", count: 0)),
        Construct(
            "library",
            whole: "library Helpers;\nhelper def : f() : Integer = 1;\n",
            .unsupported(text: "library", line: 1)),
        Construct(
            "uses",
            "uses Helpers;\nhelper def : f() : Integer = 1;\n",
            .unsupported(text: "uses", line: 3)),
        Construct(
            "refining mode",
            whole: "module Test;\ncreate OUT : Tgt refining IN : Src;\n",
            .unsupported(text: "refining", line: 2)),
        Construct(
            "distinct foreach",
            """
            rule H2T {
                from h : Src!Holder
                to t : Tgt!TNode distinct foreach (i in h.items) (name <- i.name)
            }
            """, .unsupported(text: "distinct", line: 5)),
        Construct(
            "foreach",
            """
            rule H2T {
                from h : Src!Holder
                to t : Tgt!TNode foreach (i in h.items) (name <- i.name)
            }
            """, .unsupported(text: "foreach", line: 5)),
        Construct(
            "nodefault",
            "nodefault rule N2T { from s : Src!Node to t : Tgt!TNode (name <- s.name) }",
            .unsupported(text: "nodefault", line: 3)),
        Construct(
            "extending a lazy rule",
            """
            abstract rule Base { from s : Src!Node to t : Tgt!TNode (name <- s.name) }
            lazy rule Copy extends Base { from s : Src!Node to t : Tgt!TNode (tag <- 'x') }
            """, .unsupported(text: "extends", line: 4)),
        Construct(
            "extending a called rule",
            """
            abstract rule Base { from s : Src!Node to t : Tgt!TNode (name <- s.name) }
            rule Make(n : String) extends Base { to t : Tgt!TNode (tag <- n) }
            """, .unsupported(text: "extends", line: 4)),
    ]

    private static func slice(_ range: SourceRange?, of source: String) -> String? {
        ATLDiagnosingParserTests.slice(range, of: source)
    }

    /// Builds a module from parsed text, substituting the hand-built metamodels.
    private func module(_ parsed: ATLModule, _ fixture: SemanticsFixture) -> ATLModule {
        ATLModule(
            name: parsed.name, sourceMetamodels: ["IN": fixture.source],
            targetMetamodels: ["OUT": fixture.target], helpers: parsed.helpers,
            matchedRules: parsed.matchedRules, calledRules: parsed.calledRules)
    }

    @Test("A construct parses and runs or is reported as unsupported", arguments: constructs)
    func construct(_ construct: Construct) async throws {
        switch construct.outcome {
        case .runs(let className, let count):
            var fixture = SemanticsFixture()
            await fixture.populate()
            let parsed = try await ATLParser().parseContent(construct.source)
            let machine = ATLVirtualMachine(module: module(parsed, fixture))
            try await machine.execute(
                sources: ["IN": fixture.sourceResource], targets: ["OUT": fixture.targetResource])
            #expect(await fixture.targets(className).count == count)

        case .unsupported(let text, let line):
            await #expect {
                try await ATLParser().parseContent(construct.source)
            } throws: { error in
                guard case ATLParseError.unsupportedConstruct = error else { return false }
                return true
            }
            let result = await ATLParser().parseDiagnosing(construct.source, name: "test.atl")
            let diagnostic = try #require(
                result.diagnostics.first { $0.code == ATLDiagnosticCode.unsupportedConstruct.rawValue })
            #expect(Self.slice(diagnostic.range, of: construct.source) == text)
            #expect(diagnostic.range?.start.line == line)
        }
    }

    @Test("Unsupported constructs do not hide supported declarations after them")
    func recoveryAfterUnsupported() async throws {
        let source =
            ATLConstructSupportTests.Construct.header
            + "uses Helpers;\nhelper def : f() : Integer = 1;\nnodefault rule R { from s : Src!Node to t : Tgt!TNode }\nhelper def : g() : Integer = 2;\n"
        let result = await ATLParser().parseDiagnosing(source, name: "test.atl")
        #expect(
            result.diagnostics.filter { $0.code == ATLDiagnosticCode.unsupportedConstruct.rawValue }
                .count == 2)
        #expect(result.module?.helpers["f"] != nil)
        #expect(result.module?.helpers["g"] != nil)
    }

    @Test("Tokens that start no declaration are rejected by the throwing parser")
    func strayTokens() async {
        await #expect {
            try await ATLParser().parseContent("module T;\nstray\n")
        } throws: { error in
            guard case ATLParseError.unexpectedToken(let message) = error else { return false }
            return message.contains("stray") && message.contains("line 2, column 1")
        }
    }

    @Test("Malformed headers and parameter lists are rejected, not skipped")
    func malformedHeaders() async {
        for source in [
            "module T;\ncreate OUT Tgt from IN : Src;\n",
            "module T;\ncreate OUT : Tgt from IN Src;\n",
            "module T;\nhelper def : f(a : Integer : Integer = 1;\n",
            "module T;\nrule R { from s : A!B (s.x to t : C!D }\n",
        ] {
            await #expect(throws: ATLParseError.self) {
                try await ATLParser().parseContent(source)
            }
        }
    }

    nonisolated private static func fixtureURLs() throws -> [URL] {
        let resources = try #require(Bundle.module.resourceURL)
        let enumerator = try #require(
            FileManager.default.enumerator(at: resources, includingPropertiesForKeys: nil))
        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "atl" }
    }

    @Test("Every shipped fixture parses without errors")
    func fixturesParse() async throws {
        var parsed = 0
        for url in try Self.fixtureURLs() {
            let text = try String(contentsOf: url, encoding: .utf8)
            _ = try await ATLParser().parseContent(text, filename: url.path)
            let result = await ATLParser().parseDiagnosing(text, name: url.path)
            #expect(result.diagnostics.filter { $0.severity == .error }.isEmpty, "\(url.lastPathComponent)")
            parsed += 1
        }
        #expect(parsed >= 10)
    }

    @Test(
        "References to things that do not exist fail the transformation",
        arguments: [
            "rule R { from s : Src!Nonexistent to t : Tgt!TNode (name <- 'x') }",
            "rule R { from s : Src!Node to t : Tgt!Nonexistent (name <- 'x') }",
            "rule R { from s : Src!Node to t : Tgt!TNode (bogus <- 'x') }",
            "rule R { from s : Src!Node to t : Tgt!TNode (name <- thisModule.nope()) }",
            "rule R { from s : Src!Node to t : Tgt!TNode (name <- thisModule.Nope(s)) }",
            "rule R { from s : Src!Node to t : Tgt!TNode (name <- s.bogus) }",
            "rule R { from s : Foo!Node to t : Tgt!TNode (name <- 'x') }",
            "rule R { from s : Src!Node to t : Tgt!TNode (name <- nope(1)) }",
            "rule R { from s : Src!Node to t : Tgt!TNode (name <- s.name.nopeMethod()) }",
            "rule R { from s : Src!Node to t : Tgt!TNode (name <- undefinedVariable) }",
        ])
    func unknownReferences(_ declarations: String) async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        await #expect(throws: (any Error).self) {
            try await fixture.run(declarations)
        }
    }
}
