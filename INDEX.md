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

- [swift-ecore](https://github.com/mipalgu/swift-ecore) - EMF/Ecore metamodelling
- [swift-mtl](https://github.com/mipalgu/swift-mtl) - MTL code generation
- [swift-aql](https://github.com/mipalgu/swift-aql) - AQL model queries
- [swift-modelling](https://github.com/mipalgu/swift-modelling) - Unified MDE toolkit

## Documentation

The package provides declarative model-to-model transformation capabilities.
For details, see [Getting Started](https://mipalgu.github.io/swift-atl/documentation/atl/gettingstarted) and [Understanding ATL](https://mipalgu.github.io/swift-atl/documentation/atl/understandingatl).
