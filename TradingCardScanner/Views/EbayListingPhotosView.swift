import PhotosUI
import SwiftData
import CoreTransferable
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Recheck ownership when the share system requests the file, including if
/// access changes after the share button was rendered.
struct CollectorToolsPhotoArchive: Transferable {
    let url: URL
    let cardCount: Int

    @MainActor
    func authorizedURL(using store: CollectorToolsStore) throws -> URL {
        guard store.canPreparePhotos(cardCount: cardCount) else { throw AccessError.purchaseRequired }
        return url
    }

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .zip) { archive in
            let url = try await archive.authorizedURL(using: .shared)
            EbayListingPhotoExport.retainForShare(url)
            return SentTransferredFile(url)
        }
    }

    private enum AccessError: LocalizedError {
        case purchaseRequired
        var errorDescription: String? { "Collector Tools is required to export multiple cards." }
    }
}

private struct ListingPhotoShareFile: Transferable {
    let url: URL

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .jpeg) { photo in
            EbayListingPhotoExport.retainForShare(photo.url)
            return SentTransferredFile(photo.url)
        }
    }
}

struct EbayListingPhotosView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject private var collectorTools = CollectorToolsStore.shared
    @State private var isShowingOffer = false
    private enum Mode: String, CaseIterable, Identifiable {
        case single
        case batch

        var id: String { rawValue }

        var title: String {
            switch self {
            case .single: return "Single card"
            case .batch: return "Batch"
            }
        }
    }

    private enum Side: String, CaseIterable, Identifiable {
        case front
        case back

        var id: String { rawValue }

        var title: String {
            rawValue.capitalized
        }

        var systemImage: String {
            switch self {
            case .front: return "rectangle.portrait"
            case .back: return "rectangle.portrait.fill"
            }
        }
    }

    fileprivate enum GenerationScope: String, CaseIterable, Identifiable {
        case both = "Both sides"
        case front = "Front only"
        case back = "Back only"

        var id: Self { self }
    }

    fileprivate enum PhotoSource {
        case photo(PhotosPickerItem)
        case file(URL)
    }

    fileprivate struct BatchPair: Identifiable {
        let id = UUID()
        var front: PhotoSource
        var back: PhotoSource
        var frontPreview: UIImage?
        var backPreview: UIImage?
        var folderName: String
    }

    private struct InspectedPhoto: Identifiable {
        let id: Int
        let url: URL
        let dimensions: EbayListingPhotoExport.PixelDimensions
    }

    private struct BatchProgress: Equatable {
        let current: Int
        let total: Int
    }

    /// Preview identity must be cheap to compare when unrelated UI state changes.
    /// Completion changes isLoading, so a finished import starts its own preview.
    private struct PreviewRequest: Equatable {
        let generation: Int
        let isLoading: Bool
    }

    @State private var mode: Mode = .single
    @State private var isWorkflowActive = false
    @State private var frontPickerItem: PhotosPickerItem?
    @State private var backPickerItem: PhotosPickerItem?
    @State private var frontData: Data?
    @State private var backData: Data?
    @State private var generationScope: GenerationScope = .both
    @State private var frontIsLoading = false
    @State private var backIsLoading = false
    @State private var photoPickerSide: Side = .front
    @State private var isShowingPhotoPicker = false
    @State private var cameraSide: Side?
    @State private var isShowingFileImporter = false
    @State private var fileImportSide: Side?
    @State private var singleGeneration = 0
    @State private var frontLoadGeneration = 0
    @State private var backLoadGeneration = 0
    @State private var isPreparingSingle = false
    @State private var singleProcessingTask: Task<Void, Never>?
    @State private var singleOutput: EbayListingPhotoExport.Output?
    @State private var singleOutputDirectory: URL?
    @State private var errorMessage: String?

    @State private var batchPickerItems: [PhotosPickerItem] = []
    @State private var batchSourceCount = 0
    @State private var batchPairs: [BatchPair] = []
    @State private var batchSelectionGeneration = 0
    @State private var batchPreviewGeneration = 0
    @State private var batchProcessingTask: Task<Void, Never>?
    @State private var isPreparingBatch = false
    @State private var batchProgress: BatchProgress?
    @State private var batchDirectory: URL?
    @State private var batchArchiveURL: URL?
    @State private var batchFailures: [String] = []
    @State private var batchErrorMessage: String?
    @State private var singleArchiveURL: URL?
    @State private var isSavingToPhotos = false
    @State private var savingPhotoDirectory: URL?
    @State private var saveConfirmation: String?
    @State private var inspectedPhoto: InspectedPhoto?
    @State private var isReviewingOutput = false
    @State private var selectedOutputIndex = 0
    @State private var isUpdatingOrder = false
    @State private var frontStyles: [UIImage] = []
    @State private var backStyles: [UIImage] = []
    @State private var isShowingCollection = false
    @State private var collectionTitle: String?
    @State private var collectionSubtitle: String?
    @State private var isShowingStyles = false
    @State private var filesExport: ListingFilesExport?
    private let listingButtonAccent = Color(red: 0.043, green: 0.478, blue: 0.514)
    private var listingAccent: Color {
        colorScheme == .dark ? Color(red: 0.247, green: 0.761, blue: 0.796) : listingButtonAccent
    }

    init() {
#if DEBUG
        // Exercise file ownership and full-screen inspection without opening
        // a person's photo library. This route uses only generated pixels.
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-ui_debug_route"),
           arguments.indices.contains(index + 1), arguments[index + 1] == "ListingPhotos" {
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            func fixture(_ color: UIColor) -> Data? {
                UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1260), format: format).image { context in
                    color.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 900, height: 1260))
                    UIColor.black.setStroke()
                    context.stroke(CGRect(x: 30, y: 30, width: 840, height: 1200))
                    ("Synthetic listing fixture" as NSString).draw(at: CGPoint(x: 80, y: 80),
                        withAttributes: [.font: UIFont.systemFont(ofSize: 32), .foregroundColor: UIColor.black])
                }.jpegData(compressionQuality: 0.9)
            }
            let stateIndex = arguments.firstIndex(of: "-ui_debug_state")
            let state = stateIndex.flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
            if state == "styles" { _isShowingStyles = State(initialValue: true) }
            if state == "collection" {
                _collectionTitle = State(initialValue: "Sample Card")
                _collectionSubtitle = State(initialValue: "Sample Set · 041/198 · Holo Rare")
            }
            if state != "empty" && state != "back" {
                _frontData = State(initialValue: fixture(.systemTeal))
            }
            if state != "empty" && state != "front" {
                _backData = State(initialValue: fixture(.systemPurple))
            }
        }
#endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if isReviewingOutput, let singleOutput {
                    outputGrid(singleOutput)
                } else {
                    Picker("Workflow", selection: $mode) {
                        ForEach(Mode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .disabled(isPreparingSingle || isPreparingBatch)
                    if mode == .single {
                        singleContent
                    } else {
                        batchContent
                    }
                }
            }
            .padding(16)
            .contentWidthLimit(.standard)
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .tint(listingAccent)
        .navigationTitle(isReviewingOutput ? "\(singleOutput?.urls.count ?? 0) Photos" : "Listing Photos")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isReviewingOutput)
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if mode == .single { singleActionBar }
        }
        .sheet(isPresented: $isShowingOffer) { CollectorToolsOfferView() }
        .sheet(isPresented: $isShowingCollection) {
            ListingCollectionPicker { title, subtitle, data in
                startOverSingle()
                collectionTitle = title
                collectionSubtitle = subtitle
                receiveCameraCapture(data, for: .front)
            }
        }
        .sheet(isPresented: $isShowingStyles) {
            ListingPhotoStylesSheet(scope: generationScope, hasFront: frontData != nil,
                                    hasBack: backData != nil, frontPreviews: frontStyles,
                                    backPreviews: backStyles, accent: listingAccent) { scope in
                // Commit once, after dismissal, rather than invalidate the
                // source screen and generated files on every sheet selection.
                if generationScope != scope { generationScope = scope }
            }
        }
        .sheet(item: $filesExport) { export in
            ListingFilesExporter(urls: export.urls) { saved in
                if saved { saveConfirmation = "Saved listing photos to Files." }
            }
        }
        .toolbar {
            if isReviewingOutput {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isReviewingOutput = false
                    } label: { Label("Source photos", systemImage: "chevron.left") }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Back to source photos")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            } else if mode == .single {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let singleArchiveURL, let singleOutput {
                            ShareLink(item: CollectorToolsPhotoArchive(url: singleArchiveURL, cardCount: 1),
                                      preview: SharePreview("Listing photos", icon: Image(systemName: "doc.zipper"))) {
                                Label("Export ZIP", systemImage: "doc.zipper")
                            }
                            Button("Review \(singleOutput.urls.count) Photos", systemImage: "photo.on.rectangle") {
                                isReviewingOutput = true
                            }
                        }
                        Button("Use a card from Collection", systemImage: "rectangle.stack") { isShowingCollection = true }
                        Button("Photo Styles", systemImage: "slider.horizontal.3") { isShowingStyles = true }
                        Button("Start Over", systemImage: "arrow.counterclockwise", action: startOverSingle)
                    } label: {
                        Label("Photo options", systemImage: "ellipsis")
                    }
                    .labelStyle(.iconOnly)
                    .disabled(isPreparingSingle || frontIsLoading || backIsLoading)
                }
            }
            if mode == .batch, let batchArchiveURL,
               collectorTools.canPreparePhotos(cardCount: batchPairs.count) {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(
                        item: CollectorToolsPhotoArchive(url: batchArchiveURL, cardCount: batchPairs.count),
                        preview: SharePreview("Listing photos", icon: Image(systemName: "doc.zipper"))
                    ) {
                        Label("Export batch ZIP", systemImage: "doc.zipper")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Export the batch ZIP")
                }
            }
        }
        .onChange(of: frontPickerItem) { _, item in
            guard let item else { return }
            beginLoading(side: .front)
            let requestID = frontLoadGeneration
            Task { await loadSinglePhoto(.photo(item), side: .front, requestID: requestID) }
        }
        .onChange(of: backPickerItem) { _, item in
            guard let item else { return }
            beginLoading(side: .back)
            let requestID = backLoadGeneration
            Task { await loadSinglePhoto(.photo(item), side: .back, requestID: requestID) }
        }
        .onAppear {
            isWorkflowActive = true
#if DEBUG
            let arguments = ProcessInfo.processInfo.arguments
            if arguments.contains("ListingPhotos"), arguments.contains("generated"), singleOutput == nil {
                beginPreparingSingle()
            }
#endif
        }
        .onChange(of: generationScope) { _, _ in invalidateSingleOutput() }
        .task(id: PreviewRequest(generation: frontLoadGeneration, isLoading: frontIsLoading)) {
            frontStyles = []
            guard !frontIsLoading, let frontData else { return }
            do {
                let previews = try await EbayListingPhotoExport.makeStylePreviews(data: frontData, isBack: false)
                guard !Task.isCancelled else { return }
                frontStyles = previews
            } catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
        }
        .task(id: PreviewRequest(generation: backLoadGeneration, isLoading: backIsLoading)) {
            backStyles = []
            guard !backIsLoading, let backData else { return }
            do {
                let previews = try await EbayListingPhotoExport.makeStylePreviews(data: backData, isBack: true)
                guard !Task.isCancelled else { return }
                backStyles = previews
            } catch { if !Task.isCancelled { errorMessage = error.localizedDescription } }
        }
        .photosPicker(
            isPresented: $isShowingPhotoPicker,
            selection: photoPickerSide == .front ? $frontPickerItem : $backPickerItem,
            matching: .images
        )
        .task(id: batchPreviewGeneration) {
            await loadBatchPreviews(generation: batchPreviewGeneration)
        }
        .fullScreenCover(item: $cameraSide) { side in
            CenteringCameraView(configuration: .listingPhotos) { data in
                receiveCameraCapture(data, for: side)
            }
        }
        .fileImporter(
            isPresented: $isShowingFileImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: fileImportSide == nil
        ) { result in
            switch result {
            case let .success(urls):
                if let side = fileImportSide, let url = urls.first {
                    beginLoading(side: side)
                    let requestID = loadGeneration(for: side)
                    Task { await loadSinglePhoto(.file(url), side: side, requestID: requestID) }
                } else if fileImportSide == nil {
                    updateBatchPairs(sources: urls.map(PhotoSource.file))
                }
            case let .failure(error):
                if fileImportSide == nil {
                    batchErrorMessage = error.localizedDescription
                } else {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .fullScreenCover(item: $inspectedPhoto) { photo in
            ListingPhotoInspectorView(
                url: photo.url,
                nativeDimensions: photo.dimensions
            )
        }
        .onDisappear {
            // Full-screen inspection/capture temporarily hides this screen;
            // their files and selections still belong to the active workflow.
            guard cameraSide == nil, inspectedPhoto == nil,
                  !isShowingOffer, !isShowingFileImporter, !isShowingPhotoPicker,
                  !isShowingCollection, !isShowingStyles, filesExport == nil else { return }
            isWorkflowActive = false
            frontLoadGeneration &+= 1
            backLoadGeneration &+= 1
            singleGeneration &+= 1
            batchPreviewGeneration &+= 1
            singleProcessingTask?.cancel()
            singleProcessingTask = nil
            isPreparingSingle = false
            cancelBatch()
            removeSingleArtifacts()
            removeBatchArtifacts()
        }
    }

    @ViewBuilder
    private var singleContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(collectionTitle ?? (frontData == nil && backData == nil ? "Add your card" : "Your card"))
                    .font(.title2.bold())
                Text(collectionSubtitle ?? "Front, back, or both. Each side makes 5 photos.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 16)) : AnyLayout(HStackLayout(alignment: .top, spacing: 14))
            layout {
                singleSlot(side: .front, isReady: frontData != nil)
                singleSlot(side: .back, isReady: backData != nil)
            }
            if frontData != nil || backData != nil {
                Text("Tap a photo to replace it. Touch and hold for more.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                stylePreviewStrip
            }
            if frontData == nil && backData == nil {
                Button { isShowingCollection = true } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.stack.fill")
                            .foregroundStyle(listingAccent)
                            .frame(width: 36, height: 36)
                            .background(listingAccent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Use a card from Collection").font(.body.weight(.medium))
                            Text("Reuses a photo saved on this device").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(isPreparingSingle || frontIsLoading || backIsLoading)
            }
        }
        if let errorMessage {
            Text(errorMessage)
                .font(.footnote)
                .foregroundStyle(.red)
        }
    }

    private var expectedPhotoCount: Int {
        let both = frontData != nil && backData != nil
        return (frontData != nil && (!both || generationScope != .back) ? 5 : 0)
            + (backData != nil && (!both || generationScope != .front) ? 5 : 0)
    }

    private var stylePreviewStrip: some View {
        VStack(alignment: .leading, spacing: 4) {
            let headingLayout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout())
            headingLayout {
                Text("\(expectedPhotoCount) photos, in upload order").font(.subheadline.weight(.semibold))
                if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                Button("Styles") { isShowingStyles = true }.font(.subheadline).frame(minHeight: 44)
            }
            Text("Full view plus all four corners, for each side.")
                .font(.caption).foregroundStyle(.secondary)
            let both = frontData != nil && backData != nil
            let previews = (both && generationScope == .back ? [] : frontStyles)
                + (both && generationScope == .front ? [] : backStyles)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(previews.indices, id: \.self) { index in
                        ListingPhotoThumbnail(image: previews[index], number: index + (frontData == nil || (both && generationScope == .back) ? 6 : 1))
                            .frame(width: 56, height: 56)
                    }
                }
                .padding(.vertical, 8)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(expectedPhotoCount) photos: full view, top left, top right, bottom right and bottom left for each included side")
        }
    }

    private var singleActionBar: some View {
        VStack(spacing: 10) {
            if isReviewingOutput, let output = singleOutput {
                Button {
                    output.urls.forEach(EbayListingPhotoExport.retainForShare)
                    filesExport = ListingFilesExport(urls: output.urls)
                } label: {
                    HStack(spacing: 8) {
                        if !dynamicTypeSize.isAccessibilitySize { Image(systemName: "folder") }
                        Text("Save to Files").multilineTextAlignment(.center)
                    }
                        .padding(.horizontal, 20).padding(.vertical, 8)
                        .frame(maxWidth: .infinity, minHeight: 54)
                        .foregroundStyle(.white).background(listingButtonAccent, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Keeps the numbered filenames in upload order")
                .disabled(isUpdatingOrder)
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: 10)) : AnyLayout(HStackLayout(spacing: 10))
                layout {
                    Button(action: saveSingleOutputToPhotos) {
                        Label(isSavingToPhotos ? "Saving…" : "Photos", systemImage: "photo")
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .foregroundStyle(listingAccent)
                    }
                    .disabled(isSavingToPhotos || isUpdatingOrder)
                    ShareLink(items: output.urls.map { ListingPhotoShareFile(url: $0) },
                              preview: { _ in SharePreview("Listing photo", icon: Image(systemName: "photo")) }) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity, minHeight: 38)
                            .foregroundStyle(listingAccent)
                    }
                    .disabled(isUpdatingOrder)
                }
                .buttonStyle(.bordered).buttonBorderShape(.capsule)
                if isUpdatingOrder { ProgressView("Updating upload order…") }
                if let saveConfirmation { Text(saveConfirmation).font(.caption).foregroundStyle(.secondary) }
                if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            } else {
                if frontData == nil && backData == nil {
                    Text("Add at least one side to continue.").font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    if singleOutput != nil { isReviewingOutput = true } else { beginPreparingSingle() }
                } label: {
                    HStack(spacing: 8) {
                        if isPreparingSingle { ProgressView().tint(.white) }
                        else if !dynamicTypeSize.isAccessibilitySize {
                            Image(systemName: singleOutput == nil ? "wand.and.stars" : "photo.on.rectangle")
                        }
                        Text(isPreparingSingle ? "Preparing Photos…" : singleOutput == nil ? generationTitle : "Review \(singleOutput?.urls.count ?? 0) Photos")
                            .multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 20).padding(.vertical, 8)
                    .frame(maxWidth: .infinity, minHeight: 54)
                    .foregroundStyle(.white)
                    .background(listingButtonAccent, in: Capsule())
                    .opacity((frontData == nil && backData == nil) || frontIsLoading || backIsLoading ? 0.35 : 1)
                }
                .buttonStyle(.plain)
                .disabled((frontData == nil && backData == nil) || frontIsLoading || backIsLoading || isPreparingSingle)
                .accessibilityIdentifier("listingPhotos.generate")
            }
        }
        .font(.body.weight(.semibold))
        .padding(.horizontal, 16).padding(.vertical, 12)
        .contentWidthLimit(.standard)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    @ViewBuilder
    private var batchContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !collectorTools.isOwned {
                Button("View Collector Tools and price") { isShowingOffer = true }
                Text("One card is free here too. Review the one-time price before preparing multiple cards.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            PhotosPicker(
                selection: Binding(
                    get: { batchPickerItems },
                    set: { items in
                        batchPickerItems = items
                        updateBatchPairs(sources: items.map(PhotoSource.photo))
                    }
                ),
                maxSelectionCount: nil,
                selectionBehavior: .ordered,
                matching: .images
            ) {
                Label("Choose an even number of photos", systemImage: "photo.on.rectangle.angled")
            }
            .buttonStyle(.borderedProminent)
            // Re-picking mid-run cancels the batch and deletes every card
            // already written. Cancel is the deliberate way out.
            .disabled(isPreparingBatch)

            Button("Choose Files", systemImage: "folder") {
                fileImportSide = nil
                isShowingFileImporter = true
            }
            .buttonStyle(.bordered)
            .disabled(isPreparingBatch)

            Text("Images are paired in picker order, front then back. Review each pair and swap sides if needed before processing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if batchSourceCount % 2 == 1 {
                Text("Choose one more photo: a batch needs an even number of images.")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            if !batchPairs.isEmpty {
                Text("Review pairs")
                    .font(.headline)

                ForEach($batchPairs) { $pair in
                    BatchPairRow(
                        pair: $pair,
                        isEditable: !isPreparingBatch,
                        onSwap: invalidateBatchImages,
                        onNameChange: invalidateBatchResults
                    )
                }

                if isPreparingBatch, let batchProgress {
                    ProgressView("Card \(batchProgress.current) of \(batchProgress.total)")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Cancel", action: cancelBatch)
                        .buttonStyle(.bordered)
                } else if batchArchiveURL == nil {
                    Button(
                        "Prepare \(batchPairs.count) card\(batchPairs.count == 1 ? "" : "s")",
                        systemImage: "wand.and.stars",
                        action: startBatch
                    )
                    .buttonStyle(.borderedProminent)
                }

                if !batchFailures.isEmpty {
                    Text("Skipped pairs:\n\(batchFailures.joined(separator: "\n"))")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
                if batchArchiveURL != nil {
                    Text("The batch archive contains one numbered ten-photo folder per completed card.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Button("Start Over", systemImage: "arrow.counterclockwise", action: startOverBatch)
                        .buttonStyle(.bordered)
                }
            }

            if let batchErrorMessage {
                Text(batchErrorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private func singleSlot(side: Side, isReady: Bool) -> some View {
        let isLoading = side == .front ? frontIsLoading : backIsLoading
        let preview = (side == .front ? frontStyles : backStyles).first
        return VStack(spacing: 8) {
            Menu {
                sourceButtons(side: side)
                if isReady || isLoading {
                    Button("Remove Photo", systemImage: "trash", role: .destructive) { clearSinglePhoto(side: side) }
                        .accessibilityIdentifier("listingPhotos.\(side.rawValue).remove")
                }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(uiColor: .tertiarySystemBackground))
                    if let preview {
                        Image(uiImage: preview).resizable().scaledToFit().padding(4)
                        VStack {
                            HStack {
                                Spacer()
                                Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white)
                                    .frame(width: 26, height: 26).background(listingButtonAccent, in: Circle())
                            }
                            Spacer()
                        }.padding(8)
                    } else if isReady, !isLoading, errorMessage != nil {
                        Label("Preview unavailable", systemImage: "exclamationmark.triangle")
                            .font(.caption).padding()
                    } else if isLoading || isReady {
                        ProgressView("Loading…").font(.caption)
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "plus").font(.system(size: 24))
                                .foregroundStyle(.white).frame(width: 48, height: 48)
                                .background(listingButtonAccent, in: Circle())
                            Text("Add \(side.title)").font(.subheadline.weight(.semibold))
                            Text("Camera or Photos").font(.caption).foregroundStyle(.secondary)
                        }.padding(8)
                    }
                }
                .aspectRatio(5.0 / 7.0, contentMode: .fit)
                .overlay {
                    if !isReady {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(.secondary.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .buttonStyle(.plain)
            .disabled(isPreparingSingle)
            .accessibilityLabel("\(isReady ? "Replace" : "Add") \(side.title.lowercased()) photo")
            .accessibilityIdentifier("listingPhotos.\(side.rawValue).add")
            .contextMenu {
                sourceButtons(side: side)
                if isReady || isLoading {
                    Button("Remove Photo", systemImage: "trash", role: .destructive) { clearSinglePhoto(side: side) }
                }
            }
            Text(side.title).font(.subheadline.weight(.semibold))
                .foregroundStyle(isReady ? .primary : .secondary)
        }
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? 280 : .infinity)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private func sourceButtons(side: Side) -> some View {
        Button("Take Photo", systemImage: "camera") {
            cameraSide = side
        }
        Button("Choose Photo", systemImage: "photo.on.rectangle") {
            photoPickerSide = side
            isShowingPhotoPicker = true
        }
        Button("Choose File", systemImage: "folder") {
            fileImportSide = side
            isShowingFileImporter = true
        }
        .accessibilityHint("Selects an image file for the \(side.title.lowercased()) of the card")
    }

    private func outputGrid(_ output: EbayListingPhotoExport.Output) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if output.urls.indices.contains(selectedOutputIndex) {
                Button {
                    inspectedPhoto = InspectedPhoto(id: selectedOutputIndex, url: output.urls[selectedOutputIndex],
                                                    dimensions: output.pixelDimensions[selectedOutputIndex])
                } label: {
                    ListingPhotoReviewImage(image: output.previews[selectedOutputIndex], identity: output.urls[selectedOutputIndex])
                        .padding(8)
                        .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 16))
                        .overlay(alignment: .bottomLeading) {
                            Text("\(selectedOutputIndex + 1) of \(output.urls.count)\(selectedOutputIndex == 0 ? " · Cover photo" : "")")
                                .font(.caption.weight(.semibold)).foregroundStyle(.white)
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(.black.opacity(0.7), in: Capsule()).padding(12)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Photo \(selectedOutputIndex + 1), \(photoDescription(output.urls[selectedOutputIndex]))")
                .accessibilityHint("Opens full-size review with zoom")
                .accessibilityIdentifier("listingPhotos.selectedPhoto")
            }
            ForEach(Side.allCases) { side in
                let indices = output.urls.indices.filter { output.urls[$0].lastPathComponent.contains(side.title) }
                if !indices.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(side.title).font(.subheadline.weight(.semibold))
                            Spacer()
                            Text(uploadPositions(indices))
                                .font(.caption).foregroundStyle(.secondary)
                                .accessibilityLabel("Upload positions \(indices.map { String($0 + 1) }.joined(separator: ", "))")
                        }
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8),
                                                 count: dynamicTypeSize.isAccessibilitySize ? 3 : 5), spacing: 8) {
                            ForEach(indices, id: \.self) { index in
                                Button { selectedOutputIndex = index } label: {
                                    ListingPhotoThumbnail(image: output.previews[index], number: index + 1)
                                        .aspectRatio(1, contentMode: .fit)
                                        .overlay {
                                            RoundedRectangle(cornerRadius: 10)
                                                .strokeBorder(selectedOutputIndex == index ? listingAccent : .clear, lineWidth: 3)
                                        }
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Photo \(index + 1), \(photoDescription(output.urls[index]))")
                                .accessibilityAddTraits(selectedOutputIndex == index ? .isSelected : [])
                                .accessibilityIdentifier("listingPhotos.output.\(index)")
                                .draggable(String(index))
                                .dropDestination(for: String.self) { items, _ in
                                    guard let value = items.first, let source = Int(value) else { return false }
                                    moveOutput(from: source, to: index)
                                    return true
                                }
                                .contextMenu {
                                    if index > 0 {
                                        Button("Make Cover Photo", systemImage: "star") { moveOutput(from: index, to: 0) }
                                        Button("Move Earlier", systemImage: "arrow.left") { moveOutput(from: index, to: index - 1) }
                                    }
                                    if index + 1 < output.urls.count {
                                        Button("Move Later", systemImage: "arrow.right") { moveOutput(from: index, to: index + 1) }
                                    }
                                }
                                .accessibilityAction(named: "Move earlier") { moveOutput(from: index, to: max(0, index - 1)) }
                                .accessibilityAction(named: "Move later") { moveOutput(from: index, to: min(output.urls.count - 1, index + 1)) }
                                .disabled(isUpdatingOrder || isSavingToPhotos)
                            }
                        }
                    }
                }
            }
            Text("Numbered in eBay upload order. Drag to reorder.")
                .font(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity)
            if !output.reducedQualityNames.isEmpty {
                Text("JPEG quality was reduced to fit the image size limit: \(output.reducedQualityNames.joined(separator: ", ")).")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func photoDescription(_ url: URL) -> String {
        url.deletingPathExtension().lastPathComponent.dropFirst(3)
            .replacingOccurrences(of: "-TL", with: " top left corner")
            .replacingOccurrences(of: "-TR", with: " top right corner")
            .replacingOccurrences(of: "-BR", with: " bottom right corner")
            .replacingOccurrences(of: "-BL", with: " bottom left corner")
    }

    private func uploadPositions(_ indices: [Int]) -> String {
        guard let first = indices.first, let last = indices.last else { return "" }
        if last - first + 1 == indices.count { return "Photos \(first + 1)–\(last + 1)" }
        return "Photos " + indices.map { String($0 + 1) }.joined(separator: ", ")
    }

    private func moveOutput(from source: Int, to destination: Int) {
        guard let output = singleOutput, output.urls.indices.contains(source),
              output.urls.indices.contains(destination), source != destination,
              !isUpdatingOrder, !isSavingToPhotos else { return }
        var order = Array(output.urls.indices)
        order.insert(order.remove(at: source), at: destination)
        let generation = singleGeneration
        isUpdatingOrder = true
        let previousTask = singleProcessingTask
        singleProcessingTask = Task {
            // The archive still reads the old run. Let it finish before copying
            // and retiring that run; cancelling it would delete the source files.
            await previousTask?.value
            guard !Task.isCancelled, generation == singleGeneration else { return }
            do {
                let reordered = try await EbayListingPhotoExport.reorderedCopy(of: output, order: order)
                guard !Task.isCancelled, generation == singleGeneration else {
                    EbayListingPhotoExport.discardRunContainerInBackground(forContentDirectory: reordered.contentDirectory)
                    return
                }
                singleOutput = reordered
                singleOutputDirectory = reordered.contentDirectory
                selectedOutputIndex = destination
                singleArchiveURL = nil
                isUpdatingOrder = false
                saveConfirmation = nil
                EbayListingPhotoExport.discardRunContainerInBackground(forContentDirectory: output.contentDirectory)
                await buildSingleArchive(generation: generation, directory: reordered.contentDirectory)
            } catch {
                guard generation == singleGeneration else { return }
                isUpdatingOrder = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func beginLoading(side: Side) {
        invalidateSingleOutput()
        switch side {
        case .front: frontLoadGeneration &+= 1; frontData = nil; frontIsLoading = true
        case .back: backLoadGeneration &+= 1; backData = nil; backIsLoading = true
        }
    }

    private func invalidateSingleOutput() {
        singleGeneration &+= 1
        singleProcessingTask?.cancel()
        singleProcessingTask = nil
        removeSingleArtifacts()
        isPreparingSingle = false
        errorMessage = nil
        saveConfirmation = nil
    }

    private func clearSinglePhoto(side: Side) {
        invalidateSingleOutput()
        switch side {
        case .front:
            frontLoadGeneration &+= 1
            frontPickerItem = nil
            frontData = nil
            frontIsLoading = false
        case .back:
            backLoadGeneration &+= 1
            backPickerItem = nil
            backData = nil
            backIsLoading = false
        }
    }

    private func loadGeneration(for side: Side) -> Int {
        side == .front ? frontLoadGeneration : backLoadGeneration
    }

    private func loadSinglePhoto(
        _ source: PhotoSource,
        side: Side,
        requestID: Int
    ) async {
        defer {
            if requestID == loadGeneration(for: side) {
                switch side {
                case .front: frontIsLoading = false
                case .back: backIsLoading = false
                }
            }
        }
        do {
            let data = try await data(from: source, side: side.title.lowercased())
            guard !Task.isCancelled, requestID == loadGeneration(for: side) else { return }
            switch side {
            case .front: frontData = data; frontPickerItem = nil
            case .back: backData = data; backPickerItem = nil
            }
            singleGeneration &+= 1
        } catch is CancellationError {
            guard requestID == loadGeneration(for: side) else { return }
            switch side {
            case .front: frontPickerItem = nil
            case .back: backPickerItem = nil
            }
            return
        } catch {
            guard !Task.isCancelled, requestID == loadGeneration(for: side) else { return }
            // Release the failed selection so choosing this same asset again
            // produces a change and starts a fresh load.
            switch side {
            case .front: frontPickerItem = nil
            case .back: backPickerItem = nil
            }
            errorMessage = error.localizedDescription
        }
    }

    private func receiveCameraCapture(_ data: Data, for side: Side) {
        invalidateSingleOutput()
        switch side {
        case .front: frontLoadGeneration &+= 1; frontData = data; frontIsLoading = false
        case .back: backLoadGeneration &+= 1; backData = data; backIsLoading = false
        }
        singleGeneration &+= 1
    }

    private func beginPreparingSingle() {
        guard !frontIsLoading, !backIsLoading, frontData != nil || backData != nil else { return }
        invalidateSingleOutput()
        let generation = singleGeneration
        let hasBoth = frontData != nil && backData != nil
        let front = hasBoth && generationScope == .back ? nil : frontData
        let back = hasBoth && generationScope == .front ? nil : backData
        isPreparingSingle = true
        singleProcessingTask = Task {
            await prepareSingle(generation: generation, frontData: front, backData: back)
        }
    }

    private var generationTitle: String {
        let hasBoth = frontData != nil && backData != nil
        if hasBoth && generationScope == .both { return "Generate 10 photos" }
        if (hasBoth && generationScope == .back) || frontData == nil && backData != nil {
            return "Generate 5 back photos"
        }
        if frontData != nil { return "Generate 5 front photos" }
        return "Generate photos"
    }

    private func prepareSingle(
        generation: Int,
        frontData: Data?,
        backData: Data?
    ) async {
        guard !Task.isCancelled, generation == singleGeneration,
              singleOutput == nil, frontData != nil || backData != nil else { return }
        isPreparingSingle = true
        do {
            let output = try await EbayListingPhotoExport.makeListingPhotos(
                frontData: frontData,
                backData: backData
            )
            guard !Task.isCancelled, generation == singleGeneration else {
                EbayListingPhotoExport.discardRunContainerInBackground(forContentDirectory: output.contentDirectory)
                return
            }
            singleOutput = output
            singleOutputDirectory = output.contentDirectory
            selectedOutputIndex = 0
            isReviewingOutput = true
            isPreparingSingle = false
            await buildSingleArchive(generation: generation, directory: output.contentDirectory)
        } catch is CancellationError {
            guard generation == singleGeneration else { return }
            isPreparingSingle = false
        } catch {
            guard generation == singleGeneration else { return }
            isPreparingSingle = false
            errorMessage = error.localizedDescription
        }
    }

    /// Builds the shareable ZIP for a finished single-card export. The
    /// loose files stay shareable even if this fails, so a zip failure is
    /// reported without discarding the export.
    private func buildSingleArchive(generation: Int, directory: URL?) async {
        guard let directory else { return }
        do {
            let archive = try await EbayListingPhotoExport.makeArchive(at: directory)
            // The archive worker is not cancellation-aware and finishes even
            // when this run was superseded, so re-check before publishing it.
            guard !Task.isCancelled, generation == singleGeneration else {
                EbayListingPhotoExport.discardRunInBackground(at: archive)
                return
            }
            singleArchiveURL = archive
        } catch {
            guard generation == singleGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func saveSingleOutputToPhotos() {
        guard let singleOutput, !isSavingToPhotos else { return }
        isSavingToPhotos = true
        saveConfirmation = nil
        errorMessage = nil
        let urls = singleOutput.urls
        let directory = singleOutput.contentDirectory
        savingPhotoDirectory = directory
        let generation = singleGeneration
        Task {
            defer {
                isSavingToPhotos = false
                savingPhotoDirectory = nil
                if singleOutputDirectory != directory {
                    EbayListingPhotoExport.discardRunContainerInBackground(forContentDirectory: directory)
                }
            }
            do {
                try await ListingPhotoLibrarySaver.save(urls)
                guard generation == singleGeneration else { return }
                saveConfirmation = "Saved \(urls.count) photos to Photos in listing order."
            } catch {
                guard generation == singleGeneration else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func startOverSingle() {
        collectionTitle = nil
        collectionSubtitle = nil
        singleProcessingTask?.cancel()
        frontLoadGeneration &+= 1
        backLoadGeneration &+= 1
        singleGeneration &+= 1
        frontPickerItem = nil
        backPickerItem = nil
        frontData = nil
        backData = nil
        frontIsLoading = false
        backIsLoading = false
        generationScope = .both
        errorMessage = nil
        saveConfirmation = nil
        isPreparingSingle = false
        removeSingleArtifacts()
    }

    private func removeSingleArtifacts() {
        isReviewingOutput = false
        isUpdatingOrder = false
        // The inspector reads a file inside the container about to be deleted.
        inspectedPhoto = nil
        if singleOutputDirectory != savingPhotoDirectory {
            EbayListingPhotoExport.discardRunContainerInBackground(forContentDirectory: singleOutputDirectory)
        }
        singleOutputDirectory = nil
        singleOutput = nil
        // The archive lives inside the container that was just removed.
        singleArchiveURL = nil
    }

    private func updateBatchPairs(sources: [PhotoSource]) {
        batchSelectionGeneration &+= 1
        batchPreviewGeneration &+= 1
        batchProcessingTask?.cancel()
        batchProcessingTask = nil
        isPreparingBatch = false
        batchProgress = nil
        batchFailures = []
        batchErrorMessage = nil
        removeBatchArtifacts()
        batchPairs = []
        batchSourceCount = sources.count

        guard !sources.isEmpty else { return }
        guard sources.count.isMultiple(of: 2) else {
            batchErrorMessage = "Choose an even number of photos so every front has a back."
            return
        }

        for index in stride(from: 0, to: sources.count, by: 2) {
            batchPairs.append(
                BatchPair(
                    front: sources[index],
                    back: sources[index + 1],
                    folderName: String(format: "Card-%02d", index / 2 + 1)
                )
            )
        }
    }

    private func loadBatchPreviews(generation: Int) async {
        guard !batchPairs.isEmpty else { return }
        for index in batchPairs.indices {
            guard !Task.isCancelled, generation == batchPreviewGeneration else { return }
            let pair = batchPairs[index]
            do {
                let frontData = try await data(from: pair.front, side: "front")
                let frontPreview = try await EbayListingPhotoExport.makeInputPreview(data: frontData)
                guard !Task.isCancelled, generation == batchPreviewGeneration else { return }
                batchPairs[index].frontPreview = frontPreview

                let backData = try await data(from: pair.back, side: "back")
                let backPreview = try await EbayListingPhotoExport.makeInputPreview(data: backData)
                guard !Task.isCancelled, generation == batchPreviewGeneration else { return }
                batchPairs[index].backPreview = backPreview
            } catch is CancellationError {
                return
            } catch {
                guard generation == batchPreviewGeneration else { return }
                batchErrorMessage = "Card \(index + 1) could not be previewed: \(error.localizedDescription)"
                return
            }
        }
    }

    private func data(from source: PhotoSource, side: String) async throws -> Data {
        switch source {
        case let .photo(item):
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw EbayListingPhotoExport.Error.decodeFailed(side: side)
            }
            return data
        case let .file(url):
            return try await Task.detached(priority: .userInitiated) {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess { url.stopAccessingSecurityScopedResource() }
                }
                return try Data(contentsOf: url, options: .mappedIfSafe)
            }.value
        }
    }

    private func startBatch() {
        guard !isPreparingBatch, !batchPairs.isEmpty else { return }
        guard collectorTools.canPreparePhotos(cardCount: batchPairs.count) else {
            isShowingOffer = true
            return
        }
        // The flag must be raised here, not inside the task body: `Task` does
        // not run synchronously, so two taps landing before the first hop
        // would otherwise start two pipelines and leak the first directory.
        isPreparingBatch = true
        let generation = batchSelectionGeneration
        batchProcessingTask = Task {
            await processBatch(generation: generation)
        }
    }

    private func processBatch(generation: Int) async {
        guard collectorTools.canPreparePhotos(cardCount: batchPairs.count) else {
            isPreparingBatch = false
            return
        }
        guard generation == batchSelectionGeneration, !Task.isCancelled else { return }
        guard !batchPairs.isEmpty else {
            // startBatch raised this flag; it must not survive an early return.
            isPreparingBatch = false
            return
        }
        isPreparingBatch = true
        batchProgress = nil
        batchFailures = []
        batchErrorMessage = nil

        let directory: URL
        do {
            directory = try await Task.detached(priority: .userInitiated) {
                try EbayListingPhotoExport.makeBatchDirectory()
            }.value
            guard !Task.isCancelled, generation == batchSelectionGeneration else {
                EbayListingPhotoExport.discardRunContainerInBackground(forContentDirectory: directory)
                return
            }
            batchDirectory = directory
        } catch {
            isPreparingBatch = false
            batchErrorMessage = error.localizedDescription
            return
        }

        var failures: [String] = []
        var successfulCount = 0
        var usedFolderNames = Set<String>()

        for index in batchPairs.indices {
            guard !Task.isCancelled, generation == batchSelectionGeneration else {
                EbayListingPhotoExport.discardRunContainerInBackground(forContentDirectory: directory)
                if generation == batchSelectionGeneration {
                    isPreparingBatch = false
                    batchProgress = nil
                    if batchDirectory == directory { batchDirectory = nil }
                }
                return
            }
            batchProgress = BatchProgress(current: index + 1, total: batchPairs.count)
            let pair = batchPairs[index]
            var completedOutput: EbayListingPhotoExport.Output?
            do {
                let frontData = try await data(from: pair.front, side: "front")
                let backData = try await data(from: pair.back, side: "back")
                let output = try await EbayListingPhotoExport.makeListingPhotos(
                    frontData: frontData,
                    backData: backData,
                    includePreviews: false
                )
                completedOutput = output
                let folderName = uniqueFolderName(
                    requested: pair.folderName,
                    fallback: String(format: "Card-%02d", index + 1),
                    used: &usedFolderNames
                )
                let cardDirectory = directory.appendingPathComponent(folderName, isDirectory: true)
                try await EbayListingPhotoExport.moveOutput(output, to: cardDirectory)
                completedOutput = nil
                successfulCount += 1
            } catch is CancellationError {
                if let completedOutput {
                    EbayListingPhotoExport.discardRunContainerInBackground(forContentDirectory: completedOutput.contentDirectory)
                }
                EbayListingPhotoExport.discardRunContainerInBackground(forContentDirectory: directory)
                return
            } catch {
                if let completedOutput {
                    EbayListingPhotoExport.discardRunContainerInBackground(forContentDirectory: completedOutput.contentDirectory)
                }
                failures.append("Card \(index + 1): \(error.localizedDescription)")
            }
        }

        guard generation == batchSelectionGeneration, !Task.isCancelled else {
            EbayListingPhotoExport.discardRunContainerInBackground(forContentDirectory: directory)
            return
        }
        batchFailures = failures
        if successfulCount == 0 {
            isPreparingBatch = false
            batchProgress = nil
            batchErrorMessage = EbayListingPhotoExport.Error.emptyBatch.localizedDescription
            EbayListingPhotoExport.discardRunContainerInBackground(forContentDirectory: directory)
            batchDirectory = nil
            return
        }

        await EbayListingPhotoExport.finishBatchArchive(
            at: directory,
            isCurrent: { generation == batchSelectionGeneration }
        ) { result in
            isPreparingBatch = false
            batchProgress = nil
            switch result {
            case let .success(archive):
                batchArchiveURL = archive
            case let .failure(error):
                batchErrorMessage = error.localizedDescription
                if batchDirectory == directory { batchDirectory = nil }
            }
        }
    }

    private func invalidateBatchImages() {
        // Pair edits must also invalidate previews still loading before the
        // first export. Otherwise an old front/back request can overwrite a swap.
        batchPreviewGeneration &+= 1
        invalidateBatchResults()
    }

    private func invalidateBatchResults() {
        batchSelectionGeneration &+= 1
        batchProcessingTask?.cancel()
        batchProcessingTask = nil
        isPreparingBatch = false
        batchProgress = nil
        batchFailures = []
        batchErrorMessage = nil
        removeBatchArtifacts()
    }

    private func cancelBatch() {
        batchSelectionGeneration &+= 1
        batchProcessingTask?.cancel()
        batchProcessingTask = nil
        isPreparingBatch = false
        batchProgress = nil
    }

    private func startOverBatch() {
        batchSelectionGeneration &+= 1
        batchPreviewGeneration &+= 1
        batchPickerItems = []
        batchSourceCount = 0
        batchPairs = []
        batchFailures = []
        batchErrorMessage = nil
        isPreparingBatch = false
        batchProgress = nil
        batchProcessingTask?.cancel()
        batchProcessingTask = nil
        removeBatchArtifacts()
    }

    private func removeBatchArtifacts() {
        EbayListingPhotoExport.discardRunContainerInBackground(forContentDirectory: batchDirectory)
        batchDirectory = nil
        batchArchiveURL = nil
    }

    private func uniqueFolderName(
        requested: String,
        fallback: String,
        used: inout Set<String>
    ) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/\\:")
        let cleaned = requested
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let base = cleaned.isEmpty || cleaned == "." || cleaned == ".." ? fallback : cleaned
        var candidate = base
        var suffix = 2
        while used.contains(candidate) {
            candidate = "\(base)-\(suffix)"
            suffix += 1
        }
        used.insert(candidate)
        return candidate
    }
}

private struct ListingPhotoReviewImage: View {
    let image: UIImage
    let identity: URL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Image(uiImage: image).resizable().scaledToFit()
                .id(identity).transition(.opacity)
        }
        .frame(maxWidth: .infinity).frame(height: 250)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: identity)
    }
}

/// Selection and its short animations stay local to the sheet. The parent only
/// receives the final choice when the sheet disappears.
private struct ListingPhotoStylesSheet: View {
    typealias Scope = EbayListingPhotosView.GenerationScope

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selection: Scope
    let hasFront: Bool
    let hasBack: Bool
    let frontPreviews: [UIImage]
    let backPreviews: [UIImage]
    let accent: Color
    let onApply: (Scope) -> Void

    private static let styles: [(title: String, symbol: String)] = [
        ("Full view", "rectangle.portrait"),
        ("Top left corner", "arrow.up.left"),
        ("Top right corner", "arrow.up.right"),
        ("Bottom right corner", "arrow.down.right"),
        ("Bottom left corner", "arrow.down.left")
    ]

    init(scope: Scope, hasFront: Bool, hasBack: Bool, frontPreviews: [UIImage],
         backPreviews: [UIImage], accent: Color, onApply: @escaping (Scope) -> Void) {
        _selection = State(initialValue: scope)
        self.hasFront = hasFront
        self.hasBack = hasBack
        self.frontPreviews = frontPreviews
        self.backPreviews = backPreviews
        self.accent = accent
        self.onApply = onApply
    }

    private var photoCount: Int { hasFront && hasBack ? (selection == .both ? 10 : 5) : (hasFront || hasBack ? 5 : 0) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if hasFront && hasBack {
                        ForEach(Scope.allCases) { scope in
                            scopeRow(scope)
                        }
                    } else {
                        Label(hasFront ? "Front only" : hasBack ? "Back only" : "Add a source photo first",
                              systemImage: hasFront || hasBack ? "checkmark.circle.fill" : "photo.badge.plus")
                            .frame(minHeight: 44)
                    }
                } header: {
                    Text("Include")
                } footer: {
                    Text(photoCount == 0 ? "Add a front or back photo to generate listing photos."
                         : "\(photoCount) photos in upload order.")
                        .contentTransition(.opacity)
                }

                Section {
                    ForEach(Self.styles.indices, id: \.self) { index in
                        HStack(spacing: 12) {
                            if dynamicTypeSize.isAccessibilitySize || (frontPreviews.isEmpty && backPreviews.isEmpty) {
                                Image(systemName: Self.styles[index].symbol)
                                    .font(.system(size: 20)).foregroundStyle(accent)
                                    .frame(width: 28).accessibilityHidden(true)
                            } else {
                                HStack(spacing: 4) {
                                    if frontPreviews.indices.contains(index) {
                                        preview(frontPreviews[index], included: !hasBack || selection != .back)
                                    }
                                    if backPreviews.indices.contains(index) {
                                        preview(backPreviews[index], included: !hasFront || selection != .front)
                                    }
                                }
                                .frame(width: hasFront && hasBack ? 76 : 36)
                                .accessibilityHidden(true)
                            }
                            Text(Self.styles[index].title).frame(maxWidth: .infinity, alignment: .leading)
                            Text("\(index + 1)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 48)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(index + 1). \(Self.styles[index].title)")
                    }
                } header: {
                    Text("Five photos per side")
                } footer: {
                    Text("One full view and four corner close-ups for each included side.")
                }
            }
            .navigationTitle("Photo Styles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
        .tint(accent)
        .presentationDetents([.large])
        .onDisappear {
            if hasFront && hasBack { onApply(selection) }
        }
    }

    private func scopeRow(_ scope: Scope) -> some View {
        Button { selection = scope } label: {
            HStack(spacing: 12) {
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout())
                layout {
                    Text(scope.rawValue).foregroundStyle(.primary)
                    if !dynamicTypeSize.isAccessibilitySize { Spacer() }
                    Text(scope == .both ? "10 photos" : "5 photos").font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 22)).foregroundStyle(accent)
                    .opacity(selection == scope ? 1 : 0)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: selection == scope)
                    .accessibilityHidden(true)
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(scope.rawValue), \(scope == .both ? 10 : 5) photos")
        .accessibilityAddTraits(selection == scope ? .isSelected : [])
        .accessibilityIdentifier("listingPhotos.styles.\(scope.id)")
    }

    private func preview(_ image: UIImage, included: Bool) -> some View {
        Image(uiImage: image).resizable().scaledToFit().frame(width: 36, height: 48)
            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 5))
            .opacity(included ? 1 : 0.15)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: included)
    }
}

private struct ListingPhotoThumbnail: View {
    let image: UIImage
    let number: Int

    var body: some View {
        Image(uiImage: image).resizable().scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(uiColor: .tertiarySystemBackground))
            .overlay(alignment: .bottomLeading) {
                Text("\(number)").font(.caption2.bold()).foregroundStyle(.white)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.black.opacity(0.75), in: Capsule()).padding(4)
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

private struct ListingFilesExport: Identifiable {
    let id = UUID()
    let urls: [URL]
}

/// Native Files export copies the JPEGs with their numbered names intact.
private struct ListingFilesExporter: UIViewControllerRepresentable {
    let urls: [URL]
    let onCompletion: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onCompletion: onCompletion) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: urls, asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onCompletion: (Bool) -> Void
        init(onCompletion: @escaping (Bool) -> Void) { self.onCompletion = onCompletion }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onCompletion(true) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onCompletion(false) }
    }
}

private struct ListingCollectionPicker: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \CollectedCard.dateAdded, order: .reverse) private var cards: [CollectedCard]
    @Query(sort: \LocalArtworkOverride.updatedAt, order: .reverse) private var artwork: [LocalArtworkOverride]
    @State private var search = ""
    @State private var loadingKey: String?
    @State private var selectionTask: Task<Void, Never>?
    @State private var errorMessage: String?
    let onSelect: (String, String, Data) -> Void

    private var filenames: [String: String] {
        Dictionary(artwork.map { ($0.collectionKey, $0.filename) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Choose a card with a photo saved on this device. This adds its saved photo as the front; you can replace it or add a back.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                let localFiles = filenames
                let eligible = cards.filter {
                    !(localFiles[$0.collectionKey] ?? $0.userArtworkFilename ?? "").isEmpty
                        && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search)
                            || $0.setName.localizedCaseInsensitiveContains(search))
                }
                if eligible.isEmpty {
                    ContentUnavailableView("No Saved Card Photos", systemImage: "rectangle.stack",
                        description: Text("Add a photo to a card in Collection, or use Camera, Photos or Files in Listing Photos."))
                }
                ForEach(eligible) { card in
                    Button {
                        select(card, filename: localFiles[card.collectionKey] ?? card.userArtworkFilename)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(card.name).foregroundStyle(.primary)
                                Text([card.setName, card.cardNumber, card.variantLabel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if loadingKey == card.collectionKey { ProgressView() }
                            else { Image(systemName: "plus.circle").accessibilityHidden(true) }
                        }.frame(minHeight: 44)
                    }
                    .disabled(loadingKey != nil)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .searchable(text: $search, prompt: "Find a saved card photo")
            .navigationTitle("Use from Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .onDisappear { selectionTask?.cancel() }
    }

    private func select(_ card: CollectedCard, filename: String?) {
        loadingKey = card.collectionKey
        errorMessage = nil
        let title = card.name
        let subtitle = [card.setName, card.cardNumber, card.variantLabel].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
        selectionTask = Task {
            let data = await Task.detached(priority: .userInitiated) {
                CollectionArtworkStore.image(filename: filename)?.jpegData(compressionQuality: 0.95)
            }.value
            guard !Task.isCancelled else { return }
            loadingKey = nil
            guard let data else {
                errorMessage = "This photo is unavailable on this device. Choose another card or add a photo."
                return
            }
            onSelect(title, subtitle, data)
            dismiss()
        }
    }
}

private struct BatchPairRow: View {
    @Binding var pair: EbayListingPhotosView.BatchPair
    let isEditable: Bool
    let onSwap: () -> Void
    let onNameChange: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                preview(pair.frontPreview, label: "Front")
                Image(systemName: "arrow.right")
                    .foregroundStyle(.secondary)
                preview(pair.backPreview, label: "Back")
                Spacer(minLength: 0)
                Button("Swap", systemImage: "arrow.left.arrow.right") {
                    let front = pair.front
                    pair.front = pair.back
                    pair.back = front
                    let frontPreview = pair.frontPreview
                    pair.frontPreview = pair.backPreview
                    pair.backPreview = frontPreview
                    onSwap()
                }
                .labelStyle(.iconOnly)
                .accessibilityLabel("Swap front and back for this pair")
                .disabled(!isEditable)
            }

            TextField("Folder name", text: $pair.folderName)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Folder name for this card")
                .disabled(!isEditable)
        }
        .padding(12)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
        .onChange(of: pair.folderName) { _, _ in
            onNameChange()
        }
    }

    private func preview(_ image: UIImage?, label: String) -> some View {
        VStack(spacing: 4) {
            Group {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: "photo")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 68, height: 88)
            .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}
