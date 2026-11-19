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
its input models, as described under Queries below. A module whose header declares its
source models after `refining` instead of `from` changes copies of its source models,
as described under Refining Mode below.

### Binding Metamodels

A metamodel named in the module header is bound, in order of precedence, by:

1. a `-- @nsURI Name=http://example.org/model` directive, resolved through the
   ``ATLMetamodelRegistry`` that the parser receives,
2. a `-- @path Name=Name.ecore` directive, as described under Metamodel Paths below,
3. a lookup of the name in the registry, which ignores letter case when only one
   package matches.

```swift
let registry = ATLMetamodelRegistry(packages: [ecorePackage, genModelPackage])
let module = try await ATLParser(options: .standard).parse(url, metamodelRegistry: registry)
```

A registry can also be built from a table of namespace URIs, or given a resolver closure
for namespace URIs that it does not hold. Type references such as `Ecore!EClass` use the
name from the module header, which need not equal the name of the bound package.

### Metamodel Paths

A `-- @path Name=Name.ecore` directive in the header names the file of a metamodel. A
relative path is resolved against the directory of the transformation and then against
each search directory that the parser receives. A path that starts with `/` names a file
in an Eclipse workspace, such as `/Families2Persons/Families.ecore` for `Families.ecore`
in the project `Families2Persons`. It is looked up in each search directory, first as
`Families2Persons/Families.ecore`, with the search directory as the workspace, and then
as `Families.ecore`, with the search directory as the project directory itself. A
transformation copied from an Eclipse project therefore finds its metamodels both in a
copy of the workspace and in a copy of the project directory.

### Module Parameters

Header comments declare parameters of type `String`, `Integer`, `Boolean` or `Real`. A
parameter without a default value is required:

```atl
-- @param basePackage : String = 'org.example'
-- @param generateTests : Boolean = false
-- @param projectName : String
```

The caller supplies the values when executing the module, and the transformation reads
them as `thisModule.projectName`:

```swift
try await ATLVirtualMachine(module: module, options: .standard).execute(
    sources: ["IN": input], targets: ["OUT": output],
    parameters: ["projectName": "demo", "generateTests": true])
```

A missing required parameter, an undeclared parameter or a value of the wrong type is
reported as an ``ATLExecutionError``. ``ATLModule/parameterValues(fromText:)`` converts
textual values, for example from a command line, to the declared types.

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

A source element, or a tuple of source elements matched by a rule with several source
pattern elements, is transformed by at most one matched rule, because references to it
resolve to the target elements of that rule. As in Eclipse ATL, two matched rules that
make the same match stop the run with an ``ATLExecutionError/invalidOperation(_:)`` that
names both rules and the elements, before any rule creates a target element:

- Two rules with one source pattern element make the same match when they match the same
  element, whatever their variables are called.
- Two rules with several source pattern elements make the same match when they bind the
  same elements to the same variables, in whatever order they declare the variables. Rules
  that bind the same elements to different variables do not conflict, even when they
  declare them in the same order, and the error names each element with its variable.
- A rule with one source pattern element and a rule with several never make the same
  match, even when they share an element.

```atl
rule Assignment {
    from t : Plan!Task, p : Plan!Person (t.owner = p)
    to a : Report!Assignment
}
-- Conflicts with Assignment: it binds the same elements to t and p
rule Responsibility {
    from p : Plan!Person, t : Plan!Task (t.owner = p)
    to r : Report!Responsibility
}
```

A rule and a rule that extends it transform a match they both make once, through one of
them, and two rules that extend the same rule are applied one at a time, as Rule
Inheritance below describes. Rules whose guards select different elements, or that
match an element together with different other elements, do not conflict. This holds
under both ``ATLOptions/standard`` and ``ATLOptions/legacy``, in refining mode and in
incremental updates.

### Rule Inheritance

A matched rule can extend another with `extends`. It inherits the target patterns and
bindings of the rule it extends, redeclares target patterns of the same name to change
their type or override bindings, and adds its own guard, which applies together with the
guards of the rules it extends. An `abstract` rule matches nothing on its own.

```atl
abstract rule Member2Person {
    from s : Families!Member
    to t : Persons!Person (fullName <- s.firstName + ' ' + s.familyName)
}
rule Member2Female extends Member2Person {
    from s : Families!Member (s.isFemale())
    to t : Persons!Female
}
rule Member2Male extends Member2Person {
    from s : Families!Member (not s.isFemale())
    to t : Persons!Male
}
```

A rule that extends another declares the same source pattern variables, as in Eclipse
ATL, and each of its variables stands for the variable of the same name of the rule it
extends, in whatever order the two rules declare them; each rule sees the matched
elements under its own variable names. The type of each variable must be the type of the
variable it stands for or a subtype of it; every class is a subtype of `EObject`, so a
rule on any class can extend a rule on `EObject`. A rule that declares fewer or more source
pattern elements than the rule it extends stops the run with an
``ATLExecutionError/invalidOperation(_:)``, and a variable whose type does not conform
with an ``ATLExecutionError/typeError(_:)``; both name the two rules and the variable.

When a rule and rules that extend it match an element, or bind the same tuple of elements
to the same variables, one of them transforms it. By default, the rules are tried as in
Eclipse ATL. For a rule that matches the element, the rules extending it that have a guard
are tried first, then the rule itself if it has a guard, then the rules extending it that
have none, and last the rule itself if it has none, each group in declaration order; an
abstract rule is never itself applied. The first of them that matches transforms the
element, and when that is a rule extending the other, the rules extending it are tried in
turn in the same way. A rule with a guard therefore transforms every element that it
matches in place of the rules extending it that have no guard:

```atl
rule Task2Urgent {
    from s : Project!Task (s.priority > 5)
    to t : Report!Summary (title <- s.name, rank <- 1)
}
-- Never applied by default: Task2Urgent matches every task that this rule matches
rule Task2Plain extends Task2Urgent {
    from s : Project!Task
    to t : Report!Summary (rank <- 0)
}
```

With ``ATLSubRulePrecedence/extendingRule`` for ``ATLOptions/subRulePrecedence``, which
``ATLOptions/legacy`` selects, a rule that extends another always takes precedence over it
instead, as in swift-atl 0.6, so `Task2Plain` transforms the urgent tasks above. A rule
then transforms an element only when none of the rules extending it match, and of several
rules extending it that match, the first in the order above applies.

```swift
var options = ATLOptions.standard
options.subRulePrecedence = .extendingRule
let machine = ATLVirtualMachine(module: module, options: options)
```

When several rules that extend the same rule match an element and are tried before the
rule itself, the first of them transforms it, and the run reports a warning that names
the element, the rule they extend and the rules that match, and says which of them is
applied. The warning is written to standard error and recorded in
``ATLExecutionStatistics/warnings``. Had `Member2Male` no guard, a female member would
match both rules and be transformed by `Member2Female`, with a warning. With
``ATLSiblingRuleConflicts/error`` for ``ATLOptions/siblingRuleConflicts``, such rules
instead stop the run with the ``ATLExecutionError/invalidOperation(_:)`` that two
unrelated rules matching the same element give; both presets report a warning.

```swift
var options = ATLOptions.standard
options.siblingRuleConflicts = .error
let machine = ATLVirtualMachine(module: module, options: options)
```

Under ``ATLSubRulePrecedence/eclipse``, the rules without a guard that extend a matching
rule with one are never tried, so they give neither a warning nor an error;
under ``ATLSubRulePrecedence/extendingRule``, they do.

Rule inheritance differs from Eclipse ATL in three respects:

- A rule may extend a rule whose variables have other names, provided it declares as many;
  the variables whose names the two rules do not share stand for each other in
  declaration order. Eclipse ATL requires the same names.
- With ``ATLSubRulePrecedence/extendingRule``, a rule that extends another always takes
  precedence over it for an element they both match. Eclipse ATL tries a rule that has a
  guard and is not abstract before the rules extending it that have none, as
  ``ATLSubRulePrecedence/eclipse`` does.
- When an abstract rule that extends another matches an element but none of the rules
  extending it do, the next rule in order is tried. Eclipse ATL leaves such an element
  untransformed.

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

A rule with several source pattern elements is identified by a tuple that binds each of
its source pattern variables to an element, as in Eclipse ATL:

```atl
rule Assignment {
    from t : Plan!Task, p : Plan!Person (t.owner = p)
    to a : Report!Assignment, n : Report!Note
}

note <- thisModule.resolveTemp(Tuple{t = task, p = person}, 'n')
assignment <- Tuple{p = person, t = task}   -- the default target element, a
```

The parts of the tuple are matched to the variables by name, in any order, and a tuple
that identifies no match is an error. A Sequence of the elements, listed in the order in
which the rule declares its source pattern elements, is also accepted by `resolveTemp`;
when several rules bind the same elements in that order to different variables, it finds
the first of them that has a target pattern of that name.

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

### Dispatch and Evaluation

Contextual helpers are identified by their context type and name. A call dispatches on the
dynamic type of the receiver, and the most specific context type wins, so
`helper context A def : f()` and `helper context B def : f()` can coexist. A helper whose
context is `EObject` applies to every model object, but every helper whose context is the
receiver's class or one of its declared supertypes is more specific, and it is in turn more
specific than a helper on `OclAny`. A helper
declared without a parameter list (`def : name : Type = ...`) is an attribute whose value
is computed once per receiver. A host application can add helpers written in Swift; see
``ATLNativeHelper``.

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

A containment reference holds only elements of target models. A source element that no
matched rule transforms is therefore left out of the value assigned to a containment
reference, as Eclipse ATL leaves it out, and the run reports a warning that names the
element, the reference and its class. The warning is written to standard error, as
`debug` writes its text, and recorded in ``ATLExecutionStatistics/warnings``. A
non-containment reference keeps such an element as a reference into its source model.
Such a reference into a source model in another resource set is written as EMF writes
it: the only root of a model as `/` and the elements below it as `//@tasks.0`, and root
`n` of a model with several roots as `/n` and the elements below it as `/n/@tasks.0`.

An attribute typed by a primitive Ecore type accepts only values of that type, as the
Eclipse Modeling Framework does: an Integer for `EInt`, `ELong`, `EShort`, `EByte` and
`EBigInteger`, a Real or an Integer for `EDouble`, `EFloat` and `EBigDecimal`, a Boolean
for `EBoolean` and a String for `EString`, together with their object types. Any other
value stops the run with a ``ATLExecutionError/typeError(_:)`` that names the attribute,
its class, its type and the type of the value. Because `/` gives a Real, the quotient
`(done * 100) / total` cannot be bound to an `EInt` attribute, even when it happens to be
integral; `(done * 100) div total` or `((done * 100) / total).round()` gives an Integer.
Integers bound to `EDouble` and `EFloat` attributes become Reals.

Because every matched rule creates its target elements before any binding is applied,
the order of the rules never matters for references. Abstract rules, rule inheritance
with `extends`, `unique lazy` rules, `entrypoint` and `endpoint` rules, `using`
variables, several source pattern elements and imperative `do` statements are all
supported.

### Reading Unset Features

Reading an attribute that the model leaves unset gives the default value of the feature,
as `eGet` does in the Eclipse Modeling Framework: the declared default, otherwise
`false`, `0` or `0.0`. Unset strings and references read as `OclUndefined`. A guard such
as `not c.isAbstract` therefore holds for an element whose XMI omits the attribute. A
virtual machine created with `unsetFeatureReads: .undefined` instead reads every unset
feature as `OclUndefined`, which is not standard behaviour.

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
c.package.classes.name           -- The name of each class
```

An operation called on a collection, with `.` or `->`, is the collection's own operation, so
`classes.size()` and `classes->size()` both count the classes. Navigating a feature of a
collection, as in `c.package.classes.name`, collects the feature of each element into the
collection kind that `collect` gives: a Bag for a Set or a Bag, and a Sequence for a
Sequence or an OrderedSet (always a Sequence with the ``ATLBagRepresentation/sequence`` of
``ATLOptions/bagRepresentation``). Eclipse ATL reports this as an error. An attribute
helper defined for the collection itself, with a context such as `Sequence(UML!Class)`,
`Bag(UML!Class)`, `Collection(UML!Class)` or `OclAny`, is used first, as in ATL. A helper
for a collection kind applies only to collections of that kind, so one for `Sequence(T)`
does not apply to a Bag; one for `Collection(T)` applies to every kind, and the most
specific context wins.

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

### Literals and Operators

- Strings support the escapes `\'`, `\"`, `\\`, `\n`, `\r`, `\t`, `\b`, `\f`, `\uXXXX`
  and octal escapes. Any other backslash sequence is kept as written, so regular
  expressions such as `'\s+'` need no doubling.
- Real literals (`3.14`, `1e-3`), enumeration literals (`#Editable`) and `OclUndefined`
  (or `null`) are supported. An enumeration literal evaluates to the name of the literal,
  which is how enumeration-typed attributes of dynamic objects are stored. Binding it to an
  attribute checks that the enumeration declares the literal.
- `Sequence{}`, `OrderedSet{}`, `Set{}` and `Bag{}` literals keep their elements. Sets
  and ordered sets remain free of duplicates through `union`, `including`, `append` and
  similar operations. A Bag keeps its duplicates and is a collection kind of its own, as
  in OCL and the Eclipse ATL EMFTVM: `asBag()`, `collect` on a Set or a Bag, the `union`
  of a Set or an OrderedSet with a Bag, and navigating a feature over a Set or a Bag give
  Bags, and two Bags are equal when they hold each element equally often, in any order.
  ``ATLOptions/bagRepresentation`` selects the Sequences of swift-atl 0.6 instead.
- Collection literals accept OCL integer ranges `first..last`, alone or mixed with items:
  `Sequence{0, 2..4, 9}` holds `0, 2, 3, 4, 9`. Both bounds may be expressions but must
  be Integers. A range whose first value exceeds its last is empty, and sets keep each
  integer once. Eclipse ATL does not accept ranges; see the Compatibility section of
  <doc:ATL>.
- `Tuple{name = 'a', size = 3}` creates a tuple, whose parts are read by name, as in
  `t.name`, and may be undefined. A part may carry a type, as in `Tuple{name : String =
  'a'}`. Tuples are equal when they have parts of the same names with equal values, in any
  order. They can be held in collections, bound to variables, and passed to and returned
  from helpers, whose parameters and contexts declare them as `TupleType(name : String,
  size : Integer)`. Their type is `Tuple`, and `toString()`, `debug` and query results write
  them as Eclipse ATL does, with the parts in the order in which they were written:
  `Tuple {name = 'a', size = 3}`. Reading a part that a tuple does not have is an error.
- `implies`, `xor`, `div` and `mod` are infix operators with OCL precedence: `implies`
  binds weakest, then `or` and `xor`, then `and`. Logical operators use three-valued
  logic with `OclUndefined`.
- `/` divides as OCL and Eclipse ATL do: the quotient is a Real even for two Integers, so
  `7 / 2` is `3.5` and `8 / 2` is `4.0`. ``ATLOptions/integerDivision`` selects the
  truncating division of swift-atl 0.6 instead. `div` and `mod` take Integers: `div`
  truncates the quotient towards zero and `mod` gives the remainder with the sign of the
  dividend, so `-7 div 2` is `-3` and `-7 mod 2` is `-1`. Dividing by zero is an error.

### Built-in Operations

Positions in collections and strings are 1-based. A single value behaves as a collection
of one element.

- **Collections**: `any`, `count`, `sum`, `at`, `append`, `prepend`, `insertAt`,
  `subSequence`, `subOrderedSet`, `including`, `includingAll`, `includingRange`,
  `excluding`, `excludingAll`, `union`, `intersection`, `symmetricDifference`,
  `indexOf`, `lastIndexOf`, `includesAll`, `excludesAll`, `isUnique`, `one`, `exists`
  and `forAll` (with several iterator variables), `sortedBy`, `collect`, `collectNested`,
  `flatten`, `reverse`, `max`, `min`, and the conversions `asSet`, `asOrderedSet`,
  `asSequence` and `asBag`. `collect` flattens the collections that its body yields by one
  level, whereas `collectNested` keeps them, so `Sequence{1, 2}->collectNested(x |
  Sequence{x, x})` is `Sequence{Sequence{1, 1}, Sequence{2, 2}}`; both give a Bag for a Set
  or a Bag and a Sequence otherwise. An iterator operation that does not exist is reported
  as unknown. `toString()` writes a collection as a collection literal, such as
  `Sequence{30, 10}`, as `debug` and query results write it, and a tuple as
  `Tuple {a = 1}`.
  `at` applies to Sequences and OrderedSets only and is an error on a Set or a Bag.
  `asSet()` and `asOrderedSet()` give a Set and an OrderedSet for every receiver, except
  that with ``ATLBagRepresentation/sequence`` `asSet()` on a Sequence gives a Sequence
  without duplicates, as in swift-atl 0.6.
  `first()` and `last()` return `OclUndefined` for an empty collection.
- **Strings**: `concat`, `substring`, `toInteger`, `toReal`, `toUpper`, `toLower`,
  `toSequence`, `trim`, `startsWith`, `endsWith`, `indexOf`, `lastIndexOf`, `split`,
  `replaceAll` and `regexReplaceAll`. `println()` prints the string to standard output,
  and `writeTo` and `writeToWithCharset` write it to a file, as described under Writing
  Files below.
- **Numbers**: the method form `div(n)`, `longValue()`, and the Real functions `sqrt`,
  `exp`, `log`, `sin`, `cos`, `tan`, `asin`, `acos`, `atan`, `toDegrees` and
  `toRadians`.
- **Types**: `oclIsKindOf` and `oclIsTypeOf` (over the complete supertype closure),
  `oclAsType`, `oclType`, `oclIsUndefined`, `MM!Class.allInstances()` and
  `MM!Class.allInstancesFrom('IN')`. As in EMF, every model object is an `EObject`:
  `oclIsKindOf(ECORE!EObject)` holds for every model object, while `oclIsTypeOf` holds only
  for an object whose class is `EObject` itself. Where a metamodel names `EObject`, such
  as Ecore's own, `allInstances()` of it lists every object of the model.
- **Reflection**: the operations described under Reflection and Containment below.

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

## Refining Mode

A refining transformation changes a few elements of a model and keeps the rest. Its
header declares the source models after `refining` instead of `from`, and each target
model conforms to the metamodel of the source model in the same position:

```atl
module RenameNodes;
create OUT : Graph refining IN : Graph;

rule Rename {
    from s : Graph!Node (s.name = 'a')
    to   t : Graph!Node (name <- 'A')
}
```

``ATLModule/refining(_:)`` selects the same mode for a module whose header uses `from`:

```swift
try await ATLVirtualMachine(module: module.refining(), options: .standard).execute(
    sources: ["IN": input], targets: ["OUT": output])
```

The transformation behaves like the in-place refining mode of Eclipse ATL:

- Each target model starts as a copy of its source model. Elements that no rule matches
  keep their attribute values and their references, which point to the copies.
- The first target pattern whose type is the type of the first source pattern denotes the
  matched element itself. Its bound features take their new values and its other features
  keep theirs. A binding replaces the whole value of its feature.
- Other target patterns, lazy rules and called rules create new elements.
- Rules match, and expressions navigate, the unchanged source models, which the
  transformation never modifies. A source element in a bound value resolves to the first
  target element of the matched rule that transformed it, and otherwise to its copy.

### Deleting Elements

A matched rule deletes the element it matches when its `to` section starts with `drop`,
as the ATL 2010 compiler of Eclipse ATL allows. Target patterns may follow `drop`; they
create new elements:

```atl
rule RemoveEmpty {
    from s : Graph!Node (s.weight = 0)
    to drop
}

rule Replace {
    from s : Graph!Node (s.name = 'old')
    to drop
       n : Graph!Node (name <- 'new')
}
```

- Deletion happens last, after every rule, lazy binding and endpoint rule has run. The
  elements that a dropped element contains at that point are deleted with it, so an
  element that another rule has moved to a new container survives.
- References from the remaining elements to the deleted elements are removed: a
  single-valued reference is unset, and a many-valued reference loses the deleted
  elements, which also clears both ends of opposite references. Eclipse ATL leaves such
  references dangling, which the Eclipse Modeling Framework refuses to save by default.
- A reference to the dropped source element in a bound value resolves to the first target
  pattern after `drop`, or, without any, to the copy that is deleted.
- `drop` needs refining mode, and the rule must be a matched rule with one source pattern
  element that is neither abstract nor part of a rule hierarchy. Otherwise the parser or
  the virtual machine rejects it.

Only instances of dynamic classes can be copied, so a model
holding metamodel elements, such as an Ecore package, cannot be refined. As in other
modules, rules match the elements of the first model of each metamodel, so further source
models of the same metamodel are copied unchanged.

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
let vm = ATLVirtualMachine(module: query, options: .standard)
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
let vm = ATLVirtualMachine(module: query, options: .standard, fileOutput: .confined(to: outputDirectory))
```

Eclipse ATL resolves a relative path against the workspace, or against the working
directory of the Java process when it runs outside Eclipse, and accepts any path.

`writeToWithCharset` accepts `UTF-8`, `UTF-16` (big-endian with a byte order mark, as
Java writes it), `UTF-16BE`, `UTF-16LE`, `UTF-32`, `UTF-32BE`, `UTF-32LE`, `ISO-8859-1`
and `US-ASCII`, matched without regard to case, and also `windows-1252` and the other names
and aliases of the encodings that the modelling tools read, such as `cp1252`. An unknown
charset, or a string that the
charset cannot represent, is reported as an error instead of being written with
substitute characters.

`writeTo` writes UTF-8 unless the host names another encoding with
``ATLFileOutputPolicy/defaultEncoding``, such as `windows-1252`. A string with a
character that this encoding cannot hold is not written; the error names the file and
the line and column of the character in the string.

```swift
var policy = ATLFileOutputPolicy.confined(to: outputDirectory)
policy.defaultEncoding = .isoLatin1
```

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
- [ATL Helpers and Guards](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/atl-02-helpers-guards/index.html) and the other ATL tutorials of swift-modelling
- [swift-atl](https://mipalgu.github.io/swift-modelling/documentation/swift_atl/index.html) - The command-line tool

## Related Documentation

- [swift-atl](https://mipalgu.github.io/swift-modelling/documentation/swift_atl/index.html): the `swift-atl` command-line tool of swift-modelling
- [Creating Your First ATL Transformation](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/01-first-transformation/index.html), [Class to Relational Transformation](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/atl-advanced-01-class2relational/index.html) and the [tutorials index](https://mipalgu.github.io/swift-modelling/tutorials/tutorials/index.html)
- [From Ecore to a Generator Model](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/java-01-ecore-to-genmodel/index.html), [Multi-Level Modelling with Potency](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/multilevel-01-deep-modelling/index.html) and [Reusing Modules with Model Typing](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/typing-01-check-compat/index.html)
- [swift-ecore](https://mipalgu.github.io/swift-ecore/), [swift-aql](https://mipalgu.github.io/swift-aql/), [swift-mtl](https://mipalgu.github.io/swift-mtl/), [swift-henshin](https://mipalgu.github.io/swift-henshin/), [swift-epsilon](https://mipalgu.github.io/swift-epsilon/documentation/etl/) and [swift-modelling](https://mipalgu.github.io/swift-modelling/)

### Standards

- [Eclipse ATL (Atlas Transformation Language)](https://eclipse.dev/atl/)
- [OMG QVT (Query/View/Transformation)](https://www.omg.org/spec/QVT/)
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/)
