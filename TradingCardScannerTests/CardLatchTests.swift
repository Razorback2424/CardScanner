import Vision
import XCTest
@testable import TradingCardScanner

/// The latch is the reason automatic collection entry is defensible, so these
/// cases are written as the physical situations they stand for.
final class CardLatchTests: XCTestCase {
    func testTrackerFeedsLatestObservationIntoTheNextRequest() {
        let seed = VNDetectedObjectObservation(
            boundingBox: CGRect(x: 0.2, y: 0.2, width: 0.4, height: 0.4)
        )
        let latest = VNDetectedObjectObservation(
            boundingBox: CGRect(x: 0.3, y: 0.25, width: 0.35, height: 0.4)
        )
        let request = VNTrackObjectRequest(detectedObjectObservation: seed)

        XCTAssertEqual(request.inputObservation.boundingBox, seed.boundingBox)
        CardScanner.feedForwardTrackerObservation(latest, into: request)

        XCTAssertEqual(request.inputObservation.boundingBox, latest.boundingBox)
    }

    private func pokemon(_ number: Int, code: String = "OBF") -> ScanIdentifier {
        let definition = SetCodeMap.definitions[code]!
        return .pokemon(
            setCode: code,
            cardNumber: String(format: "%03d", number),
            printedTotal: definition.officialCount,
            setDefinition: definition
        )
    }

    /// A card left sitting in the band is read over and over. It must go in once.
    func testContinuouslyVisibleCardIsConsumedOnlyOnce() {
        var latch = CardLatch()
        let card = pokemon(223)
        latch.engage(on: card, at: 0)

        for pass in 1...40 {
            XCTAssertEqual(latch.observe(card, at: Double(pass) * 0.25), .holdingLatch)
        }
        XCTAssertEqual(latch.latched, card)
    }

    func testLatchReleasesOnceTheIdentifierStopsBeingRead() {
        var latch = CardLatch(releaseAfterAbsences: 4)
        latch.engage(on: pokemon(223), at: 0)

        for pass in 1...3 {
            XCTAssertEqual(latch.observe(nil, at: Double(pass) * 0.25), .forward(nil))
            XCTAssertNotNil(latch.latched)
        }

        XCTAssertEqual(latch.observe(nil, at: 1.0), .forward(nil))
        XCTAssertNil(latch.latched)
    }

    /// Different cards in a row must stay fast: no blank frame required between them.
    func testDifferentCardIsForwardedAndAdmittedImmediately() {
        var latch = CardLatch()
        let first = pokemon(223)
        let second = pokemon(204, code: "PAL")
        latch.engage(on: first, at: 0)

        XCTAssertEqual(latch.observe(second, at: 0.25), .forward(second))
        XCTAssertTrue(latch.admits(second))
    }

    /// One garbage reading must not unlock the card that is still sitting there.
    func testSingleStrayReadingDoesNotReleaseTheLatch() {
        var latch = CardLatch(releaseAfterAbsences: 4)
        let card = pokemon(223)
        latch.engage(on: card, at: 0)

        _ = latch.observe(pokemon(204, code: "PAL"), at: 0.25)
        XCTAssertEqual(latch.latched, card)
        XCTAssertEqual(latch.observe(card, at: 0.5), .holdingLatch)
    }

    /// A focus wobble can produce several different valid-looking OCR parses
    /// without the physical card leaving. Those mismatches must not age out the
    /// latch or allow the original card to be counted again.
    func testValidOCRMismatchesDoNotCountAsCardAbsence() {
        var latch = CardLatch(releaseAfterAbsences: 4, minimumAbsenceBeforeRelatch: 2.0)
        let card = pokemon(223)
        let blurRead = pokemon(204, code: "PAL")
        latch.engage(on: card, at: 0)

        for pass in 1...8 {
            _ = latch.observe(blurRead, at: Double(pass) * 0.25)
        }

        XCTAssertEqual(latch.latched, card)
        XCTAssertFalse(latch.admits(card))
        XCTAssertEqual(latch.observe(card, at: 2.25), .holdingLatch)
    }

    /// OCR losing the card to glare is not the card leaving. Even after the latch
    /// times out, an identical reading that never really went away is refused.
    func testGlareGapCannotProduceADuplicate() {
        var latch = CardLatch(releaseAfterAbsences: 4, minimumAbsenceBeforeRelatch: 2.0)
        let card = pokemon(223)
        latch.engage(on: card, at: 0)

        for pass in 1...4 {
            _ = latch.observe(nil, at: Double(pass) * 0.25)
        }
        XCTAssertNil(latch.latched, "the absence budget really did run out")

        // The card is read continuously from here on, as it would be in a real
        // session at four passes a second.
        for pass in stride(from: 1.25, through: 6.0, by: 0.25) {
            _ = latch.observe(card, at: pass)
            XCTAssertFalse(latch.admits(card), "no duplicate while the card is still being read")
        }
    }

    func testShortOCRAbsenceDoesNotReadmitConsumedCard() {
        var latch = CardLatch(releaseAfterAbsences: 4, minimumAbsenceBeforeRelatch: 2.0)
        let card = pokemon(223)
        latch.engage(on: card, at: 0)

        for pass in 1...6 {
            _ = latch.observe(nil, at: Double(pass) * 0.25)
        }
        XCTAssertNil(latch.latched)

        _ = latch.observe(card, at: 1.75)
        XCTAssertFalse(latch.admits(card))
    }

    func testPausedRecognitionDoesNotAgeConsumedPrinting() {
        var latch = CardLatch(presumedGoneAfter: 6.0)
        let card = pokemon(223)
        latch.engage(on: card, at: 0)

        // No observation reaches the latch while a presentation sheet owns the
        // camera. The explicit clock shift is what the real scanner performs
        // on resume; without it this first blurry/empty frame would make the
        // stationary card look as though it had been gone for 30 seconds.
        latch.advanceObservedClock(by: 30)
        _ = latch.observe(nil, cardPresent: false, at: 30.25)
        _ = latch.observe(card, cardPresent: true, at: 30.50)

        XCTAssertFalse(latch.admits(card))
    }

    private func historical(_ localID: String, titles: [String]) -> ScanIdentifier {
        .pokemonHistorical(
            PokemonHistoricalScanEvidence(
                number: PokemonPrintedNumberEvidence(
                    localID: localID,
                    denominator: 102,
                    scheme: .officialSet
                ),
                titleCandidates: titles
            )
        )
    }

    /// The reported bug, as a sequence of readings.
    ///
    /// A card is added, then lifted. On the way out a blurred frame reads a
    /// neighbouring collector number twice, which confirms — and the scanner
    /// engages on it before anything has tried to resolve it. The card being
    /// lifted is still in the band, and must not go in a second time because
    /// something else briefly appeared to be there.
    func testAStrayConfirmationDoesNotReadmitTheCardStillInTheBand() {
        var latch = CardLatch()
        let card = pokemon(40)
        let blurredNeighbour = pokemon(46)
        latch.engage(on: card, at: 0)

        latch.engage(on: blurredNeighbour, at: 0.5)

        _ = latch.observe(card, at: 0.75)
        XCTAssertFalse(
            latch.admits(card),
            "the card that was just added has not left the band"
        )
    }

    /// The same defect without any misreading at all.
    ///
    /// A historical identifier carries every title observation, so one physical
    /// card produces a new identifier as soon as OCR picks up one more line of
    /// its name. That is a different `ScanIdentifier` for the same piece of
    /// cardboard, and it must not be treated as a different card arriving.
    func testATitleReadingDriftingDoesNotReadmitTheSamePhysicalCard() {
        var latch = CardLatch()
        let firstReading = historical("004", titles: ["CHARIZARD"])
        let driftedReading = historical("004", titles: ["CHARIZARD", "STAGE 2"])
        latch.engage(on: firstReading, at: 0)

        latch.engage(on: driftedReading, at: 0.5)

        _ = latch.observe(firstReading, at: 0.75)
        XCTAssertFalse(
            latch.admits(firstReading),
            "one card whose name read differently for a frame is still one card"
        )
    }

    /// The fix must not swallow real cards. Two different printings in a row,
    /// each leaving before the next arrives, both go in.
    func testTwoDifferentCardsInSuccessionAreBothAdmitted() {
        var latch = CardLatch(releaseAfterAbsences: 2, minimumAbsenceBeforeRelatch: 0.5)
        let first = pokemon(40)
        let second = pokemon(46)
        latch.engage(on: first, at: 0)

        for pass in stride(from: 0.25, through: 1.5, by: 0.25) {
            _ = latch.observe(nil, at: pass)
        }

        _ = latch.observe(second, at: 1.75)
        XCTAssertTrue(latch.admits(second), "a different card must not be blocked")
    }

    /// The reported workflow, exactly: the phone is stationary over the table and
    /// the card is picked up and moved aside.
    ///
    /// The card is right in front of the lens for the whole lift, so there is
    /// always text in the band — it is just tilting and blurring, and parses as
    /// nothing for a second or two before coming back into focus on its way out.
    /// It never left, so it must not go in again.
    func testACardBeingLiftedOutOfTheBandIsNotReadmitted() {
        var latch = CardLatch()
        let card = pokemon(40)
        latch.engage(on: card, at: 0)

        for pass in stride(from: 0.25, through: 2.5, by: 0.25) {
            _ = latch.observe(nil, cardPresent: true, at: pass)
        }

        _ = latch.observe(card, cardPresent: true, at: 2.75)
        XCTAssertFalse(
            latch.admits(card),
            "unreadable is not gone — the band was occupied the whole time"
        )
    }

    /// The same lift, but the blur parses as a neighbouring number for a frame or
    /// two on the way out. Still one card, still never left.
    func testAMisreadDuringTheLiftDoesNotReadmitTheCard() {
        var latch = CardLatch()
        let card = pokemon(40)
        latch.engage(on: card, at: 0)

        for pass in stride(from: 0.25, through: 1.5, by: 0.25) {
            _ = latch.observe(nil, cardPresent: true, at: pass)
        }
        _ = latch.observe(pokemon(46), cardPresent: true, at: 1.75)
        _ = latch.observe(pokemon(46), cardPresent: true, at: 2.0)

        _ = latch.observe(card, cardPresent: true, at: 2.25)
        XCTAssertFalse(latch.admits(card))
    }

    /// The distinction the fix rests on: an empty band still means the card left.
    func testAnEmptyBandStillMeansTheCardLeft() {
        var latch = CardLatch()
        let card = pokemon(40)
        latch.engage(on: card, at: 0)

        for pass in stride(from: 0.25, through: 2.5, by: 0.25) {
            _ = latch.observe(nil, cardPresent: false, at: pass)
        }

        _ = latch.observe(card, cardPresent: true, at: 2.75)
        XCTAssertTrue(latch.admits(card), "nothing was in the band for two seconds")
    }

    /// Nothing may be suppressed forever. A band that is never empty — because
    /// other cards keep passing through it — must still let a printing back in
    /// eventually, or a second copy later in a long run would be refused.
    func testAPrintingIsPresumedGoneOnceItHasNotBeenReadForALongTime() {
        var latch = CardLatch(presumedGoneAfter: 6.0)
        let card = pokemon(40)
        latch.engage(on: card, at: 0)

        for pass in stride(from: 0.25, through: 6.5, by: 0.25) {
            _ = latch.observe(pokemon(46), cardPresent: true, at: pass)
        }

        _ = latch.observe(card, cardPresent: true, at: 6.75)
        XCTAssertTrue(latch.admits(card))
    }

    /// A genuine second copy: the first one leaves, then an identical card lands.
    func testSecondPhysicalCopyIsAdmittedAfterTheFirstLeaves() {
        var latch = CardLatch(releaseAfterAbsences: 2, minimumAbsenceBeforeRelatch: 2.0)
        let card = pokemon(223)
        latch.engage(on: card, at: 0)

        for pass in stride(from: 0.25, through: 2.0, by: 0.25) {
            _ = latch.observe(nil, at: pass)
        }

        _ = latch.observe(card, at: 2.25)
        XCTAssertTrue(latch.admits(card))
    }

    /// Undo and dismissing a question both keep the memory: the card is still in
    /// the band, and re-adding it instantly would undo the undo.
    func testPlainReleaseKeepsRefusingTheCardStillInView() {
        var latch = CardLatch()
        let card = pokemon(223)
        latch.engage(on: card, at: 0)
        latch.release()

        XCTAssertNil(latch.latched)
        XCTAssertFalse(latch.admits(card))
    }

    /// A dropped network request wrote nothing, so it must cost a re-read at most.
    func testReleaseAndForgetAdmitsTheVeryNextConfirmation() {
        var latch = CardLatch()
        let card = pokemon(223)
        latch.engage(on: card, at: 0)
        latch.releaseAndForget()

        XCTAssertEqual(latch.observe(card, at: 0.25), .forward(card))
        XCTAssertTrue(latch.admits(card))
    }

    func testArmedRecheckBecomesAdmissibleOnlyAfterItsDelay() {
        var latch = CardLatch()
        let card = pokemon(223)
        latch.engage(on: card, at: 0)
        latch.armRecheck(for: card, at: 0.5, after: 1.25)

        XCTAssertEqual(latch.observe(card, at: 1.749), .holdingLatch)
        XCTAssertFalse(latch.admits(card))

        XCTAssertEqual(latch.observe(card, at: 1.75), .forward(card))
        XCTAssertNil(latch.latched)
        XCTAssertTrue(latch.admits(card))
    }

    func testArmedRecheckExpiresForAStationaryCardBeforeItsMatchingReadContinues() {
        var latch = CardLatch()
        let card = pokemon(223)
        latch.engage(on: card, at: 0)
        latch.armRecheck(for: card, at: 0, after: 1.25)

        for time in stride(from: 0.25, through: 1.0, by: 0.25) {
            XCTAssertEqual(latch.observe(card, at: time), .holdingLatch)
            XCTAssertFalse(latch.admits(card))
        }

        // A matching reading used to take the `continue` above, refresh
        // `lastSeenAt`, and keep the price-check latch engaged forever.
        XCTAssertEqual(latch.observe(card, at: 1.25), .forward(card))
        XCTAssertTrue(latch.admits(card))
    }

    func testArmingOneRecheckDoesNotForgetOtherConsumedPrintings() {
        var latch = CardLatch()
        let first = pokemon(223)
        let second = pokemon(204, code: "PAL")
        latch.engage(on: first, at: 0)
        latch.engage(on: second, at: 0.25)
        latch.armRecheck(for: first, at: 0.5, after: 1.25)

        XCTAssertEqual(latch.observe(first, at: 1.75), .forward(first))
        XCTAssertTrue(latch.admits(first))
        XCTAssertFalse(latch.admits(second), "arming one Price Check re-read must keep other duplicate protection")
    }

    func testHeldMatchCountTracksHowLongTheSameCardHasBeenSittingThere() {
        var latch = CardLatch()
        let card = pokemon(223)
        latch.engage(on: card, at: 0)

        for pass in 1...5 {
            _ = latch.observe(card, at: Double(pass) * 0.25)
        }
        XCTAssertEqual(latch.heldMatchCount, 5)

        latch.engage(on: card, at: 2)
        XCTAssertEqual(latch.heldMatchCount, 0)
    }

    func testTrackingAndOCRCadencesAreIndependent() {
        var scheduler = ScanCadenceScheduler()

        XCTAssertTrue(scheduler.shouldRun(.tracking, at: 0))
        XCTAssertTrue(scheduler.shouldRun(.ocr, at: 0))
        XCTAssertFalse(scheduler.shouldRun(.tracking, at: 0.05))
        XCTAssertFalse(scheduler.shouldRun(.ocr, at: 0.05))

        // Tracking continues at roughly 12 Hz while OCR is still inside its
        // 0.24-second window.
        XCTAssertTrue(scheduler.shouldRun(.tracking, at: 0.084))
        XCTAssertFalse(scheduler.shouldRun(.ocr, at: 0.084))
        XCTAssertTrue(scheduler.shouldRun(.tracking, at: 0.168))
        XCTAssertFalse(scheduler.shouldRun(.ocr, at: 0.168))
        XCTAssertTrue(scheduler.shouldRun(.ocr, at: 0.24))

        // An OCR start does not postpone the next tracking start.
        XCTAssertTrue(scheduler.shouldRun(.tracking, at: 0.252))
    }

    func testQualifyingExitCompletesOnceAfterTwoObservations() {
        var accumulator = SpatialExitObservationAccumulator()
        let outsideGuide = CGRect(x: 0.01, y: 0.01, width: 0.05, height: 0.05)

        XCTAssertFalse(accumulator.observe(box: outsideGuide, confidence: 0.9))
        XCTAssertTrue(accumulator.observe(box: outsideGuide, confidence: 0.9))
        XCTAssertFalse(
            accumulator.observe(box: outsideGuide, confidence: 0.9),
            "the tracker is torn down at the threshold, so no second proof event is possible"
        )
    }

    func testInsideObservationOrTrackerLossCannotCompleteSpatialExit() {
        var accumulator = SpatialExitObservationAccumulator()
        let insideGuide = CardFramingRegion.cardVisionRect.insetBy(dx: 0.01, dy: 0.01)
        let outsideGuide = CGRect(x: 0.01, y: 0.01, width: 0.05, height: 0.05)

        XCTAssertFalse(accumulator.observe(box: insideGuide, confidence: 0.9))
        XCTAssertFalse(
            accumulator.observe(box: outsideGuide, confidence: 0.49),
            "low confidence is not exit evidence"
        )
        // No observation is supplied for a tracker-loss event; it cannot move
        // the proof counter forward.
        XCTAssertEqual(accumulator.consecutiveQualifiedObservations, 0)
    }

    func testSpatialTrackerSeedGateRejectsSameIdentityAfterLoss() {
        var gate = SpatialTrackerSeedGate()
        let first = pokemon(223)
        let different = pokemon(204, code: "PAL")

        gate.markLost(first)
        XCTAssertFalse(gate.canSeed(first))
        gate.markLost(nil)
        XCTAssertFalse(gate.canSeed(first), "a repeated invalidation cannot clear a lost lineage")
        XCTAssertTrue(gate.canSeed(different))
        XCTAssertTrue(
            gate.canSeed(first),
            "a different encounter may establish a new lineage and clear the old marker"
        )
    }

    func testHeldRepeatAuthorizationIsOneShotAndDoesNotMarkSpatialExit() {
        var latch = CardLatch()
        let card = pokemon(223)
        latch.engage(on: card, at: 0)

        latch.authorizeHeldRepeat(for: card.suppressionKey)
        XCTAssertEqual(latch.latched, card)
        XCTAssertFalse(latch.admits(card), "authorization is not spatial exit evidence")
        XCTAssertEqual(latch.observe(card, at: 0.25), .forwardAuthorized(card))
        XCTAssertEqual(latch.heldMatchCount, 0, "the authorized frame is not a held presentation")
        XCTAssertTrue(latch.consumeHeldRepeatAuthorization(for: card.suppressionKey))
        XCTAssertFalse(latch.consumeHeldRepeatAuthorization(for: card.suppressionKey))

        XCTAssertEqual(latch.observe(card, at: 0.5), .holdingLatch)

        latch.engage(on: card, at: 1)
        XCTAssertFalse(latch.admits(card), "the newly authorized copy remains suppressed after its one use")
    }

    func testCancellingHeldRepeatRequiresFreshHeldObservationsBeforeAnotherOffer() {
        var latch = CardLatch()
        let card = pokemon(223)
        latch.engage(on: card, at: 0)
        latch.authorizeHeldRepeat(for: card.suppressionKey)
        latch.cancelHeldRepeatAuthorization()

        for pass in 1..<8 {
            XCTAssertEqual(latch.observe(card, at: Double(pass) * 0.25), .holdingLatch)
        }
        XCTAssertEqual(latch.heldMatchCount, 7)
        XCTAssertEqual(latch.observe(card, at: 2.0), .holdingLatch)
        XCTAssertEqual(latch.heldMatchCount, 8)
    }

    func testHeldRepeatAuthorizationDoesNotAdmitAnotherIdentity() {
        var latch = CardLatch()
        let first = pokemon(223)
        let different = pokemon(204, code: "PAL")
        latch.engage(on: first, at: 0)
        latch.authorizeHeldRepeat(for: first.suppressionKey)

        XCTAssertFalse(latch.consumeHeldRepeatAuthorization(for: different.suppressionKey))
        latch.cancelHeldRepeatAuthorization()
        XCTAssertTrue(latch.admits(different))
    }

    func testHeldRepeatAuthorizationCanReopenOnlyTheLostSeedGate() {
        var gate = SpatialTrackerSeedGate()
        let card = pokemon(223)
        gate.markLost(card)
        XCTAssertFalse(gate.canSeed(card))

        gate.allowAuthorizedReseed(for: card.suppressionKey)
        XCTAssertTrue(gate.canSeed(card))
    }

    func testHeldRepeatAuthorizationExpiryIsFakeClockable() {
        let authorization = HeldRepeatAuthorization(
            expectedSuppressionKey: pokemon(223).suppressionKey,
            expiresAt: 2.0
        )

        XCTAssertFalse(authorization.isExpired(at: 1.999))
        XCTAssertTrue(authorization.isExpired(at: 2.0))
    }

    func testScanRequestCarriesHeldRepeatAuthorizationThroughResolution() {
        let authorizationID = UUID()
        let request = ScanRequest(
            identifier: pokemon(223),
            purpose: .collection,
            generation: 7,
            heldRepeatAuthorizationID: authorizationID
        )

        XCTAssertEqual(request.heldRepeatAuthorizationID, authorizationID)
    }

    func testSpatialConfigurationUsesStrictExperimentalDefaults() {
        let configuration = SpatialTrackingConfiguration.experimental

        XCTAssertEqual(configuration.trackingRate, 12)
        XCTAssertEqual(configuration.seedInsetFraction, 0.06)
        XCTAssertEqual(configuration.minimumConfidence, 0.50)
        XCTAssertEqual(configuration.requiredExitObservations, 2)
        XCTAssertEqual(configuration.maximumGuideOverlap, 0.25)
    }

    func testOnlyPositiveSpatialExitMakesAConsumedPrintingReadmit() {
        var latch = CardLatch()
        let card = pokemon(223)
        latch.engage(on: card, at: 0)

        XCTAssertFalse(latch.admits(card))
        latch.confirmSpatialExit(for: card)
        XCTAssertTrue(latch.admits(card))
    }

    func testExitRequiresLowGuideOverlapEvenWhenCenterIsOutside() {
        let configuration = SpatialTrackingConfiguration.experimental
        let guide = CardFramingRegion.cardVisionRect
        let mostlyOverlappingBox = CGRect(
            x: guide.maxX - guide.width * 0.20,
            y: guide.minY,
            width: guide.width * 0.50,
            height: guide.height * 0.50
        )

        XCTAssertFalse(
            configuration.isQualifyingExit(box: mostlyOverlappingBox, confidence: 0.9)
        )
    }

    func testCollectionRoutingUsesProofAndCommittedIdentity() {
        let prior = committedSessionScan(identity: "pokemon:obf-223")
        let proof = SpatialResetProof(
            encounterID: prior.encounterID,
            presentationToken: prior.presentationToken
        )
        let sameIdentity = ConsecutiveScanIdentity(canonicalID: "pokemon:obf-223")
        let differentIdentity = ConsecutiveScanIdentity(canonicalID: "pokemon:pal-204")

        XCTAssertEqual(
            CollectionCandidateRoutingPolicy.decision(
                for: sameIdentity,
                previous: prior,
                proofs: []
            ),
            .suppress
        )
        XCTAssertEqual(
            CollectionCandidateRoutingPolicy.decision(
                for: sameIdentity,
                previous: prior,
                proofs: [proof]
            ),
            .duplicate(proof)
        )
        XCTAssertEqual(
            CollectionCandidateRoutingPolicy.decision(
                for: differentIdentity,
                previous: prior,
                proofs: []
            ),
            .automatic
        )
    }

    func testCollectionRoutingProtectsAnOlderCommittedPrintingToo() {
        let older = committedSessionScan(identity: "pokemon:obf-223")
        let latest = committedSessionScan(identity: "pokemon:pal-204")
        let sameAsOlder = ConsecutiveScanIdentity(canonicalID: older.identity.canonicalID)

        // The OCR/latch memory is bounded but intentionally wider than one
        // commit. A later unrelated card must not erase the older printing's
        // duplicate protection.
        XCTAssertEqual(
            CollectionCandidateRoutingPolicy.decision(
                for: sameAsOlder,
                previous: latest,
                history: [older, latest],
                proofs: []
            ),
            .suppress
        )

        let proof = SpatialResetProof(
            encounterID: older.encounterID,
            presentationToken: older.presentationToken
        )
        XCTAssertEqual(
            CollectionCandidateRoutingPolicy.decision(
                for: sameAsOlder,
                previous: latest,
                history: [older, latest],
                proofs: [proof]
            ),
            .duplicate(proof)
        )
    }

    func testHeldOfferDefersUntilItsEncounterIsCommitted() {
        let card = pokemon(223)
        let encounterID = UUID()
        let olderCard = heldPublicationEntry(
            identity: "pokemon:pal-204",
            suppressionKey: pokemon(204, code: "PAL").suppressionKey
        )

        XCTAssertEqual(
            HeldDuplicateOfferPublicationPolicy.decision(
                for: card.suppressionKey,
                encounterID: encounterID,
                history: [olderCard]
            ),
            .deferUntilCommit
        )

        let acknowledged = heldPublicationEntry(
            identity: "pokemon:obf-223",
            suppressionKey: card.suppressionKey,
            encounterID: encounterID
        )
        XCTAssertEqual(
            HeldDuplicateOfferPublicationPolicy.decision(
                for: card.suppressionKey,
                encounterID: encounterID,
                history: [olderCard, acknowledged]
            ),
            .publish(previous: acknowledged)
        )
    }

    func testHeldOfferDefersEvenWhenAnOlderSameKeyPresentationExists() {
        let card = pokemon(223)
        let olderPresentation = heldPublicationEntry(
            identity: "pokemon:obf-223",
            suppressionKey: card.suppressionKey,
            encounterID: UUID()
        )
        let unrelatedLatest = heldPublicationEntry(
            identity: "pokemon:pal-204",
            suppressionKey: pokemon(204, code: "PAL").suppressionKey,
            encounterID: UUID()
        )

        XCTAssertEqual(
            HeldDuplicateOfferPublicationPolicy.decision(
                for: card.suppressionKey,
                encounterID: UUID(),
                history: [olderPresentation, unrelatedLatest]
            ),
            .deferUntilCommit
        )
    }

    func testFinishAndPokemonPrintRunDifferencesStillUseSameDuplicateIdentity() {
        let prior = committedSessionScan(identity: "pokemon:obf-223")
        let proof = SpatialResetProof(
            encounterID: prior.encounterID,
            presentationToken: prior.presentationToken
        )

        // Finish and Pokémon print-run live on the candidate, not on the
        // canonical IdentifiedCard.id key. The same key therefore still takes
        // the duplicate-confirmation route after full resolution.
        let alternateResolvedPhysicalObject = ConsecutiveScanIdentity(
            canonicalID: "pokemon:obf-223"
        )
        XCTAssertEqual(
            CollectionCandidateRoutingPolicy.decision(
                for: alternateResolvedPhysicalObject,
                previous: prior,
                proofs: [proof]
            ),
            .duplicate(proof)
        )
    }

    func testStrayResolutionDoesNotChangeCommittedHistory() {
        let first = committedSessionScan(identity: "pokemon:obf-223")
        let stray = ConsecutiveScanIdentity(canonicalID: "pokemon:pal-204")
        let proof = SpatialResetProof(
            encounterID: first.encounterID,
            presentationToken: first.presentationToken
        )

        // A stray B that never commits leaves A as the previous committed
        // identity. A is consequently still protected by its proof.
        XCTAssertEqual(
            CollectionCandidateRoutingPolicy.decision(
                for: stray,
                previous: first,
                proofs: []
            ),
            .automatic
        )
        XCTAssertEqual(
            CollectionCandidateRoutingPolicy.decision(
                for: ConsecutiveScanIdentity(canonicalID: "pokemon:obf-223"),
                previous: first,
                proofs: [proof]
            ),
            .duplicate(proof)
        )

        let committedB = committedSessionScan(identity: "pokemon:pal-204")
        XCTAssertEqual(
            CollectionCandidateRoutingPolicy.decision(
                for: ConsecutiveScanIdentity(canonicalID: "pokemon:obf-223"),
                previous: committedB,
                history: [first, committedB],
                proofs: []
            ),
            .suppress
        )
    }

    private func committedSessionScan(identity: String) -> CommittedSessionScan {
        CommittedSessionScan(
            id: UUID(),
            identity: ConsecutiveScanIdentity(canonicalID: identity),
            presentationToken: UUID(),
            encounterID: UUID()
        )
    }

    private func heldPublicationEntry(
        identity: String,
        suppressionKey: ScanSuppressionKey,
        encounterID: UUID = UUID()
    ) -> HeldDuplicatePublicationHistoryEntry {
        HeldDuplicatePublicationHistoryEntry(
            committed: CommittedSessionScan(
                id: UUID(),
                identity: ConsecutiveScanIdentity(canonicalID: identity),
                presentationToken: UUID(),
                encounterID: encounterID
            ),
            suppressionKey: suppressionKey
        )
    }
}
