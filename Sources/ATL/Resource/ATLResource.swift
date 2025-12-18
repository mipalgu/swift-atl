//
//  ATLResource.swift
//  ATL
//
//  Created by Claude on 10/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
//  ATL-specific resource for managing ATL modules with XMI serialization.
//
import ECore
import EMFBase
import Foundation

/// A resource for managing ATL modules with XMI serialization support.
///
/// `ATLResource` provides a container for ATL modules that integrates with the
/// ECore resource framework. It enables loading and saving ATL modules in Eclipse
/// ATL XMI format, supporting full roundtrip serialization.
///
/// ## Overview
///
/// ATL resources manage:
/// - **ATL Modules**: The transformation specification including rules, helpers, and queries
/// - **Metamodel References**: References to source and target metamodels (EPackages)
/// - **XMI Serialization**: Proper Eclipse ATL XMI format compliance
///
/// ## Architecture
///
/// ATLResource composes an ECore `Resource` actor for managing metamodel references
/// while providing MainActor-isolated access to the ATL module. This design allows:
/// - Thread-safe metamodel management through the Resource actor
/// - Main-thread coordination for ATL module access
/// - Integration with ECore ResourceSet for cross-resource references
///
/// ## Example Usage
///
/// ```swift
/// // Create a resource for an ATL module
/// let resource = ATLResource(uri: "file:///transformations/Book2Publication.atl")
///
/// // Load from XMI
/// try await resource.load()
/// if let module = resource.module {
///     print("Loaded module: \(module.name)")
/// }
///
/// // Save to XMI
/// try await resource.save()
/// ```
@MainActor
public final class ATLResource {

    // MARK: - Properties

    /// The URI identifying this resource.
    ///
    /// The URI typically indicates the location of the ATL file and follows
    /// standard URI conventions (file://, http://, etc.).
    public let uri: String

    /// The ATL module contained in this resource.
    ///
    /// This is the main transformation specification parsed from the ATL file
    /// or loaded from XMI format.
    public var module: ATLModule?

    /// The underlying ECore resource for managing metamodel references.
    ///
    /// This resource actor holds EPackage objects for source and target metamodels
    /// that the ATL module references.
    public let ecoreResource: Resource

    /// The resource set that owns this resource, if any.
    ///
    /// When part of a resource set, this resource can resolve cross-resource
    /// references to metamodel elements.
    public weak var resourceSet: ResourceSet?

    // MARK: - Initialisation

    /// Creates a new ATL resource with the specified URI.
    ///
    /// - Parameter uri: The URI identifying this resource
    public init(uri: String) {
        self.uri = uri
        self.ecoreResource = Resource(uri: uri)
    }

    /// Creates a new ATL resource with an ATL module.
    ///
    /// - Parameters:
    ///   - uri: The URI identifying this resource
    ///   - module: The ATL module to store in this resource
    public init(uri: String, module: ATLModule) {
        self.uri = uri
        self.module = module
        self.ecoreResource = Resource(uri: uri)
    }

    // MARK: - Resource Management

    /// Sets the resource set that owns this resource.
    ///
    /// This allows the resource to participate in cross-resource reference
    /// resolution through the resource set.
    ///
    /// - Parameter resourceSet: The resource set to associate with this resource
    public func setResourceSet(_ resourceSet: ResourceSet?) async {
        self.resourceSet = resourceSet
        await ecoreResource.setResourceSet(resourceSet)
    }

    /// Loads the ATL module from its URI.
    ///
    /// This method determines the format based on the file extension:
    /// - `.atl`: Parses as ATL text format
    /// - `.xmi`: Parses as Eclipse ATL XMI format
    ///
    /// - Throws: `ATLResourceError` if loading fails
    public func load() async throws {
        // Determine format from URI
        if uri.hasSuffix(".xmi") {
            try await loadFromXMI()
        } else if uri.hasSuffix(".atl") {
            try await loadFromATL()
        } else {
            throw ATLResourceError.unsupportedFormat("Unknown file extension for URI: \(uri)")
        }
    }

    /// Saves the ATL module to its URI.
    ///
    /// The format is determined by the file extension:
    /// - `.atl`: Not supported for saving (ATL text format is input-only)
    /// - `.xmi`: Saves as Eclipse ATL XMI format
    ///
    /// - Throws: `ATLResourceError` if saving fails or module is nil
    public func save() async throws {
        guard let module = module else {
            throw ATLResourceError.noModule("Cannot save: no module loaded")
        }

        // Determine format from URI
        if uri.hasSuffix(".xmi") {
            try await saveAsXMI(module)
        } else if uri.hasSuffix(".atl") {
            throw ATLResourceError.unsupportedFormat("Saving to .atl format is not supported (read-only format)")
        } else {
            throw ATLResourceError.unsupportedFormat("Unknown file extension for URI: \(uri)")
        }
    }

    // MARK: - Private Loading Methods

    /// Loads the ATL module from ATL text format.
    private func loadFromATL() async throws {
        guard let url = URL(string: uri), url.isFileURL else {
            throw ATLResourceError.invalidURI("Not a valid file URI: \(uri)")
        }

        let parser = ATLParser()
        self.module = try await parser.parse(url)
    }

    /// Loads the ATL module from Eclipse ATL XMI format.
    private func loadFromXMI() async throws {
        guard let url = URL(string: uri), url.isFileURL else {
            throw ATLResourceError.invalidURI("Not a valid file URI: \(uri)")
        }

        let xmiText = try String(contentsOf: url, encoding: .utf8)
        let xmiParser = ATLXMIParser()
        self.module = try xmiParser.parse(xmiText)
    }

    // MARK: - Private Saving Methods

    /// Saves the ATL module as Eclipse ATL XMI format.
    private func saveAsXMI(_ module: ATLModule) async throws {
        guard let url = URL(string: uri), url.isFileURL else {
            throw ATLResourceError.invalidURI("Not a valid file URI: \(uri)")
        }

        let serializer = ATLXMISerializer()
        let xmiText = try serializer.serialize(module)
        try xmiText.write(to: url, atomically: true, encoding: .utf8)
    }
}

// MARK: - ATL Resource Errors

/// Errors that can occur during ATL resource operations.
public enum ATLResourceError: Error, LocalizedError {
    case invalidURI(String)
    case unsupportedFormat(String)
    case noModule(String)
    case serializationError(String)
    case parsingError(String)

    public var errorDescription: String? {
        switch self {
        case .invalidURI(let message):
            return "Invalid URI: \(message)"
        case .unsupportedFormat(let message):
            return "Unsupported format: \(message)"
        case .noModule(let message):
            return "No module: \(message)"
        case .serializationError(let message):
            return "Serialization error: \(message)"
        case .parsingError(let message):
            return "Parsing error: \(message)"
        }
    }
}
