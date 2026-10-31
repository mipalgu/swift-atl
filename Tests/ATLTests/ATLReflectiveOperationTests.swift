//
//  ATLReflectiveOperationTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 20/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import OrderedCollections
import Testing

@testable import ATL

// MARK: - Harness

/// Collects the lines written by the console operations `debug` and `println`.
@MainActor
final class ConsoleCapture {
    /// The lines written to standard output.
    var output: [String] = []

    /// The lines written to standard error.
    var errors: [String] = []

    /// A console that records its lines in this capture.
    var console: ATLConsole {
        ATLConsole(
            writeOutput: { [unowned self] in self.output.append($0) },
            writeError: { [unowned self] in self.errors.append($0) })
    }
}

/// Evaluates an expression with the populated semantics models registered as live models.
///
/// Unlike ``LanguageHarness``, the source and target models are registered with the
/// execution engine, so containment navigation and target element updates behave as
/// they do while a transformation runs.
@MainActor
struct ReflectiveHarness {
    /// The models and metamodels.
    let fixture: SemanticsFixture

    /// The execution context with the models registered.
    let context: ATLExecutionContext

    /// The captured console output.
    let capture = ConsoleCapture()

    /// Creates a harness whose probe helper evaluates an expression.
    ///
    /// - Parameters:
    ///   - expression: The expression the probe helper evaluates.
    ///   - declarations: Helper declarations that precede the probe.
    static func make(_ expression: String, declarations: String = "") async throws
        -> ReflectiveHarness
    {
        var fixture = SemanticsFixture()
        await fixture.populate()
        let parsed = try await ATLParser().parseContent(
            "module Test;\ncreate OUT : Tgt from IN : Src;\n" + declarations
                + "\nhelper def : \(LanguageHarness.probeName)() : OclAny = \(expression);\n")
        let module = ATLModule(
            name: parsed.name, sourceMetamodels: ["IN": fixture.source],
            targetMetamodels: ["OUT": fixture.target], helpers: parsed.helpers,
            helperOverloads: parsed.helperOverloads)
        let context = ATLExecutionContext(
            module: module, executionEngine: ECoreExecutionEngine(models: [:]))
        await context.executionEngine.enableDefaultValues()
        await context.addSource("IN", resource: fixture.sourceResource)
        await context.addTarget("OUT", resource: fixture.targetResource)
        let harness = ReflectiveHarness(fixture: fixture, context: context)
        context.console = harness.capture.console
        return harness
    }

    /// Evaluates the probe expression with variables bound.
    ///
    /// - Parameter variables: The variables visible to the expression.
    /// - Returns: The value of the expression.
    @discardableResult
    func evaluate(_ variables: [String: any EcoreValue] = [:]) async throws -> (any EcoreValue)? {
        for (name, value) in variables {
            context.setVariable(name, value: value)
        }
        return try await context.callHelper(LanguageHarness.probeName, arguments: [])
    }

    /// Creates a target element of a class of the target metamodel.
    ///
    /// - Parameter className: The class name.
    /// - Returns: The created element.
    func makeTarget(_ className: String) async throws -> any EObject {
        try await context.createElement(type: "Tgt!\(className)", in: "Tgt")
    }

    /// The current value of a feature of a target element.
    ///
    /// - Parameters:
    ///   - element: The target element.
    ///   - feature: The feature name.
    /// - Returns: The stored value.
    func stored(_ element: any EObject, _ feature: String) async -> (any EcoreValue)? {
        (await fixture.targetResource.getObject(element.id) as? DynamicEObject)?.eGet(feature)
    }
}

/// Whether an error is an execution error of the expected kind.
///
/// - Parameters:
///   - error: The thrown error.
///   - kind: Extracts the message of the expected case, or `nil` for another case.
///   - text: Text the message must contain.
/// - Returns: `true` when the error matches.
private func isExecutionError(
    _ error: any Error, _ kind: (ATLExecutionError) -> String?, containing text: String = ""
) -> Bool {
    guard let error = error as? ATLExecutionError, let message = kind(error) else { return false }
    return text.isEmpty || message.contains(text)
}

/// Extracts the message of a type error.
private func typeErrorMessage(_ error: ATLExecutionError) -> String? {
    guard case .typeError(let message) = error else { return nil }
    return message
}

/// Extracts the message of an invalid operation error.
private func invalidOperationMessage(_ error: ATLExecutionError) -> String? {
    guard case .invalidOperation(let message) = error else { return nil }
    return message
}

// MARK: - Containment

@Suite("ATL Reflective Operation Tests")
@MainActor
struct ATLReflectiveOperationTests {

    @Test("refImmediateComposite answers the container of a source element")
    func immediateCompositeOfSourceElement() async throws {
        let harness = try await ReflectiveHarness.make("n.refImmediateComposite()")
        let container = try await harness.evaluate(["n": harness.fixture.alpha])
        #expect((container as? any EObject)?.id == harness.fixture.holder.id)
    }

    @Test("refImmediateComposite of a root element is the undefined value")
    func immediateCompositeOfRoot() async throws {
        let harness = try await ReflectiveHarness.make("n.refImmediateComposite().oclIsUndefined()")
        #expect(try await harness.evaluate(["n": harness.fixture.holder]) as? Bool == true)
    }

    @Test("refImmediateComposite agrees with the eContainer property")
    func immediateCompositeMatchesProperty() async throws {
        let harness = try await ReflectiveHarness.make("n.refImmediateComposite() = n.eContainer")
        #expect(try await harness.evaluate(["n": harness.fixture.leafAlpha]) as? Bool == true)
    }

    @Test("Method forms of the containment properties answer as the properties do")
    func containmentMethodForms() async throws {
        for (expression, check) in [
            ("n.eContainer() = n.eContainer", true),
            ("n.eContainingFeature().name = 'items'", true),
            ("n.eContainingFeature().name = n.eContainingFeature.name", true),
            ("h.eContents()->size() = 6", true),
            ("h.eContents()->size() = h.eContents->size()", true),
            ("h.eAllContents()->size() = h.eAllContents->size()", true),
            ("h.eAllContents()->includes(n)", true),
            ("h.eContainer().oclIsUndefined()", true),
        ] {
            let harness = try await ReflectiveHarness.make(expression)
            let result = try await harness.evaluate([
                "n": harness.fixture.alpha, "h": harness.fixture.holder,
            ])
            #expect(result as? Bool == check, "\(expression)")
        }
    }

    @Test("Containment method forms are not offered for values that are not model elements")
    func containmentMethodFormsNeedObjects() async throws {
        let harness = try await ReflectiveHarness.make("5.eContainer()")
        await #expect(throws: ATLExecutionError.self) {
            try await harness.evaluate()
        }
    }

    @Test(
        "Reflective operations are not offered for other receivers or argument counts",
        arguments: [
            "n.refGetValue()", "n.refSetValue('name')", "n.refImmediateComposite(1)",
            "5.refGetValue('name')", "'text'.refImmediateComposite()",
            "OclUndefined.refInvokeOperation('kind', Sequence{})", "5.newInstance()",
            "n.debug()",
        ])
    func unsupportedForms(expression: String) async throws {
        let harness = try await ReflectiveHarness.make(expression)
        await #expect(throws: ATLExecutionError.self, "\(expression)") {
            try await harness.evaluate(["n": harness.fixture.alpha])
        }
    }

    // MARK: - Reading features

    @Test("refGetValue reads attributes and references like navigation")
    func getValue() async throws {
        let harness = try await ReflectiveHarness.make(
            "Sequence{n.refGetValue('name'), n.refGetValue('kids')->size(), n.refGetValue('next').name}")
        let result = try await harness.evaluate(["n": harness.fixture.alpha])
        let elements = try #require(result.collectionElements)
        #expect(elements.count == 3)
        #expect(elements[0] as? String == "alpha")
        #expect(elements[1] as? Int == 2)
        #expect(elements[2] as? String == "beta")
    }

    @Test("refGetValue reads the current state of a target element")
    func getValueOfTarget() async throws {
        let harness = try await ReflectiveHarness.make("t.refGetValue('tag')")
        let target = try await harness.makeTarget("TNode")
        try await harness.context.assignFeature(on: target, feature: "tag", value: "fresh")
        #expect(try await harness.evaluate(["t": target]) as? String == "fresh")
    }

    @Test("refGetValue requires a String feature name")
    func getValueNeedsString() async throws {
        let harness = try await ReflectiveHarness.make("n.refGetValue(1)")
        await #expect {
            try await harness.evaluate(["n": harness.fixture.alpha])
        } throws: { error in
            isExecutionError(error, typeErrorMessage, containing: "refGetValue")
        }
    }

    @Test("refGetValue of an unknown feature fails as navigation does")
    func getValueOfUnknownFeature() async throws {
        let navigation = try await ReflectiveHarness.make("n.bogus")
        await #expect(throws: (any Error).self) {
            try await navigation.evaluate(["n": navigation.fixture.alpha])
        }
        let reflective = try await ReflectiveHarness.make("n.refGetValue('bogus')")
        await #expect(throws: (any Error).self) {
            try await reflective.evaluate(["n": reflective.fixture.alpha])
        }
    }

    // MARK: - Writing features

    @Test("refSetValue sets a feature of a target element and returns the element")
    func setValue() async throws {
        let harness = try await ReflectiveHarness.make(
            "t.refSetValue('tag', 'set').refSetValue('count', 3)")
        let target = try await harness.makeTarget("TNode")
        let result = try await harness.evaluate(["t": target])
        #expect((result as? any EObject)?.id == target.id)
        #expect(await harness.stored(target, "tag") as? String == "set")
        #expect(await harness.stored(target, "count") as? Int == 3)
    }

    @Test("refSetValue stores model elements as references")
    func setValueStoresReferences() async throws {
        let harness = try await ReflectiveHarness.make("t.refSetValue('next', u)")
        let target = try await harness.makeTarget("TNode")
        let other = try await harness.makeTarget("TNode")
        try await harness.evaluate(["t": target, "u": other])
        #expect(await harness.stored(target, "next") as? EUUID == other.id)
    }

    @Test("refSetValue checks enumeration literals")
    func setValueChecksEnumerations() async throws {
        let shapes = ShapeFixture()
        let parsed = try await ATLParser().parseContent(
            """
            module Test;
            create OUT : Shapes from IN : Shapes;
            helper def : probe() : OclAny = c.refSetValue('visibility', v);
            """)
        let module = ATLModule(
            name: parsed.name, sourceMetamodels: ["IN": shapes.package],
            targetMetamodels: ["OUT": shapes.package], helpers: parsed.helpers)
        let context = ATLExecutionContext(
            module: module, executionEngine: ECoreExecutionEngine(models: [:]))
        await context.executionEngine.enableDefaultValues()
        let target = Resource(uri: "test://shapes")
        await context.addSource("IN", resource: Resource(uri: "test://empty"))
        await context.addTarget("OUT", resource: target)
        let circle = try await context.createElement(type: "Shapes!Circle", in: "Shapes")
        context.setVariable("c", value: circle)

        context.setVariable("v", value: "Private")
        _ = try await context.callHelper("probe", arguments: [])
        #expect((await target.getObject(circle.id) as? DynamicEObject)?.eGet("visibility") as? String == "Private")

        context.setVariable("v", value: "Bogus")
        await #expect {
            _ = try await context.callHelper("probe", arguments: [])
        } throws: { error in
            guard case ATLExecutionError.invalidEnumerationLiteral = error else { return false }
            return true
        }
    }

    @Test("refSetValue rejects source elements because source models are read-only")
    func setValueOnSourceIsReadOnly() async throws {
        let harness = try await ReflectiveHarness.make("n.refSetValue('name', 'changed')")
        await #expect {
            try await harness.evaluate(["n": harness.fixture.alpha])
        } throws: { error in
            isExecutionError(error, invalidOperationMessage, containing: "read-only")
        }
        let stored = await harness.fixture.sourceResource.getObject(harness.fixture.alpha.id)
        #expect((stored as? DynamicEObject)?.eGet("name") as? String == "alpha")
    }

    @Test("refSetValue requires a String feature name")
    func setValueNeedsString() async throws {
        let harness = try await ReflectiveHarness.make("t.refSetValue(true, 'x')")
        let target = try await harness.makeTarget("TNode")
        await #expect {
            try await harness.evaluate(["t": target])
        } throws: { error in
            isExecutionError(error, typeErrorMessage, containing: "refSetValue")
        }
    }

    @Test("refSetValue of an unknown feature is reported")
    func setValueOfUnknownFeature() async throws {
        let harness = try await ReflectiveHarness.make("t.refSetValue('bogus', 'x')")
        let target = try await harness.makeTarget("TNode")
        await #expect {
            try await harness.evaluate(["t": target])
        } throws: { error in
            isExecutionError(error, invalidOperationMessage, containing: "bogus")
        }
    }

    @Test("refUnsetValue clears single-valued features and empties many-valued ones")
    func unsetValue() async throws {
        let harness = try await ReflectiveHarness.make(
            "t.refUnsetValue('tag').refUnsetValue('kids').refUnsetValue('next')")
        let target = try await harness.makeTarget("TNode")
        let other = try await harness.makeTarget("TNode")
        try await harness.context.assignFeature(on: target, feature: "tag", value: "x")
        try await harness.context.assignFeature(on: target, feature: "next", value: other)
        try await harness.context.assignFeature(
            on: target, feature: "kids", value: EcoreValueArray([other]))
        #expect(await harness.stored(target, "kids") as? [EUUID] == [other.id])

        let result = try await harness.evaluate(["t": target])
        #expect((result as? any EObject)?.id == target.id)
        #expect(await harness.stored(target, "tag") == nil)
        #expect(await harness.stored(target, "next") == nil)
        #expect(await harness.stored(target, "kids") as? [EUUID] == [])
    }

    @Test("refUnsetValue restores the default of single-valued primitive attributes")
    func unsetValueRestoresDefaults() async throws {
        let gauge = EClass(
            name: "Gauge",
            eStructuralFeatures: [
                EAttribute(name: "level", eType: EDataType(name: "EInt")),
                EAttribute(name: "active", eType: EDataType(name: "EBoolean")),
                EAttribute(name: "ratio", eType: EDataType(name: "EDouble")),
                EAttribute(name: "limit", eType: EDataType(name: "EInt"), defaultValueLiteral: "7"),
                EAttribute(name: "label", eType: EDataType(name: "EString")),
            ])
        let package = EPackage(
            name: "Gauges", nsURI: "http://example.org/gauges", nsPrefix: "g", eClassifiers: [gauge])
        let parsed = try await ATLParser().parseContent(
            """
            module Test;
            create OUT : Gauges from IN : Gauges;
            helper def : probe() : OclAny =
                g.refUnsetValue('level').refUnsetValue('active').refUnsetValue('ratio')
                    .refUnsetValue('limit').refUnsetValue('label');
            helper def : read() : OclAny = Sequence{
                g.refGetValue('level'), g.refGetValue('active'), g.refGetValue('ratio'),
                g.refGetValue('limit'), g.refGetValue('label').oclIsUndefined()};
            """)
        let module = ATLModule(
            name: parsed.name, sourceMetamodels: ["IN": package], targetMetamodels: ["OUT": package],
            helpers: parsed.helpers)
        let context = ATLExecutionContext(
            module: module, executionEngine: ECoreExecutionEngine(models: [:]))
        await context.executionEngine.enableDefaultValues()
        let target = Resource(uri: "test://gauges")
        await context.addSource("IN", resource: Resource(uri: "test://empty"))
        await context.addTarget("OUT", resource: target)
        let element = try await context.createElement(type: "Gauges!Gauge", in: "Gauges")
        let values: [String: any EcoreValue] = [
            "level": 5, "active": true, "ratio": 2.5, "limit": 9, "label": "dial",
        ]
        for (name, value) in values {
            try await context.assignFeature(on: element, feature: name, value: value)
        }
        context.setVariable("g", value: element)

        _ = try await context.callHelper("probe", arguments: [])
        let stored = try #require(await target.getObject(element.id) as? DynamicEObject)
        #expect(stored.eGet("level") as? Int == 0)
        #expect(stored.eGet("active") as? Bool == false)
        #expect(stored.eGet("ratio") as? Double == 0.0)
        #expect(stored.eGet("limit") as? Int == 7)
        #expect(stored.eGet("label") == nil)

        let read = try await context.callHelper("read", arguments: [])
        let elements = try #require(read.collectionElements)
        #expect(elements.count == 5)
        #expect(elements.first as? Int == 0)
        #expect(elements.dropFirst().first as? Bool == false)
        #expect(elements.dropFirst(2).first as? Double == 0.0)
        #expect(elements.dropFirst(3).first as? Int == 7)
        #expect(elements.last as? Bool == true)
    }

    @Test("refUnsetValue rejects source elements because source models are read-only")
    func unsetValueOnSourceIsReadOnly() async throws {
        let harness = try await ReflectiveHarness.make("n.refUnsetValue('name')")
        await #expect {
            try await harness.evaluate(["n": harness.fixture.alpha])
        } throws: { error in
            isExecutionError(error, invalidOperationMessage, containing: "read-only")
        }
    }

    @Test("refUnsetValue reports unknown features and non-String names")
    func unsetValueErrors() async throws {
        let unknown = try await ReflectiveHarness.make("t.refUnsetValue('bogus')")
        let target = try await unknown.makeTarget("TNode")
        await #expect {
            try await unknown.evaluate(["t": target])
        } throws: { error in
            isExecutionError(error, invalidOperationMessage, containing: "bogus")
        }
        let untyped = try await ReflectiveHarness.make("t.refUnsetValue(3)")
        let other = try await untyped.makeTarget("TNode")
        await #expect {
            try await untyped.evaluate(["t": other])
        } throws: { error in
            isExecutionError(error, typeErrorMessage, containing: "refUnsetValue")
        }
    }

    // MARK: - Invoking helpers

    private static let helpers = """
        helper context Src!Node def : greet(prefix : String) : String = prefix + self.name;
        helper context Src!Node def : kind() : String = 'node';
        helper context Src!Special def : kind() : String = 'special';
        helper context Src!Node def : label : String = 'label ' + self.name;
        helper context OclAny def : tagged() : String = 'any';
        helper def : selfName() : String = self.name;
        helper def : twice(x : Integer) : Integer = x * 2;
        """

    @Test(
        "refInvokeOperation calls the helper selected by the receiver",
        arguments: [
            ("n.refInvokeOperation('greet', Sequence{'hi '})", "hi alpha"),
            ("n.refInvokeOperation('kind', Sequence{})", "node"),
            ("s.refInvokeOperation('kind', Sequence{})", "special"),
            ("n.refInvokeOperation('label', Sequence{})", "label alpha"),
            ("5.refInvokeOperation('tagged', Sequence{})", "any"),
            ("n.refInvokeOperation('tagged', OclUndefined)", "any"),
            ("n.refInvokeOperation('selfName', Sequence{})", "alpha"),
        ])
    func invokeOperation(expression: String, expected: String) async throws {
        let harness = try await ReflectiveHarness.make(expression, declarations: Self.helpers)
        let result = try await harness.evaluate([
            "n": harness.fixture.alpha, "s": harness.fixture.special,
        ])
        #expect(result as? String == expected)
    }

    @Test("refInvokeOperation passes the sequence elements as arguments")
    func invokeOperationArguments() async throws {
        let harness = try await ReflectiveHarness.make(
            "n.refInvokeOperation('twice', Sequence{21})", declarations: Self.helpers)
        #expect(try await harness.evaluate(["n": harness.fixture.alpha]) as? Int == 42)
    }

    @Test("refInvokeOperation leaves self unbound afterwards")
    func invokeOperationRestoresScope() async throws {
        let harness = try await ReflectiveHarness.make(
            "n.refInvokeOperation('selfName', Sequence{})", declarations: Self.helpers)
        try await harness.evaluate(["n": harness.fixture.alpha])
        #expect(throws: ATLExecutionError.self) {
            try harness.context.getVariable(ATLLanguage.selfVariable)
        }
    }

    @Test("refInvokeOperation reports a helper that does not exist")
    func invokeUnknownOperation() async throws {
        let harness = try await ReflectiveHarness.make(
            "n.refInvokeOperation('nope', Sequence{})", declarations: Self.helpers)
        await #expect {
            try await harness.evaluate(["n": harness.fixture.alpha])
        } throws: { error in
            guard case ATLExecutionError.helperNotFound(let name) = error else { return false }
            return name == "nope"
        }
    }

    @Test("refInvokeOperation requires a String operation name")
    func invokeOperationNeedsString() async throws {
        let harness = try await ReflectiveHarness.make("n.refInvokeOperation(1, Sequence{})")
        await #expect {
            try await harness.evaluate(["n": harness.fixture.alpha])
        } throws: { error in
            isExecutionError(error, typeErrorMessage, containing: "refInvokeOperation")
        }
    }

    // MARK: - Console

    @Test("debug writes the message and value to standard error and returns the receiver")
    func debugOperation() async throws {
        let harness = try await ReflectiveHarness.make("(n.name + '!').debug('name').size()")
        #expect(try await harness.evaluate(["n": harness.fixture.alpha]) as? Int == 6)
        #expect(harness.capture.errors == ["name: 'alpha!'"])
        #expect(harness.capture.output.isEmpty)
    }

    @Test("debug works without debugging enabled and for the undefined value")
    func debugUndefined() async throws {
        let harness = try await ReflectiveHarness.make("OclUndefined.debug('nothing')")
        #expect(harness.context.debug == false)
        #expect(try await harness.evaluate() == nil)
        #expect(harness.capture.errors == ["nothing: OclUndefined"])
    }

    @Test("debug requires a String message")
    func debugNeedsString() async throws {
        let harness = try await ReflectiveHarness.make("5.debug(5)")
        await #expect {
            try await harness.evaluate()
        } throws: { error in
            isExecutionError(error, typeErrorMessage, containing: "debug")
        }
    }

    @Test("println writes a String to standard output and returns it")
    func printlnOperation() async throws {
        let harness = try await ReflectiveHarness.make("'hello'.println().size()")
        #expect(try await harness.evaluate() as? Int == 5)
        #expect(harness.capture.output == ["hello"])
        #expect(harness.capture.errors.isEmpty)
    }

    @Test("println is only offered for strings and writeTo is not offered")
    func unsupportedConsoleOperations() async throws {
        for expression in ["5.println()", "'text'.writeTo('out.txt')"] {
            let harness = try await ReflectiveHarness.make(expression)
            await #expect(throws: ATLExecutionError.self, "\(expression)") {
                try await harness.evaluate()
            }
            #expect(harness.capture.output.isEmpty)
        }
    }

    @Test(
        "Values are rendered for the console as ATL writes them",
        arguments: [
            ("'text'", "'text'"),
            ("42", "42"),
            ("2.5", "2.5"),
            ("true", "true"),
            ("OclUndefined", "OclUndefined"),
            ("Sequence{1, 'a'}", "Sequence{1, 'a'}"),
            ("OrderedSet{2, 3}", "OrderedSet{2, 3}"),
            ("Set{}", "Set{}"),
        ])
    func rendering(expression: String, expected: String) async throws {
        let value = try await LanguageHarness.evaluate(expression)
        #expect(ATLReflectiveOperations.render(value) == expected)
    }

    @Test("Model elements are rendered by class and name")
    func renderingObjects() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        #expect(ATLReflectiveOperations.render(fixture.alpha) == "Node 'alpha'")
        #expect(ATLReflectiveOperations.render(fixture.holder) == "Holder")
        #expect(ATLReflectiveOperations.render(fixture.source.getClassifier("Leaf") as? EClass) == "EClass 'Leaf'")
    }

    #if !os(WASI) && !os(Windows)
    /// Writes error lines through the system console and returns what reached its error
    /// descriptor.
    ///
    /// The console writes to a pipe in place of standard error, so that the text written by
    /// tests that run meanwhile neither reaches the pipe nor is lost.
    ///
    /// - Parameter lines: The lines to write.
    /// - Returns: The text written to the error descriptor.
    private func standardErrorText(writing lines: [String]) throws -> String {
        let pipe = Pipe()
        let console = ATLConsole.system(errorDescriptor: pipe.fileHandleForWriting.fileDescriptor)
        for line in lines {
            console.writeError(line)
        }
        try pipe.fileHandleForWriting.close()
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    @Test("The system console writes its error lines to standard error")
    func systemConsoleUsesStandardError() {
        #expect(ATLStandardErrorStream().descriptor == STDERR_FILENO)
    }

    @Test("The system console writes each error line, terminated, to standard error")
    func systemConsoleWritesErrorLines() throws {
        let written = try standardErrorText(writing: ["first console line", "second console line"])
        #expect(written.contains("first console line\nsecond console line\n"))
    }

    @Test("The system console drops error lines that standard error cannot take")
    func systemConsoleToleratesUnwritableStandardError() throws {
        let readOnly = open("/dev/null", O_RDONLY)
        try #require(readOnly >= 0)
        defer { close(readOnly) }
        ATLConsole.system(errorDescriptor: readOnly).writeError("dropped console line")
        let written = try standardErrorText(writing: ["restored console line"])
        #expect(written.contains("restored console line\n"))
        #expect(!written.contains("dropped console line"))
    }
    #endif

    @Test("debug on the default console returns its receiver")
    func debugOnSystemConsole() async throws {
        #expect(try await LanguageHarness.evaluate("5.debug('default console check')") as? Int == 5)
    }

    @Test("println on the default console returns its receiver")
    func printlnOnSystemConsole() async throws {
        #expect(try await LanguageHarness.evaluate("'console check'.println()") as? String == "console check")
    }

    // MARK: - Element creation

    @Test("newInstance creates an element in the target model of its metamodel")
    func newInstance() async throws {
        let harness = try await ReflectiveHarness.make("Tgt!Marker.newInstance()")
        let created = try #require(try await harness.evaluate() as? any EObject)
        #expect(created.eClass.name == "Marker")
        #expect(await harness.fixture.targets("Marker").map(\.id) == [created.id])
    }

    @Test("newInstance elements can be filled in reflectively")
    func newInstanceThenSet() async throws {
        let harness = try await ReflectiveHarness.make(
            "Tgt!Marker.newInstance().refSetValue('label', 'made')")
        try await harness.evaluate()
        let marker = try #require(await harness.fixture.targets("Marker").first)
        #expect(marker.eGet("label") as? String == "made")
    }

    @Test(
        "newInstance needs a qualified class of a target metamodel",
        arguments: ["Src!Node.newInstance()", "'Marker'.newInstance()", "Tgt!Nope.newInstance()"])
    func newInstanceErrors(expression: String) async throws {
        let harness = try await ReflectiveHarness.make(expression)
        await #expect(throws: ATLExecutionError.self) {
            try await harness.evaluate()
        }
        #expect(await harness.fixture.targetResource.getAllObjects().isEmpty)
    }

    // MARK: - Precedence

    @Test("Helpers declared for OclAny override the reflective and console operations")
    func oclAnyHelpersOverride() async throws {
        let harness = try await ReflectiveHarness.make(
            "Sequence{5.debug('x'), n.refGetValue('name'), n.eContents(), 'text'.println()}",
            declarations: """
                helper context OclAny def : debug(s : String) : OclAny = 'mine ' + s;
                helper context OclAny def : refGetValue(f : String) : OclAny = 'own ' + f;
                helper context OclAny def : eContents() : OclAny = 'contents';
                helper context OclAny def : println() : OclAny = 'printed';
                """)
        let result = try await harness.evaluate(["n": harness.fixture.alpha])
        #expect(result.strings == ["mine x", "own name", "contents", "printed"])
        #expect(harness.capture.errors.isEmpty)
        #expect(harness.capture.output.isEmpty)
    }

    @Test("A helper declared for a specific type overrides a reflective operation")
    func specificHelperOverrides() async throws {
        let harness = try await ReflectiveHarness.make(
            "n.refGetValue('name')",
            declarations: "helper context Src!Node def : refGetValue(f : String) : String = 'mine';")
        #expect(try await harness.evaluate(["n": harness.fixture.alpha]) as? String == "mine")
    }
}

// MARK: - Shipped example

/// Runs the shipped reflective operations example over its library model.
@Suite("ATL Reflective Operations Example")
@MainActor
struct ATLReflectiveOperationsExampleTests {

    /// The location of a fixture shipped at the top level of the test resources.
    private func fixtureURL(_ name: String) throws -> URL {
        let resources = try #require(Bundle.module.resourceURL)
        let nested = resources.appendingPathComponent("Resources")
        var isDirectory: ObjCBool = false
        let root =
            FileManager.default.fileExists(atPath: nested.path, isDirectory: &isDirectory)
                && isDirectory.boolValue ? nested : resources
        return root.appendingPathComponent(name)
    }

    /// Transforms the library model into a catalogue.
    private func transformLibrary() async throws -> Resource {
        let module = try await ATLParser().parse(try fixtureURL("ReflectiveOperations.atl"))
        let resourceSet = ResourceSet()
        let library = try #require(module.sourceMetamodels["IN"])
        await resourceSet.registerMetamodel(library, uri: library.nsURI)
        let source = try await XMIParser(resourceSet: resourceSet).parse(
            try fixtureURL("Library.xmi"))
        let target = Resource(uri: "Catalogue.xmi")
        let vm = ATLVirtualMachine(module: module)
        try await vm.execute(sources: ["IN": source], targets: ["OUT": target])
        return target
    }

    /// The target elements of a class.
    private func elements(_ className: String, in resource: Resource) async -> [DynamicEObject] {
        await resource.getAllObjects().compactMap { $0 as? DynamicEObject }
            .filter { $0.eClass.name == className }
    }

    @Test("The example builds one entry per book with reflectively computed values")
    func entries() async throws {
        let target = try await transformLibrary()
        let entries = await elements("Entry", in: target)
        #expect(entries.count == 3)
        let dune = try #require(entries.first { $0.eGet("title") as? String == "Book: Dune" })
        #expect(dune.eGet("shelf") as? String == "Fiction")
        #expect(dune.eGet("location") as? String == "City Library/Fiction")
        #expect(dune.eGet("note") == nil)
        let cosmos = try #require(entries.first { $0.eGet("title") as? String == "Book: Cosmos" })
        #expect(cosmos.eGet("location") as? String == "City Library/Science")
    }

    @Test("The example keeps the containment structure of the library")
    func structure() async throws {
        let target = try await transformLibrary()
        #expect(await target.getRootObjects().count == 1)
        let catalogue = try #require(await elements("Catalogue", in: target).first)
        #expect(catalogue.eGet("name") as? String == "City Library")
        let sections = await elements("Section", in: target)
        #expect(Set(sections.compactMap { $0.eGet("name") as? String }) == ["Fiction", "Science"])
        #expect((catalogue.eGet("sections") as? [EUUID])?.count == 2)
    }
}
