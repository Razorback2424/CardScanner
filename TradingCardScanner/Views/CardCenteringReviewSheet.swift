import SwiftUI

struct CardCenteringReviewRequest: Identifiable {
    let id = UUID()
    var candidateID: String? = nil
    var frame: CardCenteringPrecisionFrame? = nil
    var side: CardCenteringPrecisionSide? = nil
}

struct CardCenteringReviewSheet: View {
    @ObservedObject var model: CardCenteringViewModel
    let request: CardCenteringReviewRequest
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var phase = Phase.loading

    private enum Phase {
        case loading
        case ready(CardCenteringViewModel.ReviewSnapshot.Key, CardCenteringReviewRenderer.Output)
        case unavailable(CardCenteringViewModel.ReviewSnapshot.Key)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let snapshot = model.reviewSnapshot() {
                        let value = snapshot.measurement
                        if let id = request.candidateID {
                            comparison(value, candidateID: id)
                            nativeDetail(value, candidateID: id)
                        }
                        Text("The original photo remains your reference. Perspective follows the card-edge guides and preserves the inner frame.")
                            .font(.subheadline).foregroundStyle(.secondary)
                        if case let .ready(key, output) = phase, key == snapshot.key {
                            photoPanels(output, measurement: value)
                        } else if case let .unavailable(key) = phase, key == snapshot.key {
                            ContentUnavailableView("Perspective view unavailable", systemImage: "photo",
                                description: Text("Your original photo and guides are still available. Try adjusting the card edges."))
                        } else {
                            ProgressView("Preparing comparison…").frame(maxWidth: .infinity, minHeight: 180)
                        }
                        if value.canReportRatios { spatialDetails(value) }
                    } else {
                        ContentUnavailableView("Review the guides first", systemImage: "viewfinder",
                            description: Text("Place a valid inner frame inside the card edges to compare the views."))
                    }
                    Text("This view helps you inspect placement; it does not establish boundary accuracy or predict a grade.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                .padding(20)
                .frame(maxWidth: 1000)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(request.candidateID == nil ? "Perspective Review" : "Compare Edge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .task(id: model.reviewSnapshot()?.key) {
            phase = .loading
            guard let snapshot = model.reviewSnapshot() else { return }
            let job = Task.detached(priority: .userInitiated) { try snapshot.render() }
            do {
                let output = try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
                guard !Task.isCancelled, model.matchesReview(snapshot) else { return }
                phase = .ready(snapshot.key, output)
            } catch {
                guard !Task.isCancelled, model.matchesReview(snapshot) else { return }
                phase = .unavailable(snapshot.key)
            }
        }
    }

    @ViewBuilder private func comparison(_ value: CardCenteringMeasurement, candidateID: String) -> some View {
        let sensitivity = value.boundarySensitivity(comparing: [candidateID])
        if let alternative = sensitivity.scenarios.last {
            VStack(alignment: .leading, spacing: 12) {
                Text("Solid: current guide · Dashed: alternative").font(.subheadline.weight(.medium))
                if let reason = alternative.rejectionReason {
                    Label(reason, systemImage: "exclamationmark.triangle").font(.subheadline)
                } else if value.canReportRatios, let current = sensitivity.scenarios.first {
                    resultRow("Current", scenario: current)
                    resultRow("Alternative", scenario: alternative)
                    Text("Only this edge changes. Other uncertainty is unknown.").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Review both frames and choose a reference to reveal ratios.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Button("Use This Edge", systemImage: "checkmark") {
                    model.selectBoundaryCandidate(candidateID)
                    if model.precisionEditReason == nil { dismiss() }
                }
                .buttonStyle(.borderedProminent)
                .frame(minHeight: 44)
                .disabled(alternative.rejectionReason != nil)
                .accessibilityHint("Moves this guide only. You can undo the choice.")
                if let reason = model.precisionEditReason { Text(reason).font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }

    private func resultRow(_ title: String, scenario: CardCenteringSensitivityScenario) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            Text(title).font(.subheadline.weight(.semibold))
            if let lr = scenario.headlineLeftRight, let tb = scenario.headlineTopBottom {
                Text("L/R \(pair(lr)) · T/B \(pair(tb))").font(.subheadline.monospacedDigit())
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func pair(_ value: CardCenteringRatioPair) -> String {
        String(format: "%.1f / %.1f", value.firstPercentage, value.secondPercentage)
    }

    @ViewBuilder private func nativeDetail(_ value: CardCenteringMeasurement, candidateID: String) -> some View {
        if let candidate = value.boundaryCandidates.first(where: { $0.id == candidateID }),
           let selected = value.selectedLines.first(where: { $0.frame == candidate.frame && $0.side == candidate.side }) {
            let a = selected.nativeLine.start, b = selected.nativeLine.end
            let middle = CardCenteringPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
            let p = candidate.nativeLine.start, q = candidate.nativeLine.end
            let dx = q.x - p.x, dy = q.y - p.y
            let t = ((middle.x - p.x) * dx + (middle.y - p.y) * dy) / max(dx * dx + dy * dy, 1e-12)
            let alternative = CardCenteringPoint(x: p.x + t * dx, y: p.y + t * dy)
            let close = hypot(alternative.x - middle.x, alternative.y - middle.y) <= 90
            let centre = close ? CardCenteringPoint(x: (middle.x + alternative.x) / 2, y: (middle.y + alternative.y) / 2) : alternative
            if let crop = model.nativeDetailCrop(in: CGRect(x: centre.x - 64, y: centre.y - 64, width: 128, height: 128)) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(close ? "Original pixels · both lines" : "Original pixels · alternative edge").font(.subheadline.weight(.semibold))
                    CardCenteringNativeDetailImage(image: crop.image, origin: crop.originOrientedNative,
                        pixelWidth: crop.width, pixelHeight: crop.height, guideStart: a, guideEnd: b,
                        guideColor: candidate.frame == .outer ? .red : .cyan,
                        alternative: candidate.nativeLine, supportBands: candidate.sampleBands,
                        excludedBands: candidate.exclusions.compactMap(\.nativeBand))
                        .accessibilityLabel("Original pixels. Solid line is the current \(candidate.side.label.lowercased()) guide; dashed line is the alternative.")
                }
            }
        }
    }

    @ViewBuilder private func photoPanels(_ output: CardCenteringReviewRenderer.Output, measurement: CardCenteringMeasurement) -> some View {
        if dynamicTypeSize.isAccessibilitySize {
            verticalPhotoPanels(output, measurement: measurement)
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 20) {
                    photoPanel("Original with guides", image: output.photo, measurement: measurement, rectified: false)
                        .frame(width: 240)
                    photoPanel("Perspective view", image: output.rectified, measurement: measurement, rectified: true)
                        .frame(width: 240)
                }
                verticalPhotoPanels(output, measurement: measurement)
            }
        }
    }

    private func verticalPhotoPanels(_ output: CardCenteringReviewRenderer.Output, measurement: CardCenteringMeasurement) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            photoPanel("Original with guides", image: output.photo, measurement: measurement, rectified: false)
            photoPanel("Perspective view", image: output.rectified, measurement: measurement, rectified: true)
        }
    }

    private func photoPanel(_ title: String, image: UIImage, measurement: CardCenteringMeasurement, rectified: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            CardCenteringReviewImage(image: image, measurement: measurement, rectified: rectified, candidateID: request.candidateID)
                .accessibilityLabel("\(title). Red outlines the card. Cyan outlines the selected inner reference.\(request.candidateID == nil ? "" : " A dashed yellow line marks the alternative.")")
            if let id = request.candidateID, let candidate = measurement.boundaryCandidates.first(where: { $0.id == id }) {
                if !candidate.sampleBands.isEmpty {
                    Text("Green segments show where samples were recorded for this alternative.").font(.caption).foregroundStyle(.secondary)
                }
                if candidate.exclusions.contains(where: { $0.nativeBand != nil }) {
                    Text("Orange segments were excluded from the fit.").font(.caption).foregroundStyle(.secondary)
                }
                if candidate.sampleBands.isEmpty {
                    Text("Image support was not recorded for this alternative.").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder private func spatialDetails(_ value: CardCenteringMeasurement) -> some View {
        if let spatial = value.spatialMeasurement {
            DisclosureGroup("Variation across the card") {
                VStack(alignment: .leading, spacing: 10) {
                    spatialRow("Left share", axis: spatial.leftRight, positions: "rows")
                    spatialRow("Top share", axis: spatial.topBottom, positions: "columns")
                    Text("These samples show how the borders vary across the selected frame. They are separate from boundary-choice uncertainty.")
                        .font(.footnote).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }
        }
    }

    @ViewBuilder private func spatialRow(_ title: String, axis: CardCenteringSpatialAxis, positions: String) -> some View {
        if let range = axis.ratioRange {
            Text(String(format: "%@: %.1f–%.1f%% across %d of 5 %@", title, range.firstMinimum, range.firstMaximum, axis.samples.count, positions))
                .font(.subheadline)
        } else { Text("\(title): no supported sample \(positions)").font(.subheadline) }
    }
}

/// Both panels use the same point transform. Evidence remains in native
/// coordinates until it is mapped into the current photo and optional view.
struct CardCenteringReviewImage: View {
    let image: UIImage
    let measurement: CardCenteringMeasurement
    let rectified: Bool
    var candidateID: String? = nil

    var body: some View {
        let spatial = measurement.spatialMeasurement
        let size = rectified ? spatial?.rectification.targetSize ?? .init(width: 1, height: 1)
            : CardCenteringSize(width: Double(measurement.imageWidth), height: Double(measurement.imageHeight))
        ZStack {
            Image(uiImage: image).resizable()
            Canvas { context, canvas in
                func screen(_ p: CardCenteringPoint) -> CGPoint {
                    let q = rectified ? spatial?.rectification.rectifiedPoint(from: p) ?? p : p
                    return .init(x: q.x / size.width * canvas.width, y: q.y / size.height * canvas.height)
                }
                func native(_ p: CardCenteringPoint) -> CardCenteringPoint {
                    measurement.coordinateMapping?.workingPoint(fromNative: p) ?? p
                }
                func segment(_ a: CardCenteringPoint, _ b: CardCenteringPoint, color: Color, width: Double = 2, dashed: Bool = false) {
                    var path = Path(); path.move(to: screen(a)); path.addLine(to: screen(b))
                    context.stroke(path, with: .color(.black.opacity(0.75)), style: StrokeStyle(lineWidth: width + 1, dash: dashed ? [6,4] : []))
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, dash: dashed ? [6,4] : []))
                }
                for (quad, color) in [(Optional(measurement.geometryOuterQuad), Color.red), (measurement.geometryInnerQuad, Color.cyan)] {
                    if let quad { for i in 0..<4 { segment(quad.points[i], quad.points[(i+1)%4], color: color) } }
                }
                if let candidate = measurement.boundaryCandidates.first(where: { $0.id == candidateID }) {
                    for band in candidate.sampleBands { segment(native(band.start), native(band.end), color: .green.opacity(0.7), width: 5) }
                    for band in candidate.exclusions.compactMap(\.nativeBand) { segment(native(band.start), native(band.end), color: .orange, width: 5, dashed: true) }
                    segment(native(candidate.nativeLine.start), native(candidate.nativeLine.end), color: .yellow, dashed: true)
                }
            }
        }
        .aspectRatio(size.width / size.height, contentMode: .fit)
        .clipped()
        .frame(maxHeight: 340)
        .accessibilityElement(children: .ignore)
    }
}
