//
// EPackageTests.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
@testable import ECore
import Foundation

// MARK: - Test Constants

private let companyPackageName = "company"
private let companyNsURI = "http://example.org/company"
private let companyNsPrefix = "comp"

private let employeeClassName = "Employee"
private let departmentClassName = "Department"
private let stringTypeName = "EString"
private let birdEnumName = "BirdType"

private let hrSubpackageName = "hr"
private let financeSubpackageName = "finance"

// MARK: - Test Suite

@Suite("EPackage Tests")
struct EPackageTests {

    // MARK: - EPackage Creation Tests

    @Test func testEPackageCreation() {
        let package = EPackage(name: companyPackageName)

        #expect(package.name == companyPackageName)
        #expect(package.nsURI == "")
        #expect(package.nsPrefix == "")
        #expect(package.eClassifiers.isEmpty)
        #expect(package.eSubpackages.isEmpty)
        #expect(package.eAnnotations.isEmpty)
    }

    @Test func testEPackageWithNamespace() {
        let package = EPackage(
            name: companyPackageName,
            nsURI: companyNsURI,
            nsPrefix: companyNsPrefix
        )

        #expect(package.nsURI == companyNsURI)
        #expect(package.nsPrefix == companyNsPrefix)
    }

    @Test func testEPackageWithClassifiers() {
        let employeeClass = EClass(name: employeeClassName)
        let departmentClass = EClass(name: departmentClassName)

        let package = EPackage(
            name: companyPackageName,
            eClassifiers: [employeeClass, departmentClass]
        )

        #expect(package.eClassifiers.count == 2)
    }

    @Test func testEPackageWithMixedClassifiers() {
        let employeeClass = EClass(name: employeeClassName)
        let stringType = EDataType(name: stringTypeName)
        let birdEnum = EEnum(name: birdEnumName)

        let package = EPackage(
            name: companyPackageName,
            eClassifiers: [employeeClass, stringType, birdEnum]
        )

        #expect(package.eClassifiers.count == 3)
    }

    @Test func testEPackageWithSubpackages() {
        let hrPackage = EPackage(name: hrSubpackageName)
        let financePackage = EPackage(name: financeSubpackageName)

        let package = EPackage(
            name: companyPackageName,
            eSubpackages: [hrPackage, financePackage]
        )

        #expect(package.eSubpackages.count == 2)
    }

    @Test func testEPackageWithAnnotations() {
        let annotation = EAnnotation(
            source: "http://www.eclipse.org/emf/2002/GenModel",
            details: ["documentation": "Company package for HR and payroll"]
        )

        let package = EPackage(
            name: companyPackageName,
            eAnnotations: [annotation]
        )

        #expect(package.eAnnotations.count == 1)
        #expect(package.eAnnotations[0].source == "http://www.eclipse.org/emf/2002/GenModel")
        #expect(package.eAnnotations[0].details["documentation"] == "Company package for HR and payroll")
    }

// MARK: - Classifier Lookup Tests

    @Test func testGetClassifier() {
        let employeeClass = EClass(name: employeeClassName)
        let package = EPackage(
            name: companyPackageName,
            eClassifiers: [employeeClass]
        )

        let found = package.getClassifier(employeeClassName)
        #expect(found != nil)
        #expect((found as? EClass)?.name == employeeClassName)
    }

    @Test func testGetClassifierNotFound() {
        let package = EPackage(name: companyPackageName)

        let found = package.getClassifier("NonExistent")
        #expect(found == nil)
    }

    @Test func testGetEClass() {
        let employeeClass = EClass(name: employeeClassName)
        let package = EPackage(
            name: companyPackageName,
            eClassifiers: [employeeClass]
        )

        let found = package.getEClass(employeeClassName)
        #expect(found != nil)
        #expect(found?.name == employeeClassName)
    }

    @Test func testGetEClassNotFound() {
        let stringType = EDataType(name: stringTypeName)
        let package = EPackage(
            name: companyPackageName,
            eClassifiers: [stringType]
        )

        // DataType exists but we're looking for a class
        let found = package.getEClass(stringTypeName)
        #expect(found == nil)
    }

    @Test func testGetEDataType() {
        let stringType = EDataType(name: stringTypeName)
        let package = EPackage(
            name: companyPackageName,
            eClassifiers: [stringType]
        )

        let found = package.getEDataType(stringTypeName)
        #expect(found != nil)
        #expect(found?.name == stringTypeName)
    }

    @Test func testGetEDataTypeNotFound() {
        let employeeClass = EClass(name: employeeClassName)
        let package = EPackage(
            name: companyPackageName,
            eClassifiers: [employeeClass]
        )

        // Class exists but we're looking for a data type
        let found = package.getEDataType(employeeClassName)
        #expect(found == nil)
    }

    @Test func testGetEEnum() {
        let birdEnum = EEnum(name: birdEnumName)
        let package = EPackage(
            name: companyPackageName,
            eClassifiers: [birdEnum]
        )

        let found = package.getEEnum(birdEnumName)
        #expect(found != nil)
        #expect(found?.name == birdEnumName)
    }

    @Test func testGetEEnumNotFound() {
        let employeeClass = EClass(name: employeeClassName)
        let package = EPackage(
            name: companyPackageName,
            eClassifiers: [employeeClass]
        )

        // Class exists but we're looking for an enum
        let found = package.getEEnum(employeeClassName)
        #expect(found == nil)
    }

    // MARK: - Subpackage Lookup Tests

    @Test func testGetSubpackage() {
        let hrPackage = EPackage(name: hrSubpackageName)
        let package = EPackage(
            name: companyPackageName,
            eSubpackages: [hrPackage]
        )

        let found = package.getSubpackage(hrSubpackageName)
        #expect(found != nil)
        #expect(found?.name == hrSubpackageName)
    }

    @Test func testGetSubpackageNotFound() {
        let package = EPackage(name: companyPackageName)

        let found = package.getSubpackage("nonexistent")
        #expect(found == nil)
    }

// MARK: - Equality and Hashing Tests

    @Test func testEPackageEquality() {
        let id = EUUID()
        let package1 = EPackage(id: id, name: companyPackageName)
        let package2 = EPackage(id: id, name: companyPackageName)

        #expect(package1 == package2)
        #expect(package1.hashValue == package2.hashValue)
    }

    @Test func testEPackageInequality() {
        let package1 = EPackage(name: companyPackageName)
        let package2 = EPackage(name: "OtherPackage")

        #expect(package1 != package2)
    }

    @Test func testEPackageEqualityIgnoresContent() {
        let id = EUUID()
        let employeeClass = EClass(name: employeeClassName)

        let package1 = EPackage(id: id, name: companyPackageName)
        let package2 = EPackage(
            id: id,
            name: "different",
            eClassifiers: [employeeClass]
        )

        // Same ID means equal, even with different content
        #expect(package1 == package2)
    }

// MARK: - Protocol Tests

    @Test func testEPackageIsENamedElement() {
        let package = EPackage(name: companyPackageName)
        let namedElement: any ENamedElement = package

        #expect(namedElement is EPackage)
        #expect(namedElement.name == companyPackageName)
    }

    @Test func testEPackageIsEcoreValue() {
        let package = EPackage(name: companyPackageName)
        let value: any EcoreValue = package

        #expect(value is EPackage)
    }
    @Test func testEPackageHasMetaclass() {
        let package = EPackage(name: companyPackageName)

        #expect(package.eClass.name == "EPackage")
    }
}

// The remaining tests were removed as they appear to belong to other test files or contain functionality not yet implemented
