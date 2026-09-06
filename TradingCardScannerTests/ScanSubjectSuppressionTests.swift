import XCTest
@testable import TradingCardScanner

final class ScanSubjectSuppressionTests: XCTestCase {
    private func pokemon(_ number: Int = 223) -> ScanIdentifier {
        let definition = SetCodeMap.definitions["OBF"]!
        return .pokemon(
            setCode: "OBF",
            cardNumber: String(format: "%03d", number),
            printedTotal: definition.officialCount,
            setDefinition: definition
        )
    }

    private func subject(
        grade: String,
        cert: String?
    ) -> ScanSubject {
        ScanSubject(
            identifier: pokemon(),
            slab: GradedSlabEvidence(
                company: .psa,
                grade: CardGrade(value: grade, label: grade == "10" ? "Gem Mint" : "Mint"),
                certificationNumber: cert,
                labelCardText: []
            )
        )
    }

    func testDifferentGradesAndCertificatesHaveDifferentSuppressionKeys() {
        let psa10 = subject(grade: "10", cert: "12345678")
        let psa9 = subject(grade: "9", cert: "12345678")
        let secondPsa10 = subject(grade: "10", cert: "87654321")

        XCTAssertNotEqual(psa10.suppressionKey, psa9.suppressionKey)
        XCTAssertNotEqual(psa10.suppressionKey, secondPsa10.suppressionKey)
        XCTAssertNotEqual(psa10, psa9)
    }

    func testLatchDoesNotSuppressASecondSlabOfTheSamePrinting() {
        var latch = CardLatch()
        let first = subject(grade: "10", cert: "12345678")
        let second = subject(grade: "9", cert: "12345678")

        latch.engage(on: first, at: 0)
        XCTAssertTrue(latch.admits(second))

        guard case let .forwardSubject(observed) = latch.observeSubject(second, at: 0.25) else {
            return XCTFail("a different slab should be forwarded")
        }
        XCTAssertEqual(observed, second)
    }

    func testSameGradeWithoutCertificateRemainsConservativelySuppressed() {
        var latch = CardLatch()
        let first = subject(grade: "10", cert: nil)
        let repeated = subject(grade: "10", cert: nil)

        latch.engage(on: first, at: 0)
        XCTAssertFalse(latch.admits(repeated))
        XCTAssertEqual(latch.observeSubject(repeated, at: 0.25), .holdingLatch)
    }

    func testConsecutiveIdentityKeepsTheSlabAxisSeparateFromTheCatalogCard() {
        let psa10 = ConsecutiveScanIdentity(
            canonicalID: "pokemon:obf-223",
            slabSuppressionFragment: subject(grade: "10", cert: "12345678").slab!.suppressionFragment
        )
        let psa9 = ConsecutiveScanIdentity(
            canonicalID: "pokemon:obf-223",
            slabSuppressionFragment: subject(grade: "9", cert: "12345678").slab!.suppressionFragment
        )
        let samePSA10 = ConsecutiveScanIdentity(
            canonicalID: "pokemon:obf-223",
            slabSuppressionFragment: subject(grade: "10", cert: "12345678").slab!.suppressionFragment
        )

        XCTAssertNotEqual(psa10, psa9)
        XCTAssertEqual(psa10, samePSA10)
    }
}
