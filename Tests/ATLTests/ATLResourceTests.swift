//
//  ATLResourceTests.swift
//  ATL
//
//  Created by Claude on 10/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
//  Tests for ATL resource framework (load/save, XMI serialization/parsing).
//
import ECore
import Foundation
import OrderedCollections
import Testing
@testable import ATL

/// Tests for ATL resource framework (load/save, XMI serialization/parsing).
@Suite("ATL Resource Tests")
@MainActor
struct ATLResourceTests {

    // MARK: - Test Resources

    /// Returns the path to a test resource file.
    func testResourcePath(_ filename: String) -> String {
        let currentFile = URL(fileURLWithPath: #filePath)
        let resourcesDir = currentFile.deletingLastPathComponent().appendingPathComponent("Resources")
        return resourcesDir.appendingPathComponent(filename).path
    }

    /// Returns a temporary file path for testing.
    func temporaryFilePath(extension ext: String) -> String {
        let tmpDir = FileManager.default.temporaryDirectory
        let filename = UUID().uuidString + "." + ext
        return tmpDir.appendingPathComponent(filename).path
    }

    // MARK: - ATLResource Loading Tests

    @Test("Load ATL file")
    func loadATLFile() async throws {
        // Given: A simple ATL transformation file
        let atlPath = testResourcePath("SimpleTransformation.atl")
        let resource = ATLResource(uri: "file://\(atlPath)")

        // When: Loading the resource
        try await resource.load()

        // Then: Module should be loaded successfully
        #expect(resource.module != nil, "Module should be loaded")
        #expect(resource.module?.name == "SimpleTransformation", "Module name should match")
    }

    @Test("Load complex ATL file")
    func loadComplexATLFile() async throws {
        // Given: A complex ATL transformation with metamodel-qualified types
        let atlPath = testResourcePath("Class2RelationalTransformation.atl")
        let resource = ATLResource(uri: "file://\(atlPath)")

        // When: Loading the resource
        try await resource.load()

        // Then: Module should be loaded with all rules
        #expect(resource.module != nil, "Module should be loaded")
        #expect(resource.module?.name == "Class2RelationalTransformation", "Module name should match")
        #expect(!(resource.module?.matchedRules.isEmpty ?? true), "Should have matched rules")
    }

    @Test("Load helper functions")
    func loadHelperFunctions() async throws {
        // Given: An ATL file with helper functions
        let atlPath = testResourcePath("HelperFunctions.atl")
        let resource = ATLResource(uri: "file://\(atlPath)")

        // When: Loading the resource
        try await resource.load()

        // Then: Helpers should be loaded
        #expect(resource.module != nil, "Module should be loaded")
        #expect(!(resource.module?.helpers.isEmpty ?? true), "Should have helper functions")
    }

    // MARK: - ATLResource Saving Tests

    @Test("Save as XMI")
    func saveAsXMI() async throws {
        // Given: A loaded ATL module
        let atlPath = testResourcePath("SimpleTransformation.atl")
        let loadResource = ATLResource(uri: "file://\(atlPath)")
        try await loadResource.load()

        guard let module = loadResource.module else {
            Issue.record("Failed to load module")
            return
        }

        // When: Saving to XMI format
        let xmiPath = temporaryFilePath(extension: "xmi")
        let saveResource = ATLResource(uri: "file://\(xmiPath)", module: module)
        try await saveResource.save()

        // Then: XMI file should exist and be valid XML
        #expect(FileManager.default.fileExists(atPath: xmiPath), "XMI file should be created")

        // Verify the content is valid XML
        let xmiContent = try String(contentsOfFile: xmiPath, encoding: .utf8)
        #expect(xmiContent.contains("<?xml version=\"1.0\""), "Should have XML declaration")
        #expect(xmiContent.contains("<atl:Module"), "Should have ATL module element")
        #expect(xmiContent.contains("</atl:Module>"), "Should have closing module tag")

        // Clean up
        try? FileManager.default.removeItem(atPath: xmiPath)
    }

    @Test("Save as ATL throws error")
    func saveAsATLThrowsError() async throws {
        // Given: A module
        let module = ATLModule(
            name: "TestModule",
            sourceMetamodels: ["IN": EPackage(name: "Source", nsURI: "http://source")],
            targetMetamodels: ["OUT": EPackage(name: "Target", nsURI: "http://target")],
            helpers: [:],
            matchedRules: [],
            calledRules: [:]
        )

        // When/Then: Saving to .atl format should throw error
        let atlPath = temporaryFilePath(extension: "atl")
        let resource = ATLResource(uri: "file://\(atlPath)", module: module)

        await #expect(throws: ATLResourceError.self) {
            try await resource.save()
        }
    }

    // MARK: - XMI Serialization Tests

    @Test("XMI serializer basic structure")
    func xmiSerializerBasicStructure() throws {
        // Given: A simple ATL module
        let module = ATLModule(
            name: "TestModule",
            sourceMetamodels: [
                "IN": EPackage(name: "TestMM", nsURI: "http://www.example.com/TestMM")
            ],
            targetMetamodels: [
                "OUT": EPackage(name: "OutputMM", nsURI: "http://www.example.com/OutputMM")
            ],
            helpers: [:],
            matchedRules: [],
            calledRules: [:]
        )

        // When: Serializing to XMI
        let serializer = ATLXMISerializer()
        let xmi = try serializer.serialize(module)

        // Then: XMI should have correct structure
        #expect(xmi.contains("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"), "Should have XML declaration")
        #expect(xmi.contains("xmlns:xmi=\"http://www.omg.org/XMI\""), "Should have XMI namespace")
        #expect(xmi.contains("xmlns:atl=\"http://www.eclipse.org/gmt/2005/ATL\""), "Should have ATL namespace")
        #expect(xmi.contains("name=\"TestModule\""), "Should have module name")
        #expect(xmi.contains("name=\"IN\""), "Should have input model")
        #expect(xmi.contains("name=\"OUT\""), "Should have output model")
    }

    @Test("XMI serializer with matched rule")
    func xmiSerializerWithMatchedRule() throws {
        // Given: A module with a matched rule
        let sourcePattern = ATLSourcePattern(
            variableName: "c",
            type: "Class",
            guard: nil
        )

        let targetPattern = ATLTargetPattern(
            variableName: "t",
            type: "Table",
            bindings: []
        )

        let rule = ATLMatchedRule(
            name: "Class2Table",
            sourcePattern: sourcePattern,
            targetPatterns: [targetPattern]
        )

        let module = ATLModule(
            name: "TestModule",
            sourceMetamodels: ["IN": EPackage(name: "Source", nsURI: "http://source")],
            targetMetamodels: ["OUT": EPackage(name: "Target", nsURI: "http://target")],
            helpers: [:],
            matchedRules: [rule],
            calledRules: [:]
        )

        // When: Serializing to XMI
        let serializer = ATLXMISerializer()
        let xmi = try serializer.serialize(module)

        // Then: XMI should contain rule structure
        #expect(xmi.contains("xsi:type=\"atl:MatchedRule\""), "Should have MatchedRule type")
        #expect(xmi.contains("name=\"Class2Table\""), "Should have rule name")
        #expect(xmi.contains("<inPattern>"), "Should have input pattern")
        #expect(xmi.contains("<outPattern>"), "Should have output pattern")
    }

    @Test("XMI serializer with helper")
    func xmiSerializerWithHelper() throws {
        // Given: A module with a helper
        let helper = ATLHelperWrapper(
            name: "testHelper",
            contextType: "String",
            returnType: "Boolean",
            parameters: [
                ATLParameter(name: "param1", type: "Integer")
            ],
            body: ATLLiteralExpression(value: true)  // Placeholder body
        )

        let module = ATLModule(
            name: "TestModule",
            sourceMetamodels: ["IN": EPackage(name: "Source", nsURI: "http://source")],
            targetMetamodels: ["OUT": EPackage(name: "Target", nsURI: "http://target")],
            helpers: ["testHelper": helper],
            matchedRules: [],
            calledRules: [:]
        )

        // When: Serializing to XMI
        let serializer = ATLXMISerializer()
        let xmi = try serializer.serialize(module)

        // Then: XMI should contain helper structure
        #expect(xmi.contains("xsi:type=\"atl:Helper\""), "Should have Helper type")
        #expect(xmi.contains("name=\"testHelper\""), "Should have helper name")
        #expect(xmi.contains("name=\"String\""), "Should have context type")
        #expect(xmi.contains("name=\"Boolean\""), "Should have return type")
        #expect(xmi.contains("name=\"param1\""), "Should have parameter")
    }

    @Test("XMI serializer XML escaping")
    func xmiSerializerXMLEscaping() throws {
        // Given: A module with special XML characters in name
        let module = ATLModule(
            name: "Test<Module>&\"Quotes\"",
            sourceMetamodels: ["IN": EPackage(name: "Source", nsURI: "http://source")],
            targetMetamodels: ["OUT": EPackage(name: "Target", nsURI: "http://target")],
            helpers: [:],
            matchedRules: [],
            calledRules: [:]
        )

        // When: Serializing to XMI
        let serializer = ATLXMISerializer()
        let xmi = try serializer.serialize(module)

        // Then: Special characters should be escaped
        #expect(xmi.contains("&lt;"), "Should escape <")
        #expect(xmi.contains("&gt;"), "Should escape >")
        #expect(xmi.contains("&amp;"), "Should escape &")
        #expect(xmi.contains("&quot;"), "Should escape \"")
        #expect(!xmi.contains("name=\"Test<"), "Should not have unescaped <")
    }

    // MARK: - XMI Parsing Tests

    @Test("XMI parser basic structure")
    func xmiParserBasicStructure() throws {
        // Given: Basic XMI content
        let xmi = """
        <?xml version="1.0" encoding="UTF-8"?>
        <atl:Module xmi:version="2.0"
                    xmlns:xmi="http://www.omg.org/XMI"
                    xmlns:atl="http://www.eclipse.org/gmt/2005/ATL"
                    name="TestModule">
          <inModels name="IN" metamodel="http://www.example.com/MM" kind="IN"/>
          <inModels name="OUT" metamodel="http://www.example.com/OutMM" kind="OUT"/>
        </atl:Module>
        """

        // When: Parsing XMI
        let parser = ATLXMIParser()
        let module = try parser.parse(xmi)

        // Then: Module should be constructed
        #expect(module.name == "TestModule", "Should parse module name")
        #expect(module.sourceMetamodels.count == 1, "Should parse input model")
        #expect(module.targetMetamodels.count == 1, "Should parse output model")
        #expect(module.sourceMetamodels["IN"]?.name == "IN", "Should parse input model name")
        #expect(module.targetMetamodels["OUT"]?.name == "OUT", "Should parse output model name")
    }

    @Test("XMI parser invalid XML")
    func xmiParserInvalidXML() throws {
        // Given: Invalid XML
        let xmi = "This is not valid XML"

        // When/Then: Parsing should throw error
        let parser = ATLXMIParser()
        #expect(throws: ATLResourceError.self) {
            try parser.parse(xmi)
        }
    }

    // MARK: - Round-Trip Tests

    @Test("Round-trip simple module")
    func roundTripSimpleModule() async throws {
        // Given: A simple ATL module
        let atlPath = testResourcePath("SimpleTransformation.atl")
        let loadResource = ATLResource(uri: "file://\(atlPath)")
        try await loadResource.load()

        guard let originalModule = loadResource.module else {
            Issue.record("Failed to load module")
            return
        }

        // When: Serializing to XMI and parsing back
        let serializer = ATLXMISerializer()
        let xmi = try serializer.serialize(originalModule)

        let parser = ATLXMIParser()
        let parsedModule = try parser.parse(xmi)

        // Then: Basic structure should be preserved
        #expect(parsedModule.name == originalModule.name, "Module name should match")
        #expect(parsedModule.sourceMetamodels.count == originalModule.sourceMetamodels.count, "Source metamodels count should match")
        #expect(parsedModule.targetMetamodels.count == originalModule.targetMetamodels.count, "Target metamodels count should match")

        // Verify source metamodel names and URIs
        for (alias, originalPackage) in originalModule.sourceMetamodels {
            guard let parsedPackage = parsedModule.sourceMetamodels[alias] else {
                Issue.record("Source metamodel '\(alias)' not found in parsed module")
                continue
            }
            #expect(parsedPackage.nsURI == originalPackage.nsURI, "Source metamodel URI should match for '\(alias)'")
        }

        // Verify target metamodel names and URIs
        for (alias, originalPackage) in originalModule.targetMetamodels {
            guard let parsedPackage = parsedModule.targetMetamodels[alias] else {
                Issue.record("Target metamodel '\(alias)' not found in parsed module")
                continue
            }
            #expect(parsedPackage.nsURI == originalPackage.nsURI, "Target metamodel URI should match for '\(alias)'")
        }
    }

    @Test("Round-trip save and load")
    func roundTripSaveAndLoad() async throws {
        // Given: A loaded ATL module
        let atlPath = testResourcePath("SimpleTransformation.atl")
        let loadResource = ATLResource(uri: "file://\(atlPath)")
        try await loadResource.load()

        guard let originalModule = loadResource.module else {
            Issue.record("Failed to load module")
            return
        }

        // When: Saving as XMI and loading back
        let xmiPath = temporaryFilePath(extension: "xmi")
        let saveResource = ATLResource(uri: "file://\(xmiPath)", module: originalModule)
        try await saveResource.save()

        let reloadResource = ATLResource(uri: "file://\(xmiPath)")
        try await reloadResource.load()

        guard let reloadedModule = reloadResource.module else {
            Issue.record("Failed to reload module")
            try? FileManager.default.removeItem(atPath: xmiPath)
            return
        }

        // Then: Basic structure should be preserved
        #expect(reloadedModule.name == originalModule.name, "Module name should match")
        #expect(reloadedModule.sourceMetamodels.count == originalModule.sourceMetamodels.count, "Source metamodels count should match")
        #expect(reloadedModule.targetMetamodels.count == originalModule.targetMetamodels.count, "Target metamodels count should match")

        // Clean up
        try? FileManager.default.removeItem(atPath: xmiPath)
    }

    // MARK: - Error Handling Tests

    @Test("Load invalid URI")
    func loadInvalidURI() async throws {
        // Given: An invalid file URI (not a file:// scheme)
        let resource = ATLResource(uri: "http://example.com/test.atl")

        // When/Then: Loading should throw error
        await #expect(throws: ATLResourceError.self) {
            try await resource.load()
        }
    }

    @Test("Load unsupported format")
    func loadUnsupportedFormat() async throws {
        // Given: A URI with unsupported extension
        let resource = ATLResource(uri: "file:///test.txt")

        // When/Then: Loading should throw error
        await #expect(throws: ATLResourceError.self) {
            try await resource.load()
        }
    }

    @Test("Save without module")
    func saveWithoutModule() async throws {
        // Given: A resource without a module
        let resource = ATLResource(uri: "file:///test.xmi")

        // When/Then: Saving should throw error
        await #expect(throws: ATLResourceError.self) {
            try await resource.save()
        }
    }

    @Test("Load non-existent file")
    func loadNonExistentFile() async throws {
        // Given: A URI pointing to non-existent file
        let resource = ATLResource(uri: "file:///non-existent-file.atl")

        // When/Then: Loading should throw error
        await #expect(throws: (any Error).self) {
            try await resource.load()
        }
    }
}
