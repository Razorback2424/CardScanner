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

    func testCertlessDifferentSlabsNeedOneSharedNormalizedLabelLine() {
        var different = SlabEvidenceConfirmationWindow(matchesRequired: 2, windowSize: 4)
        XCTAssertNil(different.observe(evidence(certificationNumber: nil, text: ["CHARIZARD"])))
        XCTAssertNil(different.observe(evidence(certificationNumber: nil, text: ["PIKACHU"])))

        var same = SlabEvidenceConfirmationWindow(matchesRequired: 2, windowSize: 4)
        XCTAssertNil(same.observe(evidence(certificationNumber: nil, text: ["Charizard-Holo"])))
        let latest = evidence(certificationNumber: nil, text: ["CHARIZARD HOLO", "glare"])
        XCTAssertNotNil(same.observe(latest))
    }

    func testCertlessEmptyLabelTextConfirmsFromTheSharedSuppressionFragment() {
        var window = SlabEvidenceConfirmationWindow(matchesRequired: 2, windowSize: 4)
        let empty = evidence(certificationNumber: nil, text: [])

        XCTAssertNil(window.observe(empty))
        XCTAssertEqual(window.observe(empty), empty)
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
