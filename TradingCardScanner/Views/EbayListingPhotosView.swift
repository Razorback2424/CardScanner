import PhotosUI
import SwiftUI
import UIKit

struct EbayListingPhotosView: View {
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

    fileprivate struct BatchPair: Identifiable {
        let id = UUID()
        var front: PhotosPickerItem
        var back: PhotosPickerItem
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

    @State private var mode: Mode = .single
    @State private var frontPickerItem: PhotosPickerItem?
    @State private var backPickerItem: PhotosPickerItem?
    @State private var frontData: Data?
    @State private var backData: Data?
    @State private var cameraSide: Side?
    @State private var singleGeneration = 0
    @State private var isPreparingSingle = false
    @State private var singleOutput: EbayListingPhotoExport.Output?
    @State private var singleOutputDirectory: URL?
    @State private var errorMessage: String?

    @State private var batchPickerItems: [PhotosPickerItem] = []
    @State private var batchPairs: [BatchPair] = []
    @State private var batchSelectionGeneration = 0
    @State private var batchProcessingTask: Task<Void, Never>?
    @State private var isPreparingBatch = false
    @State private var batchProgress: BatchProgress?
    @State private var batchDirectory: URL?
    @State private var batchArchiveURL: URL?
    @State private var batchFailures: [String] = []
    @State private var batchErrorMessage: String?
    @State private var hasSweptTemporaryDirectories = false
    @State private var singleArchiveURL: URL?
    @State private var isSavingToPhotos = false
    @State private var saveConfirmation: String?
    @State private var inspectedPhoto: InspectedPhoto?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Picker("Workflow", selection: $mode) {
                    ForEach(Mode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if mode == .single {
                    singleContent
                } else {
                    batchContent
                }
            }
            .padding(16)
            .contentWidthLimit(.standard)
        }
        .navigationTitle("eBay Listing Photos")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if mode == .single, let singleOutput, singleOutput.urls.count == 10 {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let singleArchiveURL {
                            ShareLink(item: singleArchiveURL) {
                                Label("Export ZIP", systemImage: "doc.zipper")
                            }
                        }
                        ShareLink(items: singleOutput.urls) {
                            Label("Export 10 Photos Individually", systemImage: "photo.on.rectangle")
                        }
                        Button("Export 10 Photos to Photos App", systemImage: "square.and.arrow.down") {
                            saveSingleOutputToPhotos()
                        }
                        .disabled(isSavingToPhotos)
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Export listing photos")
                }
            }
            if mode == .batch, let batchArchiveURL {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: batchArchiveURL) {
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
            let requestID = singleGeneration
            Task { await loadSinglePhoto(item, side: .front, requestID: requestID) }
        }
        .onChange(of: backPickerItem) { _, item in
            guard let item else { return }
            beginLoading(side: .back)
            let requestID = singleGeneration
            Task { await loadSinglePhoto(item, side: .back, requestID: requestID) }
        }
        .onChange(of: batchPickerItems) { _, _ in
            updateBatchPairs()
        }
        .task(id: singleGeneration) {
            await prepareSingle(
                generation: singleGeneration,
                frontData: frontData,
                backData: backData
            )
        }
        .task(id: batchSelectionGeneration) {
            await loadBatchPreviews(generation: batchSelectionGeneration)
        }
        .fullScreenCover(item: $cameraSide) { side in
            CenteringCameraView(configuration: .listingPhotos) { data in
                receiveCameraCapture(data, for: side)
            }
        }
        .fullScreenCover(item: $inspectedPhoto) { photo in
            ListingPhotoInspectorView(
                url: photo.url,
                nativeDimensions: photo.dimensions
            )
        }
        .onAppear {
            guard !hasSweptTemporaryDirectories else { return }
            hasSweptTemporaryDirectories = true
            // Safe here: nothing in this screen has produced output yet, and
            // both roots are owned exclusively by this feature.
            EbayListingPhotoExport.removeOrphanedTemporaryDirectories()
        }
        .onDisappear {
            singleGeneration &+= 1
            batchSelectionGeneration &+= 1
            batchProcessingTask?.cancel()
            batchProcessingTask = nil
            removeSingleArtifacts()
            removeBatchArtifacts()
        }
    }

    @ViewBuilder
    private var singleContent: some View {
        let isEmpty = frontData == nil && backData == nil && singleOutput == nil
        if isEmpty && !isPreparingSingle {
            ContentUnavailableView {
                Label("Prepare eBay Listing Photos", systemImage: "photo.stack")
            } description: {
                Text("Add a front and back photo to create the ten numbered upload images.")
            } actions: {
                VStack(spacing: 12) {
                    singleSlot(side: .front, isReady: false)
                    singleSlot(side: .back, isReady: false)
                }
            }
            .frame(minHeight: 430)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("Source photos")
                    .font(.headline)

                singleSlot(side: .front, isReady: frontData != nil)
                singleSlot(side: .back, isReady: backData != nil)

                if isPreparingSingle {
                    ProgressView("Preparing listing photos…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else if frontData != nil && backData != nil && singleOutput == nil {
                    Text("Both sides are ready. Preparing the export…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let singleOutput {
                    outputGrid(singleOutput)
                    Button("Start Over", systemImage: "arrow.counterclockwise", action: startOverSingle)
                        .buttonStyle(.bordered)
                }

                if isSavingToPhotos {
                    ProgressView("Saving to Photos…")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let saveConfirmation {
                    Text(saveConfirmation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
        }

        Text("Saving to Photos discards filenames. Files or AirDrop preserve the numbered upload order.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private var batchContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            PhotosPicker(
                selection: $batchPickerItems,
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

            Text("Photos are paired in selection order, front then back. Review each pair before processing.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if batchPickerItems.count % 2 == 1 {
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
                        onChange: invalidateBatchResults
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

                if let batchErrorMessage {
                    Text(batchErrorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
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
        }
    }

    private func singleSlot(side: Side, isReady: Bool) -> some View {
        let pickerBinding: Binding<PhotosPickerItem?> = side == .front
            ? $frontPickerItem
            : $backPickerItem

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(side.title, systemImage: side.systemImage)
                    .font(.headline)
                Spacer()
                Label(
                    isReady ? "Ready" : "Not added",
                    systemImage: isReady ? "checkmark.circle.fill" : "circle"
                )
                .font(.subheadline)
                .foregroundStyle(isReady ? .green : .secondary)
            }

            HStack(spacing: 10) {
                Button("Take Photo", systemImage: "camera") {
                    cameraSide = side
                }
                PhotosPicker(selection: pickerBinding, matching: .images) {
                    Label("Choose Photo", systemImage: "photo.on.rectangle")
                }
            }
            .buttonStyle(.bordered)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 14))
    }

    private func outputGrid(_ output: EbayListingPhotoExport.Output) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Listing order")
                .font(.headline)

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 140), spacing: 12)],
                spacing: 16
            ) {
                ForEach(output.urls.indices, id: \.self) { index in
                    Button {
                        inspectedPhoto = InspectedPhoto(
                            id: index,
                            url: output.urls[index],
                            dimensions: output.pixelDimensions[index]
                        )
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Image(uiImage: output.previews[index])
                                .resizable()
                                .scaledToFit()
                                .frame(maxWidth: .infinity)
                                .frame(height: 180)
                                .background(Color.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(alignment: .bottomTrailing) {
                                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.white)
                                        .padding(5)
                                        .background(.black.opacity(0.55), in: Circle())
                                        .padding(6)
                                }

                            Text(output.urls[index].deletingPathExtension().lastPathComponent)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                            let dimensions = output.pixelDimensions[index]
                            Text("\(dimensions.width) × \(dimensions.height)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens this photo for full-size review")
                }
            }

            if !output.reducedQualityNames.isEmpty {
                Text("JPEG quality was reduced to stay within eBay's 12 MB image limit for: \(output.reducedQualityNames.joined(separator: ", ")).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func beginLoading(side: Side) {
        singleGeneration &+= 1
        removeSingleArtifacts()
        isPreparingSingle = false
        errorMessage = nil
        saveConfirmation = nil
        switch side {
        case .front: frontData = nil
        case .back: backData = nil
        }
    }

    private func loadSinglePhoto(
        _ item: PhotosPickerItem,
        side: Side,
        requestID: Int
    ) async {
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw EbayListingPhotoExport.Error.decodeFailed(side: side.title.lowercased())
            }
            guard !Task.isCancelled, requestID == singleGeneration else { return }
            switch side {
            case .front: frontData = data; frontPickerItem = nil
            case .back: backData = data; backPickerItem = nil
            }
            singleGeneration &+= 1
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, requestID == singleGeneration else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func receiveCameraCapture(_ data: Data, for side: Side) {
        singleGeneration &+= 1
        removeSingleArtifacts()
        isPreparingSingle = false
        errorMessage = nil
        saveConfirmation = nil
        switch side {
        case .front: frontData = data
        case .back: backData = data
        }
        singleGeneration &+= 1
    }

    private func prepareSingle(
        generation: Int,
        frontData: Data?,
        backData: Data?
    ) async {
        guard let frontData, let backData else { return }
        isPreparingSingle = true
        do {
            let output = try await EbayListingPhotoExport.makeListingPhotos(
                frontData: frontData,
                backData: backData
            )
            guard !Task.isCancelled, generation == singleGeneration else {
                EbayListingPhotoExport.removeRunContainer(forContentDirectory: output.contentDirectory)
                return
            }
            singleOutput = output
            singleOutputDirectory = output.contentDirectory
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

    /// Builds the shareable ZIP for a finished single-card export. The ten
    /// loose files stay shareable even if this fails, so a zip failure is
    /// reported without discarding the export.
    private func buildSingleArchive(generation: Int, directory: URL?) async {
        guard let directory else { return }
        do {
            let archive = try await EbayListingPhotoExport.makeArchive(at: directory)
            // The archive worker is not cancellation-aware and finishes even
            // when this run was superseded, so re-check before publishing it.
            guard !Task.isCancelled, generation == singleGeneration else {
                EbayListingPhotoExport.removeRun(at: archive)
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
        let generation = singleGeneration
        Task {
            do {
                try await ListingPhotoLibrarySaver.save(urls)
                guard generation == singleGeneration else { return }
                isSavingToPhotos = false
                saveConfirmation = "Saved 10 photos to Photos in listing order."
            } catch {
                guard generation == singleGeneration else { return }
                isSavingToPhotos = false
                errorMessage = error.localizedDescription
            }
        }
    }

    private func startOverSingle() {
        singleGeneration &+= 1
        frontPickerItem = nil
        backPickerItem = nil
        frontData = nil
        backData = nil
        errorMessage = nil
        saveConfirmation = nil
        isPreparingSingle = false
        removeSingleArtifacts()
    }

    private func removeSingleArtifacts() {
        // The inspector reads a file inside the container about to be deleted.
        inspectedPhoto = nil
        EbayListingPhotoExport.removeRunContainer(forContentDirectory: singleOutputDirectory)
        singleOutputDirectory = nil
        singleOutput = nil
        // The archive lives inside the container that was just removed.
        singleArchiveURL = nil
    }

    private func updateBatchPairs() {
        batchSelectionGeneration &+= 1
        batchProcessingTask?.cancel()
        batchProcessingTask = nil
        isPreparingBatch = false
        batchProgress = nil
        batchFailures = []
        batchErrorMessage = nil
        removeBatchArtifacts()
        batchPairs = []

        guard !batchPickerItems.isEmpty else { return }
        guard batchPickerItems.count.isMultiple(of: 2) else {
            batchErrorMessage = "Choose an even number of photos so every front has a back."
            return
        }

        for index in stride(from: 0, to: batchPickerItems.count, by: 2) {
            batchPairs.append(
                BatchPair(
                    front: batchPickerItems[index],
                    back: batchPickerItems[index + 1],
                    folderName: String(format: "Card-%02d", index / 2 + 1)
                )
            )
        }
    }

    private func loadBatchPreviews(generation: Int) async {
        guard !batchPairs.isEmpty else { return }
        for index in batchPairs.indices {
            guard !Task.isCancelled, generation == batchSelectionGeneration else { return }
            let pair = batchPairs[index]
            do {
                let frontData = try await data(from: pair.front, side: "front")
                let frontPreview = try await EbayListingPhotoExport.makeInputPreview(data: frontData)
                guard !Task.isCancelled, generation == batchSelectionGeneration else { return }
                batchPairs[index].frontPreview = frontPreview

                let backData = try await data(from: pair.back, side: "back")
                let backPreview = try await EbayListingPhotoExport.makeInputPreview(data: backData)
                guard !Task.isCancelled, generation == batchSelectionGeneration else { return }
                batchPairs[index].backPreview = backPreview
            } catch is CancellationError {
                return
            } catch {
                guard generation == batchSelectionGeneration else { return }
                batchErrorMessage = "Card \(index + 1) could not be previewed: \(error.localizedDescription)"
                return
            }
        }
    }

    private func data(from item: PhotosPickerItem, side: String) async throws -> Data {
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw EbayListingPhotoExport.Error.decodeFailed(side: side)
        }
        return data
    }

    private func startBatch() {
        guard !isPreparingBatch, !batchPairs.isEmpty else { return }
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
        guard generation == batchSelectionGeneration, !batchPairs.isEmpty else {
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
            directory = try EbayListingPhotoExport.makeBatchDirectory()
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
                EbayListingPhotoExport.removeRunContainer(forContentDirectory: directory)
                if generation == batchSelectionGeneration {
                    isPreparingBatch = false
                    batchProgress = nil
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
                    backData: backData
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
                    EbayListingPhotoExport.removeRunContainer(forContentDirectory: completedOutput.contentDirectory)
                }
                EbayListingPhotoExport.removeRunContainer(forContentDirectory: directory)
                return
            } catch {
                if let completedOutput {
                    EbayListingPhotoExport.removeRunContainer(forContentDirectory: completedOutput.contentDirectory)
                }
                failures.append("Card \(index + 1): \(error.localizedDescription)")
            }
        }

        guard generation == batchSelectionGeneration, !Task.isCancelled else {
            EbayListingPhotoExport.removeRunContainer(forContentDirectory: directory)
            return
        }
        batchFailures = failures
        if successfulCount == 0 {
            isPreparingBatch = false
            batchProgress = nil
            batchErrorMessage = EbayListingPhotoExport.Error.emptyBatch.localizedDescription
            EbayListingPhotoExport.removeRunContainer(forContentDirectory: directory)
            batchDirectory = nil
            return
        }

        do {
            let archive = try await EbayListingPhotoExport.makeArchive(at: directory)
            // The archive worker is not cancellation-aware, so it finishes even
            // when the batch was cancelled mid-zip. Re-check before publishing.
            guard generation == batchSelectionGeneration, !Task.isCancelled else {
                EbayListingPhotoExport.removeRunContainer(forContentDirectory: directory)
                return
            }
            batchArchiveURL = archive
            isPreparingBatch = false
            batchProgress = nil
        } catch {
            isPreparingBatch = false
            batchProgress = nil
            batchErrorMessage = error.localizedDescription
            EbayListingPhotoExport.removeRunContainer(forContentDirectory: directory)
            batchDirectory = nil
        }
    }

    private func invalidateBatchResults() {
        guard batchDirectory != nil || batchArchiveURL != nil else { return }
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
        batchPickerItems = []
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
        EbayListingPhotoExport.removeRunContainer(forContentDirectory: batchDirectory)
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

private struct BatchPairRow: View {
    @Binding var pair: EbayListingPhotosView.BatchPair
    let isEditable: Bool
    let onChange: () -> Void

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
                    onChange()
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
            onChange()
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
