//
//  ATLVMSemanticsTests.swift
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

// MARK: - Fixture

/// A test expression evaluating the given expressions to a collection.
struct ListExpression: ATLExpression {
    let elements: [any ATLExpression]

    @MainActor
    func evaluate(in context: ATLExecutionContext) async throws -> (any EcoreValue)? {
        var values: [any EcoreValue] = []
        for element in elements {
            if let value = try await element.evaluate(in: context) { values.append(value) }
        }
        return EcoreValueArray(values)
    }

    static func == (lhs: ListExpression, rhs: ListExpression) -> Bool {
        lhs.elements.count == rhs.elements.count
    }

    func hash(into hasher: inout Hasher) { hasher.combine(elements.count) }
}

/// Hand-built source and target metamodels together with a source model.
///
/// The source metamodel has `Node` (with the `Special` subclass), `Leaf` and
/// `Holder`, which contains nodes and leaves. The target metamodel has `TNode`,
/// `TLeaf` and `Marker`.
@MainActor
struct SemanticsFixture {
    let source: EPackage
    let target: EPackage
    let sourceResource = Resource(uri: "test://source")
    let targetResource = Resource(uri: "test://target")

    /// Identifiers of the source elements created by ``populate()``.
    var holder: DynamicEObject!
    var alpha: DynamicEObject!
    var beta: DynamicEObject!
    var gamma: DynamicEObject!
    var special: DynamicEObject!
    var leafAlpha: DynamicEObject!
    var leafOther: DynamicEObject!

    init() {
        let string = EDataType(name: "EString")
        let integer = EDataType(name: "EInt")

        var leaf = EClass(name: "Leaf")
        leaf.eStructuralFeatures.append(EAttribute(name: "name", eType: string))
        leaf.eStructuralFeatures.append(
            EReference(name: "owner", eType: EClass(name: "Node")))

        var node = EClass(name: "Node")
        node.eStructuralFeatures.append(EAttribute(name: "name", eType: string))
        node.eStructuralFeatures.append(EAttribute(name: "age", eType: integer))
        node.eStructuralFeatures.append(EReference(name: "next", eType: EClass(name: "Node")))
        node.eStructuralFeatures.append(
            EReference(name: "kids", eType: EClass(name: "Node"), upperBound: -1))
        node.eStructuralFeatures.append(EReference(name: "leaf", eType: leaf))

        let special = EClass(name: "Special", eSuperTypes: [node])

        var holder = EClass(name: "Holder")
        holder.eStructuralFeatures.append(
            EReference(name: "items", eType: node, upperBound: -1, containment: true))
        holder.eStructuralFeatures.append(
            EReference(name: "leaves", eType: leaf, upperBound: -1, containment: true))

        var source = EPackage(name: "Src", nsURI: "http://test/src", nsPrefix: "src")
        source.eClassifiers.append(contentsOf: [leaf, node, special, holder])
        self.source = source

        var tnode = EClass(name: "TNode")
        tnode.eStructuralFeatures.append(EAttribute(name: "name", eType: string))
        tnode.eStructuralFeatures.append(EAttribute(name: "tag", eType: string))
        tnode.eStructuralFeatures.append(EAttribute(name: "count", eType: integer))
        tnode.eStructuralFeatures.append(EReference(name: "next", eType: EClass(name: "TNode")))
        tnode.eStructuralFeatures.append(
            EReference(name: "kids", eType: EClass(name: "TNode"), upperBound: -1))
        tnode.eStructuralFeatures.append(EReference(name: "leaf", eType: leaf))
        tnode.eStructuralFeatures.append(
            EReference(name: "leaves", eType: leaf, upperBound: -1))
        tnode.eStructuralFeatures.append(
            EReference(name: "mixed", eType: EClass(name: "Any"), upperBound: -1))

        var tleaf = EClass(name: "TLeaf")
        tleaf.eStructuralFeatures.append(EAttribute(name: "name", eType: string))
        tleaf.eStructuralFeatures.append(EReference(name: "node", eType: tnode))

        var marker = EClass(name: "Marker")
        marker.eStructuralFeatures.append(EAttribute(name: "label", eType: string))

        var target = EPackage(name: "Tgt", nsURI: "http://test/tgt", nsPrefix: "tgt")
        target.eClassifiers.append(contentsOf: [tnode, tleaf, marker])
        self.target = target
    }

    /// Creates the source model: a holder with nodes alpha, beta, gamma and special,
    /// and leaves "alpha" and "other".
    mutating func populate() async {
        func object(_ name: String) -> DynamicEObject {
            let eClass = (source.getClassifier(name) as? EClass)!
            return DynamicEObject(eClass: eClass)
        }
        func named(_ className: String, _ name: String, age: Int = 0) async -> DynamicEObject {
            var element = object(className)
            element.eSet("name", value: name)
            if className != "Leaf" { element.eSet("age", value: age) }
            return element
        }
        holder = object("Holder")
        alpha = await named("Node", "alpha", age: 10)
        beta = await named("Node", "beta", age: 20)
        gamma = await named("Node", "gamma", age: 30)
        special = await named("Special", "special", age: 5)
        leafAlpha = await named("Leaf", "alpha")
        leafOther = await named("Leaf", "other")

        for element in [holder!, alpha!, beta!, gamma!, special!, leafAlpha!, leafOther!] {
            await sourceResource.register(element)
        }
        await sourceResource.add(holder)
        await set(holder, "items", [alpha.id, beta.id, gamma.id, special.id])
        await set(holder, "leaves", [leafAlpha.id, leafOther.id])
        await set(alpha, "next", beta.id)
        await set(alpha, "kids", [beta.id, gamma.id])
        await set(gamma, "next", alpha.id)
        await set(alpha, "leaf", leafOther.id)
        await set(beta, "leaf", leafAlpha.id)
        await set(special, "next", beta.id)
        await set(leafAlpha, "owner", alpha.id)
    }

    func set(_ element: DynamicEObject, _ feature: String, _ value: any EcoreValue) async {
        await sourceResource.eSet(objectId: element.id, feature: feature, value: value)
    }

    /// Builds a module from ATL text, substituting the hand-built metamodels.
    func module(_ atl: String, extraRules: [ATLMatchedRule] = []) async throws -> ATLModule {
        let parsed = try await ATLParser().parseContent(
            "module Test;\ncreate OUT : Tgt from IN : Src;\n" + atl)
        return ATLModule(
            name: parsed.name,
            sourceMetamodels: ["IN": source],
            targetMetamodels: ["OUT": target],
            helpers: parsed.helpers,
            matchedRules: parsed.matchedRules + extraRules,
            calledRules: parsed.calledRules
        )
    }

    /// Runs ATL text, and any rules built by hand, over the source model.
    func run(_ atl: String, extraRules: [ATLMatchedRule] = []) async throws {
        let vm = ATLVirtualMachine(module: try await module(atl, extraRules: extraRules))
        try await vm.execute(
            sources: ["IN": sourceResource], targets: ["OUT": targetResource])
    }

    /// All target elements of a class, in creation order.
    func targets(_ className: String) async -> [DynamicEObject] {
        await targetResource.getAllObjects().compactMap { $0 as? DynamicEObject }
            .filter { $0.eClass.name == className }
    }

    /// The target element with the given class and name.
    func target(_ className: String, named name: String) async -> DynamicEObject? {
        await targets(className).first { $0.eGet("name") as? String == name }
    }
}

// MARK: - Implicit Resolution

@Suite("ATL VM Implicit Resolution")
@MainActor
struct ATLImplicitResolutionTests {

    private let nodeRule = """
        rule N2T {
            from s : Src!Node
            to t : Tgt!TNode (name <- s.name, next <- s.next, kids <- s.kids)
        }
        """

    @Test("Single and multi-valued references resolve to default targets")
    func resolvesToTargets() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(nodeRule)

        let alpha = try #require(await fixture.target("TNode", named: "alpha"))
        let beta = try #require(await fixture.target("TNode", named: "beta"))
        let gamma = try #require(await fixture.target("TNode", named: "gamma"))
        #expect(alpha.eGet("next") as? EUUID == beta.id)
        #expect(gamma.eGet("next") as? EUUID == alpha.id)
        #expect(alpha.eGet("kids") as? [EUUID] == [beta.id, gamma.id])
    }

    @Test("Resolution does not depend on rule order")
    func independentOfOrder() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule L2T {
                from l : Src!Leaf
                to t : Tgt!TLeaf (name <- l.name, node <- l.owner)
            }
            rule N2T {
                from s : Src!Node
                to t : Tgt!TNode (name <- s.name)
            }
            """)
        let leaf = try #require(await fixture.target("TLeaf", named: "alpha"))
        let node = try #require(await fixture.target("TNode", named: "alpha"))
        #expect(leaf.eGet("node") as? EUUID == node.id)
    }

    @Test("Untransformed source elements remain references into the source model")
    func keepsSourceReferences() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule N2T {
                from s : Src!Node
                to t : Tgt!TNode (name <- s.name, leaf <- s.leaf)
            }
            """)
        let alpha = try #require(await fixture.target("TNode", named: "alpha"))
        let proxy = try #require(alpha.eGet("leaf") as? ResourceProxy)
        #expect(proxy.uri == "test://source")
        #expect(proxy.fragment == "//@leaves.1")
        let beta = try #require(await fixture.target("TNode", named: "beta"))
        #expect((beta.eGet("leaf") as? ResourceProxy)?.fragment == "//@leaves.0")
        #expect(await fixture.target("TNode", named: "gamma")?.eGet("leaf") == nil)
    }

    @Test("Multi-valued untransformed references are stored as proxies")
    func multiValuedProxies() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule H2T {
                from h : Src!Holder
                to t : Tgt!TNode (name <- 'holder', leaves <- h.leaves)
            }
            """)
        let holder = try #require(await fixture.target("TNode", named: "holder"))
        let proxies = try #require(holder.eGet("leaves") as? [ResourceProxy])
        #expect(proxies.map(\.fragment) == ["//@leaves.0", "//@leaves.1"])
    }

    @Test("Mixed transformed and untransformed references are stored as an array of both forms")
    func mixedReferences() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule N2T {
                from s : Src!Node
                to t : Tgt!TNode (name <- s.name)
            }
            rule H2T {
                from h : Src!Holder
                to t : Tgt!TNode (
                    name <- 'holder',
                    mixed <- h.items->select(i | i.name = 'alpha' or i.name = 'beta')
                        ->collect(i | if i.name = 'alpha' then i.next else i.leaf endif)
                )
            }
            """)
        let alpha = try #require(await fixture.target("TNode", named: "holder"))
        let beta = try #require(await fixture.target("TNode", named: "beta"))
        let mixed = try #require(alpha.eGet("mixed") as? EcoreValueArray)
        #expect(mixed.values.count == 2)
        #expect(mixed.values[0] as? EUUID == beta.id)
        #expect((mixed.values[1] as? ResourceProxy)?.fragment == "//@leaves.0")
    }

    @Test("Repeated references to one target are stored once")
    func deduplicatesReferences() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule N2T {
                from s : Src!Node
                to t : Tgt!TNode (name <- s.name)
            }
            rule H2T {
                from h : Src!Holder
                to t : Tgt!TNode (
                    name <- 'holder',
                    kids <- h.items->select(i | i.name = 'alpha' or i.name = 'special')
                        ->collect(i | i.next)
                )
            }
            """)
        let alpha = try #require(await fixture.target("TNode", named: "holder"))
        #expect((alpha.eGet("kids") as? [EUUID])?.count == 1)
    }

    @Test("A source element is mapped to the default target of its first target pattern")
    func defaultIsFirstPattern() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule N2T {
                from s : Src!Node
                to first : Tgt!TNode (name <- s.name),
                   second : Tgt!TNode (name <- s.name + '_second')
            }
            rule L2T {
                from l : Src!Leaf (l.name = 'alpha')
                to t : Tgt!TLeaf (name <- l.name, node <- l.owner)
            }
            """)
        let leaf = try #require(await fixture.target("TLeaf", named: "alpha"))
        let first = try #require(await fixture.target("TNode", named: "alpha"))
        #expect(leaf.eGet("node") as? EUUID == first.id)
    }

    @Test("Target elements of one target model referenced from another are stored as proxies")
    func crossTargetReferences() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        let module = try await fixture.module(
            """
            rule N2T {
                from s : Src!Node (s.name = 'alpha')
                to t : Tgt!TNode (name <- s.name)
            }
            """)
        let other = Resource(uri: "test://other")
        let context = ATLExecutionContext(
            module: module,
            sources: ["IN": fixture.sourceResource],
            targets: ["OUT": fixture.targetResource, "AUX": other],
            executionEngine: ECoreExecutionEngine(models: [:])
        )
        let tnode = try #require(fixture.target.getClassifier("TNode") as? EClass)
        let owner = DynamicEObject(eClass: tnode)
        let referenced = DynamicEObject(eClass: tnode)
        await fixture.targetResource.add(owner)
        await other.add(referenced)

        try await context.assignFeature(on: owner, feature: "next", value: referenced)
        let stored = await fixture.targetResource.eGet(objectId: owner.id, feature: "next")
        let proxy = try #require(stored as? ResourceProxy)
        #expect(proxy.uri == "test://other")
        #expect(proxy.fragment == "/")
    }
}

// MARK: - resolveTemp

@Suite("ATL VM resolveTemp")
@MainActor
struct ATLResolveTempTests {

    @Test("resolveTemp returns the named target pattern element")
    func namedPattern() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule N2T {
                from s : Src!Node
                to a : Tgt!TNode (name <- s.name),
                   b : Tgt!TNode (name <- s.name + '_b')
            }
            rule L2T {
                from l : Src!Leaf (l.name = 'alpha')
                to t : Tgt!TLeaf (
                    name <- l.name,
                    node <- thisModule.resolveTemp(l.owner, 'b')
                )
            }
            """)
        let leaf = try #require(await fixture.target("TLeaf", named: "alpha"))
        let named = try #require(await fixture.target("TNode", named: "alpha_b"))
        #expect(leaf.eGet("node") as? EUUID == named.id)
    }

    @Test("resolveTemp without a name returns the first target element")
    func defaultElement() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule N2T {
                from s : Src!Node
                to a : Tgt!TNode (name <- s.name),
                   b : Tgt!TNode (name <- s.name + '_b')
            }
            rule L2T {
                from l : Src!Leaf (l.name = 'alpha')
                to t : Tgt!TLeaf (name <- l.name, node <- thisModule.resolveTemp(l.owner))
            }
            """)
        let leaf = try #require(await fixture.target("TLeaf", named: "alpha"))
        let first = try #require(await fixture.target("TNode", named: "alpha"))
        #expect(leaf.eGet("node") as? EUUID == first.id)
    }

    @Test("resolveTemp with an unknown pattern name fails the transformation")
    func unknownName() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        await #expect(throws: ATLExecutionError.self) {
            try await fixture.run(
                """
                rule N2T {
                    from s : Src!Node
                    to a : Tgt!TNode (name <- s.name)
                }
                rule L2T {
                    from l : Src!Leaf (l.name = 'alpha')
                    to t : Tgt!TLeaf (node <- thisModule.resolveTemp(l.owner, 'missing'))
                }
                """)
        }
    }

    @Test("resolveTemp finds results of rules matching several source elements by tuple")
    func tupleSources() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        let tuple = ListExpression(elements: [
            ATLVariableExpression(name: "a"), ATLVariableExpression(name: "b"),
        ])
        let lookup = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "thisModule"),
            methodName: "resolveTemp",
            arguments: [tuple, ATLLiteralExpression(value: "t")]
        )
        let again = ATLMatchedRule(
            name: "Again",
            sourcePattern: ATLSourcePattern(variableName: "a", type: "Src!Node"),
            targetPatterns: [
                ATLTargetPattern(
                    variableName: "u", type: "Tgt!TNode",
                    bindings: [
                        ATLPropertyBinding(
                            property: "name", expression: ATLLiteralExpression(value: "again")),
                        ATLPropertyBinding(property: "next", expression: lookup),
                    ])
            ],
            guard: ATLBinaryExpression(
                left: ATLNavigationExpression(
                    source: ATLVariableExpression(name: "a"), property: "name"),
                operator: .equals,
                right: ATLNavigationExpression(
                    source: ATLVariableExpression(name: "b"), property: "name")),
            additionalSourcePatterns: [ATLSourcePattern(variableName: "b", type: "Src!Leaf")]
        )
        try await fixture.run(
            """
            rule Pair {
                from a : Src!Node, b : Src!Leaf (a.name = b.name)
                to t : Tgt!TNode (name <- a.name + '/' + b.name)
            }
            """, extraRules: [again])
        let pair = try #require(await fixture.target("TNode", named: "alpha/alpha"))
        let results = await fixture.targets("TNode").filter { $0.eGet("name") as? String == "again" }
        #expect(results.count == 1)
        #expect(results.first?.eGet("next") as? EUUID == pair.id)
    }
}

// MARK: - Multiple Source Elements

@Suite("ATL VM Multiple Source Elements")
@MainActor
struct ATLMultipleSourceTests {

    @Test("A rule matches every combination of source elements satisfying the guard")
    func combinations() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule Pair {
                from a : Src!Node, b : Src!Leaf (a.name = b.name)
                to t : Tgt!TNode (name <- a.name + '/' + b.name)
            }
            """)
        let created = await fixture.targets("TNode")
        #expect(created.count == 1)
        #expect(created.first?.eGet("name") as? String == "alpha/alpha")
    }

    @Test("Without a guard the rule matches the full cross product")
    func crossProduct() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule Pair {
                from a : Src!Node, b : Src!Leaf
                to t : Tgt!TNode (name <- a.name + '/' + b.name)
            }
            """)
        #expect(await fixture.targets("TNode").count == 4 * 2)
    }
}

// MARK: - Called and Lazy Rules

@Suite("ATL VM Called and Lazy Rules")
@MainActor
struct ATLCalledRuleTests {

    @Test("Unique lazy rules create their elements once per argument")
    func uniqueLazy() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            unique lazy rule Copy {
                from s : Src!Node
                to t : Tgt!Marker (label <- s.name)
            }
            rule H2T {
                from h : Src!Holder
                to t : Tgt!TNode (name <- 'one', kids <- h.items->collect(i | thisModule.Copy(i)))
            }
            rule H2U {
                from h : Src!Holder
                to t : Tgt!TNode (name <- 'two', kids <- h.items->collect(i | thisModule.Copy(i)))
            }
            """)
        #expect(await fixture.targets("Marker").count == 4)
        let one = try #require(await fixture.target("TNode", named: "one"))
        let two = try #require(await fixture.target("TNode", named: "two"))
        #expect(one.eGet("kids") as? [EUUID] == two.eGet("kids") as? [EUUID])
    }

    @Test("Lazy rules create new elements for every invocation")
    func lazyCreatesEachTime() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            lazy rule Copy {
                from s : Src!Node
                to t : Tgt!Marker (label <- s.name)
            }
            rule H2T {
                from h : Src!Holder
                to t : Tgt!TNode (name <- 'one', kids <- h.items->collect(i | thisModule.Copy(i)))
            }
            rule H2U {
                from h : Src!Holder
                to t : Tgt!TNode (name <- 'two', kids <- h.items->collect(i | thisModule.Copy(i)))
            }
            """)
        #expect(await fixture.targets("Marker").count == 8)
    }

    @Test("Lazy rules never run unless invoked")
    func lazyNotTriggered() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            lazy rule Copy {
                from s : Src!Node
                to t : Tgt!Marker (label <- s.name)
            }
            """)
        #expect(await fixture.targets("Marker").isEmpty)
    }

    @Test("Unique lazy results are found by resolveTemp and cycles terminate")
    func uniqueCycles() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            unique lazy rule Copy {
                from s : Src!Node
                to t : Tgt!TNode (name <- s.name, next <- thisModule.Copy(s.next))
            }
            rule H2T {
                from h : Src!Holder
                to m : Tgt!Marker (label <- 'start')
            do {
                thisModule.Copy(h.items->first());
            }
            }
            """)
        // alpha -> beta, beta has no next; gamma and special are never reached
        let created = await fixture.targets("TNode")
        #expect(created.map { $0.eGet("name") as? String } == ["alpha", "beta"])
    }

    @Test("A lazy rule whose guard fails creates nothing")
    func lazyGuard() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            lazy rule Copy {
                from s : Src!Node (s.age > 15)
                to t : Tgt!Marker (label <- s.name)
            }
            rule H2T {
                from h : Src!Holder
                to t : Tgt!TNode (name <- 'one', kids <- h.items->collect(i | thisModule.Copy(i)))
            }
            """)
        let labels = await fixture.targets("Marker").compactMap { $0.eGet("label") as? String }
        #expect(labels == ["beta", "gamma"])
    }

    @Test("Called rules with to and do sections return their created element")
    func calledRuleWithDo() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule Make(n : String) {
                to t : Tgt!TNode (name <- n)
                do { t.tag <- 'made'; }
            }
            rule H2T {
                from h : Src!Holder
                to t : Tgt!TNode (name <- 'holder', next <- thisModule.Make('created'))
            }
            """)
        let holder = try #require(await fixture.target("TNode", named: "holder"))
        let made = try #require(await fixture.target("TNode", named: "created"))
        #expect(made.eGet("tag") as? String == "made")
        #expect(holder.eGet("next") as? EUUID == made.id)
    }

    @Test("Entry and end point rules run around the matched rules")
    func entryAndEndPoints() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            endpoint rule Finish() {
                to m : Tgt!Marker (label <- 'end')
            }
            entrypoint rule Start() {
                to m : Tgt!Marker (label <- 'start')
            }
            rule N2T {
                from s : Src!Node (s.name = 'alpha')
                to t : Tgt!TNode (name <- s.name, tag <- 'matched')
            }
            """)
        let objects = await fixture.targetResource.getAllObjects().compactMap { $0 as? DynamicEObject }
        let labels = objects.map { $0.eGet("label") as? String ?? $0.eClass.name }
        #expect(labels.filter { $0 == "start" || $0 == "end" } == ["start", "end"])
        #expect(labels.last == "end")
        #expect(labels.count == 3)
    }

    @Test("Entry points may refer to elements created by matched rules")
    func entryPointSeesMatches() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            entrypoint rule Start() {
                to t : Tgt!TNode (name <- 'start', next <- thisModule.resolveTemp(thisModule.first(), 't'))
            }
            helper def: first() : Src!Node = Src!Node.allInstances()->first();
            rule N2T {
                from s : Src!Node
                to t : Tgt!TNode (name <- s.name)
            }
            """)
        let start = try #require(await fixture.target("TNode", named: "start"))
        let first = start.eGet("next") as? EUUID
        #expect(first != nil)
        #expect(await fixture.targetResource.getObject(first!) != nil)
    }

    @Test("A called rule with parameters cannot be an entry point")
    func entryPointParameters() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        await #expect(throws: ATLExecutionError.self) {
            try await fixture.run(
                """
                entrypoint rule Start(n : String) {
                    to m : Tgt!Marker (label <- n)
                }
                """)
        }
    }
}

// MARK: - Imperative Blocks

@Suite("ATL VM Imperative Blocks")
@MainActor
struct ATLImperativeBlockTests {

    @Test("do blocks assign target features, declare variables and loop")
    func statements() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule N2T {
                from s : Src!Node (s.name = 'alpha')
                to t : Tgt!TNode (name <- s.name)
                do {
                    c : Integer = 0;
                    for (k in s.kids) { c <- c + 1; }
                    if (c > 1) { t.tag <- 'many'; } else { t.tag <- 'few'; }
                    t.count <- c;
                }
            }
            """)
        let alpha = try #require(await fixture.target("TNode", named: "alpha"))
        #expect(alpha.eGet("count") as? Int == 2)
        #expect(alpha.eGet("tag") as? String == "many")
    }

    @Test("The else branch runs when the condition does not hold")
    func elseBranch() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule N2T {
                from s : Src!Node (s.name = 'beta')
                to t : Tgt!TNode (name <- s.name)
                do {
                    if (s.age > 100) { t.tag <- 'old'; }
                    else if (s.age > 15) { t.tag <- 'middle'; }
                    else { t.tag <- 'young'; }
                }
            }
            """)
        #expect(await fixture.target("TNode", named: "beta")?.eGet("tag") as? String == "middle")
    }

    @Test("Assignments in do blocks resolve source elements to targets")
    func assignmentResolves() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule N2T {
                from s : Src!Node
                to t : Tgt!TNode (name <- s.name)
                do { t.next <- s.next; }
            }
            """)
        let alpha = try #require(await fixture.target("TNode", named: "alpha"))
        let beta = try #require(await fixture.target("TNode", named: "beta"))
        #expect(alpha.eGet("next") as? EUUID == beta.id)
    }

    @Test("Expression statements invoke called rules")
    func expressionStatements() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule Make(n : String) {
                to m : Tgt!Marker (label <- n)
            }
            rule H2T {
                from h : Src!Holder
                to t : Tgt!TNode (name <- 'holder')
                do {
                    for (i in h.items) { thisModule.Make(i.name); }
                }
            }
            """)
        let labels = await fixture.targets("Marker").compactMap { $0.eGet("label") as? String }
        #expect(labels == ["alpha", "beta", "gamma", "special"])
    }

    @Test("do blocks see the target variable's current state")
    func targetStateVisible() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule N2T {
                from s : Src!Node (s.name = 'alpha')
                to t : Tgt!TNode (name <- s.name)
                do {
                    t.tag <- t.name + '!';
                }
            }
            """)
        #expect(await fixture.target("TNode", named: "alpha")?.eGet("tag") as? String == "alpha!")
    }

    @Test("Assigning an undeclared variable fails")
    func undeclaredVariable() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        await #expect(throws: ATLExecutionError.self) {
            try await fixture.run(
                """
                rule N2T {
                    from s : Src!Node
                    to t : Tgt!TNode (name <- s.name)
                    do { missing <- 1; }
                }
                """)
        }
    }

    @Test("Assigning a feature of a source element fails")
    func assignToSource() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        await #expect(throws: ATLExecutionError.self) {
            try await fixture.run(
                """
                rule N2T {
                    from s : Src!Node
                    to t : Tgt!TNode (name <- s.name)
                    do { s.name <- 'changed'; }
                }
                """)
        }
    }

    @Test("Assigning an unknown feature fails")
    func unknownFeature() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        await #expect(throws: ATLExecutionError.self) {
            try await fixture.run(
                """
                rule N2T {
                    from s : Src!Node
                    to t : Tgt!TNode (name <- s.name)
                    do { t.nothing <- 'x'; }
                }
                """)
        }
    }

    @Test("A for loop over an undefined value runs no iterations")
    func loopOverUndefined() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule N2T {
                from s : Src!Node (s.name = 'beta')
                to t : Tgt!TNode (name <- s.name)
                do { for (k in s.next) { t.tag <- 'looped'; } }
            }
            """)
        #expect(await fixture.target("TNode", named: "beta")?.eGet("tag") == nil)
    }

    @Test(":= assigns variables")
    func colonEqualsAssignment() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule N2T {
                from s : Src!Node (s.name = 'beta')
                to t : Tgt!TNode (name <- s.name)
                do {
                    n : Integer <- 1;
                    n := n + 41;
                    t.count <- n;
                }
            }
            """)
        #expect(await fixture.target("TNode", named: "beta")?.eGet("count") as? Int == 42)
    }
}

// MARK: - using

@Suite("ATL VM using Variables")
@MainActor
struct ATLUsingTests {

    @Test("using variables are visible to bindings and do blocks")
    func visibleToBindingsAndDo() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule N2T {
                from s : Src!Node (s.name = 'beta')
                using {
                    double : Integer = s.age * 2;
                    label : String = s.name + '-label';
                }
                to t : Tgt!TNode (name <- label, count <- double)
                do { t.tag <- label + '/' + double.toString(); }
            }
            """)
        let beta = try #require(await fixture.target("TNode", named: "beta-label"))
        #expect(beta.eGet("count") as? Int == 40)
        #expect(beta.eGet("tag") as? String == "beta-label/40")
    }

    @Test("using variables are not visible to the guard")
    func notVisibleToGuard() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        // The guard cannot see 'double'; a failing guard evaluation aborts the run
        await #expect(throws: ATLExecutionError.self) {
            try await fixture.run(
                """
                rule N2T {
                    from s : Src!Node (double > 1)
                    using { double : Integer = s.age * 2; }
                    to t : Tgt!TNode (name <- s.name)
                }
                """)
        }
    }

    @Test("using variables are available to lazy and called rules")
    func calledRuleUsing() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            lazy rule Copy {
                from s : Src!Node
                using { shout : String = s.name + '!'; }
                to t : Tgt!Marker (label <- shout)
            }
            rule H2T {
                from h : Src!Holder
                to t : Tgt!TNode (name <- 'one', kids <- h.items->collect(i | thisModule.Copy(i)))
            }
            """)
        let labels = await fixture.targets("Marker").compactMap { $0.eGet("label") as? String }
        #expect(labels == ["alpha!", "beta!", "gamma!", "special!"])
    }
}

// MARK: - Rule Inheritance

@Suite("ATL VM Rule Inheritance")
@MainActor
struct ATLRuleInheritanceTests {

    @Test("Abstract rules do not match on their own")
    func abstractDoesNotMatch() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            abstract rule Base {
                from s : Src!Node
                to t : Tgt!TNode (name <- s.name, tag <- 'base')
            }
            """)
        #expect(await fixture.targets("TNode").isEmpty)
    }

    @Test("Sub-rules inherit bindings, override them and add their own")
    func inheritsAndOverrides() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            abstract rule Base {
                from s : Src!Node
                to t : Tgt!TNode (name <- s.name, tag <- 'base')
            }
            rule Sub extends Base {
                from sp : Src!Special
                to t : Tgt!TNode (tag <- 'special', count <- sp.age)
            }
            """)
        let created = await fixture.targets("TNode")
        #expect(created.count == 1)
        let element = try #require(created.first)
        #expect(element.eGet("name") as? String == "special")
        #expect(element.eGet("tag") as? String == "special")
        #expect(element.eGet("count") as? Int == 5)
    }

    @Test("Only the most specific matching rule is applied")
    func mostSpecificApplies() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule Plain {
                from n : Src!Node
                to t : Tgt!TNode (name <- n.name, tag <- 'node')
            }
            rule Sub extends Plain {
                from sp : Src!Special
                to t : Tgt!TNode (tag <- 'special')
            }
            """)
        let created = await fixture.targets("TNode")
        #expect(created.count == 5 - 1)
        #expect(await fixture.target("TNode", named: "special")?.eGet("tag") as? String == "special")
        #expect(await fixture.target("TNode", named: "alpha")?.eGet("tag") as? String == "node")
    }

    @Test("The super rule applies when the sub-rule's guard fails")
    func superRuleFallsBack() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            rule Plain {
                from n : Src!Node
                to t : Tgt!TNode (name <- n.name, tag <- 'node')
            }
            rule Sub extends Plain {
                from sp : Src!Special (sp.age > 10)
                to t : Tgt!TNode (tag <- 'special')
            }
            """)
        #expect(await fixture.target("TNode", named: "special")?.eGet("tag") as? String == "node")
    }

    @Test("The super rule's guard also applies to the sub-rule")
    func superGuardApplies() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            abstract rule Base {
                from n : Src!Node (n.age > 10)
                to t : Tgt!TNode (name <- n.name)
            }
            rule Sub extends Base {
                from sp : Src!Special
                to t : Tgt!TNode (tag <- 'special')
            }
            """)
        #expect(await fixture.targets("TNode").isEmpty)
    }

    @Test("Sub-rules add target patterns and inherit do blocks and using variables")
    func extraPatternsAndBlocks() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            abstract rule Base {
                from n : Src!Node
                using { shout : String = n.name + '!'; }
                to t : Tgt!TNode (name <- shout)
                do { t.tag <- 'base-do'; }
            }
            rule Sub extends Base {
                from sp : Src!Special
                to extra : Tgt!Marker (label <- shout)
                do { t.count <- 7; }
            }
            """)
        let element = try #require(await fixture.target("TNode", named: "special!"))
        #expect(element.eGet("tag") as? String == "base-do")
        #expect(element.eGet("count") as? Int == 7)
        #expect(await fixture.targets("Marker").first?.eGet("label") as? String == "special!")
    }

    @Test("resolveTemp finds inherited and own target patterns")
    func resolveTempInherited() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        try await fixture.run(
            """
            abstract rule Base {
                from n : Src!Node
                to t : Tgt!TNode (name <- n.name)
            }
            rule Sub extends Base {
                from sp : Src!Special
                to extra : Tgt!Marker (label <- sp.name)
            }
            rule L2T {
                from l : Src!Leaf (l.name = 'alpha')
                to t : Tgt!TLeaf (name <- 'x')
            }
            rule H2T {
                from h : Src!Holder
                to t : Tgt!TNode (
                    name <- 'holder',
                    next <- thisModule.resolveTemp(h.items->last(), 't'),
                    leaf <- thisModule.resolveTemp(h.items->last(), 'extra')
                )
            }
            """)
        let holder = try #require(await fixture.target("TNode", named: "holder"))
        let special = try #require(await fixture.target("TNode", named: "special"))
        #expect(holder.eGet("next") as? EUUID == special.id)
        let marker = try #require(await fixture.targets("Marker").first)
        #expect(holder.eGet("leaf") as? EUUID == marker.id)
    }

    @Test("Extending an unknown rule fails")
    func unknownSuperRule() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        await #expect(throws: ATLExecutionError.self) {
            try await fixture.run(
                """
                rule Sub extends Missing {
                    from s : Src!Special
                    to t : Tgt!TNode (name <- s.name)
                }
                """)
        }
    }

    @Test("A sub-rule whose source type does not conform to its super rule's fails")
    func nonConformingSourceType() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        await #expect(throws: ATLExecutionError.self) {
            try await fixture.run(
                """
                rule Plain {
                    from n : Src!Node
                    to t : Tgt!TNode (name <- n.name)
                }
                rule Sub extends Plain {
                    from l : Src!Leaf
                    to t : Tgt!TNode (tag <- 'leaf')
                }
                """)
        }
    }

    @Test("Circular extends relationships fail")
    func circularExtends() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        await #expect(throws: ATLExecutionError.self) {
            try await fixture.run(
                """
                rule A extends B {
                    from s : Src!Node
                    to t : Tgt!TNode (name <- s.name)
                }
                rule B extends A {
                    from s : Src!Node
                    to t : Tgt!TNode (name <- s.name)
                }
                """)
        }
    }
}

// MARK: - Reference Storage

@Suite("ATL Reference Storage")
@MainActor
struct ATLReferenceStorageTests {

    @Test("The first root element is addressed as the document root")
    func rootFragment() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        #expect(await ATLReferenceStorage.fragment(for: fixture.holder, in: fixture.sourceResource) == "/")
    }

    @Test("Contained elements are addressed by their containment path")
    func containedFragment() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        #expect(
            await ATLReferenceStorage.fragment(for: fixture.gamma, in: fixture.sourceResource)
                == "//@items.2")
    }

    @Test("Elements that cannot be located are addressed by identifier")
    func uncontainedFragment() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        let loose = try #require(
            DynamicEObject(eClass: fixture.source.getClassifier("Leaf") as! EClass) as DynamicEObject?)
        await fixture.sourceResource.register(loose)
        #expect(
            await ATLReferenceStorage.fragment(for: loose, in: fixture.sourceResource)
                == loose.id.uuidString)
    }
}

// MARK: - Parsing

@Suite("ATL Rule Declaration Parsing")
struct ATLRuleDeclarationParsingTests {

    private func parse(_ body: String) async throws -> ATLModule {
        try await ATLParser().parseContent(
            "module Test;\ncreate OUT : Tgt from IN : Src;\n" + body)
    }

    @Test("Rule modifiers are recorded")
    func modifiers() async throws {
        let module = try await parse(
            """
            unique lazy rule U { from s : Src!A to t : Tgt!B }
            lazy rule L { from s : Src!A to t : Tgt!B }
            entrypoint rule Start() { to t : Tgt!B }
            endpoint rule Finish() { to t : Tgt!B }
            rule Plain(x : Integer) { to t : Tgt!B }
            """)
        let rules = module.calledRules
        #expect(rules["U"]?.isLazy == true && rules["U"]?.isUnique == true)
        #expect(rules["L"]?.isLazy == true && rules["L"]?.isUnique == false)
        #expect(rules["Start"]?.isEntrypoint == true)
        #expect(rules["Finish"]?.isEndpoint == true)
        #expect(rules["Plain"]?.isLazy == false)
        #expect(rules["U"]?.parameters == [ATLParameter(name: "s", type: "Src!A")])
    }

    @Test("Abstract matched rules, extends and several source patterns are recorded")
    func matchedRuleDetails() async throws {
        let module = try await parse(
            """
            abstract rule Base { from s : Src!A to t : Tgt!B }
            rule Sub extends Base { from a : Src!A, b : Src!C (a.x = b.x) to t : Tgt!B }
            """)
        let base = try #require(module.matchedRules.first)
        let sub = try #require(module.matchedRules.last)
        #expect(base.isAbstract && base.superRuleName == nil)
        #expect(!sub.isAbstract && sub.superRuleName == "Base")
        #expect(sub.sourcePatterns.map(\.variableName) == ["a", "b"])
        #expect(sub.additionalSourcePatterns.first?.guard != nil)
    }

    @Test("using sections and do blocks are parsed")
    func usingAndDo() async throws {
        let module = try await parse(
            """
            rule R {
                from s : Src!A
                using { x : Integer = 1; y = 2; }
                to t : Tgt!B (name <- 'n')
                do {
                    v : Integer = 0;
                    v <- 1;
                    t.name <- 'a';
                    if (v > 0) { v <- 2; } else if (v < 0) { v <- 3; } else { v <- 4; }
                    for (e in s.items) { v <- v + 1; }
                    thisModule.Other(v);
                }
            }
            """)
        let rule = try #require(module.matchedRules.first)
        #expect(rule.localVariables.map(\.name) == ["x", "y"])
        #expect(rule.localVariables.map(\.type) == ["Integer", nil])
        #expect(rule.doStatements.count == 6)
        #expect(rule.doStatements[0] is ATLVariableDeclarationStatement)
        #expect(rule.doStatements[1] is ATLAssignmentStatement)
        #expect(rule.doStatements[3] is ATLConditionalStatement)
        #expect(rule.doStatements[4] is ATLForStatement)
        #expect(rule.doStatements[5] is ATLExpressionStatement)
    }

    @Test("Called rules may consist of a do block only")
    func doOnlyCalledRule() async throws {
        let module = try await parse("rule Run(n : Integer) { do { thisModule.Other(n); } }")
        #expect(module.calledRules["Run"]?.body.count == 1)
    }

    @Test("Malformed declarations are rejected")
    func malformed() async throws {
        await #expect(throws: ATLParseError.self) {
            _ = try await parse("lazy rule L extends B { from s : Src!A to t : Tgt!B }")
        }
        await #expect(throws: ATLParseError.self) {
            _ = try await parse("rule R(x : Integer) extends B { to t : Tgt!B }")
        }
        await #expect(throws: ATLParseError.self) {
            _ = try await parse("lazy rule L { to t : Tgt!B }")
        }
        await #expect(throws: ATLParseError.self) {
            _ = try await parse("rule R { to t : Tgt!B }")
        }
        await #expect(throws: ATLParseError.self) {
            _ = try await parse("rule R { from s : Src!A }")
        }
        await #expect(throws: ATLParseError.self) {
            _ = try await parse("rule R { from s : Src!A to t : Tgt!B do { 1 + 1 <- 2; } }")
        }
        await #expect(throws: ATLParseError.self) {
            _ = try await parse("rule R { from s : Src!A using { x 1; } to t : Tgt!B }")
        }
        await #expect(throws: ATLParseError.self) {
            _ = try await parse("rule R { from s : Src!A to t : Tgt!B do { for x in y { } } }")
        }
    }

    @Test("Equal rules compare equal and differ in modifiers")
    func equality() async throws {
        let first = try await parse("lazy rule L { from s : Src!A to t : Tgt!B }")
        let second = try await parse("unique lazy rule L { from s : Src!A to t : Tgt!B }")
        #expect(first.calledRules["L"] != second.calledRules["L"])
        #expect(first.calledRules["L"] == first.calledRules["L"])
        let matched = try await parse("abstract rule R { from s : Src!A to t : Tgt!B }")
        let plain = try await parse("rule R { from s : Src!A to t : Tgt!B }")
        #expect(matched.matchedRules.first != plain.matchedRules.first)
        #expect(matched.matchedRules.first?.hashValue != plain.matchedRules.first?.hashValue)
    }
}

// MARK: - Statement Execution and Trace State

@Suite("ATL Statement Execution")
@MainActor
struct ATLStatementExecutionTests {

    private func makeContext(_ fixture: SemanticsFixture) async throws -> ATLExecutionContext {
        ATLExecutionContext(
            module: try await fixture.module(""),
            sources: ["IN": fixture.sourceResource],
            targets: ["OUT": fixture.targetResource],
            executionEngine: ECoreExecutionEngine(models: [:])
        )
    }

    @Test("Assigning a feature of an undefined element fails")
    func undefinedOwner() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        let context = try await makeContext(fixture)
        context.setVariable("t", value: nil)
        let statement = ATLAssignmentStatement(
            target: .feature(owner: ATLVariableExpression(name: "t"), name: "name"),
            value: ATLLiteralExpression(value: "x"))
        await #expect(throws: ATLExecutionError.self) { try await statement.execute(in: context) }
    }

    @Test("Assigning a feature of a value that is not an element fails")
    func nonElementOwner() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        let context = try await makeContext(fixture)
        context.setVariable("t", value: "text")
        let statement = ATLAssignmentStatement(
            target: .feature(owner: ATLVariableExpression(name: "t"), name: "name"),
            value: ATLLiteralExpression(value: "x"))
        await #expect(throws: ATLExecutionError.self) { try await statement.execute(in: context) }
    }

    @Test("Variable assignment updates the scope that declared the variable")
    func assignsOuterScope() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        let context = try await makeContext(fixture)
        context.setVariable("n", value: 1)
        context.pushScope()
        try context.assignVariable("n", value: 2)
        context.popScope()
        #expect(try context.getVariable("n") as? Int == 2)
        #expect(throws: ATLExecutionError.self) { try context.assignVariable("missing", value: 1) }
    }

    @Test("Variable declarations without an initialiser start undefined")
    func declarationWithoutInitialiser() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        let context = try await makeContext(fixture)
        try await ATLVariableDeclarationStatement(name: "v", type: "Integer").execute(in: context)
        #expect(try context.getVariable("v") == nil)
    }

    @Test("A for loop treats a single value as a collection of one")
    func loopOverSingleValue() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        let context = try await makeContext(fixture)
        context.setVariable("count", value: 0)
        let loop = ATLForStatement(
            variable: "x",
            collection: ATLLiteralExpression(value: 5),
            body: [
                ATLAssignmentStatement(
                    target: .variable("count"),
                    value: ATLBinaryExpression(
                        left: ATLVariableExpression(name: "count"), operator: .plus,
                        right: ATLVariableExpression(name: "x")))
            ])
        try await loop.execute(in: context)
        #expect(try context.getVariable("count") as? Int == 5)
    }

    @Test("Trace links can be queried by source tuple and pattern name")
    func traceLinkQueries() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        let context = try await makeContext(fixture)
        let first = EUUID(), second = EUUID(), target = EUUID(), other = EUUID()
        context.addTraceLink(
            ATLTraceLink(
                ruleName: "R", sourceElement: first, targetElements: [target, other],
                additionalSourceElements: [second], targetNames: ["a", "b"]))
        #expect(context.getTraceLinks(forSources: [first, second]).count == 1)
        #expect(context.getTraceLinks(forSources: [first]).isEmpty)
        #expect(context.getTraceLinks(forSources: []).isEmpty)
        #expect(context.getTraceLinks(for: first).first?.targetID(named: "b") == other)
        #expect(context.getTraceLinks(for: first).first?.targetID(named: "c") == nil)
        #expect(context.defaultTargetID(for: first) == nil)
        context.addTraceLink(ruleName: "S", sourceElement: second, targetElements: [target])
        #expect(context.defaultTargetID(for: second) == target)
        context.resetTransformationState()
        #expect(context.getTraceLinks(for: second).isEmpty)
    }

    @Test("Running a transformation twice does not accumulate state")
    func rerun() async throws {
        var fixture = SemanticsFixture()
        await fixture.populate()
        let module = try await fixture.module(
            """
            unique lazy rule Copy {
                from s : Src!Node
                to t : Tgt!Marker (label <- s.name)
            }
            rule H2T {
                from h : Src!Holder
                to t : Tgt!TNode (name <- 'one', kids <- h.items->collect(i | thisModule.Copy(i)))
            }
            """)
        let vm = ATLVirtualMachine(module: module)
        for _ in 0..<2 {
            let target = Resource(uri: "test://target")
            try await vm.execute(
                sources: ["IN": fixture.sourceResource], targets: ["OUT": target])
            let markers = await target.getAllObjects().filter { $0.eClass.name == "Marker" }
            #expect(markers.count == 4)
        }
        let stats = vm.getStatistics()
        #expect(stats.elementsCreated == 5)
        #expect(stats.traceLinksCreated == 5)
    }
}
