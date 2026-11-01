import XCTest
@testable import TradingCardScanner

/// The scanner-facing half of token identity: what each confirmed face
/// reading means for the cardboard in front of the camera.
///
/// The three things this protects, in order of how badly they fail:
/// 1. Turning a recorded token over never records it again.
/// 2. A face that does not decide the card is never guessed into one.
/// 3. The flip that answers the question costs no tap.
///
/// MSH fixtures match `MagicPhysicalObjectTests`: `Merfolk // Doombot` is
/// verified against JustTCG, and Clue #17 on two cards is the repository's
/// existing MSH fixture. Coverage claims are the fixture's, not the real set's.
final class MagicTokenPairingSessionTests: XCTestCase {

    // MARK: - Fixtures

    private func face(_ set: String, _ number: String) -> MagicTokenFaceID {
        MagicTokenFaceID(setCode: set, number: number)
    }

    private func card(_ faces: (String, String, String)..., ids: Set<String> = []) -> MagicPhysicalToken {
        MagicPhysicalToken(
            faces: faces.map { MagicTokenFace(setCode: $0.0, number: $0.1, name: $0.2) },
            tcgplayerProductIDs: ids
        )!
    }

    private func key(_ faces: MagicTokenFaceID...) -> MagicPhysicalTokenKey {
        MagicPhysicalTokenKey(faces: faces)!
    }

    private var merfolkDoombot: MagicPhysicalToken {
        card(("TMSH", "6", "Merfolk"), ("TMSH", "18", "Doombot"), ids: ["703230"])
    }
    private var soldierClue: MagicPhysicalToken {
        card(("TMSH", "4", "Soldier"), ("TMSH", "17", "Clue"))
    }
    private var insectClue: MagicPhysicalToken {
        card(("TMSH", "12", "Insect"), ("TMSH", "17", "Clue"))
    }

    private func mshSession(coverage: [String: MagicTokenPairingCoverage] = ["TMSH": .complete]) -> MagicTokenPairingSession {
        MagicTokenPairingSession(catalog: MagicTokenProductCatalog(
            products: [merfolkDoombot, soldierClue, insectClue], coverage: coverage
        ))
    }

    /// A set nothing is known about: every pairing has to come from the card
    /// itself and the person holding it.
    private func uncataloguedSession() -> MagicTokenPairingSession {
        MagicTokenPairingSession(catalog: MagicTokenProductCatalog(products: []))
    }

    private func added(_ product: MagicPhysicalToken, _ basis: MagicTokenPairingBasis) -> MagicTokenPairingSession.Effect {
        .add(MagicTokenAcquisition(key: product.key, product: product, basis: basis))
    }

    private var clueQuestion: MagicTokenReverseQuestion {
        MagicTokenReverseQuestion(face: face("TMSH", "17"), candidates: [soldierClue, insectClue], catalogIsExhaustive: true)
    }

    private func openQuestion(_ face: MagicTokenFaceID) -> MagicTokenReverseQuestion {
        MagicTokenReverseQuestion(face: face, candidates: [], catalogIsExhaustive: false)
    }

    // MARK: - Recorded cards are never recorded twice

    func testUniqueFaceAddsAtOnceAndTurningItOverNeverAddsAgain() {
        var session = mshSession()

        XCTAssertEqual(session.handle(.faceConfirmed(face("TMSH", "18"))), [added(merfolkDoombot, .uniqueFace)])
        // Turning the card over empties the band for a moment.
        XCTAssertEqual(session.handle(.bandCleared), [])
        XCTAssertEqual(session.handle(.faceConfirmed(face("TMSH", "6"))), [.sameCard(merfolkDoombot.key)])
        // And back again.
        XCTAssertEqual(session.handle(.bandCleared), [])
        XCTAssertEqual(session.handle(.faceConfirmed(face("TMSH", "18"))), [.sameCard(merfolkDoombot.key)])
        XCTAssertNil(session.pendingQuestion)
    }

    /// The existing latch rule, unchanged for tokens: while a card never left,
    /// re-reading it does nothing; once the band empties, the same side again
    /// is another copy.
    func testSameSideAfterTheBandEmptiesIsAnotherCopy() {
        var session = mshSession()
        _ = session.handle(.faceConfirmed(face("TMSH", "18")))

        XCTAssertEqual(session.handle(.faceConfirmed(face("TMSH", "18"))), [])
        _ = session.handle(.bandCleared)
        XCTAssertEqual(session.handle(.faceConfirmed(face("TMSH", "18"))), [added(merfolkDoombot, .uniqueFace)])
    }

    /// A different card confirming releases the hold, exactly as it releases
    /// the latch.
    func testADifferentCardReleasesTheHold() {
        var session = mshSession()
        _ = session.handle(.faceConfirmed(face("TMSH", "18")))

        XCTAssertEqual(session.handle(.otherCardConfirmed), [])
        XCTAssertEqual(session.handle(.faceConfirmed(face("TMSH", "6"))), [added(merfolkDoombot, .uniqueFace)])
    }

    // MARK: - The flip is the answer

    func testAmbiguousFaceAsksAndTheFlipAnswersWithoutATap() {
        var session = mshSession()

        XCTAssertEqual(session.handle(.faceConfirmed(face("TMSH", "17"))), [.askForReverse(clueQuestion)])
        XCTAssertEqual(session.pendingQuestion?.knownBacks.map(\.name), ["Soldier", "Insect"])
        XCTAssertEqual(session.pendingQuestion?.allowsSingleFaced, false,
                       "every printing of this face is double-sided")

        // The flip empties the band; the question has to survive it.
        XCTAssertEqual(session.handle(.bandCleared), [])
        XCTAssertEqual(session.pendingQuestion, clueQuestion)

        XCTAssertEqual(session.handle(.faceConfirmed(face("TMSH", "12"))),
                       [.dismissPrompt, added(insectClue, .bothFacesCatalogued)])
        XCTAssertNil(session.pendingQuestion)

        // Turning it back to look at the Clue side is the same card.
        _ = session.handle(.bandCleared)
        XCTAssertEqual(session.handle(.faceConfirmed(face("TMSH", "17"))), [.sameCard(insectClue.key)])
    }

    func testSameSideWhileWaitingIsNotAnAnswer() {
        var session = mshSession()
        _ = session.handle(.faceConfirmed(face("TMSH", "17")))

        XCTAssertEqual(session.handle(.faceConfirmed(face("TMSH", "0017"))), [])
        XCTAssertEqual(session.pendingQuestion, clueQuestion)
    }

    func testTappingACandidateAnswersWithoutFlipping() {
        var session = mshSession()
        _ = session.handle(.faceConfirmed(face("TMSH", "17")))

        XCTAssertEqual(session.handle(.choseCandidate(soldierClue.key)),
                       [.dismissPrompt, added(soldierClue, .userChoseCandidate)])
    }

    func testATapOnACardThatIsNotACandidateDoesNothing() {
        var session = mshSession()
        _ = session.handle(.faceConfirmed(face("TMSH", "17")))

        XCTAssertEqual(session.handle(.choseCandidate(merfolkDoombot.key)), [])
        XCTAssertEqual(session.pendingQuestion, clueQuestion)
    }

    /// Without verified coverage a listing still answers the flip by itself:
    /// both faces were read, and one catalogued card carries both.
    func testWithoutVerifiedCoverageACataloguedBackStillAnswersByItself() {
        var session = mshSession(coverage: [:])
        let question = MagicTokenReverseQuestion(face: face("TMSH", "18"), candidates: [merfolkDoombot],
                                                 catalogIsExhaustive: false)

        XCTAssertEqual(session.handle(.faceConfirmed(face("TMSH", "18"))), [.askForReverse(question)])
        XCTAssertEqual(session.pendingQuestion?.allowsSingleFaced, true)
        XCTAssertEqual(session.handle(.faceConfirmed(face("TMSH", "6"))),
                       [.dismissPrompt, added(merfolkDoombot, .bothFacesCatalogued)])
    }

    /// TCGplayer's GRN Guild Kit listing: one Saproling face on three cards.
    func testOneFaceAcrossThreeBacksResolvesFromTheFlip() {
        let voja = card(("TGK1", "8", "Saproling"), ("TGK1", "11", "Voja"))
        let wurm = card(("TGK1", "8", "Saproling"), ("TGK1", "9", "Wurm"))
        let elfKnight = card(("TGK1", "6", "Elf Knight"), ("TGK1", "8", "Saproling"))
        var session = MagicTokenPairingSession(catalog: MagicTokenProductCatalog(
            products: [voja, wurm, elfKnight], coverage: ["TGK1": .complete]
        ))

        _ = session.handle(.faceConfirmed(face("TGK1", "8")))
        XCTAssertEqual(session.pendingQuestion?.knownBacks.map(\.name), ["Elf Knight", "Wurm", "Voja"])
        _ = session.handle(.bandCleared)
        XCTAssertEqual(session.handle(.faceConfirmed(face("TGK1", "11"))),
                       [.dismissPrompt, added(voja, .bothFacesCatalogued)])
    }

    // MARK: - Moving on is never an answer

    func testAnOrdinaryCardMeansThePersonMovedOn() {
        var session = mshSession()
        _ = session.handle(.faceConfirmed(face("TMSH", "17")))

        XCTAssertEqual(session.handle(.otherCardConfirmed), [
            .dismissPrompt,
            .park(MagicTokenParkedFace(face: face("TMSH", "17"), candidates: [soldierClue, insectClue],
                                       unconfirmedReverse: nil))
        ])
        XCTAssertNil(session.pendingQuestion)
    }

    /// Merfolk is never printed with Clue, and the set's coverage is complete,
    /// so this is the next card. Clue is parked; Merfolk is its own card.
    func testAFaceNeverPrintedWithTheQuestionStartsItsOwnCard() {
        var session = mshSession()
        _ = session.handle(.faceConfirmed(face("TMSH", "17")))

        XCTAssertEqual(session.handle(.faceConfirmed(face("TMSH", "6"))), [
            .dismissPrompt,
            .park(MagicTokenParkedFace(face: face("TMSH", "17"), candidates: [soldierClue, insectClue],
                                       unconfirmedReverse: nil)),
            added(merfolkDoombot, .uniqueFace)
        ])
    }

    func testSkipParksWithEverythingLearned() {
        var session = mshSession()
        _ = session.handle(.faceConfirmed(face("TMSH", "17")))

        XCTAssertEqual(session.handle(.skipped), [
            .dismissPrompt,
            .park(MagicTokenParkedFace(face: face("TMSH", "17"), candidates: [soldierClue, insectClue],
                                       unconfirmedReverse: nil))
        ])
        XCTAssertEqual(session.handle(.skipped), [], "nothing left to skip")
    }

    // MARK: - Single-sided

    func testSingleSidedIsNotOfferedWhenEveryPrintingIsDoubleSided() {
        var session = mshSession()
        _ = session.handle(.faceConfirmed(face("TMSH", "17")))

        XCTAssertEqual(session.handle(.declaredSingleFaced), [])
        XCTAssertEqual(session.pendingQuestion, clueQuestion)
    }

    func testDeclaringSingleSidedUsesTheCataloguedSinglePrinting() {
        let singleClue = card(("TMSH", "17", "Clue"))
        var session = MagicTokenPairingSession(catalog: MagicTokenProductCatalog(
            products: [soldierClue, insectClue, singleClue], coverage: ["TMSH": .complete]
        ))

        _ = session.handle(.faceConfirmed(face("TMSH", "17")))
        XCTAssertEqual(session.pendingQuestion?.allowsSingleFaced, true)
        XCTAssertEqual(session.handle(.declaredSingleFaced),
                       [.dismissPrompt, added(singleClue, .userDeclaredSingleFaced)])
    }

    func testDeclaringSingleSidedRecordsAnUncataloguedFaceAlone() {
        var session = uncataloguedSession()
        _ = session.handle(.faceConfirmed(face("TZZZ", "1")))

        XCTAssertEqual(session.handle(.declaredSingleFaced), [
            .dismissPrompt,
            .add(MagicTokenAcquisition(key: key(face("TZZZ", "1")), product: nil, basis: .userDeclaredSingleFaced))
        ])
    }

    // MARK: - Pairs nobody has catalogued

    func testAnUncataloguedBackNeedsOnePersonToSaySo() {
        var session = uncataloguedSession()
        let front = face("TZZZ", "1"), back = face("TZZZ", "2")

        XCTAssertEqual(session.handle(.faceConfirmed(front)), [.askForReverse(openQuestion(front))])
        _ = session.handle(.bandCleared)
        let confirmation = MagicTokenPairConfirmation(face: front, reverse: back)
        XCTAssertEqual(session.handle(.faceConfirmed(back)), [.confirmPair(confirmation)])
        XCTAssertEqual(session.pendingPairConfirmation, confirmation)

        let pair = key(front, back)
        XCTAssertEqual(session.handle(.confirmedPair), [
            .dismissPrompt,
            .add(MagicTokenAcquisition(key: pair, product: nil, basis: .userConfirmedObservedPair))
        ])
        _ = session.handle(.bandCleared)
        XCTAssertEqual(session.handle(.faceConfirmed(front)), [.sameCard(pair)])
    }

    func testTurningTheCardWhileDecidingIsNotAnAnswer() {
        var session = uncataloguedSession()
        _ = session.handle(.faceConfirmed(face("TZZZ", "1")))
        _ = session.handle(.faceConfirmed(face("TZZZ", "2")))

        XCTAssertEqual(session.handle(.faceConfirmed(face("TZZZ", "1"))), [])
        XCTAssertEqual(session.handle(.faceConfirmed(face("TZZZ", "2"))), [])
        XCTAssertNotNil(session.pendingPairConfirmation)
        XCTAssertEqual(session.handle(.choseCandidate(key(face("TZZZ", "1"), face("TZZZ", "2")))), [],
                       "a back has been read; picking a card cannot overrule it")
    }

    func testRejectingThePairParksTheFirstAndStartsTheSecond() {
        var session = uncataloguedSession()
        let front = face("TZZZ", "1"), next = face("TZZZ", "2")
        _ = session.handle(.faceConfirmed(front))
        _ = session.handle(.faceConfirmed(next))

        XCTAssertEqual(session.handle(.rejectedPair), [
            .dismissPrompt,
            .park(MagicTokenParkedFace(face: front, candidates: [], unconfirmedReverse: nil)),
            .askForReverse(openQuestion(next))
        ])
    }

    /// A third face means the person moved on without answering. Both faces
    /// read stay on one Needs Attention entry, so one card never becomes two.
    func testAThirdFaceParksTheFirstWithItsUnconfirmedBack() {
        var session = uncataloguedSession()
        let first = face("TZZZ", "1"), second = face("TZZZ", "2"), third = face("TZZZ", "3")
        _ = session.handle(.faceConfirmed(first))
        _ = session.handle(.faceConfirmed(second))

        XCTAssertEqual(session.handle(.faceConfirmed(third)), [
            .dismissPrompt,
            .park(MagicTokenParkedFace(face: first, candidates: [], unconfirmedReverse: second)),
            .askForReverse(openQuestion(third))
        ])
    }

    func testAnOrdinaryCardWhileDecidingParksBothFacesTogether() {
        var session = uncataloguedSession()
        _ = session.handle(.faceConfirmed(face("TZZZ", "1")))
        _ = session.handle(.faceConfirmed(face("TZZZ", "2")))

        XCTAssertEqual(session.handle(.otherCardConfirmed), [
            .dismissPrompt,
            .park(MagicTokenParkedFace(face: face("TZZZ", "1"), candidates: [], unconfirmedReverse: face("TZZZ", "2")))
        ])
        XCTAssertNil(session.pendingPairConfirmation)
    }
}
