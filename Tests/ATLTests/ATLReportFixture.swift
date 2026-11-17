//
//  ATLReportFixture.swift
//  ATLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ATL

/// A project metamodel and a report metamodel, with a project model to transform.
///
/// In the `Project` metamodel, a `Project` has a name and contains `Task`s, each with a
/// name and an integer priority. In the `Report` metamodel, a `Document` has a name and
/// attributes of the primitive Ecore types, contains `Summary` elements through the
/// many-valued `summaries` and the single-valued `main` references, and refers to them
/// through the many-valued `highlights` and the single-valued `lead` references. A
/// `Summary` has a title and an integer rank.
///
/// The source model lives in a resource of its own and the target model in a resource
/// set, as they do when the models are given as files.
@MainActor
struct ReportFixture {

    /// The name of the source metamodel.
    static let projectMetamodel = "Project"

    /// The name of the target metamodel.
    static let reportMetamodel = "Report"

    /// The URI of the source model.
    static let sourceURI = "test://project.xmi"

    /// The URI of the target model.
    static let targetURI = "test://report.xmi"

    /// The source metamodel.
    let project: EPackage

    /// The target metamodel.
    let report: EPackage

    /// The `Project` class.
    let projectClass: EClass

    /// The `Task` class.
    let taskClass: EClass

    /// The `Document` class.
    let documentClass: EClass

    /// The `Summary` class.
    let summaryClass: EClass

    /// Creates the metamodels.
    init() {
        func type(_ dataType: EcoreDataType) -> EDataType { EDataType(name: dataType.rawValue) }
        let string = type(.eString)
        let integer = type(.eInt)

        let task = EClass(
            name: "Task",
            eStructuralFeatures: [
                EAttribute(name: "name", eType: string),
                EAttribute(name: "priority", eType: integer),
            ])
        let project = EClass(
            name: "Project",
            eStructuralFeatures: [
                EAttribute(name: "name", eType: string),
                EReference(name: "tasks", eType: task, upperBound: -1, containment: true),
            ])
        self.taskClass = task
        self.projectClass = project
        self.project = EPackage(
            name: Self.projectMetamodel, nsURI: "http://example.org/project", nsPrefix: "project",
            eClassifiers: [project, task])

        let summary = EClass(
            name: "Summary",
            eStructuralFeatures: [
                EAttribute(name: "title", eType: string),
                EAttribute(name: "rank", eType: integer),
            ])
        let document = EClass(
            name: "Document",
            eStructuralFeatures: [
                EAttribute(name: "name", eType: string),
                EAttribute(name: "completionRate", eType: integer),
                EAttribute(name: "total", eType: type(.eLong)),
                EAttribute(name: "ratio", eType: type(.eDouble)),
                EAttribute(name: "weight", eType: type(.eFloat)),
                EAttribute(name: "done", eType: type(.eBoolean)),
                EAttribute(name: "note", eType: EDataType(name: "Note")),
                EAttribute(name: "scores", eType: integer, upperBound: -1),
                EReference(name: "summaries", eType: summary, upperBound: -1, containment: true),
                EReference(name: "main", eType: summary, containment: true),
                EReference(name: "highlights", eType: summary, upperBound: -1),
                EReference(name: "lead", eType: summary),
            ])
        self.summaryClass = summary
        self.documentClass = document
        self.report = EPackage(
            name: Self.reportMetamodel, nsURI: "http://example.org/report", nsPrefix: "report",
            eClassifiers: [document, summary])
    }

    /// Creates a project model with one task per priority.
    ///
    /// The project is named `p` and its tasks `t1`, `t2` and so on, in the order of the
    /// priorities.
    ///
    /// - Parameter priorities: The priority of each task.
    /// - Returns: The resource holding the project.
    func projectModel(priorities: [Int]) async -> Resource {
        let resource = Resource(uri: Self.sourceURI)
        var root = DynamicEObject(eClass: projectClass)
        root.eSet("name", value: "p")
        var taskIDs: [EUUID] = []
        for (index, priority) in priorities.enumerated() {
            var task = DynamicEObject(eClass: taskClass)
            task.eSet("name", value: "t\(index + 1)")
            task.eSet("priority", value: priority)
            await resource.register(task)
            taskIDs.append(task.id)
        }
        await resource.register(root)
        await resource.add(root)
        await resource.eSet(objectId: root.id, feature: "tasks", value: taskIDs)
        return resource
    }

    /// Parses rules into a module that transforms projects into reports.
    ///
    /// - Parameters:
    ///   - rules: The rules and helpers of the module.
    ///   - options: The options of the parser.
    /// - Returns: The module.
    func module(_ rules: String, options: ATLOptions = .standard) async throws -> ATLModule {
        let source = """
            module Project2Report;
            create OUT : \(Self.reportMetamodel) from IN : \(Self.projectMetamodel);
            \(rules)
            """
        let registry = ATLMetamodelRegistry(packages: [project, report])
        return try await ATLParser(options: options).parseContent(source, metamodelRegistry: registry)
    }

    /// Runs rules over a project model.
    ///
    /// - Parameters:
    ///   - rules: The rules and helpers of the module.
    ///   - priorities: The priority of each task of the project.
    ///   - options: The options of the parser and the virtual machine.
    ///   - capture: Receives the lines the run writes to its console.
    /// - Returns: The resource set and resource of the target model, and the machine that ran.
    func run(
        _ rules: String, priorities: [Int] = [], options: ATLOptions = .standard,
        capture: ConsoleCapture = ConsoleCapture()
    ) async throws -> ReportRun {
        let module = try await module(rules, options: options)
        let source = await projectModel(priorities: priorities)
        let targetSet = ResourceSet()
        let target = await targetSet.createResource(uri: Self.targetURI)
        let machine = ATLVirtualMachine(module: module, options: options)
        machine.executionContext.console = capture.console
        try await machine.execute(sources: ["IN": source], targets: ["OUT": target])
        return ReportRun(resourceSet: targetSet, target: target, machine: machine)
    }
}

/// The outcome of running rules over a project model.
@MainActor
struct ReportRun {

    /// The resource set that holds the target model.
    let resourceSet: ResourceSet

    /// The target model.
    let target: Resource

    /// The virtual machine that ran the rules.
    let machine: ATLVirtualMachine

    /// The target elements of a class, in creation order.
    ///
    /// - Parameter className: The name of the class.
    /// - Returns: The elements.
    func elements(_ className: String) async -> [DynamicEObject] {
        await target.getAllObjects().compactMap { $0 as? DynamicEObject }
            .filter { $0.eClass.name == className }
    }

    /// The only `Document` of the target model.
    ///
    /// - Returns: The document.
    /// - Throws: When the target model has no document.
    func document() async throws -> DynamicEObject {
        try #require(await elements("Document").first)
    }

    /// The current value of a feature of a target element.
    ///
    /// - Parameters:
    ///   - feature: The name of the feature.
    ///   - element: The target element.
    /// - Returns: The stored value.
    func value(_ feature: String, of element: DynamicEObject) async -> (any EcoreValue)? {
        await target.eGet(objectId: element.id, feature: feature)
    }

    /// The target model written as XMI in the default layout and in the layout of the
    /// Eclipse Modeling Framework.
    ///
    /// - Returns: The two documents.
    /// - Throws: Serialisation errors.
    func documents() async throws -> [String] {
        [
            try await XMISerializer().serialize(target),
            try await XMISerializer(options: .emf).serialize(target),
        ]
    }
}

/// Describes a thrown error as a user reads it.
///
/// - Parameter body: The code expected to throw.
/// - Returns: The description of the error, or `nil` when nothing was thrown.
@MainActor
func thrownDescription(_ body: () async throws -> Void) async -> String? {
    do {
        try await body()
        return nil
    } catch {
        return description(of: error)
    }
}

/// Describes an error thrown by synchronous code as a user reads it.
///
/// - Parameter body: The code expected to throw.
/// - Returns: The description of the error, or `nil` when nothing was thrown.
@MainActor
func thrownDescription(_ body: () throws -> Void) -> String? {
    do {
        try body()
        return nil
    } catch {
        return description(of: error)
    }
}

/// The description of an error as a user reads it.
///
/// - Parameter error: The error.
/// - Returns: Its localised description, or its text when it has none.
private func description(of error: any Error) -> String {
    (error as? LocalizedError)?.errorDescription ?? "\(error)"
}
