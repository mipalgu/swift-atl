//
//  ATLQueryTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 26/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import OrderedCollections
import Testing

@testable import ATL

// MARK: - Support

/// Locates the fixtures shared by the query tests.
enum QueryFixtures {
    /// The location of a fixture shipped at the top level of the test resources.
    ///
    /// - Parameter name: The file name of the fixture.
    /// - Returns: The fixture location.
    static func url(_ name: String) throws -> URL {
        let resources = try #require(Bundle.module.resourceURL)
        let nested = resources.appendingPathComponent("Resources")
        var isDirectory: ObjCBool = false
        let root =
            FileManager.default.fileExists(atPath: nested.path, isDirectory: &isDirectory)
                && isDirectory.boolValue ? nested : resources
        return root.appendingPathComponent(name)
    }

    /// Parses query source as if it were stored next to the library fixtures.
    ///
    /// - Parameter source: The ATL source.
    /// - Returns: The parsed unit with its directive metamodels loaded.
    static func parse(_ source: String) async throws -> ATLModule {
        try await ATLParser().parseContent(
            source, filename: try url("Inline.atl").path, continueAfterErrors: false)
    }

    /// Loads the library model of the fixtures.
    ///
    /// - Parameter package: The library metamodel.
    /// - Returns: The library model.
    static func library(conformingTo package: EPackage) async throws -> Resource {
        let resourceSet = ResourceSet()
        await resourceSet.registerMetamodel(package, uri: package.nsURI)
        return try await XMIParser(resourceSet: resourceSet).parse(try url("Library.xmi"))
    }

    /// The header that binds the library metamodel of the fixtures.
    static let libraryPath = "-- @path Library=Library.ecore\n"

    /// Creates an empty directory for files written by a test.
    ///
    /// - Returns: The location of the new directory.
    static func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("atl-query-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}

/// Extracts the message of an invalid operation error.
private func invalidOperation(_ error: any Error) -> String? {
    guard case .invalidOperation(let message)? = error as? ATLExecutionError else { return nil }
    return message
}

// MARK: - Parsing

/// Tests for parsing ATL query units.
@Suite("ATL Query Unit Parsing")
struct ATLQueryParsingTests {

    @Test("A minimal query unit is parsed as a query")
    func minimalQuery() async throws {
        let unit = try await ATLParser().parseContent("query Q = 1;")
        #expect(unit.name == "Q")
        #expect(unit.kind == .query)
        #expect(unit.isQuery)
        #expect(unit.queryBody is ATLLiteralExpression)
        #expect(unit.helpers.isEmpty)
        #expect(unit.sourceMetamodels.isEmpty)
        #expect(unit.targetMetamodels.isEmpty)
        #expect(unit.matchedRules.isEmpty)
        #expect(unit.calledRules.isEmpty)
    }

    @Test("A query unit holds the helpers that follow its query")
    func queryWithHelpers() async throws {
        let unit = try await ATLParser().parseContent(
            """
            -- A query with helpers
            query Answer = thisModule.double(21);

            helper def : double(x : Integer) : Integer = x * 2;
            helper def : base : Integer = 40;
            helper context String def : shout() : String = self.toUpper();
            """)
        #expect(unit.kind == .query)
        #expect(unit.name == "Answer")
        #expect(Set(unit.helpers.keys) == ["double", "base", "shout"])
        #expect(unit.helpers["shout"]?.contextType == "String")
        #expect(unit.helpers["base"]?.contextType == nil)
    }

    @Test("A module is still a module, and a query inside it is a helper")
    func moduleUnchanged() async throws {
        let unit = try await ATLParser().parseContent(
            "module M;\ncreate OUT : T from IN : S;\nquery Total = 42;\n")
        #expect(unit.kind == .module)
        #expect(!unit.isQuery)
        #expect(unit.queryBody == nil)
        #expect(unit.helpers["Total"] != nil)
        #expect(Array(unit.sourceMetamodels.keys) == ["IN"])
        #expect(Array(unit.targetMetamodels.keys) == ["OUT"])
    }

    @Test(
        "Malformed query units are rejected",
        arguments: [
            "query Q 1;",
            "query Q = 1",
            "query = 1;",
            "query Q = ;",
            "query Q = 1;\nquery R = 2;",
            "query Q = 1;\nrule R { from s : S!A to t : T!B }",
            "query Q = 1;\nlazy rule R { from s : S!A to t : T!B }",
            "query Q = 1;\ncreate OUT : T from IN : S;",
            "query Q = 1;\nuses Strings;",
        ])
    func malformed(source: String) async {
        await #expect(throws: ATLParseError.self, "\(source)") {
            try await ATLParser().parseContent(source)
        }
    }

    @Test("A rule in a query unit is reported with a clear message")
    func ruleMessage() async {
        await #expect {
            try await ATLParser().parseContent(
                "query Q = 1;\nrule R { from s : S!A to t : T!B }")
        } throws: { error in
            guard case .invalidSyntax(let message)? = error as? ATLParseError else { return false }
            return message.contains("query unit") && message.contains("rule")
        }
    }

    @Test("A library unit is still unsupported")
    func libraryUnsupported() async {
        await #expect {
            try await ATLParser().parseContent("library Strings;\nhelper def : x : Integer = 1;")
        } throws: { error in
            guard case .unsupportedConstruct? = error as? ATLParseError else { return false }
            return true
        }
    }

    @Test("The metamodels named by directives become the source metamodels of a query")
    func directiveMetamodels() async throws {
        let unit = try await QueryFixtures.parse(
            QueryFixtures.libraryPath + "query Books = Library!Book.allInstances()->size();")
        #expect(Array(unit.sourceMetamodels.keys) == ["Library"])
        let package = try #require(unit.sourceMetamodels["Library"])
        #expect(package.getClassifier("Book") is EClass)
        #expect(unit.declaredMetamodelNames["Library"] == "Library")
        #expect(unit.targetMetamodels.isEmpty)
    }

    @Test("A query unit file is parsed from its location")
    func parseFile() async throws {
        let unit = try await ATLParser().parse(try QueryFixtures.url("LibraryGraph.atl"))
        #expect(unit.kind == .query)
        #expect(unit.name == "LibraryGraph")
        #expect(unit.sourceMetamodels["Library"]?.getClassifier("Shelf") is EClass)
        #expect(unit.helpers["edges"] != nil)
    }

    @Test("Diagnosing a query unit outlines the query with its helpers")
    func diagnosingOutline() async throws {
        let source = "query Q = thisModule.f();\nhelper def : f() : Integer = 1;\n"
        let result = await ATLParser().parseDiagnosing(source, name: "Q.atl")
        #expect(result.diagnostics.isEmpty)
        #expect(result.module?.kind == .query)
        let root = try #require(result.outline.first)
        #expect(root.kind == ATLOutlineKind.query)
        #expect(root.name == "Q")
        #expect(root.children.map(\.kind) == [ATLOutlineKind.helper])
    }

    @Test("Diagnosing a query unit reports a rule and keeps the helpers")
    func diagnosingRule() async throws {
        let source =
            "query Q = 1;\nrule R { from s : S!A to t : T!B }\nhelper def : f() : Integer = 1;\n"
        let result = await ATLParser().parseDiagnosing(source, name: "Q.atl")
        #expect(result.diagnostics.map(\.code) == [ATLDiagnosticCode.invalidSyntax.rawValue])
        #expect(result.module?.kind == .query)
        #expect(result.module?.helpers["f"] != nil)
        #expect(result.module?.matchedRules.isEmpty == true)
    }

    @Test("Diagnosing a query unit with a malformed body still yields a query")
    func diagnosingMalformedBody() async throws {
        let result = await ATLParser().parseDiagnosing(
            "query Q = ;\nhelper def : f() : Integer = 1;\n", name: "Q.atl")
        #expect(!result.diagnostics.isEmpty)
        #expect(result.module?.kind == .query)
        #expect(result.module?.helpers["f"] != nil)
    }

    @Test("Units of different kinds are not equal")
    func equality() async throws {
        let query = try await ATLParser().parseContent("query Q = 1;")
        let other = try await ATLParser().parseContent("query Q = 2;")
        let same = try await ATLParser().parseContent("query Q = 1;")
        #expect(query == same)
        #expect(query.hashValue == same.hashValue)
        #expect(query != other)
    }
}

// MARK: - Execution

/// Tests for evaluating ATL query units.
@Suite("ATL Query Execution")
@MainActor
struct ATLQueryExecutionTests {

    /// Evaluates a query without input models.
    private func evaluate(_ source: String) async throws -> (any EcoreValue)? {
        let unit = try await ATLParser().parseContent(source)
        return try await ATLVirtualMachine(module: unit).evaluateQuery(sources: [:])
    }

    /// Evaluates a library query with the library model bound under the metamodel name.
    private func evaluateLibrary(_ body: String) async throws -> (any EcoreValue)? {
        let unit = try await QueryFixtures.parse(QueryFixtures.libraryPath + body)
        let package = try #require(unit.sourceMetamodels["Library"])
        let model = try await QueryFixtures.library(conformingTo: package)
        return try await ATLVirtualMachine(module: unit).evaluateQuery(sources: ["Library": model])
    }

    @Test("A query returns the value of its expression")
    func literalValue() async throws {
        #expect(try await evaluate("query Q = 1 + 2;") as? Int == 3)
        #expect(try await evaluate("query Q = 'a' + 'b';") as? String == "ab")
        #expect(try await evaluate("query Q = 3 > 2;") as? Bool == true)
        #expect(try await evaluate("query Q = OclUndefined;") == nil)
    }

    @Test("A query calls its helpers through thisModule and on values")
    func helpers() async throws {
        let value = try await evaluate(
            """
            query Q = thisModule.double(thisModule.base) + 'x'.width();
            helper def : double(x : Integer) : Integer = x * 2;
            helper def : base : Integer = 20;
            helper context String def : width() : Integer = self.size() + 1;
            """)
        #expect(value as? Int == 42)
    }

    @Test("A query reads the parameters declared by its header")
    func parameters() async throws {
        let unit = try await ATLParser().parseContent(
            "-- @param greeting : String = 'Hello'\nquery Q = thisModule.greeting + '!';")
        let vm = ATLVirtualMachine(module: unit)
        #expect(try await vm.evaluateQuery(sources: [:]) as? String == "Hello!")
        let custom = try await vm.evaluateQuery(sources: [:], parameters: ["greeting": "Hi"])
        #expect(custom as? String == "Hi!")
    }

    @Test("A query navigates its input model")
    func navigation() async throws {
        #expect(try await evaluateLibrary("query Q = Library!Book.allInstances()->size();") as? Int == 3)
        let pages = try await evaluateLibrary(
            "query Q = Library!Book.allInstances()->collect(b | b.pages)->sum();")
        #expect(pages as? Int == 1282)
        let names = try await evaluateLibrary(
            """
            query Q = Library!Shelf.allInstances()->iterate(s; text : String = '' |
                text + s.name + ':' + s.books->size().toString() + ' ');
            """)
        #expect(names as? String == "Fiction:2 Science:1 ")
    }

    @Test("A many-valued feature holding one element navigates as a collection")
    func singleElementCollection() async throws {
        let titles = try await evaluateLibrary(
            """
            query Q = Library!Shelf.allInstances()->iterate(s; text : String = '' |
                text + s.books->iterate(b; t : String = '' | t + b.title + ' '));
            """)
        #expect(titles as? String == "Dune Emma Cosmos ")
        let science = try await evaluateLibrary(
            "query Q = Library!Shelf.allInstances()->last().books->first().title;")
        #expect(science as? String == "Cosmos")
    }

    @Test("A query uses context helpers on model elements")
    func contextHelpers() async throws {
        let value = try await evaluateLibrary(
            """
            query Q = Library!Book.allInstances()->select(b | b.isLong)->collect(b | b.title)
                ->asSequence()->first();
            helper context Library!Book def : isLong : Boolean = self.pages > 450;
            """)
        #expect(value as? String == "Emma")
    }

    @Test("Input models can be declared with their own names")
    func declaredModels() async throws {
        let unit = try await QueryFixtures.parse(
            QueryFixtures.libraryPath
                + "query Q = Library!Book.allInstancesFrom('IN')->size() + Library!Book.allInstances()->size();"
        )
        let package = try #require(unit.sourceMetamodels["Library"])
        let bound = unit.declaringSourceModels(["IN": "Library"])
        #expect(Array(bound.sourceMetamodels.keys) == ["IN"])
        #expect(bound.declaredMetamodelNames["IN"] == "Library")
        #expect(bound.sourceMetamodels["IN"] == package)
        #expect(bound.isQuery)
        let model = try await QueryFixtures.library(conformingTo: package)
        let value = try await ATLVirtualMachine(module: bound).evaluateQuery(sources: ["IN": model])
        #expect(value as? Int == 6)
    }

    @Test("Declared input models take explicitly supplied metamodel packages")
    func declaredModelsWithPackages() async throws {
        let unit = try await ATLParser().parseContent(
            "query Q = Library!Book.allInstances()->size();")
        #expect(unit.sourceMetamodels.isEmpty)
        let package = try await EPackage(url: try QueryFixtures.url("Library.ecore"))
        let bound = unit.declaringSourceModels(["IN": "Library"], metamodels: ["Library": package])
        #expect(bound.sourceMetamodels["IN"] == package)
        let model = try await QueryFixtures.library(conformingTo: package)
        let value = try await ATLVirtualMachine(module: bound).evaluateQuery(sources: ["IN": model])
        #expect(value as? Int == 3)
    }

    @Test("A missing input model is reported")
    func missingModel() async throws {
        let unit = try await QueryFixtures.parse(QueryFixtures.libraryPath + "query Q = 1;")
        await #expect {
            try await ATLVirtualMachine(module: unit).evaluateQuery(sources: [:])
        } throws: { invalidOperation($0)?.contains("Library") == true }
    }

    @Test("An input model the query does not declare is reported")
    func unknownModel() async throws {
        let unit = try await ATLParser().parseContent("query Q = 1;")
        await #expect {
            try await ATLVirtualMachine(module: unit).evaluateQuery(sources: ["OTHER": Resource()])
        } throws: { invalidOperation($0)?.contains("OTHER") == true }
    }

    @Test("A module cannot be evaluated as a query")
    func moduleIsNotAQuery() async throws {
        let unit = try await ATLParser().parseContent(
            "module M;\ncreate OUT : T from IN : S;\nquery Total = 42;\n")
        await #expect {
            try await ATLVirtualMachine(module: unit).evaluateQuery(sources: ["IN": Resource()])
        } throws: { invalidOperation($0)?.contains("not a query") == true }
    }

    @Test("Errors in the query expression are thrown and recorded")
    func failingQuery() async throws {
        let unit = try await ATLParser().parseContent("query Q = 1 / 0;")
        let vm = ATLVirtualMachine(module: unit)
        await #expect(throws: (any Error).self) {
            try await vm.evaluateQuery(sources: [:])
        }
        #expect(vm.getStatistics().successful == false)
    }

    @Test("A query can be evaluated more than once")
    func repeatedEvaluation() async throws {
        let unit = try await ATLParser().parseContent(
            "query Q = thisModule.n;\nhelper def : n : Integer = 7;")
        let vm = ATLVirtualMachine(module: unit)
        #expect(try await vm.evaluateQuery(sources: [:]) as? Int == 7)
        #expect(try await vm.evaluateQuery(sources: [:]) as? Int == 7)
        #expect(vm.getStatistics().successful)
    }

    @Test("Query values are rendered as ATL writes them")
    func rendering() async throws {
        #expect(ATLValueText.render(try await evaluate("query Q = Sequence{1, 'a'};")) == "Sequence{1, 'a'}")
        #expect(ATLValueText.render(try await evaluate("query Q = 'text';")) == "'text'")
        #expect(ATLValueText.render(try await evaluate("query Q = OclUndefined;")) == "OclUndefined")
        #expect(ATLValueText.render(true) == "true")
    }

    @Test("A query writes a Graphviz file built from its model")
    func graphvizQuery() async throws {
        let unit = try await ATLParser().parse(try QueryFixtures.url("LibraryGraph.atl"))
        let package = try #require(unit.sourceMetamodels["Library"])
        let model = try await QueryFixtures.library(conformingTo: package)
        let directory = try QueryFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let vm = ATLVirtualMachine(module: unit, fileOutput: .confined(to: directory))
        let value = try await vm.evaluateQuery(sources: ["Library": model])
        #expect(value as? Bool == true)
        let text = try String(
            contentsOf: directory.appendingPathComponent("library.dot"), encoding: .utf8)
        #expect(
            text == """
                digraph "City Library" {
                  "Fiction" -> "Dune";
                  "Fiction" -> "Emma";
                  "Science" -> "Cosmos";
                }

                """)
    }
}
