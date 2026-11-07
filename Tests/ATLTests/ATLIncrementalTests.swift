//
//  ATLIncrementalTests.swift
//  ATLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import OrderedCollections
import Testing

@testable import ATL

@Suite("ATL incremental transformation")
@MainActor
struct ATLIncrementalTests {

    private static let familyTarget = "memory:/register.xmi"
    private static let classTarget = "memory:/schema.xmi"

    // MARK: - First execution

    @Test("the first execution gives the target model of a batch execution")
    func firstExecution() async throws {
        let world = try await FamilyWorld(families: 3, membersPerFamily: 4, seed: 1)
        let module = try await world.module
        let target = Resource(uri: Self.familyTarget)
        let transformation = ATLIncrementalTransformation(module: module, options: .standard)
        #expect(transformation.strategy == .propagation)
        #expect(transformation.hasExecuted == false)
        try await transformation.execute(sources: ["IN": world.resource], targets: ["OUT": target])
        #expect(transformation.hasExecuted && transformation.isObserving)
        #expect(transformation.matchCount == 13)
        let sizes = transformation.dependencyStatistics
        #expect(sizes.matches == 13 && sizes.candidates == 1 + 12 + 12)
        #expect(sizes.bindings == 1 + 12 * 3)
        #expect(sizes.guards == 24 && sizes.locals == 0 && sizes.helpers == 24)
        #expect(sizes.totalEntries == sizes.guardEntries + sizes.bindingEntries + sizes.helperEntries)
        #expect(sizes.totalEntries > sizes.bindings)
        #expect(transformation.statistics.successful)
        let expected = try await batchXMI(module: module, source: world.resource, targetURI: Self.familyTarget)
        #expect(try await XMISerializer().serialize(target) == expected)
    }

    @Test("an update before the first execution is rejected and an empty update does nothing")
    func updateBeforeExecution() async throws {
        let world = try await FamilyWorld(families: 1, membersPerFamily: 1, seed: 1)
        let transformation = ATLIncrementalTransformation(module: try await world.module, options: .standard)
        await #expect(throws: ATLExecutionError.self) { try await transformation.update() }
        try await transformation.execute(sources: ["IN": world.resource], targets: ["OUT": Resource()])
        let report = try await transformation.update()
        #expect(report == ATLIncrementalUpdate(changeCount: 0))
        #expect(transformation.lastUpdate == report)
    }

    // MARK: - Propagation

    @Test("changing an attribute re-evaluates only the bindings that read it")
    func attributePropagation() async throws {
        let world = try await FamilyWorld(families: 3, membersPerFamily: 4, seed: 2)
        let module = try await world.module
        let target = Resource(uri: Self.familyTarget)
        let transformation = ATLIncrementalTransformation(module: module, options: .standard)
        try await transformation.execute(sources: ["IN": world.resource], targets: ["OUT": target])
        let member = try #require(await world.ids(of: "Member").first)
        try await world.resource.eSetWithChanges(objectId: member, feature: "age", value: 77)
        #expect(transformation.pendingChangeCount == 1)
        let report = try await transformation.update()
        #expect(report.reexecuted == false)
        // The age binding of the person and the register binding, whose selection reads ages
        #expect(report.bindingsEvaluated == 2)
        #expect(report.matchesAdded == 0 && report.matchesRemoved == 0)
        #expect(report.guardsEvaluated == 0)
        let expected = try await batchXMI(module: module, source: world.resource, targetURI: Self.familyTarget)
        #expect(try await XMISerializer().serialize(target) == expected)
    }

    @Test("renaming a family re-evaluates the cached helper and the names of its members")
    func helperPropagation() async throws {
        let world = try await FamilyWorld(families: 3, membersPerFamily: 4, seed: 3)
        let module = try await world.module
        let target = Resource(uri: Self.familyTarget)
        let transformation = ATLIncrementalTransformation(module: module, options: .standard)
        try await transformation.execute(sources: ["IN": world.resource], targets: ["OUT": target])
        let family = try #require(await world.ids(of: "Family").first)
        try await world.resource.eSetWithChanges(objectId: family, feature: "lastName", value: "Renamed")
        let report = try await transformation.update()
        #expect(report.bindingsEvaluated == 4)
        let xml = try await XMISerializer().serialize(target)
        #expect(xml.contains("Renamed"))
        #expect(xml == (try await batchXMI(module: module, source: world.resource, targetURI: Self.familyTarget)))
    }

    @Test("switching a guard replaces the target element of a member")
    func guardPropagation() async throws {
        let world = try await FamilyWorld(families: 2, membersPerFamily: 3, seed: 4)
        let module = try await world.module
        let target = Resource(uri: Self.familyTarget)
        let transformation = ATLIncrementalTransformation(module: module, options: .standard)
        try await transformation.execute(sources: ["IN": world.resource], targets: ["OUT": target])
        let member = try #require(await world.ids(of: "Member").last)
        let female = await world.resource.eGet(objectId: member, feature: "isFemale") as? Bool ?? false
        try await world.resource.eSetWithChanges(objectId: member, feature: "isFemale", value: !female)
        let report = try await transformation.update()
        #expect(report.matchesAdded == 1 && report.matchesRemoved == 1)
        #expect(report.reexecuted == false)
        #expect(try await XMISerializer().serialize(target)
            == (try await batchXMI(module: module, source: world.resource, targetURI: Self.familyTarget)))
    }

    @Test("adding and deleting members creates and deletes their persons")
    func structuralPropagation() async throws {
        var world = try await FamilyWorld(families: 2, membersPerFamily: 2, seed: 5)
        let module = try await world.module
        let target = Resource(uri: Self.familyTarget)
        let transformation = ATLIncrementalTransformation(module: module, options: .standard)
        try await transformation.execute(sources: ["IN": world.resource], targets: ["OUT": target])
        let family = try #require(await world.ids(of: "Family").last)
        var member = DynamicEObject(eClass: world.metamodels.member)
        member.eSet("firstName", value: "Newborn")
        member.eSet("age", value: 0)
        try await world.resource.eAdd(objectId: family, feature: "members", value: member, at: 0)
        let added = try await transformation.update()
        #expect(added.matchesAdded == 1 && added.reexecuted == false)
        #expect(try await XMISerializer().serialize(target)
            == (try await batchXMI(module: module, source: world.resource, targetURI: Self.familyTarget)))
        await world.resource.delete([family])
        let removed = try await transformation.update()
        #expect(removed.matchesRemoved == 3)
        #expect(try await XMISerializer().serialize(target)
            == (try await batchXMI(module: module, source: world.resource, targetURI: Self.familyTarget)))
        world.counter = 0
    }

    @Test("a feature set for the first time takes the position of its binding")
    func featureOrder() async throws {
        let world = try await FamilyWorld(families: 1, membersPerFamily: 3, seed: 6)
        let module = try await ATLParser().parseContent(
            """
            module M; create OUT : Persons from IN : Families;
            rule R { from s : Families!Member to t : Persons!Male (
                fullName <- if s.age > 50 then s.firstName else OclUndefined endif, age <- s.age ) }
            """
        ).withMetamodels(source: ["IN": world.metamodels.families], target: ["OUT": world.metamodels.persons])
        let members = await world.ids(of: "Member")
        for member in members {
            try await world.resource.eSetWithChanges(objectId: member, feature: "age", value: 10)
        }
        let target = Resource(uri: Self.familyTarget)
        let transformation = ATLIncrementalTransformation(module: module, options: .standard)
        try await transformation.execute(sources: ["IN": world.resource], targets: ["OUT": target])
        try await world.resource.eSetWithChanges(objectId: members[1], feature: "age", value: 60)
        let report = try await transformation.update()
        #expect(report.bindingsEvaluated == 2)
        let xml = try await XMISerializer().serialize(target)
        #expect(xml.contains("fullName=\"M0x1\" age=\"60\""))
        #expect(xml == (try await batchXMI(module: module, source: world.resource, targetURI: Self.familyTarget)))
    }

    // MARK: - Differential testing

    @Test("families: incremental results equal batch results after random edits", arguments: [UInt64(11), 23, 2026])
    func familiesDifferential(seed: UInt64) async throws {
        var world = try await FamilyWorld(families: 4, membersPerFamily: 4, seed: seed)
        let module = try await world.module
        let target = Resource(uri: Self.familyTarget)
        let transformation = ATLIncrementalTransformation(module: module, options: .standard)
        try await transformation.execute(sources: ["IN": world.resource], targets: ["OUT": target])
        var generator = SplitMixGenerator(seed: seed)
        var reexecutions = 0
        for step in 0..<80 {
            try await world.randomEdit(&generator)
            let report = try await transformation.update()
            if report.reexecuted { reexecutions += 1 }
            let expected = try await batchXMI(module: module, source: world.resource, targetURI: Self.familyTarget)
            let actual = try await XMISerializer().serialize(target)
            #expect(actual == expected, "step \(step) of seed \(seed): \(report)")
            if actual != expected { break }
        }
        #expect(reexecutions == 0)
        #expect(transformation.strategy == .propagation)
    }

    @Test("classes: incremental results equal batch results after random edits", arguments: [UInt64(5), 17, 99])
    func classesDifferential(seed: UInt64) async throws {
        var world = try await ClassWorld(classes: 6, attributesPerClass: 3, seed: seed)
        let module = try await world.module
        let target = Resource(uri: Self.classTarget)
        let transformation = ATLIncrementalTransformation(module: module, options: .standard)
        try await transformation.execute(sources: ["IN": world.resource], targets: ["OUT": target])
        #expect(try await XMISerializer().serialize(target)
            == (try await batchXMI(module: module, source: world.resource, targetURI: Self.classTarget)))
        var generator = SplitMixGenerator(seed: seed)
        var reexecutions = 0
        for step in 0..<80 {
            try await world.randomEdit(&generator)
            let report = try await transformation.update()
            if report.reexecuted { reexecutions += 1 }
            let expected = try await batchXMI(module: module, source: world.resource, targetURI: Self.classTarget)
            let actual = try await XMISerializer().serialize(target)
            #expect(actual == expected, "step \(step) of seed \(seed): \(report)")
            if actual != expected { break }
        }
        #expect(reexecutions == 0)
    }

    // MARK: - On-demand bindings

    @Test("on-demand propagation defers bindings until they are requested")
    func onDemandBindings() async throws {
        var world = try await FamilyWorld(families: 3, membersPerFamily: 3, seed: 8)
        let module = try await world.module
        let target = Resource(uri: Self.familyTarget)
        let transformation = ATLIncrementalTransformation(
            module: module, options: .standard, bindingPropagation: .onDemand)
        try await transformation.execute(sources: ["IN": world.resource], targets: ["OUT": target])
        let family = try #require(await world.ids(of: "Family").first)
        try await world.resource.eSetWithChanges(objectId: family, feature: "lastName", value: "Later")
        let report = try await transformation.update()
        #expect(report.bindingsEvaluated == 0 && report.bindingsDeferred == 3)
        #expect(transformation.staleBindingCount == 3)
        #expect(try await XMISerializer().serialize(target).contains("Later") == false)

        let persons = await target.getAllObjects().filter { $0.eClass.name != "Register" }.map(\.id)
        var refreshed = 0
        for person in persons {
            if let name = try await transformation.value(of: person, feature: "fullName") as? String,
                name.hasSuffix("Later")
            {
                refreshed += 1
                break
            }
        }
        #expect(refreshed == 1)
        #expect(transformation.staleBindingCount == 2)
        #expect(try await transformation.value(of: EUUID(), feature: "fullName") == nil)

        var generator = SplitMixGenerator(seed: 8)
        for _ in 0..<30 { try await world.randomEdit(&generator); try await transformation.update() }
        _ = try await transformation.materialise()
        #expect(transformation.staleBindingCount == 0)
        #expect(try await transformation.materialise() == 0)
        #expect(try await XMISerializer().serialize(target)
            == (try await batchXMI(module: module, source: world.resource, targetURI: Self.familyTarget)))
    }

    // MARK: - Observation

    @Test("after stopping, changes are propagated only when given explicitly")
    func explicitChanges() async throws {
        let world = try await FamilyWorld(families: 2, membersPerFamily: 2, seed: 9)
        let module = try await world.module
        let target = Resource(uri: Self.familyTarget)
        let transformation = ATLIncrementalTransformation(module: module, options: .standard)
        try await transformation.execute(sources: ["IN": world.resource], targets: ["OUT": target])
        await transformation.stop()
        #expect(transformation.isObserving == false)
        let member = try #require(await world.ids(of: "Member").first)
        let changes = try await world.resource.eSetWithChanges(objectId: member, feature: "firstName", value: "Explicit")
        #expect(transformation.pendingChangeCount == 0)
        let report = try await transformation.update(for: changes)
        #expect(report.bindingsEvaluated == 1)
        #expect(try await XMISerializer().serialize(target)
            == (try await batchXMI(module: module, source: world.resource, targetURI: Self.familyTarget)))
    }

    // MARK: - Re-execution

    /// Executes a module incrementally and checks that a change leads to a re-execution
    /// whose result equals a batch execution.
    private func checkReexecution(_ text: String, reason expected: String, static isStatic: Bool) async throws {
        let world = try await FamilyWorld(families: 2, membersPerFamily: 3, seed: 10)
        let module = try await ATLParser().parseContent(text)
            .withMetamodels(source: ["IN": world.metamodels.families], target: ["OUT": world.metamodels.persons])
        let transformation = ATLIncrementalTransformation(module: module, options: .standard)
        if isStatic { #expect(transformation.strategy == .reexecution(reason: expected)) }
        let target = Resource(uri: Self.familyTarget)
        try await transformation.execute(sources: ["IN": world.resource], targets: ["OUT": target])
        #expect(transformation.strategy == .reexecution(reason: expected))
        let member = try #require(await world.ids(of: "Member").first)
        try await world.resource.eSetWithChanges(objectId: member, feature: "firstName", value: "Again")
        let report = try await transformation.update()
        #expect(report.reexecuted && report.reason == expected)
        #expect(try await XMISerializer().serialize(target)
            == (try await batchXMI(module: module, source: world.resource, targetURI: Self.familyTarget)))
    }

    @Test("modules with called rules are executed again")
    func calledRulesReexecute() async throws {
        try await checkReexecution(
            """
            module M; create OUT : Persons from IN : Families;
            lazy rule Copy { from s : Families!Member to t : Persons!Male ( fullName <- s.firstName ) }
            rule R { from r : Families!Registry to reg : Persons!Register (
                persons <- Families!Member.allInstances()->collect(m | thisModule.Copy(m)) ) }
            """, reason: ATLIncrementalHazard.calledRules, static: true)
    }

    @Test("modules with do sections are executed again")
    func doSectionsReexecute() async throws {
        try await checkReexecution(
            """
            module M; create OUT : Persons from IN : Families;
            rule R { from s : Families!Member to t : Persons!Male ( fullName <- s.firstName ) do { t.age <- 1; } }
            """, reason: ATLIncrementalHazard.imperativeSection, static: true)
    }

    @Test("expressions that read target elements make the module execute again")
    func targetReadsReexecute() async throws {
        try await checkReexecution(
            """
            module M; create OUT : Persons from IN : Families;
            rule R { from s : Families!Member to t : Persons!Male (
                fullName <- s.firstName, age <- thisModule.resolveTemp(s, 't').fullName.size() ) }
            """, reason: ATLIncrementalHazard.targetRead, static: false)
    }

    @Test("modules that change models from expressions are executed again")
    func modelChangesReexecute() async throws {
        try await checkReexecution(
            """
            module M; create OUT : Persons from IN : Families;
            rule R { from s : Families!Member to t : Persons!Male (
                fullName <- s.firstName, age <- t.refSetValue('fullName', 'x').age ) }
            """, reason: ATLIncrementalHazard.modelChange, static: false)
    }

    @Test("bindings of references with opposites make the module execute again")
    func oppositesReexecute() async throws {
        let k = MetamodelKit.self
        var node = EClass(name: "Node")
        node.eStructuralFeatures = [k.attribute("label", k.string)]
        let nextID = EUUID()
        let previousID = EUUID()
        node.eStructuralFeatures.append(EReference(id: nextID, name: "next", eType: node, opposite: previousID))
        node.eStructuralFeatures.append(EReference(id: previousID, name: "previous", eType: node, opposite: nextID))
        let graph = EPackage(name: "Graph", nsURI: "http://example.org/graph", nsPrefix: "graph", eClassifiers: [node])
        let world = try await FamilyWorld(families: 1, membersPerFamily: 2, seed: 3)
        let module = try await ATLParser().parseContent(
            """
            module M; create OUT : Graph from IN : Families;
            rule R { from s : Families!Member to n : Graph!Node ( label <- s.firstName, next <- s.mentor ) }
            """
        ).withMetamodels(source: ["IN": world.metamodels.families], target: ["OUT": graph])
        let transformation = ATLIncrementalTransformation(module: module, options: .standard)
        #expect(transformation.strategy == .reexecution(reason: ATLIncrementalHazard.oppositeReference))
    }

    @Test("rebinding a source element to another class makes the module execute again")
    func unboundedChangesReexecute() async throws {
        let world = try await FamilyWorld(families: 2, membersPerFamily: 2, seed: 12)
        let module = try await world.module
        let target = Resource(uri: Self.familyTarget)
        let transformation = ATLIncrementalTransformation(module: module, options: .standard)
        try await transformation.execute(sources: ["IN": world.resource], targets: ["OUT": target])
        await world.resource.rebind(to: [world.metamodels.families], from: [world.metamodels.families])
        let report = try await transformation.update()
        #expect(report.reexecuted && report.reason == ATLIncrementalHazard.unboundedChange)
        #expect(transformation.strategy == .propagation)
        #expect(try await XMISerializer().serialize(target)
            == (try await batchXMI(module: module, source: world.resource, targetURI: Self.familyTarget)))
    }

    @Test("refining modules and queries are executed again")
    func otherStaticReasons() async throws {
        let world = try await FamilyWorld(families: 1, membersPerFamily: 1, seed: 1)
        let refining = try await ATLParser().parseContent(
            "module M; create OUT : Families refining IN : Families;\n"
        ).withMetamodels(source: ["IN": world.metamodels.families], target: ["OUT": world.metamodels.families])
        #expect(
            ATLIncrementalTransformation(module: refining, options: .standard).strategy
                == .reexecution(reason: ATLIncrementalHazard.refining))
        let query = try await ATLParser().parseContent("query Q = 1;")
        #expect(
            ATLIncrementalTransformation(module: query, options: .standard).strategy
                == .reexecution(reason: ATLIncrementalHazard.query))
    }

    @Test("a binding that cannot be evaluated fails as in a batch execution")
    func failingBindings() async throws {
        let world = try await FamilyWorld(families: 1, membersPerFamily: 2, seed: 1)
        let module = try await ATLParser().parseContent(
            """
            module M; create OUT : Persons from IN : Families;
            rule R { from s : Families!Member to t : Persons!Male ( fullName <- s.noSuchFeature ) }
            """
        ).withMetamodels(source: ["IN": world.metamodels.families], target: ["OUT": world.metamodels.persons])
        let transformation = ATLIncrementalTransformation(module: module, options: .standard)
        await #expect(throws: (any Error).self) {
            try await transformation.execute(sources: ["IN": world.resource], targets: ["OUT": Resource()])
        }
    }

    @Test("a binding that fails during an update falls back to a batch execution, which fails as well")
    func failingUpdate() async throws {
        let world = try await FamilyWorld(families: 1, membersPerFamily: 3, seed: 1)
        let members = await world.ids(of: "Member")
        for member in members {
            try await world.resource.eSetWithChanges(objectId: member, feature: "age", value: 20)
        }
        let module = try await ATLParser().parseContent(
            """
            module M; create OUT : Persons from IN : Families;
            rule R { from s : Families!Member to t : Persons!Male (
                fullName <- if s.age > 50 then s.noSuchFeature else s.firstName endif ) }
            """
        ).withMetamodels(source: ["IN": world.metamodels.families], target: ["OUT": world.metamodels.persons])
        let target = Resource(uri: Self.familyTarget)
        let transformation = ATLIncrementalTransformation(module: module, options: .standard)
        try await transformation.execute(sources: ["IN": world.resource], targets: ["OUT": target])
        #expect(transformation.strategy == .propagation)
        try await world.resource.eSetWithChanges(objectId: members[0], feature: "age", value: 60)
        await #expect(throws: (any Error).self) { try await transformation.update() }
        #expect(transformation.hasExecuted == false)
        #expect(transformation.strategy == .reexecution(reason: ATLIncrementalHazard.deferredBinding))
        await #expect(throws: ATLExecutionError.self) { try await transformation.update() }
        try await world.resource.eSetWithChanges(objectId: members[0], feature: "age", value: 30)
        let fresh = Resource(uri: Self.familyTarget)
        try await transformation.execute(sources: ["IN": world.resource], targets: ["OUT": fresh])
        #expect(transformation.strategy == .propagation)
        #expect(try await XMISerializer().serialize(fresh)
            == (try await batchXMI(module: module, source: world.resource, targetURI: Self.familyTarget)))
    }

    @Test("updates report what they did")
    func reportDescribesWork() {
        let report = ATLIncrementalUpdate(
            changeCount: 2, reexecuted: false, reason: nil, guardsEvaluated: 3, matchesAdded: 1, matchesRemoved: 1,
            localsEvaluated: 1, bindingsEvaluated: 4, bindingsDeferred: 0)
        #expect(report.changeCount == 2 && report.guardsEvaluated == 3 && report.localsEvaluated == 1)
        #expect(report != ATLIncrementalUpdate(changeCount: 2))
    }
}
