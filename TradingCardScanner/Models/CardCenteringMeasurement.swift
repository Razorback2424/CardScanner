import Foundation

struct CardCenteringEdges: Equatable {
    var left: Int
    var top: Int
    var right: Int
    var bottom: Int
}

struct CardCenteringMeasurement: Equatable {
    var imageWidth: Int
    var imageHeight: Int
    var outer: CardCenteringEdges
    var inner: CardCenteringEdges
    var warnings: [String]

    var leftBorder: Int { inner.left - outer.left }
    var rightBorder: Int { outer.right - inner.right }
    var topBorder: Int { inner.top - outer.top }
    var bottomBorder: Int { outer.bottom - inner.bottom }

    var leftRightCentering: String {
        Self.centeringString(leftBorder, rightBorder)
    }

    var topBottomCentering: String {
        Self.centeringString(topBorder, bottomBorder)
    }

    mutating func refreshWarnings() {
        var updated: [String] = []
        if !(outer.left < inner.left && inner.left < inner.right && inner.right < outer.right) {
            updated.append("Check the left and right guide positions.")
        }
        if !(outer.top < inner.top && inner.top < inner.bottom && inner.bottom < outer.bottom) {
            updated.append("Check the top and bottom guide positions.")
        }
        if [leftBorder, rightBorder, topBorder, bottomBorder].contains(where: { $0 <= 0 }) {
            updated.append("Each inner guide must be inside the card edge.")
        }
        warnings = updated
    }

    private static func centeringString(_ first: Int, _ second: Int) -> String {
        let total = first + second
        guard total > 0 else { return "—" }
        return String(format: "%.1f / %.1f", 100 * Double(first) / Double(total), 100 * Double(second) / Double(total))
    }
}
