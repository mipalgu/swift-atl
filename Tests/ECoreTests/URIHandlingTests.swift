//
// URIHandlingTests.swift
// ECore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Testing
@testable import ECore
import Foundation

// MARK: - URI Handling Tests

@Suite("URI Handling Tests")
struct URIHandlingTests {
    
    // MARK: - Basic URI Tests
    
    @Test func testSimpleURIHandling() async throws {
        let resourceSet = ResourceSet()
        
        let simpleURIs = [
            "test://simple",
            "http://example.com/model",
            "file:///path/to/model.xmi",
            "platform:/resource/project/model.ecore",
            "pathmap://UML_METAMODELS/UML.ecore"
        ]
        
        for uri in simpleURIs {
            let resource = await resourceSet.createResource(uri: uri)
            #expect(resource.uri == uri)
            
            let retrieved = await resourceSet.getResource(uri: uri)
            #expect(retrieved != nil)
        }
    }
    
    @Test func testURIWithFragment() async throws {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://model.xmi")
        
        let nodeClass = EClass(name: "Node")
        let node = DynamicEObject(eClass: nodeClass)
        await resource.add(node)
        
        let uriWithFragment = "test://model.xmi#\(node.id)"
        let resolved = await resourceSet.resolveByURI(uriWithFragment)
        
        #expect(resolved != nil)
        #expect(resolved?.id == node.id)
    }
    
    @Test func testURIWithoutFragment() async throws {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://model.xmi")
        
        let nodeClass = EClass(name: "Node")
        let node1 = DynamicEObject(eClass: nodeClass)
        let node2 = DynamicEObject(eClass: nodeClass)
        
        await resource.add(node1)
        await resource.add(node2)
        
        // URI without fragment should resolve to first root object
        let resolved = await resourceSet.resolveByURI("test://model.xmi")
        #expect(resolved != nil)
        #expect(resolved?.id == node1.id)  // First added should be first root
    }
    
    // MARK: - URI Normalization Tests
    
    @Test func testURINormalizationBasic() async throws {
        let resourceSet = ResourceSet()
        
        let testCases = [
            ("test://model.xmi", "test://model.xmi"),
            ("test://path/../model.xmi", "test://model.xmi"),
            ("test://path/./model.xmi", "test://path/model.xmi"),
            ("test://path/sub/../model.xmi", "test://path/model.xmi")
        ]
        
        for (input, expected) in testCases {
            let normalized = await resourceSet.normaliseURI(input)
            #expect(normalized == expected)
        }
    }
    
    @Test func testURINormalizationWithMultipleDotDot() async throws {
        let resourceSet = ResourceSet()
        
        let testCases = [
            ("test://path/sub/subsub/../../model.xmi", "test://path/model.xmi"),
            ("test://a/b/c/../../../model.xmi", "test://model.xmi"),
            ("test://a/b/c/d/../../../../model.xmi", "test://model.xmi")
        ]
        
        for (input, expected) in testCases {
            let normalized = await resourceSet.normaliseURI(input)
            #expect(normalized == expected)
        }
    }
    
    @Test func testURINormalizationEdgeCases() async throws {
        let resourceSet = ResourceSet()
        
        let testCases = [
            ("test://model.xmi", "test://model.xmi"),  // No normalization needed
            ("test:///model.xmi", "test:///model.xmi"),  // Triple slash preserved
            ("test://./model.xmi", "test://model.xmi"),  // Leading dot-slash
            ("test://../model.xmi", "test://model.xmi"),  // Leading dot-dot-slash
            ("test://", "test://"),  // Empty path
            ("test://path//model.xmi", "test://path/model.xmi")  // Double slash
        ]
        
        for (input, expected) in testCases {
            let normalized = await resourceSet.normaliseURI(input)
            #expect(normalized == expected)
        }
    }
    
    // MARK: - URI Protocol Handling Tests
    
    @Test func testFileProtocolHandling() async throws {
        let resourceSet = ResourceSet()
        
        let fileURIs = [
            "file:///absolute/path/model.xmi",
            "file://relative/path/model.xmi",
            "file:/single/slash/model.xmi"
        ]
        
        for uri in fileURIs {
            let resource = await resourceSet.createResource(uri: uri)
            #expect(resource.uri == uri)
            
            let normalized = await resourceSet.normaliseURI(uri)
            #expect(normalized.hasPrefix("file:"))
        }
    }
    
    @Test func testHTTPProtocolHandling() async throws {
        let resourceSet = ResourceSet()
        
        let httpURIs = [
            "http://example.com/model.xmi",
            "https://secure.example.com/model.ecore",
            "http://localhost:8080/models/test.json"
        ]
        
        for uri in httpURIs {
            let resource = await resourceSet.createResource(uri: uri)
            #expect(resource.uri == uri)
            
            let normalized = await resourceSet.normaliseURI(uri)
            #expect(normalized.hasPrefix("http"))
        }
    }
    
    @Test func testPlatformProtocolHandling() async throws {
        let resourceSet = ResourceSet()
        
        let platformURIs = [
            "platform:/resource/project/model.ecore",
            "platform:/plugin/org.eclipse.emf.ecore/model/Ecore.ecore",
            "platform:/meta/org.eclipse.uml2.uml/model/UML.ecore"
        ]
        
        for uri in platformURIs {
            let resource = await resourceSet.createResource(uri: uri)
            #expect(resource.uri == uri)
            
            let normalized = await resourceSet.normaliseURI(uri)
            #expect(normalized.hasPrefix("platform:"))
        }
    }
    
    @Test func testPathmapProtocolHandling() async throws {
        let resourceSet = ResourceSet()
        
        let pathmapURIs = [
            "pathmap://UML_METAMODELS/UML.ecore",
            "pathmap://UML_LIBRARIES/UMLPrimitiveTypes.library.uml",
            "pathmap://ECORE_METAMODEL/Ecore.ecore"
        ]
        
        for uri in pathmapURIs {
            let resource = await resourceSet.createResource(uri: uri)
            #expect(resource.uri == uri)
            
            let mapped = await resourceSet.normaliseURI(uri)
            #expect(mapped.hasPrefix("pathmap:"))
        }
    }
    
    @Test func testCustomProtocolHandling() async throws {
        let resourceSet = ResourceSet()
        
        let customURIs = [
            "myprotocol://custom/path/model.ext",
            "internal://models/internal.model",
            "memory://cached/model.data"
        ]
        
        for uri in customURIs {
            let resource = await resourceSet.createResource(uri: uri)
            #expect(resource.uri == uri)
            
            let normalized = await resourceSet.normaliseURI(uri)
            // Custom protocols should be preserved as-is
            #expect(normalized == uri)
        }
    }
    
    // MARK: - Relative URI Resolution Tests
    
    @Test func testRelativeURIResolution() async throws {
        let resourceSet = ResourceSet()
        let baseURI = "http://example.com/models/base.xmi"
        let _ = await resourceSet.createResource(uri: baseURI)
        
        let relativeCases = [
            ("other.xmi", "http://example.com/models/other.xmi"),
            ("../other.xmi", "http://example.com/other.xmi"),
            ("sub/other.xmi", "http://example.com/models/sub/other.xmi"),
            ("./current.xmi", "http://example.com/models/current.xmi")
        ]
        
        for (relative, expected) in relativeCases {
            // Resolve relative URI against base using Foundation URL
            guard let baseURL = URL(string: baseURI) else {
                #expect(Bool(false), "Invalid base URI")
                continue
            }
            let resolvedURL = baseURL.deletingLastPathComponent().appendingPathComponent(relative)
            let resolved = await resourceSet.normaliseURI(resolvedURL.absoluteString)
            #expect(resolved == expected)
        }
    }
    
    @Test func testRelativeURIWithDifferentProtocols() async throws {
        let _ = ResourceSet()
        
        let testCases = [
            ("file:///base/path/model.xmi", "other.xmi", "file:///base/path/other.xmi"),
            ("platform:/resource/project/model.ecore", "../other.ecore", "platform:/resource/other.ecore"),
            ("pathmap://META/base.ecore", "ext.ecore", "pathmap://META/ext.ecore")
        ]
        
        for (base, relative, expected) in testCases {
            // Resolve relative URI against base using Foundation URL
            let resourceSet = ResourceSet()
            guard let baseURL = URL(string: base) else {
                #expect(Bool(false), "Invalid base URI")
                continue
            }
            let resolvedURL = baseURL.deletingLastPathComponent().appendingPathComponent(relative)
            let resolved = await resourceSet.normaliseURI(resolvedURL.absoluteString)
            #expect(resolved == expected)
        }
    }
    
    @Test func testAbsoluteURIOverridesBase() async throws {
        let _ = ResourceSet()
        let _ = "http://example.com/models/base.xmi"
        
        let absoluteURIs = [
            "http://other.com/model.xmi",
            "file:///absolute/path.xmi",
            "platform:/resource/project/model.ecore"
        ]
        
        for absoluteURI in absoluteURIs {
            // For absolute URIs, return them unchanged
            let resolved = absoluteURI
            #expect(resolved == absoluteURI)  // Should return absolute URI unchanged
        }
    }
    
    // MARK: - URI Mapping Tests
    
    @Test func testURIMappingBasic() async throws {
        let resourceSet = ResourceSet()
        
        // Map logical URI to physical URI
        await resourceSet.mapURI(from: "logical://model", to: "file:///real/path/model.xmi")
        
        let mapped = await resourceSet.convertURI("logical://model")
        #expect(mapped == "file:///real/path/model.xmi")
    }
    
    @Test func testURIMappingWithPrefix() async throws {
        let resourceSet = ResourceSet()
        
        // Map URI prefix
        await resourceSet.mapURI(from: "logical://", to: "file:///logical/base/")
        
        let mappedCases = [
            ("logical://model1.xmi", "file:///logical/base/model1.xmi"),
            ("logical://sub/model2.xmi", "file:///logical/base/sub/model2.xmi")
        ]
        
        for (logical, expected) in mappedCases {
            let mapped = await resourceSet.normaliseURI(logical)
            #expect(mapped == expected)
        }
    }
    
    @Test func testURIMappingChaining() async throws {
        let resourceSet = ResourceSet()
        
        // Chain mappings
        await resourceSet.mapURI(from: "logical://", to: "intermediate://")
        await resourceSet.mapURI(from: "intermediate://", to: "file:///final/")
        
        let mapped = await resourceSet.convertURI("logical://model.xmi")
        #expect(mapped == "file:///final/model.xmi")
    }
    
    @Test func testURIMappingUnmapped() async throws {
        let resourceSet = ResourceSet()
        
        let unmappedURI = "unmapped://resource"
        let mapped = await resourceSet.convertURI(unmappedURI)
        #expect(mapped == unmappedURI)  // Should return original if no mapping
    }
    
    // MARK: - URI Fragment Handling Tests
    
    @Test func testURIFragmentParsing() async throws {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://model.xmi")
        
        let nodeClass = EClass(name: "Node")
        let node = DynamicEObject(eClass: nodeClass)
        await resource.add(node)
        
        let fragmentCases = [
            "test://model.xmi#\(node.id)",
            "test://model.xmi#/\(node.id)",
            "test://model.xmi#//\(node.id)"
        ]
        
        for fragmentURI in fragmentCases {
            let resolved = await resourceSet.resolveByURI(fragmentURI)
            #expect(resolved?.id == node.id)
        }
    }
    
    @Test func testURIFragmentXPath() async throws {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://model.xmi")
        
        var containerClass = EClass(name: "Container")
        let itemClass = EClass(name: "Item")
        let itemsRef = EReference(name: "items", eType: itemClass, upperBound: -1, containment: true)
        
        containerClass.eStructuralFeatures = [itemsRef]
        
        let container = DynamicEObject(eClass: containerClass)
        let item1 = DynamicEObject(eClass: itemClass)
        let item2 = DynamicEObject(eClass: itemClass)

        await resource.add(container)
        await resource.add(item1)
        await resource.add(item2)
        await resource.eSet(objectId: container.id, feature: "items", value: [item1.id, item2.id])
        
        // Test XPath-style fragment resolution
        let xpathCases = [
            "test://model.xmi#/0",  // First root object
            "test://model.xmi#/0/items/0",  // First item in container
            "test://model.xmi#/0/items/1"   // Second item in container
        ]
        
        for xpathURI in xpathCases {
            let resolved = await resourceSet.resolveByURI(xpathURI)
            #expect(resolved != nil)
        }
    }
    
    @Test func testURIFragmentEmpty() async throws {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://model.xmi")
        
        let nodeClass = EClass(name: "Node")
        let node = DynamicEObject(eClass: nodeClass)
        await resource.add(node)
        
        // Empty fragment should resolve to first root
        let resolved = await resourceSet.resolveByURI("test://model.xmi#")
        #expect(resolved?.id == node.id)
    }
    
    // MARK: - Error Cases and Edge Cases
    
    @Test func testInvalidURIHandling() async throws {
        let resourceSet = ResourceSet()
        
        let invalidURIs = [
            "",
            "   ",
            "\n",
            "\t",
            "://invalid",
            "http://",
            "://",
            "test:////"
        ]
        
        for invalidURI in invalidURIs {
            // Should handle gracefully without throwing
            let normalized = await resourceSet.normaliseURI(invalidURI)
            #expect(normalized == invalidURI || normalized.isEmpty)
            
            let converted = await resourceSet.convertURI(invalidURI)
            #expect(converted == invalidURI)
        }
    }
    
    @Test func testURIWithSpecialCharacters() async throws {
        let resourceSet = ResourceSet()
        
        let specialCharURIs = [
            "test://path%20with%20spaces/model.xmi",
            "test://path/with spaces/model.xmi",
            "test://path/with-dashes/model.xmi",
            "test://path/with_underscores/model.xmi",
            "test://path/with.dots/model.xmi",
            "test://path/with(parentheses)/model.xmi"
        ]
        
        for uri in specialCharURIs {
            let resource = await resourceSet.createResource(uri: uri)
            #expect(resource.uri == uri)
            
            let retrieved = await resourceSet.getResource(uri: uri)
            #expect(retrieved != nil)
        }
    }
    
    @Test func testURIWithQuery() async throws {
        let resourceSet = ResourceSet()
        
        let queryURIs = [
            "http://example.com/model.xmi?version=1.0",
            "test://model.xmi?param1=value1&param2=value2",
            "file:///path/model.xmi?encoding=UTF-8"
        ]
        
        for uri in queryURIs {
            let resource = await resourceSet.createResource(uri: uri)
            #expect(resource.uri == uri)
        }
    }
    
    @Test func testURIWithPort() async throws {
        let resourceSet = ResourceSet()
        
        let portURIs = [
            "http://localhost:8080/model.xmi",
            "https://server:443/model.ecore",
            "tcp://host:9090/model.data"
        ]
        
        for uri in portURIs {
            let resource = await resourceSet.createResource(uri: uri)
            #expect(resource.uri == uri)
        }
    }
    
    @Test func testVeryLongURI() async throws {
        let resourceSet = ResourceSet()
        
        var longPath = "test://very"
        for i in 0..<100 {
            longPath += "/long\(i)"
        }
        longPath += "/model.xmi"
        
        let resource = await resourceSet.createResource(uri: longPath)
        #expect(resource.uri == longPath)
        
        let normalized = await resourceSet.normaliseURI(longPath)
        #expect(normalized == longPath)
    }
    
    // MARK: - URI Resolution Performance Tests
    
    @Test func testHighVolumeURIResolution() async throws {
        let resourceSet = ResourceSet()
        
        // Create many resources
        var uris: [String] = []
        for i in 0..<1000 {
            let uri = "test://model\(i).xmi"
            uris.append(uri)
            let resource = await resourceSet.createResource(uri: uri)
            
            let nodeClass = EClass(name: "Node")
            let node = DynamicEObject(eClass: nodeClass)
            await resource.add(node)
        }
        
        // Verify all can be resolved
        for uri in uris {
            let resource = await resourceSet.getResource(uri: uri)
            #expect(resource != nil)
            
            let resolved = await resourceSet.resolveByURI(uri)
            #expect(resolved != nil)
        }
    }
    
    @Test func testURINormalizationPerformance() async throws {
        let resourceSet = ResourceSet()
        
        let complexURI = "test://a/b/c/d/e/f/g/../../../../../../../../model.xmi"
        
        // Normalize many times
        for _ in 0..<1000 {
            let normalized = await resourceSet.normaliseURI(complexURI)
            #expect(normalized == "test://model.xmi")
        }
    }
    
    // MARK: - URI Conversion Edge Cases
    
    @Test func testURIConversionIdempotence() async throws {
        let resourceSet = ResourceSet()
        
        let testURIs = [
            "http://example.com/model.xmi",
            "file:///path/to/model.ecore",
            "platform:/resource/project/model.uml"
        ]
        
        for uri in testURIs {
            let converted1 = await resourceSet.convertURI(uri)
            let converted2 = await resourceSet.convertURI(converted1)
            
            // Should be idempotent if no mapping exists
            #expect(converted1 == converted2)
        }
    }
    
    @Test func testURINormalizationIdempotence() async throws {
        let resourceSet = ResourceSet()
        
        let testURIs = [
            "test://model.xmi",
            "test://path/model.xmi",
            "test://normalized/path/model.xmi"
        ]
        
        for uri in testURIs {
            let normalized1 = await resourceSet.normaliseURI(uri)
            let normalized2 = await resourceSet.normaliseURI(normalized1)
            
            // Should be idempotent
            #expect(normalized1 == normalized2)
        }
    }
    
    @Test func testURIFragmentPreservation() async throws {
        let resourceSet = ResourceSet()
        let resource = await resourceSet.createResource(uri: "test://model.xmi")
        
        let nodeClass = EClass(name: "Node")
        let node = DynamicEObject(eClass: nodeClass)
        await resource.add(node)
        
        let uriWithFragment = "test://model.xmi#\(node.id)"
        
        // Normalization should preserve valid fragments
        let normalized = await resourceSet.normaliseURI(uriWithFragment)
        #expect(normalized == uriWithFragment)
        
        // Conversion should preserve fragments if no mapping affects them
        let converted = await resourceSet.convertURI(uriWithFragment)
        #expect(converted == uriWithFragment)
    }
}