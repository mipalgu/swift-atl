//
// NotificationTests.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
@testable import ECore
import Foundation

// MARK: - Test Notification Observer

/// Mock observer for testing notification patterns
actor TestObserver {
    private(set) var notifications: [TestNotification] = []
    private(set) var callCount: Int = 0
    
    func record(_ notification: TestNotification) {
        notifications.append(notification)
        callCount += 1
    }
    
    func reset() {
        notifications.removeAll()
        callCount = 0
    }
    
    func lastNotification() -> TestNotification? {
        notifications.last
    }
}

/// Test notification structure
struct TestNotification: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case add
        case remove
        case set
        case unset
        case move
    }
    
    let kind: Kind
    let feature: String?
    let oldValue: String?
    let newValue: String?
    let position: Int?
    
    init(kind: Kind, feature: String? = nil, oldValue: String? = nil, newValue: String? = nil, position: Int? = nil) {
        self.kind = kind
        self.feature = feature
        self.oldValue = oldValue
        self.newValue = newValue
        self.position = position
    }
}

// MARK: - Notification System Tests

@Suite("Notification System Tests")
struct NotificationTests {
    
    // MARK: - Basic Notification Tests
    
    @Test func testAttributeSetNotification() async throws {
        let observer = TestObserver()
        let stringType = EDataType(name: "EString")
        let nameAttr = EAttribute(name: "name", eType: stringType)
        let personClass = EClass(name: "Person", eStructuralFeatures: [nameAttr])
        
        let _ = DynamicEObject(eClass: personClass)
        
        // Simulate setting an attribute
        await observer.record(TestNotification(
            kind: .set,
            feature: "name",
            oldValue: nil,
            newValue: "John"
        ))
        
        let notification = await observer.lastNotification()
        #expect(notification?.kind == .set)
        #expect(notification?.feature == "name")
        #expect(notification?.newValue == "John")
        #expect(await observer.callCount == 1)
    }
    
    @Test func testAttributeUnsetNotification() async throws {
        let observer = TestObserver()
        let stringType = EDataType(name: "EString")
        let nameAttr = EAttribute(name: "name", eType: stringType)
        let personClass = EClass(name: "Person", eStructuralFeatures: [nameAttr])
        
        let _ = DynamicEObject(eClass: personClass)
        
        // Simulate unsetting an attribute
        await observer.record(TestNotification(
            kind: .unset,
            feature: "name",
            oldValue: "John",
            newValue: nil
        ))
        
        let notification = await observer.lastNotification()
        #expect(notification?.kind == .unset)
        #expect(notification?.feature == "name")
        #expect(notification?.oldValue == "John")
        #expect(await observer.callCount == 1)
    }
    
    @Test func testReferenceAddNotification() async throws {
        let observer = TestObserver()
        let personClass = EClass(name: "Person")
        var employeeClass = EClass(name: "Employee")
        let managerRef = EReference(name: "manager", eType: personClass)
        
        employeeClass.eStructuralFeatures = [managerRef]
        
        let _ = DynamicEObject(eClass: employeeClass)
        let _ = DynamicEObject(eClass: personClass)
        
        // Simulate adding a reference
        await observer.record(TestNotification(
            kind: .add,
            feature: "manager",
            newValue: "Manager"
        ))
        
        let notification = await observer.lastNotification()
        #expect(notification?.kind == .add)
        #expect(notification?.feature == "manager")
        #expect(await observer.callCount == 1)
    }
    
    @Test func testReferenceRemoveNotification() async throws {
        let observer = TestObserver()
        let personClass = EClass(name: "Person")
        var employeeClass = EClass(name: "Employee")
        let managerRef = EReference(name: "manager", eType: personClass)
        
        employeeClass.eStructuralFeatures = [managerRef]
        
        let _ = DynamicEObject(eClass: employeeClass)
        
        // Simulate removing a reference
        await observer.record(TestNotification(
            kind: .remove,
            feature: "manager",
            oldValue: "Manager"
        ))
        
        let notification = await observer.lastNotification()
        #expect(notification?.kind == .remove)
        #expect(notification?.feature == "manager")
        #expect(notification?.oldValue == "Manager")
        #expect(await observer.callCount == 1)
    }
    
    // MARK: - Collection Notification Tests
    
    @Test func testMultiValuedAttributeAddNotification() async throws {
        let observer = TestObserver()
        let stringType = EDataType(name: "EString")
        let tagsAttr = EAttribute(name: "tags", eType: stringType, upperBound: -1)
        let itemClass = EClass(name: "Item", eStructuralFeatures: [tagsAttr])
        
        let _ = DynamicEObject(eClass: itemClass)
        
        // Simulate adding to collection
        await observer.record(TestNotification(
            kind: .add,
            feature: "tags",
            newValue: "urgent",
            position: 0
        ))
        
        let notification = await observer.lastNotification()
        #expect(notification?.kind == .add)
        #expect(notification?.feature == "tags")
        #expect(notification?.newValue == "urgent")
        #expect(notification?.position == 0)
        #expect(await observer.callCount == 1)
    }
    
    @Test func testMultiValuedReferenceAddNotification() async throws {
        let observer = TestObserver()
        let employeeClass = EClass(name: "Employee")
        var departmentClass = EClass(name: "Department")
        let employeesRef = EReference(name: "employees", eType: employeeClass, upperBound: -1, containment: true)
        
        departmentClass.eStructuralFeatures = [employeesRef]
        
        let _ = DynamicEObject(eClass: departmentClass)
        let _ = DynamicEObject(eClass: employeeClass)
        
        // Simulate adding to collection
        await observer.record(TestNotification(
            kind: .add,
            feature: "employees",
            newValue: "Employee1",
            position: 0
        ))
        
        let notification = await observer.lastNotification()
        #expect(notification?.kind == .add)
        #expect(notification?.feature == "employees")
        #expect(notification?.position == 0)
        #expect(await observer.callCount == 1)
    }
    
    @Test func testMultiValuedReferenceRemoveNotification() async throws {
        let observer = TestObserver()
        let employeeClass = EClass(name: "Employee")
        var departmentClass = EClass(name: "Department")
        let employeesRef = EReference(name: "employees", eType: employeeClass, upperBound: -1, containment: true)
        
        departmentClass.eStructuralFeatures = [employeesRef]
        
        let _ = DynamicEObject(eClass: departmentClass)
        
        // Simulate removing from collection
        await observer.record(TestNotification(
            kind: .remove,
            feature: "employees",
            oldValue: "Employee1",
            position: 0
        ))
        
        let notification = await observer.lastNotification()
        #expect(notification?.kind == .remove)
        #expect(notification?.feature == "employees")
        #expect(notification?.oldValue == "Employee1")
        #expect(notification?.position == 0)
        #expect(await observer.callCount == 1)
    }
    
    // MARK: - Bidirectional Notification Tests
    
    @Test func testBidirectionalReferenceNotifications() async throws {
        let observer1 = TestObserver()
        let observer2 = TestObserver()
        
        var personClass = EClass(name: "Person")
        var bookClass = EClass(name: "Book")
        
        var booksRef = EReference(name: "books", eType: bookClass, upperBound: -1)
        let authorRef = EReference(name: "author", eType: personClass, opposite: booksRef.id)
        booksRef.opposite = authorRef.id
        
        personClass.eStructuralFeatures = [booksRef]
        bookClass.eStructuralFeatures = [authorRef]
        
        let person = DynamicEObject(eClass: personClass)
        var book = DynamicEObject(eClass: bookClass)
        
        // Set up the bidirectional reference
        book.eSet("author", value: person.id)
        
        // Simulate setting one side of bidirectional reference
        await observer1.record(TestNotification(
            kind: .add,
            feature: "books",
            newValue: "Book1"
        ))
        
        // Simulate automatic opposite side notification
        await observer2.record(TestNotification(
            kind: .set,
            feature: "author",
            newValue: "Author1"
        ))
        
        let notification1 = await observer1.lastNotification()
        let notification2 = await observer2.lastNotification()
        
        #expect(notification1?.kind == .add)
        #expect(notification1?.feature == "books")
        #expect(notification2?.kind == .set)
        #expect(notification2?.feature == "author")
        
        #expect(await observer1.callCount == 1)
        #expect(await observer2.callCount == 1)
    }
    
    @Test func testBidirectionalReferenceUnsetNotifications() async throws {
        let observer1 = TestObserver()
        let observer2 = TestObserver()
        
        var personClass = EClass(name: "Person")
        var bookClass = EClass(name: "Book")

        var booksRef = EReference(name: "books", eType: bookClass, upperBound: -1)
        let authorRef = EReference(name: "author", eType: personClass, opposite: booksRef.id)
        booksRef.opposite = authorRef.id
        
        personClass.eStructuralFeatures = [booksRef]
        bookClass.eStructuralFeatures = [authorRef]
        
        // Simulate unsetting one side of bidirectional reference
        await observer1.record(TestNotification(
            kind: .remove,
            feature: "books",
            oldValue: "Book1"
        ))
        
        // Simulate automatic opposite side notification
        await observer2.record(TestNotification(
            kind: .unset,
            feature: "author",
            oldValue: "Author1"
        ))
        
        let notification1 = await observer1.lastNotification()
        let notification2 = await observer2.lastNotification()
        
        #expect(notification1?.kind == .remove)
        #expect(notification1?.feature == "books")
        #expect(notification2?.kind == .unset)
        #expect(notification2?.feature == "author")
        
        #expect(await observer1.callCount == 1)
        #expect(await observer2.callCount == 1)
    }
    
    // MARK: - Containment Notification Tests
    
    @Test func testContainmentAddNotification() async throws {
        let observer = TestObserver()
        let employeeClass = EClass(name: "Employee")
        var departmentClass = EClass(name: "Department")
        let employeesRef = EReference(name: "employees", eType: employeeClass, upperBound: -1, containment: true)
        
        departmentClass.eStructuralFeatures = [employeesRef]
        
        let _ = DynamicEObject(eClass: departmentClass)
        let _ = DynamicEObject(eClass: employeeClass)
        
        // Simulate containment addition
        await observer.record(TestNotification(
            kind: .add,
            feature: "employees",
            newValue: "Employee1"
        ))
        
        let notification = await observer.lastNotification()
        #expect(notification?.kind == .add)
        #expect(notification?.feature == "employees")
        #expect(await observer.callCount == 1)
    }
    
    @Test func testContainmentRemoveNotification() async throws {
        let observer = TestObserver()
        let employeeClass = EClass(name: "Employee")
        var departmentClass = EClass(name: "Department")
        let employeesRef = EReference(name: "employees", eType: employeeClass, upperBound: -1, containment: true)
        
        departmentClass.eStructuralFeatures = [employeesRef]
        
        let _ = DynamicEObject(eClass: departmentClass)
        
        // Simulate containment removal
        await observer.record(TestNotification(
            kind: .remove,
            feature: "employees",
            oldValue: "Employee1"
        ))
        
        let notification = await observer.lastNotification()
        #expect(notification?.kind == .remove)
        #expect(notification?.feature == "employees")
        #expect(notification?.oldValue == "Employee1")
        #expect(await observer.callCount == 1)
    }
    
    // MARK: - Resource Notification Tests
    
    @Test func testResourceAddNotification() async throws {
        let observer = TestObserver()
        let personClass = EClass(name: "Person")
        let _ = DynamicEObject(eClass: personClass)
        
        // Simulate resource addition - note: resources don't typically send notifications
        // for basic add/remove operations, but changes to contained objects do
        await observer.record(TestNotification(
            kind: .add,
            feature: "contents",
            newValue: "Person1"
        ))
        
        let notification = await observer.lastNotification()
        #expect(notification?.kind == .add)
        #expect(notification?.feature == "contents")
        #expect(await observer.callCount == 1)
    }
    
    // MARK: - Complex Scenario Tests
    
    @Test func testMultipleObserversNotification() async throws {
        let observer1 = TestObserver()
        let observer2 = TestObserver()
        let observer3 = TestObserver()
        
        let stringType = EDataType(name: "EString")
        let nameAttr = EAttribute(name: "name", eType: stringType)
        let personClass = EClass(name: "Person", eStructuralFeatures: [nameAttr])
        
        let _ = DynamicEObject(eClass: personClass)
        
        // Simulate notifying multiple observers
        let notification = TestNotification(kind: .set, feature: "name", oldValue: nil, newValue: "John")
        await observer1.record(notification)
        await observer2.record(notification)
        await observer3.record(notification)
        
        #expect(await observer1.callCount == 1)
        #expect(await observer2.callCount == 1)
        #expect(await observer3.callCount == 1)
        
        let notification1 = await observer1.lastNotification()
        let notification2 = await observer2.lastNotification()
        let notification3 = await observer3.lastNotification()
        
        #expect(notification1 == notification)
        #expect(notification2 == notification)
        #expect(notification3 == notification)
    }
    
    @Test func testComplexNotificationSequence() async throws {
        let observer = TestObserver()
        let stringType = EDataType(name: "EString")
        let nameAttr = EAttribute(name: "name", eType: stringType)
        let ageAttr = EAttribute(name: "age", eType: EDataType(name: "EInt"))
        let _ = EClass(name: "Person", eStructuralFeatures: [nameAttr, ageAttr])
        
        // Simulate a sequence of changes
        await observer.record(TestNotification(kind: .set, feature: "name", newValue: "John"))
        await observer.record(TestNotification(kind: .set, feature: "age", newValue: "25"))
        await observer.record(TestNotification(kind: .set, feature: "name", oldValue: "John", newValue: "Jane"))
        
        #expect(await observer.callCount == 3)
        
        let notifications = await observer.notifications
        #expect(notifications.count == 3)
        #expect(notifications[0].feature == "name")
        #expect(notifications[0].newValue == "John")
        #expect(notifications[1].feature == "age")
        #expect(notifications[1].newValue == "25")
        #expect(notifications[2].feature == "name")
        #expect(notifications[2].oldValue == "John")
        #expect(notifications[2].newValue == "Jane")
    }
    
    // MARK: - Performance Tests
    
    @Test func testHighVolumeNotifications() async throws {
        let observer = TestObserver()
        let stringType = EDataType(name: "EString")
        let itemsAttr = EAttribute(name: "items", eType: stringType, upperBound: -1)
        let _ = EClass(name: "Container", eStructuralFeatures: [itemsAttr])
        
        // Simulate adding many items
        for i in 0..<1000 {
            await observer.record(TestNotification(
                kind: .add,
                feature: "items",
                newValue: "item\(i)",
                position: i
            ))
        }
        
        #expect(await observer.callCount == 1000)
        let notifications = await observer.notifications
        #expect(notifications.count == 1000)
        #expect(notifications.first?.newValue == "item0")
        #expect(notifications.last?.newValue == "item999")
    }
}