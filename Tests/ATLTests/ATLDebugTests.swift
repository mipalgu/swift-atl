/*
 * ATLDebugTests.swift
 *
 * Debug tests for isolating ATL parsing issues.
 * These tests help identify specific parsing failures in ATL syntax.
 *
 * Created by Swift Modelling Framework
 * Copyright © 2024 Swift Modelling. All rights reserved.
 */

import Foundation
import Testing

@testable import ATL
@testable import ECore

/// Debug test suite for isolating ATL parsing issues.
///
/// This test suite provides focused tests to debug specific parsing failures,
/// allowing for step-by-step analysis of tokenisation and parsing behaviour.
struct ATLDebugTests {

    // MARK: - Simple Parsing Tests

    @Test("Debug simple helper parsing")
    func testSimpleHelperParsing() async throws {
        // Given - simplest possible helper
        let atlContent = """
            module TestModule;
            helper def : simpleHelper() : Integer = 42;
            """

        let parser = ATLParser()

        // When & Then
        do {
            let module = try await parser.parseContent(atlContent, filename: "debug.atl")
            #expect(module.name == "TestModule")
            #expect(module.helpers.count == 1)
        } catch {
            throw error
        }
    }

    @Test("Debug helper with parameters")
    func testHelperWithParameters() async throws {
        // Given - helper with parameters
        let atlContent = """
            module TestModule;
            helper def : add(a : Integer, b : Integer) : Integer = a + b;
            """

        let parser = ATLParser()

        // When & Then
        do {
            let module = try await parser.parseContent(atlContent, filename: "debug.atl")
            #expect(module.name == "TestModule")
            #expect(module.helpers.count == 1)

            let helper = module.helpers.first?.value
            #expect(helper?.name == "add")
            #expect(helper?.parameters.count == 2)
        } catch {
            throw error
        }
    }

    @Test("Debug context helper parsing")
    func testContextHelperParsing() async throws {
        // Given - context helper
        let atlContent = """
            module TestModule;
            helper context String def : isEmpty() : Boolean = self.size() = 0;
            """

        let parser = ATLParser()

        // When & Then
        do {
            let module = try await parser.parseContent(atlContent, filename: "debug.atl")
            #expect(module.name == "TestModule")
            #expect(module.helpers.count == 1)

            let helper = module.helpers.first?.value
            #expect(helper?.name == "isEmpty")
            #expect(helper?.contextType == "String")
        } catch {
            throw error
        }
    }

    @Test("Debug qualified type parsing")
    func testQualifiedTypeParsing() async throws {
        // Given - helper with qualified type
        let atlContent = """
            module TestModule;
            helper context Source!Person def : getName() : String = self.name;
            """

        let parser = ATLParser()

        // When & Then
        do {
            let module = try await parser.parseContent(atlContent, filename: "debug.atl")
            #expect(module.name == "TestModule")
            #expect(module.helpers.count == 1)

            let helper = module.helpers.first?.value
            #expect(helper?.name == "getName")
            #expect(helper?.contextType == "Source!Person")
        } catch {
            throw error
        }
    }

    @Test("Debug generic type parsing")
    func testGenericTypeParsing() async throws {
        // Given - helper with generic type
        let atlContent = """
            module TestModule;
            helper def : getMembers() : Sequence(Person) = Person.allInstances();
            """

        let parser = ATLParser()

        // When & Then
        do {
            let module = try await parser.parseContent(atlContent, filename: "debug.atl")
            #expect(module.name == "TestModule")
            #expect(module.helpers.count == 1)

            let helper = module.helpers.first?.value
            #expect(helper?.name == "getMembers")
            #expect(helper?.returnType == "Sequence(Person)")
        } catch {
            throw error
        }
    }

    @Test("Debug complex generic type parsing")
    func testComplexGenericTypeParsing() async throws {
        // Given - helper with qualified generic type
        let atlContent = """
            module TestModule;
            helper def : getMembers() : Sequence(Families!Member) = Families!Member.allInstances();
            """

        let parser = ATLParser()

        // When & Then
        do {
            let module = try await parser.parseContent(atlContent, filename: "debug.atl")
            #expect(module.name == "TestModule")
            #expect(module.helpers.count == 1)

            let helper = module.helpers.first?.value
            #expect(helper?.name == "getMembers")
            #expect(helper?.returnType == "Sequence(Families!Member)")
        } catch {
            throw error
        }
    }

    // MARK: - Tokenisation Tests

    @Test("Debug tokenisation of helper definition")
    func testHelperTokenisation() async throws {
        // Given - simple helper definition
        let atlContent = "helper def : test() : Integer = 42;"

        // When - tokenise the content
        let lexer = TestATLLexer(content: atlContent)
        let tokens = try lexer.tokenize()

        // Then - check expected tokens
        #expect(tokens.count >= 8)  // helper, def, :, test, (, ), :, Integer, =, 42, ;

        // Check specific tokens
        #expect(tokens[0].type == .keyword("helper"))
        #expect(tokens[1].type == .keyword("def"))
        #expect(tokens[2].type == .operator(":"))
    }

    @Test("Debug tokenisation of context helper")
    func testContextHelperTokenisation() async throws {
        // Given - context helper definition
        let atlContent = "helper context String def : test() : Boolean"

        // When - tokenise the content
        let lexer = TestATLLexer(content: atlContent)
        let tokens = try lexer.tokenize()

        // Check key tokens
        #expect(
            tokens.contains {
                if case .keyword("helper") = $0.type { return true }
                return false
            })
        #expect(
            tokens.contains {
                if case .keyword("context") = $0.type { return true }
                return false
            })
        #expect(
            tokens.contains {
                if case .keyword("String") = $0.type { return true }
                return false
            })
        #expect(
            tokens.contains {
                if case .keyword("def") = $0.type { return true }
                return false
            })
    }

    @Test("Debug tokenisation of qualified type")
    func testQualifiedTypeTokenisation() async throws {
        // Given - qualified type
        let atlContent = "Source!Person"

        // When - tokenise the content
        let lexer = TestATLLexer(content: atlContent)
        let tokens = try lexer.tokenize()

        // Then - check tokens
        #expect(tokens.count >= 3)  // Source, !, Person
        #expect(tokens[0].type == .identifier("Source"))
        #expect(tokens[1].type == .operator("!"))
        #expect(tokens[2].type == .identifier("Person"))
    }

    @Test("Debug tokenisation of generic type")
    func testGenericTypeTokenisation() async throws {
        // Given - generic type
        let atlContent = "Sequence(Families!Member)"

        // When - tokenise the content
        let lexer = TestATLLexer(content: atlContent)
        let tokens = try lexer.tokenize()

        // Then - check tokens
        #expect(tokens.count >= 6)  // Sequence, (, Families, !, Member, )
        #expect(tokens[0].type == .identifier("Sequence"))
        #expect(tokens[1].type == .punctuation("("))
        #expect(tokens[2].type == .identifier("Families"))
        #expect(tokens[3].type == .operator("!"))
        #expect(tokens[4].type == .identifier("Member"))
        #expect(tokens[5].type == .punctuation(")"))
    }

    // MARK: - Step-by-step Parsing Tests

    @Test("Debug parsing steps for HelperFunctions.atl excerpt")
    func testHelperFunctionsExcerpt() async throws {
        // Given - problematic excerpt from HelperFunctions.atl
        let atlContent = """
            module HelperFunctions;
            helper def : addNumbers(a : Integer, b : Integer) : Integer =
                a + b;
            """

        let parser = ATLParser()

        // When & Then
        let module = try await parser.parseContent(atlContent, filename: "debug.atl")
        #expect(module.name == "HelperFunctions")
        #expect(module.helpers.count == 1)
    }

    @Test("Debug parsing steps for Families2Persons.atl excerpt")
    func testFamilies2PersonsExcerpt() async throws {
        // Given - problematic excerpt from Families2Persons.atl
        let atlContent = """
            module Families2Persons;
            helper def: getAdultMembers() : Sequence(Families!Member) =
                Families!Member.allInstances()->select(m | m.age >= 18);
            """

        let parser = ATLParser()

        // When & Then
        let module = try await parser.parseContent(atlContent, filename: "debug.atl")
        #expect(module.name == "Families2Persons")
        #expect(module.helpers.count == 1)
    }

    @Test("Debug method call parsing")
    func testMethodCallParsing() async throws {
        // Given - method call that's causing issues
        let atlContent = """
            module TestModule;
            helper def : testMod() : Boolean = 5.mod(2) = 1;
            """

        let parser = ATLParser()

        // When & Then
        let module = try await parser.parseContent(atlContent, filename: "debug.atl")
        #expect(module.name == "TestModule")
        #expect(module.helpers.count == 1)
    }

    @Test("Debug iterate expression parsing")
    func testIterateExpressionParsing() async throws {
        // Given - iterate expression that's causing issues
        let atlContent = """
            module TestModule;
            helper def : testIterate() : Integer =
                Sequence{1, 2, 3}->iterate(n; sum : Integer = 0 | sum + n);
            """

        let parser = ATLParser()

        // When & Then
        let module = try await parser.parseContent(atlContent, filename: "debug.atl")
        #expect(module.name == "TestModule")
        #expect(module.helpers.count == 1)
    }
}

// MARK: - Test Helper Classes

/// Test-accessible ATL lexer for debugging tokenisation.
private class TestATLLexer {
    private let content: String
    private var position: String.Index
    private var line: Int = 1
    private var column: Int = 1

    private static let keywords: Set<String> = [
        "module", "create", "from", "helper", "def", "context", "rule", "query",
        "if", "then", "else", "endif", "and", "or", "not", "true", "false",
        "let", "in", "do", "to", "self", "Integer", "String", "Boolean", "Real",
    ]

    private static let operators: Set<String> = [
        "+", "-", "*", "/", "=", "<>", "<", ">", "<=", ">=", "->", ".", ":", "<-", "!",
    ]

    private static let punctuation: Set<String> = [
        "(", ")", "{", "}", "[", "]", ";", ",", "|",
    ]

    init(content: String) {
        self.content = content
        self.position = content.startIndex
    }

    func tokenize() throws -> [ATLToken] {
        var tokens: [ATLToken] = []

        while position < content.endIndex {
            let startLine = line
            let startColumn = column

            let char = content[position]

            if char.isWhitespace {
                if char == "\n" {
                    line += 1
                    column = 1
                } else {
                    column += 1
                }
                advance()
                continue
            }

            if char == "-" && peek() == "-" {
                // Skip comment
                while position < content.endIndex && content[position] != "\n" {
                    advance()
                }
                continue
            }

            if char.isLetter || char == "_" {
                let identifier = parseIdentifier(startLine: startLine, startColumn: startColumn)
                tokens.append(identifier)
                continue
            }

            if char.isNumber {
                let number = parseNumber(startLine: startLine, startColumn: startColumn)
                tokens.append(number)
                continue
            }

            if char == "'" {
                let string = try parseString(startLine: startLine, startColumn: startColumn)
                tokens.append(string)
                continue
            }

            // Check for multi-character operators
            let endPos =
                content.index(position, offsetBy: 1, limitedBy: content.endIndex)
                ?? content.endIndex
            let twoCharEndPos =
                content.index(endPos, offsetBy: 1, limitedBy: content.endIndex) ?? content.endIndex
            let twoChar = String(content[position..<twoCharEndPos])
            if Self.operators.contains(twoChar) {
                tokens.append(
                    ATLToken(
                        type: .operator(twoChar), value: twoChar, line: startLine,
                        column: startColumn))
                advance()
                advance()
                continue
            }

            // Single character tokens
            let singleChar = String(char)
            if Self.operators.contains(singleChar) {
                tokens.append(
                    ATLToken(
                        type: .operator(singleChar), value: singleChar, line: startLine,
                        column: startColumn))
                advance()
                continue
            }

            if Self.punctuation.contains(singleChar) {
                tokens.append(
                    ATLToken(
                        type: .punctuation(singleChar), value: singleChar, line: startLine,
                        column: startColumn))
                advance()
                continue
            }

            // Unknown character
            advance()
        }

        return tokens
    }

    private func parseIdentifier(startLine: Int, startColumn: Int) -> ATLToken {
        let start = position

        while position < content.endIndex {
            let char = content[position]
            if char.isLetter || char.isNumber || char == "_" {
                advance()
            } else {
                break
            }
        }

        let value = String(content[start..<position])

        if Self.keywords.contains(value) {
            return ATLToken(
                type: .keyword(value), value: value, line: startLine, column: startColumn)
        } else {
            return ATLToken(
                type: .identifier(value), value: value, line: startLine, column: startColumn)
        }
    }

    private func parseNumber(startLine: Int, startColumn: Int) -> ATLToken {
        let start = position

        while position < content.endIndex
            && (content[position].isNumber || content[position] == ".")
        {
            advance()
        }

        let value = String(content[start..<position])

        if let intValue = Int(value) {
            return ATLToken(
                type: .integerLiteral(intValue), value: value, line: startLine, column: startColumn)
        } else {
            return ATLToken(
                type: .identifier(value), value: value, line: startLine, column: startColumn)
        }
    }

    private func parseString(startLine: Int, startColumn: Int) throws -> ATLToken {
        advance()  // Skip opening quote
        let start = position

        while position < content.endIndex && content[position] != "'" {
            advance()
        }

        guard position < content.endIndex else {
            throw ATLParseError.invalidSyntax("Unterminated string literal")
        }

        let value = String(content[start..<position])
        advance()  // Skip closing quote

        return ATLToken(
            type: .stringLiteral(value), value: value, line: startLine, column: startColumn)
    }

    private func advance() {
        if position < content.endIndex {
            column += 1
            position = content.index(after: position)
        }
    }

    private func peek() -> Character? {
        guard position < content.endIndex else { return nil }
        let nextPosition = content.index(after: position)
        guard nextPosition < content.endIndex else { return nil }
        return content[nextPosition]
    }
}

/// Test token type matching the internal parser token type.
private enum ATLTokenType: Equatable {
    case keyword(String)
    case identifier(String)
    case stringLiteral(String)
    case integerLiteral(Int)
    case booleanLiteral(Bool)
    case `operator`(String)
    case punctuation(String)
    case comment(String)
    case whitespace
    case newline
    case eof
}

/// Test token structure matching the internal parser token structure.
private struct ATLToken: Equatable {
    let type: ATLTokenType
    let value: String
    let line: Int
    let column: Int
}
