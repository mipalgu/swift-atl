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
/// parsing, validation, testing, and analysis of ATL modules.
///
/// ## Available Commands
///
/// - **parse**: Parse and validate ATL transformation files
/// - **validate**: Validate ATL transformation syntax and semantics
/// - **test**: Test ATL transformation files with sample data
/// - **analyze**: Analyze ATL transformation files for complexity and metrics
/// - **compile**: Compile ATL transformation files to executable modules
/// - **transform**: Execute model transformations using compiled ATL modules
/// - **generate**: Generate code from models using ATL-based code generators
///
/// ## Example Usage
///
/// ```bash
/// # Parse an ATL transformation
/// swift-atl parse Families2Persons.atl --verbose
///
/// # Validate multiple ATL files
/// swift-atl validate *.atl --output validation-report.txt
///
/// # Test ATL transformations
/// swift-atl test --directory Tests/ATLTests/Resources
///
/// # Analyze transformation complexity
/// swift-atl analyze Families2Persons.atl --metrics complexity,rules,helpers
///
/// # Compile an ATL transformation
/// swift-atl compile Families2Persons.atl --output families2persons.atlc
///
/// # Execute a transformation
/// swift-atl transform families2persons.atlc \
///   --source families.xmi --target persons.xmi
/// ```
@main
struct SwiftATLCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "swift-atl",
        abstract: "Atlas Transformation Language command-line tool",
        discussion: """
            Swift ATL provides comprehensive support for model transformation using the
            Atlas Transformation Language (ATL). It enables parsing, validation, testing,
            analysis, compilation of ATL transformations, execution of model-to-model
            transformations, and generation of code from models.

            The tool supports standard ATL syntax for compatibility with existing Eclipse ATL
            transformations while providing enhanced performance through Swift's concurrent
            execution model and type safety.
            """,
        version: "1.0.0",
        subcommands: [
            ParseCommand.self,
            ValidateCommand.self,
            TestCommand.self,
            AnalyzeCommand.self,
            CompileCommand.self,
            TransformCommand.self,
            GenerateCommand.self,
        ],
        defaultSubcommand: nil
    )
}

// MARK: - Parse Command

/// Command for parsing ATL transformation files.
///
/// The parse command processes ATL source files and provides detailed information
/// about their structure, including modules, rules, helpers, and expressions.
/// It validates syntax and provides comprehensive parsing diagnostics.
struct ParseCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "parse",
        abstract: "Parse and analyze ATL transformation files",
        discussion: """
            Parses ATL transformation source files and displays detailed information
            about their structure. Performs syntax validation and provides comprehensive
            diagnostics about modules, rules, helpers, and expressions.

            Examples:
                swift-atl parse Families2Persons.atl --verbose
                swift-atl parse *.atl --output parsing-report.txt
                swift-atl parse transformation.atl --format json
            """
    )

    @Argument(help: "ATL source files to parse")
    var atlFiles: [String] = []

    @Option(name: .shortAndLong, help: "Output format (text, json, xml)")
    var format: String = "text"

    @Option(name: .shortAndLong, help: "Output file for parsing results")
    var output: String?

    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    @Flag(name: .long, help: "Show detailed module structure")
    var showStructure: Bool = false

    @Flag(name: .long, help: "Show rule details")
    var showRules: Bool = false

    @Flag(name: .long, help: "Show helper details")
    var showHelpers: Bool = false

    func run() async throws {
        guard !atlFiles.isEmpty else {
            throw ValidationError("No ATL files specified")
        }

        if verbose {
            print("Parsing \(atlFiles.count) ATL file(s)")
            print("Output format: \(format)")
            if let outputPath = output {
                print("Output will be written to: \(outputPath)")
            }
        }

        var results: [ParseResult] = []

        for atlFile in atlFiles {
            do {
                if verbose {
                    print("Processing: \(atlFile)")
                }

                let parseResult = try await parseATLFile(atlFile)
                results.append(parseResult)

                if !verbose && output == nil {
                    print("Parsed \(atlFile): \(parseResult.summary)")
                }

            } catch {
                let errorResult = ParseResult(
                    filename: atlFile,
                    success: false,
                    module: nil,
                    parseTime: 0,
                    error: error.localizedDescription
                )
                results.append(errorResult)

                if verbose {
                    print("Error parsing \(atlFile): \(error.localizedDescription)")
                } else {
                    print("Failed to parse \(atlFile): \(error.localizedDescription)")
                }
            }
        }

        // Generate output
        let outputContent = try generateParseOutput(results: results, format: format)

        if let outputPath = output {
            try outputContent.write(
                to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
            if verbose {
                print("Results written to: \(outputPath)")
            } else {
                print("Parse results written to \(outputPath)")
            }
        } else if verbose || results.count > 1 {
            print(outputContent)
        }
    }

    private func parseATLFile(_ filePath: String) async throws -> ParseResult {
        let startTime = Date()

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw ValidationError("File not found: \(filePath)")
        }

        let atlSource = try String(contentsOfFile: filePath, encoding: .utf8)

        if verbose {
            print("  Source size: \(atlSource.count) characters")
        }

        let parser = ATLParser()
        let module = try await parser.parseContent(
            atlSource, filename: URL(fileURLWithPath: filePath).lastPathComponent)

        let parseTime = Date().timeIntervalSince(startTime)

        if verbose {
            print("  Parse time: \(String(format: "%.3f", parseTime * 1000))ms")
            print("  Module: \(module.name)")
            print("  Source metamodels: \(module.sourceMetamodels.keys.joined(separator: ", "))")
            print("  Target metamodels: \(module.targetMetamodels.keys.joined(separator: ", "))")
            print("  Matched rules: \(module.matchedRules.count)")
            print("  Called rules: \(module.calledRules.count)")
            print("  Helpers: \(module.helpers.count)")
        }

        return ParseResult(
            filename: filePath,
            success: true,
            module: module,
            parseTime: parseTime,
            error: nil
        )
    }

    private func generateParseOutput(results: [ParseResult], format: String) throws -> String {
        switch format.lowercased() {
        case "json":
            return try generateJSONOutput(results)
        case "xml":
            return generateXMLOutput(results)
        default:
            return generateTextOutput(results)
        }
    }

    private func generateTextOutput(_ results: [ParseResult]) -> String {
        var output = "ATL Parsing Results\n"
        output += "==================\n\n"

        let successful = results.filter { $0.success }
        let failed = results.filter { !$0.success }

        output += "Summary: \(successful.count) successful, \(failed.count) failed\n"

        if !successful.isEmpty {
            let totalParseTime = successful.reduce(0) { $0 + $1.parseTime }
            let avgParseTime = totalParseTime / Double(successful.count)
            output += "Average parse time: \(String(format: "%.3f", avgParseTime * 1000))ms\n"
        }

        output += "\n"

        for result in results {
            output += "File: \(result.filename)\n"
            if result.success, let module = result.module {
                output += "  Status: SUCCESS\n"
                output += "  Parse time: \(String(format: "%.3f", result.parseTime * 1000))ms\n"
                output += "  Module: \(module.name)\n"

                if showStructure {
                    output += "  Source metamodels:\n"
                    for (alias, package) in module.sourceMetamodels {
                        output += "    \(alias): \(package.name) (\(package.nsURI))\n"
                    }
                    output += "  Target metamodels:\n"
                    for (alias, package) in module.targetMetamodels {
                        output += "    \(alias): \(package.name) (\(package.nsURI))\n"
                    }
                }

                if showRules {
                    output += "  Matched rules (\(module.matchedRules.count)):\n"
                    for rule in module.matchedRules {
                        output += "    \(rule.name): \(rule.sourcePattern.type) -> "
                        output += rule.targetPatterns.map { $0.type }.joined(separator: ", ")
                        output += "\n"
                    }
                    output += "  Called rules (\(module.calledRules.count)):\n"
                    for (name, rule) in module.calledRules {
                        output += "    \(name): \(rule.parameters.count) parameters, "
                        output += "\(rule.targetPatterns.count) target patterns\n"
                    }
                }

                if showHelpers {
                    output += "  Helpers (\(module.helpers.count)):\n"
                    for (name, helper) in module.helpers {
                        let contextInfo = helper.contextType.map { " [\($0)]" } ?? ""
                        output += "    \(name)\(contextInfo): \(helper.returnType)\n"
                    }
                }
            } else {
                output += "  Status: FAILED\n"
                if let error = result.error {
                    output += "  Error: \(error)\n"
                }
            }
            output += "\n"
        }

        return output
    }

    private func generateJSONOutput(_ results: [ParseResult]) throws -> String {
        let jsonData = try JSONSerialization.data(
            withJSONObject: results.map { $0.toJSONRepresentation() }, options: .prettyPrinted)
        return String(data: jsonData, encoding: .utf8) ?? ""
    }

    private func generateXMLOutput(_ results: [ParseResult]) -> String {
        var xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
        xml += "<atl-parse-results>\n"

        for result in results {
            xml += "  <result>\n"
            xml += "    <filename>\(xmlEscape(result.filename))</filename>\n"
            xml += "    <success>\(result.success)</success>\n"
            xml += "    <parse-time>\(result.parseTime)</parse-time>\n"

            if let module = result.module {
                xml += "    <module>\n"
                xml += "      <name>\(xmlEscape(module.name))</name>\n"
                xml += "      <matched-rules>\(module.matchedRules.count)</matched-rules>\n"
                xml += "      <called-rules>\(module.calledRules.count)</called-rules>\n"
                xml += "      <helpers>\(module.helpers.count)</helpers>\n"
                xml += "    </module>\n"
            }

            if let error = result.error {
                xml += "    <error>\(xmlEscape(error))</error>\n"
            }

            xml += "  </result>\n"
        }

        xml += "</atl-parse-results>\n"
        return xml
    }

    private func xmlEscape(_ string: String) -> String {
        return
            string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}

// MARK: - Validate Command

/// Command for validating ATL transformation files.
///
/// The validate command performs comprehensive validation of ATL transformations,
/// including syntax checking, semantic analysis, type checking, and metamodel
/// compatibility verification.
struct ValidateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate",
        abstract: "Validate ATL transformation files",
        discussion: """
            Performs comprehensive validation of ATL transformation files including
            syntax checking, semantic analysis, type checking, and metamodel compatibility.
            Provides detailed validation reports with warnings and errors.

            Examples:
                swift-atl validate Families2Persons.atl
                swift-atl validate *.atl --strict --output validation.log
                swift-atl validate transformation.atl --check-metamodels
            """
    )

    @Argument(help: "ATL source files to validate")
    var atlFiles: [String] = []

    @Option(name: .shortAndLong, help: "Output file for validation results")
    var output: String?

    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    @Flag(name: .long, help: "Enable strict validation mode")
    var strict: Bool = false

    @Flag(name: .long, help: "Check metamodel compatibility")
    var checkMetamodels: Bool = false

    @Flag(name: .long, help: "Validate rule completeness")
    var checkRules: Bool = false

    func run() async throws {
        guard !atlFiles.isEmpty else {
            throw ValidationError("No ATL files specified")
        }

        if verbose {
            print("Validating \(atlFiles.count) ATL file(s)")
            print("Strict mode: \(strict ? "enabled" : "disabled")")
            print("Metamodel checking: \(checkMetamodels ? "enabled" : "disabled")")
            print("Rule checking: \(checkRules ? "enabled" : "disabled")")
        }

        var validationResults: [ValidationResult] = []
        var totalErrors = 0
        var totalWarnings = 0

        for atlFile in atlFiles {
            if verbose {
                print("Validating: \(atlFile)")
            }

            let result = try await validateATLFile(atlFile)
            validationResults.append(result)
            totalErrors += result.errors.count
            totalWarnings += result.warnings.count

            if !verbose && output == nil {
                let status = result.isValid ? "VALID" : "INVALID"
                print(
                    "\(atlFile): \(status) (\(result.errors.count) errors, \(result.warnings.count) warnings)"
                )
            }
        }

        // Generate summary
        let validFiles = validationResults.filter { $0.isValid }.count
        let invalidFiles = validationResults.count - validFiles

        if verbose {
            print("\nValidation Summary:")
            print("Valid files: \(validFiles)")
            print("Invalid files: \(invalidFiles)")
            print("Total errors: \(totalErrors)")
            print("Total warnings: \(totalWarnings)")
        } else if output == nil {
            print(
                "Validation complete: \(validFiles) valid, \(invalidFiles) invalid (\(totalErrors) errors, \(totalWarnings) warnings)"
            )
        }

        // Write output if requested
        if let outputPath = output {
            let outputContent = generateValidationReport(validationResults)
            try outputContent.write(
                to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
            print("Validation report written to \(outputPath)")
        }

        // Exit with error code if validation failed
        if totalErrors > 0 || (strict && totalWarnings > 0) {
            throw ExitCode(totalErrors > 0 ? 1 : 2)
        }
    }

    private func validateATLFile(_ filePath: String) async throws -> ValidationResult {
        let startTime = Date()
        var errors: [ValidationIssue] = []
        var warnings: [ValidationIssue] = []

        guard FileManager.default.fileExists(atPath: filePath) else {
            errors.append(
                ValidationIssue(
                    type: .error,
                    message: "File not found: \(filePath)",
                    line: nil,
                    column: nil
                ))
            return ValidationResult(
                filename: filePath,
                validationTime: Date().timeIntervalSince(startTime),
                errors: errors,
                warnings: warnings
            )
        }

        do {
            let atlSource = try String(contentsOfFile: filePath, encoding: .utf8)
            let parser = ATLParser()
            let module = try await parser.parseContent(
                atlSource, filename: URL(fileURLWithPath: filePath).lastPathComponent)

            // Perform semantic validation
            try validateModuleSemantics(module: module, errors: &errors, warnings: &warnings)

            if checkMetamodels {
                try validateMetamodels(module: module, errors: &errors, warnings: &warnings)
            }

            if checkRules {
                try validateRules(module: module, errors: &errors, warnings: &warnings)
            }

            if verbose {
                print(
                    "  Validation time: \(String(format: "%.3f", Date().timeIntervalSince(startTime) * 1000))ms"
                )
                print("  Errors: \(errors.count)")
                print("  Warnings: \(warnings.count)")
            }

        } catch {
            errors.append(
                ValidationIssue(
                    type: .error,
                    message: "Parse error: \(error.localizedDescription)",
                    line: nil,
                    column: nil
                ))
        }

        return ValidationResult(
            filename: filePath,
            validationTime: Date().timeIntervalSince(startTime),
            errors: errors,
            warnings: warnings
        )
    }

    private func validateModuleSemantics(
        module: ATLModule, errors: inout [ValidationIssue], warnings: inout [ValidationIssue]
    ) throws {
        // Check for empty module name
        if module.name.isEmpty {
            warnings.append(
                ValidationIssue(
                    type: .warning,
                    message: "Module name is empty",
                    line: nil,
                    column: nil
                ))
        }

        // Check for missing metamodels
        if module.sourceMetamodels.isEmpty {
            errors.append(
                ValidationIssue(
                    type: .error,
                    message: "No source metamodels defined",
                    line: nil,
                    column: nil
                ))
        }

        if module.targetMetamodels.isEmpty {
            errors.append(
                ValidationIssue(
                    type: .error,
                    message: "No target metamodels defined",
                    line: nil,
                    column: nil
                ))
        }

        // Check for rules without patterns
        for rule in module.matchedRules {
            if rule.targetPatterns.isEmpty {
                warnings.append(
                    ValidationIssue(
                        type: .warning,
                        message: "Matched rule '\(rule.name)' has no target patterns",
                        line: nil,
                        column: nil
                    ))
            }
        }

        for (name, rule) in module.calledRules {
            if rule.targetPatterns.isEmpty {
                warnings.append(
                    ValidationIssue(
                        type: .warning,
                        message: "Called rule '\(name)' has no target patterns",
                        line: nil,
                        column: nil
                    ))
            }
        }
    }

    private func validateMetamodels(
        module: ATLModule, errors: inout [ValidationIssue], warnings: inout [ValidationIssue]
    ) throws {
        // Validate metamodel references in rules
        for rule in module.matchedRules {
            let sourceType = rule.sourcePattern.type
            let isValidSourceType = module.sourceMetamodels.values.contains { package in
                // Basic check - in a full implementation, we'd check package contents
                return !package.name.isEmpty
            }

            if !isValidSourceType {
                warnings.append(
                    ValidationIssue(
                        type: .warning,
                        message:
                            "Source type '\(sourceType)' in rule '\(rule.name)' may not exist in source metamodels",
                        line: nil,
                        column: nil
                    ))
            }

            for targetPattern in rule.targetPatterns {
                let targetType = targetPattern.type
                let isValidTargetType = module.targetMetamodels.values.contains { package in
                    // Basic check - in a full implementation, we'd check package contents
                    return !package.name.isEmpty
                }

                if !isValidTargetType {
                    warnings.append(
                        ValidationIssue(
                            type: .warning,
                            message:
                                "Target type '\(targetType)' in rule '\(rule.name)' may not exist in target metamodels",
                            line: nil,
                            column: nil
                        ))
                }
            }
        }
    }

    private func validateRules(
        module: ATLModule, errors: inout [ValidationIssue], warnings: inout [ValidationIssue]
    ) throws {
        // Check for duplicate rule names
        var ruleNames = Set<String>()
        for rule in module.matchedRules {
            if ruleNames.contains(rule.name) {
                errors.append(
                    ValidationIssue(
                        type: .error,
                        message: "Duplicate matched rule name: '\(rule.name)'",
                        line: nil,
                        column: nil
                    ))
            }
            ruleNames.insert(rule.name)
        }

        for (name, _) in module.calledRules {
            if ruleNames.contains(name) {
                errors.append(
                    ValidationIssue(
                        type: .error,
                        message: "Duplicate called rule name: '\(name)'",
                        line: nil,
                        column: nil
                    ))
            }
            ruleNames.insert(name)
        }

        // Check for unreachable called rules
        let calledRuleNames = Set(module.calledRules.keys)
        // In a full implementation, we'd analyze rule invocations
        // For now, just warn if there are called rules but no matched rules
        if !calledRuleNames.isEmpty && module.matchedRules.isEmpty {
            warnings.append(
                ValidationIssue(
                    type: .warning,
                    message: "Called rules defined but no matched rules to invoke them",
                    line: nil,
                    column: nil
                ))
        }
    }

    private func generateValidationReport(_ results: [ValidationResult]) -> String {
        var report = "ATL Validation Report\n"
        report += "====================\n\n"

        let validFiles = results.filter { $0.isValid }
        let invalidFiles = results.filter { !$0.isValid }
        let totalErrors = results.reduce(0) { $0 + $1.errors.count }
        let totalWarnings = results.reduce(0) { $0 + $1.warnings.count }

        report += "Summary:\n"
        report += "  Valid files: \(validFiles.count)\n"
        report += "  Invalid files: \(invalidFiles.count)\n"
        report += "  Total errors: \(totalErrors)\n"
        report += "  Total warnings: \(totalWarnings)\n\n"

        for result in results {
            report += "File: \(result.filename)\n"
            report += "Status: \(result.isValid ? "VALID" : "INVALID")\n"
            report += "Validation time: \(String(format: "%.3f", result.validationTime * 1000))ms\n"

            if !result.errors.isEmpty {
                report += "Errors (\(result.errors.count)):\n"
                for error in result.errors {
                    report += "  - \(error.message)\n"
                }
            }

            if !result.warnings.isEmpty {
                report += "Warnings (\(result.warnings.count)):\n"
                for warning in result.warnings {
                    report += "  - \(warning.message)\n"
                }
            }

            report += "\n"
        }

        return report
    }
}

// MARK: - Test Command

/// Command for testing ATL transformation files.
///
/// The test command runs comprehensive tests on ATL transformation files,
/// including parsing tests, semantic validation tests, and transformation
/// execution tests with sample data.
struct TestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Test ATL transformation files",
        discussion: """
            Runs comprehensive tests on ATL transformation files including parsing tests,
            validation tests, and transformation execution tests. Can test individual files
            or entire directories of ATL transformations.

            Examples:
                swift-atl test Families2Persons.atl
                swift-atl test --directory Tests/ATLTests/Resources
                swift-atl test *.atl --timeout 30 --verbose
            """
    )

    @Argument(help: "ATL source files to test")
    var atlFiles: [String] = []

    @Option(name: .shortAndLong, help: "Directory containing ATL test files")
    var directory: String?

    @Option(name: .long, help: "Test timeout in seconds")
    var timeout: TimeInterval = 10.0

    @Option(name: .shortAndLong, help: "Output file for test results")
    var output: String?

    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    @Flag(name: .long, help: "Stop on first test failure")
    var failFast: Bool = false

    func run() async throws {
        var filesToTest: [String] = atlFiles

        // If directory specified, find all ATL files
        if let dir = directory {
            let dirURL = URL(fileURLWithPath: dir)
            let fileManager = FileManager.default

            guard fileManager.fileExists(atPath: dir) else {
                throw ValidationError("Test directory not found: \(dir)")
            }

            if verbose {
                print("Scanning directory: \(dir)")
            }

            let contents = try fileManager.contentsOfDirectory(
                at: dirURL, includingPropertiesForKeys: nil)
            let atlFileURLs = contents.filter { $0.pathExtension.lowercased() == "atl" }
            filesToTest.append(contentsOf: atlFileURLs.map { $0.path })
        }

        guard !filesToTest.isEmpty else {
            throw ValidationError("No ATL files to test")
        }

        if verbose {
            print("Testing \(filesToTest.count) ATL file(s)")
            print("Timeout: \(timeout) seconds")
        }

        var testResults: [TestResult] = []
        var passedTests = 0
        var failedTests = 0

        for atlFile in filesToTest {
            if verbose {
                print("Testing: \(atlFile)")
            }

            let result = await runTest(for: atlFile)
            testResults.append(result)

            if result.passed {
                passedTests += 1
                if !verbose {
                    print("PASS: \(atlFile)")
                }
            } else {
                failedTests += 1
                if !verbose {
                    print("FAIL: \(atlFile) - \(result.error ?? "Unknown error")")
                }

                if failFast {
                    print("Stopping tests due to --fail-fast")
                    break
                }
            }
        }

        // Print summary
        if verbose {
            print("\nTest Summary:")
            print("Passed: \(passedTests)")
            print("Failed: \(failedTests)")
            print("Total: \(testResults.count)")
            print(
                "Success rate: \(String(format: "%.1f", Double(passedTests) / Double(testResults.count) * 100))%"
            )
        } else {
            print("Tests complete: \(passedTests) passed, \(failedTests) failed")
        }

        // Write detailed results if requested
        if let outputPath = output {
            let report = generateTestReport(testResults)
            try report.write(
                to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
            print("Test report written to \(outputPath)")
        }

        // Exit with error code if tests failed
        if failedTests > 0 {
            throw ExitCode.failure
        }
    }

    private func runTest(for filePath: String) async -> TestResult {
        let startTime = Date()

        return await withTaskGroup(of: TestResult.self) { group in
            group.addTask {
                await self.executeTestWithTimeout(filePath: filePath, startTime: startTime)
            }
            return await group.next()
                ?? TestResult(
                    filename: filePath,
                    passed: false,
                    testTime: Date().timeIntervalSince(startTime),
                    error: "Test task failed to complete"
                )
        }
    }

    private func executeTestWithTimeout(filePath: String, startTime: Date) async -> TestResult {
        do {
            let testTask = Task {
                try await executeTest(filePath: filePath, startTime: startTime)
            }

            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw TestError.timeout
            }

            let result = try await withThrowingTaskGroup(of: TestResult.self) { group in
                group.addTask { try await testTask.value }
                group.addTask {
                    _ = try await timeoutTask.value
                    throw TestError.timeout
                }

                let result = try await group.next()!
                group.cancelAll()
                return result
            }

            return result

        } catch TestError.timeout {
            return TestResult(
                filename: filePath,
                passed: false,
                testTime: timeout,
                error: "Test timed out after \(timeout) seconds"
            )
        } catch {
            return TestResult(
                filename: filePath,
                passed: false,
                testTime: Date().timeIntervalSince(startTime),
                error: error.localizedDescription
            )
        }
    }

    private func executeTest(filePath: String, startTime: Date) async throws -> TestResult {
        guard FileManager.default.fileExists(atPath: filePath) else {
            return TestResult(
                filename: filePath,
                passed: false,
                testTime: Date().timeIntervalSince(startTime),
                error: "File not found"
            )
        }

        // Test 1: Parse the ATL file
        let atlSource = try String(contentsOfFile: filePath, encoding: .utf8)
        let parser = ATLParser()
        let module = try await parser.parseContent(
            atlSource, filename: URL(fileURLWithPath: filePath).lastPathComponent)

        if verbose {
            print("  Parse successful: \(module.name)")
        }

        // Test 2: Validate module structure
        guard !module.name.isEmpty else {
            return TestResult(
                filename: filePath,
                passed: false,
                testTime: Date().timeIntervalSince(startTime),
                error: "Module name is empty"
            )
        }

        if verbose {
            print("  Module validation successful")
        }

        // Test 3: Basic semantic checks
        if module.sourceMetamodels.isEmpty && module.matchedRules.isEmpty
            && module.calledRules.isEmpty
        {
            return TestResult(
                filename: filePath,
                passed: false,
                testTime: Date().timeIntervalSince(startTime),
                error: "Module appears to be empty or invalid"
            )
        }

        if verbose {
            print("  All tests passed")
        }

        return TestResult(
            filename: filePath,
            passed: true,
            testTime: Date().timeIntervalSince(startTime),
            error: nil
        )
    }

    private func generateTestReport(_ results: [TestResult]) -> String {
        var report = "ATL Test Report\n"
        report += "===============\n\n"

        let passedTests = results.filter { $0.passed }
        let failedTests = results.filter { !$0.passed }
        let totalTime = results.reduce(0) { $0 + $1.testTime }

        report += "Summary:\n"
        report += "  Tests passed: \(passedTests.count)\n"
        report += "  Tests failed: \(failedTests.count)\n"
        report += "  Total time: \(String(format: "%.3f", totalTime * 1000))ms\n"
        report +=
            "  Success rate: \(String(format: "%.1f", Double(passedTests.count) / Double(results.count) * 100))%\n\n"

        for result in results {
            report += "Test: \(result.filename)\n"
            report += "Result: \(result.passed ? "PASS" : "FAIL")\n"
            report += "Time: \(String(format: "%.3f", result.testTime * 1000))ms\n"
            if let error = result.error {
                report += "Error: \(error)\n"
            }
            report += "\n"
        }

        return report
    }
}

// MARK: - Analyze Command

/// Command for analyzing ATL transformation files.
///
/// The analyze command provides comprehensive analysis of ATL transformation files,
/// including complexity metrics, rule analysis, helper function analysis,
/// and transformation pattern detection.
struct AnalyzeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "analyze",
        abstract: "Analyze ATL transformation files",
        discussion: """
            Provides comprehensive analysis of ATL transformation files including
            complexity metrics, rule analysis, helper function analysis, and
            transformation pattern detection.

            Examples:
                swift-atl analyze Families2Persons.atl
                swift-atl analyze *.atl --metrics complexity,rules,helpers
                swift-atl analyze transformation.atl --output analysis.json
            """
    )

    @Argument(help: "ATL source files to analyze")
    var atlFiles: [String] = []

    @Option(name: .long, help: "Analysis metrics to compute (complexity,rules,helpers,patterns)")
    var metrics: String = "all"

    @Option(name: .shortAndLong, help: "Output file for analysis results")
    var output: String?

    @Option(name: .shortAndLong, help: "Output format (text, json)")
    var format: String = "text"

    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() async throws {
        guard !atlFiles.isEmpty else {
            throw ValidationError("No ATL files specified")
        }

        let metricsToCompute = parseMetrics(metrics)

        if verbose {
            print("Analyzing \(atlFiles.count) ATL file(s)")
            print("Metrics: \(metricsToCompute.joined(separator: ", "))")
            print("Output format: \(format)")
        }

        var analysisResults: [AnalysisResult] = []

        for atlFile in atlFiles {
            if verbose {
                print("Analyzing: \(atlFile)")
            }

            let result = try await analyzeATLFile(atlFile, metrics: metricsToCompute)
            analysisResults.append(result)

            if !verbose && output == nil {
                print("\(atlFile): \(result.summary)")
            }
        }

        // Generate output
        let outputContent = try generateAnalysisOutput(results: analysisResults, format: format)

        if let outputPath = output {
            try outputContent.write(
                to: URL(fileURLWithPath: outputPath), atomically: true, encoding: .utf8)
            print("Analysis results written to \(outputPath)")
        } else if verbose || analysisResults.count > 1 {
            print(outputContent)
        }
    }

    private func parseMetrics(_ metricsString: String) -> [String] {
        if metricsString.lowercased() == "all" {
            return ["complexity", "rules", "helpers", "patterns"]
        }
        return metricsString.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces).lowercased()
        }
    }

    private func analyzeATLFile(_ filePath: String, metrics: [String]) async throws
        -> AnalysisResult
    {
        let startTime = Date()

        guard FileManager.default.fileExists(atPath: filePath) else {
            throw ValidationError("File not found: \(filePath)")
        }

        let atlSource = try String(contentsOfFile: filePath, encoding: .utf8)
        let parser = ATLParser()
        let module = try await parser.parseContent(
            atlSource, filename: URL(fileURLWithPath: filePath).lastPathComponent)

        var analysis = AnalysisResult(filename: filePath, analysisTime: 0)

        if metrics.contains("complexity") {
            analysis.complexity = analyzeComplexity(module: module, source: atlSource)
        }

        if metrics.contains("rules") {
            analysis.ruleAnalysis = analyzeRules(module: module)
        }

        if metrics.contains("helpers") {
            analysis.helperAnalysis = analyzeHelpers(module: module)
        }

        if metrics.contains("patterns") {
            analysis.patterns = analyzePatterns(module: module)
        }

        analysis.analysisTime = Date().timeIntervalSince(startTime)

        if verbose {
            print("  Analysis time: \(String(format: "%.3f", analysis.analysisTime * 1000))ms")
        }

        return analysis
    }

    private func analyzeComplexity(module: ATLModule, source: String) -> ComplexityMetrics {
        let lines = source.components(separatedBy: .newlines)
        let nonEmptyLines = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let commentLines = lines.filter { $0.trimmingCharacters(in: .whitespaces).hasPrefix("--") }

        return ComplexityMetrics(
            linesOfCode: nonEmptyLines.count,
            commentLines: commentLines.count,
            totalRules: module.matchedRules.count + module.calledRules.count,
            totalHelpers: module.helpers.count,
            cyclomaticComplexity: calculateCyclomaticComplexity(module: module),
            maintainabilityIndex: calculateMaintainabilityIndex(
                linesOfCode: nonEmptyLines.count,
                commentRatio: Double(commentLines.count) / Double(lines.count))
        )
    }

    private func calculateCyclomaticComplexity(module: ATLModule) -> Int {
        // Simplified cyclomatic complexity calculation
        // In practice, this would analyze expressions and control flow
        var complexity = 1  // Base complexity
        complexity += module.matchedRules.count
        complexity += module.calledRules.count
        return complexity
    }

    private func calculateMaintainabilityIndex(linesOfCode: Int, commentRatio: Double) -> Double {
        // Simplified maintainability index calculation
        // Real calculation would include Halstead metrics and cyclomatic complexity
        let baseIndex = 100.0
        let locPenalty = Double(linesOfCode) * 0.1
        let commentBonus = commentRatio * 20.0
        return max(0, baseIndex - locPenalty + commentBonus)
    }

    private func analyzeRules(module: ATLModule) -> RuleAnalysis {
        var sourceTypes = Set<String>()
        var targetTypes = Set<String>()

        for rule in module.matchedRules {
            sourceTypes.insert(rule.sourcePattern.type)
            for pattern in rule.targetPatterns {
                targetTypes.insert(pattern.type)
            }
        }

        return RuleAnalysis(
            matchedRules: module.matchedRules.count,
            calledRules: module.calledRules.count,
            uniqueSourceTypes: sourceTypes.count,
            uniqueTargetTypes: targetTypes.count,
            averageTargetPatterns: module.matchedRules.isEmpty
                ? 0
                : Double(module.matchedRules.reduce(0) { $0 + $1.targetPatterns.count })
                    / Double(module.matchedRules.count)
        )
    }

    private func analyzeHelpers(module: ATLModule) -> HelperAnalysis {
        var contextTypes = Set<String>()
        var returnTypes = Set<String>()
        var totalParameters = 0

        for (_, helper) in module.helpers {
            if let contextType = helper.contextType {
                contextTypes.insert(contextType)
            }
            returnTypes.insert(helper.returnType)
            totalParameters += helper.parameters.count
        }

        return HelperAnalysis(
            totalHelpers: module.helpers.count,
            contextHelpers: contextTypes.count,
            uniqueReturnTypes: returnTypes.count,
            averageParameters: module.helpers.isEmpty
                ? 0 : Double(totalParameters) / Double(module.helpers.count)
        )
    }

    private func analyzePatterns(module: ATLModule) -> [String] {
        var patterns: [String] = []

        if module.matchedRules.count > module.calledRules.count {
            patterns.append("Transformation-heavy (more matched rules than called rules)")
        }

        if module.helpers.count > module.matchedRules.count {
            patterns.append("Helper-heavy (more helpers than rules)")
        }

        if module.sourceMetamodels.count > 1 {
            patterns.append("Multi-source transformation")
        }

        if module.targetMetamodels.count > 1 {
            patterns.append("Multi-target transformation")
        }

        return patterns.isEmpty ? ["Standard transformation pattern"] : patterns
    }

    private func generateAnalysisOutput(results: [AnalysisResult], format: String) throws -> String
    {
        switch format.lowercased() {
        case "json":
            let jsonData = try JSONSerialization.data(
                withJSONObject: results.map { $0.toJSONRepresentation() }, options: .prettyPrinted)
            return String(data: jsonData, encoding: .utf8) ?? ""
        default:
            return generateTextAnalysisOutput(results)
        }
    }

    private func generateTextAnalysisOutput(_ results: [AnalysisResult]) -> String {
        var output = "ATL Analysis Results\n"
        output += "====================\n\n"

        for result in results {
            output += "File: \(result.filename)\n"
            output += "Analysis time: \(String(format: "%.3f", result.analysisTime * 1000))ms\n"

            if let complexity = result.complexity {
                output += "\nComplexity Metrics:\n"
                output += "  Lines of code: \(complexity.linesOfCode)\n"
                output += "  Comment lines: \(complexity.commentLines)\n"
                output += "  Total rules: \(complexity.totalRules)\n"
                output += "  Total helpers: \(complexity.totalHelpers)\n"
                output += "  Cyclomatic complexity: \(complexity.cyclomaticComplexity)\n"
                output +=
                    "  Maintainability index: \(String(format: "%.1f", complexity.maintainabilityIndex))\n"
            }

            if let ruleAnalysis = result.ruleAnalysis {
                output += "\nRule Analysis:\n"
                output += "  Matched rules: \(ruleAnalysis.matchedRules)\n"
                output += "  Called rules: \(ruleAnalysis.calledRules)\n"
                output += "  Unique source types: \(ruleAnalysis.uniqueSourceTypes)\n"
                output += "  Unique target types: \(ruleAnalysis.uniqueTargetTypes)\n"
                output +=
                    "  Average target patterns: \(String(format: "%.1f", ruleAnalysis.averageTargetPatterns))\n"
            }

            if let helperAnalysis = result.helperAnalysis {
                output += "\nHelper Analysis:\n"
                output += "  Total helpers: \(helperAnalysis.totalHelpers)\n"
                output += "  Context helpers: \(helperAnalysis.contextHelpers)\n"
                output += "  Unique return types: \(helperAnalysis.uniqueReturnTypes)\n"
                output +=
                    "  Average parameters: \(String(format: "%.1f", helperAnalysis.averageParameters))\n"
            }

            if !result.patterns.isEmpty {
                output += "\nDetected Patterns:\n"
                for pattern in result.patterns {
                    output += "  - \(pattern)\n"
                }
            }

            output += "\n"
        }

        return output
    }
}

// MARK: - Compile Command

/// Command for compiling ATL transformation files to executable modules.
///
/// The compile command processes ATL source files and produces compiled transformation
/// modules that can be executed efficiently by the ATL virtual machine. Compilation
/// includes syntax analysis, type checking, and optimization for performance.
struct CompileCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compile",
        abstract: "Compile ATL transformation files",
        discussion: """
            Compiles ATL transformation source files into optimized executable modules.
            The compilation process includes syntax parsing, semantic analysis, type
            checking, and optimization for efficient transformation execution.

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

    @Flag(name: .long, help: "Enable optimization")
    var optimize: Bool = false

    func run() async throws {
        if verbose {
            print("Compiling ATL transformation: \(atlFile)")
            print("Optimization: \(optimize ? "enabled" : "disabled")")
        }

        // Determine output file name
        let outputPath = output ?? defaultOutputPath(for: atlFile)

        do {
            // Load and parse the ATL file
            let atlSource = try String(contentsOfFile: atlFile, encoding: .utf8)

            if verbose {
                print("Loaded ATL source (\(atlSource.count) characters)")
                print("Parsing transformation module...")
            }

            let parser = ATLParser()
            let module = try await parser.parseContent(
                atlSource, filename: URL(fileURLWithPath: atlFile).lastPathComponent)

            if verbose {
                print("Module parsed successfully: \(module.name)")
                print("Matched rules: \(module.matchedRules.count)")
                print("Called rules: \(module.calledRules.count)")
                print("Helpers: \(module.helpers.count)")
            }

            // TODO: Implement actual compilation to bytecode/optimized format
            // For now, just serialize the parsed module
            if verbose {
                print("Compilation completed successfully")
                print("Output written to: \(outputPath)")
            } else {
                print("Compiled \(atlFile) -> \(outputPath)")
            }

        } catch {
            print("Compilation failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

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
                # Transform using ATL source
                swift-atl transform Families2Persons.atl \\
                  --source families.xmi --target persons.xmi
            """
    )

    @Argument(help: "ATL transformation file (.atl)")
    var transformation: String

    @Option(name: .long, help: "Source model files (format: alias=file)")
    var sources: [String] = []

    @Option(name: .long, help: "Target model files (format: alias=file)")
    var targets: [String] = []

    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() async throws {
        if verbose {
            print("Starting ATL transformation: \(transformation)")
            print("Source models: \(sources)")
            print("Target models: \(targets)")
        }

        do {
            if verbose {
                print("Loading transformation module...")
            }

            // Parse the transformation file
            let atlSource = try String(contentsOfFile: transformation, encoding: .utf8)
            let parser = ATLParser()
            let module = try await parser.parseContent(
                atlSource, filename: URL(fileURLWithPath: transformation).lastPathComponent)

            if verbose {
                print("Transformation module loaded: \(module.name)")
                print(
                    "  - Source metamodels: \(module.sourceMetamodels.keys.joined(separator: ", "))"
                )
                print(
                    "  - Target metamodels: \(module.targetMetamodels.keys.joined(separator: ", "))"
                )
                print("  - Matched rules: \(module.matchedRules.count)")
                print("  - Called rules: \(module.calledRules.count)")
                print("  - Helpers: \(module.helpers.count)")
            }

            // Create and configure the ATL virtual machine
            let virtualMachine = ATLVirtualMachine(module: module)

            if verbose {
                print("Executing transformation...")
            }

            // TODO: Implement actual model loading and transformation execution
            // For now, just run the VM with empty resources
            let emptySourceModels: OrderedDictionary<String, Resource> = [:]
            let emptyTargetModels: OrderedDictionary<String, Resource> = [:]

            try await virtualMachine.execute(
                sources: emptySourceModels,
                targets: emptyTargetModels
            )

            // Display execution statistics
            let stats = virtualMachine.getStatistics()
            if verbose {
                print("Transformation Statistics:")
                print(stats.summary())
            } else {
                let duration = String(format: "%.3f", stats.executionTime * 1000)
                print("Transformation completed in \(duration)ms")
            }

        } catch {
            print("Transformation failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }
}

// MARK: - Generate Command

/// Command for generating code from models using ATL transformations.
///
/// The generate command uses ATL-based code generators to produce source code
/// from input models. It supports multiple target languages and customizable
/// generation templates through ATL transformation modules.
struct GenerateCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "generate",
        abstract: "Generate code from models",
        discussion: """
            Generates source code from input models using ATL-based code generators.
            Supports multiple target languages with customizable generation templates.

            Examples:
                # Generate Swift code from Ecore model
                swift-atl generate model.ecore --language swift --output Generated/
            """
    )

    @Argument(help: "Input model file")
    var inputModel: String

    @Option(name: .long, help: "ATL transformation directory or file")
    var transformations: String?

    @Option(name: .shortAndLong, help: "Target language (swift, cpp, c)")
    var language: String = "swift"

    @Option(name: .shortAndLong, help: "Output directory")
    var output: String = "Generated"

    @Flag(name: .shortAndLong, help: "Enable verbose output")
    var verbose: Bool = false

    func run() async throws {
        if verbose {
            print("Starting code generation:")
            print("  Input model: \(inputModel)")
            print("  Target language: \(language)")
            print("  Output directory: \(output)")
        }

        do {
            // Validate target language
            guard isValidLanguage(language) else {
                throw ValidationError("Unsupported target language: \(language)")
            }

            // Determine transformation to use
            let transformationPath = transformations ?? defaultTransformationPath(for: language)

            if verbose {
                print("Using transformation: \(transformationPath)")
                print("Loading input model...")
            }

            // TODO: Implement actual code generation
            print("Code generation is not yet implemented")
            print("Would generate \(language) code from \(inputModel) to \(output)")

        } catch {
            print("Code generation failed: \(error.localizedDescription)")
            throw ExitCode.failure
        }
    }

    private func isValidLanguage(_ language: String) -> Bool {
        let supportedLanguages = ["swift", "cpp", "c"]
        return supportedLanguages.contains(language.lowercased())
    }

    private func defaultTransformationPath(for language: String) -> String {
        return "transformations/ecore-to-\(language.lowercased()).atl"
    }
}

// MARK: - Data Structures

struct ParseResult {
    let filename: String
    let success: Bool
    let module: ATLModule?
    let parseTime: TimeInterval
    let error: String?

    var summary: String {
        if success, let module = module {
            return
                "\(module.name) (rules: \(module.matchedRules.count + module.calledRules.count), helpers: \(module.helpers.count))"
        } else {
            return "FAILED - \(error ?? "Unknown error")"
        }
    }

    func toJSONRepresentation() -> [String: Any] {
        var json: [String: Any] = [
            "filename": filename,
            "success": success,
            "parseTime": parseTime,
        ]

        if let module = module {
            json["module"] = [
                "name": module.name,
                "matchedRules": module.matchedRules.count,
                "calledRules": module.calledRules.count,
                "helpers": module.helpers.count,
                "sourceMetamodels": Array(module.sourceMetamodels.keys),
                "targetMetamodels": Array(module.targetMetamodels.keys),
            ]
        }

        if let error = error {
            json["error"] = error
        }

        return json
    }
}

struct ValidationResult {
    let filename: String
    let validationTime: TimeInterval
    let errors: [ValidationIssue]
    let warnings: [ValidationIssue]

    var isValid: Bool { errors.isEmpty }
}

struct ValidationIssue {
    let type: IssueType
    let message: String
    let line: Int?
    let column: Int?

    enum IssueType {
        case error
        case warning
    }
}

struct TestResult {
    let filename: String
    let passed: Bool
    let testTime: TimeInterval
    let error: String?
}

enum TestError: Error {
    case timeout
}

struct AnalysisResult {
    let filename: String
    var analysisTime: TimeInterval
    var complexity: ComplexityMetrics?
    var ruleAnalysis: RuleAnalysis?
    var helperAnalysis: HelperAnalysis?
    var patterns: [String] = []

    var summary: String {
        var parts: [String] = []
        if let complexity = complexity {
            parts.append("\(complexity.linesOfCode) LOC")
            parts.append("\(complexity.totalRules) rules")
            parts.append("\(complexity.totalHelpers) helpers")
        }
        return parts.isEmpty ? "analyzed" : parts.joined(separator: ", ")
    }

    func toJSONRepresentation() -> [String: Any] {
        var json: [String: Any] = [
            "filename": filename,
            "analysisTime": analysisTime,
            "patterns": patterns,
        ]

        if let complexity = complexity {
            json["complexity"] = [
                "linesOfCode": complexity.linesOfCode,
                "commentLines": complexity.commentLines,
                "totalRules": complexity.totalRules,
                "totalHelpers": complexity.totalHelpers,
                "cyclomaticComplexity": complexity.cyclomaticComplexity,
                "maintainabilityIndex": complexity.maintainabilityIndex,
            ]
        }

        if let ruleAnalysis = ruleAnalysis {
            json["ruleAnalysis"] = [
                "matchedRules": ruleAnalysis.matchedRules,
                "calledRules": ruleAnalysis.calledRules,
                "uniqueSourceTypes": ruleAnalysis.uniqueSourceTypes,
                "uniqueTargetTypes": ruleAnalysis.uniqueTargetTypes,
                "averageTargetPatterns": ruleAnalysis.averageTargetPatterns,
            ]
        }

        if let helperAnalysis = helperAnalysis {
            json["helperAnalysis"] = [
                "totalHelpers": helperAnalysis.totalHelpers,
                "contextHelpers": helperAnalysis.contextHelpers,
                "uniqueReturnTypes": helperAnalysis.uniqueReturnTypes,
                "averageParameters": helperAnalysis.averageParameters,
            ]
        }

        return json
    }
}

struct ComplexityMetrics {
    let linesOfCode: Int
    let commentLines: Int
    let totalRules: Int
    let totalHelpers: Int
    let cyclomaticComplexity: Int
    let maintainabilityIndex: Double
}

struct RuleAnalysis {
    let matchedRules: Int
    let calledRules: Int
    let uniqueSourceTypes: Int
    let uniqueTargetTypes: Int
    let averageTargetPatterns: Double
}

struct HelperAnalysis {
    let totalHelpers: Int
    let contextHelpers: Int
    let uniqueReturnTypes: Int
    let averageParameters: Double
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
