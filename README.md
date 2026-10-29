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
- **Reflection**: `refImmediateComposite()`, `refGetValue`, `refSetValue`, `refUnsetValue` and `refInvokeOperation` on any model element
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

## Language Support

### Literals and operators

- Strings support the escapes `\'`, `\"`, `\\`, `\n`, `\r`, `\t`, `\b`, `\f`, `\uXXXX` and octal escapes. Any other backslash sequence is kept as written, so regular expressions such as `'\s+'` need no doubling.
- Real literals (`3.14`, `1e-3`), enumeration literals (`#Editable`), `OclUndefined` (and `null`) are supported. An enumeration literal evaluates to the literal name, which is how enumeration-typed attributes of dynamic objects are stored. Binding it to an attribute checks that the enumeration declares the literal.
- `Sequence{}`, `OrderedSet{}`, `Set{}` and `Bag{}` literals keep their elements, not descriptions of them. Sets and ordered sets remain duplicate-free through `union`, `including`, `append` and friends.
- Collection literals accept OCL integer ranges `first..last`, alone or mixed with items: `Sequence{0, 2..4, 9}` holds `0, 2, 3, 4, 9`. Both bounds may be expressions but must be Integers; a range whose first value exceeds its last is empty, and sets keep each integer once. Ranges are an OCL feature that the Eclipse ATL compilers do not accept, so transformations that use them do not run on Eclipse ATL; `includingRange` is the portable alternative.
- Infix `implies`, `xor`, `div` and `mod` follow OCL precedence: `implies` binds weakest, then `or` and `xor`, then `and`. Logical operators use three-valued logic with `OclUndefined`.

### Built-in operations

Collections: `any`, `count`, `sum`, `at`, `append`, `prepend`, `insertAt`, `subSequence`, `subOrderedSet`, `including`, `includingAll`, `includingRange`, `excluding`, `excludingAll`, `union`, `intersection`, `symmetricDifference`, `indexOf`, `lastIndexOf`, `includesAll`, `excludesAll`, `isUnique`, `one`, `exists` and `forAll` (with several iterator variables), `sortedBy`, `flatten`, `reverse`, `max`, `min`, and the conversions `asSet`, `asOrderedSet`, `asSequence` and `asBag`. `first()` and `last()` return `OclUndefined` on an empty collection. Single values behave as one-element collections.

Strings: `concat`, `substring`, `toInteger`, `toReal`, `toUpper`, `toLower`, `toSequence`, `trim`, `startsWith`, `endsWith`, `indexOf`, `lastIndexOf`, `split`, `replaceAll` and `regexReplaceAll` (positions are 1-based). `'text'.println()` prints the string to standard output, and `'text'.writeTo('out.txt')` and `'text'.writeToWithCharset('out.txt', 'ISO-8859-1')` write it to a file when the host permits it (see [Writing files](#writing-files)).

Numbers: the method form `div(n)`, `longValue()`, and the Real functions `sqrt`, `exp`, `log`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `toDegrees` and `toRadians`.

Types: `oclIsKindOf` and `oclIsTypeOf` (over the complete supertype closure), `oclAsType`, `oclType`, `oclIsUndefined`, `MM!Class.allInstances()` and `MM!Class.allInstancesFrom('IN')`.

Reflection and containment: `refImmediateComposite()` returns the object that directly contains the receiver (or `OclUndefined`); `refGetValue(name)` returns the value of the named feature; `refSetValue(name, value)` sets a feature of a target element and returns the element; `refUnsetValue(name)` resets a feature of a target element; `refInvokeOperation(name, args)` invokes the helper of that name with a sequence of arguments; `eContainer()`, `eContainingFeature()`, `eContents()` and `eAllContents()` offer the EMF spellings of container navigation (the property forms such as `obj.eContainer` also work); and `MM!Class.newInstance()` creates an element of that class in the target model bound to `MM`. Source models are read-only, so setting or unsetting a feature of a source element is an error. `debug(message)` prints `message: value` to standard error and returns the value.

### Helpers

Contextual helpers are keyed by context type and name. A call dispatches on the dynamic type of the receiver, and the most specific context type wins, so `helper context A def : f()` and `helper context B def : f()` coexist. Helpers declared without a parameter list (`def : name : Type = ...`) are attributes whose value is computed once per receiver.

### Native helpers

A host application can supply native helpers, implemented as closures rather than in ATL. A helper with a context type is called on a receiver (`s.render('x')`); one without is called by name (`greet('a')` or `thisModule.greet('a')`). Helpers are found by name and number of arguments, and contextual ones by the dynamic type of the receiver. A native helper takes precedence over a module helper of the same name, so a host can override it. An error thrown by the body is reported as an execution error that names the helper.

```swift
let greet = ATLNativeHelper(
    name: "greet", parameterTypes: ["String"], returnType: "String"
) { _, arguments in
    "hello \(arguments.first.flatMap { $0 as? String } ?? "")"
}
let machine = ATLVirtualMachine(module: module, nativeHelpers: [greet])
machine.register(otherHelper)  // helpers can also be added later
```

### Binding metamodels

A metamodel named in the module header is bound, in order of precedence, by:

1. `-- @nsURI Name=http://example.org/model`, resolved through an `ATLMetamodelRegistry` supplied to the parser,
2. `-- @path Name=/path/to/Name.ecore`,
3. a lookup of the name in the registry (letter case is ignored when the match is unique).

```swift
let registry = ATLMetamodelRegistry(packages: [ecorePackage, genModelPackage])
let module = try await ATLParser().parse(url, metamodelRegistry: registry)
```

A registry can also be built from a table of namespace URIs, or given a resolver closure for URIs it does not hold. Type references such as `Ecore!EClass` use the name from the module header, which need not equal the name of the bound package.

### Module parameters

Header comments declare parameters of type `String`, `Integer`, `Boolean` or `Real`. A parameter without a default is required.

```
-- @param basePackage : String = 'org.example'
-- @param generateTests : Boolean = false
-- @param projectName : String
```

The caller supplies values when executing, and the transformation reads them as `thisModule.projectName`:

```swift
try await ATLVirtualMachine(module: module).execute(
    sources: ["IN": input], targets: ["OUT": output],
    parameters: ["projectName": "demo", "generateTests": true])
```

A missing required parameter, an undeclared parameter or a value of the wrong type is reported as an `ATLExecutionError`. `ATLModule.parameterValues(fromText:)` converts textual values, for example from a command line, to the declared types.

### Queries

A query unit computes a single value from its input models instead of creating target models. It starts with `query Name = expression;` instead of a module header and contains only helpers besides its query (no rules and no `create` statement). Its metamodels are named by `-- @path` or `-- @nsURI` directives, as in Eclipse ATL.

```
-- @path Library=Library.ecore
query BookCount = Library!Book.allInstances()->size().toString() + ' ' + thisModule.unit;

helper def : unit : String = 'books';
```

`ATLParser` returns a query unit as an `ATLModule` whose `kind` is `.query` and whose `queryBody` holds the query expression. `ATLVirtualMachine.evaluateQuery(sources:parameters:)` binds the input models, evaluates the query and returns its value. Each metamodel named by a directive is declared as an input model of the same name; `declaringSourceModels(_:metamodels:)` gives the models other names, as `IN : Library` would in a module header, and can supply metamodel packages that no directive names:

```swift
let query = try await ATLParser().parse(queryURL)
let value = try await ATLVirtualMachine(module: query).evaluateQuery(sources: ["Library": library])

// Name the model IN, so that the query can use allInstancesFrom('IN')
let renamed = query.declaringSourceModels(["IN": "Library"])
let count = try await ATLVirtualMachine(module: renamed).evaluateQuery(sources: ["IN": library])
```

Helpers, `thisModule` and `-- @param` parameters work in queries as they do in modules. A query whose value is a string often ends with `writeTo`, in which case its value is `true`, as in Eclipse ATL.

### Writing files

`writeTo(path)` writes a string to a file in UTF-8 and returns `true`; `writeToWithCharset(path, charset)` writes it in the named charset. Both replace an existing file, create missing intermediate directories and write the string exactly, without adding a line break. They work in queries, helpers, bindings and `do` blocks alike.

Writing files is disabled by default: a transformation or query that calls either operation fails with an `ATLExecutionError` until the host enables file output on the virtual machine with an `ATLFileOutputPolicy`:

```swift
// Write only inside the output directory
let vm = ATLVirtualMachine(module: query, fileOutput: .confined(to: outputDirectory))

// Trusted code only: relative paths resolve against the directory, absolute paths are accepted
vm.fileOutput = .unrestricted(relativeTo: outputDirectory)
```

A confined policy resolves relative paths against its directory and rejects absolute paths and every path that leads outside the directory, whether through `..` components or through symbolic links, with an error that names the path. Confinement protects against the transformation itself, not against other processes that can change the output directory while the transformation runs, so the output directory should not be writable by untrusted users. Eclipse ATL resolves relative paths against the workspace or the working directory of the Java process instead, and accepts any path.

The charsets `UTF-8`, `UTF-16` (big-endian with a byte order mark, as Java writes it), `UTF-16BE`, `UTF-16LE`, `UTF-32`, `UTF-32BE`, `UTF-32LE`, `ISO-8859-1` and `US-ASCII` are supported, and their names are matched without regard to case. An unknown charset, or a string that the charset cannot represent, is reported as an error rather than written with substitute characters.

### Execution semantics

A transformation runs in two phases. All matched rules first create their target elements (and `entrypoint` called rules run), then every binding and `do` block is applied, then failed bindings are retried and `endpoint` rules run. Rule order therefore never matters for references.

- A source element assigned to a reference becomes the default target element it was transformed into; `thisModule.resolveTemp(source, 'pattern')` selects a named target pattern element instead.
- The same applies inside collections: `Sequence{a, b}`, `Set{}` and results of `collect` keep their elements, which are then resolved element by element when assigned to a multi-valued feature.
- References to elements of the same target model are stored by identifier, references to elements that were not transformed are stored as cross-resource proxies, and a mix is stored as a mixed collection.
- Every assignment (bindings, `target.feature <- value;` in `do` blocks and retried bindings) applies the enumeration-literal check and numeric conversion of the target feature.
- Reading an attribute that the model leaves unset gives the feature's default value, as `eGet` does in the Eclipse Modeling Framework: the declared default, otherwise `false`, `0` or `0.0`; strings and references read as `OclUndefined`. A guard such as `not c.isAbstract` therefore holds for an element whose XMI omits the attribute; create the virtual machine with `unsetFeatureReads: .undefined` for the non-standard mode that reads every unset feature as `OclUndefined`.
- `abstract`, `extends`, `unique lazy`, `entrypoint` and `endpoint` rules, `using` variables, several source patterns and imperative `do` statements are supported. Metamodels are looked up through the aliases declared in the module header, so `-- @nsURI` bindings and `thisModule` parameters work in every rule kind.

### Progress and cancellation

`ATLVirtualMachine.execute(sources:targets:parameters:progress:)` reports `ATLProgress` values (the phase, the number of steps completed, the total when it is known and the current rule) to a `@MainActor` callback, and the run ends with a `finished` report. The run checks for cancellation at every rule, element and binding and gives other tasks a turn about every ten milliseconds, so a run started on the main actor keeps the interface responsive. A cancelled run throws `CancellationError` and leaves the target models partly populated.

### Editor support

`ATLSyntax.tokens(in:)` classifies the tokens of ATL source text, including comments and unreadable text, without ever failing. `ATLParser.parseDiagnosing(_:name:metamodelRegistry:)` parses source text without throwing: it recovers at declaration and binding level, and returns the module read so far, diagnostics with source ranges and stable `ATLDiagnosticCode` values, an outline of the module and the tokens. Parsed syntax tree nodes carry a `SourceOrigin` with their range in the source text, which does not take part in equality.

The ATL constructs that are not supported (libraries and `uses`, refining mode, `nodefault` rules, iterated target patterns with `foreach` or `distinct`, and `extends` on lazy or called rules) are reported as `unsupportedConstruct` errors at the offending token. Text that cannot start a declaration is reported as an unexpected token by both parsers.

## CLI Tool

The `swift-atl` command-line tool is available in the [swift-modelling](https://github.com/mipalgu/swift-modelling) package and provides comprehensive transformation functionality:

- **parse**: Parse and analyse ATL transformation files
- **validate**: Validate ATL transformation syntax and semantics
- **test**: Test ATL transformation files with comprehensive checks
- **analyse**: Analyse complexity metrics and transformation patterns
- **compile**: Compile ATL transformations to optimised format (planned)
- **transform**: Execute model transformations (in development)
- **query**: Evaluate ATL queries and write the files they produce
- **generate**: Generate code from models (planned)

To use the CLI tool, install the [swift-modelling](https://github.com/mipalgu/swift-modelling) package.

## Implementation Status

### ATL Library Core

- [x] **ATL Parser**: Complete syntax support for all ATL constructs (96/96 tests passing)
- [x] **Module System**: Full ATL module support with source/target metamodels
- [x] **Query Units**: `query Name = expression;` with helpers, evaluated to a value
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
- [x] **Collection Literals**: Sequence, Set, Bag, OrderedSet literals, including integer ranges
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
- [x] **Rule Execution**: Matched rule execution with element selection
- [x] **Lazy Binding Resolution**: Deferred reference resolution
- [x] **Helper Execution**: Context and standalone helper invocation
- [x] **OCL Expression Evaluation**: Full expression evaluation engine
- [ ] **Model Loading**: XMI/JSON source model loading
- [ ] **Model Saving**: Target model serialisation
- [x] **Two-phase Execution**: All matched rules create their targets before any binding is applied
- [x] **Implicit Trace Resolution**: Source elements bound to references become the target elements they were transformed into; `resolveTemp(source, 'pattern')` returns a named target pattern element
- [x] **Cross-model References**: References to elements that were not transformed are stored as `ResourceProxy` values (URI of the source resource plus an XPath-style fragment) so that they serialise as cross-document `href`s
- [x] **Rule Variants**: `abstract` rules, `extends` inheritance, `unique lazy` memoisation, `entrypoint` and `endpoint` rules, `using` variables and several source patterns in `from`
- [x] **Imperative Blocks**: `do { }` sections with `target.feature <- value;`, variable declarations and assignments, `if`/`else`, `for` and expression statements
- [x] **Reflective Operations**: `refImmediateComposite`, `refGetValue`, `refSetValue`, `refUnsetValue`, `refInvokeOperation` and the `eContainer`, `eContainingFeature`, `eContents` and `eAllContents` method forms
- [x] **Read-only Source Models**: Setting or unsetting a feature of a source element is an error; only target elements can be modified
- [x] **File Output**: `writeTo` and `writeToWithCharset`, disabled unless the host enables them, and confined to an output directory by default


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

## References

This implementation is based on the following standards and technologies:

- [Eclipse ATL (Atlas Transformation Language)](https://eclipse.dev/atl/) - The reference ATL implementation
- [OMG QVT (Query/View/Transformation)](https://www.omg.org/spec/QVT/) - The model transformation standard
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/) - Expression language for guards and queries
- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/) - The metamodelling foundation