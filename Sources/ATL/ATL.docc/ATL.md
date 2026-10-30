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
- **Queries**: `query Name = expression;` units evaluated to a value with ``ATLVirtualMachine/evaluateQuery(sources:parameters:)``
- **File output**: `writeTo` and `writeToWithCharset`, disabled unless the host enables them with an ``ATLFileOutputPolicy``
- **Two-phase execution**: Targets are created before bindings, with implicit trace resolution, `resolveTemp`, unique lazy rules, entrypoint and endpoint rules, and imperative `do` blocks

### Quick Example

```swift
import ATL
import ECore

// Parse the transformation
let parser = ATLParser(options: .standard)
let module = try await parser.parse(URL(fileURLWithPath: "Class2Table.atl"))

// Create and configure the virtual machine
let vm = ATLVirtualMachine(module: module)
try await vm.registerSourceMetamodel(umlMetamodel, as: "UML")
try await vm.registerTargetMetamodel(dbMetamodel, as: "DB")
try await vm.registerSourceModel(classModel, as: "IN")

// Execute and get results
let result = try await vm.execute()
let tableModel = result.targetModels["OUT"]
```

### Compatibility with 0.6

APIs that take an ``ATLOptions`` value default to the current behaviour,
``ATLOptions/standard``. The APIs of swift-atl 0.6, which take no options, keep the
behaviour of 0.6 by using ``ATLOptions/legacy``; those whose behaviour now differs
from the default are deprecated in favour of the variant that takes options.

| Behaviour | Default | Option | 0.6 behaviour |
| :-- | :-- | :-- | :-- |
| Integer ranges in collection literals, such as `Sequence{1..3}` | Accepted | ``ATLOptions/collectionRangeSyntax`` | ``ATLCollectionRangeSyntax/eclipse``: rejected, as in Eclipse ATL |
| Collection ranges in XMI | ``ATLCollectionRangeEncoding/collectionRange`` | ``ATLOptions/collectionRangeEncoding`` | No ranges could be written; ``ATLCollectionRangeEncoding/portable`` writes them with expressions that 0.6 reads |

A rejected range is reported with a message that names the portable alternatives:
listing the integers, as in `Sequence{1, 2, 3}`, or calling `includingRange`, as in
`Sequence{}->includingRange(1, 3)`, which the Eclipse ATL EMFTVM provides. To keep the
0.6 behaviour with the new APIs, pass ``ATLOptions/legacy``, for example
`ATLParser(options: .legacy)`. Parse errors now also describe themselves through
`localizedDescription`.

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:UnderstandingATL>

### Transformation Execution

- ``ATLVirtualMachine``
- ``ATLExecutionContext``
- ``ATLExecutionResult``
- ``ATLExecutionStatistics``
- ``ATLFileOutputPolicy``

### Modules and Rules

- ``ATLModule``
- ``ATLUnitKind``
- ``ATLMatchedRule``
- ``ATLCalledRule``
- ``ATLLazyRule``
- ``ATLHelper``
- ``ATLNativeHelper``

### Patterns and Bindings

- ``ATLInPattern``
- ``ATLOutPattern``
- ``ATLBinding``
- ``ATLSimpleInPatternElement``
- ``ATLSimpleOutPatternElement``

### Expressions

- ``ATLExpression``
- ``ATLNavigationExpression``
- ``ATLOperationCallExpression``
- ``ATLCollectionExpression``
- ``ATLLiteralExpression``

### Parsing

- ``ATLParser``
- ``ATLOptions``
- ``ATLCollectionRangeSyntax``
- ``ATLCollectionRangeEncoding``
- ``ATLLexer``
- ``ATLSyntaxParser``

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
