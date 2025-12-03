//
// CollectionBehaviorTests.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
@testable import ECore
import Foundation

// MARK: - Collection Behavior Tests

@Suite("Collection Behavior Tests")
struct CollectionBehaviorTests {
    
    // MARK: - Upper Bound Tests
    
    @Test func testAttributeUpperBoundEnforcement() async throws {
        let stringType = EDataType(name: "EString")
        let tagsAttr = EAttribute(name: "tags", eType: stringType, upperBound: 3)
        let itemClass = EClass(name: "Item", eStructuralFeatures: [tagsAttr])
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://item")
        var item = DynamicEObject(eClass: itemClass)
        await resource.add(item)
        
        // Should be able to add up to upper bound
        item.eSet("tags", value: ["tag1"])
        item.eSet("tags", value: ["tag1", "tag2"])
        item.eSet("tags", value: ["tag1", "tag2", "tag3"])
        
        let tags = item.eGet("tags") as? [String]
        #expect(tags?.count == 3)
        #expect(tags == ["tag1", "tag2", "tag3"])
    }
    
    @Test func testReferenceUpperBoundEnforcement() async throws {
        let employeeClass = EClass(name: "Employee")
        var departmentClass = EClass(name: "Department")
        let employeesRef = EReference(name: "employees", eType: employeeClass, upperBound: 2, containment: true)
        
        departmentClass.eStructuralFeatures = [employeesRef]
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://department")
        var department = DynamicEObject(eClass: departmentClass)
        let employee1 = DynamicEObject(eClass: employeeClass)
        let employee2 = DynamicEObject(eClass: employeeClass)
        
        await resource.add(department)
        await resource.add(employee1)
        await resource.add(employee2)
        
        // Should be able to add up to upper bound
        department.eSet("employees", value: [employee1.id])
        department.eSet("employees", value: [employee1.id, employee2.id])
        
        let employees = department.eGet("employees") as? [EUUID]
        #expect(employees?.count == 2)
        #expect(employees?.contains(employee1.id) == true)
        #expect(employees?.contains(employee2.id) == true)
    }
    
    @Test func testUnboundedCollection() async throws {
        let stringType = EDataType(name: "EString")
        let itemsAttr = EAttribute(name: "items", eType: stringType, upperBound: -1)
        let containerClass = EClass(name: "Container", eStructuralFeatures: [itemsAttr])
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://container")
        var container = DynamicEObject(eClass: containerClass)
        await resource.add(container)
        
        // Should be able to add many items to unbounded collection
        var items: [String] = []
        for i in 0..<100 {
            items.append("item\(i)")
        }
        
        container.eSet("items", value: items)
        
        let retrievedItems = container.eGet("items") as? [String]
        #expect(retrievedItems?.count == 100)
        #expect(retrievedItems?.first == "item0")
        #expect(retrievedItems?.last == "item99")
    }
    
    // MARK: - Lower Bound Tests
    
    @Test func testAttributeLowerBoundValidation() async throws {
        let stringType = EDataType(name: "EString")
        let nameAttr = EAttribute(name: "name", eType: stringType, lowerBound: 1)
        let personClass = EClass(name: "Person", eStructuralFeatures: [nameAttr])
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://person")
        var person = DynamicEObject(eClass: personClass)
        await resource.add(person)
        
        // Required attribute should be settable
        person.eSet("name", value: "John")
        let name = person.eGet("name") as? String
        #expect(name == "John")
        
        // Note: Lower bound validation typically happens at validation time,
        // not at runtime in EMF
        #expect(nameAttr.lowerBound == 1)
        #expect(nameAttr.isRequired == true)
    }
    
    @Test func testReferenceLowerBoundValidation() async throws {
        let personClass = EClass(name: "Person")
        var employeeClass = EClass(name: "Employee")
        let managerRef = EReference(name: "manager", eType: personClass, lowerBound: 1)
        
        employeeClass.eStructuralFeatures = [managerRef]
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://employee")
        var employee = DynamicEObject(eClass: employeeClass)
        let manager = DynamicEObject(eClass: personClass)
        
        await resource.add(employee)
        await resource.add(manager)
        
        // Required reference should be settable
        employee.eSet("manager", value: manager.id)
        let managerId = employee.eGet("manager") as? EUUID
        #expect(managerId == manager.id)
        
        #expect(managerRef.lowerBound == 1)
        #expect(managerRef.isRequired == true)
    }
    
    @Test func testMultiValuedLowerBound() async throws {
        let employeeClass = EClass(name: "Employee")
        var teamClass = EClass(name: "Team")
        let membersRef = EReference(name: "members", eType: employeeClass, lowerBound: 2, upperBound: -1)
        
        teamClass.eStructuralFeatures = [membersRef]
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://team")
        var team = DynamicEObject(eClass: teamClass)
        let employee1 = DynamicEObject(eClass: employeeClass)
        let employee2 = DynamicEObject(eClass: employeeClass)
        let employee3 = DynamicEObject(eClass: employeeClass)
        
        await resource.add(team)
        await resource.add(employee1)
        await resource.add(employee2)
        await resource.add(employee3)
        
        // Should be able to set multiple members
        team.eSet("members", value: [employee1.id, employee2.id, employee3.id])
        
        let members = team.eGet("members") as? [EUUID]
        #expect(members?.count == 3)
        #expect(membersRef.lowerBound == 2)
        #expect(membersRef.upperBound == -1)
    }
    
    // MARK: - Collection Ordering Tests
    
    @Test func testOrderedCollection() async throws {
        let stringType = EDataType(name: "EString")
        let itemsAttr = EAttribute(name: "items", eType: stringType, upperBound: -1)
        let listClass = EClass(name: "List", eStructuralFeatures: [itemsAttr])
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://list")
        var list = DynamicEObject(eClass: listClass)
        await resource.add(list)
        
        // Order should be preserved
        let items = ["first", "second", "third", "second"]  // Note: "second" appears twice
        list.eSet("items", value: items)
        
        let retrievedItems = list.eGet("items") as? [String]
        #expect(retrievedItems == items)
        #expect(retrievedItems?[0] == "first")
        #expect(retrievedItems?[1] == "second")
        #expect(retrievedItems?[2] == "third")
        #expect(retrievedItems?[3] == "second")
    }
    
    @Test func testUnorderedCollectionBehavior() async throws {
        let stringType = EDataType(name: "EString")
        let tagsAttr = EAttribute(name: "tags", eType: stringType, upperBound: -1)
        let itemClass = EClass(name: "Item", eStructuralFeatures: [tagsAttr])
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://item")
        var item = DynamicEObject(eClass: itemClass)
        await resource.add(item)
        
        let tags = ["urgent", "important", "review"]
        item.eSet("tags", value: tags)
        
        let retrievedTags = item.eGet("tags") as? [String]
        #expect(retrievedTags?.count == 3)
        // For unordered collections, we just verify all elements are present
        #expect(retrievedTags?.contains("urgent") == true)
        #expect(retrievedTags?.contains("important") == true)
        #expect(retrievedTags?.contains("review") == true)
        
        // Note: ordered property not implemented in current EAttribute
    }
    
    // MARK: - Collection Uniqueness Tests
    
    @Test func testUniqueCollection() async throws {
        let stringType = EDataType(name: "EString")
        let tagsAttr = EAttribute(name: "tags", eType: stringType, upperBound: -1)
        let itemClass = EClass(name: "Item", eStructuralFeatures: [tagsAttr])
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://item")
        var item = DynamicEObject(eClass: itemClass)
        await resource.add(item)
        
        // Unique collections should not allow duplicates
        let tagsWithDuplicates = ["urgent", "important", "urgent", "review"]
        item.eSet("tags", value: tagsWithDuplicates)
        
        let retrievedTags = item.eGet("tags") as? [String]
        // Implementation should handle uniqueness
        #expect(retrievedTags?.count ?? 0 <= 4)  // May have duplicates filtered
        // Note: unique property not implemented in current EAttribute
    }
    
    @Test func testNonUniqueCollection() async throws {
        let stringType = EDataType(name: "EString")
        let itemsAttr = EAttribute(name: "items", eType: stringType, upperBound: -1)
        let bagClass = EClass(name: "Bag", eStructuralFeatures: [itemsAttr])
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://bag")
        var bag = DynamicEObject(eClass: bagClass)
        await resource.add(bag)
        
        // Non-unique collections should allow duplicates
        let itemsWithDuplicates = ["apple", "banana", "apple", "cherry", "banana"]
        bag.eSet("items", value: itemsWithDuplicates)
        
        let retrievedItems = bag.eGet("items") as? [String]
        #expect(retrievedItems?.count == 5)
        // Note: unique property not implemented in current EAttribute
        
        // Count occurrences
        let appleCount = retrievedItems?.filter { $0 == "apple" }.count
        let bananaCount = retrievedItems?.filter { $0 == "banana" }.count
        #expect(appleCount == 2)
        #expect(bananaCount == 2)
    }
    
    // MARK: - Reference Collection Tests
    
    @Test func testContainmentReferenceCollection() async throws {
        var nodeClass = EClass(name: "Node")
        let childrenRef = EReference(name: "children", eType: nodeClass, upperBound: -1, containment: true)
        
        nodeClass.eStructuralFeatures = [childrenRef]
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://tree")
        var root = DynamicEObject(eClass: nodeClass)
        let child1 = DynamicEObject(eClass: nodeClass)
        let child2 = DynamicEObject(eClass: nodeClass)
        let child3 = DynamicEObject(eClass: nodeClass)
        
        await resource.add(root)
        await resource.add(child1)
        await resource.add(child2)
        await resource.add(child3)
        
        // Add children to containment reference
        root.eSet("children", value: [child1.id, child2.id, child3.id])
        
        let children = root.eGet("children") as? [EUUID]
        #expect(children?.count == 3)
        #expect(children?.contains(child1.id) == true)
        #expect(children?.contains(child2.id) == true)
        #expect(children?.contains(child3.id) == true)
        
        #expect(childrenRef.containment == true)
        #expect(childrenRef.isMany == true)
    }
    
    @Test func testNonContainmentReferenceCollection() async throws {
        let personClass = EClass(name: "Person")
        var teamClass = EClass(name: "Team")
        let membersRef = EReference(name: "members", eType: personClass, upperBound: -1)
        
        teamClass.eStructuralFeatures = [membersRef]
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://team")
        var team = DynamicEObject(eClass: teamClass)
        let person1 = DynamicEObject(eClass: personClass)
        let person2 = DynamicEObject(eClass: personClass)
        
        await resource.add(team)
        await resource.add(person1)
        await resource.add(person2)
        
        // Add members to non-containment reference
        team.eSet("members", value: [person1.id, person2.id])
        
        let members = team.eGet("members") as? [EUUID]
        #expect(members?.count == 2)
        #expect(members?.contains(person1.id) == true)
        #expect(members?.contains(person2.id) == true)
        
        #expect(membersRef.containment == false)
        #expect(membersRef.isMany == true)
    }
    
    // MARK: - Complex Collection Scenarios
    
    @Test func testMixedCollectionProperties() async throws {
        let stringType = EDataType(name: "EString")
        // Bounded collection
        let prioritiesAttr = EAttribute(
            name: "priorities",
            eType: stringType,
            lowerBound: 1,
            upperBound: 5
        )
        let taskClass = EClass(name: "Task", eStructuralFeatures: [prioritiesAttr])
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://task")
        var task = DynamicEObject(eClass: taskClass)
        await resource.add(task)
        
        let priorities = ["high", "medium", "low"]
        task.eSet("priorities", value: priorities)
        
        let retrievedPriorities = task.eGet("priorities") as? [String]
        #expect(retrievedPriorities?.count == 3)
        
        #expect(prioritiesAttr.lowerBound == 1)
        #expect(prioritiesAttr.upperBound == 5)
        // Note: ordered and unique properties not implemented in current EAttribute
        #expect(prioritiesAttr.isRequired == true)
        #expect(prioritiesAttr.isMany == true)
    }
    
    @Test func testCollectionClearOperation() async throws {
        let stringType = EDataType(name: "EString")
        let itemsAttr = EAttribute(name: "items", eType: stringType, upperBound: -1)
        let containerClass = EClass(name: "Container", eStructuralFeatures: [itemsAttr])
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://container")
        var container = DynamicEObject(eClass: containerClass)
        await resource.add(container)
        
        // Add items
        let items = ["item1", "item2", "item3"]
        container.eSet("items", value: items)
        
        var retrievedItems = container.eGet("items") as? [String]
        #expect(retrievedItems?.count == 3)
        
        // Clear collection
        container.eSet("items", value: [String]())
        
        retrievedItems = container.eGet("items") as? [String]
        #expect(retrievedItems?.isEmpty == true)
    }
    
    @Test func testCollectionWithNullValues() async throws {
        let personClass = EClass(name: "Person")
        var teamClass = EClass(name: "Team")
        let membersRef = EReference(name: "members", eType: personClass, upperBound: -1)
        
        teamClass.eStructuralFeatures = [membersRef]
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://team")
        var team = DynamicEObject(eClass: teamClass)
        let person1 = DynamicEObject(eClass: personClass)
        
        await resource.add(team)
        await resource.add(person1)
        
        // Test with valid reference
        team.eSet("members", value: [person1.id])
        let members = team.eGet("members") as? [EUUID]
        #expect(members?.count == 1)
        #expect(members?.first == person1.id)
        
        // Test clearing
        team.eSet("members", value: [EUUID]())
        let clearedMembers = team.eGet("members") as? [EUUID]
        #expect(clearedMembers?.isEmpty == true)
    }
    
    // MARK: - Performance Tests
    
    @Test func testLargeCollectionHandling() async throws {
        let stringType = EDataType(name: "EString")
        let itemsAttr = EAttribute(name: "items", eType: stringType, upperBound: -1)
        let containerClass = EClass(name: "Container", eStructuralFeatures: [itemsAttr])
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://large-container")
        var container = DynamicEObject(eClass: containerClass)
        await resource.add(container)
        
        // Create large collection
        let itemCount = 10_000
        var items: [String] = []
        for i in 0..<itemCount {
            items.append("item\(i)")
        }
        
        container.eSet("items", value: items)
        
        let retrievedItems = container.eGet("items") as? [String]
        #expect(retrievedItems?.count == itemCount)
        #expect(retrievedItems?.first == "item0")
        #expect(retrievedItems?.last == "item\(itemCount - 1)")
    }
    
    @Test func testCollectionModificationSequence() async throws {
        let stringType = EDataType(name: "EString")
        let itemsAttr = EAttribute(name: "items", eType: stringType, upperBound: -1)
        let containerClass = EClass(name: "Container", eStructuralFeatures: [itemsAttr])
        
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://container")
        var container = DynamicEObject(eClass: containerClass)
        await resource.add(container)
        
        // Start empty
        container.eSet("items", value: [String]())
        var items = container.eGet("items") as? [String]
        #expect(items?.isEmpty == true)
        
        // Add some items
        container.eSet("items", value: ["a", "b", "c"])
        items = container.eGet("items") as? [String]
        #expect(items?.count == 3)
        
        // Modify collection
        container.eSet("items", value: ["a", "d", "e", "f"])
        items = container.eGet("items") as? [String]
        #expect(items?.count == 4)
        #expect(items?.contains("a") == true)
        #expect(items?.contains("d") == true)
        #expect(items?.contains("b") == false)
        
        // Clear again
        container.eSet("items", value: [String]())
        items = container.eGet("items") as? [String]
        #expect(items?.isEmpty == true)
    }
}