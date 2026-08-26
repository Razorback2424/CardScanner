import XCTest
@testable import TradingCardScanner

/// The latch is the reason automatic collection entry is defensible, so these
/// cases are written as the physical situations they stand for.
final class CardLatchTests: XCTestCase {
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
}
