# Swift Modelling

A pure Swift implementation of the Eclipse Modeling Framework (EMF) Ecore metamodel for macOS and Linux.

## Features

- ✅ **Pure Swift**: No Java/EMF dependencies, Swift 6.2+ with strict concurrency
- ✅ **Cross-Platform**: Full support for macOS and Linux
- ✅ **Value Types**: Sendable structs and enums for thread safety
- ✅ **BigInt Support**: Full arbitrary-precision integer support via swift-numerics
- ✅ **Complete Metamodel**: EClass, EAttribute, EReference, EPackage, EEnum, EDataType
- ✅ **Resource Infrastructure**: EMF-compliant object management and ID-based reference resolution
- ✅ **JSON Serialization**: Load and save JSON models with full round-trip support
- ✅ **Bidirectional References**: Automatic opposite reference management across resources
- 🚧 **XMI Serialization**: Load .ecore and .xmi files (parser implemented, serializer in progress)
- 🚧 **ATL Transformations**: Model-to-model transformations (coming soon)
- 🚧 **Code Generation**: Generate Swift, C++, C, LLVM IR via ATL (coming soon)

## Requirements

- Swift 6.0 or later
- macOS 14.0+ or Linux

## Building

```bash
# Build the library and CLI tool
swift build --scratch-path /tmp/build-swift-ecore

# Run tests
swift test --scratch-path /tmp/build-swift-ecore

# Run the CLI
swift run --scratch-path /tmp/build-swift-ecore swift-ecore --help
```

## Testing on Linux

```bash
# Update and test on remote Linux machine (using git)
ssh plucky.local "cd src/swift/rh/Metamodels/swift-modelling && git pull && swift test --scratch-path /tmp/build-swift-ecore"
```

## Project Status

### Phase 1: Core Types ✅

- [x] SPM package structure
- [x] Primitive type mappings (EString, EInt, EBoolean, EBigInt, etc.)
- [x] BigInt support via swift-numerics
- [x] Type conversion utilities
- [x] 100% test coverage for primitive types

### Phase 2: Metamodel Core 🚧

- [x] EObject protocol
- [x] EModelElement (annotations)
- [x] ENamedElement
- [x] EClassifier hierarchy (EDataType, EEnum, EEnumLiteral)
- [x] EClass with structural features
- [x] EStructuralFeature (EAttribute and EReference with ID-based opposites)
- [x] EPackage and EFactory
- [x] Resource and ResourceSet infrastructure

### Phase 3: Serialization 🚧

- [ ] XMI parser and serializer
- [ ] JSON parser and serializer
- [ ] Cross-format conversion

### Phase 4: CLI Tool 🚧

- [ ] Validate command
- [ ] Convert command
- [ ] Generate command
- [ ] Query command

### Phase 5: ATL 🚧

- [ ] ATL lexer and parser
- [ ] ATL interpreter
- [ ] Code generation templates

## Architecture

**Swift Modelling** consists of:
- **ECore module**: Core library implementing the Ecore metamodel
- **swift-ecore executable**: Command-line tool for validation, conversion, and code generation

All types are value types (structs) for thread safety, with ID-based reference resolution for bidirectional relationships. Resources provide EMF-compliant object ownership and cross-reference resolution using actor-based concurrency.

## Licence

See the details in the LICENCE file.

## Compatibility

Swift Modelling aims for 100% round-trip compatibility with:
- [emf4cpp](https://github.com/catedrasaes-umu/emf4cpp) - C++ EMF implementation
- [pyecore](https://github.com/pyecore/pyecore) - Python EMF implementation

Test data is validated against both implementations to ensure interoperability.
