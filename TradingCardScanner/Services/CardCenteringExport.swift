import UIKit

/// Renders a finished centering measurement as one shareable image.
///
/// The export exists because a screenshot loses the thing that makes the
/// measurement worth anything: the guide positions the user tuned by hand, and
/// the numbers those positions produced, in one artifact that still means
/// something months later. So the guides are drawn into the pixels rather than
/// described, and the figures travel with them.
///
/// Everything is sized from the canvas width so a 600px phone photo and a
/// 1200px scan produce the same proportions rather than the same point sizes.
enum CardCenteringExport {
    /// Guide colours, matched to what the on-screen overlay draws so the export
    /// is recognisably the same picture the user was just looking at.
    private enum Palette {
        static let outer = UIColor.systemRed
        static let inner = UIColor.systemCyan
        static let background = UIColor(red: 0.055, green: 0.06, blue: 0.075, alpha: 1)
        static let tile = UIColor(red: 0.11, green: 0.12, blue: 0.145, alpha: 1)
        static let primary = UIColor.white
        static let secondary = UIColor(white: 1, alpha: 0.55)
        static let divider = UIColor(white: 1, alpha: 0.09)
        static let warning = UIColor.systemOrange
    }

    /// Small photos would otherwise render their labels at unreadable sizes.
    private static let minimumCanvasWidth: CGFloat = 900

    /// A filename that still says what the image is in a folder of screenshots.
    ///
    /// The centering figures carry a slash, which a path component cannot, so it
    /// becomes a hyphen rather than being dropped — "52.3-47.7" still reads as
    /// the ratio it came from.
    static func filename(
        for measurement: CardCenteringMeasurement,
        rotationDegrees: Double = 0
    ) -> String {
        let descriptor = [measurement.leftRightCentering, measurement.topBottomCentering]
            .filter { $0 != "—" }
            .map { $0.replacingOccurrences(of: " / ", with: "-") }
            .joined(separator: " ")
        let rotation = abs(rotationDegrees) >= 0.005
            ? String(format: " rotated %.2f°", rotationDegrees)
            : ""
        return descriptor.isEmpty
            ? "Card Centering\(rotation).png"
            : "Card Centering \(descriptor)\(rotation).png"
    }

    static func render(
        image: UIImage,
        measurement: CardCenteringMeasurement,
        rotationDegrees: Double
    ) -> UIImage {
        let canvasWidth = max(CGFloat(measurement.imageWidth), minimumCanvasWidth)
        let unit = canvasWidth / 1000
        let padding = canvasWidth * 0.045
        let imageAspect = CGFloat(measurement.imageHeight) / CGFloat(max(measurement.imageWidth, 1))
        let photoHeight = (canvasWidth * imageAspect).rounded()

        let layout = PanelLayout(canvasWidth: canvasWidth, unit: unit, padding: padding, measurement: measurement)
        let totalHeight = photoHeight + layout.height

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(
            size: CGSize(width: canvasWidth, height: totalHeight),
            format: format
        ).image { context in
            Palette.background.setFill()
            context.fill(CGRect(x: 0, y: 0, width: canvasWidth, height: totalHeight))

            let photoRect = CGRect(x: 0, y: 0, width: canvasWidth, height: photoHeight)
            context.cgContext.saveGState()
            context.cgContext.translateBy(x: photoRect.midX, y: photoRect.midY)
            context.cgContext.rotate(by: CGFloat(rotationDegrees * .pi / 180))
            image.draw(in: CGRect(
                x: -photoRect.width / 2,
                y: -photoRect.height / 2,
                width: photoRect.width,
                height: photoRect.height
            ))
            context.cgContext.restoreGState()
            drawGuides(measurement: measurement, in: photoRect, unit: unit, context: context.cgContext)

            Palette.divider.setFill()
            context.fill(CGRect(x: 0, y: photoHeight, width: canvasWidth, height: max(1, unit)))

            layout.draw(measurement: measurement, rotationDegrees: rotationDegrees, topEdge: photoHeight)
        }
    }

    // MARK: - Guides

    private static func drawGuides(
        measurement: CardCenteringMeasurement,
        in rect: CGRect,
        unit: CGFloat,
        context: CGContext
    ) {
        let xScale = rect.width / CGFloat(max(measurement.imageWidth, 1))
        let yScale = rect.height / CGFloat(max(measurement.imageHeight, 1))
        let lineWidth = max(2, unit * 3)

        func trace(_ edges: CardCenteringEdges) {
            for x in [edges.left, edges.right] {
                let position = rect.minX + CGFloat(x) * xScale
                context.move(to: CGPoint(x: position, y: rect.minY))
                context.addLine(to: CGPoint(x: position, y: rect.maxY))
            }
            for y in [edges.top, edges.bottom] {
                let position = rect.minY + CGFloat(y) * yScale
                context.move(to: CGPoint(x: rect.minX, y: position))
                context.addLine(to: CGPoint(x: rect.maxX, y: position))
            }
        }

        // Drawn outer-first so the inner frame stays legible where the two run
        // close together on a badly cut card — which is exactly the case the
        // user is most likely to be exporting.
        for (edges, colour) in [(measurement.outer, Palette.outer), (measurement.inner, Palette.inner)] {
            // A dark casing under each line. Card art is arbitrary, and a red
            // guide laid over red art is invisible in the one export the user
            // most needs to read — the casing costs a pixel either side and
            // makes both colours legible over anything.
            context.setStrokeColor(UIColor.black.withAlphaComponent(0.45).cgColor)
            context.setLineWidth(lineWidth * 2.4)
            context.setLineCap(.butt)
            trace(edges)
            context.strokePath()

            context.setStrokeColor(colour.cgColor)
            context.setLineWidth(lineWidth)
            trace(edges)
            context.strokePath()
        }
    }

    // MARK: - Panel

    /// Measures the panel before anything is drawn, so the canvas can be sized
    /// to its contents rather than to a guess that clips a long warning.
    private struct PanelLayout {
        let canvasWidth: CGFloat
        let unit: CGFloat
        let padding: CGFloat
        let warningText: String?
        let warningHeight: CGFloat

        private var headerHeight: CGFloat { unit * 34 }
        private var metricTileHeight: CGFloat { unit * 150 }
        private var borderTileHeight: CGFloat { unit * 96 }
        private var legendHeight: CGFloat { unit * 34 }
        private var gap: CGFloat { unit * 26 }

        init(canvasWidth: CGFloat, unit: CGFloat, padding: CGFloat, measurement: CardCenteringMeasurement) {
            self.canvasWidth = canvasWidth
            self.unit = unit
            self.padding = padding
            let text = measurement.warnings.isEmpty
                ? nil
                : measurement.warnings.joined(separator: " ")
            warningText = text
            if let text {
                let width = canvasWidth - padding * 2 - unit * 46
                let bounding = (text as NSString).boundingRect(
                    with: CGSize(width: width, height: .greatestFiniteMagnitude),
                    options: [.usesLineFragmentOrigin, .usesFontLeading],
                    attributes: [.font: UIFont.systemFont(ofSize: unit * 26, weight: .medium)],
                    context: nil
                )
                warningHeight = ceil(bounding.height) + unit * 34
            } else {
                warningHeight = 0
            }
        }

        var height: CGFloat {
            padding + headerHeight + gap + metricTileHeight + gap + borderTileHeight
                + gap + legendHeight
                + (warningText == nil ? 0 : gap + warningHeight)
                + padding
        }

        func draw(measurement: CardCenteringMeasurement, rotationDegrees: Double, topEdge: CGFloat) {
            var y = topEdge + padding
            let contentWidth = canvasWidth - padding * 2

            drawHeader(measurement: measurement, rotationDegrees: rotationDegrees, y: y, width: contentWidth)
            y += headerHeight + gap

            let tileGap = unit * 18
            let metricWidth = (contentWidth - tileGap) / 2
            drawMetricTile(
                title: "LEFT / RIGHT",
                value: measurement.leftRightCentering,
                rect: CGRect(x: padding, y: y, width: metricWidth, height: metricTileHeight)
            )
            drawMetricTile(
                title: "TOP / BOTTOM",
                value: measurement.topBottomCentering,
                rect: CGRect(x: padding + metricWidth + tileGap, y: y, width: metricWidth, height: metricTileHeight)
            )
            y += metricTileHeight + gap

            let borders = [
                ("LEFT", measurement.leftBorder),
                ("RIGHT", measurement.rightBorder),
                ("TOP", measurement.topBorder),
                ("BOTTOM", measurement.bottomBorder)
            ]
            let borderGap = unit * 12
            let borderWidth = (contentWidth - borderGap * CGFloat(borders.count - 1)) / CGFloat(borders.count)
            for (index, border) in borders.enumerated() {
                drawBorderTile(
                    title: border.0,
                    value: border.1,
                    rect: CGRect(
                        x: padding + (borderWidth + borderGap) * CGFloat(index),
                        y: y,
                        width: borderWidth,
                        height: borderTileHeight
                    )
                )
            }
            y += borderTileHeight + gap

            drawLegend(y: y)
            y += legendHeight

            if let warningText {
                y += gap
                drawWarning(warningText, y: y, width: contentWidth)
            }
        }

        private func drawHeader(
            measurement: CardCenteringMeasurement,
            rotationDegrees: Double,
            y: CGFloat,
            width: CGFloat
        ) {
            let title = NSAttributedString(
                string: "CARD CENTERING",
                attributes: [
                    .font: UIFont.systemFont(ofSize: unit * 27, weight: .heavy),
                    .foregroundColor: Palette.primary,
                    .kern: unit * 2.4
                ]
            )
            title.draw(at: CGPoint(x: padding, y: y))

            // Provenance: the pixel grid the numbers were measured against, and
            // any rotation applied first. Without these the figures cannot be
            // reproduced from the original photo.
            var detail = "\(measurement.imageWidth) × \(measurement.imageHeight) px"
            if abs(rotationDegrees) >= 0.005 {
                detail += String(format: "   ·   rotated %.2f°", rotationDegrees)
            }
            let attributed = NSAttributedString(
                string: detail,
                attributes: [
                    .font: UIFont.monospacedDigitSystemFont(ofSize: unit * 24, weight: .medium),
                    .foregroundColor: Palette.secondary
                ]
            )
            let size = attributed.size()
            attributed.draw(at: CGPoint(x: padding + width - size.width, y: y + unit * 3))
        }

        private func drawMetricTile(title: String, value: String, rect: CGRect) {
            fillTile(rect)
            draw(
                title,
                font: .systemFont(ofSize: unit * 24, weight: .semibold),
                colour: Palette.secondary,
                kern: unit * 1.6,
                centeredIn: rect,
                offsetY: unit * 30
            )
            draw(
                value,
                font: .monospacedDigitSystemFont(ofSize: unit * 62, weight: .bold),
                colour: Palette.primary,
                kern: 0,
                centeredIn: rect,
                offsetY: unit * 68
            )
        }

        private func drawBorderTile(title: String, value: Int, rect: CGRect) {
            fillTile(rect)
            draw(
                title,
                font: .systemFont(ofSize: unit * 20, weight: .semibold),
                colour: Palette.secondary,
                kern: unit * 1.2,
                centeredIn: rect,
                offsetY: unit * 20
            )
            draw(
                "\(value) px",
                font: .monospacedDigitSystemFont(ofSize: unit * 34, weight: .semibold),
                colour: Palette.primary,
                kern: 0,
                centeredIn: rect,
                offsetY: unit * 48
            )
        }

        private func drawLegend(y: CGFloat) {
            var x = padding
            for (colour, label) in [(Palette.outer, "Card edge"), (Palette.inner, "Inner frame")] {
                let swatchHeight = max(2, unit * 5)
                let swatchWidth = unit * 40
                colour.setFill()
                UIBezierPath(
                    roundedRect: CGRect(
                        x: x,
                        y: y + unit * 12,
                        width: swatchWidth,
                        height: swatchHeight
                    ),
                    cornerRadius: swatchHeight / 2
                ).fill()
                x += swatchWidth + unit * 12

                let attributed = NSAttributedString(
                    string: label,
                    attributes: [
                        .font: UIFont.systemFont(ofSize: unit * 24, weight: .medium),
                        .foregroundColor: Palette.secondary
                    ]
                )
                attributed.draw(at: CGPoint(x: x, y: y))
                x += attributed.size().width + unit * 46
            }
        }

        private func drawWarning(_ text: String, y: CGFloat, width: CGFloat) {
            let rect = CGRect(x: padding, y: y, width: width, height: warningHeight)
            Palette.warning.withAlphaComponent(0.14).setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: unit * 16).fill()

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            NSAttributedString(
                string: text,
                attributes: [
                    .font: UIFont.systemFont(ofSize: unit * 26, weight: .medium),
                    .foregroundColor: Palette.warning,
                    .paragraphStyle: paragraph
                ]
            ).draw(
                with: rect.insetBy(dx: unit * 23, dy: unit * 17),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
        }

        private func fillTile(_ rect: CGRect) {
            Palette.tile.setFill()
            UIBezierPath(roundedRect: rect, cornerRadius: unit * 20).fill()
        }

        private func draw(
            _ string: String,
            font: UIFont,
            colour: UIColor,
            kern: CGFloat,
            centeredIn rect: CGRect,
            offsetY: CGFloat
        ) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            var attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: colour,
                .paragraphStyle: paragraph
            ]
            if kern > 0 { attributes[.kern] = kern }
            NSAttributedString(string: string, attributes: attributes).draw(
                with: CGRect(
                    x: rect.minX,
                    y: rect.minY + offsetY,
                    width: rect.width,
                    height: rect.height
                ),
                options: [.usesLineFragmentOrigin, .usesFontLeading],
                context: nil
            )
        }
    }
}
