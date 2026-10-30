//
//  ATLOptionsSemanticsTests.swift
//  ATLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import Foundation
import Testing

@testable import ATL

@Suite("ATL Options from Semantics")
struct ATLOptionsSemanticsTests {
    /// The name of the environment variable, as documented.
    private let variable = "SWIFT_MODELLING_SEMANTICS"

    @Test("Each semantics selects its preset")
    func presets() {
        #expect(ATLOptions(semantics: .standard) == .standard)
        #expect(ATLOptions(semantics: .legacy) == .legacy)
    }

    @Test("The environment selects the preset", arguments: ModellingSemantics.allCases)
    func environment(semantics: ModellingSemantics) throws {
        #expect(try ATLOptions.fromEnvironment([variable: semantics.rawValue]) == ATLOptions(semantics: semantics))
    }

    @Test("Without a choice in the environment, the options are standard")
    func unset() throws {
        #expect(try ATLOptions.fromEnvironment([:]) == .standard)
        #expect(try ATLOptions.fromEnvironment([variable: ""]) == .standard)
    }

    @Test("An invalid value in the environment is an error")
    func invalid() {
        #expect(throws: ModellingSemanticsError.invalidValue("eclipse", variable: variable)) {
            try ATLOptions.fromEnvironment([variable: "eclipse"])
        }
    }

    @Test("The process environment is read by default")
    func processEnvironment() throws {
        let expected = try ATLOptions.fromEnvironment(ProcessInfo.processInfo.environment)
        #expect(try ATLOptions.fromEnvironment() == expected)
    }
}
