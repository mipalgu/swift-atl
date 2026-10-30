# Understanding ATL

Learn the fundamental concepts of the Atlas Transformation Language.

## Overview

[ATL (Atlas Transformation Language)](https://eclipse.dev/atl/) is a model transformation
language that allows you to declaratively specify how elements in a source model should
be transformed into elements in a target model.

ATL is related to the OMG QVT (Query/View/Transformation)
([OMG QVT](https://www.omg.org/spec/QVT/))
standard and uses OCL (Object Constraint Language)
([OCL](https://www.omg.org/spec/OCL/))
for expressions. This article explains the core concepts.

## Transformation Structure

An ATL transformation consists of:

1. **Module declaration**: Names the transformation and declares models
2. **Rules**: Define how source elements map to target elements
3. **Helpers**: Reusable query operations

```atl
module MyTransformation;                    -- Module name
create OUT : TargetMM from IN : SourceMM;  -- Model declaration

helper def: myHelper() : String = 'value'; -- Helper

rule MyRule {                               -- Rule
    from s : SourceMM!SourceClass
    to   t : TargetMM!TargetClass (...)
}
```

A query unit has no module declaration and no rules. It computes a single value from
its input models, as described under Queries below.

## Rule Types

ATL supports three types of rules:

### Matched Rules

Matched rules are automatically applied to all source elements that match their
input pattern. They are the most common rule type.

```atl
rule Class2Table {
    from
        c : UML!Class
    to
        t : DB!Table (
            name <- c.name
        )
}
```

The rule engine:
1. Finds all instances of `UML!Class` in the source model
2. Creates a `DB!Table` for each one
3. Sets the `name` attribute from the source

### Called Rules

Called rules are invoked explicitly using `thisModule.ruleName(args)`. They're
useful for:
- Creating elements conditionally
- Passing parameters
- Imperative control flow

```atl
rule CreateColumn(name : String, type : String) {
    to
        col : DB!Column (
            name <- name,
            type <- type
        )
    do {
        col;  -- Return the created element
    }
}
```

Invoke with:
```atl
columns <- attrs->collect(a | thisModule.CreateColumn(a.name, a.type.name))
```

### Lazy Rules

Lazy rules create elements on-demand. Unlike matched rules, they only execute
when explicitly called, but they cache results - calling with the same source
element returns the same target element.

```atl
lazy rule Type2SQLType {
    from
        t : UML!DataType
    to
        st : DB!SQLType (
            name <- t.name.toUpper()
        )
}
```

## Patterns

### Input Patterns

Input patterns specify what source elements to match:

```atl
from
    c : UML!Class,                          -- Simple pattern
    p : UML!Package (p.classes->includes(c)) -- With filter
```

Multiple pattern elements create a cross-product of matches (use with caution).

### Guards

Guards filter which elements a rule applies to:

```atl
from
    c : UML!Class (
        c.isAbstract = false and          -- Boolean guard
        c.attributes->notEmpty()           -- OCL expression
    )
```

### Output Patterns

Output patterns specify what target elements to create:

```atl
to
    t : DB!Table (
        name <- c.name,                    -- Simple binding
        columns <- c.attrs->collect(...)   -- Collection binding
    ),
    pk : DB!PrimaryKey (                   -- Multiple outputs
        table <- t
    )
```

## Bindings

Bindings assign values to target element features:

### Simple Bindings

```atl
name <- c.name                    -- Direct copy
upperName <- c.name.toUpper()     -- With transformation
```

### Reference Bindings

```atl
-- Single reference
owner <- c.package

-- Collection reference
columns <- c.attributes->collect(a | thisModule.resolveTemp(a, 'col'))
```

### Resolving References

Use `thisModule.resolveTemp(source, targetName)` to get the target element
created from a source element:

```atl
rule Class2Table {
    from c : UML!Class
    to
        t : DB!Table (...),
        pk : DB!PrimaryKey (...)
}

-- Later, to get the PrimaryKey created from a Class:
pk <- thisModule.resolveTemp(someClass, 'pk')
```

## Helpers

Helpers are reusable operations that can be:

### Attribute Helpers

Return a computed value for an element:

```atl
helper context UML!Class def: fullName : String =
    self.package.name + '.' + self.name;
```

Usage: `c.fullName`

### Operation Helpers

Take parameters and return values:

```atl
helper context UML!Class def: getAttribute(name : String) : UML!Attribute =
    self.attributes->select(a | a.name = name)->first();
```

Usage: `c.getAttribute('id')`

### Module Helpers

Not bound to a context, accessed via `thisModule`:

```atl
helper def: sqlTypes : Map(String, String) =
    Map{('String', 'VARCHAR'), ('Integer', 'INT')};
```

Usage: `thisModule.sqlTypes.get('String')`

## Execution Model

ATL executes in phases:

### 1. Matching Phase

- All matched rules are evaluated against source elements
- Guards determine which rules apply to which elements
- A schedule of rule applications is created

### 2. Creation Phase

- Target elements are created (but not fully initialised)
- Element references are recorded in the trace model

### 3. Initialisation Phase

- Bindings are evaluated
- Target element features are set
- References are resolved using the trace model

### 4. Resolution Phase

- Cross-references between target elements are resolved
- Lazy bindings are evaluated
- `endpoint` rules run last; `entrypoint` rules run after the creation phase

Every assignment, whether from a binding, a `do` block statement or a retried
binding, converts its value for the target feature: source elements in single
values and in collections become the target elements they were transformed into,
elements of the same target model are stored by identifier, other elements are
stored as cross-resource proxies, and enumeration-typed attributes accept only
the literals the enumeration declares.

## The Trace Model

ATL maintains a trace model linking source to target elements. This enables:

- **Reference resolution**: Finding target elements from source references
- **`resolveTemp`**: Getting specific target elements by name
- **Debugging**: Understanding which rules created which elements

## OCL Integration

ATL uses OCL (Object Constraint Language) for expressions:

### Navigation

```atl
c.name                           -- Attribute access
c.package                        -- Reference navigation
c.package.classes                -- Chained navigation
```

### Collections

```atl
classes->select(c | c.isAbstract)    -- Filter
classes->collect(c | c.name)          -- Map
classes->forAll(c | c.name <> '')     -- All match
classes->exists(c | c.isAbstract)     -- Any match
classes->size()                       -- Count
classes->first()                      -- First element
```

### Operations

```atl
name.toUpper()                    -- String operations
size > 0                          -- Comparisons
a and b                           -- Boolean logic
if cond then x else y endif       -- Conditionals
```

### Reflection and Containment

Standard OCL cannot navigate from an object to the object that contains it unless the
metamodel declares an opposite reference. ATL offers `refImmediateComposite()` for this
purpose, but it is an engine extension that not every ATL virtual machine provides (EMFTVM
in particular lacks it). Transformation authors therefore often thread parents through
helper parameters, or declare `eOpposite` references in the metamodel purely for the
transformation. This implementation supports `refImmediateComposite()` and the EMF
spellings `eContainer()`, `eContainingFeature()`, `eContents()` and `eAllContents()`, so
a transformation over a metamodel with plain containment can ask an element for its
container directly. For example, a transition in a nested arrangement of state machines
can find the machine that owns it:

```atl
module Machines2Flat;
create OUT : MM from IN : MM;

helper context MM!Transition def : owner : MM!Machine =
    self.refImmediateComposite();

rule Transition2Edge {
    from
        t : MM!Transition
    to
        e : MM!Edge (
            machineName <- t.owner.name,
            parent <- t.refImmediateComposite()
        )
}
```

The `refGetValue`, `refSetValue` and `refUnsetValue` operations read and modify features
by name. Source models are read-only, so these setters apply only to target elements;
setting a feature of a source element is an error.

```atl
rule Machine2Node {
    from
        m : MM!Machine
    to
        n : MM!Node
    do {
        n.refSetValue('label', m.refGetValue('name'));
        n.refUnsetValue('comment');
    }
}
```

`refInvokeOperation` calls the helper of the given name on the receiver with a sequence
of arguments, which is useful when the helper to call is chosen at run time:

```atl
helper context MM!Machine def : scaled(factor : Integer) : Integer =
    self.size * factor;

rule Machine2Scaled {
    from
        m : MM!Machine
    to
        n : MM!Node (
            size <- m.refInvokeOperation('scaled', Sequence {2})
        )
}
```

`MM!Class.newInstance()` creates a new element of that class in the target model bound to
`MM`, for use in called rules and `do` blocks.

`debug(message)` prints `message: value` to standard error and returns the value, which
makes it convenient for inspecting an expression in place.

## Queries

A query unit computes a single value from its input models. It starts with
`query Name = expression;` instead of a module header, and contains only helpers besides
its query: it has no `create` statement and no rules. The metamodels are named by
`-- @path` or `-- @nsURI` directives:

```atl
-- @path Library=Library.ecore
query BookCount =
    Library!Book.allInstances()->select(b | b.isLong)->size().toString();

helper context Library!Book def : isLong : Boolean = self.pages > 400;
```

The parser returns a query unit as an ``ATLModule`` whose ``ATLModule/kind`` is
``ATLUnitKind/query`` and whose ``ATLModule/queryBody`` holds the query expression.
``ATLVirtualMachine/evaluateQuery(sources:parameters:)`` binds the input models,
evaluates the query and returns its value:

```swift
let query = try await ATLParser(options: .standard).parse(queryURL)
let vm = ATLVirtualMachine(module: query)
let count = try await vm.evaluateQuery(sources: ["Library": libraryModel])
```

A query has no `from` clause, so each metamodel named by a directive is declared as an
input model with the name of the metamodel. ``ATLModule/declaringSourceModels(_:metamodels:)``
declares models with other names, as `IN : Library` would in a module header, and can
supply metamodel packages that no directive names. Type references such as
`Library!Book` resolve through the metamodel name, `allInstances()` collects the
instances in every model of that metamodel, and `allInstancesFrom('IN')` selects one
model by name.

Helpers, `thisModule` and `-- @param` parameters work in a query as they do in a
module. In Eclipse ATL the value of a query is returned to the program that launched
it, and the Eclipse launcher discards it; a query that produces text therefore usually
ends with `writeTo`.

## Writing Files

`writeTo(path)` writes a string to a file in UTF-8 and returns `true`, and
`writeToWithCharset(path, charset)` writes it in the named charset. Both replace an
existing file, create missing intermediate directories, and write the string exactly,
without adding a line break. They can be called anywhere a string is available: in a
query, a helper, a binding or a `do` block.

```atl
query Graph =
    ('digraph {\n' + Library!Shelf.allInstances()->iterate(s; text : String = '' |
        text + '  "' + s.name + '";\n') + '}\n').writeTo('library.dot');
```

Because a transformation can come from anywhere, writing files is disabled by default.
Both operations then fail with an ``ATLExecutionError`` until the host enables file
output with an ``ATLFileOutputPolicy``:

- ``ATLFileOutputPolicy/disabled`` (the default) rejects every write.
- ``ATLFileOutputPolicy/confined(to:)`` resolves relative paths against a directory
  and rejects absolute paths and every path that leads outside the directory, whether
  through `..` components or through symbolic links. The error names the path.
  Confinement protects against the transformation itself, not against other processes that can change the output directory while the transformation runs,
  so the output directory should not be writable by untrusted users.
- ``ATLFileOutputPolicy/unrestricted(relativeTo:)`` resolves relative paths against
  a directory and accepts every other path. Use it only for trusted transformations.

```swift
let vm = ATLVirtualMachine(module: query, fileOutput: .confined(to: outputDirectory))
```

Eclipse ATL resolves a relative path against the workspace, or against the working
directory of the Java process when it runs outside Eclipse, and accepts any path.

`writeToWithCharset` accepts `UTF-8`, `UTF-16` (big-endian with a byte order mark, as
Java writes it), `UTF-16BE`, `UTF-16LE`, `UTF-32`, `UTF-32BE`, `UTF-32LE`, `ISO-8859-1`
and `US-ASCII`, matched without regard to case. An unknown charset, or a string that the
charset cannot represent, is reported as an error instead of being written with
substitute characters.

## Best Practices

1. **Keep rules simple**: One rule per concept mapping
2. **Use helpers**: Extract complex logic into reusable helpers
3. **Guard early**: Use guards to filter, not conditional bindings
4. **Name outputs**: Give meaningful names to output pattern elements
5. **Test incrementally**: Verify rules work before adding complexity
6. **Ask for the container**: Prefer `refImmediateComposite()` over threading parents through helper parameters, or adding `eOpposite` references to the metamodel only for the transformation

## Next Steps

- <doc:GettingStarted> - Practical examples
- ``ATLMatchedRule`` - Matched rule API
- ``ATLHelper`` - Helper API
- ``ATLVirtualMachine`` - Execution engine

## See Also

- [Eclipse ATL (Atlas Transformation Language)](https://eclipse.dev/atl/)
- [OMG QVT (Query/View/Transformation)](https://www.omg.org/spec/QVT/)
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/)
