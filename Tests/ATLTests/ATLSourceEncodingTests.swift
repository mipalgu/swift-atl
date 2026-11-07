//
//  ATLSourceEncodingTests.swift
//  ATLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import EMFBase
import Foundation
import Testing

@testable import ATL

/// Tests for the character encodings in which the parser reads ATL source files.
///
/// A file is read as UTF-8; a file that is not valid UTF-8 is read as ISO-8859-1 with a
/// warning, and an explicit encoding is used alone.
@Suite("ATL source encodings")
struct ATLSourceEncodingTests {
    /// The comment whose accented letter makes the source differ between encodings.
    static let comment = "-- Café"

    /// A module whose first line is ``comment``.
    static let source = """
        \(comment)
        module Encoded;
        create OUT : Target from IN : Source;
        helper def : greeting : String = 'café';

        """

    /// Writes bytes to a new temporary ATL file.
    ///
    /// - Parameter bytes: The contents of the file.
    /// - Returns: The location of the file.
    /// - Throws: Any error writing the file.
    static func write(_ bytes: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("Encoded.atl")
        try bytes.write(to: url)
        return url
    }

    /// The source encoded in ISO-8859-1.
    static var latin1Bytes: Data {
        Data(source.unicodeScalars.map { UInt8($0.value) })
    }

    @Test("reads a UTF-8 file without a warning")
    func utf8() async throws {
        let url = try Self.write(Data(Self.source.utf8))
        let parser = ATLParser(options: .standard)

        let module = try await parser.parse(url)

        #expect(module.name == "Encoded")
        #expect(module.helpers["greeting"] != nil)
        #expect(await parser.decodingWarnings.isEmpty)
    }

    @Test("reads a file that is not UTF-8 as ISO-8859-1 with a warning")
    func latin1Fallback() async throws {
        let url = try Self.write(Self.latin1Bytes)
        let parser = ATLParser(options: .standard)

        let module = try await parser.parse(url)

        #expect(module.name == "Encoded")
        let warnings = await parser.decodingWarnings
        #expect(warnings.count == 1)
        #expect(warnings.first?.code == TextDecodingDiagnostic.decodedAsISOLatin1)
        #expect(warnings.first?.severity == .warning)
        #expect(warnings.first?.range?.start.line == 1)
        #expect(warnings.first?.document == url.absoluteString)
    }

    @Test("reads a file in an explicit encoding without a warning")
    func explicitEncoding() async throws {
        let url = try Self.write(Self.latin1Bytes)
        let parser = ATLParser(options: .standard)

        let module = try await parser.parse(url, encoding: .isoLatin1)

        #expect(module.name == "Encoded")
        #expect(await parser.decodingWarnings.isEmpty)
    }

    @Test("rejects a file that is not valid in an explicit encoding")
    func malformedExplicitEncoding() async throws {
        let url = try Self.write(Self.latin1Bytes)
        let parser = ATLParser(options: .standard)

        await #expect {
            _ = try await parser.parse(url, encoding: .usASCII)
        } throws: { error in
            guard case ATLParseError.invalidEncoding = error else { return false }
            return true
        }
    }

    @Test("forgets the warnings of an earlier file")
    func warningsOfLatestFile() async throws {
        let latin1 = try Self.write(Self.latin1Bytes)
        let utf8 = try Self.write(Data(Self.source.utf8))
        let parser = ATLParser(options: .standard)

        _ = try await parser.parse(latin1)
        _ = try await parser.parse(utf8)

        #expect(await parser.decodingWarnings.isEmpty)
    }

    @Test("still reports a missing file as not found")
    func missingFile() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".atl")
        let parser = ATLParser(options: .standard)

        await #expect {
            _ = try await parser.parse(url)
        } throws: { error in
            guard case ATLParseError.fileNotFound(let path) = error else { return false }
            return path == url.path
        }
    }
}
