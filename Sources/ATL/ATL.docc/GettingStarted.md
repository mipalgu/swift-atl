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
