# ``ATL``

@Metadata {
    @DisplayName("ATL")
}

A pure Swift implementation of the [Atlas Transformation Language (ATL)](https://eclipse.dev/atl/) for model-to-model transformations.

## Overview

ATL provides a declarative approach to model transformation, allowing you to specify
how elements in a source model should be transformed into elements in a target model.
The transformation rules are pattern-matched against the source model, and corresponding
target elements are created automatically.

This implementation follows the [ATL specification](https://eclipse.dev/atl/documentation/)
and is related to the [OMG QVT (Query/View/Transformation)](https://www.omg.org/spec/QVT/)
standard, whilst providing a modern Swift API for integration with the ECore
metamodelling framework.

### Key Features

- **Declarative transformations**: Define rules that match source patterns and produce targets
- **Matched rules**: Automatically applied to all matching source elements
- **Called rules**: Explicitly invoked for imperative control flow
- **Lazy rules**: Create target elements on-demand
- **Helpers**: Define reusable query operations
- **OCL expressions**: Full support for guards, bindings, and navigation
- **Language coverage**: String escapes, real, enumeration and `OclUndefined` literals, collection literals that keep their objects and accept integer ranges such as `Sequence{1..3}`, three-valued logical operators, and extensive collection, string and type operations
- **Options**: ``ATLOptions`` selects between the current behaviour and that of swift-atl 0.6 or Eclipse ATL
- **Reflective operations**: `refImmediateComposite()`, `refGetValue`, `refSetValue`, `refUnsetValue`, `refInvokeOperation` and the `eContainer()` family navigate and modify models by name
- **Helper overloads**: Contextual helpers dispatch on the dynamic type of the receiver
- **Metamodel binding**: `@nsURI` and `@path` directives with an ``ATLMetamodelRegistry``
- **Module parameters**: `-- @param` declarations supplied through `execute(sources:targets:parameters:)`
- **Refining mode**: `create OUT : MM refining IN : MM;` modules, or ``ATLModule/refining(_:)``, change a copy of the source model in place, copy the elements that no rule matches, and delete the elements that rules `drop`
- **Queries**: `query Name = expression;` units evaluated to a value with ``ATLVirtualMachine/evaluateQuery(sources:parameters:)``
- **File output**: `writeTo` and `writeToWithCharset`, disabled unless the host enables them with an ``ATLFileOutputPolicy``
- **Two-phase execution**: Targets are created before bindings, with implicit trace resolution, `resolveTemp`, unique lazy rules, entrypoint and endpoint rules, and imperative `do` blocks
- **Native helpers**: Helpers implemented in Swift with ``ATLNativeHelper``, which take precedence over module helpers of the same name
- **Progress and cancellation**: ``ATLProgress`` reports while a transformation runs, and a cancelled task stops it
- **Editor support**: ``ATLSyntax`` classifies tokens, and ``ATLParser/parseDiagnosing(_:name:metamodelRegistry:)`` parses with error recovery and stable ``ATLDiagnosticCode`` values
- **XMI serialisation**: ``ATLResource`` reads and writes ATL modules in the Eclipse ATL XMI format
- **Incremental execution**: ``ATLIncrementalTransformation`` propagates source model changes to the target models match by match and binding by binding, with results identical to a batch execution; see <doc:IncrementalTransformations>

### Quick Example

```swift
import ATL
import ECore

// Parse the transformation; its header binds the metamodels
let module = try await ATLParser(options: .standard)
    .parse(URL(fileURLWithPath: "Families2Persons.atl"))

// Load the source model against the source metamodel
let resourceSet = ResourceSet()
if let families = module.sourceMetamodels["IN"] {
    await resourceSet.registerMetamodel(families, uri: families.nsURI)
}
let source = try await XMIParser(resourceSet: resourceSet)
    .parse(URL(fileURLWithPath: "Families.xmi"))

// Run the transformation and save the target model
let target = Resource(uri: "Persons.xmi")
let vm = ATLVirtualMachine(module: module, options: .standard)
try await vm.execute(sources: ["IN": source], targets: ["OUT": target])
try await XMISerializer().serialize(target, to: URL(fileURLWithPath: "Persons.xmi"))
```

## Compatibility

### Eclipse ATL

The parser accepts the syntax of Eclipse ATL transformations, and ``ATLResource``,
``ATLXMIParser`` and ``ATLXMISerializer`` read and write ATL modules in the Eclipse ATL
XMI format, so that a module survives a round trip unchanged.

The following ATL constructs are not supported. The parser reports each of them as an
``ATLDiagnosticCode/unsupportedConstruct`` error at the offending token:

- libraries (`library`) and library imports (`uses`),
- the `nodefault` rule modifier,
- iterated target patterns with `foreach` or `distinct`,
- `extends` on lazy or called rules.

Integer ranges in collection literals, such as `Sequence{0, 2..4, 9}`, are an OCL feature
that the Eclipse ATL compilers do not accept, so a transformation that uses them does not
run on Eclipse ATL. `includingRange` is the portable alternative, and parsing with
`ATLOptions(collectionRangeSyntax: .eclipse)` rejects ranges as Eclipse ATL does.

### Compatibility with 0.6

APIs that take an ``ATLOptions`` value default to the current behaviour,
``ATLOptions/standard``, which `ATLOptions()` also gives. These are the initialisers of
``ATLParser``, ``ATLVirtualMachine``, ``ATLResource``, ``ATLXMISerializer`` and
``ATLExpressionXMISerializer``, and ``ATLSyntax/tokens(in:options:)``. The APIs of
swift-atl 0.6, which take no options, keep the behaviour of 0.6 by using
``ATLOptions/legacy``; those whose behaviour now differs from the default
(`ATLParser(enableDebugging:)`, `ATLVirtualMachine(module:enableDebugging:unsetFeatureReads:nativeHelpers:fileOutput:)`,
`ATLResource(uri:)`, `ATLResource(uri:module:)` and ``ATLSyntax/tokens(in:)``) are
deprecated in favour of the variant that takes options.

| Behaviour | Default | Option | 0.6 behaviour |
| :-- | :-- | :-- | :-- |
| Integer ranges in collection literals, such as `Sequence{1..3}` | Accepted | ``ATLOptions/collectionRangeSyntax`` | ``ATLCollectionRangeSyntax/eclipse``: rejected, as in Eclipse ATL |
| Collection ranges in XMI | ``ATLCollectionRangeEncoding/collectionRange`` | ``ATLOptions/collectionRangeEncoding`` | No ranges could be written; ``ATLCollectionRangeEncoding/portable`` writes them with expressions that 0.6 reads |
| `/` on two Integers, such as `7 / 2` | ``ATLIntegerDivision/real``: a Real (`3.5`), as in OCL and Eclipse ATL | ``ATLOptions/integerDivision`` | ``ATLIntegerDivision/truncating``: an Integer truncated towards zero (`3`), as `div` gives |
| Bag values, such as `Bag{1, 1}`, `asBag()`, `Set{...}->collect(...)` and a feature navigated over a Set | ``ATLBagRepresentation/bag``: Bags, as in OCL and the Eclipse ATL EMFTVM | ``ATLOptions/bagRepresentation`` | ``ATLBagRepresentation/sequence``: Sequences |

With ``ATLCollectionRangeSyntax/eclipse``, `..` is read as two `.` tokens, and a range is
reported as a syntax error whose message names the portable alternatives: listing the
integers, as in `Sequence{1, 2, 3}`, or calling `includingRange`, as in
`Sequence{}->includingRange(1, 3)`, which the Eclipse ATL EMFTVM provides. With
``ATLCollectionRangeEncoding/portable``, a range whose bounds are integer literals is
written as its integers, and any other range as a call of `includingRange`, with the items
after it added by `includingAll`. Both operations exist in swift-atl 0.6 and in the Eclipse
ATL EMFTVM, which however reports an error for an empty range.

With ``ATLBagRepresentation/bag``, a Bag keeps its duplicates but is neither a Sequence nor
a Set: it conforms to `Bag(T)` and `Collection(T)`, `oclType()` names it `Bag`, it is written
as `Bag{...}`, helpers declared for `Bag(T)` apply to it while those for `Sequence(T)` do not,
and it equals a collection that holds each element equally often, in any order. With
``ATLBagRepresentation/sequence``, the same expressions give Sequences, which conform to
`Sequence(T)` and compare element by element.

To keep the 0.6 behaviour with the new APIs, pass ``ATLOptions/legacy``, for example
`ATLParser(options: .legacy)` or `ATLVirtualMachine(module: module, options: .legacy)`.
Parse errors now also describe themselves through `localizedDescription`.

A virtual machine created with
``ATLVirtualMachine/init(module:options:enableDebugging:unsetFeatureReads:nativeHelpers:fileOutput:)``
evaluates expressions as its options select; one created without options truncates the
quotient of two Integers, as swift-atl 0.6 did. `div` and `mod` behave alike under both:
`div` truncates the quotient of two Integers towards zero and `mod` gives the remainder with
the sign of the dividend, as in OCL and Eclipse ATL.

``ATLOptions/init(semantics:)`` selects ``ATLOptions/standard`` or ``ATLOptions/legacy``
from a `ModellingSemantics` value, and ``ATLOptions/fromEnvironment(_:)`` reads that choice
from the `SWIFT_MODELLING_SEMANTICS` environment variable (`standard` or `legacy`;
``ATLOptions/standard`` if it is unset or empty, and an error for any other value):

```swift
let parser = ATLParser(options: try ATLOptions.fromEnvironment())
```

The `eContainer()` family of operations finds containers through the resources of the
models, in the container lookup scope configured for each resource or its resource set
(`ContainerLookupScope`), and in the scope of version 0.6 if none is configured.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:UnderstandingATL>
- <doc:IncrementalTransformations>

### Transformation Execution

- ``ATLVirtualMachine``
- ``ATLExecutionContext``
- ``ATLExecutionStatistics``
- ``ATLProgress``
- ``ATLProgressPhase``
- ``ATLFileOutputPolicy``

### Modules and Rules

- ``ATLModule``
- ``ATLUnitKind``
- ``ATLModuleParameter``
- ``ATLMatchedRule``
- ``ATLCalledRule``
- ``ATLHelper``
- ``ATLNativeHelper``

### Patterns and Bindings

- ``ATLSourcePattern``
- ``ATLTargetPattern``
- ``ATLPropertyBinding``

### Expressions

- ``ATLExpression``
- ``ATLNavigationExpression``
- ``ATLOperationExpression``
- ``ATLMethodCallExpression``
- ``ATLCollectionExpression``
- ``ATLLiteralExpression``

### Parsing

- ``ATLParser``
- ``ATLOptions``
- ``ATLCollectionRangeSyntax``
- ``ATLCollectionRangeEncoding``
- ``ATLIntegerDivision``
- ``ATLBagRepresentation``
- ``ATLMetamodelRegistry``

### Editor Support

- ``ATLSyntax``
- ``ATLParseResult``
- ``ATLDiagnosticCode``
- ``ATLOutlineKind``

### XMI Serialisation

- ``ATLResource``
- ``ATLXMIParser``
- ``ATLXMISerializer``

### Model Adapters

- ``ATLSourceModel``
- ``ATLTargetModel``
- ``ATLModelAdapterFactory``

### Errors

- ``ATLExecutionError``
- ``ATLParseError``

## See Also

- [Eclipse ATL (Atlas Transformation Language)](https://eclipse.dev/atl/)
- [OMG QVT (Query/View/Transformation)](https://www.omg.org/spec/QVT/)
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/)
- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/)
