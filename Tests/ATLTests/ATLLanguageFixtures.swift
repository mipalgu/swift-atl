//
//  ATLLanguageFixtures.swift
//  ATLTests
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import OrderedCollections
import Testing

@testable import ATL

/// A small metamodel with inheritance, an enumeration and a containment reference.
///
/// `Shape` is the abstract root with a name and a visibility. `Circle` and `Square`
/// extend it, and `LabelledCircle` extends `Circle`, which gives a three-level chain.
/// `Drawing` contains shapes.
struct ShapeFixture {
    static let namespaceURI = "http://example.org/shapes"
    static let metamodelName = "Shapes"

    let package: EPackage
    let visibility: EEnum
    let shape: EClass
    let circle: EClass
    let labelledCircle: EClass
    let square: EClass
    let drawing: EClass

    init() {
        let string = EDataType(name: "EString")
        let double = EDataType(name: "EDouble")
        let visibility = EEnum(
            name: "Visibility",
            literals: [
                EEnumLiteral(name: "Public", value: 0),
                EEnumLiteral(name: "Private", value: 1),
            ])
        let shape = EClass(
            name: "Shape", isAbstract: true,
            eStructuralFeatures: [
                EAttribute(name: "name", eType: string),
                EAttribute(name: "visibility", eType: visibility),
            ])
        let circle = EClass(
            name: "Circle", eSuperTypes: [shape],
            eStructuralFeatures: [EAttribute(name: "radius", eType: double)])
        let labelledCircle = EClass(name: "LabelledCircle", eSuperTypes: [circle])
        let square = EClass(
            name: "Square", eSuperTypes: [shape],
            eStructuralFeatures: [EAttribute(name: "side", eType: double)])
        let drawing = EClass(
            name: "Drawing",
            eStructuralFeatures: [
                EAttribute(name: "title", eType: string),
                EReference(name: "shapes", eType: shape, upperBound: -1, containment: true),
            ])

        self.visibility = visibility
        self.shape = shape
        self.circle = circle
        self.labelledCircle = labelledCircle
        self.square = square
        self.drawing = drawing
        self.package = EPackage(
            name: Self.metamodelName, nsURI: Self.namespaceURI, nsPrefix: "shp",
            eClassifiers: [visibility, shape, circle, labelledCircle, square, drawing])
    }

    /// Creates an instance of a class with attribute values.
    func make(_ eClass: EClass, _ values: [String: any EcoreValue] = [:]) -> DynamicEObject {
        var object = DynamicEObject(eClass: eClass)
        for (name, value) in values {
            object.eSet(name, value: value)
        }
        return object
    }
}

/// Parses ATL source and evaluates expressions in the resulting module.
@MainActor
struct LanguageHarness {
    let module: ATLModule
    let context: ATLExecutionContext

    /// The name of the probe helper that wraps evaluated expressions.
    static let probeName = "probe"

    /// Creates a harness for a module with the standard shape header.
    ///
    /// - Parameters:
    ///   - declarations: Helper and rule declarations that follow the module header.
    ///   - expression: The expression the probe helper evaluates.
    ///   - fixture: The metamodel bound to both the source and the target model.
    ///   - sources: Source models by alias.
    ///   - directives: Header comment directives placed before the module.
    static func make(
        declarations: String = "",
        expression: String = "OclUndefined",
        fixture: ShapeFixture = ShapeFixture(),
        sources: OrderedDictionary<String, Resource> = [:],
        directives: String = ""
    ) async throws -> LanguageHarness {
        let source = """
            \(directives)
            module Probe;
            create OUT : \(ShapeFixture.metamodelName) from IN : \(ShapeFixture.metamodelName);
            \(declarations)
            helper def : \(probeName)() : OclAny = \(expression);
            """
        let registry = ATLMetamodelRegistry(packages: [fixture.package])
        let module = try await ATLParser().parseContent(source, metamodelRegistry: registry)
        let context = ATLExecutionContext(
            module: module, sources: sources, targets: [:],
            executionEngine: ECoreExecutionEngine(models: [:]))
        return LanguageHarness(module: module, context: context)
    }

    /// Evaluates an expression in a module with the given declarations.
    @discardableResult
    static func evaluate(
        _ expression: String,
        declarations: String = "",
        fixture: ShapeFixture = ShapeFixture(),
        sources: OrderedDictionary<String, Resource> = [:]
    ) async throws -> (any EcoreValue)? {
        let harness = try await make(
            declarations: declarations, expression: expression, fixture: fixture, sources: sources)
        return try await harness.context.callHelper(probeName, arguments: [])
    }
}

/// Collection helpers for assertions.
extension Optional where Wrapped == any EcoreValue {
    /// The elements of a collection result, or `nil` when the result is not a collection.
    var collectionElements: [any EcoreValue]? {
        guard ATLCollections.isCollection(self) else { return nil }
        return ATLCollections.elements(of: self)
    }

    /// The elements of a collection result as strings.
    var strings: [String]? { collectionElements?.compactMap { $0 as? String } }

    /// The elements of a collection result as integers.
    var integers: [Int]? { collectionElements?.compactMap { $0 as? Int } }
}
