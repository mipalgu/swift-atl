# Incremental Transformations

Keep target models up to date as source models change, without executing the whole
transformation again.

## Overview

An ``ATLIncrementalTransformation`` executes a module as ``ATLVirtualMachine`` does, while
recording what each rule guard, `using` variable and binding reads from the source models
and the trace. It then watches the source models, and each ``ATLIncrementalTransformation/update()``
propagates the changes made since the previous update:

1. Guards whose dependencies changed are evaluated again, and the rules whose source
   element types gained or lost instances are matched again, evaluating the guards of new
   source element tuples only.
2. The target elements of matches that no longer hold are deleted, those of new matches are
   created, and the trace is brought up to date.
3. The `using` variables and bindings whose dependencies changed, including those that
   resolved a source element whose trace changed, are evaluated again and assigned. Cached
   attribute helper values are kept until a change affects what they read.

After every update the target models are exactly as a fresh execution over the changed
source models leaves them, including the order of their root elements and of feature values,
so that their serialised forms are identical.

```swift
let transformation = ATLIncrementalTransformation(module: module, options: .standard)
try await transformation.execute(sources: ["IN": families], targets: ["OUT": persons])
try await families.eSetWithChanges(objectId: member.id, feature: "firstName", value: "Jo")
let report = try await transformation.update()
print(report.bindingsEvaluated)
```

Incremental execution is opt-in: ``ATLVirtualMachine`` behaves exactly as before.

### Bindings on Demand

With ``ATLBindingPropagation/onDemand``, an update only marks the affected bindings as stale.
They are evaluated when ``ATLIncrementalTransformation/value(of:feature:)`` requests the
feature they set, or all at once by ``ATLIncrementalTransformation/materialise()``, in the
manner of the lazy bindings of ReactiveATL.

### What Is Propagated

Changes are propagated for modules made of matched rules, with guards, `using` variables,
bindings, rule inheritance, several source pattern elements, helpers and `resolveTemp`. The
following are kept up to date by executing the module again on each update, as
``ATLIncrementalTransformation/strategy`` reports:

- refining mode, called rules, lazy and unique lazy rules, and `do` sections;
- bindings of references that have an opposite;
- expressions that read elements of a target model or create or change model elements;
- changes that cannot be summarised precisely, such as rebinding an element to another class.

Expressions that call native helpers, and bindings that store a reference to an
untransformed source element, are evaluated again after every change.

## Topics

### Incremental Execution

- ``ATLIncrementalTransformation``
- ``ATLIncrementalStrategy``
- ``ATLBindingPropagation``
- ``ATLIncrementalUpdate``
- ``ATLIncrementalHazard``
