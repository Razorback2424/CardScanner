import Foundation
import XCTest
@testable import TradingCardScanner

@MainActor
final class CardFinishMotionSourceTests: XCTestCase {
    func testCollectionAndDetailUseIndependentDeliveryRates() {
        let sampler = TestMotionSampler()
        var now = 0.0
        let source = CardFinishMotionSource(
            sampler: sampler,
            now: { now }
        )
        let collection = source.channel(for: .passive)
        let detail = source.channel(for: .detail)
        let collectionOwner = TestRegistrationOwner()
        let detailOwner = TestRegistrationOwner()

        let collectionToken = source.register(.passive, owner: collectionOwner)
        let detailToken = source.register(.detail, owner: detailOwner)

        XCTAssertEqual(sampler.interval, 1.0 / 60.0, accuracy: 0.0001)

        sampler.emit(roll: 0.20, pitch: 0)
        now += 1.0 / 60.0
        sampler.emit(roll: 0.30, pitch: 0)

        XCTAssertEqual(collection.deliveredSampleCount, 1)
        XCTAssertEqual(detail.deliveredSampleCount, 2)

        source.unregister(collectionToken)
        source.unregister(detailToken)
        XCTAssertTrue(sampler.isStopped)
    }

    func testImmaterialTiltNoiseIsDeduplicatedPerChannel() {
        let sampler = TestMotionSampler()
        var now = 0.0
        let source = CardFinishMotionSource(sampler: sampler, now: { now })
        let collection = source.channel(for: .passive)
        let owner = TestRegistrationOwner()
        let token = source.register(.passive, owner: owner)

        sampler.emit(roll: 0.20, pitch: 0)
        now += 1.0 / 30.0
        sampler.emit(roll: 0.201, pitch: 0)

        XCTAssertEqual(collection.deliveredSampleCount, 1)
        source.unregister(token)
    }

    func testSensorStopsWhenTheLastVisibleRegistrationLeaves() {
        let sampler = TestMotionSampler()
        let source = CardFinishMotionSource(sampler: sampler)
        let collectionOwner = TestRegistrationOwner()
        let detailOwner = TestRegistrationOwner()
        let collectionToken = source.register(.passive, owner: collectionOwner)
        let detailToken = source.register(.detail, owner: detailOwner)

        source.unregister(detailToken)
        XCTAssertFalse(sampler.isStopped)
        source.unregister(collectionToken)
        XCTAssertTrue(sampler.isStopped)
        XCTAssertEqual(source.activeRegistrationCount, 0)
    }

    func testStoppingMotionResetsTheSharedChannelToCenter() {
        let sampler = TestMotionSampler()
        var now = 0.0
        let source = CardFinishMotionSource(sampler: sampler, now: { now })
        let collection = source.channel(for: .passive)
        let owner = TestRegistrationOwner()
        let token = source.register(.passive, owner: owner)

        sampler.emit(roll: 0.20, pitch: 0)
        now += 1.0 / 30.0
        sampler.emit(roll: 0.40, pitch: 0)
        XCTAssertNotEqual(collection.tilt, .zero)

        source.unregister(token)

        XCTAssertEqual(collection.tilt, .zero)
        XCTAssertTrue(sampler.isStopped)
    }

    func testChangingFromDetailToCollectionKeepsSensorAtCollectionRate() {
        let sampler = TestMotionSampler()
        let source = CardFinishMotionSource(sampler: sampler)
        let collectionOwner = TestRegistrationOwner()
        let detailOwner = TestRegistrationOwner()
        let collectionToken = source.register(.passive, owner: collectionOwner)
        let detailToken = source.register(.detail, owner: detailOwner)

        source.unregister(detailToken)

        XCTAssertEqual(sampler.interval, 1.0 / 30.0, accuracy: 0.0001)
        source.unregister(collectionToken)
    }

    func testDetailRegistrationDoesNotDeliverToUnusedCollectionChannel() {
        let sampler = TestMotionSampler()
        var now = 0.0
        let source = CardFinishMotionSource(sampler: sampler, now: { now })
        let collection = source.channel(for: .passive)
        let detail = source.channel(for: .detail)
        let owner = TestRegistrationOwner()
        let token = source.register(.detail, owner: owner)

        sampler.emit(roll: 0.20, pitch: 0)
        now += 1.0 / 60.0
        sampler.emit(roll: 0.30, pitch: 0)

        XCTAssertEqual(collection.deliveredSampleCount, 0)
        XCTAssertEqual(detail.deliveredSampleCount, 2)
        source.unregister(token)
    }

    func testDeadRegistrationOwnerIsPrunedAndStopsMotion() {
        let sampler = TestMotionSampler()
        let source = CardFinishMotionSource(sampler: sampler)
        var owner: TestRegistrationOwner? = TestRegistrationOwner()

        _ = source.register(.passive, owner: owner!)
        XCTAssertEqual(source.activeRegistrationCount, 1)

        owner = nil
        sampler.emit(roll: 0.20, pitch: 0)

        XCTAssertEqual(source.activeRegistrationCount, 0)
        XCTAssertTrue(sampler.isStopped)
    }

    func testQueuedSensorCallbackAfterReduceMotionStopsWithoutDelivery() {
        let sampler = TestMotionSampler()
        var reduceMotionEnabled = false
        let source = CardFinishMotionSource(
            sampler: sampler,
            reduceMotionEnabled: { reduceMotionEnabled }
        )
        let collection = source.channel(for: .passive)
        let owner = TestRegistrationOwner()
        let token = source.register(.passive, owner: owner)

        sampler.emit(roll: 0.20, pitch: 0)
        XCTAssertEqual(collection.deliveredSampleCount, 1)

        reduceMotionEnabled = true
        sampler.emit(roll: 0.40, pitch: 0)

        XCTAssertEqual(collection.deliveredSampleCount, 1)
        XCTAssertEqual(collection.tilt, .zero)
        XCTAssertTrue(sampler.isStopped)
        source.unregister(token)
    }
}

private final class TestRegistrationOwner {}

@MainActor
private final class TestMotionSampler: CardFinishMotionSampler {
    var isDeviceMotionAvailable = true
    var isStopped = true
    var interval: TimeInterval = 0
    private var handler: ((CardFinishMotionAttitude) -> Void)?

    func start(
        interval: TimeInterval,
        handler: @escaping (CardFinishMotionAttitude) -> Void
    ) {
        self.interval = interval
        self.handler = handler
        isStopped = false
    }

    func stop() {
        isStopped = true
        handler = nil
    }

    func emit(roll: Double, pitch: Double) {
        handler?(CardFinishMotionAttitude(roll: roll, pitch: pitch))
    }
}
