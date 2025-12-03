//
// EModelElementTests.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
@testable import ECore
import Foundation

// MARK: - Test Constants

// URL sources
private let testUrlSource = "http://test.com"
private let testUrl1Source = "http://test1.com"
private let testUrl2Source = "http://test2.com"
private let testUrl3Source = "http://test3.com"
private let notFoundUrlSource = "http://notfound.com"

// Element names
private let testElementName = "TestElement"
private let oldElementName = "OldName"
private let newElementName = "NewName"
private let documentedElementName = "DocumentedElement"

// Classifier names
private let testClassName = "TestClass"
private let mockNamedElementClassName = "MockNamedElement"

// Annotation details
private let documentationKey = "documentation"
private let documentationValue = "This is a test element"
private let key1 = "key1"
private let key2 = "key2"
private let value1 = "value1"
private let value2 = "value2"

// Test names
private let test1Name = "Test1"
private let test2Name = "Test2"

// Magic numbers for counts
private let expectedAnnotationCount1 = 1
private let expectedAnnotationCount3 = 3

// MARK: - Mock Types

struct MockNamedElement: ENamedElement {
    typealias Classifier = MockClassifier

    let id: EUUID
    let eClass: MockClassifier
    var name: String
    var eAnnotations: [EAnnotation]
    private var storage: EObjectStorage

    init(
        id: EUUID = EUUID(),
        classifier: MockClassifier = MockClassifier(name: mockNamedElementClassName),
        name: String,
        eAnnotations: [EAnnotation] = []
    ) {
        self.id = id
        self.eClass = classifier
        self.name = name
        self.eAnnotations = eAnnotations
        self.storage = EObjectStorage()
    }

    func eGet(_ feature: some EStructuralFeature) -> (any EcoreValue)? {
        return storage.get(feature: feature.id)
    }

    mutating func eSet(_ feature: some EStructuralFeature, _ value: (any EcoreValue)?) {
        storage.set(feature: feature.id, value: value)
    }

    func eIsSet(_ feature: some EStructuralFeature) -> Bool {
        return storage.isSet(feature: feature.id)
    }

    mutating func eUnset(_ feature: some EStructuralFeature) {
        storage.unset(feature: feature.id)
    }

    static func == (lhs: MockNamedElement, rhs: MockNamedElement) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

// MARK: - EAnnotation Tests

@Test func testEAnnotationCreation() {
    let annotation = EAnnotation(source: testUrlSource)

    #expect(annotation.source == testUrlSource)
    #expect(annotation.details.isEmpty)
}

@Test func testEAnnotationWithDetails() {
    let annotation = EAnnotation(
        source: testUrlSource,
        details: [key1: value1, key2: value2]
    )

    #expect(annotation.details[key1] == value1)
    #expect(annotation.details[key2] == value2)
}

@Test func testEAnnotationEquality() {
    let id = EUUID()
    let annotation1 = EAnnotation(id: id, source: testUrlSource)
    let annotation2 = EAnnotation(id: id, source: testUrlSource)

    #expect(annotation1 == annotation2)
}

@Test func testEAnnotationInequality() {
    let annotation1 = EAnnotation(source: testUrl1Source)
    let annotation2 = EAnnotation(source: testUrl2Source)

    #expect(annotation1 != annotation2)
}

@Test func testEAnnotationHash() {
    let id = EUUID()
    let annotation1 = EAnnotation(id: id, source: testUrlSource)
    let annotation2 = EAnnotation(id: id, source: testUrlSource)

    #expect(annotation1.hashValue == annotation2.hashValue)
}

@Test func testEAnnotationIsEcoreValue() {
    let annotation = EAnnotation(source: testUrlSource)
    let value: any EcoreValue = annotation

    #expect(value is EAnnotation)
}

// MARK: - EModelElement Tests

@Test func testEModelElementAnnotations() {
    var element = MockNamedElement(name: testElementName)

    #expect(element.eAnnotations.isEmpty)

    let annotation = EAnnotation(source: testUrlSource)
    element.eAnnotations.append(annotation)

    #expect(element.eAnnotations.count == expectedAnnotationCount1)
}

@Test func testEModelElementGetAnnotation() {
    let annotation1 = EAnnotation(source: testUrl1Source)
    let annotation2 = EAnnotation(source: testUrl2Source)

    let element = MockNamedElement(
        name: testElementName,
        eAnnotations: [annotation1, annotation2]
    )

    let found = element.getEAnnotation(source: testUrl1Source)
    #expect(found?.source == testUrl1Source)
}

@Test func testEModelElementGetAnnotationNotFound() {
    let element = MockNamedElement(name: testElementName)

    let found = element.getEAnnotation(source: notFoundUrlSource)
    #expect(found == nil)
}

@Test func testEModelElementMultipleAnnotations() {
    let annotation1 = EAnnotation(source: testUrl1Source)
    let annotation2 = EAnnotation(source: testUrl2Source)
    let annotation3 = EAnnotation(source: testUrl3Source)

    let element = MockNamedElement(
        name: testElementName,
        eAnnotations: [annotation1, annotation2, annotation3]
    )

    #expect(element.eAnnotations.count == expectedAnnotationCount3)
    #expect(element.getEAnnotation(source: testUrl2Source)?.source == testUrl2Source)
}

// MARK: - ENamedElement Tests

@Test func testENamedElementCreation() {
    let element = MockNamedElement(name: testElementName)

    #expect(element.name == testElementName)
}

@Test func testENamedElementNameChange() {
    var element = MockNamedElement(name: oldElementName)

    element.name = newElementName

    #expect(element.name == newElementName)
}

@Test func testENamedElementEquality() {
    let id = EUUID()
    let element1 = MockNamedElement(id: id, name: test1Name)
    let element2 = MockNamedElement(id: id, name: test1Name)

    #expect(element1 == element2)
}

@Test func testENamedElementInequality() {
    let element1 = MockNamedElement(name: test1Name)
    let element2 = MockNamedElement(name: test2Name)

    #expect(element1 != element2)
}

@Test func testENamedElementIsEObject() {
    let element = MockNamedElement(name: test1Name)
    let obj: any EObject = element

    #expect(obj is MockNamedElement)
}

@Test func testENamedElementIsEModelElement() {
    let element = MockNamedElement(name: test1Name)
    let modelElement: any EModelElement = element

    #expect(modelElement is MockNamedElement)
}

@Test func testENamedElementWithAnnotations() {
    let annotation = EAnnotation(
        source: testUrlSource,
        details: [documentationKey: documentationValue]
    )

    let element = MockNamedElement(
        name: documentedElementName,
        eAnnotations: [annotation]
    )

    #expect(element.name == documentedElementName)
    #expect(element.eAnnotations.count == expectedAnnotationCount1)

    let found = element.getEAnnotation(source: testUrlSource)
    #expect(found?.details[documentationKey] == documentationValue)
}
