//
//  ATLModuleParameterTests.swift
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

/// Tests for module parameters declared with `-- @param` and read as `thisModule.<name>`.
@Suite("ATL Module Parameter Tests")
@MainActor
struct ATLModuleParameterTests {

    private let header = """
        -- @param basePackage : String = 'org.example'
        -- @param retries : Integer = 3
        -- @param verbose : Boolean = false
        -- @param scale : Real = 1.5
        -- @param projectName : String
        """

    private func harness(
        directives: String? = nil, expression: String = "OclUndefined"
    ) async throws -> LanguageHarness {
        try await LanguageHarness.make(
            expression: expression, directives: directives ?? header)
    }

    // MARK: - Declaration

    @Test("Declarations are parsed with their types and defaults")
    func declarations() async throws {
        let module = try await harness().module
        #expect(
            module.parameters == [
                ATLModuleParameter(name: "basePackage", type: .string, defaultValue: .string("org.example")),
                ATLModuleParameter(name: "retries", type: .integer, defaultValue: .integer(3)),
                ATLModuleParameter(name: "verbose", type: .boolean, defaultValue: .boolean(false)),
                ATLModuleParameter(name: "scale", type: .real, defaultValue: .real(1.5)),
                ATLModuleParameter(name: "projectName", type: .string),
            ])
        #expect(module.parameters.last?.isRequired == true)
        #expect(module.parameters.first?.isRequired == false)
    }

    @Test(
        "String defaults accept quotes, escapes, empty values and bare text",
        arguments: [
            ("'it\\'s'", "it's"), ("''", ""), ("bare words", "bare words"), ("'a = b'", "a = b"),
            ("'x: y'", "x: y"),
        ])
    func stringDefaults(text: String, expected: String) async throws {
        let module = try await harness(directives: "-- @param name : String = \(text)").module
        #expect(module.parameters.first?.defaultValue == .string(expected))
    }

    @Test(
        "Malformed declarations are reported",
        arguments: [
            "-- @param name",
            "-- @param : String",
            "-- @param bad name : String",
            "-- @param name : Date = 1",
            "-- @param n : Integer = three",
            "-- @param b : Boolean = maybe",
            "-- @param r : Real = x",
            "-- @param n : Integer = 1\n-- @param n : Integer = 2",
        ])
    func malformedDeclarations(directive: String) async {
        await #expect(throws: ATLParseError.self) {
            _ = try await LanguageHarness.make(directives: directive)
        }
    }

    @Test("Boolean defaults are case-insensitive")
    func booleanDefaults() async throws {
        let module = try await harness(directives: "-- @param flag : Boolean = TRUE").module
        #expect(module.parameters.first?.defaultValue == .boolean(true))
    }

    @Test("A module without declarations has no parameters")
    func noParameters() async throws {
        let module = try await harness(directives: "-- just a comment").module
        #expect(module.parameters.isEmpty)
    }

    // MARK: - Access

    @Test("Supplied values are read as thisModule attributes")
    func suppliedValues() async throws {
        let harness = try await harness(expression: "thisModule.basePackage + '.' + thisModule.projectName")
        try harness.context.setModuleParameters(["basePackage": "org.acme", "projectName": "demo"])
        let result = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        #expect(result as? String == "org.acme.demo")
    }

    @Test("Defaults apply to parameters that are not supplied")
    func defaults() async throws {
        let harness = try await harness(
            expression: "thisModule.retries + 1")
        try harness.context.setModuleParameters(["projectName": "demo"])
        let result = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        #expect(result as? Int == 4)
    }

    @Test("Every type is readable", arguments: [
        ("thisModule.basePackage", "org.example" as any EcoreValue),
        ("thisModule.retries", 3 as any EcoreValue),
        ("thisModule.verbose", false as any EcoreValue),
        ("thisModule.scale", 1.5 as any EcoreValue),
    ])
    func allTypes(expression: String, expected: any EcoreValue) async throws {
        let harness = try await harness(expression: expression)
        try harness.context.setModuleParameters(["projectName": "demo"])
        let result = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        #expect(ATLValues.areEqual(result, expected))
    }

    @Test("Parameters can drive conditionals")
    func conditional() async throws {
        let harness = try await harness(
            expression: "if thisModule.verbose then 'loud' else 'quiet' endif")
        try harness.context.setModuleParameters(["verbose": true, "projectName": "p"])
        let loud = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        #expect(loud as? String == "loud")
    }

    @Test("Integers are accepted for real parameters")
    func integerForReal() async throws {
        let harness = try await harness(expression: "thisModule.scale")
        try harness.context.setModuleParameters(["scale": 2, "projectName": "p"])
        let result = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        #expect(result as? Double == 2.0)
    }

    @Test("Reading before any values are set uses the defaults, and fails for required ones")
    func readingWithoutSetting() async throws {
        let harness = try await harness(expression: "thisModule.retries")
        let result = try await harness.context.callHelper(LanguageHarness.probeName, arguments: [])
        #expect(result as? Int == 3)

        let required = ATLNavigationExpression(
            source: ATLVariableExpression(name: "thisModule"), property: "projectName")
        await #expect {
            _ = try await required.evaluate(in: harness.context)
        } throws: { error in
            if case ATLExecutionError.missingParameter("projectName") = error { return true }
            return false
        }
    }

    // MARK: - Validation

    @Test("A missing required parameter is a clear error")
    func missingRequired() async throws {
        let harness = try await harness()
        await #expect {
            try harness.context.setModuleParameters(["basePackage": "x"])
        } throws: { error in
            guard case ATLExecutionError.missingParameter("projectName") = error else { return false }
            return (error as? ATLExecutionError)?.errorDescription?.contains("projectName") == true
        }
    }

    @Test("An undeclared parameter is rejected")
    func undeclared() async throws {
        let harness = try await harness()
        await #expect {
            try harness.context.setModuleParameters(["projectName": "p", "typo": 1])
        } throws: { error in
            guard case ATLExecutionError.unknownParameter("typo") = error else { return false }
            return (error as? ATLExecutionError)?.errorDescription?.contains("@param typo") == true
        }
    }

    @Test(
        "A value of the wrong type is rejected",
        arguments: [
            ["projectName": 5 as any EcoreValue],
            ["projectName": "p" as any EcoreValue, "retries": "three" as any EcoreValue],
            ["projectName": "p" as any EcoreValue, "verbose": 1 as any EcoreValue],
            ["projectName": "p" as any EcoreValue, "scale": "big" as any EcoreValue],
            ["projectName": "p" as any EcoreValue, "retries": 1.5 as any EcoreValue],
        ])
    func wrongType(values: [String: any EcoreValue]) async throws {
        let harness = try await harness()
        await #expect {
            try harness.context.setModuleParameters(values)
        } throws: { error in
            if case ATLExecutionError.typeError = error { return true }
            return false
        }
    }

    // MARK: - Text conversion

    @Test("Textual values convert to the declared types")
    func textConversion() async throws {
        let module = try await harness().module
        let values = try module.parameterValues(fromText: [
            "basePackage": "org.text", "retries": "7", "verbose": "TRUE", "scale": "2.25",
            "projectName": "demo",
        ])
        #expect(values["basePackage"] as? String == "org.text")
        #expect(values["retries"] as? Int == 7)
        #expect(values["verbose"] as? Bool == true)
        #expect(values["scale"] as? Double == 2.25)
    }

    @Test(
        "Malformed textual values and unknown names are rejected",
        arguments: [["retries": "x"], ["verbose": "yes"], ["scale": "x"], ["nope": "1"]])
    func textConversionErrors(text: [String: String]) async throws {
        let module = try await harness().module
        #expect(throws: ATLExecutionError.self) {
            _ = try module.parameterValues(fromText: text)
        }
    }

    @Test("Parameter values expose their representation")
    func parameterValueRepresentation() {
        #expect(ATLParameterValue.string("a").ecoreValue as? String == "a")
        #expect(ATLParameterValue.integer(1).ecoreValue as? Int == 1)
        #expect(ATLParameterValue.boolean(true).ecoreValue as? Bool == true)
        #expect(ATLParameterValue.real(0.5).ecoreValue as? Double == 0.5)
    }

    // MARK: - Virtual machine

    @Test("The virtual machine binds parameters for the whole execution")
    func virtualMachineExecution() async throws {
        let fixture = ShapeFixture()
        let source = """
            -- @param prefix : String = 'copy of '
            -- @param radiusScale : Integer
            module Scaled;
            create OUT : Shapes from IN : Shapes;
            rule Circle2Circle {
                from s : Shapes!Circle
                to t : Shapes!Circle (
                    name <- thisModule.prefix + s.name,
                    radius <- s.radius * thisModule.radiusScale
                )
            }
            """
        let registry = ATLMetamodelRegistry(packages: [fixture.package])
        let module = try await ATLParser().parseContent(source, metamodelRegistry: registry)
        let input = Resource(uri: "test://in")
        await input.add(fixture.make(fixture.circle, ["name": "c", "radius": 2.0]))

        // Missing required parameter
        let vm = ATLVirtualMachine(module: module)
        await #expect {
            try await vm.execute(
                sources: ["IN": input], targets: ["OUT": Resource(uri: "test://out0")])
        } throws: { error in
            if case ATLExecutionError.missingParameter("radiusScale") = error { return true }
            return false
        }

        let output = Resource(uri: "test://out")
        try await ATLVirtualMachine(module: module).execute(
            sources: ["IN": input], targets: ["OUT": output],
            parameters: ["radiusScale": 3])
        let created = try #require(await output.getAllInstancesOf(fixture.circle).first as? DynamicEObject)
        #expect(created.eGet("name") as? String == "copy of c")
        #expect(created.eGet("radius") as? Double == 6.0)
    }
}
