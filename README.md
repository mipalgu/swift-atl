# Swift ATL - Atlas Transformation Language Library

[![CI](https://github.com/mipalgu/swift-atl/actions/workflows/ci.yml/badge.svg)](https://github.com/mipalgu/swift-atl/actions/workflows/ci.yml)
[![Documentation](https://github.com/mipalgu/swift-atl/actions/workflows/documentation.yml/badge.svg)](https://github.com/mipalgu/swift-atl/actions/workflows/documentation.yml)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmipalgu%2Fswift-atl%2Fbadge%3Ftype%3Dswift-versions)](https://swiftpackageindex.com/mipalgu/swift-atl)
[![](https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fmipalgu%2Fswift-atl%2Fbadge%3Ftype%3Dplatforms)](https://swiftpackageindex.com/mipalgu/swift-atl)

A pure Swift implementation of the Eclipse Atlas Transformation Language (ATL) with full XMI serialisation support.

**Note**: This package provides the ATL library. The `swift-atl` command-line tool is available in the [swift-modelling](https://github.com/mipalgu/swift-modelling) package.

## Features

- **Pure Swift**: No Java/EMF dependencies, Swift 6.0+ with strict concurrency
- **Cross-Platform**: Full support for macOS 15.0+ and Linux
- **Eclipse ATL Compatibility**: Syntax-compatible with Eclipse ATL transformations
- **Complete ATL Parser**: Full ATL/OCL syntax support with 96/96 tests passing
- **XMI Serialisation**: Complete Eclipse ATL XMI format support with 134/134 round-trip tests passing
- **Resource Framework**: Integration with ECore Resource/ResourceSet for metamodel management
- **Expression System**: 16+ expression types (literals, navigation, operations, collections, control flow)
- **Advanced OCL**: Let expressions, tuple expressions, iterate operations, lambda expressions
- **Metamodel-Qualified Types**: Full support for `MM!Type` syntax
- **Lazy Rules**: Deferred rule execution with lazy binding resolution
- **Helper Functions**: Context and standalone helper functions
- **Execution Engine**: Complete ATL virtual machine with 134/134 tests passing

## Requirements

- Swift 6.0 or later
- macOS 15.0+ or Linux

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

The ATL library can be used programmatically for parsing and executing ATL transformations:

```swift
import ATL
import ECore

// Parse ATL transformation
let parser = ATLParser()
let module = try await parser.parseFile(url: transformationURL)

// Create resource and load module
let resource = ATLResource(uri: "file:///path/to/transform.atl")
try await resource.load()

// Access parsed module
if let atlModule = resource.module {
    print("Module: \(atlModule.name)")
    print("Matched rules: \(atlModule.matchedRules.count)")
    print("Helpers: \(atlModule.helpers.count)")
}

// Save to XMI format
let xmiResource = ATLResource(uri: "file:///path/to/output.xmi", module: module)
try await xmiResource.save()
```

## CLI Tool

The `swift-atl` command-line tool is available in the [swift-modelling](https://github.com/mipalgu/swift-modelling) package and provides comprehensive transformation functionality:

- **parse**: Parse and analyse ATL transformation files
- **validate**: Validate ATL transformation syntax and semantics
- **test**: Test ATL transformation files with comprehensive checks
- **analyse**: Analyse complexity metrics and transformation patterns
- **compile**: Compile ATL transformations to optimised format (planned)
- **transform**: Execute model transformations (in development)
- **generate**: Generate code from models (planned)

To use the CLI tool, install the [swift-modelling](https://github.com/mipalgu/swift-modelling) package.

## Implementation Status

### ATL Library Core

- [x] **ATL Parser**: Complete syntax support for all ATL constructs (96/96 tests passing)
- [x] **Module System**: Full ATL module support with source/target metamodels
- [x] **Matched Rules**: Pattern matching with guards and multiple target patterns
- [x] **Called Rules**: Parameterised transformation rules
- [x] **Lazy Rules**: Deferred rule execution with lazy binding resolution
- [x] **Helper Functions**: Context helpers and standalone helper functions
- [x] **OCL Expressions**: Complete expression system (16+ types)
- [x] **Metamodel-Qualified Types**: Full `MM!Type` syntax support

### OCL Expression System

- [x] **Literals**: Integer, Real, String, Boolean, Type literals
- [x] **Variables**: Variable references and declarations
- [x] **Navigation**: Property and feature navigation
- [x] **Binary Operations**: Arithmetic, comparison, logical, string operations
- [x] **Unary Operations**: Negation, logical not
- [x] **Method Calls**: Object method invocations
- [x] **Helper Calls**: ATL helper function calls
- [x] **Conditional Expressions**: If-then-else expressions
- [x] **Collection Literals**: Sequence, Set, Bag, OrderedSet literals
- [x] **Collection Operations**: select, reject, collect, iterate, forAll, exists, etc.
- [x] **Let Expressions**: Local variable binding
- [x] **Lambda Expressions**: Anonymous functions for iteration
- [x] **Iterate Expressions**: Custom iteration with accumulator
- [x] **Tuple Expressions**: Tuple construction and field access

### ATL XMI Serialisation

- [x] **ATL Resource Framework**: Integration with ECore Resource/ResourceSet
- [x] **XMI Serialisation**: Eclipse ATL XMI format for all constructs
- [x] **XMI Parsing**: Recursive descent parser for expression trees
- [x] **Expression Serialisation**: All 16+ expression types supported
- [x] **Expression Parsing**: DOM-based architecture for correctness
- [x] **Round-Trip Tests**: 134/134 tests passing including nested expressions
- [x] **Eclipse Compatibility**: Proper namespace and format compliance

### ATL Execution Engine 🚧

- [x] **ATLVirtualMachine**: Basic VM architecture
- [x] **ATLExecutionContext**: Transformation context management
- [x] **Model Adapters**: Source/target model integration
- [ ] **Rule Execution**: Matched rule execution with element selection
- [ ] **Lazy Binding Resolution**: Deferred reference resolution
- [ ] **Helper Execution**: Context and standalone helper invocation
- [ ] **OCL Expression Evaluation**: Full expression evaluation engine
- [ ] **Model Loading**: XMI/JSON source model loading
- [ ] **Model Saving**: Target model serialisation


## Architecture

Swift ATL is built on a layered architecture:

1. **ATL Parser:** Lexer → Parser → AST construction
2. **ATL Module:** Module, Rule, Helper, Expression structures
3. **Resource Framework:** ATLResource with XMI serialisation
4. **Execution Engine** (In Development): Virtual machine for transformation execution

### Design Principles

- **Pure Swift**: No Java/EMF dependencies, native Swift 6.0 concurrency
- **Value Types**: Sendable structs for thread-safe ATL modules
- **@MainActor Isolation**: ATLResource uses @MainActor for coordination
- **Actor-based VM**: ATLVirtualMachine uses actor isolation for execution
- **Recursive Descent**: Expression parser uses DOM-based architecture for correctness
- **Eclipse Compatibility**: XMI format compatible with Eclipse ATL tools

## Licence

See the details in the LICENCE file.

## Compatibility

Swift ATL targets compatibility with:

- **[Eclipse ATL](https://eclipse.dev/atl/)**: Syntax-compatible with Eclipse ATL transformations
- **Eclipse ATL XMI**: Full round-trip compatibility with Eclipse ATL XMI format
- **[swift-ecore](https://github.com/mipalgu/swift-ecore)**: Integrated with ECore metamodel framework