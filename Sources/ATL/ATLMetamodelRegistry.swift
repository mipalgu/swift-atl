//
//  ATLMetamodelRegistry.swift
//  ATL
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import Foundation

/// A caller-supplied collection of metamodel packages that ATL modules can bind to.
///
/// The registry lets a host application provide packages that are not loaded
/// from files, such as built-in metamodels. A module binds to a registered
/// package with a `-- @nsURI Name=http://example.org/model` header comment, or
/// implicitly when the name used in the module header (for example `Ecore` in
/// `create OUT : GenModel from IN : Ecore`) matches the name of a registered
/// package and no `@path` or `@nsURI` directive names it.
///
/// Packages are found by namespace URI, by the packages' own names, and through
/// an optional resolver closure that is consulted last for namespace URIs.
///
/// ## Example Usage
///
/// ```swift
/// let registry = ATLMetamodelRegistry(packages: [ecorePackage, genModelPackage])
/// let module = try await ATLParser().parse(url, metamodelRegistry: registry)
/// ```
public struct ATLMetamodelRegistry: Sendable {

    /// A closure that finds a package for a namespace URI that is not registered directly.
    public typealias Resolver = @Sendable (_ nsURI: String) -> EPackage?

    /// The registry that holds no packages.
    public static let empty = ATLMetamodelRegistry()

    private var packagesByNamespaceURI: [String: EPackage] = [:]
    private var packagesByName: [String: EPackage] = [:]
    private let resolver: Resolver?

    /// Creates a registry from packages.
    ///
    /// Each package is registered under its namespace URI and its name.
    ///
    /// - Parameters:
    ///   - packages: The packages to register.
    ///   - resolver: A closure consulted for namespace URIs that are not registered.
    public init(packages: [EPackage] = [], resolver: Resolver? = nil) {
        self.resolver = resolver
        for package in packages {
            register(package)
        }
    }

    /// Creates a registry from a table of namespace URIs.
    ///
    /// - Parameters:
    ///   - packagesByNSURI: The packages by namespace URI.
    ///   - resolver: A closure consulted for namespace URIs that are not in the table.
    public init(packagesByNSURI: [String: EPackage], resolver: Resolver? = nil) {
        self.resolver = resolver
        for (nsURI, package) in packagesByNSURI {
            register(package, nsURI: nsURI)
        }
    }

    /// Registers a package under a namespace URI and under its name.
    ///
    /// - Parameters:
    ///   - package: The package to register.
    ///   - nsURI: The namespace URI to register it under; the package's own URI when `nil`.
    public mutating func register(_ package: EPackage, nsURI: String? = nil) {
        packagesByNamespaceURI[nsURI ?? package.nsURI] = package
        packagesByName[package.name] = package
    }

    /// Finds a package by namespace URI.
    ///
    /// - Parameter nsURI: The namespace URI.
    /// - Returns: The registered package, the resolver's answer, or `nil`.
    public func package(nsURI: String) -> EPackage? {
        packagesByNamespaceURI[nsURI] ?? resolver?(nsURI)
    }

    /// Finds a package by name.
    ///
    /// An exact match on the package name wins; otherwise a unique match that
    /// ignores letter case is accepted, so that the header name `GenModel`
    /// finds a package named `genmodel`.
    ///
    /// - Parameter name: The metamodel name.
    /// - Returns: The registered package, or `nil` when there is no unique match.
    public func package(named name: String) -> EPackage? {
        if let exact = packagesByName[name] { return exact }
        let matches = packagesByName.filter { $0.key.caseInsensitiveCompare(name) == .orderedSame }
        return matches.count == 1 ? matches.first?.value : nil
    }
}
