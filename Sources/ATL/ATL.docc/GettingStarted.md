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

The `module` line declares the transformation name. The `create` line specifies:
- `OUT : Database` - the output model uses the Database metamodel
- `IN : UML` - the input model uses the UML metamodel

### Matched Rules

Each `rule` block defines a pattern match:
- `from` - the source pattern to match
- `to` - the target elements to create

## Loading Metamodels

Before running a transformation, load the source and target metamodels:

```swift
import ATL
import ECore

// Load metamodels from .ecore files
let xmiParser = XMIParser()

let umlResource = try await xmiParser.parse(URL(fileURLWithPath: "UML.ecore"))
let umlMetamodel = umlResource.rootObjects.first as! EPackage

let dbResource = try await xmiParser.parse(URL(fileURLWithPath: "Database.ecore"))
let dbMetamodel = dbResource.rootObjects.first as! EPackage
```

## Parsing the Transformation

Use ``ATLParser`` to parse the ATL file:

```swift
let parser = ATLParser()
let module = try await parser.parse(URL(fileURLWithPath: "Class2Table.atl"))

print("Loaded module: \(module.name)")
print("Rules: \(module.matchedRules.count)")
```

## Configuring the Virtual Machine

Create an ``ATLVirtualMachine`` and register your metamodels and models:

```swift
// Create the virtual machine
let vm = ATLVirtualMachine(module: module)

// Register metamodels (names must match the ATL module declaration)
try await vm.registerSourceMetamodel(umlMetamodel, as: "UML")
try await vm.registerTargetMetamodel(dbMetamodel, as: "Database")

// Load and register the source model
let sourceResource = try await xmiParser.parse(URL(fileURLWithPath: "my-classes.xmi"))
try await vm.registerSourceModel(sourceResource, as: "IN")
```

## Executing the Transformation

Execute the transformation and retrieve results:

```swift
// Run the transformation
let result = try await vm.execute()

// Access execution statistics
print("Elements created: \(result.statistics.elementsCreated)")
print("Rules applied: \(result.statistics.rulesApplied)")

// Get the target model
guard let targetResource = result.targetModels["OUT"] else {
    fatalError("Target model not found")
}

// Save the result
let serialiser = XMISerializer()
try serialiser.save(resource: targetResource, to: URL(fileURLWithPath: "tables.xmi"))
```

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
let machine = ATLVirtualMachine(module: module, nativeHelpers: [greet])
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
let query = try await ATLParser().parse(URL(fileURLWithPath: "LibraryGraph.atl"))
let vm = ATLVirtualMachine(
    module: query, fileOutput: .confined(to: URL(fileURLWithPath: "output")))
let written = try await vm.evaluateQuery(sources: ["Library": libraryModel])
```

See <doc:UnderstandingATL> for how input models are named and how file paths are
resolved.

## Debugging Transformations

Enable debugging to trace execution:

```swift
let vm = ATLVirtualMachine(module: module, enableDebugging: true)
```

This prints detailed information about rule matching and element creation.

## Next Steps

- <doc:UnderstandingATL> - Deep dive into ATL concepts
- ``ATLMatchedRule`` - Matched rule API reference
- ``ATLHelper`` - Helper definition API
- ``ATLExecutionContext`` - Advanced execution control
