import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

@MainActor
final class CardCenteringViewModel: ObservableObject {
    @Published var selectedPhoto: PhotosPickerItem?
    @Published var image: UIImage?
    @Published var measurement: CardCenteringMeasurement?
    @Published var rotationDegrees = 0.0
    @Published var isAnalyzing = false
    @Published var errorMessage: String?

    private var sourceData: Data?
    private var loadGeneration = 0
    private var analysisGeneration = 0

    func loadSelectedPhoto() async {
        guard let selectedPhoto else { return }
        loadGeneration &+= 1
        let requestID = loadGeneration
        do {
            guard let data = try await selectedPhoto.loadTransferable(type: Data.self) else {
                throw CardCenteringAnalyzerError.unreadableImage
            }
            guard requestID == loadGeneration, !Task.isCancelled else { return }
            sourceData = data
            self.selectedPhoto = nil
            rotationDegrees = 0
            analyze(data, rotationDegrees: 0)
        } catch {
            guard requestID == loadGeneration, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    func loadCapturedPhoto(_ data: Data) {
        loadImageData(data)
    }

    func loadFile(at url: URL) async {
        loadGeneration &+= 1
        let requestID = loadGeneration
        do {
            let data = try await Task.detached(priority: .userInitiated) {
                let hasAccess = url.startAccessingSecurityScopedResource()
                defer {
                    if hasAccess { url.stopAccessingSecurityScopedResource() }
                }
                return try Data(contentsOf: url, options: .mappedIfSafe)
            }.value
            guard requestID == loadGeneration, !Task.isCancelled else { return }
            loadImageData(data)
        } catch {
            guard requestID == loadGeneration, !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func loadImageData(_ data: Data) {
        loadGeneration &+= 1
        sourceData = data
        selectedPhoto = nil
        rotationDegrees = 0
        analyze(data, rotationDegrees: 0)
    }

    func adjustRotation(by amount: Double) {
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
        measurement.outer[keyPath: keyPath] = min(range.upperBound, max(range.lowerBound, value))
        measurement.refreshWarnings()
        self.measurement = measurement
    }

    func updateInner(
        _ keyPath: WritableKeyPath<CardCenteringEdges, Int>,
        to value: Int,
        within range: ClosedRange<Int>
    ) {
        guard var measurement else { return }
        measurement.inner[keyPath: keyPath] = min(range.upperBound, max(range.lowerBound, value))
        measurement.refreshWarnings()
        self.measurement = measurement
    }

#if DEBUG
    /// Gives the screenshot route a stable, local image so the centering controls
    /// can be checked without a Photos permission prompt or a camera session.
    func loadDebugFixtureIfNeeded() {
        guard sourceData == nil else { return }

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
        loadImageData(data)
    }
#endif

    /// Compose the current image, its guides and its figures into one PNG on
    /// disk, ready to hand to the share sheet.
    ///
    /// Written to a file rather than shared as raw image data so the sheet has a
    /// real filename to offer — the measurement is the point of the export, and
    /// "Card Centering 52.3-47.7 49.1-50.9.png" still says what it is a year
    /// later in a folder of screenshots.
    func makeExportFile() -> URL? {
        guard let image, let measurement else { return nil }
        let rendered = CardCenteringExport.render(
            image: image,
            measurement: measurement,
            // Rotation is a display adjustment. It does not rerun detection and
            // it does not move either guide, so the export uses the same visual
            // treatment as the preview.
            rotationDegrees: rotationDegrees
        )
        guard let data = rendered.pngData() else {
            errorMessage = "The centering image could not be prepared for export."
            return nil
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(CardCenteringExport.filename(for: measurement))
        do {
            try data.write(to: url, options: .atomic)
            return url
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    private func analyze(_ data: Data, rotationDegrees: Double) {
        analysisGeneration &+= 1
        let requestID = analysisGeneration
        isAnalyzing = true
        errorMessage = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try CardCenteringAnalyzer.analyze(data, rotationDegrees: rotationDegrees) }
            DispatchQueue.main.async {
                guard let self, self.analysisGeneration == requestID else { return }
                self.isAnalyzing = false
                switch result {
                case let .success(analysis):
                    self.image = analysis.image
                    self.measurement = analysis.measurement
                    // `analysis.image` is already straightened when the card was
                    // skewed, and the measurement is in that image's
                    // coordinates. `rotationDegrees` is the person's own display
                    // adjustment and stays theirs — adding the correction to it
                    // would rotate an already-level card a second time.
                case let .failure(error):
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}

struct CardCenteringView: View {
    @StateObject private var model = CardCenteringViewModel()
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    @State private var isShowingCamera = false
    @State private var isShowingSettings = false
    @State private var isShowingFileImporter = false
    @State private var isOuterExpanded = ProcessInfo.processInfo.arguments.contains("CenteringExpanded")
    @State private var isInnerExpanded = ProcessInfo.processInfo.arguments.contains("CenteringExpanded")
    /// The rendered export, prepared ahead of the tap so `ShareLink` can own the
    /// presentation. `ShareLink` anchors itself correctly as a popover in wide
    /// windows and as a sheet in narrow ones, which a hand-rolled
    /// `UIActivityViewController` does not.
    @State private var exportURL: URL?

    var body: some View {
        NavigationStack {
            Group {
                if let image = model.image, let measurement = model.measurement {
                    VStack(spacing: 0) {
                        GeometryReader { proxy in
                            imageReview(image, measurement: measurement)
                                .frame(width: proxy.size.width, height: proxy.size.height)
                        }
                        .frame(height: 300)
                        .padding(.horizontal, 16)
                        .padding(.top, 8)

                        Divider()

                        ScrollViewReader { reader in
                            ScrollView {
                                VStack(spacing: 18) {
                                    resultSummary(measurement)
                                    rotationControls
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
                                      arguments.indices.contains(routeIndex + 1),
                                      arguments[routeIndex + 1] == "CenteringExpanded" else { return }
                                DispatchQueue.main.async {
                                    withAnimation(nil) {
                                        reader.scrollTo("guide-controls", anchor: .top)
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Settings", systemImage: "gearshape") {
                        isShowingSettings = true
                    }
                    .labelStyle(.iconOnly)
                    .accessibilityLabel("Settings")
                }

                if model.image != nil {
                    ToolbarItemGroup(placement: .topBarTrailing) {
                        if let exportURL {
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

                        Button("Take Photo", systemImage: "camera") {
                            isShowingCamera = true
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Take a new photo")

                        photoButton("Choose Photo")
                            .labelStyle(.iconOnly)
                            .accessibilityLabel("Choose a photo")

                        Button("Choose File", systemImage: "folder") {
                            isShowingFileImporter = true
                        }
                        .labelStyle(.iconOnly)
                        .accessibilityLabel("Choose an image file")
                    }
                }
            }
            .onChange(of: model.selectedPhoto) {
                Task { await model.loadSelectedPhoto() }
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
            .task(id: model.measurement) {
                exportURL = model.makeExportFile()
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
    }

    private func photoButton(_ title: String) -> some View {
        PhotosPicker(selection: $model.selectedPhoto, matching: .images) {
            Label(title, systemImage: "photo.on.rectangle")
        }
    }

    private func imageReview(_ image: UIImage, measurement: CardCenteringMeasurement) -> some View {
        CardCenteringImage(image: image, measurement: measurement, rotationDegrees: model.rotationDegrees)
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
                    .onEnded { _ in lastZoom = zoom }
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
            .accessibilityLabel("Card image with outer red guides and inner cyan guides")
    }

    private func resultSummary(_ measurement: CardCenteringMeasurement) -> some View {
        VStack(spacing: 14) {
            HStack(spacing: 12) {
                CenteringMetric(title: "Left / Right", value: measurement.leftRightCentering)
                CenteringMetric(title: "Top / Bottom", value: measurement.topBottomCentering)
            }

            HStack {
                borderValue("L", measurement.leftBorder)
                borderValue("R", measurement.rightBorder)
                borderValue("T", measurement.topBorder)
                borderValue("B", measurement.bottomBorder)
            }

            if !measurement.warnings.isEmpty {
                Label(measurement.warnings.joined(separator: " "), systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Divider()

            if let exportURL {
                ShareLink(item: exportURL) {
                    Label("Export Image", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }

    private func borderValue(_ label: String, _ value: Int) -> some View {
        VStack(spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text("\(value) px").font(.subheadline.monospacedDigit())
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

            HStack(spacing: 8) {
                rotationButton("−1", -1)
                rotationButton("−0.1", -0.1)
                rotationButton("−0.01", -0.01)
                rotationButton("+0.01", 0.01)
                rotationButton("+0.1", 0.1)
                rotationButton("+1", 1)
            }

            HStack {
                Button("Reset") { model.resetRotation() }
                    .disabled(model.rotationDegrees == 0)
                Spacer()
                Text("Rotates photo only")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }

    private func rotationButton(_ title: String, _ amount: Double) -> some View {
        Button(title) { model.adjustRotation(by: amount) }
            .buttonStyle(.bordered)
            .font(.caption.monospacedDigit())
            .frame(maxWidth: .infinity)
    }

    private func guideControls(_ measurement: CardCenteringMeasurement) -> some View {
        VStack(spacing: 14) {
            Text("Adjust Guides")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("Red marks the card edge. Cyan marks the inner frame.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            DisclosureGroup("Outer card edge", isExpanded: $isOuterExpanded) {
                VStack(spacing: 10) {
                    edgeStepper("Left", value: outerBinding(\.left, range: 0...(measurement.imageWidth - 1)), range: 0...(measurement.imageWidth - 1))
                    edgeStepper("Right", value: outerBinding(\.right, range: 0...(measurement.imageWidth - 1)), range: 0...(measurement.imageWidth - 1))
                    edgeStepper("Top", value: outerBinding(\.top, range: 0...(measurement.imageHeight - 1)), range: 0...(measurement.imageHeight - 1))
                    edgeStepper("Bottom", value: outerBinding(\.bottom, range: 0...(measurement.imageHeight - 1)), range: 0...(measurement.imageHeight - 1))
                }
                .padding(.top, 10)
            }

            DisclosureGroup("Inner frame", isExpanded: $isInnerExpanded) {
                VStack(spacing: 10) {
                    edgeStepper("Left", value: innerBinding(\.left, range: 0...(measurement.imageWidth - 1)), range: 0...(measurement.imageWidth - 1))
                    edgeStepper("Right", value: innerBinding(\.right, range: 0...(measurement.imageWidth - 1)), range: 0...(measurement.imageWidth - 1))
                    edgeStepper("Top", value: innerBinding(\.top, range: 0...(measurement.imageHeight - 1)), range: 0...(measurement.imageHeight - 1))
                    edgeStepper("Bottom", value: innerBinding(\.bottom, range: 0...(measurement.imageHeight - 1)), range: 0...(measurement.imageHeight - 1))
                }
                .padding(.top, 10)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }

    private func edgeStepper(_ label: String, value: Binding<Int>, range: ClosedRange<Int>) -> some View {
        Stepper(value: value, in: range) {
            HStack(spacing: 10) {
                Text(label)
                Spacer(minLength: 8)
                TextField("0", value: value, format: .number)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 82)
                    .monospacedDigit()
                    .accessibilityLabel("\(label) guide position")
                    .accessibilityValue("\(value.wrappedValue) pixels")
                Text("px")
                    .foregroundStyle(.secondary)
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

private struct CardCenteringImage: View {
    let image: UIImage
    let measurement: CardCenteringMeasurement
    let rotationDegrees: Double

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

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .rotationEffect(.degrees(rotationDegrees))

            guideLines(measurement.outer, color: .red, origin: origin, size: fittedSize)
            guideLines(measurement.inner, color: .cyan, origin: origin, size: fittedSize)
        }
        .aspectRatio(CGFloat(measurement.imageWidth) / CGFloat(measurement.imageHeight), contentMode: .fit)
        .background(Color.black)
    }

    private func guideLines(_ edges: CardCenteringEdges, color: Color, origin: CGPoint, size: CGSize) -> some View {
        let xScale = size.width / CGFloat(measurement.imageWidth)
        let yScale = size.height / CGFloat(measurement.imageHeight)
        return Path { path in
            for x in [edges.left, edges.right] {
                let position = origin.x + CGFloat(x) * xScale
                path.move(to: CGPoint(x: position, y: origin.y))
                path.addLine(to: CGPoint(x: position, y: origin.y + size.height))
            }
            for y in [edges.top, edges.bottom] {
                let position = origin.y + CGFloat(y) * yScale
                path.move(to: CGPoint(x: origin.x, y: position))
                path.addLine(to: CGPoint(x: origin.x + size.width, y: position))
            }
        }
        .stroke(color, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        .allowsHitTesting(false)
    }
}
