import SwiftData
import SwiftUI

/// One continuous session. The camera is the product surface and never goes
/// away: there is no result screen, no confirm step, and no dismiss animation
/// between cards. Success is a receipt below the footer guide while the next
/// card is already being read.
struct ScannerView: View {
    let browseCatalog: BrowseCatalog
    @EnvironmentObject private var model: ScannerViewModel
    @EnvironmentObject private var summaryStore: ScanSessionSummaryStore
    @EnvironmentObject private var writeCoordinator: DerivedStateWriteCoordinator
    @EnvironmentObject private var collectionProjection: CollectionProjectionStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var storageGeneration = CollectionStorageGeneration.shared

    @State private var isShowingSettings = false
    @State private var reviewing: RecentScan?
    @State private var isShowingSessionReview = false
    @State private var isShowingTradeReview = false
    @State private var isShowingUnresolved = false
    @State private var pendingUnresolvedResolution: PendingUnresolvedResolution?
    @State private var guideFrames: ScannerGuideFrames?
#if DEBUG && targetEnvironment(simulator)
    @State private var didSeedCameraOptionsFixture = false
#endif
#if DEBUG && LOCAL_ONLY_SIGNING
    @Environment(\.cardGameRuntimes) private var runtimes
    @State private var acceptanceNumber = OnePieceCatalogBootstrap.acceptanceNumber()
    @State private var injectedAcceptanceSample = false
    @State private var lorcanaSample = LorcanaReviewLaunch.initialSample
    @State private var injectedLorcanaSample = false
    @State private var yuGiOhSample = YuGiOhAcceptanceLaunch.Sample.older
    @State private var injectedYuGiOhSample = false
    @State private var yuGiOhDiagnostic: String?

    private func injectYuGiOhSample() {
        guard let recognizer = runtimes?.runtime(for: .yuGiOh)?.recognizer else { return }
        let outcome = recognizer.identify(yuGiOhSample.lines)
        yuGiOhDiagnostic = YuGiOhAcceptanceLaunch.diagnostic(for: outcome)
        guard case let .identified(subject) = outcome else { return }
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), subject, nil)
    }

    private func injectLorcanaSample() {
        guard let recognizer = runtimes?.runtime(for: .lorcana)?.recognizer,
              case let .identified(subject) = recognizer.identify([.init(text: lorcanaSample.footerText)]) else { return }
        // Use the actual scanner/model callback and catalog authority. This is
        // synthetic OCR input, not a fabricated successful scan or device proof.
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), subject, nil)
    }

    private var acceptanceReady: Bool {
        if YuGiOhAcceptanceLaunch.enabled {
            if YuGiOhAcceptanceLaunch.pricingSourceReview
                || (YuGiOhAcceptanceLaunch.initialSample == nil && YuGiOhAcceptanceLaunch.storageDirectory != "YuGiOhAcceptance") {
                return runtimes?.runtime(for: .yuGiOh) != nil
            }
            return injectedYuGiOhSample && (yuGiOhDiagnostic != nil
                || (model.recognitionCount > 0 && !model.isIdentificationProcessingForTesting
                    && (model.pendingIdentityChoice != nil || model.pendingChoice != nil
                        || model.successCount > 0 || model.unresolvedCount > 0)))
        }
        return ((OnePieceCatalogBootstrap.isAcceptanceLaunch() && injectedAcceptanceSample)
            || (LorcanaReviewLaunch.isEnabled() && injectedLorcanaSample))
            && model.recognitionCount > 0 && !model.isIdentificationProcessingForTesting
            && (model.pendingIdentityChoice != nil || model.pendingChoice != nil
                || model.successCount > 0 || model.unresolvedCount > 0)
    }

    private func writeAcceptanceReadyMarker() {
        let arguments = ProcessInfo.processInfo.arguments
        guard acceptanceReady,
              let index = arguments.firstIndex(of: "-ui_debug_ready_path"),
              arguments.indices.contains(index + 1) else { return }
        let marker = YuGiOhAcceptanceLaunch.enabled ? #"{"yuGiOhAcceptanceReady":true}"#
            : LorcanaReviewLaunch.isEnabled() ? #"{"lorcanaReviewReady":true}"# : #"{"onePieceAcceptanceReady":true}"#
        try? Data(marker.utf8)
            .write(to: URL(fileURLWithPath: arguments[index + 1]), options: .atomic)
    }

    private func injectAcceptanceSample() {
        guard let adapter = runtimes?.runtime(for: .onePiece)?.catalog as? OnePieceCatalogAdapter,
              case let .identified(subject) = OnePieceScanProfile(registry: adapter.registry)
                .identify([.init(text: acceptanceNumber)]) else { return }
        model.scanner.onConfirmedSubjectCandidate?(nil, UUID(), subject, nil)
    }
#endif

    private struct PendingUnresolvedResolution {
        let id: UUID
        let choice: UnresolvedResolutionChoice
    }

    init(browseCatalog: BrowseCatalog = BrowseCatalog()) {
        self.browseCatalog = browseCatalog
    }

#if DEBUG
    private var scannerScreenshotRoute: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ui_debug_route"),
              arguments.indices.contains(index + 1) else { return nil }
        let route = arguments[index + 1]
        return [
            "WholeCardScanner",
            "PriceCheck",
            "TradeAnalyzer",
            "ScanChoiceCancellation",
            "TrustScanReceipt"
        ].contains(route) ? route : nil
    }
#endif

    var body: some View {
        ZStack {
            CameraPreview(
                scanner: model.scanner,
                successCount: model.successCount,
                recognitionCount: model.recognitionCount,
                onGuideFramesChange: { guideFrames = $0 }
            )
                .ignoresSafeArea()

            ScannerChrome(
                model: model,
                scanner: model.scanner,
                guideFrames: guideFrames,
                openSettings: {
                    model.pauseForSettingsPresentation()
                    isShowingSettings = true
                },
                openReview: { scan in
                    model.pauseForPresentation()
                    reviewing = scan
                },
                openUnresolved: {
                    model.pauseForPresentation()
                    isShowingUnresolved = true
                },
                openSessionReview: {
                    model.pauseForPresentation()
                    isShowingSessionReview = true
                },
                openTradeReview: {
                    guard model.canOpenTradeReview else { return }
                    model.pauseForPresentation()
                    isShowingTradeReview = true
                }
            )
            // Camera chrome uses white labels in either app appearance. Match
            // the material and button contrast to that fixed foreground.
            .environment(\.colorScheme, .dark)
        }
#if DEBUG && LOCAL_ONLY_SIGNING
        .safeAreaInset(edge: .top) {
            if LorcanaReviewLaunch.isEnabled() {
                VStack(alignment: .leading, spacing: 8) {
                    Menu {
                        Picker("Review sample", selection: $lorcanaSample) {
                            ForEach(LorcanaReviewLaunch.samples) { sample in
                                Text(sample.label).tag(sample)
                            }
                        }
                    } label: {
                        Label(lorcanaSample.label, systemImage: "list.bullet")
                            .font(.caption2)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: 44)
                    }
                    .accessibilityIdentifier("lorcana-review-sample")
                    Button(action: injectLorcanaSample) {
                        Text("Scan synthetic footer")
                            .font(.caption2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                        .buttonStyle(.borderedProminent)
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("lorcana-review-inject")
                        .disabled(model.pendingIdentityChoice != nil || model.pendingChoice != nil
                            || model.pendingPrintRunChoice != nil || model.isIdentificationProcessingForTesting
                            || runtimes?.runtime(for: .lorcana) == nil)
                }
                .padding(8).frame(maxWidth: .infinity, alignment: .leading).background(.regularMaterial)
            }
            if YuGiOhAcceptanceLaunch.enabled {
                if YuGiOhAcceptanceLaunch.pricingSourceReview {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Bundled source").font(.headline)
                        YuGiOhPricingNotice()
                        Text("Synthetic approved-source presentation").font(.headline)
                        YuGiOhPricingNotice()
                            .environment(\.cardGameRuntimes, YuGiOhAcceptanceLaunch.pricingReviewRuntimes)
                    }
                    .font(.footnote).padding().background(.regularMaterial)
                } else {
                    VStack(spacing: 4) {
                        Text("Yu-Gi-Oh! fixture OCR · Separate test collection").font(.caption).foregroundStyle(.secondary)
                        if let yuGiOhDiagnostic {
                            Text(yuGiOhDiagnostic).font(.caption)
                                .accessibilityIdentifier("yugioh-recognition-diagnostic")
                        }
                        HStack {
                            Menu(yuGiOhSample.rawValue) {
                                ForEach(YuGiOhAcceptanceLaunch.Sample.allCases) { sample in
                                    Button(sample.rawValue) { yuGiOhSample = sample }
                                }
                            }
                            Button("Inject code", action: injectYuGiOhSample)
                                .disabled(model.pendingIdentityChoice != nil || model.pendingChoice != nil || model.isIdentificationProcessingForTesting)
                        }
                    }.padding(8).frame(maxWidth: .infinity).background(.regularMaterial)
                }
            }
            if OnePieceCatalogBootstrap.isAcceptanceLaunch() {
                VStack(spacing: 4) {
                    Text("One Piece acceptance · Separate test collection")
                        .font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Menu(acceptanceNumber) {
                            ForEach(["ST11-003", "ST01-003", "OP01-120", "P-001", "OP01-999"], id: \.self) { number in
                                Button(number) { acceptanceNumber = number }
                            }
                        }
                        Button("Inject number", action: injectAcceptanceSample)
                            .accessibilityIdentifier("one-piece-acceptance-inject")
                            .disabled(model.pendingIdentityChoice != nil || model.pendingChoice != nil
                                || model.isIdentificationProcessingForTesting
                                || runtimes?.runtime(for: .onePiece) == nil)
                    }
                }
                .padding(8).frame(maxWidth: .infinity).background(.regularMaterial)
            }
        }
        .onChange(of: acceptanceReady, initial: true) { _, ready in
            if ready { writeAcceptanceReadyMarker() }
        }
#endif
        .onAppear {
#if DEBUG
            if scannerScreenshotRoute == "PriceCheck" {
                model.setPurpose(.priceCheck)
            }
            if scannerScreenshotRoute == "TradeAnalyzer" {
                let arguments = ProcessInfo.processInfo.arguments
                model.seedTradeScreenshot(
                    populated: !arguments.contains("empty") && !arguments.contains("review-empty"),
                    partiallyPriced: arguments.contains("review-partial")
                )
                isShowingTradeReview = ["review", "review-empty", "review-partial"].contains { arguments.contains($0) }
            }
            if scannerScreenshotRoute == "WholeCardScanner" || scannerScreenshotRoute == "TrustScanReceipt" {
                if ProcessInfo.processInfo.arguments.contains("permission-denied") {
                    model.scanner.uiState.setCameraIssue(.permissionDenied)
                } else if ProcessInfo.processInfo.arguments.contains("multitasking-unavailable") {
                    model.scanner.uiState.setCameraIssue(.multitaskingUnavailable)
                } else {
                    model.seedReceiptFixtureForScreenshot()
                }
                if ProcessInfo.processInfo.arguments.contains("recovery-saving") { isShowingUnresolved = true }
            }
#if targetEnvironment(simulator)
            if scannerScreenshotRoute == "WholeCardScanner", !didSeedCameraOptionsFixture {
                let arguments = ProcessInfo.processInfo.arguments
                let longSummary = arguments.contains("camera-options-long")
                if longSummary || arguments.contains("camera-options") {
                    model.scanner.simulateLensAttachmentsForTesting()
                    if longSummary { model.seedLongScannerToolbarForScreenshot() }
                    if arguments.contains("scan-light-on") {
                        // After launch settles: the first scene-phase change
                        // turns the light off, as it should on a device.
                        let scanner = model.scanner
                        Task { @MainActor in
                            try? await Task.sleep(for: .seconds(0.5))
                            scanner.simulateScanLightOnForScreenshot(level: 0.4)
                        }
                    }
                    didSeedCameraOptionsFixture = true
                }
            }
#endif
            if scannerScreenshotRoute == "ScanChoiceCancellation" {
                model.seedVariantChoiceCancellationFixtureForScreenshot()
            }
            guard scannerScreenshotRoute == nil else { return }
#endif
#if DEBUG && LOCAL_ONLY_SIGNING
            let usesCamera = !OnePieceCatalogBootstrap.isAcceptanceLaunch() && !LorcanaReviewLaunch.isEnabled() && !YuGiOhAcceptanceLaunch.enabled
#else
            let usesCamera = true
#endif
            model.start(
                context: modelContext,
                isSceneActive: scenePhase == .active,
                startCamera: usesCamera,
                shouldRefreshMagicDirectory: usesCamera,
                summaryStore: summaryStore,
                writeCoordinator: writeCoordinator,
                storageGeneration: storageGeneration,
                collectionProjection: collectionProjection
            )
#if DEBUG && LOCAL_ONLY_SIGNING
            if LorcanaReviewLaunch.isEnabled(), !injectedLorcanaSample {
                injectedLorcanaSample = true
                model.setPurpose(.collection)
                model.clearFinishLocks()
                injectLorcanaSample()
            }
            if let sample = YuGiOhAcceptanceLaunch.initialSample, !injectedYuGiOhSample {
                injectedYuGiOhSample = true
                yuGiOhSample = sample
                injectYuGiOhSample()
            }
            if OnePieceCatalogBootstrap.isAcceptanceLaunch(), !injectedAcceptanceSample {
                injectedAcceptanceSample = true
                model.setPurpose(.collection)
                model.clearFinishLocks()
                injectAcceptanceSample()
            }
#endif
        }
        .onDisappear { model.viewDisappeared() }
        .onChange(of: isSheetRequested, initial: true) { _, requested in
            model.setScannerSheetRequested(requested)
        }
        .onChange(of: scenePhase) { _, phase in
            model.scenePhaseChanged(
                isActive: phase == .active,
                isBackgrounded: phase == .background
            )
        }
        .sheet(isPresented: $isShowingSettings, onDismiss: model.resumeAfterSettingsPresentation) {
            SettingsView()
        }
        .sheet(item: $reviewing, onDismiss: model.resumeAfterPresentation) { scan in
                    ScanReviewSheet(
                        scan: scan,
                        onCorrect: { variant in
                            await model.correct(scanID: scan.id, to: variant)
                        },
                        onDelete: {
                            let didDelete = await model.undoScan(scanID: scan.id)
                            if didDelete {
                                reviewing = nil
                            }
                            return didDelete
                        }
                    )
        }
        .sheet(isPresented: $isShowingUnresolved, onDismiss: {
            if let pendingUnresolvedResolution {
                model.resolveUnresolved(
                    id: pendingUnresolvedResolution.id,
                    choice: pendingUnresolvedResolution.choice
                )
                self.pendingUnresolvedResolution = nil
            }
            model.resumeAfterPresentation()
        }) {
            UnresolvedScansSheet(
                model: model,
                browseCatalog: browseCatalog,
                onClear: model.clearUnresolvedScans,
                onDismiss: model.dismissUnresolved,
                onResolve: { id, choice in
                    guard model.canResolveUnresolved(id: id, choice: choice) else { return }
                    pendingUnresolvedResolution = PendingUnresolvedResolution(
                        id: id,
                        choice: choice
                    )
                    isShowingUnresolved = false
                }
            )
        }
        .sheet(item: $model.priceCheckResult, onDismiss: model.dismissPriceCheckResult) { result in
            PriceCheckResultView(initialResult: result)
        }
        .sheet(isPresented: $isShowingSessionReview, onDismiss: model.resumeAfterPresentation) {
            ScanSessionReviewSheet()
        }
        .sheet(isPresented: $isShowingTradeReview, onDismiss: model.resumeAfterPresentation) {
            TradeReviewSheet(model: model)
        }
        .toolbar(isScanChoicePending ? .hidden : .visible, for: .tabBar)
    }

    /// Price Check's result sheet is owned by the view model and excluded here.
    private var isSheetRequested: Bool {
        isShowingSettings || reviewing != nil || isShowingUnresolved || isShowingSessionReview || isShowingTradeReview
    }

    /// Keep the existing focused choice flow until the current scan is resolved.
    private var isScanChoicePending: Bool {
        model.pendingChoice != nil
            || model.pendingPrintRunChoice != nil
            || model.pendingIdentityChoice != nil
            || model.pendingDuplicateConfirmation != nil
    }
}

/// The chrome observes the view model, while scanner-owned status is isolated to
/// small child views. A Vision publication therefore cannot rebuild the menu
/// hierarchy just because the camera preview received another frame.
private struct ScannerChrome: View {
    @ObservedObject var model: ScannerViewModel
    let scanner: CardScanner
    let guideFrames: ScannerGuideFrames?
    let openSettings: () -> Void
    let openReview: (RecentScan) -> Void
    let openUnresolved: () -> Void
    let openSessionReview: () -> Void
    let openTradeReview: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace
    @State private var isSessionExpanded = false
    @State private var lens: CameraLens = .standard
    @State private var availableLenses: [CameraLens] = []

    var body: some View {
        GeometryReader { geometry in
            let frame = geometry.frame(in: .global)
            let reservesWholeGuide = model.purpose == .tradeAnalyzer && !isScanChoicePending
            let protectedGuide = guideFrames.map { reservesWholeGuide ? $0.card.union($0.footer) : $0.footer }
            let guideSpacing: CGFloat = reservesWholeGuide ? 8 : 12
            let topHeight = max(0, (protectedGuide?.minY ?? frame.midY) - frame.minY - guideSpacing)
            let feedbackHeight = max(0, frame.maxY - (protectedGuide?.maxY ?? frame.midY) - guideSpacing)
            ZStack(alignment: .top) {
                Group {
                    if reservesWholeGuide {
                        ScrollView {
                            VStack(spacing: 5) {
                                topBar
                                topStack
                            }
                        }
                        .scrollBounceBehavior(.basedOnSize)
                    } else {
                        VStack(spacing: 10) {
                            topBar
                            ScrollView { topStack }
                                .scrollBounceBehavior(.basedOnSize)
                        }
                    }
                }
                .frame(height: topHeight, alignment: .top)
                .accessibilityIdentifier("scanner-top-controls")

                ScrollView {
                    scanFeedback.fixedSize(horizontal: false, vertical: true)
                }
                .scrollBounceBehavior(.basedOnSize)
                .frame(height: feedbackHeight)
                .frame(maxHeight: .infinity, alignment: .bottom)
                .accessibilityIdentifier("scanner-bottom-feedback")
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .contentWidthLimit(.standard)
        .overlay {
            ScannerCameraIssueOverlay(state: scanner.uiState)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.receipt)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.scanAcknowledgement)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.pendingChoice)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.pendingPrintRunChoice)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.pendingIdentityChoice)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.pendingDuplicateConfirmation)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.heldDuplicateOffer)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: model.recent)
        .animation(.easeOut(duration: 0.18), value: model.sessionScans.count)
        .animation(.easeOut(duration: 0.18), value: model.note)
        .animation(.easeOut(duration: 0.18), value: isScanChoicePending)
        .transaction { transaction in
            if reduceMotion {
                transaction.animation = nil
                transaction.disablesAnimations = true
            }
        }
        .onChange(of: model.receipt?.id) { _, id in
            // The receipt is visual; say the same thing for someone scanning
            // by ear. Only collection adds produce a receipt.
            guard id != nil, let receipt = model.receipt, model.purpose == .collection else { return }
            var message = "Added \(receipt.name)"
            if case let .price(price) = receipt.price, !receipt.isGradedPricePending {
                message += ", \(price.unitMarketPriceUSD.formatted(.currency(code: price.currencyCode)))"
                if !receipt.isGraded, price.isStale() { message += ", last known price" }
            }
            AccessibilityNotification.Announcement(message).post()
        }
    }

    private var topBar: some View {
        ScannerTopBar(
            purpose: model.purpose,
            subjectMode: model.subjectMode,
            lens: lens,
            availableLenses: availableLenses,
            finishLocks: model.finishLocks,
            variantLockMenu: model.gameRegistry.variantLockMenu,
            isSlowIdentifying: model.isSlowIdentifying,
            setPurpose: model.setPurpose,
            setSubjectMode: model.setSubjectMode,
            setLens: scanner.setLens,
            setFinishLock: model.setFinishLock,
            clearFinishLocks: model.clearFinishLocks,
            openSettings: openSettings,
            scannerState: scanner.uiState,
            setScanLight: scanner.setScanLight,
            setScanLightLevel: scanner.setScanLightLevel
        )
        .equatable()
        // Observe the confirmed camera values without observing per-frame scanner state.
        .onReceive(scanner.uiState.$lens) { if lens != $0 { lens = $0 } }
        .onReceive(scanner.uiState.$availableLenses) { if availableLenses != $0 { availableLenses = $0 } }
    }

    private var topStack: some View {
        VStack(spacing: 10) {
            // A question owns the screen until it is answered: history steps
            // aside so the only thing above the band is the one decision.
            if !isScanChoicePending {
                if model.purpose == .tradeAnalyzer {
                    TradeScannerControls(model: model, openReview: openTradeReview)
                } else {
                    sessionHistory
                        .transition(.opacity)
                }
            }

            scanActions

            if model.purpose != .tradeAnalyzer, let note = model.note {
                ScanNoteView(note: note)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            ScannerStatusView(state: scanner.uiState)

            if let offer = model.pendingSlabConversionOffer {
                PendingSlabConversionOfferView(
                    offer: offer,
                    onConvert: { Task { await model.convertRawScanToGraded(scanID: offer.scanID) } },
                    onDismiss: model.dismissSlabConversionOffer
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let offer = model.heldDuplicateOffer {
                HeldDuplicateOfferView(
                    offer: offer,
                    onAddAnother: model.addAnotherHeldCopy
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if let correction = model.pendingGradedVariantCorrection {
                GradedVariantCorrectionOfferView(
                    correction: correction,
                    onChoose: model.chooseGradedVariant,
                    onDismiss: model.dismissGradedVariantCorrection
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Top actions

    private var scanActions: some View {
        VStack(spacing: 9) {
            if let confirmation = model.pendingDuplicateConfirmation {
                DuplicateConfirmationBar(
                    confirmation: confirmation,
                    onSameCard: model.chooseSameCard,
                    onAddAnother: model.addAnother
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .appGlassEffectID("scanner-top-actions", in: glassNamespace)
            } else if let choice = model.pendingIdentityChoice {
                if choice.request.identifier.game == .yuGiOh,
                   model.scanAcknowledgement?.encounterID == choice.request.encounterID,
                   model.scanAcknowledgement?.phase == .failed,
                   let message = model.scanAcknowledgement?.message {
                    Text(message).font(.footnote).foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("printing-choice-recovery-explanation")
                }
                PrintingChoiceBar(
                    choice: choice,
                    onChoose: model.choose,
                    onDismiss: model.dismissIdentityChoice,
                    onChooseEnglish: model.chooseWithEnglishConfirmation
                )
                .id(choice.id)
                .transition(.move(edge: .top).combined(with: .opacity))
                .appGlassEffectID("scanner-top-actions", in: glassNamespace)
            } else if let choice = model.pendingPrintRunChoice {
                PrintRunChoiceBar(
                    choice: choice,
                    onChoose: model.choose,
                    onDismiss: model.dismissPrintRunChoice
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .appGlassEffectID("scanner-top-actions", in: glassNamespace)
            } else if let choice = model.pendingChoice {
                VariantChoiceBar(
                    choice: choice,
                    onChoose: model.choose,
                    onDismiss: model.dismissChoice
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .appGlassEffectID("scanner-top-actions", in: glassNamespace)
            }

            ScannerSlabPromptView(
                state: scanner.uiState,
                switchToRaw: { model.setSubjectMode(.raw) }
            )
        }
    }

    @ViewBuilder
    private var scanFeedback: some View {
        if model.scanAcknowledgement?.subject.identifier.game == .yuGiOh
            || model.pendingIdentityChoice?.displayCandidates.first?.game == .yuGiOh {
            YuGiOhPricingNotice()
                .font(.footnote).foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        // Only the current scan's feedback belongs below the reading band.
        // Explicit choices suppress it until the scan can be confirmed.
        if model.pendingDuplicateConfirmation == nil,
           model.pendingIdentityChoice == nil,
           model.pendingPrintRunChoice == nil,
           model.pendingChoice == nil {
            if let acknowledgement = model.scanAcknowledgement {
                ScanAcknowledgementCard(
                    acknowledgement: acknowledgement,
                    onRetryScan: {
                        model.retryFailedScan(encounterID: acknowledgement.encounterID)
                    }
                )
                    .transition(.opacity)
                    .appGlassEffectID("scanner-feedback", in: glassNamespace)
            } else if model.purpose == .collection, let receipt = model.receipt {
                ScanReceiptCard(
                    receipt: receipt,
                    onUndo: {
                        Task { @MainActor in
                            _ = await model.undoScan(scanID: receipt.scanID)
                        }
                    },
                    onOpen: {
                        guard let scan = model.sessionScans.first(where: { $0.id == receipt.scanID }) else { return }
                        openReview(scan)
                    }
                )
                .transition(.opacity)
                .appGlassEffectID("scanner-feedback", in: glassNamespace)
            } else if model.purpose == .tradeAnalyzer {
                if let note = model.note {
                    ScanNoteView(note: note)
                } else if let entry = model.tradeDraft.latest {
                    TradeScannerReceipt(entry: entry, undo: model.undoLatestTradeScan)
                        .transition(.opacity)
                }
            }
        }
    }

    private var showsSessionTray: Bool {
        model.purpose == .collection && !model.recent.isEmpty
    }

    /// The session at a glance: a fanned stack of the latest cards and a running
    /// count, so progress through a stack is visible without opening anything.
    /// Attention is one tap from the same row, never a second disclosure.
    private var sessionHistory: some View {
        VStack(alignment: .leading, spacing: 8) {
            if showsSessionTray || model.unresolvedCount > 0 {
                sessionPillCluster
            }

            if showsSessionTray, isSessionExpanded {
                sessionTrayContent
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(.white)
    }

    /// Pills share one glass container so neighbouring capsules blend as a
    /// single cluster on Liquid Glass, as the top bar already does.
    @ViewBuilder
    private var sessionPillCluster: some View {
        let pills = ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { sessionPills }
            VStack(alignment: .leading, spacing: 8) { sessionPills }
        }
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) { pills }
        } else {
            pills
        }
    }

    private var isScanChoicePending: Bool {
        model.pendingChoice != nil
            || model.pendingPrintRunChoice != nil
            || model.pendingIdentityChoice != nil
            || model.pendingDuplicateConfirmation != nil
    }

    /// What the stack is worth so far, shown only when at least one card has a
    /// quote. Unpriced cards are left out rather than counted as zero; the
    /// spoken label says how many were priced.
    private var sessionValueText: String? {
        let value = model.sessionKnownValue
        guard value.pricedCount > 0, value.total.isValid else { return nil }
        return value.total.formatted()
    }

    @ViewBuilder
    private var sessionPills: some View {
        if showsSessionTray {
            Button {
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.86)) {
                    isSessionExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    SessionThumbnailStack(scans: Array(model.recent.prefix(3)))
                    Text("\(model.sessionScans.count) added")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .contentTransition(.numericText())
                        .lineLimit(1)
                    if let sessionValueText {
                        Text("·")
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white.opacity(0.45))
                        Text(sessionValueText)
                            .font(.system(.subheadline, design: .rounded).weight(.bold).monospacedDigit())
                            .contentTransition(.numericText())
                            .lineLimit(1)
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .rotationEffect(.degrees(isSessionExpanded ? 180 : 0))
                }
                .foregroundStyle(.white)
                .padding(.leading, 10)
                .padding(.trailing, 12)
                .frame(minHeight: 44)
                .appPillGlass(interactive: true)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("scanner-session-disclosure")
            .accessibilityLabel(sessionAccessibilityLabel)
            .accessibilityValue(isSessionExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint("Shows the cards added during this scanner visit.")
        }

        if model.unresolvedCount > 0 {
            Button(action: openUnresolved) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text(attentionTitle)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .appPillGlass(tint: Color.orange.opacity(0.22), interactive: true)
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("scanner-attention-review")
            .accessibilityHint("Shows what was read and why it was not added")
        }
    }

    private var sessionAccessibilityLabel: String {
        let count = model.sessionScans.count
        guard let sessionValueText else { return "Recent scans, \(count) cards" }
        let priced = model.sessionKnownValue.pricedCount
        let pricedNote = priced == count ? "" : ", from \(priced) priced"
        return "Recent scans, \(count) cards, \(sessionValueText) known value\(pricedNote)"
    }

    private var sessionTrayContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            RecentScanRail(
                scans: model.recent,
                gradedPriceUpdatedScanID: model.gradedPriceUpdatedScanID,
                onSelect: openReview,
                onDelete: model.deleteRecentScan
            )

            Button(action: openSessionReview) {
                HStack(spacing: 8) {
                    Label("Review session", systemImage: "list.bullet.rectangle")
                    Spacer(minLength: 4)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.6))
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("scanner-session-review")
            .accessibilityLabel("Review session, \(model.sessionScans.count) cards")
            .accessibilityHint("Opens every card added during this scanner visit.")
        }
        .padding(.horizontal, 12)
        .padding(.top, 10)
        .appGlass(cornerRadius: 20)
    }

    private var attentionTitle: String {
        "\(model.unresolvedCount) need\(model.unresolvedCount == 1 ? "s" : "") attention"
    }

}

/// The latest few cards, fanned like the stack in your hand.
private struct SessionThumbnailStack: View {
    let scans: [RecentScan]

    var body: some View {
        ZStack {
            ForEach(Array(Array(scans.enumerated()).reversed()), id: \.element.id) { index, scan in
                CardThumbnail(artwork: scan.artwork(prefersFullSize: false), width: 20)
                    .shadow(color: .black.opacity(0.3), radius: 1.5, y: 1)
                    .rotationEffect(.degrees(Double(index) * -9), anchor: .bottom)
                    .offset(x: CGFloat(index) * -4)
            }
        }
        .frame(width: 30, height: 32)
        .accessibilityHidden(true)
    }
}

private struct ScannerStatusView: View {
    @ObservedObject var state: CardScannerUIState

    var body: some View {
        Group {
            if let message = state.scanAssistance.message {
                ScanAssistanceView(message: message)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: state.scanAssistance)
    }
}

private struct ScannerSlabPromptView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject var state: CardScannerUIState
    let switchToRaw: () -> Void

    var body: some View {
        Group {
            if let prompt = state.slabLabelReadPrompt {
                SlabLabelReadingOfferView(prompt: prompt, onSwitchToRaw: switchToRaw)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.18), value: state.slabLabelReadPrompt)
    }
}

private struct ScannerCameraIssueOverlay: View {
    @ObservedObject var state: CardScannerUIState
    @Environment(\.openURL) private var openURL

    var body: some View {
        Group {
            if let issue = state.cameraIssue {
                VStack(spacing: 14) {
                    ViewThatFits(in: .vertical) {
                        message(issue)
                        ScrollView { message(issue) }
                            .scrollBounceBehavior(.basedOnSize)
                    }
                    if issue == .permissionDenied {
                        Button {
                            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                            openURL(url)
                        } label: {
                            Text("Open Settings")
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .layoutPriority(1)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 22)
                .frame(maxWidth: 340)
                .appGlass(cornerRadius: 28)
                .padding(30)
            }
        }
    }

    private func message(_ issue: CameraIssue) -> some View {
        VStack(spacing: 14) {
            ScannerStatusBadge(tone: .neutral, systemName: "camera.fill", size: 56)
            Text(issue.message)
                .font(.callout.weight(.medium))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct ScannerTopBar: View, Equatable {
    let purpose: ScanPurpose
    let subjectMode: ScanSubjectMode
    let lens: CameraLens
    let availableLenses: [CameraLens]
    let finishLocks: [CardGame: VariantLock]
    let variantLockMenu: [GameVariantLockOptions]
    let isSlowIdentifying: Bool
    let setPurpose: (ScanPurpose) -> Void
    let setSubjectMode: (ScanSubjectMode) -> Void
    let setLens: (CameraLens) -> Void
    let setFinishLock: (VariantLock?, CardGame) -> Void
    let clearFinishLocks: () -> Void
    let openSettings: () -> Void
    /// Observed only inside the options panel, so torch changes never
    /// re-evaluate the bar. Not part of equality: the object is stable for the
    /// session.
    let scannerState: CardScannerUIState
    let setScanLight: (Bool, Float) -> Void
    let setScanLightLevel: (Float) -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Namespace private var glassNamespace
    @State private var isShowingOptions = false
    /// Full Settings is a sheet, so it waits until the popover has gone.
    @State private var opensSettingsAfterOptions = false

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.purpose == rhs.purpose
            && lhs.subjectMode == rhs.subjectMode
            && lhs.lens == rhs.lens
            && lhs.availableLenses == rhs.availableLenses
            && lhs.finishLocks == rhs.finishLocks
            && lhs.variantLockMenu == rhs.variantLockMenu
            && lhs.isSlowIdentifying == rhs.isSlowIdentifying
    }

    var body: some View {
        topBarCluster
#if DEBUG && targetEnvironment(simulator)
            .task {
                guard ProcessInfo.processInfo.arguments.contains("scan-options-open") else { return }
                try? await Task.sleep(for: .seconds(1))
                isShowingOptions = true
            }
#endif
    }

    @ViewBuilder
    private var topBarCluster: some View {
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: 8) {
                topBar
            }
        } else {
            topBar
        }
    }

    /// The mode you are in, not the modes you could be in.
    ///
    /// A segmented control spends half its width showing the option you did not
    /// pick, and on a camera screen the useful fact is which mode is live — the
    /// consequence of `collection` is silent and accumulating, so it has to be
    /// readable at a glance without dominating the viewfinder. The alternatives,
    /// and what each one does, live one tap away in the menu, which is where they
    /// are needed: at the moment of deciding.
    private func purposeControl(compact: Bool = false) -> some View {
        Menu {
            ForEach(ScanPurpose.allCases) { purpose in
                Button {
                    setPurpose(purpose)
                } label: {
                    Text(purpose.title)
                    Text(purpose.statusText)
                    if self.purpose == purpose {
                        Image(systemName: "checkmark")
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: purpose.symbolName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(purposeTint)
                Text(compact ? "Trade" : purpose.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: true)
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .frame(minHeight: 44)
            .appPillGlass(interactive: true)
            .appGlassEffectID("scanner-purpose", in: glassNamespace)
            .appGlassEffectUnion("scanner-top-controls", in: glassNamespace)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityLabel("Scan mode: \(purpose.title)")
        .accessibilityHint("Choose Collection, Price Check, or Trade Analyzer.")
    }

    private var purposeTint: Color {
        switch purpose {
        case .collection: .green
        case .priceCheck: .yellow
        case .tradeAnalyzer: .mint
        }
    }

    /// Almost nothing. There is no game picker because the printed identifier
    /// already says which game the card is, and asking the user to pre-declare it
    /// was asking for information the card carries.
    private func finishLockControl(wrapsSummary: Bool, compact: Bool = false) -> some View {
        FinishLockControl(
            subjectMode: subjectMode,
            locks: finishLocks,
            variantLockMenu: variantLockMenu,
            wrapsSummary: wrapsSummary,
            compact: compact,
            setSubjectMode: setSubjectMode,
            setLock: setFinishLock,
            clearLocks: clearFinishLocks,
            glassNamespace: glassNamespace
        )
        .equatable()
    }

    private var topBar: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize && purpose != .tradeAnalyzer {
                stackedTopBar
            } else {
                ViewThatFits(in: .horizontal) {
                    inlineTopBar()
                    if purpose == .tradeAnalyzer {
                        inlineTopBar(compactFinish: true)
                    }
                    stackedTopBar
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: isSlowIdentifying)
    }

    private func inlineTopBar(compactFinish: Bool = false) -> some View {
        HStack(spacing: compactFinish ? 6 : 8) {
            purposeControl(compact: compactFinish && dynamicTypeSize.isAccessibilitySize)
                .fixedSize(horizontal: true, vertical: false)
            finishLockControl(wrapsSummary: false, compact: compactFinish)
                .fixedSize(horizontal: true, vertical: false)
            identificationSpinner
            Spacer(minLength: 0)
            optionsButton
        }
    }

    private var stackedTopBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                purposeControl()
                Spacer(minLength: 0)
                optionsButton
            }
            HStack(spacing: 8) {
                finishLockControl(wrapsSummary: true)
                identificationSpinner
            }
        }
    }

    @ViewBuilder
    private var identificationSpinner: some View {
        if isSlowIdentifying {
            ProgressView()
                .tint(.white)
                .controlSize(.small)
                .transition(.opacity)
                .accessibilityLabel("Identifying card")
        }
    }

    /// One button for everything about the camera itself. The panel holds the
    /// light and lens and links to full Settings.
    private var optionsButton: some View {
        Group {
            if purpose == .tradeAnalyzer {
                Button { isShowingOptions = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .appPillGlass(interactive: true)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            } else if #available(iOS 26.0, *) {
                Button { isShowingOptions = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.glass)
            } else {
                Button { isShowingOptions = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.black.opacity(0.55), in: Circle())
                        .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .appGlassEffectID("scanner-settings", in: glassNamespace)
        .accessibilityLabel("Scan options")
        .accessibilityIdentifier("scanner-settings")
        .popover(isPresented: $isShowingOptions, arrowEdge: .top) {
            ScanOptionsPanel(
                scannerState: scannerState,
                lens: lens,
                availableLenses: availableLenses,
                setScanLight: setScanLight,
                setScanLightLevel: setScanLightLevel,
                setLens: setLens,
                openAllSettings: {
                    opensSettingsAfterOptions = true
                    isShowingOptions = false
                }
            )
            .presentationCompactAdaptation(.popover)
            .onDisappear {
                guard opensSettingsAfterOptions else { return }
                opensSettingsAfterOptions = false
                openSettings()
            }
        }
    }
}

/// The scan settings that change what the camera does right now. Opening this
/// panel does not pause scanning, so the user can watch the card while choosing
/// a brightness or a lens. Everything else is in full Settings.
private struct ScanOptionsPanel: View {
    @ObservedObject var scannerState: CardScannerUIState
    let lens: CameraLens
    let availableLenses: [CameraLens]
    let setScanLight: (Bool, Float) -> Void
    let setScanLightLevel: (Float) -> Void
    let setLens: (CameraLens) -> Void
    let openAllSettings: () -> Void

    @AppStorage(ScanLightLevel.storageKey) private var level = Double(ScanLightLevel.defaultLevel)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if scannerState.scanLight != .unsupported {
                    lightSection
                }
                if availableLenses.count > 1 {
                    section("Camera") {
                        Picker("Camera", selection: Binding(get: { lens }, set: setLens)) {
                            ForEach(availableLenses.reversed()) { option in
                                Text(option == .macro ? "Macro" : "Standard").tag(option)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("scan-options-camera")
                    }
                }
                Divider()
                Button(action: openAllSettings) {
                    HStack {
                        Label("All Settings", systemImage: "gearshape")
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("scan-options-all-settings")
            }
            .padding(16)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(idealWidth: 320, maxWidth: 340)
        .accessibilityIdentifier("scan-options-panel")
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private var isLightOn: Bool { scannerState.scanLight == .on }

    private var lightSection: some View {
        section("Light") {
            Toggle(isOn: Binding(
                get: { isLightOn },
                set: { setScanLight($0, Float(level)) }
            )) {
                Label("Scan light", systemImage: isLightOn ? "flashlight.on.fill" : "flashlight.off.fill")
            }
            .disabled(scannerState.scanLight == .unavailable)
            .frame(minHeight: 44)
            .accessibilityIdentifier("scan-light-toggle")

            if scannerState.scanLight == .unavailable {
                Text("The light is unavailable right now, often because the phone is warm.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if isLightOn {
                HStack(spacing: 10) {
                    Image(systemName: "sun.min.fill")
                        .accessibilityHidden(true)
                    Slider(
                        value: $level,
                        in: Double(ScanLightLevel.range.lowerBound)...Double(ScanLightLevel.range.upperBound)
                    )
                    .accessibilityLabel("Scan light brightness")
                    .accessibilityValue(level.formatted(.percent.precision(.fractionLength(0))))
                    .accessibilityIdentifier("scan-light-brightness")
                    Image(systemName: "sun.max.fill")
                        .accessibilityHidden(true)
                }
                .foregroundStyle(.secondary)
                .onChange(of: level) { _, newLevel in
                    setScanLightLevel(Float(newLevel))
                }
            }
        }
        .animation(.easeOut(duration: 0.2), value: scannerState.scanLight)
    }
}

private struct FinishLockControl: View, Equatable {
    let subjectMode: ScanSubjectMode
    let locks: [CardGame: VariantLock]
    let variantLockMenu: [GameVariantLockOptions]
    let wrapsSummary: Bool
    let compact: Bool
    let setSubjectMode: (ScanSubjectMode) -> Void
    let setLock: (VariantLock?, CardGame) -> Void
    let clearLocks: () -> Void
    let glassNamespace: Namespace.ID
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.subjectMode == rhs.subjectMode && lhs.locks == rhs.locks
            && lhs.variantLockMenu == rhs.variantLockMenu
            && lhs.wrapsSummary == rhs.wrapsSummary && lhs.compact == rhs.compact
    }

    private var activeLocks: [(game: CardGame, displayName: String, lock: VariantLock)] {
        variantLockMenu.compactMap { entry in
            locks[entry.game].map { (game: entry.game, displayName: entry.displayName, lock: $0) }
        }
    }

    private var summary: String {
        return activeLocks.isEmpty
            ? "Auto"
            : activeLocks.map { "\($0.displayName) \($0.lock.label)" }.joined(separator: " · ")
    }

    private var visibleSummary: String {
        guard dynamicTypeSize.isAccessibilitySize, !activeLocks.isEmpty else { return summary }
        if activeLocks.count == 1, let lock = activeLocks.first?.lock { return lock.label }
        return String(localized: "\(activeLocks.count) locks")
    }

    var body: some View {
        Menu {
            Section("Scanning") {
                Picker("Card type", selection: Binding(
                    get: { subjectMode },
                    set: setSubjectMode
                )) {
                    ForEach(ScanSubjectMode.allCases) { mode in
                        Label(mode.title, systemImage: mode.symbolName)
                            .tag(mode)
                    }
                }
                .pickerStyle(.inline)
            }

            Divider()

            if subjectMode == .slab {
                Text("Finish locks apply to raw cards")
                    .font(.caption)
            }

            Button(action: clearLocks) {
                Text("Auto")
                if locks.isEmpty {
                    Image(systemName: "checkmark")
                }
            }
            .disabled(subjectMode == .slab)

            ForEach(variantLockMenu) { entry in
                let game = entry.game
                Menu {
                    Picker(
                        entry.displayName,
                        selection: Binding<VariantLock?>(
                            get: { locks[game] },
                            set: { setLock($0, game) }
                        )
                    ) {
                        Text("Auto")
                            .tag(VariantLock?.none)
                        ForEach(entry.options) { lock in
                            Text(lock.label)
                                .tag(VariantLock?.some(lock))
                        }
                    }
                } label: {
                    Text(locks[game].map { "\(entry.displayName)  \($0.label)" } ?? entry.displayName)
                }
                .disabled(subjectMode == .slab)
            }
        } label: {
            Group {
                if subjectMode == .slab {
                    HStack(spacing: 6) {
                        Image(systemName: "rectangle.stack")
                            .font(.system(size: 13, weight: .semibold))
                        if !compact {
                            Text("Slabs")
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .appPillGlass(tint: .cyan, interactive: true)
                } else {
                    HStack(spacing: 6) {
                        Image(systemName: locks.isEmpty ? "lock.open" : "lock.fill")
                            .font(.system(size: 13, weight: .semibold))
                        if !compact {
                            Text(visibleSummary)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(wrapsSummary ? nil : 1)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .appPillGlass(tint: locks.isEmpty ? nil : .red, interactive: true)
                }
            }
            .appGlassEffectID("scanner-finish-lock", in: glassNamespace)
            .appGlassEffectUnion("scanner-top-controls", in: glassNamespace)
            .animation(.easeOut(duration: 0.2), value: locks)
            .animation(.easeOut(duration: 0.2), value: subjectMode)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .accessibilityIdentifier("scanner-options")
        .accessibilityLabel(subjectMode == .slab
            ? "Scanning mode: graded slabs"
            : "Raw cards. Finish lock: \(summary)")
        .accessibilityHint(subjectMode == .slab
            ? "Finish locks apply to raw cards."
            : "A finish lock applies only where the catalog agrees the finish is physically possible, so it can never record a variant that was never printed.")
    }
}

private struct UnresolvedScansSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var model: ScannerViewModel
    let browseCatalog: BrowseCatalog
    private var scans: [UnresolvedScan] { model.unresolvedScans }
    let onClear: () -> Void
    let onDismiss: (UUID) -> Void
    let onResolve: (UUID, UnresolvedResolutionChoice) -> Void

    private var instructions: String {
        if model.hasUnresolvedWritesInFlight {
            return "A card is being saved. You can review other cards while it finishes."
        }
        if scans.contains(where: { $0.reason == .noConfirmedMatch }) {
            return "Nothing in this list was added to your collection. Use the details below to reposition and scan again."
        }
        if scans.isEmpty {
            return "Nothing in this list was added to your collection."
        }
        return "Nothing here was added. Check that the number shown matches the card. Newly released cards can take a while to reach the catalog."
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text(instructions)
                        .foregroundStyle(.secondary)
                }

                Section("Needs attention") {
                    ForEach(scans) { scan in
                        NavigationLink {
                            UnresolvedScanDetailView(
                                model: model,
                                browseCatalog: browseCatalog,
                                scan: scan,
                                onDismissRow: { onDismiss(scan.id) },
                                onResolve: { onResolve(scan.id, $0) }
                            )
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(scan.displayIdentifier)
                                    .font(.headline.monospacedDigit())
                                if !scan.requestEvidence.titleReadings.isEmpty {
                                    Text("Title readings: \(scan.requestEvidence.titleReadings.joined(separator: ", "))")
                                        .font(.subheadline)
                                        .lineLimit(2)
                                }
                                Text(scan.reason.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if model.isUnresolvedWriteInFlight(id: scan.id) {
                                    ProgressView("Saving…")
                                        .font(.caption)
                                }
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .swipeActions(edge: .trailing) {
                            Button("Dismiss", systemImage: "xmark", role: .destructive) {
                                onDismiss(scan.id)
                            }
                            .disabled(model.isUnresolvedWriteInFlight(id: scan.id))
                        }
                    }
                }
            }
            .navigationTitle("Unresolved Scans")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !scans.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear", role: .destructive) {
                            onClear()
                            dismiss()
                        }
                        .disabled(model.hasUnresolvedWritesInFlight)
                    }
                }
            }
        }
    }
}
