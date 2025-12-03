//
// EStructuralFeatureTests.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
@testable import ECore
import Foundation

// MARK: - Test Constants

private let stringTypeName = "EString"
private let intTypeName = "EInt"

private let nameAttributeName = "name"
private let ageAttributeName = "age"
private let idAttributeName = "id"
private let tagsAttributeName = "tags"

private let managerReferenceName = "manager"
private let employeesReferenceName = "employees"
private let booksReferenceName = "books"
private let authorsReferenceName = "authors"

private let personClassName = "Person"
private let employeeClassName = "Employee"
private let bookClassName = "Book"

// MARK: - Test Suite

@Suite("EStructural Feature Tests")
struct EStructuralFeatureTests {

    // MARK: - EAttribute Creation Tests

    @Test func testEAttributeCreation() {
        let stringType = EDataType(name: stringTypeName)
        let attribute = EAttribute(
            name: nameAttributeName,
            eType: stringType
        )

        #expect(attribute.name == nameAttributeName)
        #expect(attribute.eType.name == stringTypeName)
        #expect(attribute.lowerBound == 0)
        #expect(attribute.upperBound == 1)
        #expect(attribute.changeable == true)
        #expect(attribute.volatile == false)
        #expect(attribute.transient == false)
        #expect(attribute.defaultValueLiteral == nil)
        #expect(attribute.isID == false)
    }

    @Test func testEAttributeWithDefaultValue() {
        let intType = EDataType(name: intTypeName)
        let defaultValue = "0"
        let attribute = EAttribute(
            name: ageAttributeName,
            eType: intType,
            defaultValueLiteral: defaultValue
        )

        #expect(attribute.defaultValueLiteral == defaultValue)
    }

    @Test func testEAttributeAsID() {
        let stringType = EDataType(name: stringTypeName)
        let attribute = EAttribute(
            name: idAttributeName,
            eType: stringType,
            isID: true
        )

        #expect(attribute.isID == true)
    }

    @Test func testEAttributeRequired() {
        let stringType = EDataType(name: stringTypeName)
        let attribute = EAttribute(
            name: nameAttributeName,
            eType: stringType,
            lowerBound: 1
        )

        #expect(attribute.lowerBound == 1)
        #expect(attribute.isRequired == true)
    }

    @Test func testEAttributeMultiValued() {
        let stringType = EDataType(name: stringTypeName)
        let attribute = EAttribute(
            name: tagsAttributeName,
            eType: stringType,
            upperBound: -1  // Unbounded
        )

        #expect(attribute.upperBound == -1)
        #expect(attribute.isMany == true)
    }

    @Test func testEAttributeReadOnly() {
        let stringType = EDataType(name: stringTypeName)
        let attribute = EAttribute(
            name: nameAttributeName,
            eType: stringType,
            changeable: false
        )

        #expect(attribute.changeable == false)
    }

    @Test func testEAttributeVolatile() {
        let stringType = EDataType(name: stringTypeName)
        let attribute = EAttribute(
            name: nameAttributeName,
            eType: stringType,
            volatile: true
        )

        #expect(attribute.volatile == true)
    }

    @Test func testEAttributeTransient() {
        let stringType = EDataType(name: stringTypeName)
        let attribute = EAttribute(
            name: nameAttributeName,
            eType: stringType,
            transient: true
        )

        #expect(attribute.transient == true)
    }

    // MARK: - EAttribute Multiplicity Tests

    @Test func testEAttributeIsManyFalse() {
        let stringType = EDataType(name: stringTypeName)
        let attribute = EAttribute(
            name: nameAttributeName,
            eType: stringType,
            upperBound: 1
        )

        #expect(attribute.isMany == false)
    }

    @Test func testEAttributeIsManyTrue() {
        let stringType = EDataType(name: stringTypeName)
        let attribute = EAttribute(
            name: tagsAttributeName,
            eType: stringType,
            upperBound: 5
        )

        #expect(attribute.isMany == true)
    }

    @Test func testEAttributeIsRequiredFalse() {
        let stringType = EDataType(name: stringTypeName)
        let attribute = EAttribute(
            name: nameAttributeName,
            eType: stringType,
            lowerBound: 0
        )

        #expect(attribute.isRequired == false)
    }

    @Test func testEAttributeIsRequiredTrue() {
        let stringType = EDataType(name: stringTypeName)
        let attribute = EAttribute(
            name: nameAttributeName,
            eType: stringType,
            lowerBound: 1
        )

        #expect(attribute.isRequired == true)
    }

    // MARK: - EAttribute Equality Tests

    @Test func testEAttributeEquality() {
        let id = EUUID()
        let stringType = EDataType(name: stringTypeName)
        let attr1 = EAttribute(id: id, name: nameAttributeName, eType: stringType)
        let attr2 = EAttribute(id: id, name: nameAttributeName, eType: stringType)

        #expect(attr1 == attr2)
        #expect(attr1.hashValue == attr2.hashValue)
    }

    @Test func testEAttributeInequality() {
        let stringType = EDataType(name: stringTypeName)
        let attr1 = EAttribute(name: nameAttributeName, eType: stringType)
        let attr2 = EAttribute(name: ageAttributeName, eType: stringType)

        #expect(attr1 != attr2)
    }

    // MARK: - EAttribute Protocol Tests

    @Test func testEAttributeIsENamedElement() {
        let stringType = EDataType(name: stringTypeName)
        let attribute = EAttribute(name: nameAttributeName, eType: stringType)
        let namedElement: any ENamedElement = attribute

        #expect(namedElement is EAttribute)
        #expect(namedElement.name == nameAttributeName)
    }

    @Test func testEAttributeIsEcoreValue() {
        let stringType = EDataType(name: stringTypeName)
        let attribute = EAttribute(name: nameAttributeName, eType: stringType)
        let value: any EcoreValue = attribute

        #expect(value is EAttribute)
    }

    @Test func testEAttributeHasMetaclass() {
        let stringType = EDataType(name: stringTypeName)
        let attribute = EAttribute(name: nameAttributeName, eType: stringType)

        #expect(attribute.eClass.name == "EAttribute")
    }

    // MARK: - EReference Creation Tests

    @Test func testEReferenceCreation() {
        let personClass = EClass(name: personClassName)
        let reference = EReference(
            name: managerReferenceName,
            eType: personClass
        )

        #expect(reference.name == managerReferenceName)
        #expect(reference.eType.name == personClassName)
        #expect(reference.lowerBound == 0)
        #expect(reference.upperBound == 1)
        #expect(reference.changeable == true)
        #expect(reference.volatile == false)
        #expect(reference.transient == false)
        #expect(reference.containment == false)
        #expect(reference.opposite == nil)
        #expect(reference.resolveProxies == true)
    }

    @Test func testEReferenceContainment() {
        let employeeClass = EClass(name: employeeClassName)
        let reference = EReference(
            name: employeesReferenceName,
            eType: employeeClass,
            containment: true
        )

        #expect(reference.containment == true)
    }

    @Test func testEReferenceRequired() {
        let personClass = EClass(name: personClassName)
        let reference = EReference(
            name: managerReferenceName,
            eType: personClass,
            lowerBound: 1
        )

        #expect(reference.lowerBound == 1)
        #expect(reference.isRequired == true)
    }

    @Test func testEReferenceMultiValued() {
        let employeeClass = EClass(name: employeeClassName)
        let reference = EReference(
            name: employeesReferenceName,
            eType: employeeClass,
            upperBound: -1  // Unbounded
        )

        #expect(reference.upperBound == -1)
        #expect(reference.isMany == true)
    }

    @Test func testEReferenceWithOpposite() {
        let bookClass = EClass(name: bookClassName)
        let personClass = EClass(name: personClassName)

        let booksRef = EReference(
            name: booksReferenceName,
            eType: bookClass,
            upperBound: -1
        )

        let authorsRef = EReference(
            name: authorsReferenceName,
            eType: personClass,
            upperBound: -1,
            opposite: booksRef.id  // ID-based opposite
        )

        #expect(authorsRef.opposite != nil)
        #expect(authorsRef.opposite == booksRef.id)
    }

    @Test func testEReferenceReadOnly() {
        let personClass = EClass(name: personClassName)
        let reference = EReference(
            name: managerReferenceName,
            eType: personClass,
            changeable: false
        )

        #expect(reference.changeable == false)
    }

    @Test func testEReferenceVolatile() {
        let personClass = EClass(name: personClassName)
        let reference = EReference(
            name: managerReferenceName,
            eType: personClass,
            volatile: true
        )

        #expect(reference.volatile == true)
    }

    @Test func testEReferenceTransient() {
        let personClass = EClass(name: personClassName)
        let reference = EReference(
            name: managerReferenceName,
            eType: personClass,
            transient: true
        )

        #expect(reference.transient == true)
    }

    @Test func testEReferenceNoProxyResolve() {
        let personClass = EClass(name: personClassName)
        let reference = EReference(
            name: managerReferenceName,
            eType: personClass,
            resolveProxies: false
        )

        #expect(reference.resolveProxies == false)
    }

    // MARK: - EReference Multiplicity Tests

    @Test func testEReferenceIsManyFalse() {
        let personClass = EClass(name: personClassName)
        let reference = EReference(
            name: managerReferenceName,
            eType: personClass,
            upperBound: 1
        )

        #expect(reference.isMany == false)
    }

    @Test func testEReferenceIsManyTrue() {
        let employeeClass = EClass(name: employeeClassName)
        let reference = EReference(
            name: employeesReferenceName,
            eType: employeeClass,
            upperBound: 5
        )

        #expect(reference.isMany == true)
    }

    @Test func testEReferenceIsRequiredFalse() {
        let personClass = EClass(name: personClassName)
        let reference = EReference(
            name: managerReferenceName,
            eType: personClass,
            lowerBound: 0
        )

        #expect(reference.isRequired == false)
    }

    @Test func testEReferenceIsRequiredTrue() {
        let personClass = EClass(name: personClassName)
        let reference = EReference(
            name: managerReferenceName,
            eType: personClass,
            lowerBound: 1
        )

        #expect(reference.isRequired == true)
    }

    // MARK: - EReference Equality Tests

    @Test func testEReferenceEquality() {
        let id = EUUID()
        let personClass = EClass(name: personClassName)
        let ref1 = EReference(id: id, name: managerReferenceName, eType: personClass)
        let ref2 = EReference(id: id, name: managerReferenceName, eType: personClass)

        #expect(ref1 == ref2)
        #expect(ref1.hashValue == ref2.hashValue)
    }

    @Test func testEReferenceInequality() {
        let personClass = EClass(name: personClassName)
        let ref1 = EReference(name: managerReferenceName, eType: personClass)
        let ref2 = EReference(name: employeesReferenceName, eType: personClass)

        #expect(ref1 != ref2)
    }

    // MARK: - EReference Protocol Tests

    @Test func testEReferenceIsENamedElement() {
        let personClass = EClass(name: personClassName)
        let reference = EReference(name: managerReferenceName, eType: personClass)
        let namedElement: any ENamedElement = reference

        #expect(namedElement is EReference)
        #expect(namedElement.name == managerReferenceName)
    }

    @Test func testEReferenceIsEcoreValue() {
        let personClass = EClass(name: personClassName)
        let reference = EReference(name: managerReferenceName, eType: personClass)
        let value: any EcoreValue = reference

        #expect(value is EReference)
    }

    @Test func testEReferenceHasMetaclass() {
        let personClass = EClass(name: personClassName)
        let reference = EReference(name: managerReferenceName, eType: personClass)

        #expect(reference.eClass.name == "EReference")
    }

    // MARK: - Integration Tests

    @Test func testPersonEmployeeAttributes() {
        let stringType = EDataType(name: stringTypeName)
        let intType = EDataType(name: intTypeName)

        let nameAttr = EAttribute(name: nameAttributeName, eType: stringType, lowerBound: 1)
        let ageAttr = EAttribute(name: ageAttributeName, eType: intType)
        let idAttr = EAttribute(name: idAttributeName, eType: stringType, isID: true)

        let personClass = EClass(
            name: personClassName,
            eStructuralFeatures: [nameAttr, ageAttr, idAttr]
        )

        #expect(personClass.allAttributes.count == 3)

        let foundName = personClass.getEAttribute(name: nameAttributeName)
        #expect(foundName != nil)
        #expect(foundName?.isRequired == true)

        let foundAge = personClass.getEAttribute(name: ageAttributeName)
        #expect(foundAge != nil)
        #expect(foundAge?.isRequired == false)

        let foundID = personClass.getEAttribute(name: idAttributeName)
        #expect(foundID != nil)
        #expect(foundID?.isID == true)
    }
}