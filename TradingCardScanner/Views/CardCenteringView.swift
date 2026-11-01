import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import CoreTransferable
import CryptoKit

/// Owns only centering artifacts. Files handed to the system remain available
/// for this process; a later process retires the previous session's files.
enum CenteringExportFiles {
    private static let lock = NSLock()
    private static var sharedFiles: Set<URL> = []
    static let sessionDirectory: URL = {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CardScannerCenteringExports", isDirectory: true)
        if let sessions = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for session in sessions where UUID(uuidString: session.lastPathComponent) != nil {
                try? FileManager.default.removeItem(at: session)
            }
        }
        return root.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }()

    static func retainForShare(_ url: URL) {
        lock.lock(); defer { lock.unlock() }
        sharedFiles.insert(url)
    }

    static func retire(_ url: URL?) {
        guard let url, url.deletingLastPathComponent().deletingLastPathComponent() == sessionDirectory else { return }
        lock.lock(); defer { lock.unlock() }
        guard !sharedFiles.contains(url) else { return }
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent())
    }
}

private struct CenteringShareArtifact: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .png) { artifact in
            CenteringExportFiles.retainForShare(artifact.url)
            return SentTransferredFile(artifact.url)
        }
    }
}

@MainActor
final class CardCenteringViewModel: ObservableObject {
    private var currentExportFile: URL?

    func retireExportFile() {
        CenteringExportFiles.retire(currentExportFile)
        currentExportFile = nil
    }

    func acceptExportFile(_ url: URL) {
        retireExportFile()
        currentExportFile = url
    }
    @Published var selectedPhoto: PhotosPickerItem?
    @Published var image: UIImage?
    @Published private(set) var imageRevision = 0
    @Published var measurement: CardCenteringMeasurement?
    @Published var rotationDegrees = 0.0
    @Published var isAnalyzing = false
    @Published var errorMessage: String?
    /// The photo's luma, for snapping a dragged guide to an edge. Nil until it
    /// has been built in the background, and snapping waits for it.
    @Published private(set) var lumaField: CardCenteringLumaField?
    @Published private(set) var canUndo = false

    /// The guides as the detector placed them, for Reset Guides.
    private var detectedMeasurement: CardCenteringMeasurement?
    private var undoStack: [CardCenteringMeasurement] = []
    private var lastUndoKey: (key: String, time: Date)?

    @Published private(set) var nativeSourceData: Data?
    private var nativeDetailCache: (revision: Int, rect: CGRect, crop: CardCenteringNativeRefiner.Crop)?
    @Published private(set) var precisionEditReason: String?
    private var precisionUndo: CardCenteringMeasurement?
    private var precisionStart: CardCenteringMeasurement?

    private var hasLoadedSource = false
    private var loadGeneration = 0
    private var analysisGeneration = 0
    private var analysisTask: Task<Void, Never>?

#if DEBUG
    private var isSyntheticDebugFixture = false
    private var debugInputSHA256: String?

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
        if state == "confirmed" || state == "rotated" || state == "zoom" || state == "tilted" { fixture.confirmFrames() }
        if state == "tilted" {
            fixture.turnGuide(.init(frame: .inner, side: .right), about: .start, byDegrees: 0.25)
        }
        if state == "invalid" { fixture.setManualInnerEdge(\.left, to: 20) }
        if state == "rotated" || state == "zoom" { rotationDegrees = 7 }
        measurement = fixture
    }

    /// Generic deterministic UI evidence, applied after production analysis.
    /// Values come from a caller-owned development fixture, never a detector
    /// branch, image identity or production constant.
    private func applyDebugPrecisionActions() {
        struct Action: Decodable {
            let frame: CardCenteringPrecisionFrame
            let side: CardCenteringPrecisionSide
            let position: Double?
            let angle: Double?
        }
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-ui_debug_precision_actions_path"), arguments.indices.contains(index + 1),
           let data = try? Data(contentsOf: URL(fileURLWithPath: arguments[index + 1])),
           let actions = try? JSONDecoder().decode([Action].self, from: data) {
            for action in actions { updatePrecisionSide(action.side, frame: action.frame, position: action.position, angle: action.angle) }
        }
        if arguments.contains("-ui_debug_confirm_frames") { confirmFrames() }
        if let index = arguments.firstIndex(of: "-ui_debug_photo_rotation"), arguments.indices.contains(index + 1),
           let degrees = Double(arguments[index + 1]) { adjustRotation(by: degrees) }
        if arguments.contains("-ui_debug_reset_photo_rotation") { resetRotation() }
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
        let inputSHA256: String?
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
            topBottomCentering: measurement?.topBottomCentering,
            inputSHA256: debugInputSHA256
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

    func recordDebugExport(_ file: URL, snapshot: ExportSnapshot) {
        guard matches(snapshot), let url = debugSettledMarkerURL,
              let data = try? Data(contentsOf: url),
              var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        object["exportFilePath"] = file.path
        object["exportPhotoRotationDegrees"] = snapshot.rotationDegrees
        object["geometryRole"] = ProcessInfo.processInfo.arguments.contains("-ui_debug_precision_actions_path")
            ? "development_manual_guide_actions" : "unchanged_automatic_proposal_confirmed_for_comparison"
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
                selectedPhoto = nil
                return
            }
            acceptImageData(data)
        } catch {
            guard requestID == loadGeneration else { return }
            isAnalyzing = false
            // Let the picker select the same asset again after a failed load.
            selectedPhoto = nil
            if !Task.isCancelled { errorMessage = error.localizedDescription }
        }
    }

    private func beginImageLoad() -> Int {
        analysisTask?.cancel()
        loadGeneration &+= 1
        analysisGeneration &+= 1
        imageRevision &+= 1
        measurement = nil
        detectedMeasurement = nil
        lumaField = nil
        clearUndo()

        nativeSourceData = nil
        nativeDetailCache = nil
        precisionUndo = nil
        precisionStart = nil
        precisionEditReason = nil
        isAnalyzing = true
        errorMessage = nil
        rotationDegrees = 0
#if DEBUG
        debugInputSHA256 = nil
        clearDebugSettledMarker()
#endif
        return loadGeneration
    }

    private func loadImageData(_ data: Data) {
        _ = beginImageLoad()
        acceptImageData(data)
    }

    private func acceptImageData(_ data: Data) {
        hasLoadedSource = true
        selectedPhoto = nil
#if DEBUG
        debugInputSHA256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
#endif
        analyze(data, rotationDegrees: 0)
    }

    func adjustRotation(by amount: Double) {
        guard amount.isFinite else { return }
        let adjusted = ((rotationDegrees + amount) * 100).rounded() / 100
        let next = min(45, max(-45, adjusted))
        guard next != rotationDegrees else { return }
        rotationDegrees = next
        invalidateAfterPhotoRotation()
    }

    func resetRotation() {
        guard rotationDegrees != 0 else { return }
        rotationDegrees = 0
        invalidateAfterPhotoRotation()
    }

    private func invalidateAfterPhotoRotation() {
        measurement?.invalidateFrameConfirmationForPhotoRotation()
        retireExportFile()
        precisionUndo = nil
        precisionStart = nil
        precisionEditReason = nil
    }

    var precisionMeasurement: CardCenteringMeasurement? {
        guard var value = measurement else { return nil }
        let size = CardCenteringSize(width: Double(value.imageWidth), height: Double(value.imageHeight))
        var mapping = value.coordinateMapping ?? CardCenteringCoordinateMapping(orientedSourceSize: size, workingSize: size)
        mapping.appliedRotationDegrees += rotationDegrees
        value.coordinateMapping = mapping
        return value
    }

    var canUndoPrecisionEdit: Bool { precisionUndo != nil }
    var canResetPrecisionEdits: Bool { precisionStart.map { $0 != measurement } ?? false }

    func nativeDetailCrop(in rect: CGRect) -> CardCenteringNativeRefiner.Crop? {
        guard let data = nativeSourceData, !rect.isNull, !rect.isInfinite else { return nil }
        let key = rect.integral
        if let cached = nativeDetailCache, cached.revision == imageRevision, cached.rect == key { return cached.crop }
        let crop = autoreleasepool { () -> CardCenteringNativeRefiner.Crop? in
            guard let source = UIImage(data: data) else { return nil }
            return CardCenteringNativeRefiner.crop(source: source, orientedRect: key)
        }
        if let crop { nativeDetailCache = (imageRevision, key, crop) }
        return crop
    }

    func updatePrecisionSide(_ side: CardCenteringPrecisionSide, frame: CardCenteringPrecisionFrame = .inner,
                             position: Double? = nil, angle: Double? = nil) {
        guard let before = measurement, var candidate = precisionMeasurement else { return }
        guard candidate.setPrecisionSide(side, frame: frame, positionNativePixels: position, angleDegrees: angle) else {
            precisionEditReason = "That change would cross or collapse a frame. The last valid guides are retained."
            return
        }
        candidate.coordinateMapping = before.coordinateMapping
        recordUndoPoint(coalescing: "precision \(frame) \(side)", keepsPrecisionSession: true)
        if precisionStart == nil { precisionStart = before }
        precisionUndo = before
        measurement = candidate
        precisionEditReason = nil
    }

    func undoPrecisionEdit() {
        guard let previous = precisionUndo else { return }
        recordUndoPoint(keepsPrecisionSession: true)
        measurement = previous
        precisionUndo = nil
        precisionEditReason = nil
    }

    func resetPrecisionEdits() {
        guard let starting = precisionStart else { return }
        recordUndoPoint(keepsPrecisionSession: true)
        precisionUndo = measurement
        measurement = starting
        precisionStart = nil
        precisionEditReason = nil
    }

    func updateOuter(
        _ keyPath: WritableKeyPath<CardCenteringEdges, Int>,
        to value: Int,
        within range: ClosedRange<Int>
    ) {
        guard var measurement else { return }
        recordUndoPoint(coalescing: "exact outer \(keyPath)")
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
        recordUndoPoint(coalescing: "exact inner \(keyPath)")
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

    var canResetGuides: Bool {
        detectedMeasurement != nil && detectedMeasurement != measurement
    }

    /// Saves the current guides before an edit. Repeated presses of the same
    /// arrow within a moment share one undo step, so holding an arrow down
    /// undoes in one go.
    ///
    /// Every edit path records here, so Undo steps back through drags,
    /// arrows and Exact Values alike. Any edit outside the precision controls
    /// ends their session, so their Undo and Reset cannot restore guides from
    /// before later edits.
    func recordUndoPoint(coalescing key: String? = nil, keepsPrecisionSession: Bool = false) {
        guard let measurement else { return }
        if !keepsPrecisionSession {
            precisionUndo = nil
            precisionStart = nil
        }
        let now = Date()
        defer { lastUndoKey = key.map { ($0, now) } }
        if let key, let lastUndoKey, lastUndoKey.key == key, now.timeIntervalSince(lastUndoKey.time) < 1.2 {
            return
        }
        undoStack.append(measurement)
        if undoStack.count > 50 { undoStack.removeFirst() }
        canUndo = true
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        measurement = previous
        precisionUndo = nil
        precisionStart = nil
        lastUndoKey = nil
        canUndo = !undoStack.isEmpty
    }

    private func clearUndo() {
        undoStack = []
        lastUndoKey = nil
        canUndo = false
    }

    /// Takes the guides a drag produced.
    func applyGuideEdit(_ edited: CardCenteringMeasurement) {
        var edited = edited
        edited.refreshWarnings()
        measurement = edited
    }

    /// One arrow press: 1 px for a slide, 0.05° for a turn.
    func nudge(_ selection: CardCenteringGuideSelection, by steps: Double) {
        guard var measurement, steps.isFinite else { return }
        if let end = selection.end {
            recordUndoPoint(coalescing: "turn \(selection.guide) \(end)")
            measurement.turnGuide(selection.guide, about: end.opposite, byDegrees: steps * 0.05)
            // Stepping back through zero lands exactly square.
            if selection.guide.frame == .inner,
               abs(measurement.innerTiltDegrees ?? 0) < CardCenteringMeasurement.innerTiltDetentDegrees / 2 {
                measurement.squareInnerFrameToCardEdge()
            }
        } else {
            recordUndoPoint(coalescing: "nudge \(selection.guide)")
            measurement.nudgeGuide(selection.guide, by: steps)
        }
        applyGuideEdit(measurement)
    }

    func squareInnerFrame() {
        guard var measurement else { return }
        recordUndoPoint()
        measurement.squareInnerFrameToCardEdge()
        applyGuideEdit(measurement)
    }

    func addInnerFrame() {
        guard var measurement else { return }
        recordUndoPoint()
        measurement.placeDefaultInnerFrame()
        applyGuideEdit(measurement)
    }

    func resetGuides() {
        guard let detectedMeasurement, canResetGuides else { return }
        recordUndoPoint()
        measurement = detectedMeasurement
    }

    private func buildLumaField(for image: UIImage, measurement: CardCenteringMeasurement, revision: Int) {
        lumaField = nil
        guard let cgImage = image.cgImage else { return }
        let size = CardCenteringSize(width: Double(measurement.imageWidth), height: Double(measurement.imageHeight))
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let field = CardCenteringLumaField(image: cgImage, measurementSize: size)
            DispatchQueue.main.async {
                guard let self, self.imageRevision == revision else { return }
                self.lumaField = field
            }
        }
    }

#if DEBUG
    /// Gives the screenshot route a stable, local image so the centering controls
    /// can be checked without a Photos permission prompt or a camera session.
    func loadDebugFixtureIfNeeded(arguments: [String] = ProcessInfo.processInfo.arguments) {
        guard !hasLoadedSource else { return }
        if let index = arguments.firstIndex(of: "-ui_debug_fixture_path") {
            guard arguments.indices.contains(index + 1),
                  let data = try? Data(contentsOf: URL(fileURLWithPath: arguments[index + 1])) else {
                hasLoadedSource = true
                errorMessage = "The requested development image could not be read."
                markDebugAnalysisSettled()
                return
            }
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
            let directory = CenteringExportFiles.sessionDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
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
        do {
            let url = try snapshot.write()
            acceptExportFile(url)
            return url
        }
        catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func analyze(_ data: Data, rotationDegrees: Double) {
        analysisTask?.cancel()
        analysisGeneration &+= 1
        let requestID = analysisGeneration
        measurement = nil
        isAnalyzing = true
        errorMessage = nil
#if DEBUG
        clearDebugSettledMarker()
#endif
        analysisTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result = Result { try CardCenteringAnalyzer.analyze(data, rotationDegrees: rotationDegrees) }
            guard let self, !Task.isCancelled else { return }
            await MainActor.run {
                guard self.analysisGeneration == requestID else { return }
                self.isAnalyzing = false
                switch result {
                case let .success(analysis):
                    self.image = analysis.image
                    self.nativeSourceData = analysis.nativeSourceData
                    self.imageRevision &+= 1
                    self.measurement = analysis.measurement
                    // `analysis.image` is already straightened when the card was
                    // skewed, and the measurement is in that image's
                    // coordinates. `rotationDegrees` is the person's own display
                    // adjustment and stays theirs — adding the correction to it
                    // would rotate an already-level card a second time.
#if DEBUG
                    self.applySyntheticDebugState()
                    self.applyDebugPrecisionActions()
                    self.markDebugAnalysisSettled(
                        self.measurement,
                        appliedRotationDegrees: analysis.appliedRotationDegrees,
                        detectedSkewDegrees: analysis.detectedSkewDegrees
                    )
#endif
                    self.detectedMeasurement = self.measurement
                    self.clearUndo()
                    if let measurement = self.measurement {
                        self.buildLumaField(for: analysis.image, measurement: measurement, revision: self.imageRevision)
                    }
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
    @ObservedObject private var collectorTools = CollectorToolsStore.shared
    @State private var isShowingOffer = false

    var body: some View {
        Group {
            if collectorTools.canUseCentering {
                GuidedCardCenteringView()
            } else if collectorTools.ownership == .loading {
                ProgressView("Checking purchases…")
            } else {
                CenteringIntroLayout {
                    CenteringIntroHeader(isScanning: false, title: "Card Centering")
                    Button { isShowingOffer = true } label: {
                        Label("Unlock with Collector Tools", systemImage: "sparkles")
                            .font(.body.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.large)
                }
            }
        }
        .navigationTitle("Centering")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $isShowingOffer) { CollectorToolsOfferView() }
    }
}

/// Centres short intro content in the screen, and scrolls it when Dynamic
/// Type makes it taller than the screen.
private struct CenteringIntroLayout<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 28) {
                    content()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
                .frame(maxWidth: 480)
                .frame(maxWidth: .infinity, minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .background(Color(.systemGroupedBackground))
    }
}

/// The animated guide card with a title beneath it; the opening of every
/// centering state that has no photo yet.
private struct CenteringIntroHeader: View {
    let isScanning: Bool
    let title: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 22) {
            // Smaller at accessibility sizes, so the larger buttons stay in reach.
            CenteringGuideArt(cardWidth: dynamicTypeSize.isAccessibilitySize ? 92 : 132, isScanning: isScanning)
                .accessibilityHidden(true)
            HStack(spacing: 10) {
                if isScanning { ProgressView() }
                Text(title)
                    .font(.title2.weight(.bold))
                    .contentTransition(.opacity)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
        }
    }
}

/// Where centering begins: the card, and three ways to bring one in. How the
/// tool works lives behind the toolbar's help button, so the screen itself
/// stays just the choice.
private struct CenteringStartScreen<PhotoPicker: View>: View {
    let isAnalyzing: Bool
    let errorMessage: String?
    let onTakePhoto: () -> Void
    let onChooseFile: () -> Void
    @ViewBuilder let photoPicker: () -> PhotoPicker

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        CenteringIntroLayout {
            CenteringIntroHeader(
                isScanning: isAnalyzing,
                title: isAnalyzing ? "Finding Card Edges" : "Check Card Centering"
            )

            if let errorMessage, !isAnalyzing {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !isAnalyzing {
                sources
                    .transition(.opacity)
            }
        }
        .animation(.smooth(duration: 0.35), value: isAnalyzing)
        .animation(.smooth(duration: 0.35), value: errorMessage)
    }

    private var sources: some View {
        VStack(spacing: 10) {
            Button(action: onTakePhoto) {
                Label("Take Photo", systemImage: "camera.fill")
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 30)
            }
            .buttonStyle(.borderedProminent)

            let secondary = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(spacing: 10))
            secondary {
                photoPicker()
                    .buttonStyle(.bordered)
                Button(action: onChooseFile) {
                    Label("Files", systemImage: "folder")
                        .frame(maxWidth: .infinity, minHeight: 30)
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Choose File")
            }
        }
        .buttonBorderShape(.capsule)
        .controlSize(.large)
    }
}

/// The how-to and the estimate caveat, kept off the start screen until asked.
private struct CenteringGuideSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    step("viewfinder", "Shoot straight on", "Flat and evenly lit, with the whole card in frame.")
                    step("square.dashed", "Confirm both frames", "Drag any guide that's off the outer edge or the inner border.")
                    step("square.and.arrow.up", "Share the result", "Export an annotated image with both ratios.")
                    Divider()
                    Label("Guided estimate only. Not professional grading or a predicted grade.", systemImage: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(20)
            }
            .navigationTitle("How It Works")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func step(_ systemImage: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 36, height: 36)
                .background(Color.accentColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct GuidedCardCenteringView: View {
    @StateObject private var model = CardCenteringViewModel()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedEdgeField: EdgeField?
    @State private var selection: CardCenteringGuideSelection?
    @State private var isStraightening = false
    @State private var isShowingExactValues = false
    @State private var bottomPanelHeight: CGFloat = 0
    @State private var precisionFocusReset = 0
    @State private var isShowingCamera = false
    @State private var isShowingSettings = false
    @State private var isShowingGuide = false
    @State private var isShowingFileImporter = false
    @State private var isOuterExpanded = ProcessInfo.processInfo.arguments.contains("CenteringExpanded")
        || ProcessInfo.processInfo.arguments.contains("CenteringOuterControls")
    @State private var isInnerExpanded = ProcessInfo.processInfo.arguments.contains("CenteringExpanded")
        || ProcessInfo.processInfo.arguments.contains("CenteringInnerControls")
#if DEBUG
    @State private var debugPanelRoute: String?
#endif
    /// The rendered export, prepared ahead of the tap so `ShareLink` can own the
    /// presentation. `ShareLink` anchors itself correctly as a popover in wide
    /// windows and as a sheet in narrow ones, which a hand-rolled
    /// `UIActivityViewController` does not.
    @State private var exportURL: URL?
    @State private var exportedSnapshot: CardCenteringViewModel.ExportSnapshot?
    @State private var isPrecisionExpanded = ProcessInfo.processInfo.arguments.contains("CenteringPrecision")
    @State private var precisionSide: CardCenteringPrecisionSide = ProcessInfo.processInfo.arguments.contains("outer-bottom-detail") ? .bottom : .left
    @State private var precisionFrame: CardCenteringPrecisionFrame = ProcessInfo.processInfo.arguments.contains("outer-bottom-detail") ? .outer : .inner
    @State private var nativeDetailProgress = 0.5

    private var currentExportURL: URL? {
        guard let exportedSnapshot, model.matches(exportedSnapshot) else { return nil }
        return exportURL
    }

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
                    ratioStrip(measurement)
                    Divider()
                    ZStack(alignment: .bottom) {
                        CardCenteringCanvas(
                            image: image,
                            measurement: measurement,
                            rotationDegrees: model.rotationDegrees,
                            imageRevision: model.imageRevision,
                            lumaField: model.lumaField,
                            selection: $selection,
                            onBeginEdit: { model.recordUndoPoint() },
                            onEdit: { model.applyGuideEdit($0) },
                            onAccessibilityNudge: { amount in
                                if let selection { model.nudge(selection, by: amount) }
                            },
                            initialZoomMultiplier: initialZoomMultiplier,
                            bottomInset: bottomPanelHeight,
                            onFrameChange: { frame in
#if DEBUG
                                model.recordDebugImageFrame(frame)
#endif
                            }
                        )
                        bottomPanel(measurement)
                            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomPanelHeight = $0 }
                    }
                }
            } else {
                CenteringStartScreen(
                    isAnalyzing: model.isAnalyzing,
                    errorMessage: model.errorMessage,
                    onTakePhoto: { isShowingCamera = true },
                    onChooseFile: { isShowingFileImporter = true }
                ) {
                    PhotosPicker(selection: $model.selectedPhoto, matching: .images) {
                        Label("Photos", systemImage: "photo.on.rectangle")
                            .frame(maxWidth: .infinity, minHeight: 30)
                    }
                    .accessibilityLabel("Choose Photo")
                }
            }
        }
        .navigationTitle("Centering")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button("How It Works", systemImage: "questionmark.circle") {
                    isShowingGuide = true
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("How It Works")
                Button("Settings", systemImage: "gearshape") {
                    isShowingSettings = true
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("Settings")
            }

            if model.image != nil {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if let exportURL = currentExportURL, model.measurement?.canReportRatios == true, !model.isAnalyzing {
                        ShareLink(item: CenteringShareArtifact(url: exportURL), preview: SharePreview("Centering image")) {
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
        .sheet(isPresented: $isShowingGuide) {
            CenteringGuideSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .onChange(of: model.imageRevision) {
            selection = nil
            isStraightening = false
#if DEBUG
            applyDebugPanelRoute()
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
            // CenteringStart opens the tool on its start screen, with no fixture.
            guard route.hasPrefix("Centering"), route != "CenteringStart" else { return }
            debugPanelRoute = route
            model.loadDebugFixtureIfNeeded()
            applyDebugPanelRoute()
        }
#endif
        .overlay {
            // Before the first measurement the start screen shows its own
            // scanning state; this dims only an image being re-measured.
            if model.isAnalyzing, model.image != nil, model.measurement != nil {
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
            // A guide drag emits a burst of values. Coalesce that burst, and
            // key the task by every input that changes the pixels so a
            // rotation or a new image cannot leave the previous export
            // attached to ShareLink.
            exportURL = nil
            exportedSnapshot = nil
            model.retireExportFile()
            guard let snapshot = model.exportSnapshot() else { return }
            try? await Task.sleep(for: .milliseconds(180))
            guard !Task.isCancelled else { return }
            do {
                let url = try await Task.detached(priority: .userInitiated) {
                    try snapshot.write()
                }.value
                guard !Task.isCancelled, model.matches(snapshot) else {
                    CenteringExportFiles.retire(url)
                    return
                }
                model.acceptExportFile(url)
                exportURL = url
                exportedSnapshot = snapshot
#if DEBUG
                model.recordDebugExport(url, snapshot: snapshot)
#endif
            } catch {
                guard !Task.isCancelled, model.matches(snapshot) else { return }
                model.errorMessage = error.localizedDescription
            }
        }
        .onDisappear {
            model.retireExportFile()
            exportURL = nil
            exportedSnapshot = nil
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $isShowingExactValues) {
            exactValuesSheet
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

    private var initialZoomMultiplier: CGFloat {
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-ui_debug_state"), arguments.indices.contains(index + 1),
           arguments[index + 1] == "zoom" {
            return 2
        }
#endif
        return 1
    }

#if DEBUG
    /// The screenshot routes that once scrolled to a control now open the
    /// panel that holds it, once the fixture has been measured.
    private func applyDebugPanelRoute() {
        guard model.measurement != nil, let route = debugPanelRoute else { return }
        switch route {
        case "CenteringExpanded", "CenteringOuterControls", "CenteringInnerControls":
            isShowingExactValues = true
        case "CenteringPrecision":
            isShowingExactValues = true
            isPrecisionExpanded = true
        case "CenteringRotation":
            isStraightening = true
        default:
            break
        }
        // `-ui_debug_selection inner.right.end` picks up a guide, by an end
        // when one is named, so the selected controls can be captured.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-ui_debug_selection"), arguments.indices.contains(index + 1) {
            let parts = arguments[index + 1].split(separator: ".").map(String.init)
            if parts.count >= 2, let side = CardCenteringSide(rawValue: parts[1]) {
                selection = CardCenteringGuideSelection(
                    guide: .init(frame: parts[0] == "outer" ? .outer : .inner, side: side),
                    end: parts.count > 2 ? (parts[2] == "start" ? .start : .end) : nil
                )
            }
        }
    }
#endif

    private func photoButton(_ title: String) -> some View {
        PhotosPicker(selection: $model.selectedPhoto, matching: .images) {
            Label(title, systemImage: "photo.on.rectangle")
        }
    }

    // MARK: Reading

    private func ratioStrip(_ measurement: CardCenteringMeasurement) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
            CenteringMetric(
                title: "Left / Right",
                value: measurement.leftRightCentering,
                detail: ratioDetail(measurement, horizontal: true)
            )
            CenteringMetric(
                title: "Top / Bottom",
                value: measurement.topBottomCentering,
                detail: ratioDetail(measurement, horizontal: false)
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: measurement.leftRightCentering)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: measurement.topBottomCentering)
    }

    /// Border widths, or how the ratio changes along the card when the print
    /// is tilted.
    private func ratioDetail(_ measurement: CardCenteringMeasurement, horizontal: Bool) -> String {
        guard measurement.canReportRatios else { return "Confirm frames to read" }
        if measurement.hasReportableInnerTilt,
           let samples = measurement.positionalConsistency?.samples,
           let first = samples.first, let last = samples.last {
            func ratio(_ pair: CardCenteringRatioPair) -> String {
                String(format: "%.0f/%.0f", pair.firstPercentage, pair.secondPercentage)
            }
            return horizontal
                ? "\(ratio(first.leftRight)) top → \(ratio(last.leftRight)) bottom"
                : "\(ratio(first.topBottom)) left → \(ratio(last.topBottom)) right"
        }
        return horizontal
            ? "\(measurement.leftBorder) · \(measurement.rightBorder) px"
            : "\(measurement.topBorder) · \(measurement.bottomBorder) px"
    }

    // MARK: Controls

    private func bottomPanel(_ measurement: CardCenteringMeasurement) -> some View {
        VStack(spacing: 8) {
            if isStraightening {
                straightenControls
            } else if let selection, measurement.segment(for: selection.guide) != nil {
                selectedGuideControls(selection, measurement: measurement)
            } else {
                standardControls(measurement)
            }

            Text("Guided estimate only. Not professional grading or a predicted grade.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .contentWidthLimit(.standard)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: selection)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: isStraightening)
    }

    private func standardControls(_ measurement: CardCenteringMeasurement) -> some View {
        VStack(spacing: 8) {
            if measurement.hasReportableInnerTilt, let tilt = measurement.innerTiltDegrees {
                tiltRow(tilt)
            }
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(guidance(for: measurement))
                        .font(.subheadline)
                        .fixedSize(horizontal: false, vertical: true)
                    if !measurement.warnings.isEmpty && measurement.canReportRatios {
                        Label(measurement.warnings.joined(separator: " "), systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if measurement.geometryInnerQuad == nil {
                    Button("Add Frame", systemImage: "plus") {
                        model.addInnerFrame()
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .accessibilityLabel("Add an inner frame")
                } else if !measurement.canReportRatios {
                    Button("Confirm", systemImage: "checkmark") {
                        model.confirmFrames()
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(!measurement.hasValidFrameGeometry)
                    .accessibilityLabel("Confirm frames")
                    .accessibilityHint("Accepts the reviewed outer card edges and inner reference together.")
                }

                moreMenu(measurement)
            }
        }
    }

    /// The print's tilt against the card edge, kept clear of the photo so it
    /// never covers an edge being lined up.
    private func tiltRow(_ tilt: Double) -> some View {
        HStack(spacing: 10) {
            Label {
                Text("Print tilted \(abs(tilt), specifier: "%.2f")° \(tilt > 0 ? "clockwise" : "counterclockwise")")
                    .monospacedDigit()
            } icon: {
                Image(systemName: tilt > 0 ? "rotate.right" : "rotate.left")
            }
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
            Button("Square", systemImage: "square.dashed") {
                model.squareInnerFrame()
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .accessibilityLabel("Square the inner frame to the card edge")
        }
    }

    private func guidance(for measurement: CardCenteringMeasurement) -> String {
        if measurement.geometryInnerQuad == nil {
            return "No inner frame found. Add one to begin."
        }
        if !measurement.hasValidFrameGeometry {
            return "Keep each cyan line inside the red edge."
        }
        if !measurement.canReportRatios {
            return "Check both frames, then confirm."
        }
        return model.lumaField == nil
            ? "Drag any line to adjust it."
            : "Drag any line. It snaps to edges."
    }

    private func moreMenu(_ measurement: CardCenteringMeasurement) -> some View {
        Menu {
            Button("Undo", systemImage: "arrow.uturn.backward") {
                model.undo()
            }
            .disabled(!model.canUndo)
            if measurement.hasReportableInnerTilt {
                Button("Square Inner Frame", systemImage: "square") {
                    model.squareInnerFrame()
                }
            }
            Button("Straighten Photo", systemImage: "rotate.right") {
                selection = nil
                isStraightening = true
            }
            Button("Exact Values…", systemImage: "slider.horizontal.3") {
                isShowingExactValues = true
            }
            Divider()
            Button("Reset Guides", systemImage: "arrow.counterclockwise", role: .destructive) {
                selection = nil
                model.resetGuides()
            }
            .disabled(!model.canResetGuides)
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .menuOrder(.fixed)
        .accessibilityLabel("More options")
    }

    private func selectedGuideControls(
        _ selection: CardCenteringGuideSelection,
        measurement: CardCenteringMeasurement
    ) -> some View {
        let guide = selection.guide
        let frameName = guide.frame == .outer ? "Card edge" : "Inner frame"
        let side = guide.side.rawValue
        let isTurning = selection.end != nil
        let caption: String
        let value: String
        let hint: String
        let decrease: (symbol: String, label: String)
        let increase: (symbol: String, label: String)
        if isTurning {
            decrease = ("rotate.left", "Turn 0.05 degrees counterclockwise")
            increase = ("rotate.right", "Turn 0.05 degrees clockwise")
            if guide.frame == .inner {
                caption = "Inner frame · print tilt"
                let tilt = measurement.innerTiltDegrees ?? 0
                value = measurement.hasReportableInnerTilt
                    ? String(format: "%.2f° %@", abs(tilt), tilt > 0 ? "clockwise" : "counterclockwise")
                    : "Square"
                hint = "The arrows tilt 0.05°. Ease back toward square and it snaps."
            } else {
                caption = "Card edge · \(side) side angle"
                value = borderValue(guide.side, measurement)
                hint = "The far end stays put. The arrows turn this side 0.05°."
            }
        } else {
            caption = "\(frameName) · \(side) border"
            value = borderValue(guide.side, measurement)
            decrease = guide.side.isVertical ? ("chevron.left", "Move 1 pixel left") : ("chevron.up", "Move 1 pixel up")
            increase = guide.side.isVertical ? ("chevron.right", "Move 1 pixel right") : ("chevron.down", "Move 1 pixel down")
            hint = guide.frame == .inner
                ? "Drag an end grip to tilt the frame. The arrows move 1 px."
                : "Drag an end grip to turn this side. The arrows move 1 px."
        }

        return VStack(spacing: 6) {
            HStack(spacing: 10) {
                nudgeButton(decrease.symbol, label: decrease.label) {
                    model.nudge(selection, by: -1)
                }
                VStack(spacing: 1) {
                    Text(caption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(value)
                        .font(.headline.monospacedDigit())
                        .contentTransition(.numericText())
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                nudgeButton(increase.symbol, label: increase.label) {
                    model.nudge(selection, by: 1)
                }
                Button("Done") {
                    self.selection = nil
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }
            Text(hint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
        }
    }

    /// The selected side's border, once the frames are confirmed: before
    /// that no measurement is presented as a reading.
    private func borderValue(_ side: CardCenteringSide, _ measurement: CardCenteringMeasurement) -> String {
        guard measurement.canReportRatios else { return "Not confirmed" }
        return "\(Int(measurement.borderDistance(side).rounded())) px"
    }

    private var straightenControls: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Straighten Photo").font(.headline)
                Spacer()
                Text("\(model.rotationDegrees, specifier: "%.2f")°")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            HStack(spacing: 10) {
                nudgeButton("rotate.left", label: "Rotate the photo 0.1 degrees counterclockwise") {
                    model.adjustRotation(by: -0.1)
                }
                Slider(
                    value: Binding(
                        get: { model.rotationDegrees },
                        set: { model.adjustRotation(by: $0 - model.rotationDegrees) }
                    ),
                    in: -15...15
                ) {
                    Text("Photo rotation")
                }
                nudgeButton("rotate.right", label: "Rotate the photo 0.1 degrees clockwise") {
                    model.adjustRotation(by: 0.1)
                }
            }
            HStack {
                Button("Reset") { model.resetRotation() }
                    .disabled(model.rotationDegrees == 0)
                Spacer()
                Text("Turns the photo under the lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { isStraightening = false }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
            }
        }
    }

    private func nudgeButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .background(Color(.tertiarySystemFill), in: Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
        .buttonRepeatBehavior(.enabled)
        .accessibilityLabel(label)
    }

    private var exactValuesSheet: some View {
        NavigationStack {
            ScrollView {
                if let measurement = model.measurement {
                    guideControls(measurement)
                        .padding(16)
                }
            }
            .navigationTitle("Exact Values")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isShowingExactValues = false }
                }
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") {
                        focusedEdgeField = nil
                        precisionFocusReset &+= 1
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
    }
    private func guideControls(_ measurement: CardCenteringMeasurement) -> some View {
        VStack(spacing: 14) {
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

            if measurement.geometryInnerQuad != nil {
                DisclosureGroup("Precision adjustments", isExpanded: $isPrecisionExpanded) {
                    if isPrecisionExpanded { precisionControls }
                }
                .id("precision-guides")
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }

    private var precisionControls: some View {
        let frame = precisionFrame, side = precisionSide, revision = model.imageRevision
        return VStack(alignment: .leading, spacing: 12) {
            Text("Native pixels set adjustment units, not accuracy. Angles run clockwise from the source image horizontal. Tap Done to apply a typed value.")
                .font(.footnote).foregroundStyle(.secondary)
            Picker("Guide frame", selection: $precisionFrame) {
                ForEach(CardCenteringPrecisionFrame.allCases) { frame in Text(frame.label).tag(frame) }
            }
            .pickerStyle(.menu)
            Picker("Side", selection: $precisionSide) {
                ForEach(CardCenteringPrecisionSide.allCases) { side in Text(side.label).tag(side) }
            }
            .pickerStyle(.menu)
            if let line = model.precisionMeasurement?.precisionLine(precisionSide, frame: precisionFrame) {
                precisionNumber(precisionSide.isVertical ? "Horizontal position (native px)" : "Vertical position (native px)", value: line.position, step: 0.1) {
                    guard model.imageRevision == revision else { return }
                    model.updatePrecisionSide(side, frame: frame, position: $0)
                }
                .id("precision-position")
                precisionNumber("Angle (degrees)", value: line.angle, step: 0.01) {
                    guard model.imageRevision == revision else { return }
                    model.updatePrecisionSide(side, frame: frame, angle: $0)
                }
                Slider(value: $nativeDetailProgress, in: 0...1) {
                    Text("Detail position along side")
                }
                .accessibilityValue("\(Int(nativeDetailProgress * 100)) percent along side")
                nativeDetail.id("native-detail")
            }
            HStack {
                Button("Undo adjustment") { model.undoPrecisionEdit() }
                    .disabled(!model.canUndoPrecisionEdit)
                Spacer()
                Button("Reset precision edits") { model.resetPrecisionEdits() }
                    .disabled(!model.canResetPrecisionEdits)
            }
            .buttonStyle(.bordered)
            if let reason = model.precisionEditReason {
                Label(reason, systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.primary)
                    .accessibilityLabel(reason)
            }
        }
        .padding(.top, 10)
    }

    private func precisionNumber(_ label: String, value: Double, step: Double, update: @escaping (Double) -> Void) -> some View {
        CardCenteringPrecisionNumberField(label: label,
            accessibilityName: "\(precisionFrame.label) \(precisionSide.rawValue) \(label)",
            value: value, step: step, focusReset: precisionFocusReset, update: update)
            .id("\(precisionFrame.rawValue)-\(precisionSide.rawValue)-\(label)")
    }

    @ViewBuilder private var nativeDetail: some View {
        if let value = model.precisionMeasurement,
           let inner = value.geometryInnerQuad {
            let selected = precisionFrame == .outer ? value.geometryOuterQuad : inner
            let native = value.coordinateMapping?.nativeQuad(fromWorking: selected) ?? selected
            let a = native.points[precisionSide.index], b = native.points[(precisionSide.index + 1) % 4]
            let middle = CGPoint(x: a.x + (b.x - a.x) * nativeDetailProgress, y: a.y + (b.y - a.y) * nativeDetailProgress)
            if let crop = model.nativeDetailCrop(in: CGRect(x: middle.x - 64, y: middle.y - 64, width: 128, height: 128)) {
                Text(precisionFrame == .outer ? "Native source detail · selected card edge" : "Native source detail · selected inner guide").font(.caption).foregroundStyle(.secondary)
                CardCenteringNativeDetailImage(image: crop.image, origin: crop.originOrientedNative,
                    pixelWidth: crop.width, pixelHeight: crop.height, guideStart: a, guideEnd: b,
                    guideColor: precisionFrame == .outer ? .red : .cyan)
                    .accessibilityLabel("Enlarged original source pixels at \(Int(nativeDetailProgress * 100)) percent along the \(precisionFrame.rawValue) \(precisionSide.rawValue) guide. \(precisionFrame == .outer ? "Red" : "Cyan") marks the selected line.")
            }
        }
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

/// Keep partially typed localized numbers intact. Formatting a value binding
/// on every keystroke can replace the draft before its decimal digits arrive.
struct CardCenteringPrecisionNumberField: View {
    let label: String
    let accessibilityName: String
    let value: Double
    let step: Double
    let focusReset: Int
    let update: (Double) -> Void
    @Environment(\.locale) private var locale
    @FocusState private var isFocused: Bool
    @State private var draft = ""
    @State private var inputReason: String?

    static func parsedValue(_ text: String, locale: Locale) -> Double? {
        guard let value = try? FloatingPointFormatStyle<Double>.number.locale(locale).parseStrategy.parse(text),
              value.isFinite else { return nil }
        return value
    }

    private var formattedValue: String {
        value.formatted(.number.precision(.fractionLength(2)).locale(locale))
    }

    private func commit() {
        // Merely focusing a rounded display must not quantize the authoritative
        // Double line position when the person leaves without changing it.
        guard draft != formattedValue else { inputReason = nil; return }
        guard let parsed = Self.parsedValue(draft, locale: locale) else {
            inputReason = "Enter a finite number using your region’s decimal separator."
            draft = formattedValue
            return
        }
        inputReason = nil
        draft = formattedValue
        if parsed != value { update(parsed) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.subheadline)
            TextField(label, text: $draft)
                .focused($isFocused)
                .keyboardType(.numbersAndPunctuation)
                .textFieldStyle(.roundedBorder)
                .monospacedDigit()
                .accessibilityLabel(accessibilityName)
                .onSubmit { isFocused = false }
            Stepper(label, onIncrement: { update(value + step) }, onDecrement: { update(value - step) })
                .labelsHidden()
                .disabled(isFocused)
                .accessibilityLabel(accessibilityName)
                .accessibilityValue("\(value)")
            if let inputReason {
                Label(inputReason, systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.primary)
            }
        }
        .onAppear { draft = formattedValue }
        .onChange(of: value) { _, _ in if !isFocused { draft = formattedValue } }
        .onChange(of: isFocused) { wasFocused, focused in if wasFocused && !focused { commit() } }
        .onChange(of: focusReset) { _, _ in isFocused = false }
        .onDisappear { if isFocused { commit() } }
    }
}

/// Both layers receive the same aspect-constrained bounds. Applying an
/// overlay to an internally letterboxed Image would map into the padding.
struct CardCenteringNativeDetailImage: View {
    let image: UIImage
    let origin: CardCenteringPoint
    let pixelWidth: Int
    let pixelHeight: Int
    let guideStart: CardCenteringPoint
    let guideEnd: CardCenteringPoint
    let guideColor: Color

    var body: some View {
        ZStack {
            Image(uiImage: image).resizable().interpolation(.none)
            GeometryReader { proxy in
                Path { path in
                    path.move(to: CGPoint(x: (guideStart.x - origin.x) * proxy.size.width / Double(pixelWidth),
                        y: (guideStart.y - origin.y) * proxy.size.height / Double(pixelHeight)))
                    path.addLine(to: CGPoint(x: (guideEnd.x - origin.x) * proxy.size.width / Double(pixelWidth),
                        y: (guideEnd.y - origin.y) * proxy.size.height / Double(pixelHeight)))
                }.stroke(guideColor, lineWidth: 1)
            }
        }
        .aspectRatio(CGFloat(pixelWidth) / CGFloat(pixelHeight), contentMode: .fit)
        .clipped()
        .frame(maxHeight: 220)
        .accessibilityElement(children: .ignore)
    }
}

private struct CenteringMetric: View {
    let title: String
    let value: String
    var detail: String?

    var body: some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
                .font(.title3.bold().monospacedDigit())
                .contentTransition(.numericText())
            if let detail {
                Text(detail)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// The image/guide composition is kept as a separate internal view so its
/// transform can be exercised with injected geometry without invoking the
/// detector.
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
                    // Rotation straightens the photo beneath the fixed measuring guides.
                    .rotationEffect(.degrees(rotationDegrees))

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
