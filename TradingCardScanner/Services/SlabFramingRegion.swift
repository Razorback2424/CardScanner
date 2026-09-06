import CoreGraphics

/// Geometry for the outer slab and the card window inside it.
///
/// Values in `Geometry` are normalized to the slab itself and use Vision's
/// bottom-left origin. The camera-facing rectangle is derived separately from
/// the source image aspect ratio, just as `CardFramingRegion` does for a raw
/// card. Keeping these values here makes the slab guide and every Vision ROI
/// share one calibration surface.
enum SlabFramingRegion {
    struct Geometry: Equatable, Sendable {
        let slabAspect: CGFloat
        let cardWindow: CGRect
        let labelBand: CGRect
        let footerBand: CGRect
        let titleBand: CGRect
    }

    /// The common physical slab width/height ratio. The known graders use
    /// slightly different moulds, but those differences are below the useful
    /// precision of a live camera guide; the per-company geometry still gives
    /// the label and card-window bands their own calibration hook.
    private static let defaultSlabAspect: CGFloat = 3.25 / 5.25
    private static let sourceImageAspectRatio: CGFloat = 9.0 / 16.0
    private static let normalizedSlabWidth: CGFloat = 0.72

    /// A generic envelope is intentionally conservative. It is used for the
    /// first label pass, before any company has earned confirmation.
    private static let genericGeometry = Geometry(
        slabAspect: defaultSlabAspect,
        cardWindow: CGRect(x: 0.11, y: 0.10, width: 0.78, height: 0.68),
        labelBand: CGRect(x: 0.06, y: 0.79, width: 0.88, height: 0.20),
        footerBand: CGRect(x: 0.13, y: 0.115, width: 0.74, height: 0.105),
        titleBand: CGRect(x: 0.135, y: 0.625, width: 0.73, height: 0.115)
    )

    static func geometry(for company: GradingCompany?) -> Geometry {
        // Keep the selector explicit so a future label revision can change a
        // single company's bands without changing the parser or camera loop.
        switch company {
        case .none:
            return genericGeometry
        case .psa, .bgs, .cgc, .sgc, .bccg, .bvg, .tag:
            return Geometry(
                slabAspect: defaultSlabAspect,
                cardWindow: CGRect(x: 0.115, y: 0.105, width: 0.77, height: 0.666),
                labelBand: CGRect(x: 0.07, y: 0.786, width: 0.86, height: 0.199),
                footerBand: CGRect(x: 0.13425, y: 0.11499, width: 0.7315, height: 0.0999),
                titleBand: CGRect(x: 0.14195, y: 0.63014, width: 0.7161, height: 0.10656)
            )
        }
    }

    /// The outer slab guide in full-frame Vision coordinates.
    static func slabVisionRect(for company: GradingCompany? = nil) -> CGRect {
        let geometry = geometry(for: company)
        let height = normalizedSlabWidth * sourceImageAspectRatio / geometry.slabAspect
        return CGRect(
            x: (1 - normalizedSlabWidth) / 2,
            y: (1 - height) / 2,
            width: normalizedSlabWidth,
            height: height
        )
    }

    static func visionRect(
        for slabRelativeRect: CGRect,
        company: GradingCompany? = nil
    ) -> CGRect {
        let slabRect = slabVisionRect(for: company)
        return CGRect(
            x: slabRect.minX + slabRelativeRect.minX * slabRect.width,
            y: slabRect.minY + slabRelativeRect.minY * slabRect.height,
            width: slabRelativeRect.width * slabRect.width,
            height: slabRelativeRect.height * slabRect.height
        )
    }

    static func cardWindowVisionRect(for company: GradingCompany? = nil) -> CGRect {
        visionRect(for: geometry(for: company).cardWindow, company: company)
    }

    static func labelVisionRect(for company: GradingCompany? = nil) -> CGRect {
        visionRect(for: geometry(for: company).labelBand, company: company)
    }

    static func footerVisionRect(for company: GradingCompany? = nil) -> CGRect {
        visionRect(for: geometry(for: company).footerBand, company: company)
    }

    static func titleVisionRect(for company: GradingCompany? = nil) -> CGRect {
        visionRect(for: geometry(for: company).titleBand, company: company)
    }
}
