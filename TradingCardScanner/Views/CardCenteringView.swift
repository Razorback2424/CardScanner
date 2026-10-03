import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class CardCenteringViewModel: ObservableObject {
    @Published var selectedPhoto: PhotosPickerItem?
    @Published var image: UIImage?
    @Published private(set) var imageRevision = 0
    @Published var measurement: CardCenteringMeasurement?
    @Published var rotationDegrees = 0.0
    @Published var isAnalyzing = false
    @Published var errorMessage: String?

    private var sourceData: Data?
    private var loadGeneration = 0
    private var analysisGeneration = 0

#if DEBUG
    private var isSyntheticDebugFixture = false

    private var debugState: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ui_debug_state"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    private func applySyntheticDebugState() {
        guard isSyntheticDebugFixture, let state = debugState, let analysis = measurement else { return }
        var fixture = CardCenteringMeasurement(imageWidth: 360, imageHeight: 504,
            outerQuad: .axisAligned(.init(left: 38, top: 34, right: 322, bottom: 470)),
            innerQuad: state == "missing" ? nil : .axisAligned(.init(left: 64, top: 60, right: 296, bottom: 444)),
            warnings: [], innerReference: state == "missing" ? .none : .printedBorder,
            confidence: .manualConfirmationRequired(preserving: analysis.confidence, reason: "Review frames"))
        if state == "confirmed" || state == "rotated" || state == "zoom" { fixture.confirmFrames() }
        if state == "invalid" { fixture.setManualInnerEdge(\.left, to: 20) }
        if state == "rotated" || state == "zoom" { rotationDegrees = 7 }
        measurement = fixture
    }

    private struct DebugAnalysisMarker: Codable {
        let state: String
        let imageWidth: Int?
        let imageHeight: Int?
        let outerQuad: CardCenteringQuad?
        let innerQuad: CardCenteringQuad?
        let innerReference: CardCenteringInnerReference?
        let confidence: CardCenteringConfidence?
        let appliedRotationDegrees: Double?
        let detectedSkewDegrees: Double?
        let reason: String?
        let screenScale: Double
        let coordinateMapping: CardCenteringCoordinateMapping?
        let leftRightCentering: String?
        let topBottomCentering: String?
    }

    private var debugSettledMarkerURL: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ui_debug_ready_path"),
              arguments.indices.contains(index + 1) else { return nil }
        return URL(fileURLWithPath: arguments[index + 1])
    }

    private func clearDebugSettledMarker() {
        guard let url = debugSettledMarkerURL else { return }
        try? FileManager.default.removeItem(at: url)
    }

    private func markDebugAnalysisSettled(
        _ measurement: CardCenteringMeasurement? = nil,
        appliedRotationDegrees: Double? = nil,
        detectedSkewDegrees: Double? = nil
    ) {
        guard let url = debugSettledMarkerURL else { return }
        let marker = DebugAnalysisMarker(
            state: measurement == nil ? "error" : (measurement?.isDeclined == true ? "declined" : "settled"),
            imageWidth: measurement?.imageWidth,
            imageHeight: measurement?.imageHeight,
            outerQuad: measurement?.geometryOuterQuad,
            innerQuad: measurement?.geometryInnerQuad,
            innerReference: measurement?.innerReference,
            confidence: measurement?.confidence,
            appliedRotationDegrees: measurement == nil ? nil : (appliedRotationDegrees ?? rotationDegrees),
            detectedSkewDegrees: measurement == nil ? nil : detectedSkewDegrees,
            reason: measurement?.declineReason,
            screenScale: Double(UIScreen.main.scale),
            coordinateMapping: measurement?.coordinateMapping,
            leftRightCentering: measurement?.leftRightCentering,
            topBottomCentering: measurement?.topBottomCentering
        )
        guard let data = try? JSONEncoder().encode(marker) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func recordDebugImageFrame(_ frame: CGRect) {
        guard let url = debugSettledMarkerURL,
              let data = try? Data(contentsOf: url),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        object["presentedImageFrame"] = [
            "x": frame.origin.x,
            "y": frame.origin.y,
            "width": frame.width,
            "height": frame.height
        ]
        guard let updated = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        try? updated.write(to: url, options: .atomic)
    }
#endif

    func loadSelectedPhoto() async {
        guard let selectedPhoto else { return }
        await loadImageData {
            guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else {
                throw CardCenteringAnalyzerError.unreadableImage
            }
            return data
        }
    }

    func loadCapturedPhoto(_ data: Data) {
        loadImageData(data)
    }

    func loadFile(at url: URL) async {
        await loadImageData {
            try await Task.detached(priority: .userInitiated) {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess { url.stopAccessingSecurityScopedResource() }
                }
                return try Data(contentsOf: url, options: .mappedIfSafe)
            }.value
        }
    }

    /// Close approval as soon as an input starts loading, before any suspension.
    /// One generation owns loading and analysis, including failure and cancellation.
    func loadImageData(using loader: () async throws -> Data) async {
        let requestID = beginImageLoad()
        do {
            let data = try await loader()
            guard requestID == loadGeneration else { return }
            guard !Task.isCancelled else {
                isAnalyzing = false
                return
            }
            acceptImageData(data)
        } catch {
            guard requestID == loadGeneration else { return }
            isAnalyzing = false
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }

    private func beginImageLoad() -> Int {
        loadGeneration &+= 1
        analysisGeneration &+= 1
        imageRevision &+= 1
        measurement = nil
        isAnalyzing = true
        errorMessage = nil
        rotationDegrees = 0
#if DEBUG
        clearDebugSettledMarker()
#endif
        return loadGeneration
    }

    private func loadImageData(_ data: Data) {
        _ = beginImageLoad()
        acceptImageData(data)
    }

    private func acceptImageData(_ data: Data) {
        sourceData = data
        selectedPhoto = nil
        analyze(data, rotationDegrees: 0)
    }

    func adjustRotation(by amount: Double) {
        guard amount.isFinite else { return }
        let adjusted = ((rotationDegrees + amount) * 100).rounded() / 100
        rotationDegrees = min(45, max(-45, adjusted))
    }

    func resetRotation() {
        rotationDegrees = 0
    }

    func updateOuter(
        _ keyPath: WritableKeyPath<CardCenteringEdges, Int>,
        to value: Int,
        within range: ClosedRange<Int>
    ) {
        guard var measurement else { return }
        measurement.setManualOuterEdge(
            keyPath,
            to: min(range.upperBound, max(range.lowerBound, value))
        )
        measurement.refreshWarnings()
        self.measurement = measurement
    }

    func updateInner(
        _ keyPath: WritableKeyPath<CardCenteringEdges, Int>,
        to value: Int,
        within range: ClosedRange<Int>
    ) {
        guard var measurement else { return }
        measurement.setManualInnerEdge(
            keyPath,
            to: min(range.upperBound, max(range.lowerBound, value))
        )
        measurement.refreshWarnings()
        self.measurement = measurement
    }

    func confirmFrames() {
        guard var measurement, measurement.confirmFrames() else { return }
        self.measurement = measurement
    }

#if DEBUG
    /// Gives the screenshot route a stable, local image so the centering controls
    /// can be checked without a Photos permission prompt or a camera session.
    func loadDebugFixtureIfNeeded() {
        guard sourceData == nil else { return }

        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-ui_debug_fixture_path"),
           arguments.indices.contains(index + 1),
           let data = try? Data(contentsOf: URL(fileURLWithPath: arguments[index + 1])) {
            loadImageData(data)
            return
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: CGSize(width: 360, height: 504), format: format).image { context in
            UIColor(white: 0.94, alpha: 1).setFill()
            context.fill(CGRect(x: 0, y: 0, width: 360, height: 504))

            UIColor(red: 0.10, green: 0.20, blue: 0.38, alpha: 1).setFill()
            context.fill(CGRect(x: 38, y: 34, width: 284, height: 436))

            UIColor(red: 0.95, green: 0.76, blue: 0.22, alpha: 1).setFill()
            context.fill(CGRect(x: 64, y: 60, width: 232, height: 384))

            UIColor(red: 0.16, green: 0.40, blue: 0.58, alpha: 1).setFill()
            context.fill(CGRect(x: 92, y: 126, width: 176, height: 118))
            UIColor.white.withAlphaComponent(0.9).setFill()
            context.fill(CGRect(x: 110, y: 274, width: 140, height: 10))
            context.fill(CGRect(x: 132, y: 296, width: 96, height: 8))
        }

        guard let data = image.pngData() else { return }
        isSyntheticDebugFixture = true
        loadImageData(data)
    }
#endif

    struct ExportSnapshot: @unchecked Sendable {
        let image: UIImage
        let measurement: CardCenteringMeasurement
        let imageRevision: Int
        let rotationDegrees: Double

        func write() throws -> URL {
            guard measurement.canReportRatios, rotationDegrees.isFinite else {
                throw CardCenteringAnalyzerError.renderFailed
            }
            let rendered = CardCenteringExport.render(
                image: image, measurement: measurement, rotationDegrees: rotationDegrees
            )
            guard let data = rendered.pngData() else {
                throw CardCenteringAnalyzerError.renderFailed
            }
            // Keep the descriptive filename in a unique directory. A new edit
            // cannot overwrite a file already handed to a share sheet.
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("CenteringExport-" + UUID().uuidString, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let url = directory.appendingPathComponent(
                CardCenteringExport.filename(for: measurement, rotationDegrees: rotationDegrees)
            )
            do {
                try data.write(to: url, options: .atomic)
                return url
            } catch {
                try? FileManager.default.removeItem(at: directory)
                throw error
            }
        }
    }

    func exportSnapshot() -> ExportSnapshot? {
        guard !isAnalyzing, let image, let measurement, measurement.canReportRatios else { return nil }
        return ExportSnapshot(image: image, measurement: measurement,
                              imageRevision: imageRevision, rotationDegrees: rotationDegrees)
    }

    func matches(_ snapshot: ExportSnapshot) -> Bool {
        !isAnalyzing && imageRevision == snapshot.imageRevision
            && measurement == snapshot.measurement && rotationDegrees == snapshot.rotationDegrees
    }

    func makeExportFile() -> URL? {
        guard let snapshot = exportSnapshot() else { return nil }
        do { return try snapshot.write() }
        catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func analyze(_ data: Data, rotationDegrees: Double) {
        analysisGeneration &+= 1
        let requestID = analysisGeneration
        measurement = nil
        isAnalyzing = true
        errorMessage = nil
#if DEBUG
        clearDebugSettledMarker()
#endif
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try CardCenteringAnalyzer.analyze(data, rotationDegrees: rotationDegrees) }
            DispatchQueue.main.async {
                guard let self, self.analysisGeneration == requestID else { return }
                self.isAnalyzing = false
                switch result {
                case let .success(analysis):
                    self.image = analysis.image
                    self.imageRevision &+= 1
                    self.measurement = analysis.measurement
                    // `analysis.image` is already straightened when the card was
                    // skewed, and the measurement is in that image's
                    // coordinates. `rotationDegrees` is the person's own display
                    // adjustment and stays theirs — adding the correction to it
                    // would rotate an already-level card a second time.
#if DEBUG
                    self.applySyntheticDebugState()
                    self.markDebugAnalysisSettled(
                        self.measurement,
                        appliedRotationDegrees: analysis.appliedRotationDegrees,
                        detectedSkewDegrees: analysis.detectedSkewDegrees
                    )
#endif
                case let .failure(error):
                    self.errorMessage = error.localizedDescription
#if DEBUG
                    self.markDebugAnalysisSettled()
#endif
                }
            }
        }
    }
}

struct CardCenteringView: View {
    @StateObject private var model = CardCenteringViewModel()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedEdgeField: EdgeField?
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    @State private var isShowingCamera = false
    @State private var isShowingSettings = false
    @State private var isShowingFileImporter = false
    @State private var isOuterExpanded = ProcessInfo.processInfo.arguments.contains("CenteringExpanded")
        || ProcessInfo.processInfo.arguments.contains("CenteringOuterControls")
    @State private var isInnerExpanded = ProcessInfo.processInfo.arguments.contains("CenteringExpanded")
        || ProcessInfo.processInfo.arguments.contains("CenteringInnerControls")
    /// The rendered export, prepared ahead of the tap so `ShareLink` can own the
    /// presentation. `ShareLink` anchors itself correctly as a popover in wide
    /// windows and as a sheet in narrow ones, which a hand-rolled
    /// `UIActivityViewController` does not.
    @State private var exportURL: URL?

    private struct ExportInput: Equatable {
        let imageRevision: Int
        let measurement: CardCenteringMeasurement?
        let rotationDegrees: Double
    }

    private enum EdgeField: Hashable {
        case outerLeft
        case outerRight
        case outerTop
        case outerBottom
        case innerLeft
        case innerRight
        case innerTop
        case innerBottom
    }

    var body: some View {
        Group {
            if let image = model.image, let measurement = model.measurement {
                VStack(spacing: 0) {
                    GeometryReader { proxy in
                        imageReview(image, measurement: measurement)
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                    .frame(height: dynamicTypeSize.isAccessibilitySize ? 180 : 300)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)

                    Divider()

                    ScrollViewReader { reader in
                        ScrollView {
                            VStack(spacing: 18) {
                                resultSummary(measurement)
                                rotationControls
                                    .id("rotation-controls")
                                guideControls(measurement)
                                    .id("guide-controls")

                                if let errorMessage = model.errorMessage {
                                    Text(errorMessage)
                                        .font(.footnote)
                                        .foregroundStyle(.red)
                                }
                            }
                            .padding(16)
                            .padding(.bottom, 16)
                            .contentWidthLimit(.standard)
                        }
                        .scrollIndicators(.visible)
                        .safeAreaPadding(.bottom, 80)
#if DEBUG
                        .onAppear {
                            let arguments = ProcessInfo.processInfo.arguments
                            guard let routeIndex = arguments.firstIndex(of: "-ui_debug_route"),
                                  arguments.indices.contains(routeIndex + 1) else { return }
                            let target: String
                            switch arguments[routeIndex + 1] {
                            case "CenteringExpanded": target = "guide-controls"
                            case "CenteringRotation": target = "rotation-controls"
                            case "CenteringOuterControls": target = "outer-guides"
                            case "CenteringInnerControls": target = "inner-guides"
                            default: return
                            }
                            DispatchQueue.main.async {
                                withAnimation(nil) {
                                    reader.scrollTo(target, anchor: .top)
                                }
                            }
                        }
#endif
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: 18) {
                        if model.isAnalyzing {
                            ProgressView("Finding card edges…")
                                .frame(maxWidth: .infinity, minHeight: 360)
                        } else {
                            ContentUnavailableView {
                                Label("Check Card Centering", systemImage: "square.dashed.inset.filled")
                            } description: {
                                Text("Choose a clear, straight-on card photo or scan.")
                            } actions: {
                                VStack(spacing: 10) {
                                    Button("Take Photo", systemImage: "camera") {
                                        isShowingCamera = true
                                    }
                                    photoButton("Choose Photo")
                                    Button("Choose File", systemImage: "folder") {
                                        isShowingFileImporter = true
                                    }
                                }
                            }
                            .frame(minHeight: 460)
                        }

                        if let errorMessage = model.errorMessage {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                    .padding(16)
                    .contentWidthLimit(.standard)
                }
            }
        }
        .navigationTitle("Centering")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") {
                    focusedEdgeField = nil
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Settings", systemImage: "gearshape") {
                    isShowingSettings = true
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("Settings")
            }

            if model.image != nil {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let exportURL, model.measurement?.canReportRatios == true, !model.isAnalyzing {
                        ShareLink(item: exportURL) {
                            Label("Export Image", systemImage: "square.and.arrow.up")
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Export the centering image")
                    } else {
                        Button("Export Image", systemImage: "square.and.arrow.up") {}
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("Export the centering image")
                            .disabled(true)
                    }

                    Menu {
                        Button("Take Photo", systemImage: "camera") {
                            isShowingCamera = true
                        }
                        photoButton("Choose Photo")
                        Button("Choose File", systemImage: "folder") {
                            isShowingFileImporter = true
                        }
                    } label: {
                        Label("Choose Image", systemImage: "photo.badge.plus")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Choose a new image")
                }
            }
        }
        .onChange(of: model.imageRevision) {
            zoom = 1
            lastZoom = 1
            panOffset = .zero
            lastPanOffset = .zero
#if DEBUG
            let args = ProcessInfo.processInfo.arguments
            if let index = args.firstIndex(of: "-ui_debug_state"), args.indices.contains(index + 1), args[index + 1] == "zoom" {
                zoom = 2
                lastZoom = 2
                panOffset = CGSize(width: 12, height: 9)
                lastPanOffset = panOffset
            }
#endif
        }
        .onChange(of: model.selectedPhoto) {
            Task { await model.loadSelectedPhoto() }
        }
        .onChange(of: model.measurement?.canReportRatios) { _, canReport in
            if canReport == false {
                isOuterExpanded = true
                isInnerExpanded = true
            }
        }
#if DEBUG
        .task {
            let arguments = ProcessInfo.processInfo.arguments
            guard let routeIndex = arguments.firstIndex(of: "-ui_debug_route"),
                  arguments.indices.contains(routeIndex + 1) else { return }
            let route = arguments[routeIndex + 1]
            guard route.hasPrefix("Centering") else { return }
            model.loadDebugFixtureIfNeeded()
        }
#endif
        .overlay {
            if model.isAnalyzing, model.image != nil {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    ProgressView("Measuring…")
                        .padding(20)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
        .task(
            id: ExportInput(
                imageRevision: model.imageRevision,
                measurement: model.measurement,
                rotationDegrees: model.rotationDegrees
            )
        ) {
            // Guide steppers can emit a burst of values while a control is
            // held. Coalesce that burst, and key the task by every input
            // that changes the pixels so a rotation or a new image cannot
            // leave the previous export attached to ShareLink.
            exportURL = nil
            guard let snapshot = model.exportSnapshot() else { return }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try snapshot.write()
                }.value
                guard !Task.isCancelled, model.matches(snapshot) else {
                    try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
                    return
                }
                exportURL = url
            } catch {
                guard !Task.isCancelled, model.matches(snapshot) else { return }
                model.errorMessage = error.localizedDescription
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .fullScreenCover(isPresented: $isShowingCamera) {
            CenteringCameraView { data in
                model.loadCapturedPhoto(data)
            }
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.image]
        ) { result in
            switch result {
            case let .success(url):
                Task { await model.loadFile(at: url) }
            case let .failure(error):
                model.errorMessage = error.localizedDescription
            }
        }
    }

    private func photoButton(_ title: String) -> some View {
        PhotosPicker(selection: $model.selectedPhoto, matching: .images) {
            Label(title, systemImage: "photo.on.rectangle")
        }
    }

    private func imageReview(_ image: UIImage, measurement: CardCenteringMeasurement) -> some View {
        CardCenteringImage(
            image: image,
            measurement: measurement,
            rotationDegrees: model.rotationDegrees,
            onFrameChange: { frame in
#if DEBUG
                model.recordDebugImageFrame(frame)
#endif
            }
        )
            .scaleEffect(zoom)
            .offset(panOffset)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        zoom = min(6, max(1, lastZoom * value.magnification))
                    }
                    .onEnded { _ in
                        lastZoom = zoom
                        if zoom == 1 { panOffset = .zero; lastPanOffset = .zero }
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        guard zoom > 1 else { return }
                        panOffset = CGSize(
                            width: lastPanOffset.width + value.translation.width,
                            height: lastPanOffset.height + value.translation.height
                        )
                    }
                    .onEnded { _ in
                        if zoom > 1 {
                            lastPanOffset = panOffset
                        } else {
                            panOffset = .zero
                            lastPanOffset = .zero
                        }
                    }
            )
            .onTapGesture(count: 2) {
                withAnimation(.snappy) {
                    zoom = zoom > 1 ? 1 : 2
                    lastZoom = zoom
                    if zoom == 1 {
                        panOffset = .zero
                        lastPanOffset = .zero
                    }
                }
            }
            .accessibilityLabel(
                measurement.geometryInnerQuad == nil
                    ? "Card image with outer red guides; inner guide unavailable"
                    : measurement.requiresManualFrameConfirmation
                        ? "Card image with unconfirmed red outer and cyan inner guides"
                        : "Card image with outer red guides and inner cyan guides"
            )
    }

    private func resultSummary(_ measurement: CardCenteringMeasurement) -> some View {
        VStack(spacing: 14) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    CenteringMetric(title: "Left / Right", value: measurement.leftRightCentering)
                    CenteringMetric(title: "Top / Bottom", value: measurement.topBottomCentering)
                }
            } else {
                HStack(spacing: 12) {
                    CenteringMetric(title: "Left / Right", value: measurement.leftRightCentering)
                    CenteringMetric(title: "Top / Bottom", value: measurement.topBottomCentering)
                }
            }

            HStack {
                borderValue("L", measurement.leftBorder, declined: measurement.isDeclined)
                borderValue("R", measurement.rightBorder, declined: measurement.isDeclined)
                borderValue("T", measurement.topBorder, declined: measurement.isDeclined)
                borderValue("B", measurement.bottomBorder, declined: measurement.isDeclined)
            }

            if measurement.isDeclined {
                VStack(alignment: .leading, spacing: 6) {
                    Label(measurement.hasValidFrameGeometry ? "Review frames" : "Reading unavailable",
                          systemImage: "rectangle.dashed")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(measurement.hasValidFrameGeometry
                         ? "Check the red card edge and cyan inner frame before reading centering."
                         : "Adjust the guides to place the inner frame inside the card edges.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Text("Use the guide controls below, then confirm both frames.")
                        .font(.footnote.weight(.medium))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !measurement.warnings.isEmpty && measurement.canReportRatios {
                Label(measurement.warnings.joined(separator: " "), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            if let exportURL, measurement.canReportRatios {
                ShareLink(item: exportURL) {
                    Label("Export Image", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            } else {
                // Keep the export row in the layout while a guide edit is
                // preparing the next file. Removing it briefly changes the
                // ScrollView's content height and makes the steppers move
                // under a rapid series of taps.
                Button("Export Image", systemImage: "square.and.arrow.up") {}
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)
                    .disabled(true)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }

    private func borderValue(_ label: String, _ value: Int, declined: Bool) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(declined ? "—" : "\(value) px")
                .font(.subheadline.monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }

    private var rotationControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Rotation").font(.headline)
                Spacer()
                Text("\(model.rotationDegrees, specifier: "%.2f")°")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            ViewThatFits(in: .horizontal) {
                rotationButtons
                VStack(spacing: 8) {
                    HStack { rotationButton("−1", -1); rotationButton("+1", 1) }
                    HStack { rotationButton("−0.1", -0.1); rotationButton("+0.1", 0.1) }
                    HStack { rotationButton("−0.01", -0.01); rotationButton("+0.01", 0.01) }
                }
            }

            HStack {
                Button("Reset") { model.resetRotation() }
                    .disabled(model.rotationDegrees == 0)
                Spacer()
                Text("Rotates photo and guides")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }

    private var rotationButtons: some View {
        HStack(spacing: 8) {
            rotationButton("−1", -1)
            rotationButton("−0.1", -0.1)
            rotationButton("−0.01", -0.01)
            rotationButton("+0.01", 0.01)
            rotationButton("+0.1", 0.1)
            rotationButton("+1", 1)
        }
    }

    private func rotationButton(_ title: String, _ amount: Double) -> some View {
        Button {
            model.adjustRotation(by: amount)
        } label: {
            Text(title).fixedSize(horizontal: true, vertical: false)
        }
            .buttonStyle(.bordered)
            .font(.caption.monospacedDigit())
            .frame(maxWidth: .infinity, minHeight: 44)
            .accessibilityLabel("Rotate by \(amount) degrees")
    }

    private func guideControls(_ measurement: CardCenteringMeasurement) -> some View {
        VStack(spacing: 14) {
            Text("Adjust Guides")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(
                measurement.geometryInnerQuad == nil
                    ? "Red marks the card edge. Adjust the inner frame manually."
                    : "Red marks the card edge. Cyan marks the inner frame."
            )
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if !measurement.canReportRatios {
                Button("Confirm frames", systemImage: "checkmark.rectangle") {
                    model.confirmFrames()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!measurement.hasValidFrameGeometry)
                .accessibilityHint("Accepts the reviewed outer card edges and inner reference together.")
            }

            DisclosureGroup("Outer card edge", isExpanded: $isOuterExpanded) {
                VStack(spacing: 10) {
                    edgeStepper("Left", field: .outerLeft, value: outerBinding(\.left, range: 0...(measurement.imageWidth - 1)), range: 0...(measurement.imageWidth - 1))
                    edgeStepper("Right", field: .outerRight, value: outerBinding(\.right, range: 0...(measurement.imageWidth - 1)), range: 0...(measurement.imageWidth - 1))
                    edgeStepper("Top", field: .outerTop, value: outerBinding(\.top, range: 0...(measurement.imageHeight - 1)), range: 0...(measurement.imageHeight - 1))
                    edgeStepper("Bottom", field: .outerBottom, value: outerBinding(\.bottom, range: 0...(measurement.imageHeight - 1)), range: 0...(measurement.imageHeight - 1))
                }
                .padding(.top, 10)
            }
            .id("outer-guides")

            DisclosureGroup("Inner frame", isExpanded: $isInnerExpanded) {
                VStack(spacing: 10) {
                    edgeStepper("Left", field: .innerLeft, value: innerBinding(\.left, range: 0...(measurement.imageWidth - 1)), range: 0...(measurement.imageWidth - 1))
                    edgeStepper("Right", field: .innerRight, value: innerBinding(\.right, range: 0...(measurement.imageWidth - 1)), range: 0...(measurement.imageWidth - 1))
                    edgeStepper("Top", field: .innerTop, value: innerBinding(\.top, range: 0...(measurement.imageHeight - 1)), range: 0...(measurement.imageHeight - 1))
                    edgeStepper("Bottom", field: .innerBottom, value: innerBinding(\.bottom, range: 0...(measurement.imageHeight - 1)), range: 0...(measurement.imageHeight - 1))
                }
                .padding(.top, 10)
            }
            .id("inner-guides")
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }

    private func edgeStepper(
        _ label: String,
        field: EdgeField,
        value: Binding<Int>,
        range: ClosedRange<Int>
    ) -> some View {
        let context = String(describing: field).hasPrefix("outer") ? "Outer" : "Inner"
        return VStack(alignment: .leading, spacing: 8) {
            if dynamicTypeSize.isAccessibilitySize {
                Text("\(context) \(label.lowercased())")
                HStack {
                    TextField("0", value: value, format: .number)
                        .keyboardType(.numberPad)
                        .focused($focusedEdgeField, equals: field)
                        .textFieldStyle(.roundedBorder)
                        .monospacedDigit()
                        .accessibilityLabel("\(context) \(label.lowercased()) guide position")
                    Text("px").foregroundStyle(.secondary)
                }
                Stepper("\(context) \(label.lowercased())", value: value, in: range)
                    .labelsHidden()
                    .accessibilityLabel("\(context) \(label.lowercased()) guide position")
                    .accessibilityValue("\(value.wrappedValue) pixels")
            } else {
                HStack(spacing: 10) {
                    Text(label)
                    Spacer(minLength: 8)
                    TextField("0", value: value, format: .number)
                        .keyboardType(.numberPad)
                        .focused($focusedEdgeField, equals: field)
                        .multilineTextAlignment(.trailing)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 82)
                        .monospacedDigit()
                        .accessibilityLabel("\(context) \(label.lowercased()) guide position")
                        .accessibilityValue("\(value.wrappedValue) pixels")
                    Text("px")
                        .foregroundStyle(.secondary)
                    Stepper("\(context) \(label.lowercased())", value: value, in: range)
                        .labelsHidden()
                        .fixedSize()
                        .accessibilityLabel("\(context) \(label.lowercased()) guide position")
                        .accessibilityValue("\(value.wrappedValue) pixels")
                }
            }
        }
    }

    private func outerBinding(
        _ keyPath: WritableKeyPath<CardCenteringEdges, Int>,
        range: ClosedRange<Int>
    ) -> Binding<Int> {
        Binding(
            get: { model.measurement?.outer[keyPath: keyPath] ?? 0 },
            set: { model.updateOuter(keyPath, to: $0, within: range) }
        )
    }

    private func innerBinding(
        _ keyPath: WritableKeyPath<CardCenteringEdges, Int>,
        range: ClosedRange<Int>
    ) -> Binding<Int> {
        Binding(
            get: { model.measurement?.inner[keyPath: keyPath] ?? 0 },
            set: { model.updateInner(keyPath, to: $0, within: range) }
        )
    }
}

private struct CenteringMetric: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold().monospacedDigit())
        }
        .frame(maxWidth: .infinity)
    }
}

/// The image/guide composition is kept as a separate internal view so its
/// transform can be exercised with injected geometry without invoking the
/// detector. Production callers still reach it only through `imageReview`.
struct CardCenteringImage: View {
    let image: UIImage
    let measurement: CardCenteringMeasurement
    let rotationDegrees: Double
    let onFrameChange: (CGRect) -> Void

    var body: some View {
        GeometryReader { proxy in
            let imageRatio = CGFloat(measurement.imageWidth) / CGFloat(measurement.imageHeight)
            let availableRatio = proxy.size.width / max(proxy.size.height, 1)
            let fittedSize = availableRatio > imageRatio
                ? CGSize(width: proxy.size.height * imageRatio, height: proxy.size.height)
                : CGSize(width: proxy.size.width, height: proxy.size.width / imageRatio)
            let origin = CGPoint(
                x: (proxy.size.width - fittedSize.width) / 2,
                y: (proxy.size.height - fittedSize.height) / 2
            )
            let imageFrame = CGRect(origin: origin, size: fittedSize)
            let imageSize = CardCenteringSize(
                width: Double(measurement.imageWidth),
                height: Double(measurement.imageHeight)
            )
            let _ = onFrameChange(imageFrame)

            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)

                guidePath(
                    measurement.geometryOuterQuad,
                    color: .red,
                    imageSize: imageSize,
                    frame: imageFrame
                )
                if let inner = measurement.geometryInnerQuad {
                    guidePath(inner, color: .cyan, imageSize: imageSize, frame: imageFrame)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .rotationEffect(.degrees(rotationDegrees))
        }
        .aspectRatio(CGFloat(measurement.imageWidth) / CGFloat(measurement.imageHeight), contentMode: .fit)
        .background(Color.black)
    }

    private func guidePath(
        _ quad: CardCenteringQuad,
        color: Color,
        imageSize: CardCenteringSize,
        frame: CGRect
    ) -> some View {
        let points = CardCenteringGuideGeometry.screenPoints(
            for: quad,
            imageSize: imageSize,
            in: frame
        )
        return Path { path in
            guard points.allSatisfy({ $0.x.isFinite && $0.y.isFinite }),
                  let first = points.first else { return }
            path.move(to: first)
            for point in points.dropFirst() {
                path.addLine(to: point)
            }
            path.closeSubpath()
        }
        .stroke(color, style: StrokeStyle(lineWidth: 1.5, lineCap: .butt))
        .allowsHitTesting(false)
    }
}
