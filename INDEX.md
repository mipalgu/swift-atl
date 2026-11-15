# Swift ATL

The [swift-atl](https://github.com/mipalgu/swift-atl) package provides
a pure Swift implementation of the
[Atlas Transformation Language (ATL)](https://eclipse.dev/atl/) for
model-to-model transformations.

## Installation

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/mipalgu/swift-atl.git", branch: "main"),
]
```

## Requirements

- Swift 6.0 or later
- macOS 15.0+ or Linux

## References

- [Eclipse ATL (Atlas Transformation Language)](https://eclipse.dev/atl/)
- [OMG QVT (Query/View/Transformation)](https://www.omg.org/spec/QVT/)
- [OMG OCL (Object Constraint Language)](https://www.omg.org/spec/OCL/)
- [Eclipse Modeling Framework (EMF)](https://eclipse.dev/emf/)

## Related Packages

- [swift-ecore](https://mipalgu.github.io/swift-ecore/) - EMF/Ecore metamodelling, OCL, generator models and multi-level modelling ([GitHub](https://github.com/mipalgu/swift-ecore))
- [swift-aql](https://mipalgu.github.io/swift-aql/) - AQL model queries ([GitHub](https://github.com/mipalgu/swift-aql))
- [swift-mtl](https://mipalgu.github.io/swift-mtl/) - MTL model-to-text generation ([GitHub](https://github.com/mipalgu/swift-mtl))
- [swift-henshin](https://mipalgu.github.io/swift-henshin/) - Henshin graph transformation, critical pair analysis and state-space exploration ([GitHub](https://github.com/mipalgu/swift-henshin))
- [swift-epsilon](https://mipalgu.github.io/swift-epsilon/) - Epsilon model management languages (EOL, EVL, ETL and EGL) ([GitHub](https://github.com/mipalgu/swift-epsilon))
- [swift-xtend](https://mipalgu.github.io/swift-xtend/) - Xtend generators and transformations ([GitHub](https://github.com/mipalgu/swift-xtend))
- [swift-modelling](https://mipalgu.github.io/swift-modelling/) - Command-line tools, code generators and tutorials for the whole toolkit ([GitHub](https://github.com/mipalgu/swift-modelling))

## Documentation

The package provides declarative model-to-model transformation capabilities.
For details, see [Getting Started](https://mipalgu.github.io/swift-atl/documentation/atl/gettingstarted) and [Understanding ATL](https://mipalgu.github.io/swift-atl/documentation/atl/understandingatl).

The `swift-atl` command-line tool of [swift-modelling](https://mipalgu.github.io/swift-modelling/)
is described in [swift-atl](https://mipalgu.github.io/swift-modelling/documentation/swift_atl/index.html),
and the [ATL tutorials](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/01-first-transformation/index.html)
introduce it step by step (see all [tutorials](https://mipalgu.github.io/swift-modelling/tutorials/tutorials/index.html)).

- [ATL module documentation](documentation/atl/)

The tutorials include:

- [Creating Your First ATL Transformation](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/01-first-transformation/index.html)
- [ATL Helpers and Guards](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/atl-02-helpers-guards/index.html)
- [Working with Collections](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/atl-03-collections/index.html)
- [Advanced Rule Patterns](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/atl-04-advanced-rules/index.html)
- [OCL Expressions Deep Dive](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/atl-05-ocl-expressions/index.html)
- [Debugging Transformations](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/atl-06-debugging/index.html)
- [Complex Model Transformations](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/atl-07-complex-transformations/index.html)
- [Performance Optimisation](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/atl-08-performance/index.html)

Advanced ATL transformations:

- [Class to Relational Transformation](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/atl-advanced-01-class2relational/index.html)
- [Container Navigation and Reflection in ATL](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/atl-advanced-02-container-navigation/index.html)

Related chapters:

- [From Ecore to a Generator Model](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/java-01-ecore-to-genmodel/index.html)
- [From a Generator Model to Java](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/java-02-genmodel-to-java/index.html)
- [Multi-Level Modelling with Potency](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/multilevel-01-deep-modelling/index.html)
- [Reusing Modules with Model Typing](https://mipalgu.github.io/swift-modelling/tutorials/swiftmodelling/typing-01-check-compat/index.html)
