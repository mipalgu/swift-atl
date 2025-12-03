//
// EcoreValueTests.swift
// SwiftEcore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
import Foundation
@testable import SwiftEcore

@Test func testStringIsEcoreValue() {
    let value: any EcoreValue = "test"
    #expect(value as? String == "test")
}

@Test func testIntIsEcoreValue() {
    let value: any EcoreValue = 42
    #expect(value as? Int == 42)
}

@Test func testBoolIsEcoreValue() {
    let value: any EcoreValue = true
    #expect(value as? Bool == true)
}

@Test func testFloatIsEcoreValue() {
    let value: any EcoreValue = Float(3.14)
    #expect(value as? Float == 3.14)
}

@Test func testDoubleIsEcoreValue() {
    let value: any EcoreValue = 3.14159
    #expect(value as? Double == 3.14159)
}

@Test func testUUIDIsEcoreValue() {
    let uuid = UUID()
    let value: any EcoreValue = uuid
    #expect(value as? UUID == uuid)
}

@Test func testEcoreValueEquality() {
    let value1: any EcoreValue = "test"
    let value2: any EcoreValue = "test"

    // Use string representation for comparison (simplified)
    #expect(String(describing: value1) == String(describing: value2))
}

@Test func testEcoreValueInequality() {
    let value1: any EcoreValue = "test"
    let value2: any EcoreValue = "different"

    #expect(String(describing: value1) != String(describing: value2))
}
