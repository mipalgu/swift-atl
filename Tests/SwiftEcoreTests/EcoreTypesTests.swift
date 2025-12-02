//
// EcoreTypesTest.swift
// SwiftEcore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
@testable import SwiftEcore

@Test func testStringTypeAlias() {
    let value: EString = "test"
    #expect(value == "test")
}

@Test func testIntTypeAlias() {
    let value: EInt = 42
    #expect(value == 42)
}

@Test func testBooleanTypeAlias() {
    let value: EBoolean = true
    #expect(value == true)
}

@Test func testFloatTypeAlias() {
    let value: EFloat = 3.14
    #expect(value == 3.14)
}

@Test func testDoubleTypeAlias() {
    let value: EDouble = 3.14159
    #expect(value == 3.14159)
}

@Test func testByteTypeAlias() {
    let value: EByte = 127
    #expect(value == 127)
}

@Test func testShortTypeAlias() {
    let value: EShort = 32767
    #expect(value == 32767)
}

@Test func testLongTypeAlias() {
    let value: ELong = 9223372036854775807
    #expect(value == 9223372036854775807)
}

@Test func testTypeConversionFromString() {
    let intValue = EcoreTypeConverter.fromString("42", as: EInt.self)
    #expect(intValue == 42)

    let boolValue = EcoreTypeConverter.fromString("true", as: EBoolean.self)
    #expect(boolValue == true)

    let floatValue = EcoreTypeConverter.fromString("3.14", as: EFloat.self)
    #expect(floatValue == 3.14)

    let stringValue = EcoreTypeConverter.fromString("hello", as: EString.self)
    #expect(stringValue == "hello")
}

@Test func testTypeConversionToString() {
    let intString = EcoreTypeConverter.toString(42)
    #expect(intString == "42")

    let boolString = EcoreTypeConverter.toString(true)
    #expect(boolString == "true")

    let floatString = EcoreTypeConverter.toString(3.14)
    #expect(floatString.starts(with: "3.14"))

    let stringString = EcoreTypeConverter.toString("hello")
    #expect(stringString == "hello")
}

@Test func testInvalidConversions() {
    let invalidInt = EcoreTypeConverter.fromString("not a number", as: EInt.self)
    #expect(invalidInt == nil)

    let invalidBool = EcoreTypeConverter.fromString("not a bool", as: EBoolean.self)
    #expect(invalidBool == nil)

    let invalidFloat = EcoreTypeConverter.fromString("not a float", as: EFloat.self)
    #expect(invalidFloat == nil)
}
