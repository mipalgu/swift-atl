//
//  ATLClock.swift
//  ATL
//
//  Created by Rene Hexel on 24/11/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// The source of the time that the module operation `getCurrentTime()` returns.
///
/// ATL code reads the current time with `thisModule.getCurrentTime()`, which gives the
/// milliseconds since the Unix epoch, 1 January 1970 00:00:00 UTC, as an Integer. A virtual
/// machine, an incremental transformation and an execution context read the time from
/// their clock, which is ``system`` unless the host sets another, so that a host can
/// replay a run or test a transformation with a time of its choice:
///
/// ```swift
/// let machine = ATLVirtualMachine(module: module, options: .standard)
/// machine.clock = .fixed(1_700_000_000_000)
/// ```
public struct ATLClock: Sendable {

    /// Reads the time, in milliseconds since the Unix epoch.
    public let millisecondsSinceEpoch: @Sendable () -> Int

    /// Creates a clock that reads the time with a function.
    ///
    /// - Parameter millisecondsSinceEpoch: Returns the time, in milliseconds since the Unix
    ///   epoch, each time it is called.
    public init(millisecondsSinceEpoch: @escaping @Sendable () -> Int) {
        self.millisecondsSinceEpoch = millisecondsSinceEpoch
    }

    /// The clock of the system, which gives the current time.
    ///
    /// The milliseconds are rounded down to a whole number.  On a platform whose integers
    /// are narrower than 64 bits the count does not fit and wraps around, so that only the
    /// difference between two readings is meaningful there.
    public static let system = ATLClock {
        Int(truncatingIfNeeded: Int64((Date().timeIntervalSince1970 * millisecondsPerSecond).rounded(.down)))
    }

    /// Creates a clock that always gives the same time.
    ///
    /// - Parameter milliseconds: The time to give, in milliseconds since the Unix epoch.
    /// - Returns: The clock.
    public static func fixed(_ milliseconds: Int) -> ATLClock {
        ATLClock { milliseconds }
    }

    /// The number of milliseconds in a second.
    private static let millisecondsPerSecond: Double = 1000
}
