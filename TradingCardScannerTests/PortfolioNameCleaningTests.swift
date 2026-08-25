import XCTest
@testable import TradingCardScanner

/// The product name is what identity, catalog matching and artwork lookup all
/// key on, so residue left in it by an imperfect strip is not cosmetic — it
/// becomes a row that can never resolve.
final class PortfolioNameCleaningTests: XCTestCase {
    private func importedName(
        productName: String,
        cardNumber: String,
        set: String = "Battle Academy 2024"
    ) throws -> String {
        let csv = """
        category,product_name,set,card_number,quantity
        Pokemon,"\(productName)","\(set)",\(cardNumber),1
        """
        let plan = try CollectionCSV.parse(Data(csv.utf8))
        return try XCTUnwrap(plan.entries.first).name
    }

    /// The separator the export uses varies. Every one of these is the same
    /// card, and the number belongs in the number column, not the name.
    func testTrailingCardNumberIsRemovedWhateverTheSeparator() throws {
        let cases: [(String, String)] = [
            ("Basic Lightning Energy - 4", "4"),
            ("Basic Lightning Energy – 4", "4"),      // en dash
            ("Basic Lightning Energy — 4", "4"),      // em dash
            ("Basic Lightning Energy #4", "4"),
            ("Basic Lightning Energy 4", "4"),
            ("Basic Lightning Energy - 004", "4"),    // zero padded in the name
            ("Basic Lightning Energy - 4", "004")     // zero padded in the column
        ]

        for (productName, cardNumber) in cases {
            XCTAssertEqual(
                try importedName(productName: productName, cardNumber: cardNumber),
                "Basic Lightning Energy",
                "failed for \(productName.debugDescription) / \(cardNumber.debugDescription)"
            )
        }
    }

    /// Never remove a trailing token that is not the collector number. A name
    /// that genuinely ends in a number keeps it.
    func testTrailingNumberThatIsNotTheCardNumberIsKept() throws {
        XCTAssertEqual(
            try importedName(productName: "Battle Academy 2024", cardNumber: "4"),
            "Battle Academy 2024"
        )
        XCTAssertEqual(
            try importedName(productName: "Eevee - 25", cardNumber: "4"),
            "Eevee - 25"
        )
    }

    /// Letter-prefixed numbers are the e-card scheme and behave the same way.
    func testSubsetNumberIsRemoved() throws {
        XCTAssertEqual(
            try importedName(productName: "Houndoom - H11", cardNumber: "H11"),
            "Houndoom"
        )
    }
}
