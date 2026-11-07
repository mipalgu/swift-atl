# Swift ATL - Atlas Transformation Language Library

[![CI](https://github.com/mipalgu/swift-atl/actions/workflows/ci.yml/badge.svg)](https://github.com/mipalgu/swift-atl/actions/workflows/ci.yml)
[![Documentation](https://github.com/mipalgu/swift-atl/actions/workflows/documentation.yml/badge.svg)](https://github.com/mipalgu/swift-atl/actions/workflows/documentation.yml)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmipalgu%2Fswift-atl%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/mipalgu/swift-atl)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmipalgu%2Fswift-atl%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/mipalgu/swift-atl)

A pure Swift implementation of the Eclipse Atlas Transformation Language (ATL) for
model-to-model transformations, with Eclipse ATL XMI serialisation.

This package provides the ATL library. The `swift-atl` command-line tool is part of the
[swift-modelling](https://github.com/mipalgu/swift-modelling) package.

## Features

- **Pure Swift**: no Java or EMF runtime, with strict concurrency checking
- **Eclipse ATL compatible**: parses and runs Eclipse ATL transformations, and reads and
  writes ATL modules in the Eclipse ATL XMI format
- **Complete rule language**: matched, lazy, unique lazy and called rules, rule
  inheritance, entrypoint and endpoint rules, and imperative `do` blocks
- **OCL expressions**: navigation, collections and iterators, `let`, tuples, three-valued
  logic and a broad library of built-in and reflective operations
- **Refining mode**: in-place transformations that keep unmatched elements, including
  `drop` to delete matched elements
- **Queries and file output**: `query` units evaluated to a value, with `writeTo` under a
  host-controlled file output policy
- **Host integration**: module parameters, native helpers written in Swift, metamodel
  registries, progress reporting and cancellation
- **Editor support**: token classification and error-tolerant parsing with diagnostics
- **Incremental execution**: source changes propagated to targets, matching a batch run
- **[swift-ecore](https://github.com/mipalgu/swift-ecore) integration**: transforms
  models held in ECore resources

## Requirements

- Swift 6.0 or later
- macOS 15.0 or later, Linux or Windows

## Installation

### Swift Package Manager

Add the following to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-atl.git", branch: "main")
]
```

And add `"ATL"` to your target's dependencies:

```swift
.target(
    name: "YourTarget",
    dependencies: [
        .product(name: "ATL", package: "swift-atl"),
    ]
)
```

## Building

```bash
# Build the library
swift build

# Run tests
swift test
```

## Library Usage

Parse a transformation, load its source model with swift-ecore, run it and save the
result:

```swift
import ATL
import ECore
import Foundation

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

`ATLOptions.standard` selects the current behaviour; `ATLOptions.legacy` keeps that of
swift-atl 0.6.

## Documentation

The [ATL documentation](https://mipalgu.github.io/swift-atl/documentation/atl/) covers
the API, the supported language, execution semantics and compatibility, including:

- [Getting Started](https://mipalgu.github.io/swift-atl/documentation/atl/gettingstarted):
  adding the package, running transformations and queries, and host integration
- [Understanding ATL](https://mipalgu.github.io/swift-atl/documentation/atl/understandingatl):
  rules, helpers, expressions, refining mode, queries and file output

## Licence

See the details in the LICENCE file.

## References

This implementation is based on the following standards and technologies:

- [Eclipse ATL (Atlas Transformation Language)](https://eclipse.dev/atl/) - The reference ATL implementation
- [OMG QVT (Query/View/Transformation)](https://www.omg.org/spec/QVT/) - The model transformation standard
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/) - Expression language for guards and queries
- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/) - The metamodelling foundation
- [swift-ecore](https://github.com/mipalgu/swift-ecore) - The Swift Ecore metamodelling framework
