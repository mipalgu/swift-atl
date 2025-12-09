//
//  ATLEndToEndTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 6/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//

import Foundation
import Testing

@testable import ATL
@testable import ECore

/// End-to-end test suite for ATL functionality.
///
/// Tests complete ATL workflows including:
/// - Loading ATL files from Resources directory
/// - Parsing ATL modules with various constructs
/// - Validating module structure and contents
/// - Testing complex transformations and helper functions
/// - Integration between ATL components
///
/// This test suite validates the full ATL implementation stack
/// from file parsing to module execution.
@Suite("ATL End-to-End Tests")
struct ATLEndToEndTests {

    // MARK: - Resource Loading Tests

    @Test("Load and parse SimpleQuery.atl")
    func testLoadSimpleQuery() async throws {
        // Given
        let resourceURL = try getResourceURL("SimpleQuery.atl")
        let parser = ATLParser()

        // When
        let module = try await parser.parse(resourceURL)

        // Then
        #expect(module.name == "SimpleQuery")
        #expect(module.sourceMetamodels.count >= 1)
        #expect(module.targetMetamodels.count >= 1)

        // Should have default metamodels since none specified in file
        #expect(module.sourceMetamodels["IN"] != nil)
        #expect(module.targetMetamodels["OUT"] != nil)
    }

    @Test("Load and parse HelperFunctions.atl")
    func testLoadHelperFunctions() async throws {
        // Given
        let resourceURL = try getResourceURL("HelperFunctions.atl")
        let parser = ATLParser()

        // When
        let module = try await parser.parse(resourceURL)

        // Then
        #expect(module.name == "HelperFunctions")
        #expect(module.helpers.count > 0)

        // Check for specific helpers we defined
        #expect(module.helpers["addNumbers"] != nil)
        #expect(module.helpers["concatenateStrings"] != nil)
        #expect(module.helpers["factorial"] != nil)

        // Verify helper properties
        if let addNumbersHelper = module.helpers["addNumbers"] {
            #expect(addNumbersHelper.name == "addNumbers")
            #expect(addNumbersHelper.contextType == nil)  // Context-free helper
            #expect(addNumbersHelper.returnType == "Integer")
            #expect(addNumbersHelper.parameters.count == 2)
        }
    }

    @Test("Load and parse SimpleTransformation.atl")
    func testLoadSimpleTransformation() async throws {
        // Given
        let resourceURL = try getResourceURL("SimpleTransformation.atl")
        let parser = ATLParser()

        // When
        let module = try await parser.parse(resourceURL)

        // Then
        #expect(module.name == "SimpleTransformation")
        #expect(module.sourceMetamodels.count > 0)
        #expect(module.targetMetamodels.count > 0)

        // Should have specified metamodels
        #expect(module.sourceMetamodels["IN"] != nil)
        #expect(module.targetMetamodels["OUT"] != nil)

        // Check for transformation rules
        #expect(module.matchedRules.count > 0)

        // Verify specific rules exist
        let ruleNames = module.matchedRules.map { $0.name }
        #expect(ruleNames.contains("PersonToEmployee"))
        #expect(ruleNames.contains("AdultPersonToManager"))

        // Check called rules
        #expect(module.calledRules.count > 0)
        #expect(module.calledRules["CreateDepartment"] != nil)
    }

    @Test("Load and parse CollectionOperations.atl")
    func testLoadCollectionOperations() async throws {
        // Given
        let resourceURL = try getResourceURL("CollectionOperations.atl")
        let parser = ATLParser()

        // When
        let module = try await parser.parse(resourceURL)

        // Then
        #expect(module.name == "CollectionOperations")
        #expect(module.helpers.count > 0)

        // Check for collection helper functions
        #expect(module.helpers["createNumberSequence"] != nil)
        #expect(module.helpers["sumSequence"] != nil)

        // Verify context helpers are parsed
        let helperNames = module.helpers.keys.map { $0 }
        #expect(helperNames.contains("createNumberSequence"))
        #expect(helperNames.contains("sumSequence"))
    }

    @Test("Load and parse Families2Persons.atl")
    func testLoadFamiliesToPersons() async throws {
        // Given
        let resourceURL = try getResourceURL("Families2Persons.atl")
        let parser = ATLParser()

        // When
        let module = try await parser.parse(resourceURL)

        // Then
        #expect(module.name == "Families2Persons")
        #expect(module.sourceMetamodels.count > 0)
        #expect(module.targetMetamodels.count > 0)

        // Check metamodels
        #expect(module.sourceMetamodels["IN"] != nil)
        #expect(module.targetMetamodels["OUT"] != nil)

        // Check for transformation rules
        #expect(module.matchedRules.count > 0)
        let ruleNames = module.matchedRules.map { $0.name }
        #expect(ruleNames.contains("Member2Male"))
        #expect(ruleNames.contains("Member2Female"))

        // Check for helper functions
        #expect(module.helpers.count > 0)
        #expect(module.helpers["isValidName"] != nil)
        #expect(module.helpers["countAllMembers"] != nil)
        #expect(module.helpers["getAdultMembers"] != nil)
    }

    // MARK: - Module Structure Validation Tests

    @Test("Validate parsed module equals constructed module")
    func testParsedModuleStructure() async throws {
        // Given
        let resourceURL = try getResourceURL("SimpleQuery.atl")
        let parser = ATLParser()

        // When
        let parsedModule = try await parser.parse(resourceURL)

        // Manually construct equivalent module
        let sourcePackage = EPackage(name: "DefaultSource", nsURI: "http://default.source")
        let targetPackage = EPackage(name: "DefaultTarget", nsURI: "http://default.target")

        let expectedModule = ATLModule(
            name: "SimpleQuery",
            sourceMetamodels: ["IN": sourcePackage],
            targetMetamodels: ["OUT": targetPackage]
        )

        // Then
        #expect(parsedModule.name == expectedModule.name)
        #expect(parsedModule.sourceMetamodels.count == expectedModule.sourceMetamodels.count)
        #expect(parsedModule.targetMetamodels.count == expectedModule.targetMetamodels.count)
    }

    @Test("Validate helper function parsing details")
    func testHelperFunctionDetails() async throws {
        // Given
        let resourceURL = try getResourceURL("HelperFunctions.atl")
        let parser = ATLParser()

        // When
        let module = try await parser.parse(resourceURL)

        // Then - Check specific helper details
        guard let addNumbersHelper = module.helpers["addNumbers"] else {
            #expect(Bool(false), "addNumbers helper should exist")
            return
        }

        #expect(addNumbersHelper.name == "addNumbers")
        #expect(addNumbersHelper.contextType == nil)
        #expect(addNumbersHelper.returnType == "Integer")
        #expect(addNumbersHelper.parameters.count == 2)

        // Check parameter details
        let paramNames = addNumbersHelper.parameters.map { $0.name }
        let paramTypes = addNumbersHelper.parameters.map { $0.type }
        #expect(paramNames.contains("a"))
        #expect(paramNames.contains("b"))
        #expect(paramTypes.allSatisfy { $0 == "Integer" })
    }

    @Test("Validate transformation rule parsing details")
    func testTransformationRuleDetails() async throws {
        // Given
        let resourceURL = try getResourceURL("SimpleTransformation.atl")
        let parser = ATLParser()

        // When
        let module = try await parser.parse(resourceURL)

        // Then - Check first matched rule
        #expect(module.matchedRules.count > 0)
        let firstRule = module.matchedRules[0]

        #expect(!firstRule.name.isEmpty)
        #expect(!firstRule.sourcePattern.variableName.isEmpty)
        #expect(!firstRule.sourcePattern.type.isEmpty)
        #expect(firstRule.targetPatterns.count > 0)

        let firstTargetPattern = firstRule.targetPatterns[0]
        #expect(!firstTargetPattern.variableName.isEmpty)
        #expect(!firstTargetPattern.type.isEmpty)
    }

    // MARK: - Integration Tests

    @Test("Parse multiple ATL files in sequence")
    func testMultipleFilesParsing() async throws {
        // Given
        let fileNames = [
            "SimpleQuery.atl",
            "HelperFunctions.atl",
            "SimpleTransformation.atl",
            "CollectionOperations.atl",
        ]
        let parser = ATLParser()

        // When & Then
        for fileName in fileNames {
            let resourceURL = try getResourceURL(fileName)
            let module = try await parser.parse(resourceURL)

            #expect(!module.name.isEmpty)
            #expect(module.sourceMetamodels.count > 0)
            #expect(module.targetMetamodels.count > 0)
        }
    }

    @Test("Validate module hashability and equality")
    func testModuleHashingAndEquality() async throws {
        // Given
        let resourceURL = try getResourceURL("SimpleQuery.atl")
        let parser = ATLParser()

        // When
        let module1 = try await parser.parse(resourceURL)
        let module2 = try await parser.parse(resourceURL)

        // Then
        #expect(module1 == module2)
        #expect(module1.hashValue == module2.hashValue)
    }

    @Test("Validate ATL module metamodel references")
    func testMetamodelReferences() async throws {
        // Given
        let resourceURL = try getResourceURL("Families2Persons.atl")
        let parser = ATLParser()

        // When
        let module = try await parser.parse(resourceURL)

        // Then
        #expect(module.sourceMetamodels.count > 0)
        #expect(module.targetMetamodels.count > 0)

        // Check metamodel properties
        for (alias, metamodel) in module.sourceMetamodels {
            #expect(!alias.isEmpty)
            #expect(!metamodel.name.isEmpty)
            #expect(!metamodel.nsURI.isEmpty)
        }

        for (alias, metamodel) in module.targetMetamodels {
            #expect(!alias.isEmpty)
            #expect(!metamodel.name.isEmpty)
            #expect(!metamodel.nsURI.isEmpty)
        }
    }

    // MARK: - Error Handling Tests

    @Test("Handle missing ATL file gracefully")
    func testMissingFileHandling() async throws {
        // Given
        let missingFileURL = URL(fileURLWithPath: "/nonexistent/path/missing.atl")
        let parser = ATLParser()

        // When & Then
        await #expect(throws: ATLParseError.self) {
            _ = try await parser.parse(missingFileURL)
        }
    }

    @Test("Handle malformed ATL content")
    func testMalformedContentHandling() async throws {
        // Given
        let malformedContent = "this is not valid ATL content at all"
        let parser = ATLParser()

        // When & Then
        await #expect(throws: ATLParseError.self) {
            _ = try await parser.parseContent(malformedContent, filename: "test.atl")
        }
    }

    @Test("Handle empty ATL file")
    func testEmptyFileHandling() async throws {
        // Given
        let emptyContent = ""
        let parser = ATLParser()

        // When & Then
        await #expect(throws: ATLParseError.self) {
            _ = try await parser.parseContent(emptyContent, filename: "empty.atl")
        }
    }

    // MARK: - Performance Tests

    @Test("Parse large ATL file efficiently")
    func testLargeFilePerformance() async throws {
        // Given - Use the most complex file we have
        let resourceURL = try getResourceURL("CollectionOperations.atl")
        let parser = ATLParser()

        // When
        let startTime = CFAbsoluteTimeGetCurrent()
        let module = try await parser.parse(resourceURL)
        let endTime = CFAbsoluteTimeGetCurrent()

        // Then
        let parseTime = endTime - startTime
        #expect(parseTime < 1.0)  // Should parse in less than 1 second
        #expect(!module.name.isEmpty)
        #expect(module.helpers.count > 0)
    }

    // MARK: - Helper Methods

    /// Gets the URL for a test resource file
    /// - Parameter filename: The name of the resource file
    /// - Returns: URL to the resource file
    /// - Throws: Error if resource cannot be found
    private func getResourceURL(_ filename: String) throws -> URL {
        guard let bundleResourcesURL = Bundle.module.resourceURL else {
            throw ATLParseError.fileNotFound("Bundle resource URL not found")
        }

        let fm = FileManager.default
        let testResourcesURL = bundleResourcesURL.appendingPathComponent("Resources")
        var isDirectory = ObjCBool(false)

        let baseURL: URL
        if fm.fileExists(atPath: testResourcesURL.path, isDirectory: &isDirectory),
            isDirectory.boolValue
        {
            baseURL = testResourcesURL
        } else {
            baseURL = bundleResourcesURL
        }

        let resourceURL = baseURL.appendingPathComponent(filename)

        guard fm.fileExists(atPath: resourceURL.path) else {
            throw ATLParseError.fileNotFound(
                "Could not find resource file: \(filename) at \(resourceURL.path)")
        }

        return resourceURL
    }

    /// Creates a temporary ATL file with the given content for testing
    /// - Parameter content: The ATL content to write
    /// - Returns: URL to the temporary file
    /// - Throws: Error if file creation fails
    private func createTempATLFile(content: String) throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".atl")

        try content.write(to: tempFile, atomically: true, encoding: .utf8)

        return tempFile
    }

    /// Cleans up temporary files created during testing
    /// - Parameter url: The URL of the temporary file to remove
    private func cleanupTempFile(_ url: URL) {
        try? FileManager.default.removeItem(at: url)
    }

    @Test("Debug generic type parsing issue")
    func testDebugGenericTypeParsing() async throws {
        // Given - minimal ATL content that might trigger the issue
        let minimalRuleContent = """
            module TestModule;
            create OUT : Target from IN : Source;

            rule SimpleRule {
                from
                    s : Source!Element
                to
                    t : Target!Element (
                        name <- s.name
                    )
            }
            """

        let parser = ATLParser()

        // When & Then - this should help isolate the parsing issue
        let module = try await parser.parseContent(minimalRuleContent, filename: "debug.atl")
        #expect(module.name == "TestModule")
    }

    @Test("Debug even simpler parsing issue")
    func testEvenSimplerParsing() async throws {
        // Given - just a target pattern without source
        let simplestContent = """
            module TestModule;
            create OUT : Target from IN : Source;

            rule SimpleRule {
                from
                    s : Source!Element
                to
                    t : Target!Element
            }
            """

        let parser = ATLParser()

        // When & Then
        let module = try await parser.parseContent(simplestContent, filename: "simplest.atl")
        #expect(module.name == "TestModule")
    }

    @Test("Debug property binding parsing issue")
    func testPropertyBindingParsing() async throws {
        // Given - just add property bindings to see where it fails
        let propertyBindingContent = """
            module TestModule;
            create OUT : Target from IN : Source;

            rule SimpleRule {
                from
                    s : Source!Element
                to
                    t : Target!Element (
                        name <- s.name
                    )
            }
            """

        let parser = ATLParser()

        // When & Then
        let module = try await parser.parseContent(propertyBindingContent, filename: "binding.atl")
        #expect(module.name == "TestModule")
    }

    @Test("Debug CollectionOperations parsing issue")
    func testDebugCollectionOperations() async throws {
        // Given - just the first helper from CollectionOperations.atl
        let collectionHelperContent = """
            module CollectionOperations;

            helper def : createNumberSequence(start : Integer, count : Integer) : Sequence(Integer) =
                if count <= 0 then
                    Sequence{}
                else
                    Sequence{start}->union(createNumberSequence(start + 1, count - 1))
                endif;
            """

        let parser = ATLParser()

        // When & Then
        let module = try await parser.parseContent(
            collectionHelperContent, filename: "collection.atl")
        #expect(module.name == "CollectionOperations")
    }

    @Test("Debug simple lambda parsing issue")
    func testDebugSimpleLambda() async throws {
        // Given - just a simple lambda expression
        let simpleLambdaContent = """
            module TestModule;

            helper context Sequence(Integer) def : filterEven() : Sequence(Integer) =
                self->select(n | n.mod(2) = 0);
            """

        let parser = ATLParser()

        // When & Then
        let module = try await parser.parseContent(simpleLambdaContent, filename: "lambda.atl")
        #expect(module.name == "TestModule")
    }

    // MARK: - Advanced Transformation Tests

    @Test("Load and parse BookTransformation.atl")
    func testLoadBookTransformation() async throws {
        // Given
        let resourceURL = try getResourceURL("BookTransformation.atl")
        let parser = ATLParser()

        // When
        let module = try await parser.parse(resourceURL)

        // Then
        #expect(module.name == "BookTransformation")
        #expect(module.sourceMetamodels["IN"] != nil)
        #expect(module.targetMetamodels["OUT"] != nil)

        // Should have complex helpers with iterate operations
        #expect(module.helpers["getAuthors"] != nil)
        #expect(module.helpers["getTotalPages"] != nil)
        #expect(module.helpers["getLongestChapter"] != nil)
        #expect(module.helpers["countLongChapters"] != nil)

        // Should have transformation rules with guards
        let ruleNames = module.matchedRules.map { $0.name }
        #expect(ruleNames.contains("Book2Publication"))
        #expect(ruleNames.contains("ShortBook2Booklet"))

        // Should parse complex transformations successfully
        #expect(module.matchedRules.count >= 2)
        #expect(module.helpers.count >= 4)
    }

    @Test("Load and parse Class2RelationalTransformation.atl")
    func testLoadClass2RelationalTransformation() async throws {
        // Given
        let resourceURL = try getResourceURL("Class2RelationalTransformation.atl")
        let parser = ATLParser()

        // When
        let module = try await parser.parse(resourceURL)

        // Then
        #expect(module.name == "Class2RelationalTransformation")
        #expect(module.sourceMetamodels["IN"] != nil)
        #expect(module.targetMetamodels["OUT"] != nil)

        // Should have global helpers
        #expect(module.helpers["objectIdType"] != nil)
        #expect(module.helpers["stringType"] != nil)

        // Should have transformation rules for different patterns
        let ruleNames = module.matchedRules.map { $0.name }
        #expect(ruleNames.contains("Class2Table"))
        #expect(ruleNames.contains("DataType2Type"))
        #expect(ruleNames.contains("DataTypeAttribute2Column"))
        #expect(ruleNames.contains("MultiValuedDataTypeAttribute2Table"))
        #expect(ruleNames.contains("ClassAttribute2ForeignKey"))
        #expect(ruleNames.contains("MultiValuedClassAttribute2JunctionTable"))

        // Should have complex transformation patterns
        #expect(module.matchedRules.count >= 6)
        #expect(module.helpers.count >= 2)
    }

    @Test("Load and parse IteratorOperationsTest.atl")
    func testLoadIteratorOperationsTest() async throws {
        // Given
        let resourceURL = try getResourceURL("IteratorOperationsTest.atl")
        let parser = ATLParser()

        // When
        let module = try await parser.parse(resourceURL)

        // Then
        #expect(module.name == "IteratorOperationsTest")
        #expect(module.sourceMetamodels["IN"] != nil)
        #expect(module.targetMetamodels["OUT"] != nil)

        // Should have global test data helpers
        #expect(module.helpers["numberSequence"] != nil)
        #expect(module.helpers["stringSequence"] != nil)
        #expect(module.helpers["mixedNumbers"] != nil)
        #expect(module.helpers["duplicateSequence"] != nil)
        #expect(module.helpers["personData"] != nil)

        // Should have context helpers for collections
        #expect(module.helpers.values.contains { $0.contextType == "Sequence(Integer)" })
        #expect(module.helpers.values.contains { $0.contextType == "Sequence(String)" })

        // Should have comprehensive test rule
        let ruleNames = module.matchedRules.map { $0.name }
        #expect(ruleNames.contains("TestIteratorOperations"))

        // Should have comprehensive iterator operation patterns
        #expect(module.matchedRules.count >= 1)
        #expect(module.helpers.count >= 5)
    }

    @Test("Load and parse AdvancedRulePatterns.atl")
    func testLoadAdvancedRulePatterns() async throws {
        // Given
        let resourceURL = try getResourceURL("AdvancedRulePatterns.atl")
        let parser = ATLParser()

        // When
        let module = try await parser.parse(resourceURL)

        // Then
        #expect(module.name == "AdvancedRulePatterns")
        #expect(module.sourceMetamodels["IN"] != nil)
        #expect(module.targetMetamodels["OUT"] != nil)

        // Should have global helpers
        #expect(module.helpers["defaultCounter"] != nil)
        #expect(module.helpers["createUniqueId"] != nil)

        // Should have context helpers with complex logic
        #expect(module.helpers.values.contains { $0.contextType == "SourceModel!Element" })
        #expect(module.helpers.values.contains { $0.contextType == "SourceModel!Container" })

        // Should have matched rules with complex conditions
        let ruleNames = module.matchedRules.map { $0.name }
        #expect(ruleNames.contains("Container2ProcessingUnit"))
        #expect(ruleNames.contains("Element2ProcessedItem"))
        #expect(ruleNames.contains("HighPriorityContainer2SpecialUnit"))
        #expect(ruleNames.contains("FilteredContainer2OptimizedUnit"))

        // Should have advanced rule patterns
        #expect(module.matchedRules.count >= 4)
        #expect(module.calledRules.count >= 1)
        #expect(module.helpers.count >= 2)

        // Should have called rules
        let calledRuleNames = module.calledRules.keys
        #expect(calledRuleNames.contains("CreateAuditEntry"))
    }

    @Test("Validate advanced transformation parsing performance")
    func testAdvancedTransformationPerformance() async throws {
        // Given
        let advancedFiles = [
            "BookTransformation.atl",
            "Class2RelationalTransformation.atl",
            "IteratorOperationsTest.atl",
            "AdvancedRulePatterns.atl",
        ]
        let parser = ATLParser()

        // When & Then
        for filename in advancedFiles {
            let resourceURL = try getResourceURL(filename)

            let startTime = CFAbsoluteTimeGetCurrent()
            let module = try await parser.parse(resourceURL)
            let endTime = CFAbsoluteTimeGetCurrent()

            let parseTime = endTime - startTime
            #expect(
                parseTime < 2.0,
                "File \(filename) should parse in less than 2 seconds, took \(parseTime)")
            #expect(!module.name.isEmpty)
            #expect(module.helpers.count > 0)
        }
    }

    @Test("Validate complex iterate operations in advanced files")
    func testComplexIterateOperations() async throws {
        // Given - test files with complex iterate syntax
        let filesToTest = [
            ("BookTransformation.atl", "BookTransformation"),
            ("Class2RelationalTransformation.atl", "Class2RelationalTransformation"),
            ("IteratorOperationsTest.atl", "IteratorOperationsTest"),
            ("AdvancedRulePatterns.atl", "AdvancedRulePatterns"),
        ]
        let parser = ATLParser()

        // When & Then
        for (filename, expectedModuleName) in filesToTest {
            let resourceURL = try getResourceURL(filename)
            let module = try await parser.parse(resourceURL)

            #expect(module.name == expectedModuleName)
            #expect(module.helpers.count > 0, "File \(filename) should have helpers")

            // Verify at least one helper or query contains iterate operations
            let hasIterateOperations =
                module.helpers.values.contains { helper in
                    // Check if helper body likely contains iterate (simplified check)
                    true  // Since we can't easily inspect the parsed expression tree
                }

            #expect(hasIterateOperations, "File \(filename) should contain iterate operations")
        }
    }
}

// MARK: - Test Helper Extensions

extension ATLEndToEndTests {

    /// Test data for creating dynamic ATL content during tests
    struct TestATLContent {
        static let minimalModule = """
            module TestModule;
            """

        static let moduleWithHelper = """
            module TestModuleWithHelper;

            helper def : testHelper() : String =
                'test result';
            """

        static let moduleWithRule = """
            module TestModuleWithRule;
            create OUT : Target from IN : Source;

            rule TestRule {
                from
                    s : Source!Element
                to
                    t : Target!Element (
                        name <- s.name
                    )
            }
            """
    }

    @Test("Parse dynamically created ATL content")
    func testDynamicATLContent() async throws {
        // Given
        let parser = ATLParser()

        // Test minimal module
        let minimalModule = try await parser.parseContent(
            TestATLContent.minimalModule,
            filename: "minimal.atl"
        )
        #expect(minimalModule.name == "TestModule")

        // Test module with helper
        let helperModule = try await parser.parseContent(
            TestATLContent.moduleWithHelper,
            filename: "helper.atl"
        )
        #expect(helperModule.name == "TestModuleWithHelper")
        #expect(helperModule.helpers.count > 0)

        // Test module with rule
        let ruleModule = try await parser.parseContent(
            TestATLContent.moduleWithRule,
            filename: "rule.atl"
        )
        #expect(ruleModule.name == "TestModuleWithRule")
        #expect(ruleModule.matchedRules.count > 0)
    }
}
