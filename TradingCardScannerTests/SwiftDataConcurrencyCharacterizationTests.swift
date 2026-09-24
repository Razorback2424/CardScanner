import Foundation
import SwiftData
import XCTest
@testable import TradingCardScanner

@MainActor
final class SwiftDataConcurrencyCharacterizationTests: XCTestCase {
    func testDifferentPropertiesChangedInTwoContexts() throws {
        let container = try makeContainer()
        try insertCard(in: container.mainContext, key: "different-properties")

        let first = ModelContext(container)
        let second = ModelContext(container)
        let firstCard = try XCTUnwrap(card("different-properties", in: first))
        let secondCard = try XCTUnwrap(card("different-properties", in: second))
        firstCard.name = "First context name"
        secondCard.setName = "Second context set"

        try first.save()
        try second.save()

        let verification = ModelContext(container)
        let stored = try XCTUnwrap(card("different-properties", in: verification))
        // The second save writes its stale full snapshot and loses the first
        // context's change to a different property.
        XCTAssertEqual(stored.name, "Test Card")
        XCTAssertEqual(stored.setName, "Second context set")
    }

    func testSamePropertyChangedInTwoContexts() throws {
        let container = try makeContainer()
        try insertCard(in: container.mainContext, key: "same-property")

        let first = ModelContext(container)
        let second = ModelContext(container)
        let firstCard = try XCTUnwrap(card("same-property", in: first))
        let secondCard = try XCTUnwrap(card("same-property", in: second))
        firstCard.name = "First context name"
        secondCard.name = "Second context name"

        try first.save()
        try second.save()

        let verification = ModelContext(container)
        let stored = try XCTUnwrap(card("same-property", in: verification))
        XCTAssertEqual(stored.name, "Second context name")
    }

    func testStaleContextUpdateAfterSiblingDeleteDoesNotRestoreTheRow() throws {
        let container = try makeContainer()
        try insertCard(in: container.mainContext, key: "deleted-sibling")

        let staleContext = ModelContext(container)
        let deleteContext = ModelContext(container)
        let staleCard = try XCTUnwrap(card("deleted-sibling", in: staleContext))
        let deletedCard = try XCTUnwrap(card("deleted-sibling", in: deleteContext))
        deleteContext.delete(deletedCard)
        try deleteContext.save()

        staleCard.name = "Stale edit"
        try staleContext.save()

        let verification = ModelContext(container)
        XCTAssertNil(try card("deleted-sibling", in: verification))
    }

    func testFreshFetchByCollectionKeyAfterSiblingDeleteReturnsNothing() throws {
        let container = try makeContainer()
        try insertCard(in: container.mainContext, key: "fetch-after-delete")

        let deleteContext = ModelContext(container)
        let row = try XCTUnwrap(card("fetch-after-delete", in: deleteContext))
        deleteContext.delete(row)
        try deleteContext.save()

        let readContext = ModelContext(container)
        XCTAssertNil(try card("fetch-after-delete", in: readContext))
    }

    func testDidSaveKeysAndPersistentIdentifierEntityName() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let capture = SaveNotificationCapture()
        let token = NotificationCenter.default.addObserver(
            forName: ModelContext.didSave,
            object: context,
            queue: nil
        ) { capture.record($0) }
        defer { NotificationCenter.default.removeObserver(token) }

        let row = makeCard(key: "notification-keys")
        context.insert(row)
        try context.save()

        let userInfo = try XCTUnwrap(capture.userInfo)
        let keys = Set(userInfo.keys.map(Self.notificationKeyName))
        XCTAssertEqual(
            keys,
            Set([
                "inserted",
                "updated",
                "deleted"
            ])
        )
        XCTAssertEqual(row.persistentModelID.entityName, "CollectedCard")
        let insertedIdentifiers = try XCTUnwrap(
            userInfo.first { Self.notificationKeyName($0.key) ==
                ModelContext.NotificationKey.insertedIdentifiers.rawValue }?.value
                as? [PersistentIdentifier]
        )
        XCTAssertTrue(insertedIdentifiers.contains(row.persistentModelID))
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: CollectionStorageModelSchema.full,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func insertCard(in context: ModelContext, key: String) throws {
        context.insert(makeCard(key: key))
        try context.save()
    }

    private func makeCard(key: String) -> CollectedCard {
        CollectedCard(
            collectionKey: key,
            game: .pokemon,
            providerID: "test-set-001",
            name: "Test Card",
            setName: "Test Set",
            setCode: "TST",
            cardNumber: "001",
            rarity: nil,
            imageURL: nil,
            thumbnailURL: nil,
            variant: .normal,
            variantResolution: .userConfirmed
        )
    }

    private func card(_ key: String, in context: ModelContext) throws -> CollectedCard? {
        try context.fetch(FetchDescriptor<CollectedCard>(
            predicate: #Predicate { $0.collectionKey == key }
        )).first
    }

    private static func notificationKeyName(_ key: AnyHashable) -> String {
        if let key = key.base as? ModelContext.NotificationKey {
            return key.rawValue
        }
        if let key = key.base as? String {
            return key
        }
        return String(describing: key)
    }
}

private final class SaveNotificationCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var storedUserInfo: [AnyHashable: Any]?

    var userInfo: [AnyHashable: Any]? {
        lock.lock()
        defer { lock.unlock() }
        return storedUserInfo
    }

    func record(_ notification: Notification) {
        lock.lock()
        storedUserInfo = notification.userInfo
        lock.unlock()
    }
}
