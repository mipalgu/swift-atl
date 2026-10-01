//
//  ATLEndToEndExecutionTests.swift
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

/// Runs a parsed ATL file over an XMI model and checks the serialised result.
///
/// The transformation under test lives in `Resources/Semantics`. It combines
/// rule inheritance, `using` variables, `do` blocks, implicit trace resolution
/// and a reference from the target model into the source model.
@Suite("ATL End-to-End Execution Tests")
@MainActor
struct ATLEndToEndExecutionTests {

    /// The directory holding the fixtures of this suite.
    private func fixtureURL(_ name: String) throws -> URL {
        let resources = try #require(Bundle.module.resourceURL)
        return resources.appendingPathComponent("Resources/Semantics/\(name)")
    }

    /// Runs the Families to Persons transformation and returns the target and its XMI text.
    private func transformFamilies() async throws -> (target: Resource, xml: String) {
        let module = try await ATLParser().parse(try fixtureURL("Families2Persons.atl"))

        let resourceSet = ResourceSet()
        let familiesPackage = try #require(module.sourceMetamodels["IN"])
        await resourceSet.registerMetamodel(familiesPackage, uri: familiesPackage.nsURI)
        let source = try await XMIParser(resourceSet: resourceSet).parse(
            try fixtureURL("Families.xmi"))

        let target = Resource(uri: "Persons.xmi")
        let vm = ATLVirtualMachine(module: module)
        try await vm.execute(sources: ["IN": source], targets: ["OUT": target])

        let xml = try await XMISerializer().serialize(target)
        return (target, xml)
    }

    @Test("Parsed module carries inheritance, using and do sections")
    func parsedModuleStructure() async throws {
        let module = try await ATLParser().parse(try fixtureURL("Families2Persons.atl"))
        let base = try #require(module.matchedRules.first { $0.name == "Member2Person" })
        let male = try #require(module.matchedRules.first { $0.name == "Member2Male" })
        #expect(base.isAbstract)
        #expect(base.localVariables.map(\.name) == ["fullName"])
        #expect(male.superRuleName == "Member2Person")
        #expect(male.doStatements.count == 1)
    }

    @Test("Transformation creates one person per member with inherited bindings")
    func createsPersons() async throws {
        let (target, _) = try await transformFamilies()
        let persons = await target.getAllObjects().compactMap { $0 as? DynamicEObject }
            .filter { ($0.eClass.name == "Male") || ($0.eClass.name == "Female") }
        #expect(persons.count == 3)

        let names = persons.compactMap { $0.eGet("fullName") as? String }
        #expect(Set(names) == ["Jim March", "Cindy March", "Peter Sailor"])

        let jim = try #require(persons.first { $0.eGet("fullName") as? String == "Jim March" })
        #expect(jim.eClass.name == "Male")
        #expect(jim.eGet("label") as? String == "male")
        #expect(jim.eGet("age") as? Int == 45)
    }

    @Test("Spouse references resolve to the transformed persons")
    func resolvesSpouses() async throws {
        let (target, _) = try await transformFamilies()
        let persons = await target.getAllObjects().compactMap { $0 as? DynamicEObject }
        let jim = try #require(persons.first { $0.eGet("fullName") as? String == "Jim March" })
        let cindy = try #require(persons.first { $0.eGet("fullName") as? String == "Cindy March" })
        #expect(jim.eGet("partner") as? EUUID == cindy.id)
        #expect(cindy.eGet("partner") as? EUUID == jim.id)
    }

    @Test("Untransformed source elements stay cross-document references")
    func keepsFamilyReferences() async throws {
        let (target, xml) = try await transformFamilies()
        let persons = await target.getAllObjects().compactMap { $0 as? DynamicEObject }
        let jim = try #require(persons.first { $0.eGet("fullName") as? String == "Jim March" })
        let proxy = try #require(jim.eGet("family") as? ResourceProxy)
        #expect(proxy.fragment == "//@families.0")
        #expect(xml.contains("<family href=\"\(proxy.uri)#//@families.0\"/>"))
        #expect(xml.contains("<family href=\"\(proxy.uri)#//@families.1\"/>"))
    }

    @Test("Serialised target holds the persons inside the register")
    func serialisedStructure() async throws {
        let (target, xml) = try await transformFamilies()
        #expect(await target.getRootObjects().count == 1)
        #expect(xml.contains("fullName=\"Jim March\""))
        #expect(xml.contains("label=\"female\""))
        #expect(xml.contains("<partner href=\"#//@persons."))
    }
}
