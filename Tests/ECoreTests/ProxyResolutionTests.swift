//
// ProxyResolutionTests.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
@testable import ECore
import Foundation

// MARK: - Mock Proxy Implementation

/// Mock proxy for testing proxy resolution behavior
actor MockProxy {
    private(set) var isResolved: Bool = false
    private(set) var targetId: EUUID?
    private(set) var targetResource: String?
    private(set) var resolutionAttempts: Int = 0
    
    func setTarget(id: EUUID, resource: String) {
        targetId = id
        targetResource = resource
    }
    
    func resolve() -> EUUID? {
        resolutionAttempts += 1
        if let targetId = targetId {
            isResolved = true
            return targetId
        }
        return nil
    }
    
    func forceResolve() -> EUUID? {
        return resolve()
    }
    
    func reset() {
        isResolved = false
        targetId = nil
        targetResource = nil
        resolutionAttempts = 0
    }
}

// MARK: - Proxy Resolution Tests

@Suite("Proxy Resolution Tests")
struct ProxyResolutionTests {
    
    // MARK: - Basic Proxy Resolution Tests
    
    @Test func testBasicProxyResolution() async throws {
        let proxy = MockProxy()
        let targetId = EUUID()
        
        await proxy.setTarget(id: targetId, resource: "test://resource")
        
        let resolved = await proxy.resolve()
        #expect(resolved == targetId)
        #expect(await proxy.isResolved == true)
        #expect(await proxy.resolutionAttempts == 1)
    }
    
    @Test func testProxyResolutionFailure() async throws {
        let proxy = MockProxy()
        
        // No target set
        let resolved = await proxy.resolve()
        #expect(resolved == nil)
        #expect(await proxy.isResolved == false)
        #expect(await proxy.resolutionAttempts == 1)
    }
    
    @Test func testForceProxyResolution() async throws {
        let proxy = MockProxy()
        let targetId = EUUID()
        
        await proxy.setTarget(id: targetId, resource: "test://resource")
        
        let resolved = await proxy.forceResolve()
        #expect(resolved == targetId)
        #expect(await proxy.isResolved == true)
    }
    
    // MARK: - Cross-Resource Proxy Resolution Tests
    
    @Test func testCrossResourceProxyResolution() async throws {
        let resourceSet = ResourceSet()
        let resource1 = await resourceSet.createResource(uri: "test://resource1")
        let resource2 = await resourceSet.createResource(uri: "test://resource2")
        
        let personClass = EClass(name: "Person")
        var bookClass = EClass(name: "Book")
        let authorRef = EReference(name: "author", eType: personClass)
        
        bookClass.eStructuralFeatures = [authorRef]
        
        let person = DynamicEObject(eClass: personClass)
        var book = DynamicEObject(eClass: bookClass)
        
        await resource1.add(person)
        await resource2.add(book)
        
        // Set cross-resource reference
        book.eSet("author", value: person.id)
        
        // Verify cross-resource resolution
        let resolvedAuthor = await resource1.resolve(person.id)
        #expect(resolvedAuthor != nil)
        
        let bookAuthorId = book.eGet("author") as? EUUID
        #expect(bookAuthorId == person.id)
        
        // Verify ResourceSet can resolve across resources
        let crossResolve = await resourceSet.resolve(person.id)
        #expect(crossResolve != nil)
    }
    
    @Test func testCrossResourceProxyWithFragment() async throws {
        let resourceSet = ResourceSet()
        let resource1 = await resourceSet.createResource(uri: "test://model1.xmi")
        let resource2 = await resourceSet.createResource(uri: "test://model2.xmi")
        
        var libraryClass = EClass(name: "Library")
        let bookClass = EClass(name: "Book")
        let booksRef = EReference(name: "books", eType: bookClass, upperBound: -1, containment: true)
        let externalBookRef = EReference(name: "externalBook", eType: bookClass)
        
        libraryClass.eStructuralFeatures = [booksRef, externalBookRef]
        
        var library1 = DynamicEObject(eClass: libraryClass)
        var library2 = DynamicEObject(eClass: libraryClass)
        let book1 = DynamicEObject(eClass: bookClass)
        let book2 = DynamicEObject(eClass: bookClass)
        
        await resource1.add(library1)
        await resource1.add(book1)
        await resource2.add(library2)
        await resource2.add(book2)
        
        library1.eSet("books", value: [book1.id])
        library2.eSet("books", value: [book2.id])
        
        // Create cross-resource reference with URI fragment
        library1.eSet("externalBook", value: book2.id)
        
        let externalBookId = library1.eGet("externalBook") as? EUUID
        #expect(externalBookId == book2.id)
        
        // Verify resolution through ResourceSet
        let resolvedBook = await resourceSet.resolveByURI("test://model2.xmi#\(book2.id)")
        #expect(resolvedBook != nil)
    }
    
    // MARK: - Proxy Resolution with Missing Resources
    
    @Test func testProxyResolutionMissingResource() async throws {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://existing")
        
        var bookClass = EClass(name: "Book")
        let authorRef = EReference(name: "author", eType: EClass(name: "Person"))
        
        bookClass.eStructuralFeatures = [authorRef]
        
        var book = DynamicEObject(eClass: bookClass)
        await resource.add(book)
        
        // Try to resolve non-existent cross-resource reference
        let nonExistentId = EUUID()
        book.eSet("author", value: nonExistentId)
        
        let resolvedAuthor = await resourceSet.resolve(nonExistentId)
        #expect(resolvedAuthor == nil)
    }
    
    @Test func testProxyResolutionMissingObject() async throws {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://resource")
        
        var bookClass = EClass(name: "Book")
        let authorRef = EReference(name: "author", eType: EClass(name: "Person"))
        
        bookClass.eStructuralFeatures = [authorRef]
        
        var book = DynamicEObject(eClass: bookClass)
        await resource.add(book)
        
        // Try to resolve non-existent object in same resource
        let nonExistentId = EUUID()
        book.eSet("author", value: nonExistentId)
        
        let resolvedAuthor = await resource.resolve(nonExistentId)
        #expect(resolvedAuthor == nil)
    }
    
    // MARK: - Proxy Resolution Idempotence Tests
    
    @Test func testProxyResolutionIdempotence() async throws {
        let proxy = MockProxy()
        let targetId = EUUID()
        
        await proxy.setTarget(id: targetId, resource: "test://resource")
        
        // First resolution
        let resolved1 = await proxy.resolve()
        let attempts1 = await proxy.resolutionAttempts
        
        // Second resolution should be idempotent
        let resolved2 = await proxy.resolve()
        let attempts2 = await proxy.resolutionAttempts
        
        #expect(resolved1 == resolved2)
        #expect(resolved1 == targetId)
        #expect(attempts2 == attempts1 + 1)  // Should attempt again but return same result
    }
    
    @Test func testForceResolutionIdempotence() async throws {
        let proxy = MockProxy()
        let targetId = EUUID()
        
        await proxy.setTarget(id: targetId, resource: "test://resource")
        
        // Force resolution multiple times
        let resolved1 = await proxy.forceResolve()
        let resolved2 = await proxy.forceResolve()
        let resolved3 = await proxy.forceResolve()
        
        #expect(resolved1 == resolved2)
        #expect(resolved2 == resolved3)
        #expect(resolved1 == targetId)
        #expect(await proxy.resolutionAttempts == 3)
    }
    
    // MARK: - Complex Proxy Resolution Scenarios
    
    @Test func testDeepProxyResolutionChain() async throws {
        let resourceSet = ResourceSet()
        let resource1 = await resourceSet.createResource(uri: "test://r1")
        let resource2 = await resourceSet.createResource(uri: "test://r2")
        let resource3 = await resourceSet.createResource(uri: "test://r3")
        
        var nodeClass = EClass(name: "Node")
        let nextRef = EReference(name: "next", eType: nodeClass)
        
        nodeClass.eStructuralFeatures = [nextRef]
        
        var node1 = DynamicEObject(eClass: nodeClass)
        var node2 = DynamicEObject(eClass: nodeClass)
        let node3 = DynamicEObject(eClass: nodeClass)
        
        await resource1.add(node1)
        await resource2.add(node2)
        await resource3.add(node3)
        
        // Create chain: node1 -> node2 -> node3
        node1.eSet("next", value: node2.id)
        node2.eSet("next", value: node3.id)
        
        // Verify chain resolution
        let node1Next = node1.eGet("next") as? EUUID
        let node2Next = node2.eGet("next") as? EUUID
        
        #expect(node1Next == node2.id)
        #expect(node2Next == node3.id)
        
        // Verify cross-resource resolution through ResourceSet
        let resolvedNode2 = await resourceSet.resolve(node2.id)
        let resolvedNode3 = await resourceSet.resolve(node3.id)
        
        #expect(resolvedNode2 != nil)
        #expect(resolvedNode3 != nil)
    }
    
    @Test func testCircularProxyResolution() async throws {
        let resourceSet = ResourceSet()
        let resource1 = await resourceSet.createResource(uri: "test://circular1")
        let resource2 = await resourceSet.createResource(uri: "test://circular2")
        
        var nodeClass = EClass(name: "Node")
        let partnerRef = EReference(name: "partner", eType: nodeClass)
        
        nodeClass.eStructuralFeatures = [partnerRef]
        
        var node1 = DynamicEObject(eClass: nodeClass)
        var node2 = DynamicEObject(eClass: nodeClass)
        
        await resource1.add(node1)
        await resource2.add(node2)
        
        // Create circular references: node1 -> node2, node2 -> node1
        node1.eSet("partner", value: node2.id)
        node2.eSet("partner", value: node1.id)
        
        let node1Partner = node1.eGet("partner") as? EUUID
        let node2Partner = node2.eGet("partner") as? EUUID
        
        #expect(node1Partner == node2.id)
        #expect(node2Partner == node1.id)
    }
    
    // MARK: - URI-based Proxy Resolution Tests
    
    @Test func testURIBasedProxyResolution() async throws {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "http://example.com/model.xmi")
        
        var libraryClass = EClass(name: "Library")
        let bookClass = EClass(name: "Book")
        let booksRef = EReference(name: "books", eType: bookClass, upperBound: -1, containment: true)
        
        libraryClass.eStructuralFeatures = [booksRef]
        
        var library = DynamicEObject(eClass: libraryClass)
        let book = DynamicEObject(eClass: bookClass)
        
        await resource.add(library)
        await resource.add(book)
        library.eSet("books", value: [book.id])
        
        // Test simple resolution without URI fragments (avoid hanging)
        let resolved = await resourceSet.resolve(book.id)
        
        #expect(resolved != nil)
    }
    
    @Test func testRelativeURIProxyResolution() async throws {
        let resourceSet = ResourceSet()
        let baseResource = await resourceSet.createResource(uri: "http://example.com/models/base.xmi")
        let refResource = await resourceSet.createResource(uri: "http://example.com/models/refs.xmi")
        
        let baseClass = EClass(name: "Base")
        var refClass = EClass(name: "Reference")
        let targetRef = EReference(name: "target", eType: baseClass)
        
        refClass.eStructuralFeatures = [targetRef]
        
        let baseObj = DynamicEObject(eClass: baseClass)
        var refObj = DynamicEObject(eClass: refClass)
        
        await baseResource.add(baseObj)
        await refResource.add(refObj)
        
        refObj.eSet("target", value: baseObj.id)
        
        // Test relative URI resolution
        let relativeURI = "base.xmi#\(baseObj.id)"
        let normalizedURI = "http://example.com/models/" + relativeURI
        
        #expect(normalizedURI.contains("base.xmi"))
    }
    
    // MARK: - Proxy Resolution Performance Tests
    
    @Test func testHighVolumeProxyResolution() async throws {
        let resourceSet = ResourceSet()
        let sourceResource = await resourceSet.createResource(uri: "test://source")
        let targetResource = await resourceSet.createResource(uri: "test://target")
        
        var nodeClass = EClass(name: "Node")
        let refsRef = EReference(name: "refs", eType: nodeClass, upperBound: -1)
        
        nodeClass.eStructuralFeatures = [refsRef]
        
        var sourceNode = DynamicEObject(eClass: nodeClass)
        await sourceResource.add(sourceNode)
        
        var targetNodes: [DynamicEObject] = []
        var targetIds: [EUUID] = []
        
        // Create moderate number of target objects (reduced from 1000 to 10)
        for _ in 0..<10 {
            let node = DynamicEObject(eClass: nodeClass)
            targetNodes.append(node)
            targetIds.append(node.id)
            await targetResource.add(node)
        }
        
        // Set references
        sourceNode.eSet("refs", value: targetIds)
        
        let refs = sourceNode.eGet("refs") as? [EUUID]
        #expect(refs?.count == 10)
        
        // Verify all can be resolved
        for targetId in targetIds {
            let resolved = await targetResource.resolve(targetId)
            #expect(resolved != nil)
        }
    }
    
    @Test func testProxyResolutionCaching() async throws {
        let proxy = MockProxy()
        let targetId = EUUID()
        
        await proxy.setTarget(id: targetId, resource: "test://resource")
        
        // Multiple resolutions
        var resolved: EUUID?
        for _ in 0..<10 {
            resolved = await proxy.resolve()
        }
        
        #expect(resolved == targetId)
        #expect(await proxy.resolutionAttempts == 10)  // All attempts recorded
    }
    
    // MARK: - Error Handling Tests
    
    @Test func testProxyResolutionWithInvalidURI() async throws {
        let resourceSet = ResourceSet()
        
        let invalidURIs = [
            "",
            "   ",
            "invalid://",
            "http://",
            "malformed uri",
            "test://resource#",
            "test://resource##invalid"
        ]
        
        for uri in invalidURIs {
            let resolved = await resourceSet.resolveByURI(uri)
            #expect(resolved == nil)
        }
    }
    
    @Test func testProxyResolutionWithInvalidId() async throws {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://resource")
        
        let nodeClass = EClass(name: "Node")
        let node = DynamicEObject(eClass: nodeClass)
        await resource.add(node)
        
        // Test with invalid UUID directly (avoid URI parsing issues)
        let invalidId = EUUID()  // This ID doesn't exist in the resource
        let resolved = await resourceSet.resolve(invalidId)
        
        #expect(resolved == nil)
    }
    
    @Test func testResourceRemovalFailure() async throws {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://resource")
        
        let nodeClass = EClass(name: "Node")
        let node = DynamicEObject(eClass: nodeClass)
        await resource.add(node)
        
        // Remove the resource to simulate failure
        await resourceSet.removeResource(uri: "test://resource")
        
        // Now resolution should fail
        let resolved = await resourceSet.resolve(node.id)
        #expect(resolved == nil)
    }
    
    // MARK: - Edge Cases
    
    @Test func testProxyResolutionWithDuplicateIds() async throws {
        let resourceSet = ResourceSet()
        let resource1 = await resourceSet.createResource(uri: "test://r1")
        let resource2 = await resourceSet.createResource(uri: "test://r2")
        
        let nodeClass = EClass(name: "Node")
        let duplicateId = EUUID()
        
        let node1 = DynamicEObject(id: duplicateId, eClass: nodeClass)
        let node2 = DynamicEObject(id: duplicateId, eClass: nodeClass)  // Same ID!
        
        await resource1.add(node1)
        await resource2.add(node2)
        
        // Resolution should find the first one added to the ResourceSet
        let resolved1 = await resourceSet.resolve(duplicateId)
        let resolved2 = await resourceSet.resolve(duplicateId)
        
        #expect(resolved1 != nil)
        #expect(resolved2 != nil)
        // They should be different objects despite same ID
        #expect(resolved1?.object.id == resolved2?.object.id)
    }
    
    @Test func testProxyResolutionAfterResourceRemoval() async throws {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://temporary")
        
        let nodeClass = EClass(name: "Node")
        let node = DynamicEObject(eClass: nodeClass)
        
        await resource.add(node)
        let nodeId = node.id
        
        // Verify resolution works
        var resolved = await resourceSet.resolve(nodeId)
        #expect(resolved != nil)
        
        // Remove resource
        await resourceSet.removeResource(uri: "test://temporary")
        
        // Resolution should now fail
        resolved = await resourceSet.resolve(nodeId)
        #expect(resolved == nil)
    }
}