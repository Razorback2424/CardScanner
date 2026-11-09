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
#if DEBUG
    private let printReference: CardCenteringPrintReference?
    private let printReferences: [CardCenteringPrintReference]
    init(printReference: CardCenteringPrintReference? = nil, printReferences: [CardCenteringPrintReference] = []) {
        self.printReference = printReference
        self.printReferences = printReferences
    }
#endif
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
    @Published var image: UIImage? {
        didSet {
            if image !== oldValue { invalidateAfterPhotoRotation() }
        }
    }
    @Published private(set) var imageRevision = 0
    @Published var measurement: CardCenteringMeasurement? {
        didSet {
            if measurement != oldValue { clearBoundaryComparison() }
        }
    }
    @Published private(set) var comparedCandidateIDs: [String] = []

    func compareBoundary(_ id: String) {
        guard let value = precisionMeasurement,
              value.boundaryCandidates.contains(where: { $0.id == id }) else { return }
        comparedCandidateIDs = [id]
        retireExportFile()
    }

    func clearBoundaryComparison() {
        if !comparedCandidateIDs.isEmpty { comparedCandidateIDs = [] }
        retireExportFile()
    }

    var boundaryComparison: CardCenteringBoundarySensitivity? {
        guard !comparedCandidateIDs.isEmpty, let value = precisionMeasurement, value.canReportRatios else { return nil }
        return value.boundarySensitivity(comparing: comparedCandidateIDs)
    }
    @Published var rotationDegrees = 0.0 {
        didSet {
            if rotationDegrees != oldValue { invalidateAfterPhotoRotation() }
        }
    }
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

    deinit { analysisTask?.cancel() }

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
        let inner = state == "independent"
            ? CardCenteringQuad(topLeft: .init(x: 64, y: 64), topRight: .init(x: 296, y: 58),
                                bottomRight: .init(x: 286, y: 444), bottomLeft: .init(x: 54, y: 450))
            : .axisAligned(.init(left: 64, top: 60, right: 296, bottom: 444))
        var candidates = analysis.boundaryCandidates
        if ["comparison", "ambiguous"].contains(state) {
            candidates.append(.init(id: "ui-inner-alternative", frame: .inner, side: .left,
                nativeLine: .init(start: .init(x: 68, y: 444), end: .init(x: 68, y: 60)),
                source: "synthetic_ui_fixture", proposedRole: .printedBorder, competingRoles: [.artwork],
                signal: "known fixture stripe", strength: nil, polarity: nil, coverage: nil, fitResidualNativePixels: nil,
                sampleBands: [.init(start: .init(x: 68, y: 100), end: .init(x: 68, y: 200), sampleCount: nil),
                              .init(start: .init(x: 68, y: 300), end: .init(x: 68, y: 410), sampleCount: nil)],
                exclusions: [.init(role: .artwork, reason: "Known occluded region in synthetic UI fixture",
                    nativeBand: .init(start: .init(x: 68, y: 210), end: .init(x: 68, y: 270), sampleCount: nil))],
                selectionReason: .competingCandidate, reason: "Known alternative in synthetic UI fixture"))
        }
        var fixture = CardCenteringMeasurement(imageWidth: 360, imageHeight: 504,
            outerQuad: .axisAligned(.init(left: 38, top: 34, right: 322, bottom: 470)),
            innerQuad: state == "missing" ? nil : inner,
            warnings: [], coordinateMapping: analysis.coordinateMapping,
            innerReference: state == "missing" ? .none : .printedBorder,
            confidence: analysis.confidence, inputRecord: analysis.inputRecord,
            boundaryCandidates: candidates)
        if ["confirmed", "rotated", "zoom", "tilted", "independent", "comparison"].contains(state) { fixture.confirmFrames(reference: .userPrintedBorder) }
        if state == "tilted" {
            fixture.turnGuide(.init(frame: .inner, side: .right), about: .start, byDegrees: 0.25)
        }
        if state == "invalid" { fixture.setManualInnerEdge(\.left, to: 20) }
        if state == "no-reference" { fixture.clearReference() }
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
        if arguments.contains("-ui_debug_confirm_frames") {
            confirmFrames(reference: measurement?.reviewedDesign == nil ? .userPrintedBorder : nil)
        }
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
        let reviewState: CardCenteringReviewState?
        let hasManualGuideEdits: Bool?
        let proposedOuterQuad: CardCenteringQuad?
        let proposedInnerQuad: CardCenteringQuad?
        let ratioMethod: String
        let appliedRotationDegrees: Double?
        let detectedSkewDegrees: Double?
        let reason: String?
        let screenScale: Double
        let coordinateMapping: CardCenteringCoordinateMapping?
        let leftRightCentering: String?
        let topBottomCentering: String?
        let inputSHA256: String?
        let referenceDefinition: CardCenteringReferenceDefinition?
        let inputRecord: CardCenteringInputRecord?
        let boundaryCandidates: [CardCenteringBoundaryCandidate]?
        let selectedLines: [CardCenteringSelectedLine]?
        let observedPaths: CardCenteringPrintMatcher.ObservedMeasurement?
        let spatialMeasurement: CardCenteringSpatialMeasurement?
        let comparedCandidateIDs: [String]
        let boundaryComparison: CardCenteringBoundarySensitivity?
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
            reviewState: measurement?.reviewState,
            hasManualGuideEdits: measurement?.hasManualGuideEdits,
            proposedOuterQuad: measurement?.proposedOuterQuad,
            proposedInnerQuad: measurement?.proposedInnerQuad,
            ratioMethod: measurement?.hasObservedPaths == true ? "paired_observed_paths_local_mean_v1" : "rectified_endpoint_average_v1",
            appliedRotationDegrees: measurement == nil ? nil : (appliedRotationDegrees ?? rotationDegrees),
            detectedSkewDegrees: measurement == nil ? nil : detectedSkewDegrees,
            reason: measurement?.declineReason,
            screenScale: Double(UIScreen.main.scale),
            coordinateMapping: measurement?.coordinateMapping,
            leftRightCentering: measurement?.leftRightCentering,
            topBottomCentering: measurement?.topBottomCentering,
            inputSHA256: debugInputSHA256,
            referenceDefinition: measurement?.referenceDefinition,
            inputRecord: measurement?.inputRecord,
            boundaryCandidates: measurement?.boundaryCandidates,
            selectedLines: measurement == nil ? nil : precisionMeasurement?.selectedLines,
            observedPaths: measurement?.observedPrintMeasurement,
            spatialMeasurement: measurement == nil ? nil : precisionMeasurement?.spatialMeasurement,
            comparedCandidateIDs: comparedCandidateIDs,
            boundaryComparison: boundaryComparison
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
              let previous = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        // A receipt must describe the exported revision, including human
        // choices, rather than retain the original analysis geometry.
        markDebugAnalysisSettled(snapshot.measurement,
            detectedSkewDegrees: previous["detectedSkewDegrees"] as? Double)
        guard let refreshed = try? Data(contentsOf: url),
              var object = try? JSONSerialization.jsonObject(with: refreshed) as? [String: Any] else { return }
        object["presentedImageFrame"] = previous["presentedImageFrame"]
        object["exportFilePath"] = file.path
        object["exportPhotoRotationDegrees"] = snapshot.rotationDegrees
        object["geometryRole"] = isSyntheticDebugFixture ? "synthetic_geometry_fixture"
            : snapshot.measurement.hasManualGuideEdits ? "user_adjusted_guides"
            : "unchanged_automatic_proposal_confirmed_for_comparison"
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
        guard amount.isFinite, measurement?.hasObservedPaths != true else { return }
        let adjusted = ((rotationDegrees + amount) * 100).rounded() / 100
        let next = min(45, max(-45, adjusted))
        guard next != rotationDegrees else { return }
        rotationDegrees = next
    }

    func resetRotation() {
        guard rotationDegrees != 0 else { return }
        rotationDegrees = 0
    }

    private func invalidateAfterPhotoRotation() {
        clearBoundaryComparison()
        measurement?.invalidateFrameConfirmationForPhotoRotation()
        // Guides remain undoable, but approval belongs to the exact photo
        // coordinate system. Even rotating back requires fresh confirmation.
        for index in undoStack.indices {
            undoStack[index].invalidateFrameConfirmationForPhotoRotation()
        }
        detectedMeasurement?.invalidateFrameConfirmationForPhotoRotation()
        retireExportFile()
        precisionUndo = nil
        precisionStart = nil
        precisionEditReason = nil
    }

    var precisionMeasurement: CardCenteringMeasurement? {
        measurement?.includingPhotoRotation(rotationDegrees)
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

    func confirmFrames(reference: CardCenteringReferenceDefinition? = nil) {
        guard var measurement, measurement.confirmFrames(reference: reference) else { return }
        if self.measurement?.canReportRatios == true, let reference, self.measurement?.referenceDefinition != reference {
            recordUndoPoint()
        }
        self.measurement = measurement
    }

    func clearReference() {
        guard var measurement else { return }
        recordUndoPoint()
        measurement.clearReference()
        self.measurement = measurement
    }

    func selectBoundaryCandidate(_ id: String) {
        guard let before = measurement, var candidate = precisionMeasurement,
              let evidence = candidate.boundaryCandidates.first(where: { $0.id == id }) else { return }
        let role: CardCenteringBoundaryRole = evidence.frame == .outer ? .physicalCut : candidate.referenceDefinition.role
        guard candidate.selectBoundaryCandidate(id: id, as: role) else {
            precisionEditReason = "That edge would cross or collapse a frame. Your guides are unchanged."
            return
        }
        candidate.coordinateMapping = before.coordinateMapping
        recordUndoPoint(keepsPrecisionSession: true)
        if precisionStart == nil { precisionStart = before }
        precisionUndo = before
        measurement = candidate
        precisionEditReason = nil
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

    func beginManualGuides() {
        guard measurement?.hasObservedPaths == true else { return }
        recordUndoPoint()
        measurement?.beginManualGuides()
        clearBoundaryComparison()
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
               !measurement.innerFrameHasIndependentSlopes,
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

            if ["comparison", "ambiguous"].contains(debugState ?? "") {
                UIColor(red: 0.64, green: 0.42, blue: 0.08, alpha: 1).setFill()
                context.fill(CGRect(x: 64, y: 60, width: 4, height: 384))
                UIColor(white: 0.6, alpha: 1).setFill()
                context.fill(CGRect(x: 62, y: 210, width: 10, height: 60))
            }

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
        var comparedCandidateIDs: [String] = []
        var sensitivity: CardCenteringBoundarySensitivity? = nil

        func write() throws -> URL {
            guard measurement.canReportRatios, rotationDegrees.isFinite else {
                throw CardCenteringAnalyzerError.renderFailed
            }
            let rendered = CardCenteringExport.render(
                image: image, measurement: measurement, rotationDegrees: rotationDegrees, sensitivity: sensitivity
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

    struct ReviewSnapshot: @unchecked Sendable {
        struct Key: Equatable {
            let imageIdentity: ObjectIdentifier
            let imageRevision: Int
            let geometry: CardCenteringGeometryRevision
            let rotationDegrees: Double
        }
        let image: UIImage
        let measurement: CardCenteringMeasurement
        let imageRevision: Int
        let rotationDegrees: Double
        var key: Key { .init(imageIdentity: ObjectIdentifier(image), imageRevision: imageRevision,
            geometry: measurement.geometryRevision, rotationDegrees: rotationDegrees) }
        func render() throws -> CardCenteringReviewRenderer.Output {
            try CardCenteringReviewRenderer.render(image: image, measurement: measurement, rotationDegrees: rotationDegrees)
        }
    }

    func reviewSnapshot() -> ReviewSnapshot? {
        guard !isAnalyzing, let image, let value = precisionMeasurement, value.hasValidFrameGeometry else { return nil }
        return .init(image: image, measurement: value, imageRevision: imageRevision, rotationDegrees: rotationDegrees)
    }

    func matchesReview(_ snapshot: ReviewSnapshot) -> Bool { reviewSnapshot()?.key == snapshot.key }

    func exportSnapshot() -> ExportSnapshot? {
        guard !isAnalyzing, let image, let measurement, measurement.canReportRatios else { return nil }
        return ExportSnapshot(image: image, measurement: measurement,
                              imageRevision: imageRevision, rotationDegrees: rotationDegrees,
                              comparedCandidateIDs: comparedCandidateIDs, sensitivity: boundaryComparison)
    }

    func matches(_ snapshot: ExportSnapshot) -> Bool {
        !isAnalyzing && image === snapshot.image && imageRevision == snapshot.imageRevision
            && measurement == snapshot.measurement && rotationDegrees == snapshot.rotationDegrees
            && comparedCandidateIDs == snapshot.comparedCandidateIDs
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
        let reference = printReference
        let references = printReferences
#endif
        analysisTask = Task.detached(priority: .userInitiated) { [weak self] in
            let result = Result {
#if DEBUG
                if reference != nil || !references.isEmpty {
                    return try CardCenteringAnalyzer.$activePrintReferences.withValue(reference.map { [$0] } ?? references) {
                        try CardCenteringAnalyzer.analyze(data, rotationDegrees: rotationDegrees)
                    }
                }
#endif
                return try CardCenteringAnalyzer.analyze(data, rotationDegrees: rotationDegrees)
            }
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
#if DEBUG
    private let printReference: CardCenteringPrintReference?
    private let printReferences: [CardCenteringPrintReference]
    init(printReference: CardCenteringPrintReference? = .launchReference,
         printReferences: [CardCenteringPrintReference] = CardCenteringPrintReference.launchLibrary) {
        self.printReference = printReference
        self.printReferences = printReferences
    }
#endif
    @ObservedObject private var collectorTools = CollectorToolsStore.shared
    @State private var isShowingOffer = false

    var body: some View {
        Group {
            if collectorTools.canUseCentering {
#if DEBUG
                GuidedCardCenteringView(printReference: printReference, printReferences: printReferences)
                    .id(printReference.map { [$0] } ?? printReferences)
#else
                GuidedCardCenteringView()
#endif
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
                    step("square.dashed", "Review the reference", "Align red guides with the card edges and cyan guides with a visible printed reference. Choose what the cyan guides follow to confirm both frames.")
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
#if DEBUG
    init(printReference: CardCenteringPrintReference? = nil, printReferences: [CardCenteringPrintReference] = []) {
        _model = StateObject(wrappedValue: CardCenteringViewModel(printReference: printReference, printReferences: printReferences))
    }
#endif
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focusedEdgeField: EdgeField?
    @State private var selection: CardCenteringGuideSelection?
    @State private var showsAllBoundaryCandidates = false
    @State private var reviewRequest: CardCenteringReviewRequest?
    @State private var edgeReviewRequest: CardCenteringReviewRequest?
    @State private var isStraightening = false
    @State private var isShowingExactValues = false
    @State private var bottomPanelHeight: CGFloat = 0
    @State private var precisionCommitAction = CardCenteringPrecisionCommitAction()
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
    @State private var debugReviewPresented = false
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
        let comparedCandidateIDs: [String]
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
                if dynamicTypeSize.isAccessibilitySize {
                    GeometryReader { proxy in
                        VStack(spacing: 0) {
                            // Keep guide drags outside the scrolling controls so
                            // reading long text cannot accidentally move an edge.
                            guideCanvas(image, measurement: measurement, bottomInset: 0)
                                .frame(height: max(160, min(360, proxy.size.height * 0.4)))
                            Divider()
                            ScrollView {
                                VStack(spacing: 0) {
                                    ratioStrip(measurement)
                                    Divider()
                                    bottomPanel(measurement)
                                }
                            }
                            .scrollBounceBehavior(.basedOnSize)
                        }
                    }
                } else {
                    VStack(spacing: 0) {
                        ratioStrip(measurement)
                        Divider()
                        ZStack(alignment: .bottom) {
                            guideCanvas(image, measurement: measurement, bottomInset: bottomPanelHeight)
                            bottomPanel(measurement)
                                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { bottomPanelHeight = $0 }
                        }
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
            reviewRequest = nil
            edgeReviewRequest = nil
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
                rotationDegrees: model.rotationDegrees,
                comparedCandidateIDs: model.comparedCandidateIDs
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
        .sheet(item: $reviewRequest) { request in
            CardCenteringReviewSheet(model: model, request: request)
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
        if !debugReviewPresented, model.reviewSnapshot() != nil,
           let index = arguments.firstIndex(of: "-ui_debug_review"), arguments.indices.contains(index + 1) {
            let mode = arguments[index + 1]
            isShowingExactValues = false
            if mode == "perspective" {
                reviewRequest = .init()
                debugReviewPresented = true
            } else if mode == "edge", let value = model.precisionMeasurement {
                let candidate = value.boundaryCandidates.first { $0.id == "ui-inner-alternative" }
                    ?? value.reviewCandidates(frame: .inner, side: .left).first { candidate in
                        !value.selectedLines.contains { $0.frame == .inner && $0.side == .left && $0.nativeLine.coincides(with: candidate.nativeLine) }
                    }
                if let candidate {
                    model.compareBoundary(candidate.id)
                    reviewRequest = .init(candidateID: candidate.id, frame: candidate.frame, side: candidate.side)
                    debugReviewPresented = true
                }
            }
        }
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

    private func guideCanvas(_ image: UIImage, measurement: CardCenteringMeasurement, bottomInset: CGFloat) -> some View {
        CardCenteringCanvas(
            image: image, measurement: measurement, rotationDegrees: model.rotationDegrees,
            imageRevision: model.imageRevision, lumaField: model.lumaField, selection: $selection,
            onBeginEdit: { model.recordUndoPoint() }, onEdit: { model.applyGuideEdit($0) },
            onAccessibilityNudge: { amount in
                if let selection { model.nudge(selection, by: amount) }
            },
            initialZoomMultiplier: initialZoomMultiplier, bottomInset: bottomInset,
            onFrameChange: { frame in
#if DEBUG
                model.recordDebugImageFrame(frame)
#endif
            }
        )
    }

    private func ratioStrip(_ measurement: CardCenteringMeasurement) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
        return layout {
#if DEBUG
            if let design = measurement.reviewedDesign {
                artworkMetric(measurement, title: "Left margin share", design: design.designLeft, horizontal: true)
                artworkMetric(measurement, title: "Top margin share", design: design.designTop, horizontal: false)
            } else {
                ordinaryMetrics(measurement)
            }
#else
            ordinaryMetrics(measurement)
#endif
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: measurement.leftRightCentering)
        .animation(reduceMotion ? nil : .snappy(duration: 0.2), value: measurement.topBottomCentering)
    }

#if DEBUG
    private func artworkMetric(_ measurement: CardCenteringMeasurement, title: String, design: Double, horizontal: Bool) -> some View {
        let share = measurement.centeringPair(horizontal: horizontal)?.firstPercentage ?? 0
        return CenteringMetric(title: title,
            value: measurement.canReportRatios ? String(format: "%.1f%%",share) : "—",
            detail: measurement.canReportRatios ? String(format: "Design %.1f%%", design) : "Confirm frames to read")
    }
#endif

    @ViewBuilder private func ordinaryMetrics(_ measurement: CardCenteringMeasurement) -> some View {
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

    /// Border widths, or positional variation along independently placed edges.
    private func ratioDetail(_ measurement: CardCenteringMeasurement, horizontal: Bool) -> String {
        guard measurement.canReportRatios else {
            return measurement.referenceDefinition.isAvailable ? "Confirm frames to read" : "Choose a reference to read"
        }
        if let detail = measurement.spatialRatioDetail(horizontal: horizontal) { return detail }
        return horizontal
            ? "\(measurement.leftBorder) · \(measurement.rightBorder) px"
            : "\(measurement.topBorder) · \(measurement.bottomBorder) px"
    }

    // MARK: Controls

    private func bottomPanel(_ measurement: CardCenteringMeasurement) -> some View {
        VStack(spacing: 8) {
            if measurement.hasObservedPaths {
                standardControls(measurement)
            } else if isStraightening {
                straightenControls
            } else if let selection, measurement.segment(for: selection.guide) != nil {
                selectedGuideControls(selection, measurement: measurement)
            } else {
                standardControls(measurement)
            }

            Text("Guided estimate only. Not professional grading or a predicted grade.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
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
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
        return VStack(spacing: 8) {
            if measurement.hasObservedPaths {
                Button("Adjust with straight guides",systemImage: "slider.horizontal.3") {
                    selection = nil
                    model.beginManualGuides()
                }
                .buttonStyle(.bordered)
                .accessibilityHint("Switches to editable straight guides. Undo restores the detected curves.")
            }
            if measurement.hasReportableInnerTilt, let tilt = measurement.innerTiltDegrees {
                tiltRow(tilt, independentSlopes: measurement.innerFrameHasIndependentSlopes)
            }
            if !dynamicTypeSize.isAccessibilitySize, !measurement.referenceDefinition.isAvailable,
               measurement.geometryInnerQuad != nil {
                Text(guidance(for: measurement))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack {
                    confirmationControl(measurement)
                        .fixedSize(horizontal: true, vertical: false)
                    Spacer()
                    moreMenu(measurement)
                }
            } else {
                layout {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(guidance(for: measurement))
                            .font(.subheadline)
                            .fixedSize(horizontal: false, vertical: true)
                        if !measurement.warnings.isEmpty &&
                            (measurement.canReportRatios || measurement.outerAspectResidual > 0.04) {
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
                        .disabled(measurement.outerAspectResidual > 0.04)
                        .accessibilityLabel("Add an inner frame")
                        .accessibilityHint(measurement.outerAspectResidual > 0.04
                            ? "Move the red guides onto the card first."
                            : "Adds editable cyan guides inside the card.")
                    } else if !measurement.canReportRatios {
                        confirmationControl(measurement)
                    }

                    moreMenu(measurement)
                }
            }
        }
    }

    @ViewBuilder private func confirmationControl(_ measurement: CardCenteringMeasurement) -> some View {
        if measurement.referenceDefinition.isAvailable {
            Button("Confirm", systemImage: "checkmark") { model.confirmFrames() }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(!measurement.hasValidFrameGeometry)
                .accessibilityLabel("Confirm frames")
                .accessibilityHint("Accepts the reviewed card edges and selected reference.")
        } else {
            referenceMenu(measurement, title: "Choose Reference")
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(!measurement.hasValidFrameGeometry)
        }
    }

    private func referenceMenu(_ measurement: CardCenteringMeasurement, title: String) -> some View {
        Menu {
            Section("Cyan guides follow…") {
                ForEach(CardCenteringReferenceDefinition.userChoices, id: \.self) { reference in
                    Button(reference.label) { model.confirmFrames(reference: reference) }
                }
            }
            Button("No usable reference") { model.clearReference() }
        } label: {
            Label(title, systemImage: "viewfinder")
        }
        .accessibilityHint("Choose what the cyan guides follow to confirm both reviewed frames and show a geometric estimate.")
    }

    /// The print's tilt against the card edge, kept clear of the photo so it
    /// never covers an edge being lined up.
    private func tiltRow(_ tilt: Double, independentSlopes: Bool) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10))
            : AnyLayout(HStackLayout(spacing: 10))
        return layout {
            Label {
                if independentSlopes {
                    Text("Inner edge angles vary")
                } else {
                    Text("Inner frame tilted \(abs(tilt), specifier: "%.2f")° \(tilt > 0 ? "clockwise" : "counterclockwise")")
                        .monospacedDigit()
                }
            } icon: {
                Image(systemName: tilt > 0 ? "rotate.right" : "rotate.left")
            }
            .font(.subheadline.weight(.semibold))
            .fixedSize(horizontal: false, vertical: true)
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
#if DEBUG
        if let design = measurement.reviewedDesign, measurement.hasValidFrameGeometry {
            let region = measurement.referenceDefinition == .matchedPrintedBorder ? "printed frame" : "artwork frame"
            let placement = measurement.referenceDefinition == .matchedPrintedBorder ? "Printed frame" : "Artwork"
            return measurement.canReportRatios
                ? "\(placement) placement compared with \(design.label)."
                : "Check the card edges and the \(region) for \(design.label), then confirm."
        }
#endif
        if measurement.outerAspectResidual > 0.04 {
            return "The card edge wasn't identified reliably. Move the red guides onto the card first."
        }
        if measurement.geometryInnerQuad == nil {
            return "No inner frame found. Add one to begin."
        }
        if !measurement.hasValidFrameGeometry {
            return "Keep each cyan line inside the red edge."
        }
        if !measurement.canReportRatios {
            if !measurement.referenceDefinition.isAvailable {
                return "Check both frames, then choose what the cyan guides follow."
            }
            return "Check both frames, then confirm."
        }
        return measurement.referenceDefinition.isUserSelected
            ? "Geometric estimate · \(measurement.referenceDefinition.label.lowercased()) chosen by you."
            : "\(measurement.referenceDefinition.label). Frames reviewed by you."
    }

    private func moreMenu(_ measurement: CardCenteringMeasurement) -> some View {
        Menu {
            referenceMenu(measurement, title: "Change Reference")
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
            .disabled(measurement.hasObservedPaths)
            Button("Exact Values…", systemImage: "slider.horizontal.3") {
                isShowingExactValues = true
            }
            .disabled(measurement.hasObservedPaths)
            Button("Compare Perspective…", systemImage: "rectangle.on.rectangle") {
                reviewRequest = .init()
            }
            .disabled(!measurement.hasValidFrameGeometry || measurement.hasObservedPaths)
            Divider()
            Button("Reset Guides", systemImage: "arrow.counterclockwise", role: .destructive) {
                selection = nil
                model.resetGuides()
            }
            .disabled(!model.canResetGuides)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
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
                value = measurement.innerFrameHasIndependentSlopes ? "Angles vary" : measurement.hasReportableInnerTilt
                    ? String(format: "%.2f° %@", abs(tilt), tilt > 0 ? "clockwise" : "counterclockwise")
                    : "Square"
                hint = measurement.innerFrameHasIndependentSlopes
                    ? "The arrows turn all four edges together by 0.05°."
                    : "The arrows tilt 0.05°. Ease back toward square and it snaps."
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
                        precisionCommitAction.commitActiveAndDismiss()
                        focusedEdgeField = nil
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
        .sheet(item: $edgeReviewRequest) { request in
            CardCenteringReviewSheet(model: model, request: request)
        }
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
                confirmationControl(measurement)
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
                precisionNumber(precisionSide.isVertical ? "Horizontal position (native px)" : "Vertical position (native px)", value: line.position, step: 0.1, currentValue: {
                    guard model.imageRevision == revision else { return nil }
                    return model.precisionMeasurement?.precisionLine(side, frame: frame)?.position
                }) {
                    guard model.imageRevision == revision else { return }
                    model.updatePrecisionSide(side, frame: frame, position: $0)
                }
                .id("precision-position")
                precisionNumber("Angle (degrees)", value: line.angle, step: 0.01, currentValue: {
                    guard model.imageRevision == revision else { return nil }
                    return model.precisionMeasurement?.precisionLine(side, frame: frame)?.angle
                }) {
                    guard model.imageRevision == revision else { return }
                    model.updatePrecisionSide(side, frame: frame, angle: $0)
                }
                Slider(value: $nativeDetailProgress, in: 0...1) {
                    Text("Detail position along side")
                }
                .accessibilityValue("\(Int(nativeDetailProgress * 100)) percent along side")
                nativeDetail.id("native-detail")
                boundaryAlternatives
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

    @ViewBuilder private var boundaryAlternatives: some View {
        if let measurement = model.precisionMeasurement {
            let candidates = measurement.reviewCandidates(frame: precisionFrame, side: precisionSide)
            if !candidates.isEmpty {
                DisclosureGroup("Other detected edges (\(candidates.count))") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Compare each edge with the photo. Using one moves only this guide; you can undo the choice.")
                            .font(.footnote).foregroundStyle(.secondary)
                        ForEach(Array(candidates.prefix(showsAllBoundaryCandidates ? candidates.count : 6))) { candidate in
                            let line = candidate.nativeLine
                            let position = precisionSide.isVertical ? (line.start.x + line.end.x) / 2 : (line.start.y + line.end.y) / 2
                            Button {
                                precisionCommitAction.commitActiveAndDismiss()
                                model.selectBoundaryCandidate(candidate.id)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Use edge at \(position, specifier: "%.1f") px")
                                    Text(candidate.proposedRole.label).font(.subheadline)
                                    Text(candidate.selectionReason == .detectorProposal ? "Starting proposal" : "Alternative · identity needs review")
                                        .font(.caption).foregroundStyle(.secondary)
                                    if let stations = candidate.observedPointStations {
                                        Text("Straight guide approximates \(stations.count) of 61 observed positions; inspect the gaps.")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.vertical, 4)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityHint(precisionFrame == .outer ? "Use as the physical card edge. Other guides stay fixed." : "Use as the selected inner reference. Other guides stay fixed.")
                            Button("Compare this edge", systemImage: "rectangle.on.rectangle") {
                                precisionCommitAction.commitActiveAndDismiss()
                                model.compareBoundary(candidate.id)
                                edgeReviewRequest = .init(candidateID: candidate.id, frame: candidate.frame, side: candidate.side)
                            }
                            .frame(minHeight: 44)
                            .accessibilityLabel("Compare \(precisionSide.label.lowercased()) edge at \(position.formatted(.number.precision(.fractionLength(1)))) native pixels")
                        }
                        if candidates.count > 6 {
                            Button(showsAllBoundaryCandidates ? "Show nearest edges" : "Show all \(candidates.count) edges") {
                                showsAllBoundaryCandidates.toggle()
                            }
                        }
                    }
                }
            }
        }
    }

    private func precisionNumber(_ label: String, value: Double, step: Double,
                                 currentValue: @escaping () -> Double?, update: @escaping (Double) -> Void) -> some View {
        CardCenteringPrecisionNumberField(label: label,
            accessibilityName: "\(precisionFrame.label) \(precisionSide.rawValue) \(label)",
            value: value, step: step, currentValue: currentValue, commitAction: precisionCommitAction, update: update)
            .id("\(model.imageRevision)-\(precisionFrame.rawValue)-\(precisionSide.rawValue)-\(label)")
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

/// An opt-in, per-host diagnostic sink. No global observer or logging is installed
/// by the app. Tests supply synthetic input and retain events on one monotonic
/// clock, without adding tasks, waiting, or changing focus from the observer.
@MainActor
final class CardCenteringPrecisionTrace {
    struct Event {
        let uptimeNanoseconds: UInt64
        let name: String
        let field: String
        let focused: Bool?
        let draft: String?
        let value: Double?
        let detail: String?
    }

    let receive: (Event) -> Void

    init(receive: @escaping (Event) -> Void) { self.receive = receive }

    func record(_ name: String, field: String = "fixture", focused: Bool? = nil,
                draft: String? = nil, value: Double? = nil, detail: String? = nil) {
        receive(Event(uptimeNanoseconds: DispatchTime.now().uptimeNanoseconds,
                      name: name, field: field, focused: focused, draft: draft,
                      value: value, detail: detail))
    }
}

private struct CardCenteringPrecisionTraceKey: EnvironmentKey {
    static let defaultValue: CardCenteringPrecisionTrace? = nil
}

extension EnvironmentValues {
    var centeringPrecisionTrace: CardCenteringPrecisionTrace? {
        get { self[CardCenteringPrecisionTraceKey.self] }
        set { self[CardCenteringPrecisionTraceKey.self] = newValue }
    }
}

/// The toolbar invokes this boundary synchronously. An observed SwiftUI focus
/// change cannot identify which editing session an earlier Done belonged to.
@MainActor
final class CardCenteringPrecisionCommitAction {
    fileprivate weak var activeEditor: CardCenteringPrecisionEditor?
    private var nextSessionToken: UInt64 = 0
    private var latestBoundaries: [String: UInt64] = [:]
#if DEBUG
    // Per-host seam for holding the real removal finalizer in native tests.
    // Done and ordinary blur never pass through this scheduler.
    var removalCompletionSchedulerForTesting: ((@escaping @MainActor () -> Void) -> Void)?
#endif

    fileprivate func scheduleRemovalCompletion(_ completion: @escaping @MainActor () -> Void) {
        var delivered = false
        let once: @MainActor () -> Void = {
            guard !delivered else { return }
            delivered = true
            completion()
        }
#if DEBUG
        if let removalCompletionSchedulerForTesting {
            removalCompletionSchedulerForTesting(once)
            return
        }
#endif
        DispatchQueue.main.async { once() }
    }

    fileprivate func makeSessionToken() -> UInt64 {
        nextSessionToken &+= 1
        return nextSessionToken
    }

    fileprivate func consume(_ token: UInt64, field: String) -> Bool {
        guard token >= latestBoundaries[field, default: 0] else { return false }
        latestBoundaries[field] = token
        return true
    }

    fileprivate func ownsBoundary(_ token: UInt64, field: String) -> Bool {
        latestBoundaries[field] == token
    }

    func commitActiveAndDismiss() {
        // Publishing may focus another field. Keep both commit and dismissal
        // attached to the editor captured by this action.
        let editor = activeEditor
        editor?.done()
    }
}

/// Keep partially typed localized numbers intact. Only this precision input
/// owns a native editing session; the surrounding controls remain SwiftUI.
struct CardCenteringPrecisionNumberField: View {
    let label: String
    let accessibilityName: String
    let value: Double
    let step: Double
    let currentValue: () -> Double?
    let commitAction: CardCenteringPrecisionCommitAction
    let update: (Double) -> Void
    @Environment(\.locale) private var locale
    @Environment(\.centeringPrecisionTrace) private var diagnosticTrace
    @StateObject private var editor = CardCenteringPrecisionEditor()

    static func parsedValue(_ text: String, locale: Locale) -> Double? {
        LocalizedNumberInput.parse(text, locale: locale)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label).font(.subheadline)
            CardCenteringPrecisionNativeField(label: label, value: value, editor: editor,
                context: .init(field: accessibilityName, locale: locale, currentValue: currentValue,
                               update: update, trace: diagnosticTrace), commitAction: commitAction)
                .fixedSize(horizontal: false, vertical: true)
            Stepper(label, onIncrement: { update(value + step) }, onDecrement: { update(value - step) })
                .labelsHidden()
                .disabled(editor.isEditing)
                .accessibilityLabel(accessibilityName)
                .accessibilityValue("\(value)")
            if let inputReason = editor.inputReason {
                Label(inputReason, systemImage: "exclamationmark.triangle")
                    .font(.footnote).foregroundStyle(.primary)
            }
        }
        .onChange(of: editor.isEditing) { _, focused in editor.observeFocus(focused) }
    }
}

@MainActor
fileprivate final class CardCenteringPrecisionEditor: NSObject, ObservableObject, UITextFieldDelegate {
    struct Context {
        let field: String
        let locale: Locale
        let currentValue: () -> Double?
        let update: (Double) -> Void
        let trace: CardCenteringPrecisionTrace?

        func formatted(_ value: Double) -> String {
            value.formatted(.number.precision(.fractionLength(2)).locale(locale))
        }
    }

    @MainActor
    private final class Session {
        let id: UInt64
        let inputID: ObjectIdentifier
        let boundaryToken: UInt64
        let commitAction: CardCenteringPrecisionCommitAction
        let context: Context
        let initialDisplay: String
        var consumed = false

        init(id: UInt64, input: CardCenteringPrecisionTextInput, context: Context,
             commitAction: CardCenteringPrecisionCommitAction, initialDisplay: String) {
            self.id = id; self.inputID = ObjectIdentifier(input)
            self.boundaryToken = commitAction.makeSessionToken()
            self.commitAction = commitAction
            self.context = context; self.initialDisplay = initialDisplay
        }
    }

    private struct Snapshot {
        let session: Session
        let input: CardCenteringPrecisionTextInput
        let draft: String
    }

    @Published private(set) var isEditing = false
    @Published private(set) var inputReason: String?
    private weak var input: CardCenteringPrecisionTextInput?
    private weak var commitAction: CardCenteringPrecisionCommitAction?
    private var context: Context?
    private var session: Session?
    private var nextSessionID: UInt64 = 0
    private var lastConsumedSessionID: UInt64 = 0
    private var observedFocus = false
    private var removed = false
    private var nativeLifetime: UInt64 = 0
    private var displayedValue: Double?

    func configure(_ input: CardCenteringPrecisionTextInput, value: Double,
                   context: Context, commitAction: CardCenteringPrecisionCommitAction) {
        if let previous = self.input, previous !== input {
            // A replacement native control cannot inherit the departing
            // control's still-open editing context.
            detach(previous)
        }
        self.input = input
        self.context = context
        self.commitAction = commitAction
        guard !removed else { return }
        if displayedValue != value {
            record("value.observed", detail: "old=\(String(describing: displayedValue)) new=\(value)")
            displayedValue = value
        }
        // A's publication can arrive after B has already started. Native
        // editing ownership, not a delayed SwiftUI focus value, protects B.
        if !input.isFirstResponder, session == nil {
            input.text = context.formatted(context.currentValue() ?? value)
            record("draft.formatted")
        }
    }

    func appear(_ input: CardCenteringPrecisionTextInput) {
        guard self.input === input else { return }
        nativeLifetime &+= 1
        removed = false
        observedFocus = input.isFirstResponder
        if session == nil, let context, let value = context.currentValue() {
            input.text = context.formatted(value)
        }
        record("view.appear", detail: "lifetime=\(nativeLifetime) context=\(ObjectIdentifier(input))")
        if isEditing, !input.isFirstResponder {
            let lifetime = nativeLifetime
            // Reattachment may supersede the old removal's UI cleanup without
            // starting another edit. Refresh this lifetime after reconciliation,
            // provided no intervening refocus has established a new session.
            DispatchQueue.main.async { [weak self, weak input] in
                guard let self, let input, self.input === input,
                      !removed, nativeLifetime == lifetime,
                      session == nil, !input.isFirstResponder, isEditing else { return }
                isEditing = false
            }
        }
    }

    func observeFocus(_ focused: Bool) {
        guard !removed else { return }
        let old = observedFocus
        observedFocus = focused
        record("focus.observed", detail: "old=\(old) new=\(focused)")
    }

    func begin(_ input: CardCenteringPrecisionTextInput, initialDisplay: String? = nil) {
        guard !removed, self.input === input, let context, let commitAction else { return }
        nextSessionID &+= 1
        let editing = Session(id: nextSessionID, input: input, context: context,
                              commitAction: commitAction,
                              initialDisplay: initialDisplay ?? input.text ?? "")
        session = editing
        commitAction.activeEditor = self
        record("editing.begin", detail: "session=\(editing.id)")
        isEditing = true
    }

    func changed(_ input: CardCenteringPrecisionTextInput) {
        guard !removed, self.input === input, input.isFirstResponder else { return }
        // If UIKit refused dismissal after Done, subsequent typing belongs to
        // a fresh edit, never to the consumed snapshot.
        if session == nil || session?.consumed == true {
            let baseline = context.flatMap { context in context.currentValue().map(context.formatted) }
            begin(input, initialDisplay: baseline)
        }
        record("draft.native-observed", detail: "session=\(session?.id ?? 0)")
    }

    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        if let input = textField as? CardCenteringPrecisionTextInput, input.isFirstResponder,
           session == nil || session?.consumed == true {
            // Capture the pre-edit display if a previous Done could not dismiss
            // UIKit. Capturing from editingChanged would mistake B for untouched.
            begin(input)
        }
        return true
    }

    private func snapshot(_ input: CardCenteringPrecisionTextInput) -> Snapshot? {
        guard !removed, self.input === input, let session,
              session.inputID == ObjectIdentifier(input) else { return nil }
        return Snapshot(session: session, input: input, draft: input.text ?? "")
    }

    func captureEndEditing(_ input: CardCenteringPrecisionTextInput) -> (() -> Void)? {
        guard let ended = snapshot(input) else { return nil }
        // The native resignation captures A before UIKit can begin B. Replay
        // of this callback can only finish A; it never reads the live draft.
        return { [weak self] in self?.end(ended) }
    }

    func captureWindowDetachment(_ input: CardCenteringPrecisionTextInput) -> (() -> Void)? {
        guard let context, let trace = context.trace else { return nil }
        let field = context.field, identity = ObjectIdentifier(input)
        return {
            trace.record("view.window-detached", field: field,
                         detail: "context=\(identity)")
        }
    }

    private func end(_ ended: Snapshot) {
        commit(ended)
        guard session === ended.session else { return }
        session = nil
        if !ended.input.isFirstResponder {
            if commitAction?.activeEditor === self { commitAction?.activeEditor = nil }
            isEditing = false
        }
    }

    func done() {
        guard let input, let intended = snapshot(input) else { return }
        record("done.delivered", snapshot: intended)
        commit(intended)
        // An update callback may already have refocused this same native
        // control. Its new session does not belong to this Done action.
        guard session === intended.session else { return }
        record("done.dismiss-requested", snapshot: intended)
        _ = input.resignFirstResponder()
        record("done.focus-reset-returned", snapshot: intended)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        record("submit.delivered")
        done()
        return false
    }

    func disappear(_ input: CardCenteringPrecisionTextInput) {
        guard !removed, self.input === input else { return }
        let departing = snapshot(input)
        let departingAction = departing?.session.commitAction ?? commitAction
        let departingContext = departing?.session.context ?? context
        let departingDraft = input.text
        let departingFocus = observedFocus
        let departingInputID = ObjectIdentifier(input)
        let lifetime = nativeLifetime
        // Native removal occurs inside SwiftUI reconciliation. Consume and
        // validate its immutable edit now, but publish the departing model
        // value only after that reconciliation has returned. Done and ordinary
        // focus loss keep their synchronous commit boundary.
        removed = true
        session = nil
        if commitAction?.activeEditor === self { commitAction?.activeEditor = nil }
        let publication = departing.flatMap { commit($0, deferPublication: true) }
        record("view.removal-captured", snapshot: departing, detail: "lifetime=\(lifetime)")
        _ = input.resignFirstResponder()
        // Retain the captured owner until completion: a weak reference could
        // drop a legitimate removal commit when SwiftUI releases this editor.
        let complete: @MainActor () -> Void = { [self] in
            publication?()
            if removed, nativeLifetime == lifetime, isEditing { isEditing = false }
            // Teardown waits for this completion event, not merely native
            // removal, so no queued commit outlives its owned test/view case.
            departingContext?.trace?.record("view.disappear", field: departingContext?.field ?? "fixture",
                focused: departingFocus, draft: departingDraft,
                value: departingContext?.currentValue(), detail: "lifetime=\(lifetime) context=\(departingInputID)")
        }
        if let departingAction { departingAction.scheduleRemovalCompletion(complete) }
        else { DispatchQueue.main.async { complete() } }
    }

    func detach(_ input: CardCenteringPrecisionTextInput) {
        guard self.input === input else { return }
        input.prepareWindowDetachment()
        disappear(input)
        input.delegate = nil
        input.editor = nil
        self.input = nil
    }

    @discardableResult
    private func commit(_ intended: Snapshot, deferPublication: Bool = false) -> (@MainActor () -> Void)? {
        let editing = intended.session
        guard !editing.consumed else { return nil }
        editing.consumed = true
        // This also closes invalid and untouched drafts. A delayed older end
        // cannot publish after a newer explicit boundary, even if that field
        // has been recreated with a different editor instance.
        guard editing.id >= lastConsumedSessionID,
              editing.commitAction.consume(editing.boundaryToken, field: editing.context.field) else { return nil }
        lastConsumedSessionID = editing.id
        record("commit.enter", snapshot: intended)
        record("commit.session-consumed", snapshot: intended)
        guard let authoritative = editing.context.currentValue() else {
            record("commit.context-invalid", snapshot: intended)
            return nil
        }
        let ownsDisplay = !removed && session === editing && input === intended.input
        // Compare to the display the user actually entered, preserving the
        // full authoritative Double when that rounded text was untouched.
        guard intended.draft != editing.initialDisplay else {
            if ownsDisplay { inputReason = nil }
            record("commit.unchanged-display", snapshot: intended)
            return nil
        }
        guard let parsed = CardCenteringPrecisionNumberField.parsedValue(intended.draft, locale: editing.context.locale) else {
            record("commit.parse-invalid", snapshot: intended)
            if ownsDisplay {
                inputReason = "Enter a finite number using your region’s decimal separator."
                intended.input.text = editing.context.formatted(authoritative)
                record("draft.restored-invalid")
            } else {
                record("draft.discarded-invalid", snapshot: intended)
            }
            return nil
        }
        record("commit.parse-valid", snapshot: intended, detail: "parsed=\(parsed)")
        if ownsDisplay {
            inputReason = nil
            intended.input.text = editing.context.formatted(authoritative)
            record("draft.restored-before-update")
        }
        let needsUpdate = parsed != authoritative
        let publish: @MainActor () -> Void = { [self] in
            guard editing.id == lastConsumedSessionID,
                  editing.commitAction.ownsBoundary(editing.boundaryToken, field: editing.context.field) else {
                record("commit.superseded", snapshot: intended)
                return
            }
            guard let current = editing.context.currentValue() else {
                record("commit.context-invalid", snapshot: intended)
                return
            }
            // A non-text model action can also supersede a departing edit.
            // Never replay an old removal over a newer authoritative value.
            guard !deferPublication || current == authoritative || current == parsed else {
                record("commit.superseded", snapshot: intended, detail: "authoritative value changed")
                return
            }
            if needsUpdate, parsed != current {
                record("commit.update-call", snapshot: intended, detail: "parsed=\(parsed)")
                editing.context.update(parsed)
                record("commit.update-returned", snapshot: intended)
            }
            // Read accepted geometry synchronously. Removal completions never
            // format a control that could already belong to a newer draft.
            if !deferPublication, !removed, session === editing, input === intended.input,
               let accepted = editing.context.currentValue() {
                intended.input.text = editing.context.formatted(accepted)
                record("draft.formatted")
            }
            record("commit.exit", snapshot: intended)
        }
        if deferPublication { return publish }
        publish()
        return nil
    }

    private func record(_ name: String, snapshot: Snapshot? = nil, detail: String? = nil) {
        guard let context = snapshot?.session.context ?? context else { return }
        let ownership = snapshot.map {
            "session=\($0.session.id) boundary=\($0.session.boundaryToken) context=\(ObjectIdentifier($0.input))"
        }
        context.trace?.record(name, field: context.field, focused: observedFocus,
                              draft: snapshot?.draft ?? input?.text,
                              value: context.currentValue(),
                              detail: [ownership, detail].compactMap { $0 }.joined(separator: " "))
    }
}

/// The native responder boundary supplies an immutable end event. SwiftUI's
/// coalesced focus notifications are used only to render/observe UI state.
@MainActor
final class CardCenteringPrecisionTextInput: UITextField {
    fileprivate weak var editor: CardCenteringPrecisionEditor?
    private var windowDetachment: (() -> Void)?

    fileprivate func prepareWindowDetachment() {
        if windowDetachment == nil { windowDetachment = editor?.captureWindowDetachment(self) }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            windowDetachment = nil
            editor?.appear(self)
        } else {
            let detached = windowDetachment
            windowDetachment = nil
            detached?()
        }
    }

    override func willMove(toWindow newWindow: UIWindow?) {
        // Capture removal while this native view still owns its edit. A later
        // SwiftUI disappearance notification cannot consume a refocused draft.
        if window != nil, newWindow == nil {
            prepareWindowDetachment()
            editor?.disappear(self)
        }
        super.willMove(toWindow: newWindow)
    }

    override func becomeFirstResponder() -> Bool {
        let alreadyFocused = isFirstResponder
        let succeeded = super.becomeFirstResponder()
        if succeeded && !alreadyFocused { editor?.begin(self) }
        return succeeded
    }

    func captureEndEditing() -> (() -> Void)? { editor?.captureEndEditing(self) }

    override func resignFirstResponder() -> Bool {
        let ended = captureEndEditing()
        let succeeded = super.resignFirstResponder()
        if succeeded { ended?() }
        return succeeded
    }

    @objc fileprivate func editingChanged() { editor?.changed(self) }
}

private struct CardCenteringPrecisionNativeField: UIViewRepresentable {
    let label: String
    let value: Double
    let editor: CardCenteringPrecisionEditor
    let context: CardCenteringPrecisionEditor.Context
    let commitAction: CardCenteringPrecisionCommitAction

    func makeUIView(context: Context) -> CardCenteringPrecisionTextInput {
        let input = CardCenteringPrecisionTextInput(frame: .zero)
        input.editor = editor
        input.delegate = editor
        input.keyboardType = .numbersAndPunctuation
        input.returnKeyType = .done
        input.borderStyle = .roundedRect
        input.adjustsFontForContentSizeCategory = true
        input.addTarget(input, action: #selector(CardCenteringPrecisionTextInput.editingChanged), for: .editingChanged)
        input.setContentHuggingPriority(.defaultLow, for: .horizontal)
        updateUIView(input, context: context)
        return input
    }

    func updateUIView(_ input: CardCenteringPrecisionTextInput, context: Context) {
        input.placeholder = label
        input.accessibilityLabel = self.context.field
        input.font = UIFontMetrics(forTextStyle: .body).scaledFont(for:
            .monospacedDigitSystemFont(ofSize: UIFont.systemFontSize, weight: .regular))
        editor.configure(input, value: value, context: self.context, commitAction: commitAction)
    }

    static func dismantleUIView(_ input: CardCenteringPrecisionTextInput, coordinator: ()) {
        input.editor?.detach(input)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: CardCenteringPrecisionTextInput, context: Context) -> CGSize? {
        CGSize(width: proposal.width ?? uiView.intrinsicContentSize.width,
               height: uiView.intrinsicContentSize.height)
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
    var alternative: CardCenteringNativeLine? = nil
    var supportBands: [CardCenteringSampleBand] = []
    var excludedBands: [CardCenteringSampleBand] = []

    var body: some View {
        ZStack {
            Image(uiImage: image).resizable().interpolation(.none)
            GeometryReader { proxy in
                if let alternative {
                    Canvas { context, size in
                        func point(_ p: CardCenteringPoint) -> CGPoint {
                            .init(x: (p.x - origin.x) * size.width / Double(pixelWidth),
                                y: (p.y - origin.y) * size.height / Double(pixelHeight))
                        }
                        func line(_ a: CardCenteringPoint, _ b: CardCenteringPoint, color: Color, width: Double, dash: [CGFloat] = []) {
                            var path = Path(); path.move(to: point(a)); path.addLine(to: point(b))
                            context.stroke(path, with: .color(.black.opacity(0.75)), style: .init(lineWidth: width + 1, dash: dash))
                            context.stroke(path, with: .color(color), style: .init(lineWidth: width, dash: dash))
                        }
                        for band in supportBands { line(band.start, band.end, color: .green.opacity(0.7), width: 5) }
                        for band in excludedBands { line(band.start, band.end, color: .orange, width: 5, dash: [5,4]) }
                        line(alternative.start, alternative.end, color: .yellow, width: 2, dash: [6,4])
                    }
                }
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
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
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
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
