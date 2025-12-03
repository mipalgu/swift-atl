//
// EClassTests.swift
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
private let personClassName = "Person"
private let employeeClassName = "Employee"
private let managerClassName = "Manager"
private let animalClassName = "Animal"
private let birdClassName = "Bird"
private let comparableInterfaceName = "Comparable"

// MARK: - Test Suite

@Suite("EClass Tests")
struct EClassTests {

    // MARK: - EClass Creation Tests

        @Test func testEClassCreation() {
            let eClass = EClass(name: personClassName)

            #expect(eClass.name == personClassName)
            #expect(eClass.isAbstract == false)
            #expect(eClass.isInterface == false)
            #expect(eClass.eSuperTypes.isEmpty)
            #expect(eClass.eStructuralFeatures.isEmpty)
            #expect(eClass.eOperations.isEmpty)
            #expect(eClass.eAnnotations.isEmpty)
        }

    @Test func testEClassWithAbstract() {
        let eClass = EClass(
            name: animalClassName,
            isAbstract: true
        )

        #expect(eClass.name == animalClassName)
        #expect(eClass.isAbstract == true)
        #expect(eClass.isInterface == false)
    }

    @Test func testEClassAsInterface() {
        let eClass = EClass(
            name: comparableInterfaceName,
            isInterface: true
        )

        #expect(eClass.name == comparableInterfaceName)
        #expect(eClass.isAbstract == false)
        #expect(eClass.isInterface == true)
    }

    @Test func testEClassWithAnnotations() {
        let genModelSource = "http://www.eclipse.org/emf/2002/GenModel"
        let documentationDetail = "Represents a person in the system"
        let annotation = EAnnotation(
            source: genModelSource,
            details: ["documentation": documentationDetail]
        )

        let eClass = EClass(
            name: personClassName,
            eAnnotations: [annotation]
        )

        #expect(eClass.eAnnotations.count == 1)
        #expect(eClass.eAnnotations[0].source == genModelSource)
        #expect(eClass.eAnnotations[0].details["documentation"] == documentationDetail)
    }

// MARK: - Inheritance Tests

    @Test func testEClassWithSingleSupertype() {
        let person = EClass(name: personClassName)
        let employee = EClass(
            name: employeeClassName,
            eSuperTypes: [person]
        )

        #expect(employee.eSuperTypes.count == 1)
        #expect(employee.eSuperTypes[0].name == personClassName)
    }

    @Test func testEClassWithMultipleSupertypes() {
        let person = EClass(name: personClassName)
        let comparable = EClass(name: comparableInterfaceName, isInterface: true)
        let employee = EClass(
            name: employeeClassName,
            eSuperTypes: [person, comparable]
        )

        #expect(employee.eSuperTypes.count == 2)
        #expect(employee.eSuperTypes[0].name == personClassName)
        #expect(employee.eSuperTypes[1].name == comparableInterfaceName)
    }

    @Test func testAllSuperTypesDirectOnly() {
        let person = EClass(name: personClassName)
        let employee = EClass(
            name: employeeClassName,
            eSuperTypes: [person]
        )

        let allSuper = employee.allSuperTypes
        #expect(allSuper.count == 1)
        #expect(allSuper[0].name == personClassName)
    }

    @Test func testAllSuperTypesTransitive() {
        let person = EClass(name: personClassName)
        let employee = EClass(
            name: employeeClassName,
            eSuperTypes: [person]
        )
        let manager = EClass(
            name: managerClassName,
            eSuperTypes: [employee]
        )

        let allSuper = manager.allSuperTypes
        #expect(allSuper.count == 2)
        #expect(allSuper.contains(where: { $0.name == personClassName }))
        #expect(allSuper.contains(where: { $0.name == employeeClassName }))
    }

    @Test func testAllSuperTypesMultipleInheritance() {
        let person = EClass(name: personClassName)
        let comparable = EClass(name: comparableInterfaceName, isInterface: true)
        let employee = EClass(
            name: employeeClassName,
            eSuperTypes: [person, comparable]
        )

        let allSuper = employee.allSuperTypes
        #expect(allSuper.count == 2)
        #expect(allSuper.contains(where: { $0.name == personClassName }))
        #expect(allSuper.contains(where: { $0.name == comparableInterfaceName }))
    }

    @Test func testIsSuperTypeOfDirect() {
        let person = EClass(name: personClassName)
        let employee = EClass(
            name: employeeClassName,
            eSuperTypes: [person]
        )

        #expect(person.isSuperTypeOf(employee) == true)
        #expect(employee.isSuperTypeOf(person) == false)
    }

    @Test func testIsSuperTypeOfTransitive() {
        let person = EClass(name: personClassName)
        let employee = EClass(
            name: employeeClassName,
            eSuperTypes: [person]
        )
        let manager = EClass(
            name: managerClassName,
            eSuperTypes: [employee]
        )

        #expect(person.isSuperTypeOf(manager) == true)
        #expect(manager.isSuperTypeOf(person) == false)
    }

    @Test func testIsSuperTypeOfUnrelated() {
        let person = EClass(name: personClassName)
        let animal = EClass(name: animalClassName)

        #expect(person.isSuperTypeOf(animal) == false)
        #expect(animal.isSuperTypeOf(person) == false)
    }

// MARK: - Feature Access Tests

    @Test func testEmptyStructuralFeatures() {
        let eClass = EClass(name: personClassName)

        #expect(eClass.eStructuralFeatures.isEmpty)
        #expect(eClass.allStructuralFeatures.isEmpty)
        #expect(eClass.allAttributes.isEmpty)
        #expect(eClass.allReferences.isEmpty)
    }

    @Test func testGetStructuralFeatureNotFound() {
        let eClass = EClass(name: personClassName)

        let feature = eClass.getStructuralFeature(name: "nonexistent")
        #expect(feature == nil)
    }

    @Test func testGetEAttributeNotFound() {
        let eClass = EClass(name: personClassName)

        let attribute = eClass.getEAttribute(name: "nonexistent")
        #expect(attribute == nil)
    }

    @Test func testGetEReferenceNotFound() {
        let eClass = EClass(name: personClassName)

        let reference = eClass.getEReference(name: "nonexistent")
        #expect(reference == nil)
    }

    @Test func testAllContainmentsEmpty() {
        let eClass = EClass(name: personClassName)

        // Class with no features has no containments
        #expect(eClass.allContainments.isEmpty)
    }

// MARK: - Equality and Hashing Tests

    @Test func testEClassEquality() {
        let id = EUUID()
        let class1 = EClass(id: id, name: personClassName)
        let class2 = EClass(id: id, name: personClassName)

        #expect(class1 == class2)
        #expect(class1.hashValue == class2.hashValue)
    }

    @Test func testEClassInequality() {
        let class1 = EClass(name: personClassName)
        let class2 = EClass(name: employeeClassName)

        #expect(class1 != class2)
    }

    @Test func testEClassEqualityIgnoresProperties() {
        let id = EUUID()
        let class1 = EClass(id: id, name: personClassName, isAbstract: false)
        let class2 = EClass(id: id, name: employeeClassName, isAbstract: true)

        // Same ID means equal, even with different properties
        #expect(class1 == class2)
    }
    // MARK: - ENamedElement Protocol Tests

    @Test func testEClassIsENamedElement() {
        let eClass = EClass(name: personClassName)
        let namedElement: any ENamedElement = eClass

        #expect(namedElement is EClass)
        #expect(namedElement.name == personClassName)
    }

    // MARK: - EObject Protocol Tests

    @Test func testEClassReflectiveAPI() {
        // Mock feature for testing
        struct MockFeature: EStructuralFeature {
            let id = EUUID()
            let name = "testFeature"
        }

        var eClass = EClass(name: personClassName)
        let feature = MockFeature()
        let testValue: EString = "testValue"

        // Initially not set
        #expect(eClass.eIsSet(feature) == false)
        #expect(eClass.eGet(feature) == nil)

        // Set value
        eClass.eSet(feature, testValue)
        #expect(eClass.eIsSet(feature) == true)
        #expect(eClass.eGet(feature) as? EString == testValue)

        // Unset value
        eClass.eUnset(feature)
        #expect(eClass.eIsSet(feature) == false)
        #expect(eClass.eGet(feature) == nil)
    }

    // MARK: - Metaclass Tests

    @Test func testEClassHasMetaclass() {
        let eClass = EClass(name: personClassName)

        #expect(eClass.eClass.name == "EClass")
    }

    // MARK: - EcoreValue Protocol Tests

    @Test func testEClassIsEcoreValue() {
        let eClass = EClass(name: personClassName)
        let value: any EcoreValue = eClass

        #expect(value is EClass)
    }

    // MARK: - Integration Tests

    @Test func testSimpleInheritanceHierarchy() {
        // Create a simple hierarchy: Animal -> Bird
        let animal = EClass(
            name: animalClassName,
            isAbstract: true
        )

        let bird = EClass(
            name: birdClassName,
            eSuperTypes: [animal]
        )

        #expect(bird.eSuperTypes.count == 1)
        #expect(bird.allSuperTypes.count == 1)
        #expect(animal.isSuperTypeOf(bird))
        #expect(!bird.isSuperTypeOf(animal))
    }

    @Test func testCompanyMetamodelHierarchy() {
        // Based on: emf4cpp/emf4cpp.tests/company/company.ecore
        // Create: NamedElement -> Person -> Employee, Manager
        let namedElement = EClass(
            name: "NamedElement",
            isAbstract: true
        )

        let person = EClass(
            name: personClassName,
            isAbstract: true,
            eSuperTypes: [namedElement]
        )

        let employee = EClass(
            name: employeeClassName,
            eSuperTypes: [person]
        )

        let manager = EClass(
            name: managerClassName,
            eSuperTypes: [employee]
        )

        // Verify hierarchy
        #expect(person.eSuperTypes.count == 1)
        #expect(employee.eSuperTypes.count == 1)
        #expect(manager.eSuperTypes.count == 1)

        // Verify transitive supertypes
        #expect(employee.allSuperTypes.count == 2)  // Person, NamedElement
        #expect(manager.allSuperTypes.count == 3)   // Employee, Person, NamedElement

        // Verify isSuperTypeOf
        #expect(namedElement.isSuperTypeOf(person))
        #expect(namedElement.isSuperTypeOf(employee))
        #expect(namedElement.isSuperTypeOf(manager))
        #expect(person.isSuperTypeOf(employee))
        #expect(person.isSuperTypeOf(manager))
        #expect(employee.isSuperTypeOf(manager))

        // Verify reverse is false
        #expect(!manager.isSuperTypeOf(employee))
        #expect(!employee.isSuperTypeOf(person))
        #expect(!person.isSuperTypeOf(namedElement))
    }
}
