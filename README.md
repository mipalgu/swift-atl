# Swift Modelling

A pure Swift implementation of the Atlas Transformation Language.

## Features

- **Pure Swift**: No Java/EMF dependencies, Swift 6.2+ with strict concurrency
- **Cross-Platform**: Full support for macOS and Linux
- **Value Types**: Sendable structs and enums for thread safety
- **BigInt Support**: Full arbitrary-precision integer support via swift-numerics
- **Complete Metamodel**: EClass, EAttribute, EReference, EPackage, EEnum, EDataType
- **Resource Infrastructure**: EMF-compliant object management and ID-based reference resolution
- **JSON Serialisation**: Load and save JSON models with full round-trip support
- **Bidirectional References**: Automatic opposite reference management across resources
- **XMI Parsing**: Load .ecore metamodels and .xmi instance files
- **Dynamic Attribute Parsing**: Arbitrary XML attributes with automatic type inference (Int, Double, Bool, String)
- **XPath Reference Resolution**: Same-resource references with XPath-style navigation (//@feature.index)
- **XMI Serialisation**: Write models to XMI format with full round-trip support
- 🚧 **ATL Transformations**: Atlas Transformation Language with parser and end-to-end testing (basic functionality)
- 🚧 **Code Generation**: Generate Swift, C++, C, LLVM IR via ATL (coming soon)

## Requirements

- Swift 6.0 or later
- macOS 15.0+ or Linux (macOS 15.0+ required for SwiftXML dependency)

## Building

```bash
# Build the library and CLI tool
swift build

# Run tests
swift test

# Run the CLI
swift run swift-atl --help
```

## Usage

The `swift-atl` command-line tool provides comprehensive transformation functionality for Swift.
All commands support the `--verbose` flag for detailed output and `--help` for usage information.

## Implementation Status

### Core Types ✅

- [x] SPM package structure
- [x] Primitive type mappings (EString, EInt, EBoolean, EBigInt, etc.)
- [x] BigInt support via swift-numerics
- [x] Type conversion utilities
- [x] 100% test coverage for primitive types

### Metamodel Core ✅

- [x] EObject protocol
- [x] EModelElement (annotations)
- [x] ENamedElement
- [x] EClassifier hierarchy (EDataType, EEnum, EEnumLiteral)
- [x] EClass with structural features
- [x] EStructuralFeature (EAttribute and EReference with ID-based opposites)
- [x] EPackage and EFactory
- [x] Resource and ResourceSet infrastructure

### In-Memory Model Testing ✅

- [x] Binary tree containment tests (BinTree model)
- [x] Company cross-reference tests
- [x] Shared reference tests
- [x] Multi-level containment hierarchy tests

### JSON Serialisation ✅

- [x] JSON parser for model instances
- [x] JSON serialiser with sorted keys
- [x] Round-trip tests for all data types
- [x] Comprehensive error handling

### XMI Serialisation ✅

- [x] SwiftXML dependency added
- [x] XMI parser foundation (Step 4.1)
- [x] XMI metamodel deserialisation (Step 4.2) - EPackage, EClass, EEnum, EDataType, EAttribute, EReference
- [x] XMI instance deserialisation (Step 4.3) - Dynamic object creation from instance files
- [x] Dynamic attribute parsing with type inference - Arbitrary XML attributes parsed without hardcoding
- [x] XPath reference resolution (Step 4.4) - Same-resource references with XPath-style navigation
- [x] XMI serialiser (Step 4.5) - Full serialisation with attributes, containment, and cross-references
- [x] Round-trip tests - XMI → memory → XMI with in-memory verification at each step
- [x] Cross-resource references (Step 4.6)

### Generic JSON Serialisation ✅

- [x] JSON parser for model instances (Step 5.1)
- [x] JSON serialiser with sorted keys (Step 5.2)
- [x] Dynamic EClass creation from JSON - Type inference for attributes and references
- [x] Boolean type handling fix - Boolean detection from Foundation's JSONSerialisation
- [x] Multiple root objects support - Arrays of JSON root objects
- [x] Cross-format conversion - XMI ↔ JSON bidirectional conversion
- [x] Round-trip tests for all data types
- [x] PyEcore compatibility validation - minimal.json and intfloat.json patterns
- [x] Comprehensive error handling

### Phase 7: ATL 🚧

- [x] ATL parser infrastructure with lexer and syntax analyzer
- [x] End-to-end testing with comprehensive ATL resource files
- [x] Resource loading and Bundle.module integration
- [x] Basic ATL module construction and validation
- [ ] ATL execution engine and virtual machine
- [ ] OCL expression evaluation
- [ ] Model-to-model transformation execution
- [ ] Code generation templates

### ATL CLI Tool 🚧

- [x] Validate command - Validate models and metamodels for correctness
- [x] Convert command - Convert between XMI and JSON formats  
- [x] Generate command - Generate code in Swift, C++, C, and LLVM IR
- [x] Query command - Query models with info, count, find, list-classes, and tree operations


## Architecture

**Swift Modelling** consists of:
- **ECore module**: Core library implementing the Ecore metamodel
- **ATL module**: Atlas Transformation Language parser and infrastructure
- **swift-ecore executable**: Command-line tool for validation, conversion, and code generation
- **swift-atl executable**: ATL transformation tool (coming soon)

All types are value types (structs) for thread safety, with ID-based reference resolution for bidirectional relationships.
Resources provide EMF-compliant object ownership and cross-reference resolution using actor-based concurrency.
ATL transformations use generics over existentials for type safety while maintaining flexibility for heterogeneous collections.

## Licence

See the details in the LICENCE file.

## Compatibility

Swift Modelling aims for 100% round-trip compatibility with:
- [emf4cpp](https://github.com/catedrasaes-umu/emf4cpp) - C++ EMF implementation
- [pyecore](https://github.com/pyecore/pyecore) - Python EMF implementation
- [Eclipse ATL](https://eclipse.dev/atl/) - Reference ATL implementation (syntax compatibility)
