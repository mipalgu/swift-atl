//
// EcoreValueTests.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
import Foundation
@testable import ECore

// MARK: - Test Constants

// Test values
private let testString = "test"
private let differentString = "different"
private let intValue = 42
private let floatValue: Float = 3.14
private let doubleValue = 3.14159

@Test func testStringIsEcoreValue() {
    let value: any EcoreValue = testString
    #expect(value as? String == testString)
}

@Test func testIntIsEcoreValue() {
    let value: any EcoreValue = intValue
    #expect(value as? Int == intValue)
}

@Test func testBoolIsEcoreValue() {
    let value: any EcoreValue = true
    #expect(value as? Bool == true)
}

@Test func testFloatIsEcoreValue() {
    let value: any EcoreValue = floatValue
    #expect(value as? Float == floatValue)
}

@Test func testDoubleIsEcoreValue() {
    let value: any EcoreValue = doubleValue
    #expect(value as? Double == doubleValue)
}

@Test func testUUIDIsEcoreValue() {
    let uuid = UUID()
    let value: any EcoreValue = uuid
    #expect(value as? UUID == uuid)
}

@Test func testEcoreValueEquality() {
    let value1: any EcoreValue = testString
    let value2: any EcoreValue = testString

    // Use string representation for comparison (simplified)
    #expect(String(describing: value1) == String(describing: value2))
}

@Test func testEcoreValueInequality() {
    let value1: any EcoreValue = testString
    let value2: any EcoreValue = differentString

    #expect(String(describing: value1) != String(describing: value2))
}
