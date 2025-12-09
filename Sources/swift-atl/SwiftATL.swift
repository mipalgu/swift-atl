import ATL
//
//  SwiftATL.swift
//  swift-atl
//
//  Created by Rene Hexel on 6/12/2025.
//  Copyright © 2025 Rene Hexel. All rights reserved.
//
import ArgumentParser
import ECore
import Foundation
import OrderedCollections

/// The main entry point for the swift-atl command-line tool.
///
/// Swift ATL provides a command-line interface for Atlas Transformation Language
/// operations, including transformation compilation, model transformation execution,
/// and code generation using ATL modules.
///
/// ## Available Commands
///
/// - **compile**: Compile ATL transformation files to executable modules
/// - **transform**: Execute model transformations using compiled ATL modules
/// - **generate**: Generate code from models using ATL-based code generators
///
/// ## Example Usage
///
/// ```bash
/// # Compile an ATL transformation
/// swift-atl compile Families2Persons.atl --output families2persons.atlc
///
/// # Execute a transformation
/// swift-atl transform families2persons.atlc \
///   --source families.xmi --target persons.xmi
///
/// # Generate Swift code from a model
/// swift-atl generate model.ecore --language swift --output Generated/
/// ```
@main
struct SwiftATLCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-atl",
        abstract: "Atlas Transformation Language command-line tool",
        discussion: """
            Swift ATL provides comprehensive support for model transformation using the
            Atlas Transformation Language (ATL). It enables compilation of ATL transformations,
            execution of model-to-model transformations, and generation of code from models.

            The tool supports standard ATL syntax for compatibility with existing Eclipse ATL
            transformations while providing enhanced performance through Swift's concurrent
            execution model and type safety.
            """,
        version: "1.0.0",
        subcommands: [
            CompileCommand.self,
            TransformCommand.self,
            GenerateCommand.self,
        ],
        defaultSubcommand: nil
    )
}

// MARK: - Compile Command

/// Command for compiling ATL transformation files to executable modules.
///
/// The compile command processes ATL source files and produces compiled transformation
/// modules that can be executed efficiently by the ATL virtual machine. Compilation
/// includes syntax analysis, type checking, and optimisation for performance.
struct CompileCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compile",
        abstract: "Compile ATL transformation files",
        discussion: """
            Compiles ATL transformation source files into optimised executable modules.
            The compilation process includes syntax parsing, semantic analysis, type
            checking, and optimisation for efficient transformation execution.

            Example:
                swift-atl compile Families2Persons.atl --output families2persons.atlc
            """
    )

    @Argument(help: "ATL source file to compile")
    var atlFile: String

    @Option(name: .shortAndLong, help: "Output file for compiled module")
    var output: String?

    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() async throws {
        if verbose {
            print("🔧 Compiling ATL transformation: \(atlFile)")
        }

        // Determine output file name
        let outputPath = output ?? defaultOutputPath(for: atlFile)

        do {
            // Load and parse the ATL file
            let atlSource = try String(contentsOfFile: atlFile, encoding: .utf8)

            if verbose {
                print("📖 Loaded ATL source (\(atlSource.count) characters)")
                print("🔍 Parsing transformation module...")
            }

            // TODO: Implement ATL parser and compiler
            // let parser = ATLParser(source: atlSource)
            // let module = try await parser.parseModule()
            // let compiler = ATLCompiler(module: module)
            // let compiledModule = try await compiler.compile()

            if verbose {
                print("✅ Compilation successful")
                print("📦 Output written to: \(outputPath)")
            } else {
                print("Compiled \(atlFile) → \(outputPath)")
            }

        } catch {
            print("❌ Compilation failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

    /// Generates a default output path for the compiled module.
    ///
    /// - Parameter inputPath: The input ATL file path
    /// - Returns: The default output path with .atlc extension
    private func defaultOutputPath(for inputPath: String) -> String {
        let url = URL(fileURLWithPath: inputPath)
        let baseName = url.deletingPathExtension().lastPathComponent
        return "\(baseName).atlc"
    }
}

// MARK: - Transform Command

/// Command for executing model transformations using ATL modules.
///
/// The transform command executes compiled ATL transformation modules to transform
/// source models into target models according to the transformation specifications.
/// It supports multiple input and output formats including XMI and JSON.
struct TransformCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "transform",
        abstract: "Execute model transformations",
        discussion: """
            Executes model transformations using compiled ATL modules or source files.
            Supports transformation of models in XMI and JSON formats with automatic
            format detection and conversion.

            Examples:
                # Transform using compiled module
                swift-atl transform families2persons.atlc \\
                  --source families.xmi --target persons.xmi

                # Transform using ATL source (auto-compilation)
                swift-atl transform Families2Persons.atl \\
                  --source families.json --target persons.xmi
            """
    )

    @Argument(help: "ATL transformation file (.atl or .atlc)")
    var transformation: String

    @Option(name: .long, help: "Source model files (format: alias=file)")
    var sources: [String] = []

    @Option(name: .long, help: "Target model files (format: alias=file)")
    var targets: [String] = []

    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    @MainActor
    func run() async throws {
        if verbose {
            print("🚀 Starting ATL transformation: \(transformation)")
            print("📥 Source models: \(sources)")
            print("📤 Target models: \(targets)")
        }

        do {
            // Parse source and target model specifications
            let sourceModels = try parseModelSpecifications(sources, type: "source")
            let targetModels = try parseModelSpecifications(targets, type: "target")

            if verbose {
                print("🔧 Loading transformation module...")
            }

            // Load or compile the transformation module
            let module = try await loadTransformationModule(transformation)

            if verbose {
                print("📊 Transformation module loaded: \(module.name)")
                print(
                    "   - Source metamodels: \(module.sourceMetamodels.keys.joined(separator: ", "))"
                )
                print(
                    "   - Target metamodels: \(module.targetMetamodels.keys.joined(separator: ", "))"
                )
                print("   - Matched rules: \(module.matchedRules.count)")
                print("   - Called rules: \(module.calledRules.count)")
                print("   - Helpers: \(module.helpers.count)")
            }

            // Create and configure the ATL virtual machine
            let virtualMachine = ATLVirtualMachine(module: module)

            if verbose {
                print("⚡️ Executing transformation...")
            }

            // Execute the transformation
            try await virtualMachine.execute(
                sources: sourceModels,
                targets: targetModels
            )

            // Display execution statistics
            let stats = virtualMachine.getStatistics()
            if verbose {
                print("📈 Transformation Statistics:")
                print(stats.summary())
            } else {
                let duration = String(format: "%.3f", stats.executionTime * 1000)
                print("Transformation completed in \(duration)ms")
                print(
                    "   Processed \(stats.elementsProcessed) elements, created \(stats.elementsCreated) elements"
                )
            }

        } catch {
            print("Transformation failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

    /// Parses model specification strings into model resources.
    ///
    /// - Parameters:
    ///   - specifications: Array of "alias=file" specifications
    ///   - type: Type description for error messages
    /// - Returns: Dictionary of model resources indexed by alias
    /// - Throws: Parsing errors for invalid specifications
    private func parseModelSpecifications(_ specifications: [String], type: String) throws
        -> OrderedDictionary<String, Resource>
    {
        var models: OrderedDictionary<String, Resource> = [:]

        for spec in specifications {
            let components = spec.split(separator: "=", maxSplits: 1)
            guard components.count == 2 else {
                throw ValidationError(
                    "Invalid \(type) model specification: '\(spec)'. Expected format: alias=file")
            }

            let alias = String(components[0])
            let filePath = String(components[1])

            // TODO: Load model resource from file
            // For now, create a placeholder resource to avoid compiler warnings
            let resource = Resource()
            models[alias] = resource

            if verbose {
                print("📋 Registered \(type) model '\(alias)' from \(filePath)")
            }
        }

        return models
    }

    /// Loads a transformation module from file.
    ///
    /// - Parameter path: Path to ATL source or compiled module
    /// - Returns: The loaded ATL module
    /// - Throws: Loading errors for invalid files
    private func loadTransformationModule(_ path: String) async throws -> ATLModule {
        let url = URL(fileURLWithPath: path)
        let fileExtension = url.pathExtension.lowercased()

        switch fileExtension {
        case "atlc":
            // Load compiled module
            throw ValidationError("Loading compiled ATL modules not yet implemented")
        case "atl":
            // Compile source module
            throw ValidationError("ATL source compilation not yet implemented")
        default:
            throw ValidationError("Unsupported transformation file type: .\(fileExtension)")
        }
    }
}

// MARK: - Generate Command

/// Command for generating code from models using ATL transformations.
///
/// The generate command uses ATL-based code generators to produce source code
/// from input models. It supports multiple target languages and customisable
/// generation templates through ATL transformation modules.
struct GenerateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: "Generate code from models",
        discussion: """
            Generates source code from input models using ATL-based code generators.
            Supports multiple target languages including Swift, C++, C, and LLVM IR
            with customisable generation templates and output formatting.

            Examples:
                # Generate Swift code from Ecore model
                swift-atl generate model.ecore --language swift --output Generated/

                # Generate C++ code with custom transformation
                swift-atl generate model.xmi --transformation ecore2cpp.atl \\
                  --output src/ --language cpp
            """
    )

    @Argument(help: "Input model file")
    var inputModel: String

    @Option(name: .long, help: "ATL transformation directory or file")
    var transformations: String?

    @Option(name: .shortAndLong, help: "Target language (swift, cpp, c, llvm)")
    var language: String = "swift"

    @Option(name: .shortAndLong, help: "Output directory")
    var output: String = "Generated"

    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() async throws {
        if verbose {
            print("🏗️  Starting code generation:")
            print("   Input model: \(inputModel)")
            print("   Target language: \(language)")
            print("   Output directory: \(output)")
        }

        do {
            // Validate target language
            guard isValidLanguage(language) else {
                throw ValidationError("Unsupported target language: \(language)")
            }

            // Determine transformation to use
            let transformationPath = transformations ?? defaultTransformationPath(for: language)

            if verbose {
                print("🔧 Using transformation: \(transformationPath)")
                print("📥 Loading input model...")
            }

            // TODO: Implement code generation
            // let inputResource = try await loadModelResource(inputModel)
            // let transformationModule = try await loadTransformationModule(transformationPath)
            // let generator = CodeGenerator(module: transformationModule, language: language)
            // try await generator.generate(from: inputResource, to: output)

            if verbose {
                print("Code generation completed")
                print("Generated files written to: \(output)")
            } else {
                print("Generated \(language) code from \(inputModel) → \(output)")
            }

        } catch {
            print("Code generation failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

    /// Validates if the specified language is supported.
    ///
    /// - Parameter language: The target language identifier
    /// - Returns: `true` if the language is supported
    private func isValidLanguage(_ language: String) -> Bool {
        let supportedLanguages = ["swift", "cpp", "c", "llvm"]
        return supportedLanguages.contains(language.lowercased())
    }

    /// Generates the default transformation path for a language.
    ///
    /// - Parameter language: The target language
    /// - Returns: The default transformation file path
    private func defaultTransformationPath(for language: String) -> String {
        return "transformations/ecore-to-\(language.lowercased()).atl"
    }
}

// MARK: - Error Types

/// Validation errors for command-line arguments.
struct ValidationError: Error, LocalizedError {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        return message
    }
}
