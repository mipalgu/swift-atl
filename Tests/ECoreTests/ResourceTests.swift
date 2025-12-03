//
// ResourceTests.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
@testable import ECore
import Foundation

// MARK: - Test Constants

private let testResourceURI = "http://example.org/test-model.xmi"
private let testResourceURI2 = "http://example.org/other-model.xmi"
private let companyNamespaceURI = "http://example.org/company"
private let personClassName = "Person"
private let companyClassName = "Company"

// MARK: - Test Suite

@Suite("Resource Tests")
struct ResourceTests {
    
    // MARK: - Resource Creation Tests
    
    @Test func testResourceCreation() async {
        let resource = Resource(uri: testResourceURI)
        
        #expect(resource.uri == testResourceURI)
        #expect(await resource.count() == 0)
        #expect(await resource.getRootObjects().isEmpty)
        #expect(await resource.getAllObjects().isEmpty)
    }
    
    @Test func testResourceCreationWithDefaultURI() async {
        let resource = Resource()
        
        #expect(resource.uri.hasPrefix("resource://"))
        #expect(await resource.count() == 0)
    }
    
    // MARK: - Object Management Tests
    
    @Test func testAddObjectToResource() async {
        let resource = Resource(uri: testResourceURI)
        let personClass = EClass(name: personClassName)
        let person = DynamicEObject(eClass: personClass)
        
        let added = await resource.add(person)
        
        #expect(added == true)
        #expect(await resource.count() == 1)
        #expect(await resource.contains(id: person.id))
    }
    
    @Test func testAddDuplicateObjectToResource() async {
        let resource = Resource(uri: testResourceURI)
        let personClass = EClass(name: personClassName)
        let person = DynamicEObject(eClass: personClass)
        
        let firstAdd = await resource.add(person)
        let secondAdd = await resource.add(person)
        
        #expect(firstAdd == true)
        #expect(secondAdd == false)
        #expect(await resource.count() == 1)
    }
    
    @Test func testRemoveObjectFromResource() async {
        let resource = Resource(uri: testResourceURI)
        let personClass = EClass(name: personClassName)
        let person = DynamicEObject(eClass: personClass)
        
        await resource.add(person)
        let removed = await resource.remove(person)
        
        #expect(removed == true)
        #expect(await resource.count() == 0)
        #expect(await !resource.contains(id: person.id))
    }
    
    @Test func testRemoveObjectByIdFromResource() async {
        let resource = Resource(uri: testResourceURI)
        let personClass = EClass(name: personClassName)
        let person = DynamicEObject(eClass: personClass)
        
        await resource.add(person)
        let removed = await resource.remove(id: person.id)
        
        #expect(removed == true)
        #expect(await resource.count() == 0)
    }
    
    @Test func testRemoveNonexistentObjectFromResource() async {
        let resource = Resource(uri: testResourceURI)
        let personClass = EClass(name: personClassName)
        let person = DynamicEObject(eClass: personClass)
        
        let removed = await resource.remove(person)
        
        #expect(removed == false)
        #expect(await resource.count() == 0)
    }
    
    @Test func testClearResource() async {
        let resource = Resource(uri: testResourceURI)
        let personClass = EClass(name: personClassName)
        
        // Add multiple objects
        for _ in 0..<3 {
            let person = DynamicEObject(eClass: personClass)
            await resource.add(person)
        }
        
        #expect(await resource.count() == 3)
        
        await resource.clear()
        
        #expect(await resource.count() == 0)
        #expect(await resource.getAllObjects().isEmpty)
        #expect(await resource.getRootObjects().isEmpty)
    }
    
    // MARK: - Object Resolution Tests
    
    @Test func testResolveObjectById() async {
        let resource = Resource(uri: testResourceURI)
        let personClass = EClass(name: personClassName)
        let person = DynamicEObject(eClass: personClass)
        
        await resource.add(person)
        let resolved = await resource.resolve(person.id)
        
        #expect(resolved?.id == person.id)
    }
    
    @Test func testResolveObjectByIdWithType() async {
        let resource = Resource(uri: testResourceURI)
        let personClass = EClass(name: personClassName)
        let person = DynamicEObject(eClass: personClass)
        
        await resource.add(person)
        let resolved = await resource.resolve(person.id, as: DynamicEObject.self)
        
        #expect(resolved?.id == person.id)
        #expect(resolved != nil)
    }
    
    @Test func testResolveNonexistentObject() async {
        let resource = Resource(uri: testResourceURI)
        let randomId = EUUID()
        
        let resolved = await resource.resolve(randomId)
        
        #expect(resolved == nil)
    }
    
    @Test func testGetAllObjects() async {
        let resource = Resource(uri: testResourceURI)
        let personClass = EClass(name: personClassName)
        
        var addedObjects: [DynamicEObject] = []
        for _ in 0..<3 {
            let person = DynamicEObject(eClass: personClass)
            addedObjects.append(person)
            await resource.add(person)
        }
        
        let allObjects = await resource.getAllObjects()
        
        #expect(allObjects.count == 3)
        for addedObject in addedObjects {
            #expect(allObjects.contains { $0.id == addedObject.id })
        }
    }
    
    @Test func testGetRootObjects() async {
        let resource = Resource(uri: testResourceURI)
        let personClass = EClass(name: personClassName)
        let person = DynamicEObject(eClass: personClass)
        
        await resource.add(person)
        let rootObjects = await resource.getRootObjects()
        
        #expect(rootObjects.count == 1)
        #expect(rootObjects.first?.id == person.id)
    }
    
    // MARK: - URI Path Resolution Tests
    
    @Test func testResolveBySimplePath() async {
        let resource = Resource(uri: testResourceURI)
        let personClass = EClass(name: personClassName)
        let person = DynamicEObject(eClass: personClass)
        
        await resource.add(person)
        let resolved = await resource.resolveByPath("/@contents.0")
        
        #expect(resolved?.id == person.id)
    }
    
    @Test func testResolveByInvalidPath() async {
        let resource = Resource(uri: testResourceURI)
        let personClass = EClass(name: personClassName)
        let person = DynamicEObject(eClass: personClass)
        
        await resource.add(person)
        let resolved = await resource.resolveByPath("/@contents.99")
        
        #expect(resolved == nil)
    }
    
    @Test func testResolveByMalformedPath() async {
        let resource = Resource(uri: testResourceURI)
        let resolved = await resource.resolveByPath("invalid-path")
        
        #expect(resolved == nil)
    }
    
    // MARK: - Resource Equality Tests
    
    @Test func testResourceEquality() {
        let resource1 = Resource(uri: testResourceURI)
        let resource2 = Resource(uri: testResourceURI)
        
        #expect(resource1 == resource2)
    }
    
    @Test func testResourceInequality() {
        let resource1 = Resource(uri: testResourceURI)
        let resource2 = Resource(uri: testResourceURI2)
        
        #expect(resource1 != resource2)
    }
    
    @Test func testResourceHashing() {
        let resource1 = Resource(uri: testResourceURI)
        let resource2 = Resource(uri: testResourceURI)
        let resource3 = Resource(uri: testResourceURI2)
        
        #expect(resource1.hashValue == resource2.hashValue)
        #expect(resource1.hashValue != resource3.hashValue)
    }
    
    // MARK: - ResourceSet Creation Tests
    
    @Test func testResourceSetCreation() async {
        let resourceSet = ResourceSet()
        
        #expect(await resourceSet.count() == 0)
        #expect(await resourceSet.getResources().isEmpty)
        #expect(await resourceSet.getMetamodelURIs().isEmpty)
    }
    
    // MARK: - ResourceSet Resource Management Tests
    
    @Test func testCreateResourceInSet() async {
        let resourceSet = ResourceSet()
        
        let resource = await resourceSet.createResource(uri: testResourceURI)
        
        #expect(resource.uri == testResourceURI)
        #expect(await resourceSet.count() == 1)
        #expect(await resourceSet.getResources().count == 1)
    }
    
    @Test func testCreateDuplicateResourceInSet() async {
        let resourceSet = ResourceSet()
        
        let resource1 = await resourceSet.createResource(uri: testResourceURI)
        let resource2 = await resourceSet.createResource(uri: testResourceURI)
        
        #expect(resource1 === resource2)
        #expect(await resourceSet.count() == 1)
    }
    
    @Test func testGetResourceFromSet() async {
        let resourceSet = ResourceSet()
        await resourceSet.createResource(uri: testResourceURI)
        
        let retrieved = await resourceSet.getResource(uri: testResourceURI)
        
        #expect(retrieved?.uri == testResourceURI)
    }
    
    @Test func testGetNonexistentResourceFromSet() async {
        let resourceSet = ResourceSet()
        
        let retrieved = await resourceSet.getResource(uri: "http://nonexistent.uri")
        
        #expect(retrieved == nil)
    }
    
    @Test func testRemoveResourceFromSet() async {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: testResourceURI)
        
        let removed = await resourceSet.removeResource(resource)
        
        #expect(removed == true)
        #expect(await resourceSet.count() == 0)
    }
    
    @Test func testRemoveResourceByURIFromSet() async {
        let resourceSet = ResourceSet()
        await resourceSet.createResource(uri: testResourceURI)
        
        let removed = await resourceSet.removeResource(uri: testResourceURI)
        
        #expect(removed == true)
        #expect(await resourceSet.count() == 0)
    }
    
    @Test func testRemoveNonexistentResourceFromSet() async {
        let resourceSet = ResourceSet()
        let resource = Resource(uri: testResourceURI)
        
        let removed = await resourceSet.removeResource(resource)
        
        #expect(removed == false)
    }
    
    // MARK: - Metamodel Registry Tests
    
    @Test func testRegisterMetamodel() async {
        let resourceSet = ResourceSet()
        let companyPackage = EPackage(
            name: "company",
            nsURI: companyNamespaceURI,
            nsPrefix: "company"
        )
        
        await resourceSet.registerMetamodel(companyPackage, uri: companyNamespaceURI)
        
        let retrieved = await resourceSet.getMetamodel(uri: companyNamespaceURI)
        #expect(retrieved?.name == "company")
        #expect(retrieved?.nsURI == companyNamespaceURI)
    }
    
    @Test func testUnregisterMetamodel() async {
        let resourceSet = ResourceSet()
        let companyPackage = EPackage(
            name: "company",
            nsURI: companyNamespaceURI,
            nsPrefix: "company"
        )
        
        await resourceSet.registerMetamodel(companyPackage, uri: companyNamespaceURI)
        let unregistered = await resourceSet.unregisterMetamodel(uri: companyNamespaceURI)
        
        #expect(unregistered?.name == "company")
        #expect(await resourceSet.getMetamodel(uri: companyNamespaceURI) == nil)
    }
    
    @Test func testGetMetamodelURIs() async {
        let resourceSet = ResourceSet()
        let companyPackage = EPackage(
            name: "company",
            nsURI: companyNamespaceURI,
            nsPrefix: "company"
        )
        let otherPackage = EPackage(
            name: "other",
            nsURI: "http://example.org/other",
            nsPrefix: "other"
        )
        
        await resourceSet.registerMetamodel(companyPackage, uri: companyNamespaceURI)
        await resourceSet.registerMetamodel(otherPackage, uri: "http://example.org/other")
        
        let uris = await resourceSet.getMetamodelURIs()
        
        #expect(uris.count == 2)
        #expect(uris.contains(companyNamespaceURI))
        #expect(uris.contains("http://example.org/other"))
    }
    
    // MARK: - URI Management Tests
    
    @Test func testMapURI() async {
        let resourceSet = ResourceSet()
        let logicalURI = "models://company.xmi"
        let physicalURI = "/path/to/company.xmi"
        
        await resourceSet.mapURI(from: logicalURI, to: physicalURI)
        let converted = await resourceSet.convertURI(logicalURI)
        
        #expect(converted == physicalURI)
    }
    
    @Test func testConvertUnmappedURI() async {
        let resourceSet = ResourceSet()
        let originalURI = "http://example.org/test.xmi"
        
        let converted = await resourceSet.convertURI(originalURI)
        
        #expect(converted == originalURI)
    }
    
    @Test func testNormaliseURI() async {
        let resourceSet = ResourceSet()
        let messyURI = "http://example.org/./path/../other/./file.xmi"
        
        let normalised = await resourceSet.normaliseURI(messyURI)
        
        #expect(normalised == "http://example.org/other/file.xmi")
    }
    
    @Test func testNormaliseURIWithMultipleDotDot() async {
        let resourceSet = ResourceSet()
        let messyURI = "path/to/deep/../../../simple.xmi"
        
        let normalised = await resourceSet.normaliseURI(messyURI)
        
        #expect(normalised == "simple.xmi")
    }
    
    // MARK: - Cross-Resource Resolution Tests
    
    @Test func testCrossResourceResolve() async {
        let resourceSet = ResourceSet()
        let resource1 = await resourceSet.createResource(uri: testResourceURI)
        let resource2 = await resourceSet.createResource(uri: testResourceURI2)
        
        let personClass = EClass(name: personClassName)
        let person1 = DynamicEObject(eClass: personClass)
        let person2 = DynamicEObject(eClass: personClass)
        
        await resource1.add(person1)
        await resource2.add(person2)
        
        let resolved1 = await resourceSet.resolve(person1.id)
        let resolved2 = await resourceSet.resolve(person2.id)
        
        #expect(resolved1?.object.id == person1.id)
        #expect(resolved1?.resource.uri == testResourceURI)
        #expect(resolved2?.object.id == person2.id)
        #expect(resolved2?.resource.uri == testResourceURI2)
    }
    
    @Test func testCrossResourceResolveNonexistent() async {
        let resourceSet = ResourceSet()
        await resourceSet.createResource(uri: testResourceURI)
        
        let randomId = EUUID()
        let resolved = await resourceSet.resolve(randomId)
        
        #expect(resolved == nil)
    }
    
    @Test func testResolveByURIWithFragment() async {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: testResourceURI)
        
        let personClass = EClass(name: personClassName)
        let person = DynamicEObject(eClass: personClass)
        await resource.add(person)
        
        let fullURI = "\(testResourceURI)#/@contents.0"
        let resolved = await resourceSet.resolveByURI(fullURI)
        
        #expect(resolved?.id == person.id)
    }
    
    @Test func testResolveByURIWithoutFragment() async {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: testResourceURI)
        
        let personClass = EClass(name: personClassName)
        let person = DynamicEObject(eClass: personClass)
        await resource.add(person)
        
        let resolved = await resourceSet.resolveByURI(testResourceURI)
        
        #expect(resolved?.id == person.id)
    }
    
    @Test func testResolveByURINonexistentResource() async {
        let resourceSet = ResourceSet()
        
        let resolved = await resourceSet.resolveByURI("http://nonexistent.org/model.xmi")
        
        #expect(resolved == nil)
    }
    
    // MARK: - Reference Resolution Tests
    
    @Test func testOppositeReferenceResolution() async {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: testResourceURI)
        
        // Create bidirectional references first
        let worksForRef = EReference(
            name: "worksFor",
            eType: EDataType(name: "Company") // Temporary type for now
        )
        let employeesRef = EReference(
            name: "employees",
            eType: EDataType(name: "Person"), // Temporary type for now
            upperBound: -1,
            containment: true,
            opposite: worksForRef.id
        )
        
        // Update worksFor to reference employees as opposite
        let updatedWorksForRef = EReference(
            id: worksForRef.id,
            name: worksForRef.name,
            eType: worksForRef.eType,
            opposite: employeesRef.id
        )
        
        // Create classes with the references as structural features
        let personClass = EClass(
            name: personClassName,
            eStructuralFeatures: [updatedWorksForRef]
        )
        let companyClass = EClass(
            name: companyClassName,
            eStructuralFeatures: [employeesRef]
        )
        
        // Create objects
        let person = DynamicEObject(eClass: personClass)
        let company = DynamicEObject(eClass: companyClass)
        
        await resource.add(person)
        await resource.add(company)
        
        let oppositeRef = await resourceSet.resolveOpposite(updatedWorksForRef)
        
        #expect(oppositeRef?.id == employeesRef.id)
        #expect(oppositeRef?.name == "employees")
    }
    
    // MARK: - Description Tests
    
    @Test func testResourceDescription() {
        let resource = Resource(uri: testResourceURI)
        let description = resource.description
        
        #expect(description.contains("Resource"))
        #expect(description.contains(testResourceURI))
    }
    
    @Test func testResourceSetDescription() async {
        let resourceSet = ResourceSet()
        await resourceSet.createResource(uri: testResourceURI)
        
        let companyPackage = EPackage(name: "company")
        await resourceSet.registerMetamodel(companyPackage, uri: companyNamespaceURI)
        
        let description = resourceSet.description
        
        #expect(description.contains("ResourceSet"))
        // Note: Simplified description due to actor isolation constraints
        // #expect(description.contains("resources: 1"))
        // #expect(description.contains("metamodels: 1"))
    }
}

// MARK: - Mock Resource Factory

private struct MockResourceFactory: ResourceFactory {
    func createResource(uri: String, in resourceSet: ResourceSet) throws -> Resource {
        let resource = Resource(uri: uri)
        return resource
    }
    
    func canHandle(uri: String) -> Bool {
        return uri.hasSuffix(".mock")
    }
}

// MARK: - Resource Factory Tests

@Suite("Resource Factory Tests")  
struct ResourceFactoryTests {
    
    @Test func testRegisterResourceFactory() async {
        let resourceSet = ResourceSet()
        let factory = MockResourceFactory()
        
        await resourceSet.registerResourceFactory(factory, for: ".mock")
        let retrieved = await resourceSet.getResourceFactory(for: "test.mock")
        
        #expect(retrieved != nil)
    }
    
    @Test func testGetResourceFactoryForUnknownExtension() async {
        let resourceSet = ResourceSet()
        
        let factory = await resourceSet.getResourceFactory(for: "test.unknown")
        
        #expect(factory == nil)
    }
}