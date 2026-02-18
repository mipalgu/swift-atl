//
//  ATLThisModuleTests.swift
//  ATLTests
//
//  Tests for thisModule dispatch, allInstances collection return, callHelper ATL
//  evaluation, collection EcoreValueArray handling, and setElementProperty alias
//  mapping.
//
import ECore
import EMFBase
import OrderedCollections
import Testing

@testable import ATL

/// Tests for `thisModule` dispatch and related fixes.
///
/// Covers all seven originally reported bugs:
/// 1. `thisModule.helper()` / `thisModule.attribute` / `thisModule.calledRule()` dispatch
/// 2. `callHelper` routes through the ATL evaluator (not ECore bridge)
/// 3. `allInstances()` returns `EcoreValueArray` (not `Int`)
/// 4. Collection operations work on `EcoreValueArray`
/// 5. `toCollection(nil)` returns empty collection
/// 6. `setElementProperty` maps metamodel name to model alias
/// 7. Missing dispatch entries (`notEmpty`, `oclIsKindOf`, `mod`, etc.)
@Suite("ATL thisModule Tests")
@MainActor
struct ATLThisModuleTests {

    // MARK: - Test Fixtures

    /// Creates a minimal execution context using the provided module.
    private func makeContext(
        module: ATLModule,
        sources: OrderedDictionary<String, Resource> = [:],
        targets: OrderedDictionary<String, Resource> = [:]
    ) -> ATLExecutionContext {
        ATLExecutionContext(
            module: module,
            sources: sources,
            targets: targets,
            executionEngine: ECoreExecutionEngine(models: [:])
        )
    }

    /// Creates a minimal module with default dummy metamodels.
    private func makeMinimalModule(
        helpers: OrderedDictionary<String, any ATLHelperType> = [:],
        matchedRules: [ATLMatchedRule] = [],
        calledRules: OrderedDictionary<String, ATLCalledRule> = [:]
    ) -> ATLModule {
        ATLModule(
            name: "TestModule",
            sourceMetamodels: [
                "IN": EPackage(name: "Source", nsURI: "http://test/source", nsPrefix: "src")
            ],
            targetMetamodels: [
                "OUT": EPackage(name: "Target", nsURI: "http://test/target", nsPrefix: "tgt")
            ],
            helpers: helpers,
            matchedRules: matchedRules,
            calledRules: calledRules
        )
    }

    // MARK: - Issue 1: thisModule method dispatch (helpers)

    @Test("thisModule.helperName() dispatches to module helper")
    func testThisModuleHelperCall() async throws {
        // Helper that returns a constant string
        let helper = ATLHelperWrapper(
            name: "greeting",
            returnType: "String",
            body: ATLLiteralExpression(value: "hello from helper")
        )
        let module = makeMinimalModule(helpers: ["greeting": helper])
        let context = makeContext(module: module)

        // Evaluate: thisModule.greeting()
        let expr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "thisModule"),
            methodName: "greeting",
            arguments: []
        )

        let result = try await expr.evaluate(in: context)
        #expect(result as? String == "hello from helper")
    }

    @Test("thisModule.helper(arg) passes arguments correctly")
    func testThisModuleHelperWithArgs() async throws {
        // Helper: double(x) = x + x
        let helper = ATLHelperWrapper(
            name: "double",
            returnType: "Integer",
            parameters: [ATLParameter(name: "x", type: "Integer")],
            body: ATLBinaryExpression(
                left: ATLVariableExpression(name: "x"),
                operator: .plus,
                right: ATLVariableExpression(name: "x")
            )
        )
        let module = makeMinimalModule(helpers: ["double": helper])
        let context = makeContext(module: module)

        // Evaluate: thisModule.double(21)
        let expr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "thisModule"),
            methodName: "double",
            arguments: [ATLLiteralExpression(value: 21)]
        )

        let result = try await expr.evaluate(in: context)
        #expect(result as? Int == 42)
    }

    @Test("thisModule helper can call another helper via thisModule")
    func testThisModuleNestedHelperCalls() async throws {
        // inner() = 10
        let inner = ATLHelperWrapper(
            name: "inner",
            returnType: "Integer",
            body: ATLLiteralExpression(value: 10)
        )
        // outer() = thisModule.inner() + 5
        let outer = ATLHelperWrapper(
            name: "outer",
            returnType: "Integer",
            body: ATLBinaryExpression(
                left: ATLMethodCallExpression(
                    receiver: ATLVariableExpression(name: "thisModule"),
                    methodName: "inner",
                    arguments: []
                ),
                operator: .plus,
                right: ATLLiteralExpression(value: 5)
            )
        )
        let module = makeMinimalModule(helpers: ["inner": inner, "outer": outer])
        let context = makeContext(module: module)

        // Evaluate: thisModule.outer() should return 15
        let expr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "thisModule"),
            methodName: "outer",
            arguments: []
        )

        let result = try await expr.evaluate(in: context)
        #expect(result as? Int == 15)
    }

    // MARK: - Issue 1: thisModule attribute dispatch

    @Test("thisModule.attribute dispatches to context-free helper via navigation")
    func testThisModuleAttribute() async throws {
        let helper = ATLHelperWrapper(
            name: "version",
            returnType: "String",
            body: ATLLiteralExpression(value: "1.0")
        )
        let module = makeMinimalModule(helpers: ["version": helper])
        let context = makeContext(module: module)

        // Evaluate: thisModule.version (navigation expression, not a method call)
        let expr = ATLNavigationExpression(
            source: ATLVariableExpression(name: "thisModule"),
            property: "version"
        )

        let result = try await expr.evaluate(in: context)
        #expect(result as? String == "1.0")
    }

    @Test("thisModule.attribute rejects contextual helpers")
    func testThisModuleAttributeRejectsContextual() async throws {
        let contextualHelper = ATLHelperWrapper(
            name: "fullName",
            contextType: "Person",
            returnType: "String",
            body: ATLLiteralExpression(value: "should not reach")
        )
        let module = makeMinimalModule(helpers: ["fullName": contextualHelper])
        let context = makeContext(module: module)

        let expr = ATLNavigationExpression(
            source: ATLVariableExpression(name: "thisModule"),
            property: "fullName"
        )

        await #expect(throws: ATLExecutionError.self) {
            _ = try await expr.evaluate(in: context)
        }
    }

    // MARK: - Issue 1: thisModule unknown helper throws

    @Test("thisModule.unknown() throws helperNotFound")
    func testThisModuleUnknownHelper() async throws {
        let module = makeMinimalModule()
        let context = makeContext(module: module)

        let expr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "thisModule"),
            methodName: "nonExistent",
            arguments: []
        )

        await #expect(throws: ATLExecutionError.self) {
            _ = try await expr.evaluate(in: context)
        }
    }

    // MARK: - Issue 2: callHelper uses ATL evaluator (not ECore bridge)

    @Test("Helper body with conditional expression evaluates correctly")
    func testHelperWithConditionalBody() async throws {
        // Helper: classify(n: Integer) = if n > 0 then 'positive' else 'non-positive'
        let helper = ATLHelperWrapper(
            name: "classify",
            returnType: "String",
            parameters: [ATLParameter(name: "n", type: "Integer")],
            body: ATLConditionalExpression(
                condition: ATLBinaryExpression(
                    left: ATLVariableExpression(name: "n"),
                    operator: .greaterThan,
                    right: ATLLiteralExpression(value: 0)
                ),
                thenExpression: ATLLiteralExpression(value: "positive"),
                elseExpression: ATLLiteralExpression(value: "non-positive")
            )
        )
        let module = makeMinimalModule(helpers: ["classify": helper])
        let context = makeContext(module: module)

        let positiveExpr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "thisModule"),
            methodName: "classify",
            arguments: [ATLLiteralExpression(value: 5)]
        )
        let negativeExpr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "thisModule"),
            methodName: "classify",
            arguments: [ATLLiteralExpression(value: -3)]
        )

        let positiveResult = try await positiveExpr.evaluate(in: context)
        let negativeResult = try await negativeExpr.evaluate(in: context)
        #expect(positiveResult as? String == "positive")
        #expect(negativeResult as? String == "non-positive")
    }

    @Test("Helper body calling thisModule from within helper evaluates correctly")
    func testHelperBodyWithThisModuleCall() async throws {
        // base() = 100
        let base = ATLHelperWrapper(
            name: "base",
            returnType: "Integer",
            body: ATLLiteralExpression(value: 100)
        )
        // doubled() = thisModule.base() * 2
        let doubled = ATLHelperWrapper(
            name: "doubled",
            returnType: "Integer",
            body: ATLBinaryExpression(
                left: ATLMethodCallExpression(
                    receiver: ATLVariableExpression(name: "thisModule"),
                    methodName: "base",
                    arguments: []
                ),
                operator: .multiply,
                right: ATLLiteralExpression(value: 2)
            )
        )
        let module = makeMinimalModule(helpers: ["base": base, "doubled": doubled])
        let context = makeContext(module: module)

        let expr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "thisModule"),
            methodName: "doubled",
            arguments: []
        )

        let result = try await expr.evaluate(in: context)
        #expect(result as? Int == 200)
    }

    // MARK: - Issue 3: allInstances returns EcoreValueArray (not Int)

    @Test("allInstances() returns EcoreValueArray of instances")
    func testAllInstancesReturnsCollection() async throws {
        var sourcePackage = EPackage(name: "src", nsURI: "http://test/src", nsPrefix: "s")
        let personClass = EClass(name: "Person")
        sourcePackage.eClassifiers.append(personClass)

        let sourceResource = Resource(uri: "test://source")
        await sourceResource.add(DynamicEObject(eClass: personClass))
        await sourceResource.add(DynamicEObject(eClass: personClass))
        await sourceResource.add(DynamicEObject(eClass: personClass))

        let module = ATLModule(
            name: "TestAllInstances",
            sourceMetamodels: ["IN": sourcePackage],
            targetMetamodels: ["OUT": EPackage(name: "tgt", nsURI: "http://test/tgt")]
        )
        let context = makeContext(module: module, sources: ["IN": sourceResource])

        // Evaluate: src!Person.allInstances()
        let expr = ATLMethodCallExpression(
            receiver: ATLLiteralExpression(value: "src!Person"),
            methodName: "allInstances",
            arguments: []
        )
        let result = try await expr.evaluate(in: context)

        // Must be an EcoreValueArray, not an Int
        let array = try #require(result as? EcoreValueArray)
        #expect(array.values.count == 3)
    }

    // MARK: - Issue 3 + 4 chained: allInstances()->size()

    @Test("allInstances()->size() returns instance count via chained collection operation")
    func testAllInstancesSizeChain() async throws {
        var sourcePackage = EPackage(name: "src", nsURI: "http://test/src", nsPrefix: "s")
        let itemClass = EClass(name: "Item")
        sourcePackage.eClassifiers.append(itemClass)

        let sourceResource = Resource(uri: "test://source")
        await sourceResource.add(DynamicEObject(eClass: itemClass))
        await sourceResource.add(DynamicEObject(eClass: itemClass))

        let module = ATLModule(
            name: "TestChain",
            sourceMetamodels: ["IN": sourcePackage],
            targetMetamodels: ["OUT": EPackage(name: "tgt", nsURI: "http://test/tgt")]
        )
        let context = makeContext(module: module, sources: ["IN": sourceResource])

        // Evaluate: src!Item.allInstances()->size()
        let allInstancesExpr = ATLMethodCallExpression(
            receiver: ATLLiteralExpression(value: "src!Item"),
            methodName: "allInstances",
            arguments: []
        )
        let sizeExpr = ATLMethodCallExpression(
            receiver: allInstancesExpr,
            methodName: "size",
            arguments: []
        )

        let result = try await sizeExpr.evaluate(in: context)
        #expect(result as? Int == 2)
    }

    // MARK: - Issue 4: Collection operations work on EcoreValueArray

    @Test("select() works on EcoreValueArray")
    func testSelectOnEcoreValueArray() async throws {
        let module = makeMinimalModule()
        let context = makeContext(module: module)

        let collection = EcoreValueArray([1 as any EcoreValue, 2, 3, 4, 5])
        context.setVariable("nums", value: collection)

        // Evaluate: nums->select(n | n > 3)
        let expr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "nums"),
            methodName: "select",
            arguments: [
                ATLLambdaExpression(
                    parameter: "n",
                    body: ATLBinaryExpression(
                        left: ATLVariableExpression(name: "n"),
                        operator: .greaterThan,
                        right: ATLLiteralExpression(value: 3)
                    )
                )
            ]
        )

        let result = try await expr.evaluate(in: context)
        let array = try #require(result as? EcoreValueArray)
        #expect(array.values.count == 2)
        #expect(array.values[0] as? Int == 4)
        #expect(array.values[1] as? Int == 5)
    }

    @Test("collect() works on EcoreValueArray")
    func testCollectOnEcoreValueArray() async throws {
        let module = makeMinimalModule()
        let context = makeContext(module: module)

        let collection = EcoreValueArray([10 as any EcoreValue, 20, 30])
        context.setVariable("nums", value: collection)

        // Evaluate: nums->collect(n | n + 1)
        let expr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "nums"),
            methodName: "collect",
            arguments: [
                ATLLambdaExpression(
                    parameter: "n",
                    body: ATLBinaryExpression(
                        left: ATLVariableExpression(name: "n"),
                        operator: .plus,
                        right: ATLLiteralExpression(value: 1)
                    )
                )
            ]
        )

        let result = try await expr.evaluate(in: context)
        let array = try #require(result as? EcoreValueArray)
        #expect(array.values.count == 3)
        #expect(array.values[0] as? Int == 11)
        #expect(array.values[1] as? Int == 21)
        #expect(array.values[2] as? Int == 31)
    }

    @Test("forAll() works on EcoreValueArray")
    func testForAllOnEcoreValueArray() async throws {
        let module = makeMinimalModule()
        let context = makeContext(module: module)

        let allPositive = EcoreValueArray([1 as any EcoreValue, 2, 3])
        let withNegative = EcoreValueArray([1 as any EcoreValue, -1, 3])
        context.setVariable("pos", value: allPositive)
        context.setVariable("mixed", value: withNegative)

        let positiveExpr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "pos"),
            methodName: "forAll",
            arguments: [
                ATLLambdaExpression(
                    parameter: "n",
                    body: ATLBinaryExpression(
                        left: ATLVariableExpression(name: "n"),
                        operator: .greaterThan,
                        right: ATLLiteralExpression(value: 0)
                    )
                )
            ]
        )
        let mixedExpr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "mixed"),
            methodName: "forAll",
            arguments: [
                ATLLambdaExpression(
                    parameter: "n",
                    body: ATLBinaryExpression(
                        left: ATLVariableExpression(name: "n"),
                        operator: .greaterThan,
                        right: ATLLiteralExpression(value: 0)
                    )
                )
            ]
        )

        #expect(try await positiveExpr.evaluate(in: context) as? Bool == true)
        #expect(try await mixedExpr.evaluate(in: context) as? Bool == false)
    }

    @Test("size() works on EcoreValueArray")
    func testSizeOnEcoreValueArray() async throws {
        let module = makeMinimalModule()
        let context = makeContext(module: module)

        let collection = EcoreValueArray(["a" as any EcoreValue, "b", "c"])
        context.setVariable("items", value: collection)

        let expr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "items"),
            methodName: "size",
            arguments: []
        )

        let result = try await expr.evaluate(in: context)
        #expect(result as? Int == 3)
    }

    @Test("first() and last() work on EcoreValueArray")
    func testFirstLastOnEcoreValueArray() async throws {
        let module = makeMinimalModule()
        let context = makeContext(module: module)

        let collection = EcoreValueArray(["alpha" as any EcoreValue, "beta", "gamma"])
        context.setVariable("items", value: collection)

        let firstExpr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "items"),
            methodName: "first",
            arguments: []
        )
        let lastExpr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "items"),
            methodName: "last",
            arguments: []
        )

        let first = try await firstExpr.evaluate(in: context)
        let last = try await lastExpr.evaluate(in: context)
        #expect(first as? String == "alpha")
        #expect(last as? String == "gamma")
    }

    @Test("isEmpty() and notEmpty() work on EcoreValueArray")
    func testIsEmptyNotEmptyOnEcoreValueArray() async throws {
        let module = makeMinimalModule()
        let context = makeContext(module: module)

        let nonEmpty = EcoreValueArray([1 as any EcoreValue])
        let empty = EcoreValueArray([])
        context.setVariable("full", value: nonEmpty)
        context.setVariable("empty", value: empty)

        let isEmptyFull = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "full"),
            methodName: "isEmpty",
            arguments: []
        )
        let isEmptyEmpty = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "empty"),
            methodName: "isEmpty",
            arguments: []
        )
        let notEmptyFull = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "full"),
            methodName: "notEmpty",
            arguments: []
        )
        let notEmptyEmpty = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "empty"),
            methodName: "notEmpty",
            arguments: []
        )

        #expect(try await isEmptyFull.evaluate(in: context) as? Bool == false)
        #expect(try await isEmptyEmpty.evaluate(in: context) as? Bool == true)
        #expect(try await notEmptyFull.evaluate(in: context) as? Bool == true)
        #expect(try await notEmptyEmpty.evaluate(in: context) as? Bool == false)
    }

    @Test("includes() and excludes() work on EcoreValueArray")
    func testIncludesExcludesOnEcoreValueArray() async throws {
        let module = makeMinimalModule()
        let context = makeContext(module: module)

        let collection = EcoreValueArray([1 as any EcoreValue, 2, 3])
        context.setVariable("nums", value: collection)

        let includes2 = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "nums"),
            methodName: "includes",
            arguments: [ATLLiteralExpression(value: 2)]
        )
        let includes9 = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "nums"),
            methodName: "includes",
            arguments: [ATLLiteralExpression(value: 9)]
        )
        let excludes9 = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "nums"),
            methodName: "excludes",
            arguments: [ATLLiteralExpression(value: 9)]
        )

        #expect(try await includes2.evaluate(in: context) as? Bool == true)
        #expect(try await includes9.evaluate(in: context) as? Bool == false)
        #expect(try await excludes9.evaluate(in: context) as? Bool == true)
    }

    @Test("union() works on EcoreValueArray")
    func testUnionOnEcoreValueArray() async throws {
        let module = makeMinimalModule()
        let context = makeContext(module: module)

        let a = EcoreValueArray([1 as any EcoreValue, 2])
        let b = EcoreValueArray([3 as any EcoreValue, 4])
        context.setVariable("a", value: a)
        context.setVariable("b", value: b)

        let expr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "a"),
            methodName: "union",
            arguments: [ATLVariableExpression(name: "b")]
        )

        let result = try await expr.evaluate(in: context)
        let array = try #require(result as? EcoreValueArray)
        #expect(array.values.count == 4)
    }

    @Test("flatten() works on nested EcoreValueArray")
    func testFlattenOnEcoreValueArray() async throws {
        let module = makeMinimalModule()
        let context = makeContext(module: module)

        let inner1 = EcoreValueArray([1 as any EcoreValue, 2])
        let inner2 = EcoreValueArray([3 as any EcoreValue, 4])
        let outer = EcoreValueArray([inner1 as any EcoreValue, inner2])
        context.setVariable("nested", value: outer)

        let expr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "nested"),
            methodName: "flatten",
            arguments: []
        )

        let result = try await expr.evaluate(in: context)
        let array = try #require(result as? EcoreValueArray)
        #expect(array.values.count == 4)
    }

    @Test("asSet() deduplicates EcoreValueArray")
    func testAsSetOnEcoreValueArray() async throws {
        let module = makeMinimalModule()
        let context = makeContext(module: module)

        let collection = EcoreValueArray(["a" as any EcoreValue, "b", "a", "c", "b"])
        context.setVariable("items", value: collection)

        let expr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "items"),
            methodName: "asSet",
            arguments: []
        )

        let result = try await expr.evaluate(in: context)
        let array = try #require(result as? EcoreValueArray)
        #expect(array.values.count == 3)
    }

    @Test("asSequence() and asBag() preserve all elements in EcoreValueArray")
    func testAsSequenceAsBagOnEcoreValueArray() async throws {
        let module = makeMinimalModule()
        let context = makeContext(module: module)

        let collection = EcoreValueArray([1 as any EcoreValue, 2, 2, 3])
        context.setVariable("nums", value: collection)

        let seqExpr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "nums"),
            methodName: "asSequence",
            arguments: []
        )
        let bagExpr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "nums"),
            methodName: "asBag",
            arguments: []
        )

        let seqResult = try await seqExpr.evaluate(in: context)
        let bagResult = try await bagExpr.evaluate(in: context)
        let seqArray = try #require(seqResult as? EcoreValueArray)
        let bagArray = try #require(bagResult as? EcoreValueArray)
        #expect(seqArray.values.count == 4)
        #expect(bagArray.values.count == 4)
    }

    // MARK: - Issue 5: toCollection(nil) returns empty collection

    @Test("size() on nil returns 0 (absent multi-valued reference semantics)")
    func testSizeOnNil() async throws {
        let module = makeMinimalModule()
        let context = makeContext(module: module)

        context.setVariable("absent", value: nil)

        let expr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "absent"),
            methodName: "size",
            arguments: []
        )

        let result = try await expr.evaluate(in: context)
        #expect(result as? Int == 0)
    }

    @Test("isEmpty() on nil returns true")
    func testIsEmptyOnNil() async throws {
        let module = makeMinimalModule()
        let context = makeContext(module: module)

        context.setVariable("absent", value: nil)

        let expr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "absent"),
            methodName: "isEmpty",
            arguments: []
        )

        let result = try await expr.evaluate(in: context)
        #expect(result as? Bool == true)
    }

    // MARK: - Issue 6: setElementProperty metamodel-to-alias mapping

    @Test("Transformation with differing metamodel name and model alias succeeds")
    func testSetElementPropertyAliasMapping() async throws {
        // Source metamodel "srcmm" mapped via alias "IN"
        var srcPackage = EPackage(name: "srcmm", nsURI: "http://test/srcmm", nsPrefix: "s")
        let itemClass = EClass(name: "Item")
        srcPackage.eClassifiers.append(itemClass)

        // Target metamodel "tgtmm" mapped via alias "OUT" (name != alias)
        var tgtPackage = EPackage(name: "tgtmm", nsURI: "http://test/tgtmm", nsPrefix: "t")
        let widgetClass = EClass(name: "Widget")
        tgtPackage.eClassifiers.append(widgetClass)

        // Matched rule: srcmm!Item -> tgtmm!Widget (no bindings needed for this test)
        let rule = ATLMatchedRule(
            name: "Item2Widget",
            sourcePattern: ATLSourcePattern(variableName: "s", type: "srcmm!Item"),
            targetPatterns: [
                ATLTargetPattern(variableName: "t", type: "tgtmm!Widget")
            ]
        )

        let module = ATLModule(
            name: "AliasMappingTest",
            sourceMetamodels: ["IN": srcPackage],
            targetMetamodels: ["OUT": tgtPackage],
            matchedRules: [rule]
        )
        let vm = ATLVirtualMachine(module: module)

        let sourceResource = Resource(uri: "test://source")
        await sourceResource.add(DynamicEObject(eClass: itemClass))

        let targetResource = Resource(uri: "test://target")

        // Before the fix, setElementProperty used "tgtmm" directly as a resource key
        // (instead of mapping to "OUT"), so the target element write would fail.
        try await vm.execute(
            sources: ["IN": sourceResource],
            targets: ["OUT": targetResource]
        )

        let stats = vm.getStatistics()
        #expect(stats.successful == true)
        #expect(stats.rulesExecuted >= 1)
    }

    // MARK: - Multi-valued EReference serialisation

    /// Tests that setting a multi-valued EReference to an EcoreValueArray of EObjects
    /// stores the result as [EUUID] so the XMI serialiser can resolve and serialise the
    /// references correctly, instead of dumping an EcoreValueArray debug string.
    @Test("Multi-valued EReference binding stores [EUUID], not EcoreValueArray")
    func testMultiValuedReferenceBinding() async throws {
        // Source metamodel: Container with no structural features
        var srcPackage = EPackage(name: "src", nsURI: "http://test/src", nsPrefix: "s")
        let containerClass = EClass(name: "Container")
        let itemClass = EClass(name: "Item")
        srcPackage.eClassifiers.append(containerClass)
        srcPackage.eClassifiers.append(itemClass)

        // Target metamodel: Report with multi-valued 'outputs' EReference -> Output
        var tgtPackage = EPackage(name: "tgt", nsURI: "http://test/tgt", nsPrefix: "t")
        let outputClass = EClass(name: "Output")
        var reportClass = EClass(name: "Report")
        let outputsRef = EReference(
            name: "outputs", eType: outputClass, lowerBound: 0, upperBound: -1)
        reportClass.eStructuralFeatures.append(outputsRef)
        tgtPackage.eClassifiers.append(outputClass)
        tgtPackage.eClassifiers.append(reportClass)

        // Called rule: ItemToOutput() -> tgt!Output
        let itemToOutput = ATLCalledRule(
            name: "ItemToOutput",
            parameters: [],
            targetPatterns: [ATLTargetPattern(variableName: "o", type: "tgt!Output")]
        )

        // Matched rule: src!Container -> tgt!Report
        // outputs <- src!Item.allInstances()->collect(i | thisModule.ItemToOutput())
        let rule = ATLMatchedRule(
            name: "Container2Report",
            sourcePattern: ATLSourcePattern(variableName: "c", type: "src!Container"),
            targetPatterns: [
                ATLTargetPattern(
                    variableName: "r",
                    type: "tgt!Report",
                    bindings: [
                        ATLPropertyBinding(
                            property: "outputs",
                            expression: ATLMethodCallExpression(
                                receiver: ATLMethodCallExpression(
                                    receiver: ATLLiteralExpression(value: "src!Item"),
                                    methodName: "allInstances"
                                ),
                                methodName: "collect",
                                arguments: [
                                    ATLLambdaExpression(
                                        parameter: "i",
                                        body: ATLMethodCallExpression(
                                            receiver: ATLVariableExpression(name: "thisModule"),
                                            methodName: "ItemToOutput"
                                        )
                                    )
                                ]
                            )
                        )
                    ]
                )
            ]
        )

        let module = ATLModule(
            name: "MultiValuedRefTest",
            sourceMetamodels: ["IN": srcPackage],
            targetMetamodels: ["OUT": tgtPackage],
            matchedRules: [rule],
            calledRules: ["ItemToOutput": itemToOutput]
        )
        let vm = ATLVirtualMachine(module: module)

        let sourceResource = Resource(uri: "test://source")
        await sourceResource.add(DynamicEObject(eClass: containerClass))
        // Add two Items so allInstances() returns two elements
        await sourceResource.add(DynamicEObject(eClass: itemClass))
        await sourceResource.add(DynamicEObject(eClass: itemClass))

        let targetResource = Resource(uri: "test://target")

        try await vm.execute(
            sources: ["IN": sourceResource],
            targets: ["OUT": targetResource]
        )

        let stats = vm.getStatistics()
        #expect(stats.successful == true)

        // Verify the Report element has 'outputs' stored as [EUUID], not as
        // an EcoreValueArray string (which the XMI serialiser cannot handle).
        let allObjects = await targetResource.getAllObjects()
        let reportObjects = allObjects.filter { ($0.eClass as? EClass)?.name == "Report" }
        let report = try #require(reportObjects.first as? DynamicEObject)
        let outputsValue = report.eGet("outputs")
        // Must be [EUUID], not EcoreValueArray or nil
        let outputIds = try #require(outputsValue as? [EUUID])
        #expect(outputIds.count == 2)
    }

    // MARK: - Issue 7: Missing dispatch entries

    @Test("oclIsUndefined dispatches correctly for present and absent values")
    func testOclIsUndefined() async throws {
        let module = makeMinimalModule()
        let context = makeContext(module: module)

        context.setVariable("present", value: 42)
        context.setVariable("absent", value: nil)

        let presentExpr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "present"),
            methodName: "oclIsUndefined",
            arguments: []
        )
        let absentExpr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "absent"),
            methodName: "oclIsUndefined",
            arguments: []
        )

        #expect(try await presentExpr.evaluate(in: context) as? Bool == false)
        #expect(try await absentExpr.evaluate(in: context) as? Bool == true)
    }

    @Test("oclIsKindOf checks exact class and supertypes")
    func testOclIsKindOf() async throws {
        let animalClass = EClass(name: "Animal")
        let dogClass = EClass(name: "Dog", eSuperTypes: [animalClass])
        let dog = DynamicEObject(eClass: dogClass)

        let module = makeMinimalModule()
        let context = makeContext(module: module)
        context.setVariable("d", value: dog)

        // d.oclIsKindOf("Dog") -> true (exact class)
        let exactExpr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "d"),
            methodName: "oclIsKindOf",
            arguments: [ATLLiteralExpression(value: "Dog")]
        )
        // d.oclIsKindOf("Animal") -> true (supertype)
        let superExpr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "d"),
            methodName: "oclIsKindOf",
            arguments: [ATLLiteralExpression(value: "Animal")]
        )
        // d.oclIsKindOf("Cat") -> false
        let wrongExpr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "d"),
            methodName: "oclIsKindOf",
            arguments: [ATLLiteralExpression(value: "Cat")]
        )

        #expect(try await exactExpr.evaluate(in: context) as? Bool == true)
        #expect(try await superExpr.evaluate(in: context) as? Bool == true)
        #expect(try await wrongExpr.evaluate(in: context) as? Bool == false)
    }

    @Test("mod() dispatches and computes correctly")
    func testModDispatch() async throws {
        let module = makeMinimalModule()
        let context = makeContext(module: module)

        // 10.mod(3) = 1
        let expr = ATLMethodCallExpression(
            receiver: ATLLiteralExpression(value: 10),
            methodName: "mod",
            arguments: [ATLLiteralExpression(value: 3)]
        )

        let result = try await expr.evaluate(in: context)
        #expect(result as? Int == 1)
    }

    @Test("toUpperCase() dispatches and converts correctly")
    func testToUpperCaseDispatch() async throws {
        let module = makeMinimalModule()
        let context = makeContext(module: module)

        let expr = ATLMethodCallExpression(
            receiver: ATLLiteralExpression(value: "hello"),
            methodName: "toUpperCase",
            arguments: []
        )

        let result = try await expr.evaluate(in: context)
        #expect(result as? String == "HELLO")
    }

    @Test("createMethodSignature returns 'Collection' for EcoreValueArray")
    func testCreateMethodSignatureForEcoreValueArray() async throws {
        let module = makeMinimalModule()
        let context = makeContext(module: module)

        // Create a method call whose receiver is an EcoreValueArray; verify
        // that the dispatch resolves correctly (which requires the signature to
        // include "Collection").
        let collection = EcoreValueArray([1 as any EcoreValue, 2, 3])
        context.setVariable("c", value: collection)

        // Use size() as a proxy — it only resolves if the type signature is recognised
        let expr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "c"),
            methodName: "size",
            arguments: []
        )

        let result = try await expr.evaluate(in: context)
        #expect(result as? Int == 3)
    }

    // MARK: - Additional edge cases

    @Test("exists() works on EcoreValueArray")
    func testExistsOnEcoreValueArray() async throws {
        let module = makeMinimalModule()
        let context = makeContext(module: module)

        let collection = EcoreValueArray([1 as any EcoreValue, 2, 3])
        context.setVariable("nums", value: collection)

        // nums->exists(n | n = 2)
        let exprTrue = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "nums"),
            methodName: "exists",
            arguments: [
                ATLLambdaExpression(
                    parameter: "n",
                    body: ATLBinaryExpression(
                        left: ATLVariableExpression(name: "n"),
                        operator: .equals,
                        right: ATLLiteralExpression(value: 2)
                    )
                )
            ]
        )
        // nums->exists(n | n = 99)
        let exprFalse = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "nums"),
            methodName: "exists",
            arguments: [
                ATLLambdaExpression(
                    parameter: "n",
                    body: ATLBinaryExpression(
                        left: ATLVariableExpression(name: "n"),
                        operator: .equals,
                        right: ATLLiteralExpression(value: 99)
                    )
                )
            ]
        )

        #expect(try await exprTrue.evaluate(in: context) as? Bool == true)
        #expect(try await exprFalse.evaluate(in: context) as? Bool == false)
    }

    @Test("reject() works on EcoreValueArray")
    func testRejectOnEcoreValueArray() async throws {
        let module = makeMinimalModule()
        let context = makeContext(module: module)

        let collection = EcoreValueArray([1 as any EcoreValue, 2, 3, 4, 5])
        context.setVariable("nums", value: collection)

        // nums->reject(n | n > 3) should give [1, 2, 3]
        let expr = ATLMethodCallExpression(
            receiver: ATLVariableExpression(name: "nums"),
            methodName: "reject",
            arguments: [
                ATLLambdaExpression(
                    parameter: "n",
                    body: ATLBinaryExpression(
                        left: ATLVariableExpression(name: "n"),
                        operator: .greaterThan,
                        right: ATLLiteralExpression(value: 3)
                    )
                )
            ]
        )

        let result = try await expr.evaluate(in: context)
        let array = try #require(result as? EcoreValueArray)
        #expect(array.values.count == 3)
    }

    @Test("allInstances()->select()->size() three-step chain works")
    func testAllInstancesSelectSizeChain() async throws {
        var sourcePackage = EPackage(name: "src", nsURI: "http://test/src", nsPrefix: "s")
        let nodeClass = EClass(name: "Node")
        sourcePackage.eClassifiers.append(nodeClass)

        let sourceResource = Resource(uri: "test://source")
        for _ in 0..<5 {
            await sourceResource.add(DynamicEObject(eClass: nodeClass))
        }

        let module = ATLModule(
            name: "TestChain",
            sourceMetamodels: ["IN": sourcePackage],
            targetMetamodels: ["OUT": EPackage(name: "tgt", nsURI: "http://test/tgt")]
        )
        let context = makeContext(module: module, sources: ["IN": sourceResource])

        // src!Node.allInstances()->select(n | true)->size()
        let allInstancesExpr = ATLMethodCallExpression(
            receiver: ATLLiteralExpression(value: "src!Node"),
            methodName: "allInstances",
            arguments: []
        )
        let selectExpr = ATLMethodCallExpression(
            receiver: allInstancesExpr,
            methodName: "select",
            arguments: [
                ATLLambdaExpression(
                    parameter: "n",
                    body: ATLLiteralExpression(value: true)
                )
            ]
        )
        let sizeExpr = ATLMethodCallExpression(
            receiver: selectExpr,
            methodName: "size",
            arguments: []
        )

        let result = try await sizeExpr.evaluate(in: context)
        #expect(result as? Int == 5)
    }
}
