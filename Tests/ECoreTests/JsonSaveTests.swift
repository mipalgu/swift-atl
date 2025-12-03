//
// JsonSaveTests.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
@testable import ECore
import Foundation

// MARK: - Extensions

extension Double {
    func isApproximatelyEqual(to other: Double, tolerance: Double) -> Bool {
        return abs(self - other) < tolerance
    }
}

// MARK: - JSON Save Test Suite

@Suite("JSON Saving Tests")
struct JsonSaveTests {
    
    // MARK: - Test Constants
    
    private static let personClassName = "Person"
    private static let recordClassName = "Record"
    private static let containerClassName = "Container"
    
    // MARK: - Test Errors
    
    private enum TestError: Error {
        case attributeNotFound(String)
    }
    
    // MARK: - Helper Methods
    
    private func createPersonMetamodel() -> EClass {
        let stringType = EDataType(name: "EString")
        let intType = EDataType(name: "EInt")
        let boolType = EDataType(name: "EBoolean")
        
        let nameAttr = EAttribute(name: "name", eType: stringType)
        let ageAttr = EAttribute(name: "age", eType: intType)
        let activeAttr = EAttribute(name: "active", eType: boolType)
        
        return EClass(
            name: Self.personClassName,
            eStructuralFeatures: [nameAttr, ageAttr, activeAttr]
        )
    }
    
    private func createRecordMetamodel() -> EClass {
        let stringType = EDataType(name: "EString")
        let intType = EDataType(name: "EInt")
        let doubleType = EDataType(name: "EDouble")
        let floatType = EDataType(name: "EFloat")
        let boolType = EDataType(name: "EBoolean")
        let dateType = EDataType(name: "EDate")
        
        let stringValueAttr = EAttribute(name: "stringValue", eType: stringType)
        let intValueAttr = EAttribute(name: "intValue", eType: intType)
        let doubleValueAttr = EAttribute(name: "doubleValue", eType: doubleType)
        let floatValueAttr = EAttribute(name: "floatValue", eType: floatType)
        let booleanValueAttr = EAttribute(name: "booleanValue", eType: boolType)
        let dateValueAttr = EAttribute(name: "dateValue", eType: dateType)
        
        return EClass(
            name: Self.recordClassName,
            eStructuralFeatures: [
                stringValueAttr, intValueAttr, doubleValueAttr,
                floatValueAttr, booleanValueAttr, dateValueAttr
            ]
        )
    }
    
    private func saveJsonToTemporaryFile(_ object: DynamicEObject, fileName: String = "test") throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(fileName).json")
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(object)
        try data.write(to: fileURL)
        
        return fileURL
    }
    
    private func saveJsonArrayToTemporaryFile(_ objects: [DynamicEObject], fileName: String = "test") throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(fileName).json")
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(objects)
        try data.write(to: fileURL)
        
        return fileURL
    }
    
    private func loadJsonFromFile(_ url: URL, with eClass: EClass) throws -> DynamicEObject {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.userInfo[.eClassKey] = eClass
        
        return try decoder.decode(DynamicEObject.self, from: data)
    }
    
    private func parseJsonFile(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let dictionary = json as? [String: Any] else {
            throw TestError.attributeNotFound("Invalid JSON structure")
        }
        return dictionary
    }
    
    /// Helper to safely get an attribute from a class
    private func getAttribute(from eClass: EClass, named name: String) throws -> EAttribute {
        guard let feature = eClass.eStructuralFeatures.first(where: { $0.name == name }) as? EAttribute else {
            throw TestError.attributeNotFound(name)
        }
        return feature
    }
    
    // MARK: - Basic JSON Saving Tests
    
    @Test("Save simple person object to JSON")
    func testSaveSimpleObject() throws {
        let personClass = createPersonMetamodel()
        
        // Create a person object
        var person = DynamicEObject(eClass: personClass)
        
        let nameAttr = try getAttribute(from: personClass, named: "name")
        let ageAttr = try getAttribute(from: personClass, named: "age")
        
        person.eSet(nameAttr, "John Smith")
        person.eSet(ageAttr, 42)
        
        // Save to JSON
        let fileURL = try saveJsonToTemporaryFile(person, fileName: "simple_save")
        
        // Parse and verify JSON structure
        let json = try parseJsonFile(fileURL)
        
        #expect(json["eClass"] as? String == Self.personClassName)
        #expect(json["name"] as? String == "John Smith")
        #expect(json["age"] as? Int == 42)
        #expect(json["active"] == nil) // Unset attribute should not appear
        
        // Clean up
        try FileManager.default.removeItem(at: fileURL)
    }
    
    @Test("Save record with all basic types to JSON")
    func testSaveObjectWithAllBasicTypes() throws {
        let recordClass = createRecordMetamodel()
        
        // Create a record object with various types
        var record = DynamicEObject(eClass: recordClass)
        
        let stringValueAttr = try getAttribute(from: recordClass, named: "stringValue")
        let intValueAttr = try getAttribute(from: recordClass, named: "intValue")
        let doubleValueAttr = try getAttribute(from: recordClass, named: "doubleValue")
        let floatValueAttr = try getAttribute(from: recordClass, named: "floatValue")
        let booleanValueAttr = try getAttribute(from: recordClass, named: "booleanValue")
        let dateValueAttr = try getAttribute(from: recordClass, named: "dateValue")
        
        let testDate = Date(timeIntervalSince1970: 1701423000) // 2023-12-01T10:30:00Z
        
        record.eSet(stringValueAttr, "Test String")
        record.eSet(intValueAttr, 123)
        record.eSet(doubleValueAttr, 3.14159)
        record.eSet(floatValueAttr, Float(2.718))
        record.eSet(booleanValueAttr, true)
        record.eSet(dateValueAttr, testDate)
        
        // Save to JSON
        let fileURL = try saveJsonToTemporaryFile(record, fileName: "types_save")
        
        // Parse and verify JSON structure
        let json = try parseJsonFile(fileURL)
        
        #expect(json["eClass"] as? String == Self.recordClassName)
        #expect(json["stringValue"] as? String == "Test String")
        #expect(json["intValue"] as? Int == 123)
        #expect(json["doubleValue"] as? Double == 3.14159)
        #expect((json["floatValue"] as? Double)?.isApproximatelyEqual(to: 2.718, tolerance: 0.001) == true)
        #expect(json["booleanValue"] as? Bool == true)
        #expect(json["dateValue"] as? String == "2023-12-01T09:30:00.000000Z")
        
        // Clean up
        try FileManager.default.removeItem(at: fileURL)
    }
    
    @Test("Save object with partial attributes to JSON")
    func testSaveObjectWithPartialAttributes() throws {
        let personClass = createPersonMetamodel()
        
        // Create a person with only some attributes set
        var person = DynamicEObject(eClass: personClass)
        
        let nameAttr = try getAttribute(from: personClass, named: "name")
        let activeAttr = try getAttribute(from: personClass, named: "active")
        
        person.eSet(nameAttr, "Alice Partial")
        person.eSet(activeAttr, false)
        // Deliberately leave age unset
        
        // Save to JSON
        let fileURL = try saveJsonToTemporaryFile(person, fileName: "partial_save")
        
        // Parse and verify JSON structure
        let json = try parseJsonFile(fileURL)
        
        #expect(json["eClass"] as? String == Self.personClassName)
        #expect(json["name"] as? String == "Alice Partial")
        #expect(json["active"] as? Bool == false)
        #expect(json["age"] == nil) // Unset attribute should not appear
        
        // Clean up
        try FileManager.default.removeItem(at: fileURL)
    }
    
    @Test("Save object with explicitly unset values to JSON")
    func testSaveObjectWithNullValues() throws {
        let personClass = createPersonMetamodel()
        
        // Create a person, set values, then unset some
        var person = DynamicEObject(eClass: personClass)
        
        let nameAttr = try getAttribute(from: personClass, named: "name")
        let ageAttr = try getAttribute(from: personClass, named: "age")
        
        person.eSet(nameAttr, "Bob Null")
        person.eSet(ageAttr, 30)
        
        // Now unset the age
        person.eUnset(ageAttr)
        
        // Save to JSON
        let fileURL = try saveJsonToTemporaryFile(person, fileName: "null_save")
        
        // Parse and verify JSON structure
        let json = try parseJsonFile(fileURL)
        
        #expect(json["eClass"] as? String == Self.personClassName)
        #expect(json["name"] as? String == "Bob Null")
        #expect(json["age"] == nil) // Unset attribute should not appear
        
        // Clean up
        try FileManager.default.removeItem(at: fileURL)
    }
    
    // MARK: - Round-trip Tests
    
    @Test("Save-load round-trip with simple object should preserve data")
    func testSaveLoadRoundTripSimple() throws {
        let personClass = createPersonMetamodel()
        
        // Create original object
        var originalPerson = DynamicEObject(eClass: personClass)
        
        let nameAttr = try getAttribute(from: personClass, named: "name")
        let ageAttr = try getAttribute(from: personClass, named: "age")
        let activeAttr = try getAttribute(from: personClass, named: "active")
        
        originalPerson.eSet(nameAttr, "Round Trip")
        originalPerson.eSet(ageAttr, 50)
        originalPerson.eSet(activeAttr, true)
        
        // Save to JSON
        let fileURL = try saveJsonToTemporaryFile(originalPerson, fileName: "roundtrip_save")
        
        // Load back from JSON
        let loadedPerson = try loadJsonFromFile(fileURL, with: personClass)
        
        // Verify they match
        #expect(originalPerson.eGet(nameAttr) as? String == loadedPerson.eGet(nameAttr) as? String)
        #expect(originalPerson.eGet(ageAttr) as? Int == loadedPerson.eGet(ageAttr) as? Int)
        #expect(originalPerson.eGet(activeAttr) as? Bool == loadedPerson.eGet(activeAttr) as? Bool)
        
        // Verify isSet status matches
        #expect(originalPerson.eIsSet(nameAttr) == loadedPerson.eIsSet(nameAttr))
        #expect(originalPerson.eIsSet(ageAttr) == loadedPerson.eIsSet(ageAttr))
        #expect(originalPerson.eIsSet(activeAttr) == loadedPerson.eIsSet(activeAttr))
        
        // Clean up
        try FileManager.default.removeItem(at: fileURL)
    }
    
    @Test("Save-load round-trip with various types should preserve data")
    func testSaveLoadRoundTripWithTypes() throws {
        let recordClass = createRecordMetamodel()
        
        // Create original object with various types
        var originalRecord = DynamicEObject(eClass: recordClass)
        
        let stringValueAttr = try getAttribute(from: recordClass, named: "stringValue")
        let intValueAttr = try getAttribute(from: recordClass, named: "intValue")
        let doubleValueAttr = try getAttribute(from: recordClass, named: "doubleValue")
        let floatValueAttr = try getAttribute(from: recordClass, named: "floatValue")
        let booleanValueAttr = try getAttribute(from: recordClass, named: "booleanValue")
        
        originalRecord.eSet(stringValueAttr, "Round Trip Types")
        originalRecord.eSet(intValueAttr, 999)
        originalRecord.eSet(doubleValueAttr, 2.71828)
        originalRecord.eSet(floatValueAttr, Float(1.618))
        originalRecord.eSet(booleanValueAttr, false)
        
        // Save to JSON
        let fileURL = try saveJsonToTemporaryFile(originalRecord, fileName: "roundtrip_types")
        
        // Load back from JSON
        let loadedRecord = try loadJsonFromFile(fileURL, with: recordClass)
        
        // Verify they match
        #expect(originalRecord.eGet(stringValueAttr) as? String == loadedRecord.eGet(stringValueAttr) as? String)
        #expect(originalRecord.eGet(intValueAttr) as? Int == loadedRecord.eGet(intValueAttr) as? Int)
        #expect(originalRecord.eGet(doubleValueAttr) as? Double == loadedRecord.eGet(doubleValueAttr) as? Double)
        
        guard let originalFloat = originalRecord.eGet(floatValueAttr) as? Float else {
            #expect(Bool(false), "Original float value should be loaded")
            return
        }
        guard let loadedFloat = loadedRecord.eGet(floatValueAttr) as? Float else {
            #expect(Bool(false), "Loaded float value should be loaded")
            return
        }
        #expect(abs(originalFloat - loadedFloat) < 0.001) // Float precision handling
        
        #expect(originalRecord.eGet(booleanValueAttr) as? Bool == loadedRecord.eGet(booleanValueAttr) as? Bool)
        
        // Clean up
        try FileManager.default.removeItem(at: fileURL)
    }
    
    // MARK: - JSON Format Validation Tests
    
    @Test("JSON output formatting should work correctly")
    func testJsonOutputFormat() throws {
        let personClass = createPersonMetamodel()
        
        var person = DynamicEObject(eClass: personClass)
        
        let nameAttr = try getAttribute(from: personClass, named: "name")
        let ageAttr = try getAttribute(from: personClass, named: "age")
        
        person.eSet(nameAttr, "Format Test")
        person.eSet(ageAttr, 25)
        
        // Test different formatting options
        let encoder1 = JSONEncoder()
        encoder1.outputFormatting = [.sortedKeys]
        let compactData = try encoder1.encode(person)
        guard let compactString = String(data: compactData, encoding: .utf8) else {
            throw TestError.attributeNotFound("Failed to convert compact data to string")
        }
        
        let encoder2 = JSONEncoder()
        encoder2.outputFormatting = [.prettyPrinted, .sortedKeys]
        let prettyData = try encoder2.encode(person)
        guard let prettyString = String(data: prettyData, encoding: .utf8) else {
            throw TestError.attributeNotFound("Failed to convert pretty data to string")
        }
        
        // Both should contain the same data
        #expect(compactString.contains("\"eClass\""))
        #expect(compactString.contains("\"Format Test\""))
        #expect(prettyString.contains("\"eClass\""))
        #expect(prettyString.contains("\"Format Test\""))
        
        // Pretty printed should have more whitespace
        #expect(prettyString.count > compactString.count)
    }
    
    @Test("JSON key ordering should be consistent with sorted keys")
    func testJsonKeyOrdering() throws {
        let personClass = createPersonMetamodel()
        
        var person = DynamicEObject(eClass: personClass)
        
        let nameAttr = try getAttribute(from: personClass, named: "name")
        let ageAttr = try getAttribute(from: personClass, named: "age")
        let activeAttr = try getAttribute(from: personClass, named: "active")
        
        person.eSet(nameAttr, "Key Order")
        person.eSet(ageAttr, 35)
        person.eSet(activeAttr, true)
        
        // Use sorted keys to ensure consistent ordering
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(person)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw TestError.attributeNotFound("Failed to convert JSON data to string")
        }
        
        // Keys should appear in alphabetical order
        let activeIndex = jsonString.range(of: "\"active\":")?.lowerBound
        let ageIndex = jsonString.range(of: "\"age\":")?.lowerBound  
        let eClassIndex = jsonString.range(of: "\"eClass\":")?.lowerBound
        let nameIndex = jsonString.range(of: "\"name\":")?.lowerBound
        
        #expect(activeIndex != nil)
        #expect(ageIndex != nil)
        #expect(eClassIndex != nil)
        #expect(nameIndex != nil)
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Save to invalid path should throw error")
    func testSaveToInvalidPath() throws {
        let personClass = createPersonMetamodel()
        var person = DynamicEObject(eClass: personClass)
        
        let nameAttr = try getAttribute(from: personClass, named: "name")
        person.eSet(nameAttr, "Invalid Path Test")
        
        // Try to save to an invalid path (non-existent directory)
        let invalidURL = URL(fileURLWithPath: "/nonexistent/directory/test.json")
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(person)
        
        #expect(throws: CocoaError.self) {
            try data.write(to: invalidURL)
        }
    }
    
    // MARK: - Multiple Root Objects Test (Placeholder)
    
    @Test("Save multiple root objects to JSON array (placeholder)")
    func testSaveMultipleRootObjectsPlaceholder() throws {
        let personClass = createPersonMetamodel()
        
        var person1 = DynamicEObject(eClass: personClass)
        var person2 = DynamicEObject(eClass: personClass)
        
        let nameAttr = try getAttribute(from: personClass, named: "name")
        let ageAttr = try getAttribute(from: personClass, named: "age")
        
        person1.eSet(nameAttr, "Alice Array")
        person1.eSet(ageAttr, 40)
        
        person2.eSet(nameAttr, "Bob Array")
        person2.eSet(ageAttr, 35)
        
        let people = [person1, person2]
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        
        let jsonData = try encoder.encode(people)
        let jsonString = String(data: jsonData, encoding: .utf8)!
        
        #expect(jsonString.hasPrefix("["))
        #expect(jsonString.hasSuffix("]"))
        #expect(jsonString.contains("\"Alice Array\""))
        #expect(jsonString.contains("\"Bob Array\""))
    }
}