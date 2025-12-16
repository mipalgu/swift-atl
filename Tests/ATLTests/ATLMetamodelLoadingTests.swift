//
//  ATLMetamodelLoadingTests.swift
//  ATLTests
//
//  Created on 16/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation
import Testing

@testable import ATL
@testable import ECore

/// Test suite for ATL metamodel loading from @path directives.
///
/// Tests the extraction of @path directives from ATL comments and
/// loading of metamodels from .ecore files with search path resolution.
@Suite("ATL Metamodel Loading Tests")
struct ATLMetamodelLoadingTests {

    // MARK: - @path Directive Extraction Tests

    @Test("Extract @path directive from comment")
    func testExtractPathDirective() async throws {
        // Given
        let atlContent = """
        -- @path Families=/Families2Persons/Families.ecore
        -- @path Persons=/Families2Persons/Persons.ecore

        module Families2Persons;
        create OUT: Persons from IN: Families;
        """

        // When
        let parser = ATLParser()
        let module = try await parser.parseContent(atlContent, filename: "test.atl")

        // Then - module should be created successfully
        #expect(module.name == "Families2Persons")
        #expect(module.sourceMetamodels.count == 1)
        #expect(module.targetMetamodels.count == 1)
    }

    @Test("Extract multiple @path directives")
    func testExtractMultiplePathDirectives() async throws {
        // Given
        let atlContent = """
        -- @path Model1=/path/to/Model1.ecore
        -- @path Model2=/path/to/Model2.ecore
        -- @path Model3=/path/to/Model3.ecore

        module TestModule;
        create OUT1: Model1, OUT2: Model2 from IN: Model3;
        """

        // When
        let parser = ATLParser()
        let module = try await parser.parseContent(atlContent, filename: "test.atl")

        // Then
        #expect(module.name == "TestModule")
        #expect(module.sourceMetamodels.count == 1)
        #expect(module.targetMetamodels.count == 2)
    }

    @Test("Ignore malformed @path directives")
    func testIgnoreMalformedPathDirectives() async throws {
        // Given
        let atlContent = """
        -- @path MissingEquals
        -- @path NoPath=
        -- @path ValidModel=/path/to/Model.ecore

        module TestModule;
        create OUT: ValidModel from IN: ValidModel;
        """

        // When
        let parser = ATLParser()
        let module = try await parser.parseContent(atlContent, filename: "test.atl")

        // Then - should parse successfully despite malformed directives
        #expect(module.name == "TestModule")
    }

    @Test("Ignore regular comments without @path")
    func testIgnoreRegularComments() async throws {
        // Given
        let atlContent = """
        -- This is a regular comment
        -- Another comment about the transformation
        -- @path Families=/Families2Persons/Families.ecore
        -- Yet another regular comment

        module Families2Persons;
        create OUT: Persons from IN: Families;
        """

        // When
        let parser = ATLParser()
        let module = try await parser.parseContent(atlContent, filename: "test.atl")

        // Then
        #expect(module.name == "Families2Persons")
    }

    // MARK: - Metamodel Loading Tests

    @Test("Load metamodel from file with relative path")
    func testLoadMetamodelRelativePath() async throws {
        // Given - create a temporary .ecore file
        let tempDir = FileManager.default.temporaryDirectory
        let ecoreFile = tempDir.appendingPathComponent("TestModel.ecore")

        let ecoreContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="TestModel" nsURI="http://test.model" nsPrefix="test">
          <eClassifiers xsi:type="ecore:EClass" name="TestClass">
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="testAttr" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
          </eClassifiers>
        </ecore:EPackage>
        """

        try ecoreContent.write(to: ecoreFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: ecoreFile) }

        // Create ATL file in same directory
        let atlFile = tempDir.appendingPathComponent("test.atl")
        let atlContent = """
        -- @path TestModel=TestModel.ecore

        module TestModule;
        create OUT: TestModel from IN: TestModel;
        """

        try atlContent.write(to: atlFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: atlFile) }

        // When
        let parser = ATLParser()
        let module = try await parser.parse(atlFile)

        // Then
        #expect(module.name == "TestModule")
        #expect(module.sourceMetamodels["IN"]?.name == "TestModel")
        #expect(module.targetMetamodels["OUT"]?.name == "TestModel")

        // Verify the metamodel was actually loaded (not a dummy)
        if let loadedPackage = module.sourceMetamodels["IN"] {
            #expect(loadedPackage.nsURI == "http://test.model")
            #expect(loadedPackage.eClassifiers.count == 1)
            #expect(loadedPackage.eClassifiers.first?.name == "TestClass")
        }
    }

    @Test("Load metamodel with search path")
    func testLoadMetamodelWithSearchPath() async throws {
        // Given - create metamodel in a subdirectory
        let tempDir = FileManager.default.temporaryDirectory
        let metamodelDir = tempDir.appendingPathComponent("metamodels-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: metamodelDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: metamodelDir) }

        let ecoreFile = metamodelDir.appendingPathComponent("Families2Persons").appendingPathComponent("Families.ecore")
        try FileManager.default.createDirectory(at: ecoreFile.deletingLastPathComponent(), withIntermediateDirectories: true)

        let ecoreContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="Families" nsURI="http://www.example.org/families" nsPrefix="families">
          <eClassifiers xsi:type="ecore:EClass" name="Family">
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="lastName" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EClass" name="Member">
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="firstName" eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
          </eClassifiers>
        </ecore:EPackage>
        """

        try ecoreContent.write(to: ecoreFile, atomically: true, encoding: .utf8)

        // Create ATL file with workspace-relative path
        let atlFile = tempDir.appendingPathComponent("test-\(UUID().uuidString).atl")
        let atlContent = """
        -- @path Families=/Families2Persons/Families.ecore

        module TestModule;
        create OUT: Persons from IN: Families;
        """

        try atlContent.write(to: atlFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: atlFile) }

        // When - parse with search path
        let parser = ATLParser()
        let module = try await parser.parseContent(
            atlContent,
            filename: atlFile.path,
            searchPaths: [metamodelDir.path]
        )

        // Then
        #expect(module.name == "TestModule")

        // Verify the Families metamodel was loaded
        if let loadedPackage = module.sourceMetamodels["IN"] {
            #expect(loadedPackage.name == "Families")
            #expect(loadedPackage.nsURI == "http://www.example.org/families")
            #expect(loadedPackage.eClassifiers.count == 2)

            let classifierNames = loadedPackage.eClassifiers.map { $0.name }
            #expect(classifierNames.contains("Family"))
            #expect(classifierNames.contains("Member"))
        }
    }

    @Test("Fall back to dummy metamodel when file not found")
    func testFallbackToDummyMetamodel() async throws {
        // Given - ATL with @path pointing to non-existent file
        let atlContent = """
        -- @path NonExistent=/nonexistent/path/Model.ecore

        module TestModule;
        create OUT: NonExistent from IN: NonExistent;
        """

        // When
        let parser = ATLParser()
        let module = try await parser.parseContent(atlContent, filename: "test.atl")

        // Then - should create dummy metamodel
        #expect(module.name == "TestModule")
        #expect(module.sourceMetamodels["IN"]?.name == "NonExistent")
        #expect(module.targetMetamodels["OUT"]?.name == "NonExistent")

        // Verify it's a dummy (no classifiers loaded)
        if let dummyPackage = module.sourceMetamodels["IN"] {
            #expect(dummyPackage.eClassifiers.isEmpty)
        }
    }

    @Test("Handle missing @path directive")
    func testMissingPathDirective() async throws {
        // Given - ATL without @path directives
        let atlContent = """
        module TestModule;
        create OUT: SomeModel from IN: SomeModel;
        """

        // When
        let parser = ATLParser()
        let module = try await parser.parseContent(atlContent, filename: "test.atl")

        // Then - should create dummy metamodels
        #expect(module.name == "TestModule")
        #expect(module.sourceMetamodels["IN"]?.name == "SomeModel")
        #expect(module.targetMetamodels["OUT"]?.name == "SomeModel")

        // Verify they're dummies
        #expect(module.sourceMetamodels["IN"]?.eClassifiers.isEmpty == true)
        #expect(module.targetMetamodels["OUT"]?.eClassifiers.isEmpty == true)
    }
}
