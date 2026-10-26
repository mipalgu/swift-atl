//
//  ATLFileOutput.swift
//  ATL
//
//  Created by Rene Hexel on 26/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation

/// Where the `writeTo` and `writeToWithCharset` string operations may write files.
///
/// ATL strings can write themselves to a file with `writeTo(path)` and
/// `writeToWithCharset(path, charset)`. Because a transformation or query may come
/// from anywhere, writing files is disabled unless the host that runs it enables it
/// with a policy:
///
/// - ``disabled`` (the default) makes both operations fail with an execution error.
/// - ``confined(to:)`` resolves relative paths against a base directory and rejects
///   absolute paths and every path that leads outside the base directory, whether
///   through `..` components or through symbolic links.
/// - ``unrestricted(relativeTo:)`` resolves relative paths against a base directory
///   and accepts any other path, including absolute ones.
///
/// Confinement protects against the transformation itself, not against other
/// processes that can change the output directory while the transformation runs, so
/// the output directory should not be writable by untrusted users. On Windows a
/// backslash separates path components like a slash.
///
/// Missing intermediate directories are created and an existing file is replaced,
/// as Eclipse ATL does. The string is written exactly as it is, without a trailing
/// line break.
///
/// ## Example
///
/// ```swift
/// let vm = ATLVirtualMachine(
///     module: query, fileOutput: .confined(to: URL(fileURLWithPath: "output")))
/// ```
public struct ATLFileOutputPolicy: Sendable, Hashable {

    /// The directory that relative paths are resolved against, or `nil` when writing is disabled.
    public let baseDirectory: URL?

    /// Whether paths outside the base directory, including absolute paths, are accepted.
    public let allowsUnrestrictedPaths: Bool

    /// Whether files may be written at all.
    public var isEnabled: Bool { baseDirectory != nil }

    /// The policy that rejects every attempt to write a file.
    public static let disabled = ATLFileOutputPolicy(baseDirectory: nil, allowsUnrestrictedPaths: false)

    /// Creates a policy that writes files only inside a directory.
    ///
    /// Relative paths are resolved against the directory. Absolute paths, and
    /// relative paths that lead outside the directory after `.` and `..` components
    /// and symbolic links have been resolved, are rejected.
    ///
    /// - Parameter directory: The directory that files may be written in.
    /// - Returns: The confining policy.
    public static func confined(to directory: URL) -> ATLFileOutputPolicy {
        ATLFileOutputPolicy(baseDirectory: directory, allowsUnrestrictedPaths: false)
    }

    /// Creates a policy that writes files anywhere the process may write.
    ///
    /// Relative paths are resolved against the directory; absolute paths are used as
    /// they are. Use this only for transformations and queries that you trust.
    ///
    /// - Parameter directory: The directory that relative paths are resolved against.
    /// - Returns: The unrestricted policy.
    public static func unrestricted(relativeTo directory: URL) -> ATLFileOutputPolicy {
        ATLFileOutputPolicy(baseDirectory: directory, allowsUnrestrictedPaths: true)
    }

    /// Creates a policy.
    ///
    /// - Parameters:
    ///   - baseDirectory: The directory that relative paths are resolved against, or
    ///     `nil` to disable writing.
    ///   - allowsUnrestrictedPaths: Whether paths outside the base directory are accepted.
    public init(baseDirectory: URL?, allowsUnrestrictedPaths: Bool = false) {
        self.baseDirectory = baseDirectory?.standardizedFileURL
        self.allowsUnrestrictedPaths = allowsUnrestrictedPaths
    }

    /// Resolves the path that a string operation writes to.
    ///
    /// Relative paths are resolved against ``baseDirectory``. Unless
    /// ``allowsUnrestrictedPaths`` is set, the result must lie strictly inside the
    /// base directory after `.` and `..` components and symbolic links have been
    /// resolved, and absolute paths are rejected.
    ///
    /// - Parameter path: The path as written in the transformation.
    /// - Returns: The location of the file to write.
    /// - Throws: ``ATLExecutionError/invalidOperation(_:)`` when writing is disabled or
    ///   the policy does not permit the path.
    public func resolve(_ path: String) throws -> URL {
        try resolve(path, for: ATLReflectiveOperation.writeTo.rawValue)
    }

    /// Resolves the path that a named string operation writes to.
    ///
    /// - Parameters:
    ///   - path: The path as written in the transformation.
    ///   - operation: The name of the operation, for messages.
    /// - Returns: The location of the file to write.
    /// - Throws: ``ATLExecutionError/invalidOperation(_:)`` when writing is disabled or
    ///   the policy does not permit the path.
    func resolve(_ path: String, for operation: String) throws -> URL {
        guard let baseDirectory else {
            throw ATLExecutionError.invalidOperation(
                "\(operation) is disabled: the host has not enabled file output")
        }
        func rejected(_ reason: String) -> ATLExecutionError {
            .invalidOperation("\(operation) cannot write to '\(path)': \(reason)")
        }
        guard !path.isEmpty, !path.contains("\0") else {
            throw rejected("the path is empty or malformed")
        }
        let isAbsolute = Self.isAbsolutePath(path)
        let separated = Self.withPlatformSeparators(path)
        let base = URL(fileURLWithPath: baseDirectory.path, isDirectory: true)
        let target =
            (isAbsolute
                ? URL(fileURLWithPath: separated) : URL(fileURLWithPath: separated, relativeTo: base))
            .standardizedFileURL
        if allowsUnrestrictedPaths { return target }
        guard !isAbsolute else {
            throw rejected("absolute paths are not permitted inside the output directory")
        }
        let root: URL
        let physical: URL
        do {
            root = try Self.physicalURL(of: base.standardizedFileURL)
            physical = try Self.physicalURL(of: target)
        } catch ATLExecutionError.invalidOperation {
            throw rejected("the path involves too many symbolic links")
        }
        let rootComponents = Self.components(of: root)
        let targetComponents = Self.components(of: physical)
        guard targetComponents.count > rootComponents.count,
            targetComponents.starts(with: rootComponents)
        else {
            throw rejected("the path leads outside the output directory")
        }
        return target
    }

    /// Writes a string to a file as the `writeTo` operations do.
    ///
    /// - Parameters:
    ///   - text: The string to write.
    ///   - path: The path as written in the transformation.
    ///   - charset: The name of the charset, or `nil` for UTF-8.
    ///   - operation: The name of the operation, for messages.
    /// - Returns: `true` once the file has been written.
    /// - Throws: ``ATLExecutionError`` when the policy rejects the path, the charset is
    ///   unknown or cannot encode the string, or the file cannot be written.
    func write(_ text: String, to path: String, charset: String?, operation: String) throws -> Bool {
        let url = try resolve(path, for: operation)
        let data = try ATLCharset.encode(text, charset: charset, operation: operation)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        } catch {
            throw ATLExecutionError.runtimeError(
                "\(operation) could not write '\(path)': \(error.localizedDescription)")
        }
        return true
    }

    // MARK: - Path Resolution

    /// The largest number of symbolic links followed while resolving one path.
    private static let maximumLinkDepth = 32

    /// Whether a path written in a transformation is absolute on this platform.
    ///
    /// - Parameter path: The path.
    /// - Returns: `true` for an absolute path.
    static func isAbsolutePath(_ path: String) -> Bool {
        #if os(Windows)
        let characters = Array(path)
        if let first = characters.first, first == "/" || first == "\\" { return true }
        return characters.count >= 2 && characters[1] == ":" && characters[0].isLetter
        #else
        return path.hasPrefix("/")
        #endif
    }

    /// A path written in a transformation, with the platform's separators normalised.
    ///
    /// On Windows a backslash separates path components just as a slash does, so it is
    /// replaced by a slash before `.` and `..` components are resolved. On other
    /// platforms a backslash is an ordinary character of a file name.
    ///
    /// - Parameter path: The path as written in the transformation.
    /// - Returns: The path with `/` as its only separator on Windows, and the path
    ///   itself elsewhere.
    static func withPlatformSeparators(_ path: String) -> String {
        #if os(Windows)
        return path.replacingOccurrences(of: "\\", with: "/")
        #else
        return path
        #endif
    }

    /// The path components of a location, for comparing locations.
    private static func components(of url: URL) -> [String] {
        url.standardizedFileURL.pathComponents.filter { $0 != "/" && !$0.isEmpty }
    }

    /// Resolves the symbolic links in every existing component of a location.
    ///
    /// The longest existing prefix of the location is resolved, including a final
    /// symbolic link whose destination does not exist, and the components that do
    /// not exist yet are appended to the result.
    ///
    /// - Parameters:
    ///   - url: A standardised file location.
    ///   - depth: The number of symbolic links followed so far.
    /// - Returns: The physical location.
    /// - Throws: ``ATLExecutionError/invalidOperation(_:)`` when links nest too deeply.
    private static func physicalURL(of url: URL, depth: Int = 0) throws -> URL {
        guard depth < maximumLinkDepth else {
            throw ATLExecutionError.invalidOperation(
                "Too many symbolic links while resolving '\(url.path)'")
        }
        let manager = FileManager.default
        var existing = url.standardizedFileURL
        var missing: [String] = []
        while (try? manager.attributesOfItem(atPath: existing.path)) == nil {
            let parent = existing.deletingLastPathComponent()
            guard parent.path != existing.path else { break }
            missing.insert(existing.lastPathComponent, at: 0)
            existing = parent
        }
        var resolved: URL
        let attributes = try? manager.attributesOfItem(atPath: existing.path)
        if attributes?[.type] as? FileAttributeType == .typeSymbolicLink {
            let destination = try manager.destinationOfSymbolicLink(atPath: existing.path)
            let target =
                isAbsolutePath(destination)
                ? URL(fileURLWithPath: destination)
                : existing.deletingLastPathComponent().appendingPathComponent(destination)
            resolved = try physicalURL(of: target.standardizedFileURL, depth: depth + 1)
        } else {
            resolved = existing.resolvingSymlinksInPath()
        }
        for component in missing {
            resolved.appendPathComponent(component)
        }
        return resolved.standardizedFileURL
    }
}

// MARK: - Charsets

/// The charsets that `writeToWithCharset` accepts.
///
/// Charset names are matched without regard to case, with `_` read as `-`, and
/// cover the common Java names and aliases of each charset.
enum ATLCharset {

    /// The name of the charset that `writeTo` uses.
    static let defaultName = "UTF-8"

    /// The byte order mark that starts text in the `UTF-16` charset.
    private static let utf16ByteOrderMark: [UInt8] = [0xFE, 0xFF]

    /// The supported charsets, indexed by their normalised names.
    ///
    /// `UTF-16` is encoded big-endian with a byte order mark, as Java encodes it, and
    /// `UTF-32` big-endian without one.
    private static let encodings: [String: (encoding: String.Encoding, byteOrderMark: [UInt8])] = [
        "UTF-8": (.utf8, []), "UTF8": (.utf8, []),
        "UTF-16": (.utf16BigEndian, utf16ByteOrderMark),
        "UTF16": (.utf16BigEndian, utf16ByteOrderMark),
        "UTF-16BE": (.utf16BigEndian, []), "UTF-16LE": (.utf16LittleEndian, []),
        "UTF-32": (.utf32BigEndian, []), "UTF-32BE": (.utf32BigEndian, []),
        "UTF-32LE": (.utf32LittleEndian, []),
        "ISO-8859-1": (.isoLatin1, []), "ISO8859-1": (.isoLatin1, []),
        "LATIN1": (.isoLatin1, []), "ISO-LATIN-1": (.isoLatin1, []),
        "US-ASCII": (.ascii, []), "ASCII": (.ascii, []),
    ]

    /// Normalises a charset name for lookup.
    private static func normalised(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespaces).uppercased()
            .replacingOccurrences(of: "_", with: "-")
    }

    /// The string encoding of a charset name.
    ///
    /// - Parameter name: The charset name, such as `UTF-8` or `ISO-8859-1`.
    /// - Returns: The encoding, or `nil` for an unsupported charset.
    static func encoding(named name: String) -> String.Encoding? {
        encodings[normalised(name)]?.encoding
    }

    /// Encodes a string in a charset.
    ///
    /// - Parameters:
    ///   - text: The string to encode.
    ///   - charset: The charset name, or `nil` for ``defaultName``.
    ///   - operation: The name of the operation, for messages.
    /// - Returns: The encoded bytes.
    /// - Throws: ``ATLExecutionError/invalidOperation(_:)`` for an unsupported charset and
    ///   ``ATLExecutionError/runtimeError(_:)`` when the charset cannot encode the string.
    static func encode(_ text: String, charset: String?, operation: String) throws -> Data {
        let name = charset ?? defaultName
        guard let entry = encodings[normalised(name)] else {
            let supported = encodings.keys.sorted().joined(separator: ", ")
            throw ATLExecutionError.invalidOperation(
                "\(operation) does not support the charset '\(name)' (supported: \(supported))")
        }
        guard let data = text.data(using: entry.encoding, allowLossyConversion: false) else {
            throw ATLExecutionError.runtimeError(
                "\(operation) cannot encode the string in the charset '\(name)'")
        }
        return Data(entry.byteOrderMark) + data
    }
}
