//
// EObjectTests.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
@testable import ECore
import Foundation

// MARK: - Test Constants

// Class names
private let testClassName = "TestClass"

// Feature names
private let nameFeatureName = "name"
private let ageFeatureName = "age"

// Test values
private let testValue = "test value"
private let testString = "test"
private let johnName = "John"
private let ageValue = 42
private let differentValue = "different"

// UUID constants
private let nullUUID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

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
    let classifier = MockClassifier(name: testClassName)
    let obj = MockEObject(classifier: classifier)

    #expect(obj.id != nullUUID)
}

@Test func testEObjectHasEClass() {
    let classifier = MockClassifier(name: testClassName)
    let obj = MockEObject(classifier: classifier)

    #expect(obj.eClass.name == testClassName)
}

@Test func testEObjectSetAndGetFeature() {
    let classifier = MockClassifier(name: testClassName)
    var obj = MockEObject(classifier: classifier)
    let feature = MockFeature(name: nameFeatureName)

    // Initially not set
    #expect(obj.eGet(feature) == nil)

    // Set a value
    obj.eSet(feature, testValue)

    // Get the value
    let value = obj.eGet(feature) as? String
    #expect(value == testValue)
}

@Test func testEObjectIsSet() {
    let classifier = MockClassifier(name: testClassName)
    var obj = MockEObject(classifier: classifier)
    let feature = MockFeature(name: nameFeatureName)

    // Initially not set
    #expect(obj.eIsSet(feature) == false)

    // Set a value
    obj.eSet(feature, testString)

    // Now it's set
    #expect(obj.eIsSet(feature) == true)
}

@Test func testEObjectUnset() {
    let classifier = MockClassifier(name: testClassName)
    var obj = MockEObject(classifier: classifier)
    let feature = MockFeature(name: nameFeatureName)

    // Set a value
    obj.eSet(feature, testString)
    #expect(obj.eIsSet(feature) == true)

    // Unset the value
    obj.eUnset(feature)

    // Now it's not set
    #expect(obj.eIsSet(feature) == false)
    #expect(obj.eGet(feature) == nil)
}

@Test func testEObjectMultipleFeatures() {
    let classifier = MockClassifier(name: testClassName)
    var obj = MockEObject(classifier: classifier)
    let nameFeature = MockFeature(name: nameFeatureName)
    let ageFeature = MockFeature(name: ageFeatureName)

    // Set multiple features
    obj.eSet(nameFeature, johnName)
    obj.eSet(ageFeature, ageValue)

    // Get multiple features
    #expect(obj.eGet(nameFeature) as? String == johnName)
    #expect(obj.eGet(ageFeature) as? Int == ageValue)

    // Both are set
    #expect(obj.eIsSet(nameFeature) == true)
    #expect(obj.eIsSet(ageFeature) == true)
}

@Test func testEObjectSetNilUnsetsFeature() {
    let classifier = MockClassifier(name: testClassName)
    var obj = MockEObject(classifier: classifier)
    let feature = MockFeature(name: nameFeatureName)

    // Set a value
    obj.eSet(feature, testString)
    #expect(obj.eIsSet(feature) == true)

    // Set to nil
    obj.eSet(feature, nil)

    // Now it's not set
    #expect(obj.eIsSet(feature) == false)
    #expect(obj.eGet(feature) == nil)
}

@Test func testEObjectEquality() {
    let classifier = MockClassifier(name: testClassName)
    let id = UUID()

    let obj1 = MockEObject(id: id, classifier: classifier)
    let obj2 = MockEObject(id: id, classifier: classifier)

    // Same ID means equal
    #expect(obj1 == obj2)
    #expect(obj1.hashValue == obj2.hashValue)
}

@Test func testEObjectInequality() {
    let classifier = MockClassifier(name: testClassName)

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

    storage.set(feature: featureID, value: testString)

    #expect(storage.get(feature: featureID) as? String == testString)
    #expect(storage.isSet(feature: featureID) == true)
}

@Test func testEObjectStorageUnset() {
    var storage = EObjectStorage()
    let featureID = UUID()

    storage.set(feature: featureID, value: testString)
    storage.unset(feature: featureID)

    #expect(storage.get(feature: featureID) == nil)
    #expect(storage.isSet(feature: featureID) == false)
}

@Test func testEObjectStorageEquality() {
    var storage1 = EObjectStorage()
    var storage2 = EObjectStorage()
    let featureID = UUID()

    storage1.set(feature: featureID, value: testString)
    storage2.set(feature: featureID, value: testString)

    #expect(storage1 == storage2)
}

@Test func testEObjectStorageInequality() {
    var storage1 = EObjectStorage()
    var storage2 = EObjectStorage()
    let featureID = UUID()

    storage1.set(feature: featureID, value: testString)
    storage2.set(feature: featureID, value: differentValue)

    #expect(storage1 != storage2)
}

@Test func testEObjectStorageHash() {
    var storage1 = EObjectStorage()
    var storage2 = EObjectStorage()
    let featureID = UUID()

    storage1.set(feature: featureID, value: testString)
    storage2.set(feature: featureID, value: testString)

    #expect(storage1.hashValue == storage2.hashValue)
}

@Test func testEObjectIsEcoreValue() {
    // EObject types are automatically EcoreValues, allowing them to be stored
    let classifier = MockClassifier(name: testClassName)
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
