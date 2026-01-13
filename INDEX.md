# Swift ATL - Model Transformation Language

The [swift-atl](https://github.com/mipalgu/swift-atl) package provides a pure Swift
implementation of the [Atlas Transformation Language (ATL)](https://eclipse.dev/atl/)
for model-to-model transformations.

## Overview

Swift ATL enables declarative model transformations in Swift, providing:

- **ATL language support**: Parse and execute ATL transformation modules
- **Matched rules**: Declaratively map source model elements to target elements
- **Called rules**: Imperative rule invocation for complex scenarios
- **Lazy rules**: On-demand element creation
- **Helpers**: Reusable query operations
- **OCL integration**: Full [OCL](https://www.omg.org/spec/OCL/) expression support for guards and bindings

## Installation

Add swift-atl as a dependency in your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-atl.git", branch: "main"),
]
```

Then add the product dependency to your target:

```swift
.target(
    name: "MyApp",
    dependencies: [
        .product(name: "ATL", package: "swift-atl"),
    ]
)
```

## Quick Start

```swift
import ATL
import ECore

// Load source and target metamodels
let sourceMetamodel = try await loadMetamodel("Source.ecore")
let targetMetamodel = try await loadMetamodel("Target.ecore")

// Parse the ATL transformation
let parser = ATLParser()
let module = try await parser.parse(URL(fileURLWithPath: "Transform.atl"))

// Create the virtual machine
let vm = ATLVirtualMachine(module: module)

// Register metamodels and source model
try await vm.registerSourceMetamodel(sourceMetamodel, as: "Source")
try await vm.registerTargetMetamodel(targetMetamodel, as: "Target")
try await vm.registerSourceModel(sourceResource, as: "IN")

// Execute the transformation
let result = try await vm.execute()

// Access the target model
let targetResource = result.targetModels["OUT"]
```

## ATL Syntax Example

```atl
module Source2Target;
create OUT : Target from IN : Source;

rule Class2Table {
    from
        c : Source!Class
    to
        t : Target!Table (
            name <- c.name,
            columns <- c.attributes->collect(a | thisModule.resolveTemp(a, 'col'))
        )
}

rule Attribute2Column {
    from
        a : Source!Attribute
    to
        col : Target!Column (
            name <- a.name,
            type <- a.type.name
        )
}
```

## Documentation

Detailed documentation is available in the generated DocC documentation:

- **Getting Started**: Installation and first transformation
- **Understanding ATL**: Rules, helpers, and execution model
- **API Reference**: Complete API documentation

## Requirements

- macOS 15.0+
- Swift 6.0+
- swift-ecore

## References

This implementation is based on the following standards and technologies:

- [Eclipse ATL (Atlas Transformation Language)](https://eclipse.dev/atl/) - The reference implementation
- [OMG QVT (Query/View/Transformation)](https://www.omg.org/spec/QVT/) - The model transformation standard
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/) - Expression language for guards and queries
- [Eclipse EMF (Modeling Framework)](https://eclipse.dev/emf/) - The metamodelling foundation

## Related Packages

- [swift-ecore](https://github.com/mipalgu/swift-ecore) - EMF/Ecore metamodelling
- [swift-mtl](https://github.com/mipalgu/swift-mtl) - MTL code generation
- [swift-aql](https://github.com/mipalgu/swift-aql) - AQL model queries
- [swift-modelling](https://github.com/mipalgu/swift-modelling) - Unified MDE toolkit
