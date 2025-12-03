//
// EcoreTypesTest.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
@testable import ECore
import BigInt

// MARK: - Test Constants

// Test values
private let testString = "test"
private let helloString = "hello"
private let trueString = "true"
private let falseString = "false"
private let intString = "42"
private let floatString = "3.14"
private let intValue = 42
private let floatValue: Float = 3.14
private let doubleValue = 3.14159
private let byteValue: Int8 = 127
private let shortValue: Int16 = 32767
private let longValue: Int64 = 9223372036854775807
private let bigIntString = "123456789012345678901234567890"
private let bigIntValue = BigInt("123456789012345678901234567890")
private let veryLargeBigIntString = "999999999999999999999999999999999999999999999999999999999999999999"
private let veryLargeBigIntValue = BigInt("999999999999999999999999999999999999999999999999999999999999999999")

// Invalid values
private let invalidNumber = "not a number"
private let invalidBoolString = "not a bool"
private let invalidFloatString = "not a float"
private let invalidBigIntString = "not a big integer"

@Test func testStringTypeAlias() {
    let value: EString = testString
    #expect(value == testString)
}

@Test func testIntTypeAlias() {
    let value: EInt = intValue
    #expect(value == intValue)
}

@Test func testBooleanTypeAlias() {
    let value: EBoolean = true
    #expect(value == true)
}

@Test func testFloatTypeAlias() {
    let value: EFloat = floatValue
    #expect(value == floatValue)
}

@Test func testDoubleTypeAlias() {
    let value: EDouble = doubleValue
    #expect(value == doubleValue)
}

@Test func testByteTypeAlias() {
    let value: EByte = byteValue
    #expect(value == byteValue)
}

@Test func testShortTypeAlias() {
    let value: EShort = shortValue
    #expect(value == shortValue)
}

@Test func testLongTypeAlias() {
    let value: ELong = longValue
    #expect(value == longValue)
}

@Test func testTypeConversionFromString() {
    let convertedInt = EcoreTypeConverter.fromString(intString, as: EInt.self)
    #expect(convertedInt == intValue)

    let boolValue = EcoreTypeConverter.fromString(trueString, as: EBoolean.self)
    #expect(boolValue == true)

    let convertedFloat = EcoreTypeConverter.fromString(floatString, as: EFloat.self)
    #expect(convertedFloat == floatValue)

    let stringValue = EcoreTypeConverter.fromString(helloString, as: EString.self)
    #expect(stringValue == helloString)
}

@Test func testTypeConversionToString() {
    let convertedIntString = EcoreTypeConverter.toString(intValue)
    #expect(convertedIntString == intString)

    let boolString = EcoreTypeConverter.toString(true)
    #expect(boolString == trueString)

    let convertedFloatString = EcoreTypeConverter.toString(floatValue)
    #expect(convertedFloatString.starts(with: floatString))

    let stringString = EcoreTypeConverter.toString(helloString)
    #expect(stringString == helloString)
}

@Test func testInvalidConversions() {
    let invalidInt = EcoreTypeConverter.fromString(invalidNumber, as: EInt.self)
    #expect(invalidInt == nil)

    let invalidBool = EcoreTypeConverter.fromString(invalidBoolString, as: EBoolean.self)
    #expect(invalidBool == nil)

    let invalidFloat = EcoreTypeConverter.fromString(invalidFloatString, as: EFloat.self)
    #expect(invalidFloat == nil)

    let invalidBigInt = EcoreTypeConverter.fromString(invalidBigIntString, as: EBigInteger.self)
    #expect(invalidBigInt == nil)
}

@Test func testBigIntegerTypeAlias() {
    let value: EBigInteger = bigIntValue
    #expect(value == bigIntValue)
}

@Test func testBigIntegerFromString() {
    let convertedBigInt = EcoreTypeConverter.fromString(bigIntString, as: EBigInteger.self)
    #expect(convertedBigInt == bigIntValue)
}

@Test func testBigIntegerToString() {
    let bigIntStringResult = EcoreTypeConverter.toString(bigIntValue)
    #expect(bigIntStringResult == bigIntString)
}

@Test func testBigIntegerIsEcoreValue() {
    let value: any EcoreValue = bigIntValue
    #expect(value as? BigInt == bigIntValue)
}

@Test func testVeryLargeBigInteger() {
    let value: EBigInteger = veryLargeBigIntValue
    #expect(value == veryLargeBigIntValue)
    
    // Verify it's much larger than Int.max
    #expect(veryLargeBigIntValue > BigInt(Int.max))
    
    // Test string conversion round trip
    let stringResult = EcoreTypeConverter.toString(veryLargeBigIntValue)
    #expect(stringResult == veryLargeBigIntString)
    
    // Test parsing from string
    let parsedValue = EcoreTypeConverter.fromString(veryLargeBigIntString, as: EBigInteger.self)
    #expect(parsedValue == veryLargeBigIntValue)
}
