//
//  ATLXMIPortabilityTests.swift
//  ATLTests
//
//  Created by Rene Hexel on 5/10/2026.
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import Foundation
import Testing

@testable import ATL

/// Tests for XML edge cases handled by the ATL XMI parsers: namespaces, entities, CDATA and malformed input.
@Suite("ATL XMI Portability Tests")
struct ATLXMIPortabilityTests {

    private let expressionParser = ATLExpressionXMIParser()
    private let moduleParser = ATLXMIParser()

    private func literal(_ expression: any ATLExpression) -> ATLLiteralExpression? {
        expression as? ATLLiteralExpression
    }

    // MARK: - Expression parser

    @Test("Prefixed xsi:type and namespace declarations are accepted")
    func namespacedExpression() throws {
        let xmi = """
            <?xml version="1.0" encoding="UTF-8"?>
            <atl:OclExpression xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                xmlns:atl="http://www.eclipse.org/gmt/2005/ATL"
                xmlns:ocl="http://www.eclipse.org/gmt/2005/OCL">
              <expression xsi:type="ocl:VariableExp" varName="x"/>
            </atl:OclExpression>
            """
        let expression = try expressionParser.parse(xmi)
        #expect((expression as? ATLVariableExpression)?.name == "x")
    }

    @Test("Predefined and numeric entities in attribute values are decoded")
    func entitiesInAttributes() throws {
        let xmi = """
            <root><expression type="StringExp" stringSymbol="a &amp; b &lt;c&gt; &quot;d&quot; &#233;"/></root>
            """
        let value = try #require(literal(try expressionParser.parse(xmi)))
        #expect(value.value as? String == "a & b <c> \"d\" é")
    }

    @Test("Attribute order does not affect parsing")
    func attributeOrder() throws {
        let first = try expressionParser.parse(
            #"<r><expression type="IntegerExp" integerSymbol="7"/></r>"#)
        let second = try expressionParser.parse(
            #"<r><expression integerSymbol="7" type="IntegerExp"/></r>"#)
        #expect(literal(first)?.value as? Int == 7)
        #expect(literal(second)?.value as? Int == 7)
    }

    @Test("CDATA sections and comments around expressions are ignored")
    func cdataAndComments() throws {
        let xmi = """
            <r><!-- note --><![CDATA[ ignored text ]]>
            <expression type="BooleanExp" booleanSymbol="true"/></r>
            """
        #expect(literal(try expressionParser.parse(xmi))?.value as? Bool == true)
    }

    @Test("The root element itself may be the expression")
    func rootIsExpression() throws {
        let xmi = #"<expression type="IntegerExp" integerSymbol="3"/>"#
        #expect(literal(try expressionParser.parse(xmi))?.value as? Int == 3)
    }

    @Test("Malformed XML is rejected", arguments: ["", "<a><b></a>", "not xml", "<a"])
    func malformedExpression(xmi: String) {
        #expect(throws: (any Error).self) { try expressionParser.parse(xmi) }
    }

    @Test("A document without an expression element is reported")
    func noExpression() {
        #expect(throws: ExpressionParseError.self) { try expressionParser.parse("<r><other/></r>") }
    }

    // MARK: - Module parser

    @Test("A prefixed module with metamodels, helpers and rules parses in document order")
    func namespacedModule() throws {
        let xmi = """
            <?xml version="1.0" encoding="UTF-8"?>
            <atl:Module xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
                xmlns:atl="http://www.eclipse.org/gmt/2005/ATL" name="M">
              <inModels name="Src" metamodel="http://src" kind="IN"/>
              <inModels name="Dst" metamodel="http://dst" kind="OUT"/>
              <elements xsi:type="atl:MatchedRule" name="R1"/>
              <elements xsi:type="atl:CalledRule" name="C1"/>
              <elements xsi:type="atl:LazyMatchedRule" name="L1"/>
              <helpers name="h"/>
            </atl:Module>
            """
        let module = try moduleParser.parse(xmi)
        #expect(module.name == "M")
        #expect(module.sourceMetamodels["Src"]?.nsURI == "http://src")
        #expect(module.targetMetamodels["Dst"]?.nsURI == "http://dst")
        #expect(module.matchedRules.map(\.name) == ["R1", "L1"])
        #expect(module.calledRules.keys.contains("C1"))
        #expect(module.helpers.keys.contains("h"))
    }

    @Test("Entities and CDATA in a module document are handled")
    func moduleEntitiesAndCDATA() throws {
        let xmi = """
            <Module name="A&amp;B"><![CDATA[ text ]]><!-- c --></Module>
            """
        let module = try moduleParser.parse(xmi)
        #expect(module.name == "A&B")
        #expect(module.sourceMetamodels["IN"] != nil)
        #expect(module.targetMetamodels["OUT"] != nil)
    }

    @Test("Malformed module XML is reported as a parsing error", arguments: ["", "<Module name=\"x\">", "plain"])
    func malformedModule(xmi: String) {
        #expect(throws: ATLResourceError.self) { try moduleParser.parse(xmi) }
    }

    @Test("A document without a named module is reported")
    func noModule() {
        #expect(throws: ATLResourceError.self) { try moduleParser.parse("<Other/>") }
    }
}
