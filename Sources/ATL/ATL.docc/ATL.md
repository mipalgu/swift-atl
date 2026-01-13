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

### Quick Example

```swift
import ATL
import ECore

// Parse the transformation
let parser = ATLParser()
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

## Topics

### Essentials

- <doc:GettingStarted>
- <doc:UnderstandingATL>

### Transformation Execution

- ``ATLVirtualMachine``
- ``ATLExecutionContext``
- ``ATLExecutionResult``
- ``ATLExecutionStatistics``

### Modules and Rules

- ``ATLModule``
- ``ATLMatchedRule``
- ``ATLCalledRule``
- ``ATLLazyRule``
- ``ATLHelper``

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
- ``ATLLexer``
- ``ATLSyntaxParser``

### Model Adapters

- ``ATLSourceModel``
- ``ATLTargetModel``
- ``ATLModelAdapterFactory``

### Errors

- ``ATLExecutionError``
- ``ATLParseError``

### References

- [Eclipse ATL (Atlas Transformation Language)](https://eclipse.dev/atl/)
- [OMG QVT (Query/View/Transformation)](https://www.omg.org/spec/QVT/)
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/)
- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/)
