# Understanding ATL

Learn the fundamental concepts of the Atlas Transformation Language.

## Overview

[ATL (Atlas Transformation Language)](https://eclipse.dev/atl/) is a model transformation
language that allows you to declaratively specify how elements in a source model should
be transformed into elements in a target model.

ATL is related to the [OMG QVT (Query/View/Transformation)](https://www.omg.org/spec/QVT/)
standard and uses [OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/)
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

## Best Practices

1. **Keep rules simple**: One rule per concept mapping
2. **Use helpers**: Extract complex logic into reusable helpers
3. **Guard early**: Use guards to filter, not conditional bindings
4. **Name outputs**: Give meaningful names to output pattern elements
5. **Test incrementally**: Verify rules work before adding complexity

## Next Steps

- <doc:GettingStarted> - Practical examples
- ``ATLMatchedRule`` - Matched rule API
- ``ATLHelper`` - Helper API
- ``ATLVirtualMachine`` - Execution engine

## See Also

- [Eclipse ATL (Atlas Transformation Language)](https://eclipse.dev/atl/)
- [OMG QVT (Query/View/Transformation)](https://www.omg.org/spec/QVT/)
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/)
