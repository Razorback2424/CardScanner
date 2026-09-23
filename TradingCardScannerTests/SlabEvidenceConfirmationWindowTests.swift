import XCTest
@testable import TradingCardScanner

final class SlabEvidenceConfirmationWindowTests: XCTestCase {
    func testSameIdentityWithDifferentLeftoverTextConfirms() {
        var window = SlabEvidenceConfirmationWindow(matchesRequired: 2, windowSize: 4)
        let first = evidence(certificationNumber: "12345678", text: ["CHARIZARD HOLO"])
        let latest = evidence(certificationNumber: "12345678", text: ["CHARIZARD H0LO"])

        XCTAssertNil(window.observe(first))
        XCTAssertNotNil(window.observe(latest))
    }

    func testDifferentCertificatesDoNotConfirm() {
        var window = SlabEvidenceConfirmationWindow(matchesRequired: 2, windowSize: 4)

        XCTAssertNil(window.observe(evidence(certificationNumber: "12345678", text: ["A"])))
        XCTAssertNil(window.observe(evidence(certificationNumber: "87654321", text: ["A"])))
    }

    func testCertificateMissOnOneReadCanConfirmWithMatchingCardName() {
        var window = SlabEvidenceConfirmationWindow(matchesRequired: 2, windowSize: 4)

        XCTAssertNil(window.observe(evidence(certificationNumber: nil, text: ["CHARIZARD HOLO"])))
        XCTAssertEqual(
            window.observe(evidence(certificationNumber: "12345678", text: ["CHARIZARD H0LO"]))?.certificationNumber,
            "12345678"
        )
    }

    func testCertificateMissStillConfirmsMatchingGradeIdentityWithDifferentText() {
        var window = SlabEvidenceConfirmationWindow(matchesRequired: 2, windowSize: 4)

        XCTAssertNil(window.observe(evidence(certificationNumber: nil, text: ["CHARIZARD"])))
        XCTAssertEqual(
            window.observe(evidence(certificationNumber: "12345678", text: ["PIKACHU"]))?.certificationNumber,
            "12345678"
        )
    }

    func testTwoMatchingCertlessReadsConfirmWithoutCardNameOCR() {
        var window = SlabEvidenceConfirmationWindow(matchesRequired: 2, windowSize: 4)

        XCTAssertNil(window.observe(evidence(certificationNumber: nil, text: [])))
        XCTAssertNotNil(window.observe(evidence(certificationNumber: nil, text: [])))
    }

    func testWindowEvictionPreventsAnOldObservationFromConfirming() {
        var window = SlabEvidenceConfirmationWindow(matchesRequired: 2, windowSize: 3)
        let first = evidence(certificationNumber: "11111111", text: ["A"])

        XCTAssertNil(window.observe(first))
        XCTAssertNil(window.observe(evidence(certificationNumber: "22222222", text: ["B"])))
        XCTAssertNil(window.observe(evidence(certificationNumber: "33333333", text: ["C"])))
        XCTAssertNil(window.observe(first))
    }

    func testConfirmationResetsTheWindow() {
        var window = SlabEvidenceConfirmationWindow(matchesRequired: 2, windowSize: 4)
        let first = evidence(certificationNumber: "12345678", text: ["A"])

        XCTAssertNil(window.observe(first))
        XCTAssertEqual(window.observe(first), first)
        XCTAssertNil(window.observe(first))
    }

    func testNilObservationsDoNotPreventLaterConfirmation() {
        var window = SlabEvidenceConfirmationWindow(matchesRequired: 2, windowSize: 4)
        let first = evidence(certificationNumber: "12345678", text: ["A"])

        XCTAssertNil(window.observe(nil))
        XCTAssertNil(window.observe(first))
        XCTAssertEqual(window.observe(first), first)
    }

    func testCertlessReadsWithSameGradeIdentityIgnoreChangingCardText() {
        var window = SlabEvidenceConfirmationWindow(matchesRequired: 2, windowSize: 4)
        XCTAssertNil(window.observe(evidence(certificationNumber: nil, text: ["CHARIZARD"])))
        XCTAssertNotNil(window.observe(evidence(certificationNumber: nil, text: ["PIKACHU"])))
    }

    func testCertlessEmptyLabelTextCanConfirmOnMatchingGradeIdentity() {
        var window = SlabEvidenceConfirmationWindow(matchesRequired: 2, windowSize: 4)
        let empty = evidence(certificationNumber: nil, text: [])

        XCTAssertNil(window.observe(empty))
        XCTAssertNotNil(window.observe(empty))
    }

    func testWindowReturnsTheMostCompleteMatchingRead() {
        var window = SlabEvidenceConfirmationWindow(matchesRequired: 2, windowSize: 4)
        let partial = GradedSlabEvidence(
            company: .psa,
            grade: CardGrade(value: nil, label: "Gem Mint"),
            certificationNumber: nil,
            labelCardText: ["CHARIZARD"]
        )
        let complete = GradedSlabEvidence(
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            certificationNumber: "12345678",
            labelCardText: ["CHARIZARD", "HOLO"]
        )

        XCTAssertNil(window.observe(partial))
        XCTAssertEqual(window.observe(complete), complete)
    }

    func testLabelScheduleUsesFooterGateAndCertifiedCopyCadence() {
        XCTAssertFalse(SlabLabelSchedule.shouldReadLabel(
            mode: .raw,
            footerMatched: true,
            hasEvidence: false,
            certKnown: false,
            lastLabelAt: nil,
            now: 0
        ))
        XCTAssertTrue(SlabLabelSchedule.shouldReadLabel(
            mode: .slab,
            footerMatched: true,
            hasEvidence: false,
            certKnown: false,
            lastLabelAt: 0,
            now: 0.5
        ))
        XCTAssertFalse(SlabLabelSchedule.shouldReadLabel(
            mode: .slab,
            footerMatched: true,
            hasEvidence: true,
            certKnown: false,
            lastLabelAt: 1,
            now: 1.49
        ))
        XCTAssertTrue(SlabLabelSchedule.shouldReadLabel(
            mode: .slab,
            footerMatched: true,
            hasEvidence: true,
            certKnown: false,
            lastLabelAt: 1,
            now: 1.5
        ))
        XCTAssertFalse(SlabLabelSchedule.shouldReadLabel(
            mode: .slab,
            footerMatched: true,
            hasEvidence: true,
            certKnown: true,
            lastLabelAt: 1,
            now: 2.99
        ))
        XCTAssertTrue(SlabLabelSchedule.shouldReadLabel(
            mode: .slab,
            footerMatched: true,
            hasEvidence: true,
            certKnown: true,
            lastLabelAt: 1,
            now: 3
        ))
        XCTAssertFalse(SlabLabelSchedule.shouldReadLabel(
            mode: .slab,
            footerMatched: false,
            hasEvidence: false,
            certKnown: false,
            lastLabelAt: nil,
            now: 10
        ))
    }

    func testCertificateRefinementIgnoresUnstableCardTextButRequiresExactGrade() {
        let original = GradedSlabEvidence(
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            certificationNumber: nil,
            labelCardText: ["CHARIZARD"]
        )
        let certified = GradedSlabEvidence(
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            certificationNumber: "12345678",
            labelCardText: ["PIKACHU"]
        )
        let wrongGrade = GradedSlabEvidence(
            company: .psa,
            grade: CardGrade(value: "9", label: "Mint"),
            certificationNumber: "12345678",
            labelCardText: ["CHARIZARD"]
        )

        XCTAssertTrue(SlabEvidenceConfirmationWindow.isCertificateRefinement(from: original, to: certified))
        XCTAssertFalse(SlabEvidenceConfirmationWindow.isCertificateRefinement(from: original, to: wrongGrade))
        XCTAssertTrue(SlabEvidenceConfirmationWindow.isDistinctCertifiedCopy(from: certified, to: GradedSlabEvidence(
            company: .psa,
            grade: certified.grade,
            certificationNumber: "87654321",
            labelCardText: []
        )))
        XCTAssertFalse(SlabEvidenceConfirmationWindow.isDistinctCertifiedCopy(from: certified, to: wrongGrade))
    }

    private func evidence(certificationNumber: String?, text: [String]) -> GradedSlabEvidence {
        GradedSlabEvidence(
            company: .psa,
            grade: CardGrade(value: "10", label: "Gem Mint"),
            certificationNumber: certificationNumber,
            labelCardText: text
        )
    }
}
