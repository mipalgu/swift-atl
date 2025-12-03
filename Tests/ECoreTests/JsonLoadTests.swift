//
// JsonLoadTests.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
@testable import ECore
import Foundation

// MARK: - JSON Load Test Suite

@Suite("JSON Loading Tests")
struct JsonLoadTests {
    
    // MARK: - Test Constants
    
    private static let personClassName = "Person"
    private static let recordClassName = "Record"
    private static let containerClassName = "Container"
    
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
    
    private func getResourcesURL() throws -> URL {
        guard let bundleResourcesURL = Bundle.module.resourceURL else {
            throw TestError.resourcesNotFound
        }
        
        let fm = FileManager.default
        let testResourcesURL = bundleResourcesURL.appendingPathComponent("Resources")
        var isDirectory = ObjCBool(false)
        
        if fm.fileExists(atPath: testResourcesURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return testResourcesURL
        } else {
            return bundleResourcesURL
        }
    }
    
    private func loadJsonFile(named fileName: String, with eClass: EClass) throws -> DynamicEObject {
        let resourcesURL = try getResourcesURL()
        let fileURL = resourcesURL.appendingPathComponent("json").appendingPathComponent("\(fileName).json")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw TestError.fileNotFound(fileName)
        }
        
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.userInfo[.eClassKey] = eClass
        
        return try decoder.decode(DynamicEObject.self, from: data)
    }
    
    private func loadJsonArray(named fileName: String, with eClass: EClass) throws -> [DynamicEObject] {
        let resourcesURL = try getResourcesURL()
        let fileURL = resourcesURL.appendingPathComponent("json").appendingPathComponent("\(fileName).json")
        
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            throw TestError.fileNotFound(fileName)
        }
        
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.userInfo[.eClassKey] = eClass
        
        return try decoder.decode([DynamicEObject].self, from: data)
    }
    
    private enum TestError: Error {
        case fileNotFound(String)
        case resourcesNotFound
        case invalidData
        case attributeNotFound(String)
    }
    
    /// Helper to safely get an attribute from a class
    private func getAttribute(from eClass: EClass, named name: String) throws -> EAttribute {
        guard let feature = eClass.eStructuralFeatures.first(where: { $0.name == name }) as? EAttribute else {
            throw TestError.attributeNotFound(name)
        }
        return feature
    }
    
    // MARK: - Basic JSON Loading Tests
    
    @Test("Load simple person from JSON file")
    func testLoadSimpleObject() throws {
        let personClass = createPersonMetamodel()
        let person = try loadJsonFile(named: "simple", with: personClass)
        
        // Verify the loaded object
        #expect(person.eClass.name == Self.personClassName)
        
        // Get attributes for testing
        let nameAttr = try getAttribute(from: personClass, named: "name")
        let ageAttr = try getAttribute(from: personClass, named: "age")
        
        #expect(person.eGet(nameAttr) as? String == "John Doe")
        #expect(person.eGet(ageAttr) as? Int == 30)
    }
    
    @Test("Load person with partial attributes from JSON file")
    func testLoadObjectWithPartialAttributes() throws {
        let personClass = createPersonMetamodel()
        let person = try loadJsonFile(named: "partial", with: personClass)
        
        // Get attributes
        let nameAttr = try getAttribute(from: personClass, named: "name")
        let ageAttr = try getAttribute(from: personClass, named: "age")
        let activeAttr = try getAttribute(from: personClass, named: "active")
        
        // Verify set attributes
        #expect(person.eGet(nameAttr) as? String == "Diana")
        #expect(person.eGet(activeAttr) as? Bool == true)
        
        // Verify unset attributes
        #expect(person.eIsSet(ageAttr) == false)
        #expect(person.eGet(ageAttr) == nil)
    }
    
    @Test("Load record with various data types from JSON file")
    func testLoadObjectWithVariousTypes() throws {
        let recordClass = createRecordMetamodel()
        let record = try loadJsonFile(named: "types", with: recordClass)
        
        // Get attributes
        let stringValueAttr = try getAttribute(from: recordClass, named: "stringValue")
        let intValueAttr = try getAttribute(from: recordClass, named: "intValue")
        let doubleValueAttr = try getAttribute(from: recordClass, named: "doubleValue")
        let floatValueAttr = try getAttribute(from: recordClass, named: "floatValue")
        let booleanValueAttr = try getAttribute(from: recordClass, named: "booleanValue")
        let dateValueAttr = try getAttribute(from: recordClass, named: "dateValue")
        
        // Verify loaded values
        #expect(record.eGet(stringValueAttr) as? String == "Hello World")
        #expect(record.eGet(intValueAttr) as? Int == 42)
        #expect(record.eGet(doubleValueAttr) as? Double == 3.14159)
        #expect(record.eGet(floatValueAttr) as? Float == 2.718)
        #expect(record.eGet(booleanValueAttr) as? Bool == true)
        
        // Verify date was loaded correctly
        guard let actualDate = record.eGet(dateValueAttr) as? Date else {
            #expect(Bool(false), "Date should be loaded as a Date object")
            return
        }
        // The types.json contains "2023-12-01T10:30:00Z" which should be timestamp 1701426600
        let expectedTimestamp: TimeInterval = 1701426600 // 2023-12-01T10:30:00Z
        #expect(abs(actualDate.timeIntervalSince1970 - expectedTimestamp) < 1.0) // Allow 1 second tolerance
    }
    
    // MARK: - Multiple Root Objects Tests (Future)
    
    @Test("Load multiple root objects from JSON array (expected to fail for now)")
    func testLoadMultipleRootObjectsPlaceholder() throws {
        // This test documents the expected behavior once we implement multiple root support
        // For now, we verify that our test infrastructure works and validate expected content
        let personClass = createPersonMetamodel()
        let recordClass = createRecordMetamodel()
        
        // Test that the file exists and can be read
        let resourcesURL = try getResourcesURL()
        let fileURL = resourcesURL.appendingPathComponent("json").appendingPathComponent("multiple_roots.json")
        
        #expect(FileManager.default.fileExists(atPath: fileURL.path))
        
        let data = try Data(contentsOf: fileURL)
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        
        // Verify it's a JSON array
        #expect(json is [Any])
        
        guard let jsonArray = json as? [[String: Any]] else {
            #expect(Bool(false), "JSON should be an array of objects")
            return
        }
        
        #expect(jsonArray.count == 3)
        
        // Verify first Person object
        let person1 = jsonArray[0]
        #expect(person1["eClass"] as? String == "http://mytest/1.0#//Person")
        #expect(person1["name"] as? String == "Alice")
        #expect(person1["age"] as? Int == 30)
        
        // Verify second Person object
        let person2 = jsonArray[1]
        #expect(person2["eClass"] as? String == "http://mytest/1.0#//Person")
        #expect(person2["name"] as? String == "Bob")
        #expect(person2["age"] as? Int == 25)
        
        // Verify Record object
        let record = jsonArray[2]
        #expect(record["eClass"] as? String == "http://mytest/1.0#//Record")
        #expect(record["stringValue"] as? String == "Test Record")
        #expect(record["intValue"] as? Int == 42)
        #expect(record["booleanValue"] as? Bool == true)
        
        // Validate that our metamodels match the expected structure
        let personNameAttr = try getAttribute(from: personClass, named: "name")
        let personAgeAttr = try getAttribute(from: personClass, named: "age")
        #expect(personNameAttr.eType.name == "EString")
        #expect(personAgeAttr.eType.name == "EInt")
        
        let recordStringAttr = try getAttribute(from: recordClass, named: "stringValue")
        let recordIntAttr = try getAttribute(from: recordClass, named: "intValue")
        let recordBoolAttr = try getAttribute(from: recordClass, named: "booleanValue")
        #expect(recordStringAttr.eType.name == "EString")
        #expect(recordIntAttr.eType.name == "EInt")
        #expect(recordBoolAttr.eType.name == "EBoolean")
    }
    
    // MARK: - Error Handling Tests
    
    @Test("Load invalid JSON missing eClass field should throw error")
    func testLoadInvalidJsonMissingEClass() throws {
        let personClass = createPersonMetamodel()
        
        let resourcesURL = try getResourcesURL()
        let fileURL = resourcesURL.appendingPathComponent("json").appendingPathComponent("invalid_missing_eclass.json")
        
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.userInfo[.eClassKey] = personClass
        
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(DynamicEObject.self, from: data)
        }
    }
    
    @Test("Load JSON with wrong data types should throw error")
    func testLoadInvalidJsonWrongTypes() throws {
        let personClass = createPersonMetamodel()
        
        let resourcesURL = try getResourcesURL()
        let fileURL = resourcesURL.appendingPathComponent("json").appendingPathComponent("invalid_wrong_type.json")
        
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        decoder.userInfo[.eClassKey] = personClass
        
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(DynamicEObject.self, from: data)
        }
    }
    
    @Test("Load without eClass in userInfo should throw error")
    func testLoadWithoutEClassInUserInfo() throws {
        let resourcesURL = try getResourcesURL()
        let fileURL = resourcesURL.appendingPathComponent("json").appendingPathComponent("simple.json")
        
        let data = try Data(contentsOf: fileURL)
        let decoder = JSONDecoder()
        // Don't set userInfo - should fail
        
        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(DynamicEObject.self, from: data)
        }
    }
    
    @Test("Load nonexistent file should throw error")
    func testLoadNonexistentFile() {
        let personClass = createPersonMetamodel()
        
        #expect(throws: TestError.self) {
            _ = try loadJsonFile(named: "nonexistent", with: personClass)
        }
    }
    
    // MARK: - Round-trip Tests
    
    @Test("JSON round-trip with simple object should preserve data")
    func testJsonRoundTripSimpleObject() throws {
        let personClass = createPersonMetamodel()
        
        // Load from JSON
        let originalPerson = try loadJsonFile(named: "simple", with: personClass)
        
        // Encode back to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let encodedData = try encoder.encode(originalPerson)
        
        // Decode again
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.userInfo[.eClassKey] = personClass
        let roundTripPerson = try decoder.decode(DynamicEObject.self, from: encodedData)
        
        // Verify they match
        let nameAttr = try getAttribute(from: personClass, named: "name")
        let ageAttr = try getAttribute(from: personClass, named: "age")
        
        #expect(originalPerson.eGet(nameAttr) as? String == roundTripPerson.eGet(nameAttr) as? String)
        #expect(originalPerson.eGet(ageAttr) as? Int == roundTripPerson.eGet(ageAttr) as? Int)
    }
    
    @Test("JSON round-trip with various types should preserve data")
    func testJsonRoundTripTypesObject() throws {
        let recordClass = createRecordMetamodel()
        
        // Load from JSON
        let originalRecord = try loadJsonFile(named: "types", with: recordClass)
        
        // Encode back to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let encodedData = try encoder.encode(originalRecord)
        
        // Decode again
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.userInfo[.eClassKey] = recordClass
        let roundTripRecord = try decoder.decode(DynamicEObject.self, from: encodedData)
        
        // Verify key attributes match
        let stringValueAttr = try getAttribute(from: recordClass, named: "stringValue")
        let intValueAttr = try getAttribute(from: recordClass, named: "intValue")
        let booleanValueAttr = try getAttribute(from: recordClass, named: "booleanValue")
        
        #expect(originalRecord.eGet(stringValueAttr) as? String == roundTripRecord.eGet(stringValueAttr) as? String)
        #expect(originalRecord.eGet(intValueAttr) as? Int == roundTripRecord.eGet(intValueAttr) as? Int)
        #expect(originalRecord.eGet(booleanValueAttr) as? Bool == roundTripRecord.eGet(booleanValueAttr) as? Bool)
    }
}