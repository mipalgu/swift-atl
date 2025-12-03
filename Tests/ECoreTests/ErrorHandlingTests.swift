//
// ErrorHandlingTests.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
@testable import ECore
import Foundation

// MARK: - Error Handling Tests

@Suite("Error Handling Tests")
struct ErrorHandlingTests {
    
    // MARK: - Type Validation Error Tests
    
    @Test func testInvalidAttributeTypeError() async throws {
        let stringType = EDataType(name: "EString")
        let intType = EDataType(name: "EInt")
        let nameAttr = EAttribute(name: "name", eType: stringType)
        let ageAttr = EAttribute(name: "age", eType: intType)
        let personClass = EClass(name: "Person", eStructuralFeatures: [nameAttr, ageAttr])
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://person")
        var person = DynamicEObject(eClass: personClass)
        await resource.add(person)
        
        // Setting wrong type should handle gracefully
        person.eSet("name", value: 42)  // Integer to string attribute
        person.eSet("age", value: "not a number")  // String to integer attribute
        
        // Values should be stored as-is (EMF typically allows this at runtime)
        let name = person.eGet("name")
        let age = person.eGet("age")
        
        #expect(name != nil)
        #expect(age != nil)
        
        // Type checking is typically done at validation time, not assignment time
        #expect(nameAttr.eType.name == "EString")
        #expect(ageAttr.eType.name == "EInt")
    }
    
    @Test func testInvalidReferenceTypeError() async throws {
        var personClass = EClass(name: "Person")
        let bookClass = EClass(name: "Book")
        let addressClass = EClass(name: "Address")
        
        let booksRef = EReference(name: "books", eType: bookClass, upperBound: -1)
        personClass.eStructuralFeatures = [booksRef]
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://types")
        var person = DynamicEObject(eClass: personClass)
        let address = DynamicEObject(eClass: addressClass)
        
        await resource.add(person)
        await resource.add(address)
        
        // Setting wrong reference type should handle gracefully
        person.eSet("books", value: [address.id])  // Address ID to books reference
        
        let books = person.eGet("books") as? [EUUID]
        #expect(books?.count == 1)
        #expect(books?.first == address.id)
        
        // Type compatibility checking would be done at a higher level
        #expect(booksRef.eType.name == "Book")
    }
    
    // MARK: - Null Value Handling Tests
    
    @Test func testNullValueHandling() async throws {
        let stringType = EDataType(name: "EString")
        let nameAttr = EAttribute(name: "name", eType: stringType, lowerBound: 0)
        var personClass = EClass(name: "Person", eStructuralFeatures: [nameAttr])
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://null")
        var person = DynamicEObject(eClass: personClass)
        await resource.add(person)
        
        // Setting nil should be allowed for optional attributes
        person.eSet("name", value: nil)
        
        let name = person.eGet("name")
        #expect(name == nil)
        
        // Setting nil to required attribute should still work (validation separate)
        let requiredAttr = EAttribute(name: "required", eType: stringType, lowerBound: 1)
        personClass.eStructuralFeatures.append(requiredAttr)
        
        person.eSet("required", value: nil)
        let required = person.eGet("required")
        #expect(required == nil)  // Allowed at runtime, validation would catch this
    }
    
    @Test func testNullReferenceHandling() async throws {
        let personClass = EClass(name: "Person")
        let managerRef = EReference(name: "manager", eType: personClass, lowerBound: 0)
        let employeeClass = EClass(name: "Employee", eStructuralFeatures: [managerRef])
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://null-ref")
        var employee = DynamicEObject(eClass: employeeClass)
        await resource.add(employee)
        
        // Setting nil reference should be allowed
        employee.eSet("manager", value: nil)
        
        let manager = employee.eGet("manager")
        #expect(manager == nil)
    }
    
    // MARK: - Collection Boundary Tests
    
    @Test func testCollectionUpperBoundViolation() async throws {
        let stringType = EDataType(name: "EString")
        let tagsAttr = EAttribute(name: "tags", eType: stringType, upperBound: 3)
        let itemClass = EClass(name: "Item", eStructuralFeatures: [tagsAttr])
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://bounds")
        var item = DynamicEObject(eClass: itemClass)
        await resource.add(item)
        
        // Try to set more items than upper bound
        let manyTags = ["tag1", "tag2", "tag3", "tag4", "tag5"]
        item.eSet("tags", value: manyTags)
        
        let tags = item.eGet("tags") as? [String]
        // EMF typically allows this at runtime and validates later
        #expect(tags?.count == 5)
        #expect(tagsAttr.upperBound == 3)  // Constraint still there
    }
    
    @Test func testCollectionLowerBoundValidation() async throws {
        let employeeClass = EClass(name: "Employee")
        var teamClass = EClass(name: "Team")
        let membersRef = EReference(name: "members", eType: employeeClass, lowerBound: 2, upperBound: -1)
        
        teamClass.eStructuralFeatures = [membersRef]
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://team-bounds")
        var team = DynamicEObject(eClass: teamClass)
        let employee1 = DynamicEObject(eClass: employeeClass)
        
        await resource.add(team)
        await resource.add(employee1)
        
        // Set fewer members than lower bound
        team.eSet("members", value: [employee1.id])
        
        let members = team.eGet("members") as? [EUUID]
        #expect(members?.count == 1)
        #expect(membersRef.lowerBound == 2)  // Constraint violation allowed at runtime
    }
    
    // MARK: - Resource Error Handling Tests
    
    @Test func testResourceNotFoundError() async throws {
        let resourceSet = ResourceSet()
        
        // Try to get non-existent resource
        let resource = await resourceSet.getResource(uri: "test://nonexistent")
        #expect(resource == nil)
        
        // Try to resolve object in non-existent resource
        let resolved = await resourceSet.resolve(EUUID())
        #expect(resolved == nil)
    }
    
    @Test func testObjectNotFoundError() async throws {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://empty")
        
        // Try to resolve non-existent object
        let nonExistentId = EUUID()
        let resolved = await resource.resolve(nonExistentId)
        #expect(resolved == nil)
        
        // Try to remove non-existent object
        let removed = await resource.remove(id: nonExistentId)
        #expect(removed == false)
    }
    
    @Test func testDuplicateResourceError() async throws {
        let resourceSet = ResourceSet()
        let uri = "test://duplicate"
        
        // Create first resource
        let resource1 = await resourceSet.createResource(uri: uri)
        #expect(resource1.uri == uri)
        
        // Try to create duplicate - should return existing
        let resource2 = await resourceSet.createResource(uri: uri)
        #expect(resource1.uri == resource2.uri)
        
        // They should be the same instance
        let retrieved = await resourceSet.getResource(uri: uri)
        #expect(retrieved != nil)
    }
    
    // MARK: - Circular Reference Error Handling
    
    @Test func testCircularReferenceHandling() async throws {
        var nodeClass = EClass(name: "Node")
        let parentRef = EReference(name: "parent", eType: nodeClass)
        let childrenRef = EReference(name: "children", eType: nodeClass, upperBound: -1, containment: true)
        
        nodeClass.eStructuralFeatures = [parentRef, childrenRef]
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://circular")
        var node1 = DynamicEObject(eClass: nodeClass)
        var node2 = DynamicEObject(eClass: nodeClass)
        var node3 = DynamicEObject(eClass: nodeClass)
        
        await resource.add(node1)
        await resource.add(node2)
        await resource.add(node3)
        
        // Create chain: node1 -> node2 -> node3
        node1.eSet("children", value: [node2.id])
        node2.eSet("children", value: [node3.id])
        
        // Now try to create cycle: node3 -> node1 (should be allowed at runtime)
        node3.eSet("children", value: [node1.id])
        
        let node1Children = node1.eGet("children") as? [EUUID]
        let node2Children = node2.eGet("children") as? [EUUID]
        let node3Children = node3.eGet("children") as? [EUUID]
        
        #expect(node1Children?.contains(node2.id) == true)
        #expect(node2Children?.contains(node3.id) == true)
        #expect(node3Children?.contains(node1.id) == true)  // Cycle created
    }
    
    // MARK: - Invalid Operation Error Tests
    
    @Test func testInvalidFeatureAccess() async throws {
        var personClass = EClass(name: "Person")
        let nameAttr = EAttribute(name: "name", eType: EDataType(name: "EString"))
        personClass.eStructuralFeatures = [nameAttr]
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://invalid")
        var person = DynamicEObject(eClass: personClass)
        await resource.add(person)
        
        // Try to access non-existent feature
        person.eSet("nonexistent", value: "value")
        let value = person.eGet("nonexistent")
        
        #expect(value == nil)  // Should return nil for non-existent features
    }
    
    @Test func testInvalidContainmentOperations() async throws {
        var folderClass = EClass(name: "Folder")
        var fileClass = EClass(name: "File")
        let filesRef = EReference(name: "files", eType: fileClass, upperBound: -1, containment: true)
        let parentRef = EReference(name: "parent", eType: folderClass)
        
        folderClass.eStructuralFeatures = [filesRef]
        fileClass.eStructuralFeatures = [parentRef]
        
        let resourceSet = ResourceSet()
        let resource1 = await resourceSet.createResource(uri: "test://folder1")
        let resource2 = await resourceSet.createResource(uri: "test://folder2")
        
        var folder1 = DynamicEObject(eClass: folderClass)
        var folder2 = DynamicEObject(eClass: folderClass)
        let file = DynamicEObject(eClass: fileClass)
        
        await resource1.add(folder1)
        await resource2.add(folder2)
        await resource1.add(file)
        
        // Add file to folder1
        folder1.eSet("files", value: [file.id])
        
        var folder1Files = folder1.eGet("files") as? [EUUID]
        #expect(folder1Files?.contains(file.id) == true)
        
        // Try to add same file to folder2 (containment violation)
        folder2.eSet("files", value: [file.id])
        
        // EMF would typically handle this by moving the object
        let folder2Files = folder2.eGet("files") as? [EUUID]
        #expect(folder2Files?.contains(file.id) == true)
        
        // folder1 might still show the file (depends on implementation)
        folder1Files = folder1.eGet("files") as? [EUUID]
        // Implementation could either remove it from folder1 or allow violation
    }
    
    // MARK: - Memory and Performance Error Handling
    
    @Test func testLargeCollectionHandling() async throws {
        let stringType = EDataType(name: "EString")
        let itemsAttr = EAttribute(name: "items", eType: stringType, upperBound: -1)
        let containerClass = EClass(name: "Container", eStructuralFeatures: [itemsAttr])
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://large")
        var container = DynamicEObject(eClass: containerClass)
        await resource.add(container)
        
        // Create very large collection
        var largeCollection: [String] = []
        for i in 0..<100_000 {
            largeCollection.append("item\(i)")
        }
        
        // Should handle large collections gracefully
        container.eSet("items", value: largeCollection)
        
        let items = container.eGet("items") as? [String]
        #expect(items?.count == 100_000)
        #expect(items?.first == "item0")
        #expect(items?.last == "item99999")
    }
    
    @Test func testDeepObjectHierarchy() async throws {
        var nodeClass = EClass(name: "Node")
        let childRef = EReference(name: "child", eType: nodeClass, containment: true)
        
        nodeClass.eStructuralFeatures = [childRef]
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://deep")
        
        // Create deep hierarchy
        var currentNode = DynamicEObject(eClass: nodeClass)
        await resource.add(currentNode)
        
        for _ in 0..<1000 {
            let childNode = DynamicEObject(eClass: nodeClass)
            await resource.add(childNode)
            currentNode.eSet("child", value: childNode.id)
            currentNode = childNode
        }
        
        // Should handle deep hierarchies
        let rootObjects = await resource.getRootObjects()
        #expect(rootObjects.count >= 1)
    }
    
    // MARK: - Concurrency Error Handling Tests
    
    @Test func testConcurrentResourceAccess() async throws {
        let resourceSet = ResourceSet()
        
        // Create resources concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<100 {
                group.addTask {
                    let resource = await resourceSet.createResource(uri: "test://concurrent\(i)")
                    let nodeClass = EClass(name: "Node")
                    let node = DynamicEObject(eClass: nodeClass)
                    await resource.add(node)
                }
            }
        }
        
        // Verify all resources were created
        for i in 0..<100 {
            let resource = await resourceSet.getResource(uri: "test://concurrent\(i)")
            #expect(resource != nil)
        }
    }
    
    // MARK: - Edge Case Error Handling
    
    @Test func testEmptyStringHandling() async throws {
        let stringType = EDataType(name: "EString")
        let nameAttr = EAttribute(name: "name", eType: stringType)
        let personClass = EClass(name: "Person", eStructuralFeatures: [nameAttr])
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://empty-string")
        var person = DynamicEObject(eClass: personClass)
        await resource.add(person)
        
        // Empty string should be valid
        person.eSet("name", value: "")
        let name = person.eGet("name") as? String
        #expect(name == "")
        
        // Whitespace-only string
        person.eSet("name", value: "   ")
        let whitespace = person.eGet("name") as? String
        #expect(whitespace == "   ")
    }
    
    @Test func testSpecialCharacterHandling() async throws {
        let stringType = EDataType(name: "EString")
        let textAttr = EAttribute(name: "text", eType: stringType)
        let documentClass = EClass(name: "Document", eStructuralFeatures: [textAttr])
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://special-chars")
        var document = DynamicEObject(eClass: documentClass)
        await resource.add(document)
        
        let specialTexts = [
            "Unicode: 🎉🚀💡",
            "Newlines:\nMultiple\nLines",
            "Tabs:\tTabbed\tText",
            "Quotes: \"quoted\" and 'single'",
            "Backslashes: \\path\\to\\file",
            "HTML: <tag>content</tag>",
            "JSON: {\"key\": \"value\"}",
            "XML: <?xml version=\"1.0\"?>"
        ]
        
        for specialText in specialTexts {
            document.eSet("text", value: specialText)
            let retrieved = document.eGet("text") as? String
            #expect(retrieved == specialText)
        }
    }
    
    @Test func testNumericEdgeCaseHandling() async throws {
        let intType = EDataType(name: "EInt")
        let doubleType = EDataType(name: "EDouble")
        let intAttr = EAttribute(name: "intValue", eType: intType)
        let doubleAttr = EAttribute(name: "doubleValue", eType: doubleType)
        let numberClass = EClass(name: "Numbers", eStructuralFeatures: [intAttr, doubleAttr])
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://numbers")
        var numbers = DynamicEObject(eClass: numberClass)
        await resource.add(numbers)
        
        let edgeCases = [
            ("zero", 0),
            ("negative", -42),
            ("large", Int.max),
            ("min", Int.min)
        ]
        
        for (_, value) in edgeCases {
            numbers.eSet("intValue", value: value)
            let retrieved = numbers.eGet("intValue") as? Int
            #expect(retrieved == value)
        }
        
        let doubleEdgeCases = [
            ("zero", 0.0),
            ("negative", -3.14159),
            ("infinity", Double.infinity),
            ("negInfinity", -Double.infinity)
        ]
        
        for (_, value) in doubleEdgeCases {
            numbers.eSet("doubleValue", value: value)
            let retrieved = numbers.eGet("doubleValue") as? Double
            if value.isInfinite {
                #expect(retrieved?.isInfinite == true)
                #expect(((retrieved ?? 0) > 0) == (value > 0))  // Same sign
            } else {
                #expect(retrieved == value)
            }
        }
    }
    
    // MARK: - Resource Management Error Tests
    
    @Test func testResourceCleanupAfterError() async throws {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://cleanup")
        
        let nodeClass = EClass(name: "Node")
        let nodes = (0..<100).map { _ in DynamicEObject(eClass: nodeClass) }
        
        // Add many objects
        for node in nodes {
            await resource.add(node)
        }
        
        var allObjects = await resource.getAllObjects()
        #expect(allObjects.count == 100)
        
        // Clear resource
        await resource.clear()
        
        allObjects = await resource.getAllObjects()
        #expect(allObjects.isEmpty)
        
        // Resource should still be functional
        let newNode = DynamicEObject(eClass: nodeClass)
        await resource.add(newNode)
        
        allObjects = await resource.getAllObjects()
        #expect(allObjects.count == 1)
    }
}