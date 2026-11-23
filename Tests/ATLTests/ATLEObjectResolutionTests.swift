//
//  ATLEObjectResolutionTests.swift
//  ATLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ATL

/// A zoo metamodel that declares a class of its own called `EObject`, and a label metamodel.
///
/// `Zoo!EObject` names the declared class, which `Keeper` extends and `Animal` does not.
@MainActor
struct ZooFixture {
    /// The name of the zoo metamodel.
    static let zooName = "Zoo"

    /// The name of the label metamodel.
    static let labelsName = "Labels"

    let zoo: EPackage
    let labels: EPackage
    let declared: EClass
    let keeper: EClass
    let animal: EClass

    init() {
        let string = EDataType(name: "EString")
        let declared = EClass(
            name: EcoreClassifier.eObject.rawValue, eStructuralFeatures: [EAttribute(name: "name", eType: string)])
        let keeper = EClass(name: "Keeper", eSuperTypes: [declared])
        let animal = EClass(name: "Animal", eStructuralFeatures: [EAttribute(name: "name", eType: string)])
        let label = EClass(name: "Label", eStructuralFeatures: [EAttribute(name: "text", eType: string)])
        self.declared = declared
        self.keeper = keeper
        self.animal = animal
        zoo = EPackage(
            name: Self.zooName, nsURI: "http://example.org/zoo", nsPrefix: "zoo",
            eClassifiers: [declared, keeper, animal])
        labels = EPackage(
            name: Self.labelsName, nsURI: "http://example.org/zoo-labels", nsPrefix: "zl", eClassifiers: [label])
    }

    /// Creates a zoo model with an instance of each class.
    ///
    /// - Returns: The model.
    func source() async -> Resource {
        let resource = Resource(uri: "memory:/zoo.xmi")
        for (name, eClass) in [("thing", declared), ("kim", keeper), ("lion", animal)] {
            var object = DynamicEObject(eClass: eClass)
            object.eSet("name", value: name)
            await resource.add(object)
        }
        return resource
    }

    /// Runs rules and helpers on the zoo model.
    ///
    /// - Parameters:
    ///   - rules: The rules and helpers of the module.
    ///   - options: The options of the parser and the virtual machine.
    /// - Returns: The texts of the labels created, sorted.
    func run(_ rules: String, options: ATLOptions = .standard) async throws -> [String] {
        let registry = ATLMetamodelRegistry(packages: [zoo, labels])
        let module = try await ATLParser(options: options).parseContent(
            """
            module Zoo2Labels;
            create OUT : \(Self.labelsName) from IN : \(Self.zooName);
            \(rules)
            """, metamodelRegistry: registry)
        let target = Resource(uri: "memory:/zoo-labels.xmi")
        try await ATLVirtualMachine(module: module, options: options).execute(
            sources: ["IN": await source()], targets: ["OUT": target])
        return await target.getAllObjects().compactMap { ($0 as? DynamicEObject)?.eGet("text") as? String }.sorted()
    }
}

/// Tests that `MM!EObject` denotes Ecore's `EObject`, the supertype of every class, when the
/// metamodel `MM` declares no class of that name, and the declared class when it does.
@Suite("ATL EObject Resolution Tests")
@MainActor
struct ATLEObjectResolutionTests {

    private let fixture = ReportFixture()

    /// Both presets.
    nonisolated static let presets: [ATLOptions] = [.standard, .legacy]

    /// The rule that labels each element with the class it is transformed by.
    private let labelRule = """
        rule Any {
            from o : Project!EObject
            to t : Report!Summary (title <- o.name)
        }
        """

    /// Runs rules over a project with two tasks.
    ///
    /// - Parameters:
    ///   - rules: The rules and helpers.
    ///   - options: The options of the run.
    /// - Returns: The titles of the summaries, in creation order, and the run.
    private func titles(_ rules: String, options: ATLOptions = .standard) async throws -> ([String], ReportRun) {
        let run = try await fixture.run(rules, priorities: [3, 8], options: options)
        return (await run.elements("Summary").compactMap { $0.eGet("title") as? String }, run)
    }

    /// Evaluates a module-level helper over a project with two tasks.
    ///
    /// - Parameters:
    ///   - declarations: The helpers of the module, one of which is called `probe`.
    ///   - options: The options of the parser and the context.
    /// - Returns: The value of `probe`.
    private func probe(_ declarations: String, options: ATLOptions = .standard) async throws -> (any EcoreValue)? {
        let module = try await fixture.module(declarations, options: options)
        let context = ATLExecutionContext(
            module: module, sources: ["IN": await fixture.projectModel(priorities: [3, 8])], targets: [:],
            executionEngine: ECoreExecutionEngine(models: [:]))
        context.options = options
        return try await context.callHelper("probe", arguments: [])
    }

    // MARK: - A Metamodel Without a Class Called EObject

    @Test("A rule whose source is EObject of a metamodel without such a class matches every element", arguments: presets)
    func ruleOnUndeclaredEObject(options: ATLOptions) async throws {
        let (titles, _) = try await titles(labelRule, options: options)
        #expect(titles == ["p", "t1", "t2"])
    }

    @Test("allInstances of EObject of a metamodel without such a class lists every element", arguments: presets)
    func allInstancesOfUndeclaredEObject(options: ATLOptions) async throws {
        let all = try await probe(
            "helper def : probe : Integer = Project!EObject.allInstances()->size();", options: options)
        #expect(all as? Int == 3)
        let from = try await probe(
            "helper def : probe : Integer = Project!EObject.allInstancesFrom('IN')->size();", options: options)
        #expect(from as? Int == 3)
    }

    @Test("Every element is a kind of EObject of its metamodel, but none is of that type")
    func typeOperationsOnUndeclaredEObject() async throws {
        let kinds = try await probe(
            "helper def : probe : Boolean = Project!Task.allInstances()->forAll(t | t.oclIsKindOf(Project!EObject));")
        #expect(kinds as? Bool == true)
        let types = try await probe(
            "helper def : probe : Boolean = Project!Task.allInstances()->exists(t | t.oclIsTypeOf(Project!EObject));")
        #expect(types as? Bool == false)
        let cast = try await probe(
            "helper def : probe : String = Project!Project.allInstances()->first().oclAsType(Project!EObject).name;")
        #expect(cast as? String == "p")
    }

    @Test("A helper on EObject of a metamodel without such a class applies to every element, after nearer helpers")
    func helperOnUndeclaredEObject() async throws {
        let (titles, _) = try await titles(
            """
            helper context Project!EObject def : kind : String = 'object';
            helper context Project!Task def : kind : String = 'task';
            helper context OclAny def : kind : String = 'any';
            rule Any {
                from o : Project!EObject
                to t : Report!Summary (title <- o.name + ' ' + o.kind)
            }
            """)
        #expect(titles == ["p object", "t1 task", "t2 task"])
    }

    @Test("A helper operation on EObject of a metamodel without such a class applies to every element")
    func helperOperationOnUndeclaredEObject() async throws {
        let (titles, _) = try await titles(
            """
            helper context Project!EObject def : describe(prefix : String) : String = prefix + self.name;
            rule Any {
                from o : Project!EObject
                to t : Report!Summary (title <- o.describe('-'))
            }
            """)
        #expect(titles == ["-p", "-t1", "-t2"])
    }

    @Test("A rule on a class can extend a rule on EObject of a metamodel without such a class")
    func subRuleOfUndeclaredEObjectRule() async throws {
        let (titles, _) = try await titles(
            """
            rule Any {
                from o : Project!EObject
                to t : Report!Summary (title <- 'object ' + o.name)
            }
            rule Tasks extends Any {
                from o : Project!Task
                to t : Report!Summary (title <- 'task ' + o.name)
            }
            """)
        #expect(titles == ["object p", "task t1", "task t2"])
    }

    @Test("An incremental transformation matches a new element with a rule on EObject")
    func incrementalUndeclaredEObject() async throws {
        let module = try await fixture.module(labelRule)
        let source = await fixture.projectModel(priorities: [3])
        let target = await ResourceSet().createResource(uri: ReportFixture.targetURI)
        let transformation = ATLIncrementalTransformation(module: module, options: .standard)
        try await transformation.execute(sources: ["IN": source], targets: ["OUT": target])
        #expect(transformation.matchCount == 2)
        let project = try #require(await source.getAllObjects().first { $0.eClass.name == "Project" })
        var task = DynamicEObject(eClass: fixture.taskClass)
        task.eSet("name", value: "t9")
        try await source.eAdd(objectId: project.id, feature: "tasks", value: task, at: 0)
        let report = try await transformation.update()
        #expect(report.matchesAdded == 1)
        let titles = await target.getAllObjects().compactMap { ($0 as? DynamicEObject)?.eGet("title") as? String }
        #expect(titles.sorted() == ["p", "t1", "t9"])
    }

    // MARK: - A Metamodel That Declares a Class Called EObject

    @Test("A rule on a declared class called EObject matches only its instances and those of its subclasses")
    func ruleOnDeclaredEObject() async throws {
        let texts = try await ZooFixture().run(
            """
            rule Things {
                from o : Zoo!EObject
                to l : Labels!Label (text <- o.name)
            }
            """)
        #expect(texts == ["kim", "thing"])
    }

    @Test("allInstances and the type operations of a declared class called EObject concern only that class")
    func typeOperationsOnDeclaredEObject() async throws {
        let texts = try await ZooFixture().run(
            """
            helper def : count : Integer = Zoo!EObject.allInstances()->size();
            rule Animals {
                from a : Zoo!Animal
                to l : Labels!Label (
                    text <- thisModule.count.toString() + ' ' + a.oclIsKindOf(Zoo!EObject).toString()
                        + ' ' + a.oclIsKindOf(ECORE!EObject).toString())
            }
            rule Keepers {
                from k : Zoo!Keeper
                to l : Labels!Label (text <- k.oclIsKindOf(Zoo!EObject).toString())
            }
            """)
        #expect(texts == ["2 false true", "true"])
    }

    @Test("A helper on a declared class called EObject applies only to its instances and those of its subclasses")
    func helperOnDeclaredEObject() async throws {
        let texts = try await ZooFixture().run(
            """
            helper context Zoo!EObject def : kind : String = 'declared';
            helper context OclAny def : kind : String = 'any';
            rule Keepers {
                from k : Zoo!Keeper
                to l : Labels!Label (text <- k.name + ' ' + k.kind)
            }
            rule Animals {
                from a : Zoo!Animal
                to l : Labels!Label (text <- a.name + ' ' + a.kind)
            }
            """)
        #expect(texts == ["kim declared", "lion any"])
    }

    @Test("Only Ecore's EObject is the supertype of every class")
    func universalEObject() {
        let zoo = ZooFixture()
        #expect(ATLTypeMatching.isUniversal(EcorePackage.metaClass(.eObject)))
        #expect(!ATLTypeMatching.isUniversal(zoo.declared))
        #expect(ATLTypeMatching.conforms(zoo.animal, to: EcorePackage.metaClass(.eObject)))
        #expect(ATLTypeMatching.conforms(zoo.keeper, to: zoo.declared))
        #expect(!ATLTypeMatching.conforms(zoo.animal, to: zoo.declared))
    }
}
