//
//  ATLGenModelFindingsTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 1/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import OrderedCollections
import Testing

@testable import ATL

/// Tests for nested conditionals, references to native Ecore elements, many-valued
/// attribute storage and enumeration literal text.
@Suite("ATL Transformation Fidelity Tests")
@MainActor
struct ATLGenModelFindingsTests {

    private let fixture = ShapeFixture()

    // MARK: - Nested conditionals

    private func radii(_ expression: String, helper: String = "", names: [String]) async throws
        -> [Double]
    {
        let source = """
            module Shapes2Shapes;
            create OUT : Shapes from IN : Shapes;
            \(helper)
            rule Circle2Circle {
                from s : Shapes!Circle
                to t : Shapes!Circle (
                    name <- s.name,
                    radius <- \(expression)
                )
            }
            """
        let registry = ATLMetamodelRegistry(packages: [fixture.package])
        let module = try await ATLParser().parseContent(source, metamodelRegistry: registry)
        let input = Resource(uri: "test://in")
        for name in names { await input.add(fixture.make(fixture.circle, ["name": name])) }
        let output = Resource(uri: "test://out")
        try await ATLVirtualMachine(module: module).execute(
            sources: ["IN": input], targets: ["OUT": output])
        let created = await output.getAllInstancesOf(fixture.circle)
        let byName = Dictionary(
            uniqueKeysWithValues: created.compactMap { object -> (String, Double)? in
                guard let circle = object as? DynamicEObject,
                    let name = circle.eGet("name") as? String,
                    let radius = circle.eGet("radius") as? Double
                else { return nil }
                return (name, radius)
            })
        return names.compactMap { byName[$0] }
    }

    @Test("A conditional nested in an else branch with its own endif parses in a binding")
    func nestedConditionalInBinding() async throws {
        let result = try await radii(
            "if s.name = 'a' then 1 else if s.name = 'b' then 2 else 3 endif endif",
            names: ["a", "b", "c"])
        #expect(result == [1, 2, 3])
    }

    @Test("An else if chain sharing one endif still parses")
    func elseIfChainWithSingleEndif() async throws {
        let result = try await radii(
            "if s.name = 'a' then 1 else if s.name = 'b' then 2 else 3 endif",
            names: ["a", "b", "c"])
        #expect(result == [1, 2, 3])
    }

    @Test("Nested conditionals in the then branch and the else branch both parse")
    func nestedInBothBranches() async throws {
        let result = try await radii(
            """
            if s.name = 'a' then
                (if s.name = 'a' then 10 else 11 endif)
            else
                if s.name = 'b' then 20 else if s.name = 'c' then 30 else 40 endif endif
            endif
            """,
            names: ["a", "b", "c", "d"])
        #expect(result == [10, 20, 30, 40])
    }

    @Test("A conditional followed by more of the binding list parses")
    func nestedConditionalBeforeNextBinding() async throws {
        let source = """
            module Shapes2Shapes;
            create OUT : Shapes from IN : Shapes;
            rule Circle2Circle {
                from s : Shapes!Circle
                to t : Shapes!Circle (
                    radius <- if s.name = 'a' then 1 else if s.name = 'b' then 2 else 3 endif endif,
                    name <- s.name
                )
            }
            """
        let registry = ATLMetamodelRegistry(packages: [fixture.package])
        let module = try await ATLParser().parseContent(source, metamodelRegistry: registry)
        #expect(module.matchedRules.count == 1)
    }

    @Test("A nested conditional in an else branch parses in a helper")
    func nestedConditionalInHelper() async throws {
        let helper = """
            helper context Shapes!Circle def : size() : Real =
                if self.name = 'a' then 1.0 else if self.name = 'b' then 2.0 else 3.0 endif endif;
            """
        let result = try await radii("s.size()", helper: helper, names: ["a", "b", "c"])
        #expect(result == [1, 2, 3])
    }

    @Test("A nested conditional parses inside a let expression and a collection")
    func nestedConditionalInNestedContexts() async throws {
        let result = try await radii(
            """
            let base : Real = 1.0 in
                Sequence{
                    if s.name = 'a' then base else if s.name = 'b' then base + 1 else base + 2 endif endif
                }->first()
            """,
            names: ["a", "b", "c"])
        #expect(result == [1, 2, 3])
    }

    @Test("A conditional without endif is an error")
    func missingEndif() async throws {
        let source = """
            module Shapes2Shapes;
            create OUT : Shapes from IN : Shapes;
            rule Circle2Circle {
                from s : Shapes!Circle
                to t : Shapes!Circle ( radius <- if s.name = 'a' then 1 else 2 )
            }
            """
        let registry = ATLMetamodelRegistry(packages: [fixture.package])
        await #expect(throws: (any Error).self) {
            _ = try await ATLParser().parseContent(source, metamodelRegistry: registry)
        }
    }

    // MARK: - References to native Ecore elements

    private static let libraryEcore = """
        <?xml version="1.0" encoding="UTF-8"?>
        <ecore:EPackage xmi:version="2.0" xmlns:xmi="http://www.omg.org/XMI"
            xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
            xmlns:ecore="http://www.eclipse.org/emf/2002/Ecore" name="lib"
            nsURI="http://example.org/lib" nsPrefix="lib">
          <eClassifiers xsi:type="ecore:EClass" name="Book">
            <eStructuralFeatures xsi:type="ecore:EAttribute" name="title"
                eType="ecore:EDataType http://www.eclipse.org/emf/2002/Ecore#//EString"/>
          </eClassifiers>
          <eClassifiers xsi:type="ecore:EClass" name="Writer"/>
        </ecore:EPackage>
        """

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "atl-fidelity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func bindingPackage() -> (EPackage, EClass) {
        let holder = EClass(
            name: "Holder",
            eStructuralFeatures: [
                EReference(name: "ecoreClass", eType: EcorePackage.metaClass(.eClass)),
                EReference(
                    name: "ecoreClasses", eType: EcorePackage.metaClass(.eClass), upperBound: -1),
                EAttribute(name: "label", eType: EDataType(name: "EString")),
            ])
        let package = EPackage(
            name: "holders", nsURI: "http://example.org/holders", nsPrefix: "hld",
            eClassifiers: [holder])
        return (package, holder)
    }

    private func transformEcore(
        directory: URL, targetInSameSet: Bool
    ) async throws -> String {
        let libraryURL = directory.appendingPathComponent("lib.ecore")
        try Self.libraryEcore.write(to: libraryURL, atomically: true, encoding: .utf8)
        let set = ResourceSet()
        let source = try await set.loadEcoreResource(uri: libraryURL.absoluteString)

        let (package, _) = bindingPackage()
        let registry = ATLMetamodelRegistry(packages: [EcorePackage.instance, package])
        let module = try await ATLParser().parseContent(
            """
            module Ecore2Holder;
            create OUT : holders from IN : ecore;
            rule Package2Holder {
                from p : ecore!EPackage
                to h : holders!Holder (
                    label <- p.name,
                    ecoreClass <- p.eClassifiers->first(),
                    ecoreClasses <- p.eClassifiers
                )
            }
            """, metamodelRegistry: registry)

        let targetURL = directory.appendingPathComponent("out.xmi")
        let targetSet = targetInSameSet ? set : ResourceSet()
        await targetSet.registerMetamodel(package, uri: package.nsURI)
        let target = await targetSet.createResource(uri: targetURL.absoluteString)
        try await ATLVirtualMachine(module: module).execute(
            sources: ["IN": source], targets: ["OUT": target])
        defer { withExtendedLifetime(targetSet) {} }
        return try await XMISerializer(options: .emf).serialize(target)
    }

    @Test("References to native Ecore classes in the same resource set serialise by name")
    func nativeReferencesInSameResourceSet() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let xml = try await transformEcore(directory: directory, targetInSameSet: true)
        #expect(xml.contains("ecoreClass=\"lib.ecore#//Book\""))
        #expect(xml.contains("ecoreClasses=\"lib.ecore#//Book lib.ecore#//Writer\""))
    }

    @Test("References to native Ecore classes in another resource set carry name fragments")
    func nativeReferencesInOtherResourceSet() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let xml = try await transformEcore(directory: directory, targetInSameSet: false)
        #expect(xml.contains("ecoreClass=\"lib.ecore#//Book\""))
        #expect(xml.contains("ecoreClasses=\"lib.ecore#//Book lib.ecore#//Writer\""))
    }

    @Test("The fragment of a native Ecore element is its name-based path")
    func nativeFragment() async throws {
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let libraryURL = directory.appendingPathComponent("lib.ecore")
        try Self.libraryEcore.write(to: libraryURL, atomically: true, encoding: .utf8)
        let set = ResourceSet()
        let resource = try await set.loadEcoreResource(uri: libraryURL.absoluteString)
        let package = try #require(await resource.getRootObjects().first as? EPackage)
        let book = try #require(package.getEClass("Book"))
        let title = try #require(book.getEAttribute(name: "title"))
        #expect(await ATLReferenceStorage.fragment(for: package, in: resource) == "/")
        #expect(await ATLReferenceStorage.fragment(for: book, in: resource) == "//Book")
        #expect(await ATLReferenceStorage.fragment(for: title, in: resource) == "//Book/title")
    }

    // MARK: - Many-valued attributes

    private func namesPackage() -> (EPackage, EClass) {
        let string = EDataType(name: "EString")
        let int = EDataType(name: "EInt")
        let bool = EDataType(name: "EBoolean")
        let double = EDataType(name: "EDouble")
        let holder = EClass(
            name: "Names",
            eStructuralFeatures: [
                EAttribute(name: "foreignModel", eType: string, upperBound: -1),
                EAttribute(name: "counts", eType: int, upperBound: -1),
                EAttribute(name: "flags", eType: bool, upperBound: -1),
                EAttribute(name: "weights", eType: double, upperBound: -1),
            ])
        let package = EPackage(
            name: "names", nsURI: "http://example.org/names", nsPrefix: "nms",
            eClassifiers: [holder])
        return (package, holder)
    }

    private func runNames(_ bindings: String) async throws -> (ResourceSet, Resource, EPackage, EClass) {
        let (package, holder) = namesPackage()
        let registry = ATLMetamodelRegistry(packages: [fixture.package, package])
        let module = try await ATLParser().parseContent(
            """
            module Shapes2Names;
            create OUT : names from IN : Shapes;
            rule Circle2Names {
                from s : Shapes!Circle
                to n : names!Names ( \(bindings) )
            }
            """, metamodelRegistry: registry)
        let input = Resource(uri: "test://in")
        await input.add(fixture.make(fixture.circle, ["name": "c"]))
        let outputSet = ResourceSet()
        await outputSet.registerMetamodel(package, uri: package.nsURI)
        let output = await outputSet.createResource(uri: "test://out")
        try await ATLVirtualMachine(module: module).execute(
            sources: ["IN": input], targets: ["OUT": output])
        return (outputSet, output, package, holder)
    }

    @Test("Many-valued attributes are stored as typed arrays")
    func typedArrays() async throws {
        let (_, output, _, holder) = try await runNames(
            """
            foreignModel <- Sequence{'a.ecore', 'b.ecore'},
            counts <- Sequence{1, 2},
            flags <- Sequence{true, false},
            weights <- Sequence{1, 2.5}
            """)
        let created = try #require(await output.getAllInstancesOf(holder).first as? DynamicEObject)
        #expect(created.eGet("foreignModel") as? [String] == ["a.ecore", "b.ecore"])
        #expect(created.eGet("counts") as? [Int] == [1, 2])
        #expect(created.eGet("flags") as? [Bool] == [true, false])
        #expect(created.eGet("weights") as? [Double] == [1.0, 2.5])
    }

    @Test("A single value bound to a many-valued attribute becomes a one-element array")
    func singleValueToManyValued() async throws {
        let (_, output, _, holder) = try await runNames("foreignModel <- 'a.ecore'")
        let created = try #require(await output.getAllInstancesOf(holder).first as? DynamicEObject)
        #expect(created.eGet("foreignModel") as? [String] == ["a.ecore"])
    }

    @Test("An empty collection bound to a many-valued attribute takes the attribute type")
    func emptyManyValued() async throws {
        let (_, output, _, holder) = try await runNames(
            "counts <- Sequence{}, flags <- Sequence{}, weights <- Sequence{}, foreignModel <- Sequence{}")
        let created = try #require(await output.getAllInstancesOf(holder).first as? DynamicEObject)
        #expect(created.eGet("counts") as? [Int] == [])
        #expect(created.eGet("flags") as? [Bool] == [])
        #expect(created.eGet("weights") as? [Double] == [])
        #expect(created.eGet("foreignModel") as? [String] == [])
    }

    @Test("Many-valued attributes round trip through the serialiser")
    func manyValuedRoundTrip() async throws {
        let (outputSet, output, package, holder) = try await runNames(
            "foreignModel <- Sequence{'a.ecore', 'b.ecore'}, counts <- Sequence{3, 4}")
        defer { withExtendedLifetime(outputSet) {} }
        let xml = try await XMISerializer(options: .emf).serialize(output)
        #expect(xml.contains("<foreignModel>a.ecore</foreignModel>"))
        #expect(xml.contains("<foreignModel>b.ecore</foreignModel>"))
        #expect(xml.contains("<counts>3</counts>"))
        #expect(!xml.contains("EcoreValueArray"))

        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "names-\(UUID().uuidString).xmi")
        try xml.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }
        let resourceSet = ResourceSet()
        await resourceSet.registerMetamodel(package, uri: "http://example.org/names")
        let loaded = try await XMIParser(resourceSet: resourceSet).parse(url)
        let root = try #require(await loaded.getRootObjects().first as? DynamicEObject)
        #expect(root.eGet("foreignModel") as? [String] == ["a.ecore", "b.ecore"])
        #expect(root.eGet("counts") as? [Int] == [3, 4])
        _ = holder
    }

    // MARK: - Enumeration literal text

    private func jdkFixture() -> (EEnum, EAttribute) {
        let level = EEnum(
            name: "JDKLevel",
            literals: [
                EEnumLiteral(name: "JDK150", value: 0, literal: "5.0"),
                EEnumLiteral(name: "JDK170", value: 1, literal: "17.0"),
            ])
        return (level, EAttribute(name: "level", eType: level))
    }

    @Test("A string matching a literal's text selects that literal")
    func literalText() throws {
        let (level, attribute) = jdkFixture()
        #expect(try ATLValueConversion.prepare("17.0", for: attribute) as? String == "JDK170")
        #expect(try ATLValueConversion.prepare("JDK150", for: attribute) as? String == "JDK150")
        #expect(try ATLValueConversion.prepare(0, for: attribute) as? String == "JDK150")
        #expect(throws: ATLExecutionError.self) {
            _ = try ATLValueConversion.prepare("18.0", for: attribute)
        }
        _ = level
    }

    @Test("Literal text is matched for every element of a many-valued enumeration attribute")
    func literalTextManyValued() throws {
        let (level, _) = jdkFixture()
        let many = EAttribute(name: "levels", eType: level, upperBound: -1)
        let converted = try ATLValueConversion.prepare(
            ATLCollectionValue(kind: .sequence, values: ["5.0", "JDK170"]), for: many)
        #expect(
            (converted as? EcoreValueArray)?.values.compactMap { $0 as? String }
                == ["JDK150", "JDK170"])
    }

    @Test("A literal's text can be bound in a rule")
    func literalTextInRule() async throws {
        let (level, _) = jdkFixture()
        let holder = EClass(
            name: "Settings", eStructuralFeatures: [EAttribute(name: "level", eType: level)])
        let package = EPackage(
            name: "settings", nsURI: "http://example.org/settings", nsPrefix: "set",
            eClassifiers: [level, holder])
        let registry = ATLMetamodelRegistry(packages: [fixture.package, package])
        let module = try await ATLParser().parseContent(
            """
            module Shapes2Settings;
            create OUT : settings from IN : Shapes;
            rule Circle2Settings {
                from s : Shapes!Circle
                to t : settings!Settings ( level <- '17.0' )
            }
            """, metamodelRegistry: registry)
        let input = Resource(uri: "test://in")
        await input.add(fixture.make(fixture.circle, ["name": "c"]))
        let output = Resource(uri: "test://out")
        try await ATLVirtualMachine(module: module).execute(
            sources: ["IN": input], targets: ["OUT": output])
        let created = try #require(await output.getAllInstancesOf(holder).first as? DynamicEObject)
        #expect(created.eGet("level") as? String == "JDK170")
    }
}
