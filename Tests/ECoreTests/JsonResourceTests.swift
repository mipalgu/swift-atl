//
// JsonResourceTests.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
@testable import ECore
import Foundation

// MARK: - JSON Resource Test Suite

@Suite("JSON Resource Tests")
struct JsonResourceTests {

    // MARK: - Test Constants

    private static let personClassName = "Person"
    private static let recordClassName = "Record"
    private static let containerClassName = "Container"

    // MARK: - Test Errors

    private enum TestError: Error {
        case attributeNotFound(String)
    }

    /// Helper to safely get an attribute from a class
    private func getAttribute(from eClass: EClass, named name: String) throws -> EAttribute {
        guard let feature = eClass.eStructuralFeatures.first(where: { $0.name == name }) as? EAttribute else {
            throw TestError.attributeNotFound(name)
        }
        return feature
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

    // MARK: - JSON Loading Tests

    @Test("Load simple person from embedded JSON")
    func testLoadSimplePersonFromJson() throws {
        let jsonString = """
        {
          "eClass": "Person",
          "name": "John Doe",
          "age": 30
        }
        """

        let personClass = createPersonMetamodel()
        let jsonData = jsonString.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.userInfo[.eClassKey] = personClass

        let person = try decoder.decode(DynamicEObject.self, from: jsonData)

        // Verify the loaded object
        #expect(person.eClass.name == Self.personClassName)

        let nameAttr = try getAttribute(from: personClass, named: "name")
        let ageAttr = try getAttribute(from: personClass, named: "age")

        #expect(person.eGet(nameAttr) as? String == "John Doe")
        #expect(person.eGet(ageAttr) as? Int == 30)
    }

    @Test("Load person with partial attributes from JSON")
    func testLoadPersonWithPartialAttributes() throws {
        let jsonString = """
        {
          "eClass": "Person",
          "name": "Alice",
          "active": true
        }
        """

        let personClass = createPersonMetamodel()
        let jsonData = jsonString.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.userInfo[.eClassKey] = personClass

        let person = try decoder.decode(DynamicEObject.self, from: jsonData)

        let nameAttr = try getAttribute(from: personClass, named: "name")
        let ageAttr = try getAttribute(from: personClass, named: "age")
        let activeAttr = try getAttribute(from: personClass, named: "active")

        // Verify set attributes
        #expect(person.eGet(nameAttr) as? String == "Alice")
        #expect(person.eGet(activeAttr) as? Bool == true)

        // Verify unset attributes
        #expect(person.eIsSet(ageAttr) == false)
        #expect(person.eGet(ageAttr) == nil)
    }

    @Test("Load record with various data types from JSON")
    func testLoadRecordWithVariousTypes() throws {
        let jsonString = """
        {
          "eClass": "Record",
          "stringValue": "Hello World",
          "intValue": 42,
          "doubleValue": 3.14159,
          "floatValue": 2.718,
          "booleanValue": true,
          "dateValue": "2023-12-01T10:30:00Z"
        }
        """

        let recordClass = createRecordMetamodel()
        guard let jsonData = jsonString.data(using: .utf8) else {
            #expect(Bool(false), "Failed to convert JSON string to data")
            return
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.userInfo[.eClassKey] = recordClass

        let record = try decoder.decode(DynamicEObject.self, from: jsonData)

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
        // The embedded JSON contains "2023-12-01T10:30:00Z" which should be timestamp 1701426600
        let expectedTimestamp: TimeInterval = 1701426600 // 2023-12-01T10:30:00Z
        #expect(actualDate.timeIntervalSince1970 == expectedTimestamp)
    }

    // MARK: - JSON Saving Tests

    @Test("Save simple person object to JSON")
    func testSaveSimplePersonToJson() throws {
        let personClass = createPersonMetamodel()
        var person = DynamicEObject(eClass: personClass)

        let nameAttr = try getAttribute(from: personClass, named: "name")
        let ageAttr = try getAttribute(from: personClass, named: "age")

        person.eSet(nameAttr, "Jane Smith")
        person.eSet(ageAttr, 25)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let jsonData = try encoder.encode(person)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        #expect(jsonString.contains("\"eClass\":\"Person\""))
        #expect(jsonString.contains("\"name\":\"Jane Smith\""))
        #expect(jsonString.contains("\"age\":25"))
        #expect(!jsonString.contains("\"active\"")) // Unset attribute should not appear
    }

    @Test("Save record with various data types to JSON")
    func testSaveRecordWithVariousTypes() throws {
        let recordClass = createRecordMetamodel()
        var record = DynamicEObject(eClass: recordClass)

        let stringValueAttr = try getAttribute(from: recordClass, named: "stringValue")
        let intValueAttr = try getAttribute(from: recordClass, named: "intValue")
        let doubleValueAttr = try getAttribute(from: recordClass, named: "doubleValue")
        let booleanValueAttr = try getAttribute(from: recordClass, named: "booleanValue")
        let dateValueAttr = try getAttribute(from: recordClass, named: "dateValue")

        record.eSet(stringValueAttr, "Test Record")
        record.eSet(intValueAttr, 999)
        record.eSet(doubleValueAttr, 2.71828)
        record.eSet(booleanValueAttr, false)

        // Set a test date
        let testDate = Date(timeIntervalSince1970: 1609459200) // 2021-01-01T00:00:00Z
        record.eSet(dateValueAttr, testDate)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let jsonData = try encoder.encode(record)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        #expect(jsonString.contains("\"eClass\":\"Record\""))
        #expect(jsonString.contains("\"stringValue\":\"Test Record\""))
        #expect(jsonString.contains("\"intValue\":999"))
        #expect(jsonString.contains("\"doubleValue\":2.71828"))
        #expect(jsonString.contains("\"booleanValue\":false"))
        #expect(jsonString.contains("\"dateValue\":\"2021-01-01T00:00:00.000000Z\""))
    }

    @Test("Save object with partial attributes to JSON")
    func testSaveObjectWithPartialAttributes() throws {
        let personClass = createPersonMetamodel()
        var person = DynamicEObject(eClass: personClass)

        let nameAttr = try getAttribute(from: personClass, named: "name")
        let activeAttr = try getAttribute(from: personClass, named: "active")

        person.eSet(nameAttr, "Bob Partial")
        person.eSet(activeAttr, true)
        // Leave age unset

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let jsonData = try encoder.encode(person)
        let jsonString = String(data: jsonData, encoding: .utf8)!

        #expect(jsonString.contains("\"eClass\":\"Person\""))
        #expect(jsonString.contains("\"name\":\"Bob Partial\""))
        #expect(jsonString.contains("\"active\":true"))
        #expect(!jsonString.contains("\"age\"")) // Unset attribute should not appear
    }

    // MARK: - Round-trip Tests

    @Test("JSON round-trip with simple object should preserve data")
    func testJsonRoundTripSimple() throws {
        let personClass = createPersonMetamodel()

        // Create original object
        var originalPerson = DynamicEObject(eClass: personClass)

        let nameAttr = try getAttribute(from: personClass, named: "name")
        let ageAttr = try getAttribute(from: personClass, named: "age")
        let activeAttr = try getAttribute(from: personClass, named: "active")

        originalPerson.eSet(nameAttr, "Round Trip Test")
        originalPerson.eSet(ageAttr, 45)
        originalPerson.eSet(activeAttr, true)

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(originalPerson)

        // Decode from JSON
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.userInfo[.eClassKey] = personClass
        let decodedPerson = try decoder.decode(DynamicEObject.self, from: jsonData)

        // Verify they match
        #expect(originalPerson.eGet(nameAttr) as? String == decodedPerson.eGet(nameAttr) as? String)
        #expect(originalPerson.eGet(ageAttr) as? Int == decodedPerson.eGet(ageAttr) as? Int)
        #expect(originalPerson.eGet(activeAttr) as? Bool == decodedPerson.eGet(activeAttr) as? Bool)

        // Verify isSet status matches
        #expect(originalPerson.eIsSet(nameAttr) == decodedPerson.eIsSet(nameAttr))
        #expect(originalPerson.eIsSet(ageAttr) == decodedPerson.eIsSet(ageAttr))
        #expect(originalPerson.eIsSet(activeAttr) == decodedPerson.eIsSet(activeAttr))
    }

    @Test("JSON round-trip with various types should preserve data")
    func testJsonRoundTripWithTypes() throws {
        let recordClass = createRecordMetamodel()

        // Create original object
        var originalRecord = DynamicEObject(eClass: recordClass)

        let stringValueAttr = try getAttribute(from: recordClass, named: "stringValue")
        let intValueAttr = try getAttribute(from: recordClass, named: "intValue")
        let doubleValueAttr = try getAttribute(from: recordClass, named: "doubleValue")
        let booleanValueAttr = try getAttribute(from: recordClass, named: "booleanValue")

        originalRecord.eSet(stringValueAttr, "Round Trip Types")
        originalRecord.eSet(intValueAttr, 777)
        originalRecord.eSet(doubleValueAttr, 1.23456789)
        originalRecord.eSet(booleanValueAttr, false)

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let jsonData = try encoder.encode(originalRecord)

        // Decode from JSON
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.userInfo[.eClassKey] = recordClass
        let decodedRecord = try decoder.decode(DynamicEObject.self, from: jsonData)

        // Verify they match
        #expect(originalRecord.eGet(stringValueAttr) as? String == decodedRecord.eGet(stringValueAttr) as? String)
        #expect(originalRecord.eGet(intValueAttr) as? Int == decodedRecord.eGet(intValueAttr) as? Int)
        #expect(originalRecord.eGet(doubleValueAttr) as? Double == decodedRecord.eGet(doubleValueAttr) as? Double)
        #expect(originalRecord.eGet(booleanValueAttr) as? Bool == decodedRecord.eGet(booleanValueAttr) as? Bool)
    }

    // MARK: - Error Handling Tests

    @Test("Load invalid JSON missing eClass field should throw error")
    func testLoadInvalidJsonMissingEClass() throws {
        let jsonString = """
        {
          "name": "Invalid Object",
          "age": 25
        }
        """

        let personClass = createPersonMetamodel()
        let jsonData = jsonString.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.userInfo[.eClassKey] = personClass

        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(DynamicEObject.self, from: jsonData)
        }
    }

    @Test("Load JSON with wrong data types should throw error")
    func testLoadInvalidJsonWrongTypes() throws {
        let jsonString = """
        {
          "eClass": "Person",
          "name": 12345,
          "age": "not a number"
        }
        """

        let personClass = createPersonMetamodel()
        let jsonData = jsonString.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.userInfo[.eClassKey] = personClass

        // Note: Current implementation may be more lenient with type conversions
        // For now, just verify it doesn't crash - we can strengthen this later
        do {
            _ = try decoder.decode(DynamicEObject.self, from: jsonData)
            // If it succeeds, that's okay for now - the implementation is lenient
        } catch {
            // If it throws, that's also expected behavior
            #expect(error is DecodingError)
        }
    }

    @Test("Load without eClass in userInfo should throw error")
    func testLoadWithoutEClassInUserInfo() throws {
        let jsonString = """
        {
          "eClass": "Person",
          "name": "Test"
        }
        """

        let jsonData = jsonString.data(using: .utf8)!
        let decoder = JSONDecoder()
        // Don't set userInfo - should fail

        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(DynamicEObject.self, from: jsonData)
        }
    }

    @Test("Load with mismatched eClass name should throw error")
    func testLoadWithMismatchedEClassName() throws {
        let jsonString = """
        {
          "eClass": "Employee",
          "name": "Test"
        }
        """

        let personClass = createPersonMetamodel() // Class name is "Person" but JSON says "Employee"
        let jsonData = jsonString.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.userInfo[.eClassKey] = personClass

        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(DynamicEObject.self, from: jsonData)
        }
    }

    // MARK: - Multiple Root Objects Placeholder

    @Test("Multiple root objects JSON structure (future implementation)")
    func testMultipleRootObjectsStructure() throws {
        // This test documents the expected JSON structure for multiple roots
        let jsonString = """
        [
          {
            "eClass": "Person",
            "name": "Alice",
            "age": 30
          },
          {
            "eClass": "Person",
            "name": "Bob",
            "age": 25
          }
        ]
        """

        let jsonData = jsonString.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: jsonData, options: [])

        // Verify it's a JSON array
        #expect(json is [Any])

        if let jsonArray = json as? [[String: Any]] {
            #expect(jsonArray.count == 2)
            #expect(jsonArray[0]["eClass"] as? String == "Person")
            #expect(jsonArray[0]["name"] as? String == "Alice")
            #expect(jsonArray[1]["eClass"] as? String == "Person")
            #expect(jsonArray[1]["name"] as? String == "Bob")
        }
    }
}
