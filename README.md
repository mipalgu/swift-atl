# Swift Ecore

A pure Swift implementation of the Eclipse Modeling Framework (EMF) Ecore metamodel for macOS and Linux.

## Features

- ✅ **Pure Swift**: No Java/EMF dependencies, Swift 6.2+ with strict concurrency
- ✅ **Cross-Platform**: Full support for macOS and Linux
- ✅ **Value Types**: Sendable structs and enums for thread safety
- 🚧 **XMI Serialization**: Load and save .ecore and .xmi files (coming soon)
- 🚧 **JSON Serialization**: Load and save JSON models (coming soon)
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
# Deploy and test on remote Linux machine
scp -pr swift-ecore plucky.local:src/swift/rh/Metamodels/ && \
ssh plucky.local "cd src/swift/rh/Metamodels/swift-ecore && swift test --scratch-path /tmp/build-swift-ecore"
```

## Project Status

### Phase 1: Core Types ✅

- [x] SPM package structure
- [x] Primitive type mappings (EString, EInt, EBoolean, etc.)
- [x] Type conversion utilities
- [x] 100% test coverage for primitive types

### Phase 2: Metamodel Core 🚧

- [ ] EObject protocol
- [ ] EModelElement (annotations)
- [ ] ENamedElement
- [ ] EClassifier hierarchy
- [ ] EClass with features
- [ ] EAttribute and EReference
- [ ] EPackage and EFactory

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

## Licence

See the details in the LICENCE file.

## Compatibility

Swift Ecore aims for 100% round-trip compatibility with:
- [emf4cpp](https://github.com/catedrasaes-umu/emf4cpp) - C++ EMF implementation
- [pyecore](https://github.com/pyecore/pyecore) - Python EMF implementation

Test data is validated against both implementations to ensure interoperability.
