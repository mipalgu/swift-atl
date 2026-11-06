# Getting Started with ATL

Learn how to add ATL to your project and create your first model transformation.

## Overview

This guide walks you through adding ATL to your Swift project and demonstrates
how to write and execute a simple model transformation.

## Adding ATL to Your Project

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

## Writing an ATL Transformation

ATL transformations are written in `.atl` files. Here's a simple example that
transforms UML classes to database tables:

```atl
-- Class2Table.atl
-- @path UML=UML.ecore
-- @path Database=Database.ecore
module Class2Table;
create OUT : Database from IN : UML;

-- Transform each Class to a Table
rule Class2Table {
    from
        c : UML!Class
    to
        t : Database!Table (
            name <- c.name,
            columns <- c.attributes->collect(a | thisModule.Attribute2Column(a))
        )
}

-- Transform each Attribute to a Column
rule Attribute2Column {
    from
        a : UML!Attribute
    to
        col : Database!Column (
            name <- a.name,
            type <- a.type.name
        )
}
```

### Module Declaration

The `-- @path` comments name the files of the metamodels, relative to the
transformation. The `module` line declares the transformation name. The `create` line
specifies:
- `OUT : Database` - the output model uses the Database metamodel
- `IN : UML` - the input model uses the UML metamodel

### Matched Rules

Each `rule` block defines a pattern match:
- `from` - the source pattern to match
- `to` - the target elements to create

## Parsing the Transformation

Use ``ATLParser`` to parse the ATL file. The parser loads the metamodels that the
`-- @path` directives name; metamodels that are not held in files can be supplied with
an ``ATLMetamodelRegistry``, as <doc:UnderstandingATL> describes. The
``ATLOptions/standard`` options give the current behaviour, such as accepting collection
ranges like `Sequence{1..3}`:

```swift
import ATL
import ECore

let parser = ATLParser(options: .standard)
let module = try await parser.parse(URL(fileURLWithPath: "Class2Table.atl"))

print("Loaded module: \(module.name)")
print("Rules: \(module.matchedRules.count)")
```

## Loading the Source Model

Register the source metamodel with a resource set, so that the XMI parser can resolve
the types of the source model, and load the model:

```swift
let resourceSet = ResourceSet()
if let uml = module.sourceMetamodels["IN"] {
    await resourceSet.registerMetamodel(uml, uri: uml.nsURI)
}
let source = try await XMIParser(resourceSet: resourceSet)
    .parse(URL(fileURLWithPath: "my-classes.xmi"))
```

## Executing the Transformation

Create an ``ATLVirtualMachine`` and execute the transformation with the source and
target models, named as in the `create` line. The ``ATLOptions/standard`` options
evaluate expressions as OCL and Eclipse ATL do, so `7 / 2` is the Real `3.5`:

```swift
let target = Resource(uri: "tables.xmi")
let vm = ATLVirtualMachine(module: module, options: .standard)
try await vm.execute(sources: ["IN": source], targets: ["OUT": target])

// Access execution statistics
print("Elements created: \(vm.statistics.elementsCreated)")
print("Rules executed: \(vm.statistics.rulesExecuted)")

// Save the result
try await XMISerializer().serialize(target, to: URL(fileURLWithPath: "tables.xmi"))
```

### Reporting Progress and Cancelling

``ATLVirtualMachine/execute(sources:targets:parameters:progress:)`` reports
``ATLProgress`` values (the phase, the number of steps completed, the total when it is
known and the current rule) to a callback on the main actor, and the run ends with a
report in the ``ATLProgressPhase/finished`` phase:

```swift
try await vm.execute(sources: ["IN": source], targets: ["OUT": target]) { progress in
    print(progress.phase, progress.completed, progress.total ?? 0)
}
```

The run checks for cancellation of its task at every rule, element and binding, and
regularly gives other work a turn, so a run started on the main actor keeps a user
interface responsive. A cancelled run throws `CancellationError` and leaves the target
models partly populated.

## Using Helpers

Helpers are reusable query operations. Define them in ATL:

```atl
helper context UML!Class def: hasAttributes : Boolean =
    self.attributes->notEmpty();

helper def: formatName(name : String) : String =
    name.toUpper();
```

Use helpers in rules:

```atl
rule Class2Table {
    from
        c : UML!Class (c.hasAttributes)  -- Guard using helper
    to
        t : Database!Table (
            name <- thisModule.formatName(c.name)  -- Using module helper
        )
}
```

### Navigating to the Container

Any model element can be asked for the object that contains it, so a helper does not need
the parent passed in:

```atl
helper context MM!Transition def: owner : MM!Machine =
    self.refImmediateComposite();
```

## Using Native Helpers

A host application can supply native helpers, implemented as closures rather than in ATL. A helper with a context type is called on a receiver (`s.render('x')`); one without is called by name (`greet('a')` or `thisModule.greet('a')`). Helpers are found by name and number of arguments, and contextual ones by the dynamic type of the receiver. A native helper takes precedence over a module helper of the same name, so a host can override it. An error thrown by the body is reported as an execution error that names the helper. See ``ATLNativeHelper``.

```swift
let greet = ATLNativeHelper(
    name: "greet", parameterTypes: ["String"], returnType: "String"
) { _, arguments in
    "hello \(arguments.first.flatMap { $0 as? String } ?? "")"
}
let machine = ATLVirtualMachine(module: module, options: .standard, nativeHelpers: [greet])
machine.register(otherHelper)  // helpers can also be added later
```

## Using Called Rules

Called rules are invoked explicitly rather than matched:

```atl
-- Called rule (not automatically matched)
rule CreatePrimaryKey(tableName : String) {
    to
        pk : Database!PrimaryKey (
            name <- tableName + '_pk'
        )
    do {
        pk;  -- Return the created element
    }
}

-- Invoke from a matched rule
rule Class2Table {
    from
        c : UML!Class
    to
        t : Database!Table (
            name <- c.name,
            primaryKey <- thisModule.CreatePrimaryKey(c.name)
        )
}
```

## Running a Query

A query unit computes a value from its input models instead of creating a target
model. Parse it as a module and evaluate it with
``ATLVirtualMachine/evaluateQuery(sources:parameters:)``. A query that writes its
result with `writeTo` needs a file output policy, because writing files is disabled
by default:

```swift
let query = try await ATLParser(options: .standard).parse(URL(fileURLWithPath: "LibraryGraph.atl"))
let vm = ATLVirtualMachine(
    module: query, options: .standard, fileOutput: .confined(to: URL(fileURLWithPath: "output")))
let written = try await vm.evaluateQuery(sources: ["Library": libraryModel])
```

See <doc:UnderstandingATL> for how input models are named and how file paths are
resolved.

## Reading and Writing ATL XMI

An ``ATLResource`` holds an ATL module and reads it from a file URI ending in `.atl` or
`.xmi`. It writes the module to a `.xmi` file URI in the Eclipse ATL XMI format:

```swift
let resource = ATLResource(
    uri: URL(fileURLWithPath: "Class2Table.atl").absoluteString, options: .standard)
try await resource.load()

if let module = resource.module {
    let xmi = ATLResource(
        uri: URL(fileURLWithPath: "Class2Table.xmi").absoluteString,
        module: module, options: .standard)
    try await xmi.save()
}
```

## Supporting Editors

``ATLSyntax/tokens(in:options:)`` classifies the tokens of ATL source text, including
comments and unreadable text, and never fails.
``ATLParser/parseDiagnosing(_:name:metamodelRegistry:)`` parses source text without
throwing. It recovers at the level of declarations and bindings, and returns an
``ATLParseResult`` with the module read so far, diagnostics with source ranges and stable
``ATLDiagnosticCode`` values, an outline of the module and the tokens:

```swift
let result = await ATLParser(options: .standard)
    .parseDiagnosing(text, name: "Class2Table.atl")
for diagnostic in result.diagnostics {
    print(diagnostic.severity, diagnostic.message)
}
```

Parsed syntax tree nodes carry a `SourceOrigin` with their range in the source text,
which does not take part in equality. ATL constructs that are not supported are reported
as ``ATLDiagnosticCode/unsupportedConstruct`` errors; the Compatibility section of
<doc:ATL> lists them.

## Debugging Transformations

Enable debugging to trace execution:

```swift
let vm = ATLVirtualMachine(module: module, options: .standard, enableDebugging: true)
```

This prints detailed information about rule matching and element creation.

## Next Steps

- <doc:UnderstandingATL> - Deep dive into ATL concepts
- ``ATLMatchedRule`` - Matched rule API reference
- ``ATLHelper`` - Helper definition API
- ``ATLExecutionContext`` - Advanced execution control
