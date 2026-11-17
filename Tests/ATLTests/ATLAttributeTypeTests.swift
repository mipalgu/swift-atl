//
//  ATLAttributeTypeTests.swift
//  ATLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import Testing

@testable import ATL

/// Tests that values assigned to attributes of the primitive Ecore types have the type of
/// the attribute, as the Eclipse Modeling Framework requires.
@Suite("ATL Attribute Type Tests")
@MainActor
struct ATLAttributeTypeTests {

    private let fixture = ReportFixture()

    /// A rule that creates one document and binds its attributes.
    private func documentRule(_ bindings: String) -> String {
        """
        rule P {
            from s : Project!Project
            to t : Report!Document (name <- s.name, \(bindings))
        }
        """
    }

    /// The description of the error that binding the attributes raises.
    private func bindingError(_ bindings: String, options: ATLOptions = .standard) async -> String? {
        await thrownDescription {
            _ = try await fixture.run(documentRule(bindings), options: options)
        }
    }

    // MARK: - Integer Attributes

    @Test("A Real bound to an EInt attribute is a type error naming the attribute and both types")
    func realToInteger() async throws {
        let message = try #require(await bindingError("completionRate <- (1 * 100) / 3"))
        #expect(message.contains("completionRate"))
        #expect(message.contains("Document"))
        #expect(message.contains("EInt"))
        #expect(message.contains("Real"))
        #expect(message.contains("div"))
    }

    @Test("A Real with an integral value bound to an EInt attribute is a type error")
    func integralRealToInteger() async throws {
        let message = try #require(await bindingError("completionRate <- 8 / 2"))
        #expect(message.contains("completionRate"))
        #expect(message.contains("Real"))
    }

    @Test("The type error is raised as a type error and stops the run")
    func typeErrorKind() async throws {
        await #expect {
            _ = try await fixture.run(documentRule("completionRate <- 1 / 3"))
        } throws: { error in
            guard case ATLExecutionError.typeError = error else { return false }
            return true
        }
    }

    @Test(
        "Values of other types bound to an integer attribute are type errors",
        arguments: [
            ("completionRate <- 'many'", "String"),
            ("completionRate <- true", "Boolean"),
            ("total <- 2.5", "Real"),
        ])
    func otherTypesToInteger(binding: String, typeName: String) async throws {
        let message = try #require(await bindingError(binding))
        #expect(message.contains(typeName))
    }

    @Test("Integers, integer division and rounded quotients are accepted by integer attributes")
    func integersAccepted() async throws {
        let run = try await fixture.run(
            documentRule("completionRate <- (1 * 100) div 3, total <- (7 / 2).round()"))
        let document = try await run.document()
        #expect(await run.value("completionRate", of: document) as? Int == 33)
        #expect(await run.value("total", of: document) as? Int == 4)
    }

    @Test("With the legacy options, the truncated quotient of two Integers is accepted")
    func legacyDivision() async throws {
        let run = try await fixture.run(
            documentRule("completionRate <- (1 * 100) / 3"), options: .legacy)
        #expect(await run.value("completionRate", of: try await run.document()) as? Int == 33)
    }

    @Test("An undefined value leaves an integer attribute unset")
    func undefinedToInteger() async throws {
        let run = try await fixture.run(documentRule("completionRate <- OclUndefined"))
        #expect(await run.value("completionRate", of: try await run.document()) == nil)
    }

    @Test("Each element of a many-valued integer attribute must be an Integer")
    func manyValuedInteger() async throws {
        let message = try #require(await bindingError("scores <- Sequence{1, 2.5}"))
        #expect(message.contains("scores"))
        #expect(message.contains("Real"))

        let run = try await fixture.run(documentRule("scores <- Sequence{1, 2}"))
        #expect(await run.value("scores", of: try await run.document()) as? [Int] == [1, 2])
    }

    // MARK: - Real Attributes

    @Test("Integers bound to real attributes become Reals")
    func integerToReal() async throws {
        let run = try await fixture.run(documentRule("ratio <- 3, weight <- 2"))
        let document = try await run.document()
        #expect(await run.value("ratio", of: document) as? Double == 3.0)
        #expect(await run.value("weight", of: document) as? Double == 2.0)
    }

    @Test("A String bound to a real attribute is a type error")
    func stringToReal() async throws {
        let message = try #require(await bindingError("ratio <- 'half'"))
        #expect(message.contains("ratio"))
        #expect(message.contains("EDouble"))
        #expect(message.contains("String"))
    }

    // MARK: - Boolean and String Attributes

    @Test(
        "Values other than Booleans bound to a Boolean attribute are type errors",
        arguments: [("done <- 1", "Integer"), ("done <- 'yes'", "String")])
    func otherTypesToBoolean(binding: String, typeName: String) async throws {
        let message = try #require(await bindingError(binding))
        #expect(message.contains("done"))
        #expect(message.contains("EBoolean"))
        #expect(message.contains(typeName))
    }

    @Test("A number bound to a String attribute is a type error")
    func numberToString() async throws {
        let message = try #require(await bindingError("name <- 42"))
        #expect(message.contains("name"))
        #expect(message.contains("EString"))
        #expect(message.contains("Integer"))
    }

    @Test("Attributes of data types other than the primitive Ecore types take any value")
    func customDataType() async throws {
        let run = try await fixture.run(documentRule("note <- 42"))
        #expect(await run.value("note", of: try await run.document()) as? Int == 42)
    }

    // MARK: - Other Assignments

    @Test("An assignment in a do section is checked like a binding")
    func imperativeAssignment() async throws {
        let message = try #require(
            await thrownDescription {
                _ = try await fixture.run(
                    """
                    rule P {
                        from s : Project!Project
                        to t : Report!Document (name <- s.name)
                        do { t.completionRate <- 1 / 3; }
                    }
                    """)
            })
        #expect(message.contains("completionRate"))
        #expect(message.contains("Real"))
    }

    @Test("The value is converted and checked before it is stored")
    func preparedValues() throws {
        let rate = try #require(fixture.documentClass.getStructuralFeature(name: "completionRate"))
        let ratio = try #require(fixture.documentClass.getStructuralFeature(name: "ratio"))
        #expect(try ATLValueConversion.prepare(7, for: rate) as? Int == 7)
        #expect(try ATLValueConversion.prepare(7, for: ratio) as? Double == 7.0)
        #expect(try ATLValueConversion.prepare(Float(1.5), for: ratio) as? Float == 1.5)
        #expect(try ATLValueConversion.prepare(Int16(3), for: rate) as? Int16 == 3)
        #expect(throws: ATLExecutionError.self) { try ATLValueConversion.prepare(7.5, for: rate) }
    }

    @Test("Decimal attributes take Integers and Reals as they are")
    func decimalValues() throws {
        let amount = EAttribute(name: "amount", eType: EDataType(name: EcoreDataType.eBigDecimal.rawValue))
        #expect(try ATLValueConversion.prepare(7, for: amount) as? Int == 7)
        let quarter = try #require(Decimal(string: "1.25"))
        #expect(try ATLValueConversion.prepare(quarter, for: amount) as? Decimal == quarter)
        let message = try #require(
            thrownDescription { _ = try ATLValueConversion.prepare("much", for: amount) })
        #expect(
            message
                == "Type error: cannot assign the String value 'much' to attribute 'amount', "
                + "whose type is EBigDecimal")
    }
}
