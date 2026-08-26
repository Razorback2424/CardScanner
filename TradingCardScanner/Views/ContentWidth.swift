import SwiftUI

/// How wide a stretch of content is allowed to get before it stops being readable.
///
/// An iPad window can be any width from a narrow slice to thirteen inches, and the
/// widths that suit a paragraph, a form row and a grid of card art are not the same
/// number. Naming the three cases keeps the choice a design decision made per screen
/// rather than a magic number repeated per view.
enum ContentWidthLimit {
    /// Prose, forms, summary rows, single-column detail bodies. Roughly the system's
    /// readable content width — beyond this a line of text is tiring to track back.
    case standard
    /// Grids and dashboards, where more columns is a genuine improvement rather than
    /// just a longer line.
    case wide
    /// Card artwork and other imagery that gains nothing from being enlarged past
    /// the size it is actually printed at.
    case artwork

    var points: CGFloat {
        switch self {
        case .standard: return 700
        case .wide: return 1100
        case .artwork: return 460
        }
    }
}

extension View {
    /// Caps this content's width and centres it in the space available.
    ///
    /// Deliberately expressed as a maximum rather than a size-class branch: the same
    /// iPad can present this view at phone width and at full screen without the
    /// device or its orientation changing, so the only question worth asking is how
    /// much room there is right now.
    func contentWidthLimit(_ limit: ContentWidthLimit = .standard) -> some View {
        frame(maxWidth: limit.points)
            .frame(maxWidth: .infinity)
    }
}
