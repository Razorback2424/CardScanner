import SwiftData
import UIKit
import XCTest
@testable import TradingCardScanner

@MainActor
final class ArtworkOrphanSweepTests: XCTestCase {
    func testLegacyTreatmentArtworkMovesOnlyToOneLiveIdentity() throws {
        let container = try makeContainer()
        let canonicalKey = MagicTreatmentKeyCodec.appendCollectionSuffix(
            to: "magic:artwork-alias#foil",
            rawIDs: ["surgefoil"]
        )
        let legacyKey = try XCTUnwrap(
            MagicTreatmentKeyCodec.legacyCollectionKeys(for: canonicalKey).first
        )
        let context = container.mainContext
        context.insert(magicRow(key: canonicalKey, treatment: .surgeFoil))
        context.insert(
            LocalArtworkOverride(
                collectionKey: legacyKey,
                filename: "legacy-artwork.image"
            )
        )
        try context.save()

        let report = try CollectionWriteSerializer.perform(
            container: container,
            timeout: .wait
        ) { context in
            try ArtworkOrphanSweep.run(in: context)
        }

        XCTAssertEqual(report.repairedLegacyAliases, 1)
        let overrides = try container.mainContext.fetch(FetchDescriptor<LocalArtworkOverride>())
        XCTAssertEqual(overrides.map(\.collectionKey), [canonicalKey])
        XCTAssertEqual(overrides.first?.filename, "legacy-artwork.image")
    }

    func testAmbiguousLegacyArtworkAliasIsLeftForReview() throws {
        let container = try makeContainer()
        let baseKey = "magic:ambiguous-artwork#foil"
        let firstKey = MagicTreatmentKeyCodec.appendCollectionSuffix(
            to: baseKey,
            rawIDs: ["surgefoil"]
        )
        let secondKey = MagicTreatmentKeyCodec.appendCollectionSuffix(
            to: baseKey,
            rawIDs: ["gilded"]
        )
        let legacyKey = try XCTUnwrap(
            MagicTreatmentKeyCodec.legacyCollectionKeys(for: firstKey).first
        )
        let now = Date.now
        let context = container.mainContext
        context.insert(magicRow(key: firstKey, treatment: .surgeFoil))
        context.insert(magicRow(key: secondKey, treatment: .gilded))
        context.insert(
            LocalArtworkOverride(
                collectionKey: legacyKey,
                filename: "ambiguous-artwork.image",
                updatedAt: now
            )
        )
        try context.save()

        let report = try CollectionWriteSerializer.perform(
            container: container,
            timeout: .wait
        ) { context in
            try ArtworkOrphanSweep.run(in: context, now: now)
        }

        XCTAssertEqual(report.repairedLegacyAliases, 0)
        XCTAssertEqual(report.removedOverrides, 0)
        let overrides = try container.mainContext.fetch(FetchDescriptor<LocalArtworkOverride>())
        XCTAssertEqual(overrides.map(\.collectionKey), [legacyKey])
    }

    func testDeleteAllThenRestoreKeepsRecentArtwork() throws {
        let container = try makeContainer()
        let filename = try saveArtwork()
        defer { CollectionArtworkStore.remove(filename: filename) }
        let mutation = try CollectionWriteSerializer.perform(
            container: container,
            timeout: .wait
        ) { context in
            try CollectionStore(context: context).add(
                ProductionRowFixtures.pokemonCard(),
                resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
                source: .scan
            )
        }
        try CollectionWriteSerializer.perform(
            container: container,
            timeout: .wait
        ) { context in
            context.insert(
                LocalArtworkOverride(collectionKey: mutation.collectionKey, filename: filename)
            )
            try context.save()
        }

        try CollectionWriteSerializer.perform(
            container: container,
            timeout: .wait
        ) { context in
            XCTAssertTrue(try CollectionStore(context: context).deleteAll())
        }
        _ = try CollectionWriteSerializer.perform(
            container: container,
            timeout: .wait
        ) { context in
            try ArtworkOrphanSweep.run(in: context)
        }

        let removal = try XCTUnwrap(
            container.mainContext.fetch(FetchDescriptor<CollectionActivity>())
                .first { $0.kind == .removed }
        )
        let snapshot = try XCTUnwrap(
            removal.removalSnapshotData.flatMap {
                try? JSONDecoder().decode(RemovedCardSnapshot.self, from: $0)
            }
        )
        try CollectionWriteSerializer.perform(
            container: container,
            timeout: .wait
        ) { context in
            try CollectionStore(context: context).restore(snapshot)
        }

        let override = try XCTUnwrap(
            container.mainContext.fetch(FetchDescriptor<LocalArtworkOverride>())
                .first { $0.collectionKey == mutation.collectionKey }
        )
        XCTAssertEqual(override.filename, filename)
        XCTAssertNotNil(CollectionArtworkStore.image(filename: filename))
    }

    func testCorrectingIntoExistingFinishThenUndoKeepsSourceArtwork() throws {
        let container = try makeContainer()
        let sourceFilename = try saveArtwork()
        let destinationFilename = try saveArtwork()
        defer {
            CollectionArtworkStore.remove(filename: sourceFilename)
            CollectionArtworkStore.remove(filename: destinationFilename)
        }
        let card = try ProductionRowFixtures.pokemonCard()
        let sourceMutation = try CollectionWriteSerializer.perform(
            container: container,
            timeout: .wait
        ) { context in
            try CollectionStore(context: context).add(
                card,
                resolved: ResolvedVariant(variant: .normal, resolution: .userConfirmed),
                source: .scan
            )
        }
        let destinationMutation = try CollectionWriteSerializer.perform(
            container: container,
            timeout: .wait
        ) { context in
            try CollectionStore(context: context).add(
                card,
                resolved: ResolvedVariant(variant: .reverse, resolution: .userConfirmed),
                source: .catalog
            )
        }
        try CollectionWriteSerializer.perform(
            container: container,
            timeout: .wait
        ) { context in
            context.insert(
                LocalArtworkOverride(
                    collectionKey: sourceMutation.collectionKey,
                    filename: sourceFilename
                )
            )
            context.insert(
                LocalArtworkOverride(
                    collectionKey: destinationMutation.collectionKey,
                    filename: destinationFilename
                )
            )
            try context.save()
        }

        let sourceActivityID = try XCTUnwrap(sourceMutation.activityID)
        let correction = try XCTUnwrap(
            try CollectionWriteSerializer.perform(
                container: container,
                timeout: .wait
            ) { context in
                try CollectionStore(context: context).recordVariantCorrection(
                    forCollectionKey: sourceMutation.collectionKey,
                    to: ResolvedVariant(variant: .reverse, resolution: .userConfirmed),
                    activityID: sourceActivityID,
                    quantity: 1
                )
            }
        )
        try CollectionWriteSerializer.perform(
            container: container,
            timeout: .wait
        ) { context in
            try CollectionStore(context: context).undo(correction)
        }

        let readContext = ModelContext(container)
        let overrides = try readContext.fetch(FetchDescriptor<LocalArtworkOverride>())
        XCTAssertEqual(
            Dictionary(uniqueKeysWithValues: overrides.map { ($0.collectionKey, $0.filename) }),
            [
                sourceMutation.collectionKey: sourceFilename,
                destinationMutation.collectionKey: destinationFilename
            ]
        )
        XCTAssertNotNil(CollectionArtworkStore.image(filename: sourceFilename))
        XCTAssertNotNil(CollectionArtworkStore.image(filename: destinationFilename))
    }

    func testSweepRemovesOnlyOldUnreferencedFiles() throws {
        let container = try makeContainer()
        let referencedFilename = try saveArtwork()
        let orphanFilename = try saveArtwork()
        defer {
            CollectionArtworkStore.remove(filename: referencedFilename)
            CollectionArtworkStore.remove(filename: orphanFilename)
        }
        let context = container.mainContext
        context.insert(
            CollectedCard(
                collectionKey: "artwork-file-owner",
                game: .pokemon,
                providerID: "artwork-file-owner",
                name: "Artwork File Owner",
                setName: "Artwork Set",
                setCode: "ART",
                cardNumber: "1",
                rarity: nil,
                imageURL: nil,
                thumbnailURL: nil,
                variant: .normal,
                variantResolution: .userConfirmed
            )
        )
        context.insert(
            LocalArtworkOverride(
                collectionKey: "artwork-file-owner",
                filename: referencedFilename
            )
        )
        try context.save()

        let report = try CollectionWriteSerializer.perform(
            container: container,
            timeout: .wait
        ) { context in
            try ArtworkOrphanSweep.run(
                in: context,
                now: .now.addingTimeInterval(2 * 24 * 60 * 60)
            )
        }

        XCTAssertGreaterThanOrEqual(report.removedFiles, 1)
        XCTAssertNil(CollectionArtworkStore.image(filename: orphanFilename))
        XCTAssertNotNil(CollectionArtworkStore.image(filename: referencedFilename))
    }

    func testLegacyCollectedCardFilenamePreventsOrphanDeletion() throws {
        let container = try makeContainer()
        let filename = try saveArtwork()
        defer { CollectionArtworkStore.remove(filename: filename) }
        let context = container.mainContext
        let card = CollectedCard(
            collectionKey: "legacy-artwork-owner",
            game: .pokemon,
            providerID: "legacy-artwork-owner",
            name: "Legacy Artwork Owner",
            setName: "Artwork Set",
            setCode: "ART",
            cardNumber: "1",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .normal,
            variantResolution: .userConfirmed
        )
        card.userArtworkFilename = filename
        context.insert(card)
        try context.save()

        XCTAssertTrue(CollectionArtworkStore.removeIfUnreferenced(filename, in: context))
        XCTAssertNotNil(CollectionArtworkStore.image(filename: filename))

        card.userArtworkFilename = nil
        try context.save()
        XCTAssertTrue(CollectionArtworkStore.removeIfUnreferenced(filename, in: context))
        XCTAssertNil(CollectionArtworkStore.image(filename: filename))
    }

    func testRollbackInOneContextKeepsAnotherContextsPendingCleanup() throws {
        let container = try makeContainer()
        let aSource = try saveArtwork()
        let aDestination = try saveArtwork()
        let bSource = try saveArtwork()
        let bDestination = try saveArtwork()
        defer {
            [aSource, aDestination, bSource, bDestination]
                .forEach(CollectionArtworkStore.remove(filename:))
        }
        let now = Date.now
        let setup = container.mainContext
        for (key, filename, date) in [
            ("a-source", aSource, now.addingTimeInterval(1)),
            ("a-destination", aDestination, now),
            ("b-source", bSource, now.addingTimeInterval(1)),
            ("b-destination", bDestination, now)
        ] {
            setup.insert(LocalArtworkOverride(collectionKey: key, filename: filename, updatedAt: date))
        }
        try setup.save()

        let contextA = ModelContext(container)
        let contextB = ModelContext(container)
        try LocalArtworkOverrideRekeyer.rekey(
            from: "a-source",
            to: "a-destination",
            in: contextA
        )
        try LocalArtworkOverrideRekeyer.rekey(
            from: "b-source",
            to: "b-destination",
            in: contextB
        )

        contextA.rollback()
        LocalArtworkOverrideRekeyer.discardPendingFilesAfterRollback(in: contextA)
        try contextB.save()
        LocalArtworkOverrideRekeyer.removePendingFilesAfterSave(in: contextB)

        XCTAssertNotNil(CollectionArtworkStore.image(filename: aDestination))
        XCTAssertNil(CollectionArtworkStore.image(filename: bDestination))
        XCTAssertNotNil(CollectionArtworkStore.image(filename: aSource))
        XCTAssertNotNil(CollectionArtworkStore.image(filename: bSource))
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func saveArtwork() throws -> String {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 20, height: 24)).image { renderer in
            UIColor.systemIndigo.setFill()
            renderer.fill(CGRect(x: 0, y: 0, width: 20, height: 24))
        }
        return try XCTUnwrap(CollectionArtworkStore.save(try XCTUnwrap(image.pngData())))
    }

    private func magicRow(key: String, treatment: MagicTreatment) -> CollectedCard {
        CollectedCard(
            collectionKey: key,
            game: .magic,
            providerID: "artwork-alias",
            name: "Artwork Alias",
            setName: "Artwork Set",
            setCode: "ART",
            cardNumber: "1",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .foil,
            variantResolution: .userConfirmed,
            magicTreatments: [treatment]
        )
    }
}
