//
// EModelElementTests.swift
// SwiftEcore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
@testable import SwiftEcore
import Foundation

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
        classifier: MockClassifier = MockClassifier(name: "MockNamedElement"),
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
    let annotation = EAnnotation(source: "http://test.com")

    #expect(annotation.source == "http://test.com")
    #expect(annotation.details.isEmpty)
}

@Test func testEAnnotationWithDetails() {
    let annotation = EAnnotation(
        source: "http://test.com",
        details: ["key1": "value1", "key2": "value2"]
    )

    #expect(annotation.details["key1"] == "value1")
    #expect(annotation.details["key2"] == "value2")
}

@Test func testEAnnotationEquality() {
    let id = EUUID()
    let annotation1 = EAnnotation(id: id, source: "http://test.com")
    let annotation2 = EAnnotation(id: id, source: "http://test.com")

    #expect(annotation1 == annotation2)
}

@Test func testEAnnotationInequality() {
    let annotation1 = EAnnotation(source: "http://test1.com")
    let annotation2 = EAnnotation(source: "http://test2.com")

    #expect(annotation1 != annotation2)
}

@Test func testEAnnotationHash() {
    let id = EUUID()
    let annotation1 = EAnnotation(id: id, source: "http://test.com")
    let annotation2 = EAnnotation(id: id, source: "http://test.com")

    #expect(annotation1.hashValue == annotation2.hashValue)
}

@Test func testEAnnotationIsEcoreValue() {
    let annotation = EAnnotation(source: "http://test.com")
    let value: any EcoreValue = annotation

    #expect(value is EAnnotation)
}

// MARK: - EModelElement Tests

@Test func testEModelElementAnnotations() {
    var element = MockNamedElement(name: "TestElement")

    #expect(element.eAnnotations.isEmpty)

    let annotation = EAnnotation(source: "http://test.com")
    element.eAnnotations.append(annotation)

    #expect(element.eAnnotations.count == 1)
}

@Test func testEModelElementGetAnnotation() {
    let annotation1 = EAnnotation(source: "http://test1.com")
    let annotation2 = EAnnotation(source: "http://test2.com")

    let element = MockNamedElement(
        name: "TestElement",
        eAnnotations: [annotation1, annotation2]
    )

    let found = element.getEAnnotation(source: "http://test1.com")
    #expect(found?.source == "http://test1.com")
}

@Test func testEModelElementGetAnnotationNotFound() {
    let element = MockNamedElement(name: "TestElement")

    let found = element.getEAnnotation(source: "http://notfound.com")
    #expect(found == nil)
}

@Test func testEModelElementMultipleAnnotations() {
    let annotation1 = EAnnotation(source: "http://test1.com")
    let annotation2 = EAnnotation(source: "http://test2.com")
    let annotation3 = EAnnotation(source: "http://test3.com")

    let element = MockNamedElement(
        name: "TestElement",
        eAnnotations: [annotation1, annotation2, annotation3]
    )

    #expect(element.eAnnotations.count == 3)
    #expect(element.getEAnnotation(source: "http://test2.com")?.source == "http://test2.com")
}

// MARK: - ENamedElement Tests

@Test func testENamedElementCreation() {
    let element = MockNamedElement(name: "TestElement")

    #expect(element.name == "TestElement")
}

@Test func testENamedElementNameChange() {
    var element = MockNamedElement(name: "OldName")

    element.name = "NewName"

    #expect(element.name == "NewName")
}

@Test func testENamedElementEquality() {
    let id = EUUID()
    let element1 = MockNamedElement(id: id, name: "Test")
    let element2 = MockNamedElement(id: id, name: "Test")

    #expect(element1 == element2)
}

@Test func testENamedElementInequality() {
    let element1 = MockNamedElement(name: "Test1")
    let element2 = MockNamedElement(name: "Test2")

    #expect(element1 != element2)
}

@Test func testENamedElementIsEObject() {
    let element = MockNamedElement(name: "Test")
    let obj: any EObject = element

    #expect(obj is MockNamedElement)
}

@Test func testENamedElementIsEModelElement() {
    let element = MockNamedElement(name: "Test")
    let modelElement: any EModelElement = element

    #expect(modelElement is MockNamedElement)
}

@Test func testENamedElementWithAnnotations() {
    let annotation = EAnnotation(
        source: "http://test.com",
        details: ["documentation": "This is a test element"]
    )

    let element = MockNamedElement(
        name: "DocumentedElement",
        eAnnotations: [annotation]
    )

    #expect(element.name == "DocumentedElement")
    #expect(element.eAnnotations.count == 1)

    let found = element.getEAnnotation(source: "http://test.com")
    #expect(found?.details["documentation"] == "This is a test element")
}
