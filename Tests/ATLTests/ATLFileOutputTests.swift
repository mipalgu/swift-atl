//
//  ATLFileOutputTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 26/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import OrderedCollections
import Testing

@testable import ATL

/// Extracts the message of an invalid operation error.
private func invalidOperation(_ error: any Error) -> String? {
    guard case .invalidOperation(let message)? = error as? ATLExecutionError else { return nil }
    return message
}

/// Extracts the message of a type error.
private func typeError(_ error: any Error) -> String? {
    guard case .typeError(let message)? = error as? ATLExecutionError else { return nil }
    return message
}

/// Tests for the `writeTo` and `writeToWithCharset` string operations.
@Suite("ATL File Output")
@MainActor
struct ATLFileOutputTests {

    /// Evaluates a query with a file output policy.
    ///
    /// - Parameters:
    ///   - body: The query expression.
    ///   - fileOutput: The policy for the file operations, or `nil` for the default.
    /// - Returns: The value of the query.
    private func evaluate(_ body: String, fileOutput: ATLFileOutputPolicy? = nil) async throws
        -> (any EcoreValue)?
    {
        let unit = try await ATLParser().parseContent("query Q = \(body);")
        let vm =
            fileOutput.map { ATLVirtualMachine(module: unit, fileOutput: $0) }
            ?? ATLVirtualMachine(module: unit)
        return try await vm.evaluateQuery(sources: [:])
    }

    /// Runs a test body with a fresh output directory that is removed afterwards.
    private func withDirectory(_ body: (URL) async throws -> Void) async throws {
        let directory = try QueryFixtures.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try await body(directory)
    }

    /// The bytes of a file.
    private func bytes(_ url: URL) throws -> [UInt8] {
        Array(try Data(contentsOf: url))
    }

    // MARK: Enabling

    @Test("File output is disabled unless the host enables it")
    func disabledByDefault() async throws {
        try await withDirectory { directory in
            let path = directory.appendingPathComponent("out.txt").path
            await #expect {
                try await evaluate("'text'.writeTo('\(path)')")
            } throws: { error in
                let message = invalidOperation(error) ?? ""
                return message.contains("writeTo") && message.contains("disabled")
            }
            #expect(!FileManager.default.fileExists(atPath: path))
        }
        #expect(!ATLFileOutputPolicy.disabled.isEnabled)
        #expect(ATLVirtualMachine(module: try await ATLParser().parseContent("query Q = 1;"))
            .fileOutput == .disabled)
    }

    @Test("A disabled policy rejects writeToWithCharset as well")
    func disabledWithCharset() async throws {
        await #expect {
            try await evaluate("'text'.writeToWithCharset('out.txt', 'UTF-8')")
        } throws: { invalidOperation($0)?.contains("writeToWithCharset") == true }
    }

    @Test("writeTo writes the string under the output directory and returns true")
    func writes() async throws {
        try await withDirectory { directory in
            let value = try await evaluate(
                "'line one\\nline two'.writeTo('out.txt')", fileOutput: .confined(to: directory))
            #expect(value as? Bool == true)
            let text = try String(
                contentsOf: directory.appendingPathComponent("out.txt"), encoding: .utf8)
            #expect(text == "line one\nline two")
        }
    }

    @Test("writeTo creates missing intermediate directories")
    func createsDirectories() async throws {
        try await withDirectory { directory in
            _ = try await evaluate(
                "'x'.writeTo('graphs/dot/out.dot')", fileOutput: .confined(to: directory))
            let url = directory.appendingPathComponent("graphs/dot/out.dot")
            #expect(try String(contentsOf: url, encoding: .utf8) == "x")
        }
    }

    @Test("writeTo replaces an existing file")
    func overwrites() async throws {
        try await withDirectory { directory in
            let url = directory.appendingPathComponent("out.txt")
            try Data("a much longer previous content".utf8).write(to: url)
            _ = try await evaluate("'new'.writeTo('out.txt')", fileOutput: .confined(to: directory))
            #expect(try String(contentsOf: url, encoding: .utf8) == "new")
        }
    }

    @Test("The file output policy can be changed on the virtual machine")
    func settablePolicy() async throws {
        try await withDirectory { directory in
            let unit = try await ATLParser().parseContent("query Q = 'x'.writeTo('set.txt');")
            let vm = ATLVirtualMachine(module: unit)
            vm.fileOutput = .confined(to: directory)
            #expect(vm.fileOutput.baseDirectory != nil)
            #expect(try await vm.evaluateQuery(sources: [:]) as? Bool == true)
            #expect(FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("set.txt").path))
        }
    }

    // MARK: Confinement

    @Test(
        "Paths outside the output directory are rejected",
        arguments: ["../escape.txt", "sub/../../escape.txt", "./../escape.txt", ".", ""])
    func escapes(path: String) async throws {
        try await withDirectory { directory in
            let base = directory.appendingPathComponent("base", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            await #expect {
                try await evaluate("'x'.writeTo('\(path)')", fileOutput: .confined(to: base))
            } throws: { invalidOperation($0)?.contains("'\(path)'") == true }
            #expect(!FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("escape.txt").path))
        }
    }

    @Test("Absolute paths are rejected unless unrestricted paths are allowed")
    func absolutePaths() async throws {
        try await withDirectory { directory in
            let path = directory.appendingPathComponent("absolute.txt").path
            await #expect {
                try await evaluate("'x'.writeTo('\(path)')", fileOutput: .confined(to: directory))
            } throws: { invalidOperation($0)?.contains(path) == true }
            #expect(!FileManager.default.fileExists(atPath: path))

            let value = try await evaluate(
                "'x'.writeTo('\(path)')", fileOutput: .unrestricted(relativeTo: directory))
            #expect(value as? Bool == true)
            #expect(try String(contentsOfFile: path, encoding: .utf8) == "x")
        }
    }

    @Test("Unrestricted paths still resolve relative paths against the base directory")
    func unrestrictedRelative() async throws {
        try await withDirectory { directory in
            let base = directory.appendingPathComponent("base", isDirectory: true)
            let policy = ATLFileOutputPolicy.unrestricted(relativeTo: base)
            #expect(policy.allowsUnrestrictedPaths)
            _ = try await evaluate("'x'.writeTo('../beside.txt')", fileOutput: policy)
            #expect(FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("beside.txt").path))
        }
    }

    @Test("Resolved paths stay inside the output directory")
    func resolution() async throws {
        try await withDirectory { directory in
            let policy = ATLFileOutputPolicy.confined(to: directory)
            let resolved = try policy.resolve("a/./b/../c.txt")
            #expect(resolved.lastPathComponent == "c.txt")
            #expect(resolved.deletingLastPathComponent().lastPathComponent == "a")
            #expect(throws: ATLExecutionError.self) { try ATLFileOutputPolicy.disabled.resolve("x") }
        }
    }

    #if os(Windows)
    @Test(
        "Backslash forms that leave the output directory are rejected on Windows",
        arguments: ["..\\escape.txt", "sub\\..\\..\\escape.txt", ".\\..\\escape.txt", "..\\base\\..\\escape.txt"])
    func windowsEscapes(path: String) async throws {
        try await withDirectory { directory in
            let base = directory.appendingPathComponent("base", isDirectory: true)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            let policy = ATLFileOutputPolicy.confined(to: base)
            #expect {
                try policy.resolve(path)
            } throws: { invalidOperation($0)?.contains("'\(path)'") == true }
        }
    }

    @Test("A backslash separates directories on Windows")
    func windowsSeparator() async throws {
        try await withDirectory { directory in
            let policy = ATLFileOutputPolicy.confined(to: directory)
            let resolved = try policy.resolve("sub\\file.txt")
            #expect(resolved.lastPathComponent == "file.txt")
            #expect(resolved.deletingLastPathComponent().lastPathComponent == "sub")
            let value = try await evaluate(
                "'x'.writeTo('sub\\\\file.txt')", fileOutput: policy)
            #expect(value as? Bool == true)
            #expect(try String(
                contentsOf: directory.appendingPathComponent("sub/file.txt"), encoding: .utf8) == "x")
        }
    }

    @Test("A leading backslash is an absolute path on Windows")
    func windowsLeadingBackslash() throws {
        #expect(ATLFileOutputPolicy.isAbsolutePath("\\share\\file.txt"))
    }
    #else
    @Test("A backslash is an ordinary file name character on this platform")
    func backslashIsFileName() async throws {
        try await withDirectory { directory in
            let policy = ATLFileOutputPolicy.confined(to: directory)
            let resolved = try policy.resolve("a\\b.txt")
            #expect(resolved.lastPathComponent == "a\\b.txt")
            #expect(resolved.deletingLastPathComponent().standardizedFileURL.path
                == directory.standardizedFileURL.path)
            let value = try await evaluate("'x'.writeTo('a\\\\b.txt')", fileOutput: policy)
            #expect(value as? Bool == true)
            #expect(try String(
                contentsOf: directory.appendingPathComponent("a\\b.txt"), encoding: .utf8) == "x")
        }
    }
    #endif

    #if !os(Windows) && !os(WASI)
    @Test("A symbolic link inside the output directory cannot lead outside it")
    func symbolicLinkEscape() async throws {
        try await withDirectory { directory in
            let base = directory.appendingPathComponent("base", isDirectory: true)
            let outside = directory.appendingPathComponent("outside", isDirectory: true)
            let manager = FileManager.default
            try manager.createDirectory(at: base, withIntermediateDirectories: true)
            try manager.createDirectory(at: outside, withIntermediateDirectories: true)
            try manager.createSymbolicLink(
                at: base.appendingPathComponent("link"), withDestinationURL: outside)
            try manager.createSymbolicLink(
                atPath: base.appendingPathComponent("dangling").path,
                withDestinationPath: outside.appendingPathComponent("planted.txt").path)

            for path in ["link/out.txt", "dangling"] {
                await #expect {
                    try await evaluate("'x'.writeTo('\(path)')", fileOutput: .confined(to: base))
                } throws: { invalidOperation($0)?.contains("'\(path)'") == true }
            }
            #expect(try manager.contentsOfDirectory(atPath: outside.path).isEmpty)
        }
    }

    @Test("A symbolic link loop inside the output directory is rejected with the path")
    func symbolicLinkLoop() async throws {
        try await withDirectory { directory in
            let manager = FileManager.default
            try manager.createSymbolicLink(
                atPath: directory.appendingPathComponent("self").path, withDestinationPath: "self")
            try manager.createSymbolicLink(
                atPath: directory.appendingPathComponent("ping").path, withDestinationPath: "pong")
            try manager.createSymbolicLink(
                atPath: directory.appendingPathComponent("pong").path, withDestinationPath: "ping")

            for path in ["self", "ping/out.txt", "pong"] {
                await #expect {
                    try await evaluate("'x'.writeTo('\(path)')", fileOutput: .confined(to: directory))
                } throws: { error in
                    guard let message = invalidOperation(error) else { return false }
                    return message.contains("'\(path)'") && message.contains("symbolic links")
                }
            }
            let contents = try manager.contentsOfDirectory(atPath: directory.path).sorted()
            #expect(contents == ["ping", "pong", "self"])
        }
    }

    @Test("A symbolic link that stays inside the output directory is followed")
    func symbolicLinkInside() async throws {
        try await withDirectory { directory in
            let manager = FileManager.default
            let real = directory.appendingPathComponent("real", isDirectory: true)
            try manager.createDirectory(at: real, withIntermediateDirectories: true)
            try manager.createSymbolicLink(
                at: directory.appendingPathComponent("alias"), withDestinationURL: real)
            _ = try await evaluate("'x'.writeTo('alias/in.txt')", fileOutput: .confined(to: directory))
            #expect(manager.fileExists(atPath: real.appendingPathComponent("in.txt").path))
        }
    }
    #endif

    // MARK: Charsets

    @Test(
        "writeToWithCharset encodes the string in the named charset",
        arguments: [
            ("UTF-8", [0x41, 0xC3, 0xA9]),
            ("utf8", [0x41, 0xC3, 0xA9]),
            ("UTF-16", [0xFE, 0xFF, 0x00, 0x41, 0x00, 0xE9]),
            ("UTF-16BE", [0x00, 0x41, 0x00, 0xE9]),
            ("utf-16le", [0x41, 0x00, 0xE9, 0x00]),
            ("UTF-32", [0x00, 0x00, 0x00, 0x41, 0x00, 0x00, 0x00, 0xE9]),
            ("utf_32", [0x00, 0x00, 0x00, 0x41, 0x00, 0x00, 0x00, 0xE9]),
            ("UTF-32BE", [0x00, 0x00, 0x00, 0x41, 0x00, 0x00, 0x00, 0xE9]),
            ("UTF-32LE", [0x41, 0x00, 0x00, 0x00, 0xE9, 0x00, 0x00, 0x00]),
            ("ISO-8859-1", [0x41, 0xE9]),
            ("latin1", [0x41, 0xE9]),
        ] as [(String, [UInt8])])
    func charsets(charset: String, expected: [UInt8]) async throws {
        try await withDirectory { directory in
            let value = try await evaluate(
                "'A\\u00E9'.writeToWithCharset('out.txt', '\(charset)')",
                fileOutput: .confined(to: directory))
            #expect(value as? Bool == true)
            #expect(try bytes(directory.appendingPathComponent("out.txt")) == expected)
        }
    }

    @Test("US-ASCII writes plain text and rejects characters it cannot encode")
    func ascii() async throws {
        try await withDirectory { directory in
            let policy = ATLFileOutputPolicy.confined(to: directory)
            _ = try await evaluate("'plain'.writeToWithCharset('a.txt', 'US-ASCII')", fileOutput: policy)
            #expect(try bytes(directory.appendingPathComponent("a.txt")) == Array("plain".utf8))
            await #expect {
                try await evaluate("'\\u00E9'.writeToWithCharset('b.txt', 'US-ASCII')", fileOutput: policy)
            } throws: { error in
                guard case .runtimeError(let message)? = error as? ATLExecutionError else {
                    return false
                }
                return message.contains("US-ASCII")
            }
            #expect(!FileManager.default.fileExists(
                atPath: directory.appendingPathComponent("b.txt").path))
        }
    }

    @Test("writeTo writes UTF-8")
    func defaultCharset() async throws {
        try await withDirectory { directory in
            _ = try await evaluate("'\\u00E9'.writeTo('out.txt')", fileOutput: .confined(to: directory))
            #expect(try bytes(directory.appendingPathComponent("out.txt")) == [0xC3, 0xA9])
        }
    }

    @Test("An unknown charset is reported by name")
    func unknownCharset() async throws {
        try await withDirectory { directory in
            await #expect {
                try await evaluate(
                    "'x'.writeToWithCharset('out.txt', 'NO-SUCH-CHARSET')",
                    fileOutput: .confined(to: directory))
            } throws: { invalidOperation($0)?.contains("NO-SUCH-CHARSET") == true }
            #expect(ATLCharset.encoding(named: "NO-SUCH-CHARSET") == nil)
            #expect(ATLCharset.encoding(named: "UTF-8") != nil)
        }
    }

    // MARK: Arguments

    @Test("writeTo requires a String path")
    func pathType() async throws {
        try await withDirectory { directory in
            await #expect {
                try await evaluate("'x'.writeTo(5)", fileOutput: .confined(to: directory))
            } throws: { typeError($0)?.contains("writeTo") == true }
            await #expect {
                try await evaluate(
                    "'x'.writeToWithCharset('a.txt', 8)", fileOutput: .confined(to: directory))
            } throws: { typeError($0)?.contains("writeToWithCharset") == true }
        }
    }

    @Test("writeTo is only offered for strings")
    func receiverType() async throws {
        try await withDirectory { directory in
            await #expect(throws: ATLExecutionError.self) {
                try await evaluate("5.writeTo('out.txt')", fileOutput: .confined(to: directory))
            }
            let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            #expect(contents.isEmpty)
        }
    }

    // MARK: Modules

    @Test("A module writes files from a do block and from a helper")
    func moduleWrites() async throws {
        try await withDirectory { directory in
            let module = try await QueryFixtures.parse(
                QueryFixtures.libraryPath
                    + """
                    module Report;
                    create OUT : Library from IN : Library;

                    helper def : titles : String =
                        Library!Book.allInstances()->iterate(b; t : String = '' | t + b.title + '\\n');

                    helper def : save(name : String, text : String) : Boolean = text.writeTo(name);

                    entrypoint rule Report() {
                        do {
                            thisModule.titles.writeTo('titles.txt');
                            thisModule.save('count.txt', Library!Book.allInstances()->size().toString());
                        }
                    }
                    """)
            let package = try #require(module.sourceMetamodels["IN"])
            let source = try await QueryFixtures.library(conformingTo: package)
            let vm = ATLVirtualMachine(module: module, fileOutput: .confined(to: directory))
            try await vm.execute(sources: ["IN": source], targets: ["OUT": Resource()])
            let titles = try String(
                contentsOf: directory.appendingPathComponent("titles.txt"), encoding: .utf8)
            #expect(titles == "Dune\nEmma\nCosmos\n")
            let count = try String(
                contentsOf: directory.appendingPathComponent("count.txt"), encoding: .utf8)
            #expect(count == "3")
        }
    }

    @Test("A module writes files from a rule binding")
    func bindingWrites() async throws {
        try await withDirectory { directory in
            let module = try await QueryFixtures.parse(
                QueryFixtures.libraryPath
                    + """
                    module Copy;
                    create OUT : Library from IN : Library;

                    rule Book {
                        from b : Library!Book
                        to c : Library!Book (
                            title <- if b.title.writeTo('book-' + b.title + '.txt')
                                then b.title else 'unwritten' endif,
                            pages <- b.pages
                        )
                    }
                    """)
            let package = try #require(module.sourceMetamodels["IN"])
            let source = try await QueryFixtures.library(conformingTo: package)
            let vm = ATLVirtualMachine(module: module, fileOutput: .confined(to: directory))
            let target = Resource()
            try await vm.execute(sources: ["IN": source], targets: ["OUT": target])
            for title in ["Dune", "Emma", "Cosmos"] {
                let url = directory.appendingPathComponent("book-\(title).txt")
                #expect(try String(contentsOf: url, encoding: .utf8) == title)
            }
            let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            #expect(contents.count == 3)
        }
    }

    @Test("A rule binding cannot write files unless the host enables it")
    func bindingDisabled() async throws {
        let module = try await QueryFixtures.parse(
            QueryFixtures.libraryPath
                + """
                module Copy;
                create OUT : Library from IN : Library;

                rule Book {
                    from b : Library!Book
                    to c : Library!Book (
                        title <- if b.title.writeTo('never.txt') then b.title else '' endif
                    )
                }
                """)
        let package = try #require(module.sourceMetamodels["IN"])
        let source = try await QueryFixtures.library(conformingTo: package)
        let vm = ATLVirtualMachine(module: module)
        await #expect {
            try await vm.execute(sources: ["IN": source], targets: ["OUT": Resource()])
        } throws: { invalidOperation($0)?.contains("disabled") == true }
    }

    @Test("A module cannot write files unless the host enables it")
    func moduleDisabled() async throws {
        let module = try await ATLParser().parseContent(
            """
            module Report;
            create OUT : T from IN : S;
            entrypoint rule Report() { do { 'x'.writeTo('never.txt'); } }
            """)
        let vm = ATLVirtualMachine(module: module)
        await #expect {
            try await vm.execute(sources: ["IN": Resource()], targets: ["OUT": Resource()])
        } throws: { invalidOperation($0)?.contains("disabled") == true }
    }
}
