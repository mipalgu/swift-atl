//
// EClassifierTests.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
@testable import ECore
import Foundation

// MARK: - Test Constants

// Common type names
private let eStringTypeName = "EString"
private let eIntTypeName = "EInt"
private let complexTypeName = "ComplexType"
private let birdTypeName = "BirdType"
private let colorTypeName = "ColorType"

// Swift type names
private let swiftStringClassName = "Swift.String"

// Default values
private let zeroLiteral = "0"

// Enum literal names
private let blackbirdName = "blackbird"
private let thrushName = "thrush"
private let bluebirdName = "bluebird"
private let redbreastName = "redbreast"
private let nightingaleName = "nightingale"
private let robinName = "robin"

// Enum literal uppercase forms
private let blackbirdUppercase = blackbirdName.uppercased()

// Enum literal values
private let blackbirdValue = 0
private let thrushValue = 1
private let bluebirdValue = 2
private let redbreastValue = 3
private let nightingaleValue = 4
private let nonExistentValue = 99

// Annotation sources
private let genModelSource = "http://www.eclipse.org/emf/2002/GenModel"

// Annotation details
private let documentationKey = "documentation"
private let stringDataTypeDoc = "A string data type"

// Magic numbers for counts and indices
private let expectedLiteralCount3 = 3
private let expectedLiteralCount5 = 5
private let expectedAnnotationCount1 = 1
private let firstIndex = 0
private let secondIndex = 1

// MARK: - EDataType Tests

@Test func testEDataTypeCreation() {
    let dataType = EDataType(
        name: eStringTypeName,
        instanceClassName: swiftStringClassName
    )

    #expect(dataType.name == eStringTypeName)
    #expect(dataType.instanceClassName == swiftStringClassName)
    #expect(dataType.serialisable == true)  // Default value
}

@Test func testEDataTypeWithDefaultValue() {
    let dataType = EDataType(
        name: eIntTypeName,
        defaultValueLiteral: zeroLiteral
    )

    #expect(dataType.defaultValueLiteral == zeroLiteral)
}

@Test func testEDataTypeNonSerialisable() {
    let dataType = EDataType(
        name: complexTypeName,
        serialisable: false
    )

    #expect(dataType.serialisable == false)
}

@Test func testEDataTypeEquality() {
    let id = EUUID()
    let dataType1 = EDataType(id: id, name: eStringTypeName)
    let dataType2 = EDataType(id: id, name: eStringTypeName)

    #expect(dataType1 == dataType2)
    #expect(dataType1.hashValue == dataType2.hashValue)
}

@Test func testEDataTypeInequality() {
    let dataType1 = EDataType(name: eStringTypeName)
    let dataType2 = EDataType(name: eIntTypeName)

    #expect(dataType1 != dataType2)
}

@Test func testEDataTypeIsENamedElement() {
    let dataType = EDataType(name: eStringTypeName)
    let namedElement: any ENamedElement = dataType

    #expect(namedElement is EDataType)
    #expect(namedElement.name == eStringTypeName)
}

@Test func testEDataTypeWithAnnotations() {
    let annotation = EAnnotation(
        source: genModelSource,
        details: [documentationKey: stringDataTypeDoc]
    )

    let dataType = EDataType(
        name: eStringTypeName,
        eAnnotations: [annotation]
    )

    #expect(dataType.eAnnotations.count == expectedAnnotationCount1)
    let found = dataType.getEAnnotation(source: genModelSource)
    #expect(found?.details[documentationKey] == stringDataTypeDoc)
}

// MARK: - EEnumLiteral Tests

@Test func testEEnumLiteralCreation() {
    let literal = EEnumLiteral(
        name: blackbirdName,
        value: blackbirdValue
    )

    #expect(literal.name == blackbirdName)
    #expect(literal.value == blackbirdValue)
    #expect(literal.literal == nil)  // No explicit literal provided
}

@Test func testEEnumLiteralWithLiteral() {
    let literal = EEnumLiteral(
        name: blackbirdName,
        value: blackbirdValue,
        literal: blackbirdUppercase
    )

    #expect(literal.name == blackbirdName)
    #expect(literal.literal == blackbirdUppercase)
}

@Test func testEEnumLiteralEquality() {
    let id = EUUID()
    let literal1 = EEnumLiteral(id: id, name: blackbirdName, value: blackbirdValue)
    let literal2 = EEnumLiteral(id: id, name: blackbirdName, value: blackbirdValue)

    #expect(literal1 == literal2)
    #expect(literal1.hashValue == literal2.hashValue)
}

@Test func testEEnumLiteralInequality() {
    let literal1 = EEnumLiteral(name: blackbirdName, value: blackbirdValue)
    let literal2 = EEnumLiteral(name: thrushName, value: thrushValue)

    #expect(literal1 != literal2)
}

// MARK: - EEnum Tests

@Test func testEEnumCreation() {
    let birdType = EEnum(name: birdTypeName)

    #expect(birdType.name == birdTypeName)
    #expect(birdType.literals.isEmpty)
}

@Test func testEEnumWithLiterals() {
    let birdType = EEnum(
        name: birdTypeName,
        literals: [
            EEnumLiteral(name: blackbirdName, value: blackbirdValue),
            EEnumLiteral(name: thrushName, value: thrushValue),
            EEnumLiteral(name: bluebirdName, value: bluebirdValue)
        ]
    )

    #expect(birdType.literals.count == expectedLiteralCount3)
    #expect(birdType.literals[firstIndex].name == blackbirdName)
    #expect(birdType.literals[secondIndex].value == thrushValue)
}

@Test func testEEnumGetLiteralByName() {
    let birdType = EEnum(
        name: birdTypeName,
        literals: [
            EEnumLiteral(name: blackbirdName, value: blackbirdValue),
            EEnumLiteral(name: thrushName, value: thrushValue),
            EEnumLiteral(name: bluebirdName, value: bluebirdValue)
        ]
    )

    let literal = birdType.getLiteral(name: thrushName)
    #expect(literal?.name == thrushName)
    #expect(literal?.value == thrushValue)
}

@Test func testEEnumGetLiteralByValue() {
    let birdType = EEnum(
        name: birdTypeName,
        literals: [
            EEnumLiteral(name: blackbirdName, value: blackbirdValue),
            EEnumLiteral(name: thrushName, value: thrushValue),
            EEnumLiteral(name: bluebirdName, value: bluebirdValue)
        ]
    )

    let literal = birdType.getLiteral(value: thrushValue)
    #expect(literal?.name == thrushName)
}

@Test func testEEnumGetLiteralNotFound() {
    let birdType = EEnum(
        name: birdTypeName,
        literals: [
            EEnumLiteral(name: blackbirdName, value: blackbirdValue)
        ]
    )

    let literalByName = birdType.getLiteral(name: robinName)
    #expect(literalByName == nil)

    let literalByValue = birdType.getLiteral(value: nonExistentValue)
    #expect(literalByValue == nil)
}

@Test func testEEnumEquality() {
    let id = EUUID()
    let enum1 = EEnum(id: id, name: birdTypeName)
    let enum2 = EEnum(id: id, name: birdTypeName)

    #expect(enum1 == enum2)
    #expect(enum1.hashValue == enum2.hashValue)
}

@Test func testEEnumInequality() {
    let enum1 = EEnum(name: birdTypeName)
    let enum2 = EEnum(name: colorTypeName)

    #expect(enum1 != enum2)
}

@Test func testEEnumIsENamedElement() {
    let birdType = EEnum(name: birdTypeName)
    let namedElement: any ENamedElement = birdType

    #expect(namedElement is EEnum)
    #expect(namedElement.name == birdTypeName)
}

// MARK: - Integration Test

@Test func testBirdEnumerationFromEmf4cpp() {
    // Based on: /Users/rh/Library/CloudStorage/Dropbox/Developer/src/other/MetaModels/emf4cpp/emf4cpp.tests/enumeration/enumeration.ecore
    let birdType = EEnum(
        name: birdTypeName,
        literals: [
            EEnumLiteral(name: blackbirdName, value: blackbirdValue, literal: blackbirdName),
            EEnumLiteral(name: thrushName, value: thrushValue, literal: thrushName),
            EEnumLiteral(name: bluebirdName, value: bluebirdValue, literal: bluebirdName),
            EEnumLiteral(name: redbreastName, value: redbreastValue, literal: redbreastName),
            EEnumLiteral(name: nightingaleName, value: nightingaleValue, literal: nightingaleName)
        ]
    )

    #expect(birdType.name == birdTypeName)
    #expect(birdType.literals.count == expectedLiteralCount5)

    // Test lookup by name
    let blackbird = birdType.getLiteral(name: blackbirdName)
    #expect(blackbird?.value == blackbirdValue)

    // Test lookup by value
    let nightingale = birdType.getLiteral(value: nightingaleValue)
    #expect(nightingale?.name == nightingaleName)
}

@Test func testEDataTypeIsEcoreValue() {
    let dataType = EDataType(name: eStringTypeName)
    let value: any EcoreValue = dataType

    #expect(value is EDataType)
}

@Test func testEEnumIsEcoreValue() {
    let birdType = EEnum(name: birdTypeName)
    let value: any EcoreValue = birdType

    #expect(value is EEnum)
}

@Test func testEEnumLiteralIsEcoreValue() {
    let literal = EEnumLiteral(name: blackbirdName, value: blackbirdValue)
    let value: any EcoreValue = literal

    #expect(value is EEnumLiteral)
}
