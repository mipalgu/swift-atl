//
// EObjectTests.swift
// SwiftEcore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
@testable import SwiftEcore
import Foundation

// MARK: - Mock Types for Testing

struct MockClassifier: EClassifier {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

struct MockFeature: EStructuralFeature {
    let id: UUID
    var name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

struct MockEObject: EObject {
    typealias Classifier = MockClassifier

    let id: UUID
    private var storage: EObjectStorage
    let eClass: MockClassifier

    init(id: UUID = UUID(), classifier: MockClassifier) {
        self.id = id
        self.storage = EObjectStorage()
        self.eClass = classifier
    }

    func eGet<F: EStructuralFeature>(_ feature: F) -> (any EcoreValue)? {
        return storage.get(feature: feature.id)
    }

    mutating func eSet<F: EStructuralFeature>(_ feature: F, _ value: (any EcoreValue)?) {
        storage.set(feature: feature.id, value: value)
    }

    func eIsSet<F: EStructuralFeature>(_ feature: F) -> Bool {
        return storage.isSet(feature: feature.id)
    }

    mutating func eUnset<F: EStructuralFeature>(_ feature: F) {
        storage.unset(feature: feature.id)
    }
}

// MARK: - Tests

@Test func testEObjectHasID() {
    let classifier = MockClassifier(name: "TestClass")
    let obj = MockEObject(classifier: classifier)

    #expect(obj.id != UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
}

@Test func testEObjectHasEClass() {
    let classifier = MockClassifier(name: "TestClass")
    let obj = MockEObject(classifier: classifier)

    #expect(obj.eClass.name == "TestClass")
}

@Test func testEObjectSetAndGetFeature() {
    let classifier = MockClassifier(name: "TestClass")
    var obj = MockEObject(classifier: classifier)
    let feature = MockFeature(name: "name")

    // Initially not set
    #expect(obj.eGet(feature) == nil)

    // Set a value
    obj.eSet(feature, "test value")

    // Get the value
    let value = obj.eGet(feature) as? String
    #expect(value == "test value")
}

@Test func testEObjectIsSet() {
    let classifier = MockClassifier(name: "TestClass")
    var obj = MockEObject(classifier: classifier)
    let feature = MockFeature(name: "name")

    // Initially not set
    #expect(obj.eIsSet(feature) == false)

    // Set a value
    obj.eSet(feature, "test")

    // Now it's set
    #expect(obj.eIsSet(feature) == true)
}

@Test func testEObjectUnset() {
    let classifier = MockClassifier(name: "TestClass")
    var obj = MockEObject(classifier: classifier)
    let feature = MockFeature(name: "name")

    // Set a value
    obj.eSet(feature, "test")
    #expect(obj.eIsSet(feature) == true)

    // Unset the value
    obj.eUnset(feature)

    // Now it's not set
    #expect(obj.eIsSet(feature) == false)
    #expect(obj.eGet(feature) == nil)
}

@Test func testEObjectMultipleFeatures() {
    let classifier = MockClassifier(name: "TestClass")
    var obj = MockEObject(classifier: classifier)
    let nameFeature = MockFeature(name: "name")
    let ageFeature = MockFeature(name: "age")

    // Set multiple features
    obj.eSet(nameFeature, "John")
    obj.eSet(ageFeature, 42)

    // Get multiple features
    #expect(obj.eGet(nameFeature) as? String == "John")
    #expect(obj.eGet(ageFeature) as? Int == 42)

    // Both are set
    #expect(obj.eIsSet(nameFeature) == true)
    #expect(obj.eIsSet(ageFeature) == true)
}

@Test func testEObjectSetNilUnsetsFeature() {
    let classifier = MockClassifier(name: "TestClass")
    var obj = MockEObject(classifier: classifier)
    let feature = MockFeature(name: "name")

    // Set a value
    obj.eSet(feature, "test")
    #expect(obj.eIsSet(feature) == true)

    // Set to nil
    obj.eSet(feature, nil)

    // Now it's not set
    #expect(obj.eIsSet(feature) == false)
    #expect(obj.eGet(feature) == nil)
}

@Test func testEObjectEquality() {
    let classifier = MockClassifier(name: "TestClass")
    let id = UUID()

    let obj1 = MockEObject(id: id, classifier: classifier)
    let obj2 = MockEObject(id: id, classifier: classifier)

    // Same ID means equal
    #expect(obj1 == obj2)
    #expect(obj1.hashValue == obj2.hashValue)
}

@Test func testEObjectInequality() {
    let classifier = MockClassifier(name: "TestClass")

    let obj1 = MockEObject(classifier: classifier)
    let obj2 = MockEObject(classifier: classifier)

    // Different IDs means not equal
    #expect(obj1 != obj2)
}

@Test func testEObjectStorageInitialization() {
    let storage = EObjectStorage()
    let featureID = UUID()

    #expect(storage.get(feature: featureID) == nil)
    #expect(storage.isSet(feature: featureID) == false)
}

@Test func testEObjectStorageSetAndGet() {
    var storage = EObjectStorage()
    let featureID = UUID()

    storage.set(feature: featureID, value: "test")

    #expect(storage.get(feature: featureID) as? String == "test")
    #expect(storage.isSet(feature: featureID) == true)
}

@Test func testEObjectStorageUnset() {
    var storage = EObjectStorage()
    let featureID = UUID()

    storage.set(feature: featureID, value: "test")
    storage.unset(feature: featureID)

    #expect(storage.get(feature: featureID) == nil)
    #expect(storage.isSet(feature: featureID) == false)
}

@Test func testEObjectStorageEquality() {
    var storage1 = EObjectStorage()
    var storage2 = EObjectStorage()
    let featureID = UUID()

    storage1.set(feature: featureID, value: "test")
    storage2.set(feature: featureID, value: "test")

    #expect(storage1 == storage2)
}

@Test func testEObjectStorageInequality() {
    var storage1 = EObjectStorage()
    var storage2 = EObjectStorage()
    let featureID = UUID()

    storage1.set(feature: featureID, value: "test")
    storage2.set(feature: featureID, value: "different")

    #expect(storage1 != storage2)
}

@Test func testEObjectStorageHash() {
    var storage1 = EObjectStorage()
    var storage2 = EObjectStorage()
    let featureID = UUID()

    storage1.set(feature: featureID, value: "test")
    storage2.set(feature: featureID, value: "test")

    #expect(storage1.hashValue == storage2.hashValue)
}

@Test func testEObjectIsEcoreValue() {
    // EObject types are automatically EcoreValues, allowing them to be stored
    let classifier = MockClassifier(name: "TestClass")
    let obj = MockEObject(classifier: classifier)

    // Can be stored as an EcoreValue
    let value: any EcoreValue = obj
    #expect(value is MockEObject)

    // Can be stored in another object's storage
    var storage = EObjectStorage()
    let featureID = UUID()
    storage.set(feature: featureID, value: obj)

    let retrieved = storage.get(feature: featureID)
    #expect(retrieved is MockEObject)
}
