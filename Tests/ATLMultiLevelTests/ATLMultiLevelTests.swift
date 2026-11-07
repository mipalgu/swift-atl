//
//  ATLMultiLevelTests.swift
//  ATLMultiLevelTests
//
//  Copyright © 2026 Rene Hexel. All rights reserved.
//
import ECore
import EMFBase
import Foundation
import MultiLevel
import Testing

@testable import ATL

/// Multi-level models for the ATL tests.
enum DeepFixtures {
    /// An arcade game language with leap potency and a deep reference.
    static let arcade = """
        Model Arcade@2 {
          Node Tile@(2) {
            next : Tile[*];
            elements : ElementKind@0[*];
          }
          abstract Node ElementKind {}
          abstract Node CharacterKind : ElementKind {}
          Node HeroKind : CharacterKind {
            initLives@1 : int = 3;
            lives : int = 3;
          }
          Node EvilKind : CharacterKind {}
          Node TreasureKind : ElementKind {}
        }

        Arcade Maze {
          TreasureKind Coin {
            value : int = 10;
          }
          HeroKind Muncher {
            initLives = 5;
          }
          EvilKind Phantom {}
        }

        Maze Play {
          Tile t0 {
            next = [t1];
            elements = [c0, m];
          }
          Tile t1 {
            next = [t0];
            elements = [p];
          }
          Muncher m {}
          Phantom p {}
          Coin c0 {}
        }
        """

    /// Product types, products and individual items over three levels.
    static let products = """
        Model Commerce@2 {
          Node ProductType {
            vat@1 : double = 7.5;
            price : double = 10.0;
          }
        }

        Commerce BookStore {
          ProductType Book {
            vat = 4.0;
          }
          ProductType Disc {
            vat = 10.0;
          }
        }

        BookStore Shop {
          Book patterns {
            price = 35.0;
          }
          Disc album {
            price = 20.0;
          }
          Book draft {}
        }
        """

    /// A warehouse language whose bottom level is empty, to be filled by a transformation.
    static let warehouse = """
        Model Trade@2 {
          Node ProductType {
            price : double = 1.0;
          }
        }

        Trade Warehouse {
          ProductType Item {
            label : String;
          }
        }

        Warehouse Stock {}
        """

    /// Reads a fixture that must have no errors.
    static func model(_ text: String) throws -> DeepModel {
        let result = MetaDepthReader.parse(text)
        #expect(!result.hasErrors, "\(result.diagnostics.map(\.message))")
        return try #require(result.model)
    }

    /// A target metamodel of places and tokens.
    static func net() -> (package: EPackage, place: EClass, token: EClass) {
        let string = EcorePackage.dataType(.eString) ?? EDataType(name: "EString")
        let integer = EcorePackage.dataType(.eInt) ?? EDataType(name: "EInt")
        let token = EClass(
            name: "Token",
            eStructuralFeatures: [EAttribute(name: "kind", eType: string), EAttribute(name: "lives", eType: integer)])
        let place = EClass(
            name: "Place",
            eStructuralFeatures: [
                EAttribute(name: "size", eType: integer), EReference(name: "tokens", eType: token, upperBound: -1),
            ])
        return (EPackage(name: "Net", nsURI: "http://example.org/net", nsPrefix: "net", eClassifiers: [place, token]), place, token)
    }
}

/// Tests deep transformations: ATL rules defined against upper-level types, applied to the
/// deep level view of a lower level, without changes to the ATL engine.
@Suite("ATL deep transformations")
@MainActor
struct ATLDeepTransformationTests {
    @Test("rules for level-2 types match all their deep instances at level 0")
    func deepSourceMatching() async throws {
        let model = try DeepFixtures.model(DeepFixtures.arcade)
        let view = try await model.deepLevelView(atLevel: 0)
        #expect(view.package.name == "Maze")
        let (net, place, token) = DeepFixtures.net()
        let source = """
            module Arcade2Net;
            create OUT : Net from IN : Maze;

            helper context Maze!Tile def : characters : Sequence(Maze!CharacterKind) =
                self.elements->select(e | e.oclIsKindOf(Maze!CharacterKind));

            rule TileToPlace {
                from t : Maze!Tile
                to p : Net!Place (
                    size <- t.elements->size(),
                    tokens <- t.characters
                )
            }

            rule CharacterToToken {
                from c : Maze!CharacterKind
                to k : Net!Token (
                    kind <- if c.oclIsKindOf(Maze!HeroKind) then 'hero' else 'evil' endif
                )
            }
            """
        let module = try await ATLParser().parseContent(
            source, filename: "Arcade2Net.atl", continueAfterErrors: false,
            metamodelRegistry: ATLMetamodelRegistry(packages: [view.package, net]))
        let output = Resource(uri: "memory:net")
        try await ATLVirtualMachine(module: module, options: .standard)
            .execute(sources: ["IN": view.resource], targets: ["OUT": output])
        let places = await output.getAllInstancesOf(place).compactMap { $0 as? DynamicEObject }
        let tokens = await output.getAllInstancesOf(token).compactMap { $0 as? DynamicEObject }
        #expect(places.count == 2)
        #expect(Set(tokens.compactMap { $0.eGet("kind") as? String }) == ["hero", "evil"])
        #expect(places.compactMap { $0.eGet("size") as? Int }.sorted() == [1, 2])
        let tokenCounts = places.map { AQLLikeCount.count($0.eGet("tokens")) }
        #expect(tokenCounts.sorted() == [1, 1])
    }

    @Test("helpers read slots, defaults and type-level slots of deep instances")
    func deepNavigation() async throws {
        let model = try DeepFixtures.model(DeepFixtures.arcade)
        let view = try await model.deepLevelView(atLevel: 0)
        let (net, _, token) = DeepFixtures.net()
        let source = """
            module Heroes;
            create OUT : Net from IN : Maze;
            rule HeroToToken {
                from h : Maze!HeroKind
                to k : Net!Token (kind <- 'hero', lives <- h.initLives + h.lives)
            }
            """
        let module = try await ATLParser().parseContent(
            source, continueAfterErrors: false, metamodelRegistry: ATLMetamodelRegistry(packages: [view.package, net]))
        let output = Resource(uri: "memory:heroes")
        try await ATLVirtualMachine(module: module, options: .standard)
            .execute(sources: ["IN": view.resource], targets: ["OUT": output])
        let made = await output.getAllInstancesOf(token).compactMap { $0 as? DynamicEObject }
        #expect(made.compactMap { $0.eGet("lives") as? Int } == [8])
    }

    @Test("a writable level-pair view is an ordinary target whose objects commit to the deep model")
    func pairViewTarget() async throws {
        let products = try DeepFixtures.model(DeepFixtures.products)
        let source = try await products.deepLevelView(atLevel: 0)
        let warehouse = try DeepFixtures.model(DeepFixtures.warehouse)
        let target = try await warehouse.levelPairView(atLevel: 0)
        #expect(source.package.name == "BookStore" && target.package.name == "Warehouse")
        let transformation = """
            module Restock;
            create OUT : Warehouse from IN : BookStore;
            rule ProductToItem {
                from p : BookStore!ProductType
                to i : Warehouse!Item (price <- p.price * 2.0, label <- p.oclType().name)
            }
            """
        let module = try await ATLParser().parseContent(
            transformation, continueAfterErrors: false,
            metamodelRegistry: ATLMetamodelRegistry(packages: [source.package, target.package]))
        try await ATLVirtualMachine(module: module, options: .standard)
            .execute(sources: ["IN": source.resource], targets: ["OUT": target.resource])
        let committed = await target.committed()
        let items = try #require(committed.levelModel(atLevel: 0)?.clabjects)
        #expect(items.count == 3)
        #expect(items.allSatisfy { $0.type == committed.clabject(named: "Item")?.id })
        #expect(Set(items.compactMap { committed.values(of: "price", at: $0.id)?.first }) == [.real(70), .real(40), .real(20)])
        #expect(Set(items.compactMap { committed.values(of: "label", at: $0.id)?.first }) == [.string("Book"), .string("Disc")])
        #expect(committed.validateStructure().isEmpty)
        #expect(MetaDepthWriter.write(committed).text.contains("  Item \(MultiLevelSyntax.anonymousPrefix)"))
    }
}

/// Counts the elements of a reference value.
enum AQLLikeCount {
    static func count(_ value: (any EcoreValue)?) -> Int {
        switch value {
        case nil: return 0
        case let ids as [EUUID]: return ids.count
        case let array as EcoreValueArray: return array.values.count
        case let values as [any EcoreValue]: return values.count
        default: return 1
        }
    }
}
