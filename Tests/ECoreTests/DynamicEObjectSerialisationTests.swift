//
// DynamicEObjectSerialisationTests.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
@testable import ECore
import Foundation

// MARK: - Test Constants

private let personClassName = "Person"
private let employeeClassName = "Employee"
private let stringTypeName = "EString"
private let intTypeName = "EInt"
private let boolTypeName = "EBoolean"

// MARK: - Test Suite

@Suite("Dynamic EObject Serialisation Tests")
struct DynamicEObjectSerialisationTests {

    // MARK: - JSON Encoding Tests

    @Test func testEncodeSimpleObject() throws {
        // Create a simple Person class
        let stringType = EDataType(name: stringTypeName)
        let intType = EDataType(name: intTypeName)

        let nameAttr = EAttribute(name: "name", eType: stringType)
        let ageAttr = EAttribute(name: "age", eType: intType)

        let personClass = EClass(
            name: personClassName,
            eStructuralFeatures: [nameAttr, ageAttr]
        )

        // Create an instance
        var person = DynamicEObject(eClass: personClass)
        person.eSet(nameAttr, "Alice")
        person.eSet(ageAttr, 30)

        // Encode to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(person)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            #expect(Bool(false), "Failed to convert JSON data to string")
            return
        }

        // Verify JSON structure
        #expect(jsonString.contains("\"eClass\" : \"Person\""))
        #expect(jsonString.contains("\"name\" : \"Alice\""))
        #expect(jsonString.contains("\"age\" : 30"))
    }

    @Test func testEncodeObjectWithOnlyName() throws {
        // Create a simple class with only name
        let stringType = EDataType(name: stringTypeName)
        let nameAttr = EAttribute(name: "name", eType: stringType)

        let personClass = EClass(
            name: personClassName,
            eStructuralFeatures: [nameAttr]
        )

        var person = DynamicEObject(eClass: personClass)
        person.eSet(nameAttr, "Bob")

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(person)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            #expect(Bool(false), "Failed to convert JSON data to string")
            return
        }

        #expect(jsonString.contains("\"eClass\""))
        #expect(jsonString.contains("\"name\""))
        #expect(jsonString.contains("Bob"))
    }

    @Test func testEncodeObjectWithBooleanAttribute() throws {
        let boolType = EDataType(name: boolTypeName)
        let activeAttr = EAttribute(name: "active", eType: boolType)

        let personClass = EClass(
            name: personClassName,
            eStructuralFeatures: [activeAttr]
        )

        var person = DynamicEObject(eClass: personClass)
        person.eSet(activeAttr, true)

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(person)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            #expect(Bool(false), "Failed to convert JSON data to string")
            return
        }

        #expect(jsonString.contains("\"active\""))
        #expect(jsonString.contains("true"))
    }

    @Test func testEncodeObjectWithUnsetAttributes() throws {
        // Create a class with multiple attributes
        let stringType = EDataType(name: stringTypeName)
        let intType = EDataType(name: intTypeName)

        let nameAttr = EAttribute(name: "name", eType: stringType)
        let ageAttr = EAttribute(name: "age", eType: intType)

        let personClass = EClass(
            name: personClassName,
            eStructuralFeatures: [nameAttr, ageAttr]
        )

        // Only set name, leave age unset
        var person = DynamicEObject(eClass: personClass)
        person.eSet(nameAttr, "Charlie")

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(person)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            #expect(Bool(false), "Failed to convert JSON data to string")
            return
        }

        // Should only include set attributes
        #expect(jsonString.contains("\"name\""))
        #expect(!jsonString.contains("\"age\""))
    }

    // MARK: - JSON Decoding Tests

    @Test func testDecodeSimpleObject() throws {
        // Create metamodel
        let stringType = EDataType(name: stringTypeName)
        let intType = EDataType(name: intTypeName)

        let nameAttr = EAttribute(name: "name", eType: stringType)
        let ageAttr = EAttribute(name: "age", eType: intType)

        let personClass = EClass(
            name: personClassName,
            eStructuralFeatures: [nameAttr, ageAttr]
        )

        // Create JSON
        let json = """
        {
            "eClass": "Person",
            "name": "Diana",
            "age": 25
        }
        """
        guard let jsonData = json.data(using: .utf8) else {
            #expect(Bool(false), "Failed to convert JSON string to data")
            return
        }

        // Decode
        let decoder = JSONDecoder()
        decoder.userInfo[.eClassKey] = personClass
        let person = try decoder.decode(DynamicEObject.self, from: jsonData)

        // Verify
        #expect(person.eClass.name == personClassName)
        #expect(person.eGet(nameAttr) as? String == "Diana")
        #expect(person.eGet(ageAttr) as? Int == 25)
    }

    @Test func testDecodeObjectWithPartialAttributes() throws {
        // Create metamodel
        let stringType = EDataType(name: stringTypeName)
        let intType = EDataType(name: intTypeName)

        let nameAttr = EAttribute(name: "name", eType: stringType)
        let ageAttr = EAttribute(name: "age", eType: intType)

        let personClass = EClass(
            name: personClassName,
            eStructuralFeatures: [nameAttr, ageAttr]
        )

        // JSON with only name
        let json = """
        {
            "eClass": "Person",
            "name": "Eve"
        }
        """
        guard let jsonData = json.data(using: .utf8) else {
            #expect(Bool(false), "Failed to convert JSON string to data")
            return
        }

        // Decode
        let decoder = JSONDecoder()
        decoder.userInfo[.eClassKey] = personClass
        let person = try decoder.decode(DynamicEObject.self, from: jsonData)

        // Verify
        #expect(person.eGet(nameAttr) as? String == "Eve")
        #expect(person.eIsSet(ageAttr) == false)
        #expect(person.eGet(ageAttr) == nil)
    }

    // MARK: - Round-Trip Tests

    @Test func testRoundTripSimpleObject() throws {
        // Create metamodel
        let stringType = EDataType(name: stringTypeName)
        let intType = EDataType(name: intTypeName)

        let nameAttr = EAttribute(name: "name", eType: stringType)
        let ageAttr = EAttribute(name: "age", eType: intType)

        let personClass = EClass(
            name: personClassName,
            eStructuralFeatures: [nameAttr, ageAttr]
        )

        // Create original object
        var original = DynamicEObject(eClass: personClass)
        original.eSet(nameAttr, "Frank")
        original.eSet(ageAttr, 35)

        // Encode
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(original)

        // Decode
        let decoder = JSONDecoder()
        decoder.userInfo[.eClassKey] = personClass
        let decoded = try decoder.decode(DynamicEObject.self, from: jsonData)

        // Verify values match
        #expect(decoded.eClass.name == original.eClass.name)
        #expect(decoded.eGet(nameAttr) as? String == original.eGet(nameAttr) as? String)
        #expect(decoded.eGet(ageAttr) as? Int == original.eGet(ageAttr) as? Int)
    }

    @Test func testRoundTripWithBooleanAndDouble() throws {
        // Create metamodel
        let boolType = EDataType(name: boolTypeName)
        let doubleType = EDataType(name: "EDouble")

        let activeAttr = EAttribute(name: "active", eType: boolType)
        let scoreAttr = EAttribute(name: "score", eType: doubleType)

        let recordClass = EClass(
            name: "Record",
            eStructuralFeatures: [activeAttr, scoreAttr]
        )

        // Create object
        var original = DynamicEObject(eClass: recordClass)
        original.eSet(activeAttr, true)
        original.eSet(scoreAttr, 98.5)

        // Round-trip
        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(original)

        let decoder = JSONDecoder()
        decoder.userInfo[.eClassKey] = recordClass
        let decoded = try decoder.decode(DynamicEObject.self, from: jsonData)

        // Verify
        #expect(decoded.eGet(activeAttr) as? Bool == true)
        #expect(decoded.eGet(scoreAttr) as? Double == 98.5)
    }

    // MARK: - Error Handling Tests

    @Test func testDecodeWithoutEClassInUserInfo() throws {
        let json = """
        {
            "eClass": "Person",
            "name": "Grace"
        }
        """
        guard let jsonData = json.data(using: .utf8) else {
            #expect(Bool(false), "Failed to convert JSON string to data")
            return
        }

        let decoder = JSONDecoder()
        // Don't set userInfo - should fail

        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(DynamicEObject.self, from: jsonData)
        }
    }

    @Test func testDecodeWithMismatchedEClassName() throws {
        // Create metamodel
        let stringType = EDataType(name: stringTypeName)
        let nameAttr = EAttribute(name: "name", eType: stringType)

        let personClass = EClass(
            name: "Employee",  // Different name
            eStructuralFeatures: [nameAttr]
        )

        // JSON says "Person" but we provide "Employee" class
        let json = """
        {
            "eClass": "Person",
            "name": "Henry"
        }
        """
        guard let jsonData = json.data(using: .utf8) else {
            #expect(Bool(false), "Failed to convert JSON string to data")
            return
        }

        let decoder = JSONDecoder()
        decoder.userInfo[.eClassKey] = personClass

        #expect(throws: DecodingError.self) {
            _ = try decoder.decode(DynamicEObject.self, from: jsonData)
        }
    }
}
