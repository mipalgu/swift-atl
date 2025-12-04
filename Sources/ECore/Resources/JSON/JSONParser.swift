//
// JSONParser.swift
// ECore
//
//  Created by Rene Hexel on 4/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import Foundation

/// Parser for JSON files in emfjson/pyecore format
///
/// The JSON parser converts JSON files into EMF-compatible object graphs stored in Resources.
/// It handles:
/// - Single root objects and arrays of root objects
/// - Nested containment references
/// - Cross-references (using $ref)
/// - Type information via eClass field
/// - Compatible with pyecore and emfjson-jackson formats
///
/// ## JSON Format
///
/// Single root object:
/// ```json
/// {
///   "eClass": "http://package.uri#//ClassName",
///   "attribute": "value",
///   "reference": { ... }
/// }
/// ```
///
/// Multiple root objects:
/// ```json
/// [
///   { "eClass": "...", ... },
///   { "eClass": "...", ... }
/// ]
/// ```
///
/// ## Usage Example
///
/// ```swift
/// let parser = JSONParser()
/// let resource = try await parser.parse(jsonURL)
/// let roots = await resource.getRootObjects()
/// ```
public actor JSONParser {
    private let resourceSet: ResourceSet?

    /// Initializes a new JSON parser
    ///
    /// - Parameter resourceSet: Optional ResourceSet for cross-resource reference resolution
    public init(resourceSet: ResourceSet? = nil) {
        self.resourceSet = resourceSet
    }

    /// Parse a JSON file and return a Resource containing the objects
    /// - Parameter url: The URL of the JSON file to parse
    /// - Returns: A Resource containing the parsed objects
    /// - Throws: JSONError or DecodingError if parsing fails
    public func parse(_ url: URL) async throws -> Resource {
        let data = try Data(contentsOf: url)

        // Create resource via ResourceSet if available, otherwise create directly
        let resource: Resource
        if let resourceSet = resourceSet {
            resource = await resourceSet.createResource(uri: url.absoluteString)
        } else {
            resource = Resource(uri: url.absoluteString)
        }

        // Try to decode as array first, then fall back to single object
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        // Check if JSON is an array or single object
        let json = try JSONSerialization.jsonObject(with: data, options: [])

        if let jsonArray = json as? [[String: Any]] {
            // Multiple root objects
            for jsonObject in jsonArray {
                let objectData = try JSONSerialization.data(withJSONObject: jsonObject, options: [])
                let dynamicObject = try await parseSingleObject(from: objectData, decoder: decoder, in: resource)
                await resource.add(dynamicObject)
            }
        } else {
            // Single root object
            let dynamicObject = try await parseSingleObject(from: data, decoder: decoder, in: resource)
            await resource.add(dynamicObject)
        }

        return resource
    }

    /// Parse a single JSON object into a DynamicEObject
    private func parseSingleObject(from data: Data, decoder: JSONDecoder, in resource: Resource) async throws -> DynamicEObject {
        // Extract eClass to determine metamodel
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let jsonDict = json as? [String: Any] else {
            throw JSONError.invalidFormat("JSON must be an object with eClass field")
        }

        guard let eClassString = jsonDict["eClass"] as? String else {
            throw JSONError.missingEClass
        }

        // Create a dynamic EClass from the eClass URI
        // For now, we create a minimal EClass; in the future, this should look up the metamodel
        let eClass = DynamicEObject.createDynamicEClass(from: eClassString, jsonDict: jsonDict)

        // Set up decoder with EClass context
        decoder.userInfo[.eClassKey] = eClass

        // Decode the DynamicEObject
        let dynamicObject = try decoder.decode(DynamicEObject.self, from: data)

        return dynamicObject
    }
}

/// Errors that can occur during JSON parsing
public enum JSONError: Error, Sendable {
    case invalidFormat(String)
    case missingEClass
    case parseError(String)
}
