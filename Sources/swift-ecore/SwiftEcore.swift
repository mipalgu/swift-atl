//
// SwiftEcore.swift
// SwiftEcore
//
//  Created by Rene Hexel on 3/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import ArgumentParser
import SwiftEcore

@main
struct SwiftEcoreCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-ecore",
        abstract: "Swift Ecore - Eclipse Modeling Framework for Swift",
        version: "0.1.0"
    )

    func run() throws {
        print("Swift Ecore v0.1.0")
        print("Type 'swift-ecore --help' for usage information.")
    }
}
