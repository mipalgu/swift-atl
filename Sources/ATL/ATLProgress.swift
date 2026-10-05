//
//  ATLProgress.swift
//  ATL
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// The stages of a transformation run, in the order in which they occur.
public enum ATLProgressPhase: String, Sendable, CaseIterable, Hashable, Comparable {

    /// Matched rules are matched against the source models and their target elements are created.
    case matching

    /// Called rules marked `entrypoint` run.
    case entrypoint

    /// Bindings and imperative blocks of the matched rules are applied.
    case applying

    /// Bindings that could not be evaluated earlier are retried.
    case resolvingBindings

    /// Called rules marked `endpoint` run.
    case endpoint

    /// The transformation has completed successfully.
    case finished

    /// Orders phases by the sequence in which a run passes through them.
    public static func < (lhs: ATLProgressPhase, rhs: ATLProgressPhase) -> Bool {
        allCases.firstIndex(of: lhs)! < allCases.firstIndex(of: rhs)!
    }
}

/// A snapshot of how far a transformation run has advanced.
///
/// Snapshots are delivered to the callback of
/// ``ATLVirtualMachine/execute(sources:targets:parameters:progress:)``. Within one
/// phase `completed` never decreases, and the phases never move backwards. A
/// successful run always ends with a snapshot whose phase is ``ATLProgressPhase/finished``.
public struct ATLProgress: Sendable, Hashable {

    /// The stage the run is in.
    public let phase: ATLProgressPhase

    /// The number of work items of the phase that have been completed.
    public let completed: Int

    /// The number of work items of the phase, or `nil` if it is not known in advance.
    public let total: Int?

    /// The name of the rule being processed, if the phase works rule by rule.
    public let currentRule: String?

    /// The fraction of the phase that is complete, between zero and one.
    ///
    /// The value is `nil` when the total is unknown. A phase without work counts as complete.
    public var fractionCompleted: Double? {
        guard let total else { return nil }
        return total == 0 ? 1 : min(1, Double(completed) / Double(total))
    }

    /// Creates a progress snapshot.
    ///
    /// - Parameters:
    ///   - phase: The stage the run is in.
    ///   - completed: The number of work items completed in the phase.
    ///   - total: The number of work items of the phase, if known.
    ///   - currentRule: The name of the rule being processed, if any.
    public init(
        phase: ATLProgressPhase, completed: Int, total: Int? = nil, currentRule: String? = nil
    ) {
        self.phase = phase
        self.completed = completed
        self.total = total
        self.currentRule = currentRule
    }
}

/// The signature of a callback that receives progress snapshots on the main actor.
public typealias ATLProgressHandler = @MainActor @Sendable (ATLProgress) -> Void

/// Reports progress and keeps a long run cooperative.
///
/// The monitor forwards snapshots to the callback, checks for cancellation at
/// every checkpoint, and gives up the main actor once the time budget since the
/// last suspension has been used, so that a run on the main actor leaves the
/// user interface responsive.
@MainActor
final class ATLRunMonitor {

    /// The longest stretch of work between two suspensions.
    static let defaultYieldBudget: Duration = .milliseconds(10)

    private let handler: ATLProgressHandler?
    private let budget: Duration
    private let clock = ContinuousClock()
    private var lastSuspension: ContinuousClock.Instant

    /// Creates a monitor.
    ///
    /// - Parameters:
    ///   - handler: The callback that receives snapshots, if any.
    ///   - budget: The longest stretch of work between two suspensions.
    init(handler: ATLProgressHandler?, budget: Duration = ATLRunMonitor.defaultYieldBudget) {
        self.handler = handler
        self.budget = budget
        lastSuspension = clock.now
    }

    /// Delivers a snapshot to the callback.
    ///
    /// - Parameters:
    ///   - phase: The stage the run is in.
    ///   - completed: The number of work items completed in the phase.
    ///   - total: The number of work items of the phase, if known.
    ///   - rule: The name of the rule being processed, if any.
    func report(_ phase: ATLProgressPhase, completed: Int, total: Int?, rule: String? = nil) {
        handler?(ATLProgress(phase: phase, completed: completed, total: total, currentRule: rule))
    }

    /// Checks for cancellation and suspends briefly when the time budget is used up.
    ///
    /// - Throws: `CancellationError` if the surrounding task has been cancelled.
    func checkpoint() async throws {
        try Task.checkCancellation()
        guard clock.now - lastSuspension >= budget else { return }
        await Task.yield()
        lastSuspension = clock.now
        try Task.checkCancellation()
    }
}
