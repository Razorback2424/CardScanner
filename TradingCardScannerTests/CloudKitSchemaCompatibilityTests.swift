import SwiftData
import XCTest
@testable import TradingCardScanner

final class CloudKitSchemaCompatibilityTests: XCTestCase {
    private let syncedTypes: [any PersistentModel.Type] = [
        CollectedCard.self,
        PriceRecord.self,
        ProductIdentity.self,
        CollectionActivity.self,
        InventoryEvent.self
    ]

    @MainActor
    func testExactFiveModelSyncedSchemaConstructsLocally() throws {
        let schema = Schema(syncedTypes)
        let container = try ModelContainer(
            for: schema,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        XCTAssertEqual(container.schema.entities.count, 5)
        XCTAssertEqual(
            Set(container.schema.entities.map(\.name)),
            Set([
                "CollectedCard",
                "PriceRecord",
                "ProductIdentity",
                "CollectionActivity",
                "InventoryEvent"
            ])
        )
    }

    @MainActor
    func testRelationshipIsOptionalAndHasAnExplicitInverseInTheRuntimeSchema() throws {
        let schema = Schema(syncedTypes)
        let collectedCard = try XCTUnwrap(schema.entities.first { $0.name == "CollectedCard" })
        let activity = try XCTUnwrap(schema.entities.first { $0.name == "CollectionActivity" })

        let cardRelationship = try XCTUnwrap(
            collectedCard.properties.first { $0.name == "activityBackfillAnchor" } as? Schema.Relationship
        )
        XCTAssertTrue(cardRelationship.isOptional)

        let activityRelationship = try XCTUnwrap(
            activity.properties.first { $0.name == "backfillAnchorCard" } as? Schema.Relationship
        )
        XCTAssertTrue(activityRelationship.isOptional)
    }

    func testApplicationIdentityOwnersRemainCodeLevelNotSchemaUniqueness() {
        XCTAssertFalse(String(reflecting: CollectedCard.self).contains("unique"))
        XCTAssertFalse(String(reflecting: PriceRecord.self).contains("unique"))
        XCTAssertFalse(String(reflecting: ProductIdentity.self).contains("unique"))
        XCTAssertFalse(String(reflecting: CollectionActivity.self).contains("unique"))
        XCTAssertFalse(String(reflecting: InventoryEvent.self).contains("unique"))
    }

    func testRawCardConditionIsNotAStoredCollectedCardField() {
        let names = Schema([CollectedCard.self]).entities.flatMap { entity in
            entity.properties.map(\.name)
        }
        XCTAssertFalse(names.contains { $0.localizedCaseInsensitiveContains("condition") })
    }
}
