//
//  ATLTupleTests.swift
//  ATLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ATL

/// Tests for OCL tuple values: `Tuple{name = value, ...}` literals, their parts, their
/// equality, their text, and their use to identify the matches of rules with several
/// source pattern elements.
@Suite("ATL Tuple Tests")
@MainActor
struct ATLTupleTests {

    /// The presets.
    nonisolated static let presets = [ATLOptions.standard, ATLOptions.legacy]

    /// Evaluates an expression with the standard options.
    ///
    /// - Parameters:
    ///   - expression: The expression.
    ///   - declarations: Helper declarations that precede the probe.
    ///   - options: The options of the parser and the execution context.
    /// - Returns: The value of the expression.
    /// - Throws: Errors raised while parsing or evaluating.
    private func evaluate(
        _ expression: String, declarations: String = "", options: ATLOptions = .standard
    ) async throws -> (any EcoreValue)? {
        try await LanguageHarness.evaluate(expression, declarations: declarations, options: options)
    }

    // MARK: - Values

    @Test("A tuple literal evaluates to a tuple whose parts keep their order and values", arguments: presets)
    func literal(options: ATLOptions) async throws {
        let tuple = try #require(try await evaluate("Tuple{name = 'a', size = 3}", options: options) as? ATLTupleValue)
        #expect(tuple.names == ["name", "size"])
        #expect(tuple["name"] as? String == "a")
        #expect(tuple["size"] as? Int == 3)
        #expect(tuple["missing"] == nil)
    }

    @Test("The parts of a tuple bound to a variable are read by name", arguments: presets)
    func parts(options: ATLOptions) async throws {
        let value = try await evaluate(
            "let t : TupleType(name : String, size : Integer) = Tuple{name : String = 'a', size = 3} in t.name + t.size.toString()",
            options: options)
        #expect(value as? String == "a3")
    }

    @Test("A part may be undefined")
    func undefinedPart() async throws {
        #expect(try await evaluate("Tuple{a = OclUndefined}.a.oclIsUndefined()") as? Bool == true)
        let tuple = try #require(try await evaluate("Tuple{a = OclUndefined, b = 1}") as? ATLTupleValue)
        #expect(tuple.names == ["a", "b"])
    }

    @Test("A part written twice keeps the later value at the position of the first")
    func repeatedPart() async throws {
        let tuple = try #require(try await evaluate("Tuple{a = 1, b = 2, a = 3}") as? ATLTupleValue)
        #expect(tuple.names == ["a", "b"])
        #expect(tuple["a"] as? Int == 3)
    }

    @Test("Tuple values compare and hash in Swift as in ATL")
    func swiftEquality() {
        let first = ATLTupleValue(parts: [("a", 1), ("b", "x")])
        let reordered = ATLTupleValue(parts: [("b", "x"), ("a", 1.0)])
        let other = ATLTupleValue(parts: [("a", 2), ("b", "x")])
        #expect(first == reordered)
        #expect(first != other)
        #expect(first.hashValue == reordered.hashValue)
        #expect(Set<ATLTupleValue>([first, reordered, other]).count == 2)
    }

    @Test("Reading a part that the tuple does not have is an error naming the part")
    func missingPart() async throws {
        let message = try #require(await thrownDescription { _ = try await evaluate("Tuple{a = 1}.b") })
        #expect(message.contains("'b'"))
        #expect(message.contains("Tuple {a = 1}"))
    }

    @Test(
        "Tuples are equal when they have the same parts with equal values, in any order",
        arguments: [
            ("Tuple{a = 1, b = 'x'} = Tuple{b = 'x', a = 1}", true),
            ("Tuple{a = 1} = Tuple{a = 1.0}", true),
            ("Tuple{a = 1} = Tuple{a = 2}", false),
            ("Tuple{a = 1} = Tuple{b = 1}", false),
            ("Tuple{a = 1} = Tuple{a = 1, b = 2}", false),
            ("Tuple{a = 1} <> Tuple{a = 2}", true),
            ("Tuple{a = Sequence{1, 2}} = Tuple{a = Sequence{1, 2}}", true),
            ("Tuple{a = 1} = 1", false),
        ])
    func equality(expression: String, expected: Bool) async throws {
        #expect(try await evaluate(expression) as? Bool == expected)
    }

    @Test("Tuples are held in collections, compared there and read through iterators", arguments: presets)
    func collections(options: ATLOptions) async throws {
        #expect(
            try await evaluate("Sequence{Tuple{a = 1}, Tuple{a = 2}}->collect(t | t.a)", options: options)
                .integers == [1, 2])
        #expect(try await evaluate("Set{Tuple{a = 1}, Tuple{a = 1}, Tuple{a = 2}}->size()", options: options) as? Int == 2)
        #expect(try await evaluate("Sequence{Tuple{a = 1, b = 2}}->includes(Tuple{b = 2, a = 1})", options: options) as? Bool == true)
        #expect(
            try await evaluate("Sequence{Tuple{a = 2}, Tuple{a = 1}}->select(t | t.a > 1)->size()", options: options)
                as? Int == 1)
    }

    @Test("Tuples are passed to and returned from helpers, including helpers declared for tuple types", arguments: presets)
    func helpers(options: ATLOptions) async throws {
        let declarations = """
            helper def : pair(n : String, s : Integer) : TupleType(name : String, size : Integer) =
                Tuple{name = n, size = s};
            helper def : label(t : TupleType(name : String, size : Integer)) : String =
                t.name + '/' + t.size.toString();
            helper context TupleType(name : String, size : Integer) def : doubled : Integer = self.size * 2;
            helper context TupleType(name : String, size : Integer) def : shout() : String = self.name.toUpper();
            """
        #expect(
            try await evaluate("thisModule.label(thisModule.pair('a', 3))", declarations: declarations, options: options)
                as? String == "a/3")
        #expect(try await evaluate("thisModule.pair('a', 3).doubled", declarations: declarations, options: options) as? Int == 6)
        #expect(try await evaluate("thisModule.pair('a', 3).shout()", declarations: declarations, options: options) as? String == "A")
    }

    @Test("A tuple conforms to TupleType and OclAny, and its type is Tuple")
    func types() async throws {
        let tuple = try #require(try await evaluate("Tuple{a = 1}"))
        #expect(ATLTypeMatching.isKind(tuple, of: "TupleType(a : Integer)"))
        #expect(ATLTypeMatching.isType(tuple, of: ATLLanguage.tupleLiteral))
        #expect(ATLTypeMatching.isKind(tuple, of: ATLLanguage.SpecialType.any))
        #expect(!ATLTypeMatching.isKind(tuple, of: "String"))
        #expect(ATLTypeMatching.typeName(of: tuple) == "Tuple")
        #expect(try await evaluate("Tuple{a = 1}.oclIsUndefined()") as? Bool == false)
        #expect(try await evaluate("Tuple{a = 1}.oclType()") as? String == "Tuple")
    }

    // MARK: - Text

    @Test(
        "A tuple is written as ATL writes it",
        arguments: [
            ("Tuple{name = 'a', size = 3}.toString()", "Tuple {name = 'a', size = 3}"),
            ("Tuple{a = OclUndefined}.toString()", "Tuple {a = OclUndefined}"),
            ("Sequence{Tuple{a = 1}}.toString()", "Sequence{Tuple {a = 1}}"),
            ("Tuple{inner = Tuple{b = true}}.toString()", "Tuple {inner = Tuple {b = true}}"),
        ])
    func text(expression: String, expected: String) async throws {
        #expect(try await evaluate(expression) as? String == expected)
    }

    @Test("debug and query results write a tuple as ATL writes it")
    func debugAndQueryText() async throws {
        let harness = try await LanguageHarness.make(
            expression: "Tuple{name = 'a', size = 3}.debug('t')", options: .standard)
        let capture = ConsoleCapture()
        harness.context.console = capture.console
        let value = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        #expect(capture.errors == ["t: Tuple {name = 'a', size = 3}"])
        #expect(ATLValueText.render(value) == "Tuple {name = 'a', size = 3}")
    }

    @Test("A tuple bound to an attribute is a type error")
    func attributeBinding() async throws {
        let message = try #require(
            await thrownDescription {
                _ = try await ReportFixture().run(
                    """
                    rule P {
                        from s : Project!Project
                        to t : Report!Document (name <- Tuple{n = s.name})
                    }
                    """)
            })
        #expect(message.contains("Tuple {n = 'p'}"))
        #expect(message.contains("'name'"))
    }

    // MARK: - Resolution

    /// A rule that matches each task of the project together with the project, and a rule
    /// that matches the same elements under other variables.
    private let pairRules = """
        rule First {
            from s : Project!Task, p : Project!Project
            to t : Report!Summary (title <- 'first ' + s.name), u : Report!Summary (title <- 'extra')
        }
        rule Second {
            from x : Project!Task, y : Project!Project
            to t : Report!Summary (title <- 'second ' + x.name)
        }
        """

    /// Runs the pair rules with a document whose lead is bound to an expression.
    ///
    /// - Parameters:
    ///   - lead: The expression bound to the lead of the document.
    ///   - options: The options of the run.
    /// - Returns: The title of the summary that the lead refers to.
    /// - Throws: Errors raised by the run.
    private func leadTitle(_ lead: String, options: ATLOptions = .standard) async throws -> String? {
        let run = try await ReportFixture().run(
            pairRules + """
                rule P {
                    from s : Project!Project
                    to d : Report!Document (name <- s.name, lead <- \(lead))
                }
                """, priorities: [8, 3], options: options)
        let lead = try #require(await run.value("lead", of: try await run.document()) as? EUUID)
        return await run.target.eGet(objectId: lead, feature: "title") as? String
    }

    @Test("resolveTemp with a tuple finds the rule that binds its parts to the variables of those names", arguments: presets)
    func resolveTempWithTuple(options: ATLOptions) async throws {
        #expect(try await leadTitle("thisModule.resolveTemp(Tuple{s = s.tasks->first(), p = s}, 't')", options: options) == "first t1")
        #expect(try await leadTitle("thisModule.resolveTemp(Tuple{p = s, s = s.tasks->last()}, 'u')", options: options) == "extra")
        #expect(try await leadTitle("thisModule.resolveTemp(Tuple{x = s.tasks->first(), y = s}, 't')", options: options) == "second t1")
    }

    @Test("A tuple bound to a reference resolves to the default target of the match it identifies", arguments: presets)
    func defaultResolution(options: ATLOptions) async throws {
        #expect(try await leadTitle("Tuple{y = s, x = s.tasks->last()}", options: options) == "second t2")
        #expect(try await leadTitle("Tuple{s = s.tasks->first(), p = s}", options: options) == "first t1")
    }

    @Test("resolveTemp with a sequence still finds the first rule matching the elements in that order")
    func resolveTempWithSequence() async throws {
        #expect(try await leadTitle("thisModule.resolveTemp(Sequence{s.tasks->first(), s}, 't')") == "first t1")
    }

    @Test("resolveTemp with a tuple and a target pattern name that the rule does not have is an error")
    func missingPatternName() async throws {
        let message = try #require(
            await thrownDescription { _ = try await leadTitle("thisModule.resolveTemp(Tuple{s = s.tasks->first(), p = s}, 'none')") })
        #expect(message.contains("'none'"))
        #expect(message.contains("s = Task 't1'"))
    }

    @Test("A tuple that identifies no match is an error for resolveTemp and for a reference binding")
    func unresolvedTuple() async throws {
        let resolveTemp = try #require(
            await thrownDescription { _ = try await leadTitle("thisModule.resolveTemp(Tuple{s = s.tasks->first(), q = s}, 't')") })
        #expect(resolveTemp.contains("resolveTemp"))
        #expect(resolveTemp.contains("q = Project 'p'"))
        let binding = try #require(
            await thrownDescription { _ = try await leadTitle("Tuple{s = s.tasks->first(), q = s}") })
        #expect(binding.contains("'lead'"))
        #expect(binding.contains("q = Project 'p'"))
    }

    @Test("A tuple with one part does not identify the match of a rule with one source element, as in Eclipse ATL")
    func singlePartTuple() async throws {
        let message = try #require(
            await thrownDescription {
                _ = try await ReportFixture().run(
                    """
                    rule T {
                        from s : Project!Task
                        to t : Report!Summary (title <- s.name)
                    }
                    rule P {
                        from s : Project!Project
                        to d : Report!Document (lead <- thisModule.resolveTemp(Tuple{s = s.tasks->first()}, 't'))
                    }
                    """, priorities: [1])
            })
        #expect(message.contains("resolveTemp"))
    }

    @Test("An incremental update follows a tuple bound to a reference to the match it now identifies", arguments: presets)
    func incrementalResolution(options: ATLOptions) async throws {
        let fixture = ReportFixture()
        let rules = """
            rule Pair {
                from s : Project!Task, p : Project!Project (s.priority > 5)
                to t : Report!Summary (title <- s.name)
            }
            rule P {
                from s : Project!Project
                to d : Report!Document (
                    name <- s.name, lead <- Tuple{s = s.tasks->select(e | e.priority > 5)->first(), p = s})
            }
            """
        let module = try await fixture.module(rules, options: options)
        let source = await fixture.projectModel(priorities: [8, 3])
        let target = await ResourceSet().createResource(uri: ReportFixture.targetURI)
        let transformation = ATLIncrementalTransformation(module: module, options: options)
        try await transformation.execute(sources: ["IN": source], targets: ["OUT": target])
        let tasks = await source.getAllObjects().filter { $0.eClass.name == "Task" }
        try await source.eSetWithChanges(objectId: tasks[0].id, feature: "priority", value: 1)
        try await source.eSetWithChanges(objectId: tasks[1].id, feature: "priority", value: 9)
        _ = try await transformation.update()
        let document = try #require(await target.getAllObjects().first { $0.eClass.name == "Document" })
        let lead = try #require(await target.eGet(objectId: document.id, feature: "lead") as? EUUID)
        #expect(await target.eGet(objectId: lead, feature: "title") as? String == "t2")
    }
}
