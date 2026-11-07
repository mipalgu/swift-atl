//
//  ATLHelperBodyTests.swift
//  ATLTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ATL
import ECore
import EMFBase
import Testing

/// Verifies that tools outside the module can read the body expression of any helper
/// through ``ATLHelperType``, whichever concrete type holds it.
@Suite("Helper body expressions")
struct ATLHelperBodyTests {
    @Test("A parsed helper exposes its body expression")
    @MainActor
    func parsedHelper() async throws {
        let module = try await ATLParser().parseContent(
            """
            module M;
            create OUT : B from IN : A;
            helper def : answer : Integer = 42;
            """)
        let helper = try #require(module.helperOverloads["answer"]?.first)
        let body = try #require(helper.expressionBody as? ATLLiteralExpression)
        #expect(body.value as? Int == 42)
    }

    @Test("Helpers built in code expose their body expressions")
    func helpersInCode() {
        let wrapped: any ATLHelperType = ATLHelperWrapper(
            name: "h", returnType: "Integer", body: ATLLiteralExpression(value: 1))
        #expect((wrapped.expressionBody as? ATLLiteralExpression)?.value as? Int == 1)
        let typed: any ATLHelperType = ATLHelper(
            name: "g", returnType: "String", body: ATLVariableExpression(name: "x"))
        #expect((typed.expressionBody as? ATLVariableExpression)?.name == "x")
    }

    @Test("A native helper has no body expression")
    func nativeHelper() {
        let native: any ATLHelperType = ATLNativeHelper(name: "n", returnType: "Integer") { _, _ in 1 }
        #expect(native.expressionBody == nil)
    }
}
