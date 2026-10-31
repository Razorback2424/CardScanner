import PhotosUI
import Charts
import CoreImage
import ImageIO
import SwiftData
import SwiftUI
import UIKit

/// A quantity read or saved by this detail belongs to the exact ownership
/// inputs it observed. A newer projection immediately makes that cache stale.
struct CollectionDetailQuantityState {
    struct Input: Hashable {
        let collectionKey: String
        let physicalQuantity: Int
        let logicalQuantity: Int?
        let isLogicalConflict: Bool
        let treatments: [String]

        var displayedQuantity: Int {
            // A sibling-context save can merge the physical rows before the
            // collection projection publishes its new total.
            isLogicalConflict ? max(logicalQuantity ?? physicalQuantity, physicalQuantity) : physicalQuantity
        }
    }

    private var input: Input?
    private var quantity: Int?
    private(set) var revision: UInt = 0

    func savedQuantity(for input: Input) -> Int? {
        self.input == input ? quantity : nil
    }

    func displayedQuantity(for input: Input) -> Int {
        savedQuantity(for: input) ?? input.displayedQuantity
    }

    /// An absolute target belongs to the count visible when the user acted,
    /// including when the first authoritative read has not completed yet.
    func expectedQuantity(for input: Input) -> Int {
        displayedQuantity(for: input)
    }

    static func validateIntent(observed: Int, refreshed: Int) throws {
        guard observed == refreshed else { throw CollectionStoreError.staleQuantity }
    }

    @discardableResult
    mutating func update(
        _ quantity: Int?,
        for input: Input,
        expectedRevision: UInt? = nil
    ) -> Bool {
        if let expectedRevision, revision != expectedRevision { return false }
        self.input = input
        self.quantity = quantity
        revision &+= 1
        return true
    }
}

private struct CardDetailFact: Identifiable {
    let id: Int
    let label: String
    let value: String
}

private struct MarketHistoryLoadID: Hashable {
    let request: CardMarketHistoryRequest
    let retry: Int
}

private struct GradedFinishLoadID: Hashable {
    let summary: CatalogCardSummary?
    let retry: Int
}

struct CardDetailMovementDisplay: Equatable {
    enum Direction: Equatable {
        case positive
        case negative
        case flat
    }

    enum Status: Equatable {
        case recording
        case none
        case recorded
    }

    let status: Status
    let direction: Direction
    let amount: Money?
    let percentage: Double?
    let periodText: String
}

struct CollectionCardDetailView: View {
    @Bindable var card: CollectedCard
    let price: PriceDisplay
    @ObservedObject var history: PortfolioHistoryStore
    let unpricedReason: PricingDiagnosticReason?
    let artworkReason: ArtworkDiagnosticReason?
    var logicalQuantity: Int? = nil
    var isLogicalConflict = false
    var instrumentKey: String? = nil
    let onRemoved: (RemovedCardSnapshot) -> Void

    var body: some View {
        CollectionDetailArtworkSource(collectionKey: card.collectionKey, legacyFilename: card.userArtworkFilename) { filename in
            CollectionCardDetailContent(card: card, price: price, history: history,
                unpricedReason: unpricedReason, artworkReason: artworkReason,
                logicalQuantity: logicalQuantity, isLogicalConflict: isLogicalConflict,
                instrumentKey: instrumentKey, localArtworkFilename: filename, onRemoved: onRemoved)
        }
    }

    static func gradedAcquisitionDescriptor(for key: String) -> FetchDescriptor<CollectionActivity> {
        CollectionCardDetailContent.gradedAcquisitionDescriptor(for: key)
    }

    static func gradedVariantEvidence(for card: CollectedCard) -> VariantEvidence {
        CollectionCardDetailContent.gradedVariantEvidence(for: card)
    }

    static func gradedVariantOptions(for card: CollectedCard) -> [PhysicalVariant] {
        CollectionCardDetailContent.gradedVariantOptions(for: card)
    }

    static func gradedVariantCorrectionOptions(for card: CollectedCard, catalogCard: IdentifiedCard? = nil) -> [PhysicalVariant] {
        CollectionCardDetailContent.gradedVariantCorrectionOptions(for: card, catalogCard: catalogCard)
    }
}

/// The query is recreated from the live key, including a rekey of an already
/// presented card. Its one observed result feeds every detail artwork consumer.
struct CollectionDetailArtworkSource<Content: View>: View {
    @Query private var overrides: [LocalArtworkOverride]
    let legacyFilename: String?
    let content: (String?) -> Content

    init(collectionKey: String, legacyFilename: String?, @ViewBuilder content: @escaping (String?) -> Content) {
        var descriptor = FetchDescriptor<LocalArtworkOverride>(
            predicate: #Predicate { $0.collectionKey == collectionKey },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        descriptor.fetchLimit = 1
        _overrides = Query(descriptor)
        self.legacyFilename = legacyFilename
        self.content = content
    }

    var body: some View {
        content(Self.effectiveFilename(override: overrides.first?.filename, legacy: legacyFilename))
    }

    static func effectiveFilename(override: String?, legacy: String?) -> String? {
        if let override { return override.isEmpty ? nil : override }
        return legacy?.isEmpty == false ? legacy : nil
    }
}

private struct CollectionCardDetailContent: View {
    @Environment(\.cardGameRuntimes) private var runtimes
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .largeTitle) private var titleFontSize: CGFloat = 32
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.cardFinishMotionSource) private var cardFinishMotion
    @Bindable var card: CollectedCard
    @Query private var collectionActivities: [CollectionActivity]
    @Query private var ungradedReferenceRecords: [PriceRecord]
    let price: PriceDisplay
    @ObservedObject var history: PortfolioHistoryStore
    let unpricedReason: PricingDiagnosticReason?
    let artworkReason: ArtworkDiagnosticReason?
    let onRemoved: (RemovedCardSnapshot) -> Void
    /// When a route was opened from a logical projection, this is the quantity
    /// users should see rather than the representative physical row's quantity.
    let logicalQuantity: Int?
    /// Duplicate synced rows cannot be edited safely through a single-row API.
    let isLogicalConflict: Bool
    private let priceHistoryInstrumentKey: String
    let localArtworkFilename: String?

    @State private var isConfirmingRemoval = false
    @State private var dispositionTarget: CollectionDispositionTarget?
    @State private var isChoosingArtwork = false
    @State private var selectedArtwork: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var artworkGeneration = 0
    @State private var pendingArtwork: ArtworkRequest?
    @State private var artworkAccent: ArtworkAccent?
    @State private var quantityState = CollectionDetailQuantityState()
    @State private var isOwnershipWritePending = false
    @State private var isSharing = false
    @State private var selectedPriceDate: Date?
    @State private var marketHistory: [JustTCGHistoryPoint] = []
    @State private var marketHistoryError: String?
    @State private var isLoadingMarketHistory = true
    @State private var marketHistoryIdentity: [String]?
    @State private var marketHistoryRetry = 0
    @State private var gradedCatalogCard: IdentifiedCard?
    @State private var isLoadingGradedFinishes = false
    @State private var gradedFinishLoadFailed = false
    @State private var gradedFinishRetry = 0
#if DEBUG
    @State private var isShowingPrintingDetailsRoute = false
#endif

    private struct ArtworkRequest: Identifiable {
        let id: Int
        let item: PhotosPickerItem
    }

    init(
        card: CollectedCard,
        price: PriceDisplay,
        history: PortfolioHistoryStore,
        unpricedReason: PricingDiagnosticReason?,
        artworkReason: ArtworkDiagnosticReason?,
        logicalQuantity: Int? = nil,
        isLogicalConflict: Bool = false,
        instrumentKey: String? = nil,
        localArtworkFilename: String?,
        onRemoved: @escaping (RemovedCardSnapshot) -> Void
    ) {
        let resolvedInstrumentKey = instrumentKey ?? card.priceKey
        self._card = Bindable(card)
        let rawPrintingID = card.catalogProviderID ?? card.providerID
        let printRunQualifiedID = card.pokemonPrintRun.map {
            "\(rawPrintingID)@\($0.rawValue)"
        } ?? rawPrintingID
        let isUsableRawPrintingID = card.itemKind == .gradedCard
            && !rawPrintingID.hasPrefix("graded:")
        if isUsableRawPrintingID {
            let gameRaw = card.game
            let rawVariantID = card.variantID
            self._ungradedReferenceRecords = Query(
                filter: #Predicate<PriceRecord> {
                    $0.game == gameRaw
                        && $0.printingID == printRunQualifiedID
                        && $0.variantID == rawVariantID
                },
                sort: [SortDescriptor(\PriceRecord.key, order: .forward)]
            )
        } else {
            var descriptor = FetchDescriptor<PriceRecord>(
                predicate: #Predicate<PriceRecord> { $0.key == "__ungraded_reference_disabled__" }
            )
            descriptor.fetchLimit = 1
            self._ungradedReferenceRecords = Query(descriptor)
        }
        let resolvedCollectionKey = card.collectionKey
        if card.itemKind == .gradedCard {
            self._collectionActivities = Query(Self.gradedAcquisitionDescriptor(for: resolvedCollectionKey))
        } else {
            // Raw and sealed rows never read acquisition history. Keep their
            // query empty so unrelated activity writes cannot re-fetch a full
            // history just to evaluate an unused graded-only block.
            var descriptor = FetchDescriptor<CollectionActivity>(
                predicate: #Predicate<CollectionActivity> {
                    $0.itemKindRaw == "__graded_detail_query_disabled__"
                }
            )
            descriptor.fetchLimit = 1
            self._collectionActivities = Query(descriptor)
        }
        self.price = price
        self.history = history
        self.unpricedReason = unpricedReason
        self.artworkReason = artworkReason
        self.logicalQuantity = logicalQuantity
        self.isLogicalConflict = isLogicalConflict
        self.priceHistoryInstrumentKey = resolvedInstrumentKey
        self.localArtworkFilename = localArtworkFilename
        self.onRemoved = onRemoved
    }

    var body: some View {
        let chartModel = makePriceHistoryModel()
        let movement = movementDisplay(for: chartModel)

        return ZStack {
            AppCardDetailBackdrop()
                .ignoresSafeArea()

            ScrollViewReader { scrollProxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 0) {
                        heroSection
                        cardIdentitySection
                        if card.cardGame == .yuGiOh {
                            YuGiOhPricingNotice()
                                .font(.footnote).foregroundStyle(.secondary).padding()
                        }
                        valuationSection(model: chartModel)
                            .id("card-price-valuation")
                        priceHistorySection(model: chartModel, movement: movement)
                        marketplaceSection
                        ownershipSection
                            .id("card-ownership")

                        if isLogicalConflict {
                            conflictNotice
                                .padding(.horizontal, 16)
                                .padding(.top, 20)
                        }
                    }
                    .padding(.bottom, 24)
                }
                .coordinateSpace(name: "CardDetailScroll")
#if DEBUG
                .task {
                    let arguments = ProcessInfo.processInfo.arguments
                    if let index = arguments.firstIndex(of: "-ui_debug_state"),
                       arguments.indices.contains(index + 1),
                       arguments[index + 1].hasPrefix("price-chart") || arguments[index + 1] == "ownership" {
                        try? await Task.sleep(for: .milliseconds(300))
                        scrollProxy.scrollTo(arguments[index + 1] == "ownership" ? "card-ownership" : "card-price-valuation", anchor: .top)
                    }
                }
#endif
            }
        }
        .environment(\.colorScheme, .dark)
        .task(id: MarketHistoryLoadID(request: marketHistoryRequest, retry: marketHistoryRetry)) {
            await loadMarketHistory()
        }
        .task(id: GradedFinishLoadID(summary: gradedFinishSummary, retry: gradedFinishRetry)) {
            await loadGradedFinishes()
        }
        .task(id: runtimes?.runtime(for: card.cardGame)?.catalog?.generation) {
            guard marketHistoryRequest.requiresCatalogMapping else { return }
            let source = runtimes?.runtime(for: card.cardGame)?.activationSource
            let events = await source?.activationSnapshots()
            // Subscribe before the authoritative reload, closing a missed-event
            // window between the first load and installing this observer.
            marketHistoryRetry += 1
            guard let events else { return }
            for await _ in events {
                guard !Task.isCancelled else { return }
                marketHistory = []
                isLoadingMarketHistory = true
                marketHistoryRetry += 1
            }
        }
        .onChange(of: history.range) { _, _ in selectedPriceDate = nil }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        // Artwork actions belong in the navigation chrome so they never cover
        // printed card content in the full-bleed hero.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack {
                    if isOwnershipWritePending {
                        ProgressView().tint(.white).accessibilityLabel("Saving collection change")
                    }
                    shareButton
                    artworkMenu
                }
            }
        }
        // The detail destination is a focused surface. Leaving the collection
        // tab bar visible puts it over the identity block at the hero's resting
        // height, clipping the card name before the user can scroll.
        .toolbar(.hidden, for: .tabBar)
        // Keep the presentation host alive after the toolbar menu dismisses.
        .photosPicker(isPresented: $isChoosingArtwork, selection: $selectedArtwork, matching: .images)
        .sheet(isPresented: $isSharing) { shareSheet }
        .onChange(of: selectedArtwork) { _, item in
            guard let item else { return }
            artworkGeneration &+= 1
            pendingArtwork = ArtworkRequest(id: artworkGeneration, item: item)
        }
#if DEBUG
        // Capture-only hook for the deterministic details route. Normal
        // launches do not pass this argument, so the destination remains a
        // normal user-driven navigation row.
        .onAppear {
            if CommandLine.arguments.contains("-ui_card_details_route") {
                isShowingPrintingDetailsRoute = true
            }
            if let index = CommandLine.arguments.firstIndex(of: "-ui_debug_state"),
               CommandLine.arguments.indices.contains(index + 1),
               ["record-sale", "record-trade"].contains(CommandLine.arguments[index + 1]) {
                presentDisposition(kind: CommandLine.arguments[index + 1] == "record-trade" ? .traded : .sold)
            }
        }
        .navigationDestination(isPresented: $isShowingPrintingDetailsRoute) {
            printingDetailsDestination
        }
#endif
        .task(id: artworkSourceKey) {
            let localFilename = localArtworkFilename
            let remoteURL = card.highImageURL ?? card.lowImageURL
            artworkAccent = await ArtworkAccentStore.accent(
                localFilename: localFilename,
                remoteURL: remoteURL
            )
        }
        .task(id: card.catalogProviderID ?? card.providerID) {
            await loadMarketplaceLinkIfNeeded()
        }
        .task(id: quantityInput) {
            await refreshDisplayedQuantity(for: quantityInput)
        }
        .task(id: pendingArtwork?.id) {
            guard let request = pendingArtwork else { return }
            await saveSelectedArtwork(
                request.item,
                requestID: request.id,
                collectionKey: card.collectionKey
            )
            if pendingArtwork?.id == request.id {
                pendingArtwork = nil
            }
        }
        .onDisappear {
            // `.task` is cancelled automatically when this view disappears;
            // advancing the generation also makes a completion that is already
            // returning from PhotosUI unable to commit after dismissal.
            artworkGeneration &+= 1
            pendingArtwork = nil
        }
        .alert("Collection Change Couldn’t Be Saved", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Please try again.")
        }
        .sheet(item: $dispositionTarget) { target in
            CollectionDispositionSheet(target: target) { snapshot in
                let remaining = target.quantity - snapshot.quantity
                quantityState.update(remaining, for: quantityInput)
                if remaining == 0 {
                    onRemoved(snapshot)
                    dismiss()
                }
            }
        }
        .confirmationDialog(
            "Remove \(card.name)?",
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                removeCard()
            }
            .disabled(isOwnershipWritePending)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removalMessage)
        }
    }

    private var shareButton: some View {
        Button {
            isSharing = true
        } label: {
            Image(systemName: "square.and.arrow.up")
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Share card")
        .accessibilityHint("Shares an image of this card, with or without its price.")
    }

    private var shareSheet: some View {
        let source = CatalogCardArtworkSource(collectedCard: card, prefersFullSize: true)
        return CollectionShareSheet(
            identity: CardShareIdentity(collectedCard: card),
            price: CardSharePrice(collectedCard: card, display: price),
            showsFinishSheen: showsShareFinishSheen,
            localArtworkFilename: localArtworkFilename,
            remoteArtworkURLs: [source.primaryURL].compactMap { $0 } + source.fallbacks
        )
    }

    /// The same finishes the detail hero animates; a still pose stands in for
    /// the live sheen in the shared image.
    private var showsShareFinishSheen: Bool {
        guard card.itemKind == .rawCard,
              let variant = card.variant,
              let resolution = card.variantResolution,
              resolution != .catalogSilent,
              resolution != .imported else { return false }
        return [PhysicalVariant.holo.id, PhysicalVariant.reverse.id, PhysicalVariant.foil.id].contains(variant.id)
    }

    @ViewBuilder
    private var artworkMenu: some View {
        Menu {
            NavigationLink {
                CollectionCardHistoryView(
                    collectionKey: card.collectionKey,
                    cardName: card.name
                )
            } label: {
                Label("Collection History", systemImage: "clock.arrow.circlepath")
            }

            Divider()

            Button {
                isChoosingArtwork = true
            } label: {
                Label(
                    localArtworkFilename == nil ? "Choose Photo" : "Replace Photo",
                    systemImage: "photo.badge.plus"
                )
            }

            if localArtworkFilename != nil {
                Button("Use Catalog Artwork", role: .destructive) {
                    removeUserArtwork()
                }
            }

            Divider()

            Button("Remove from Collection", role: .destructive) {
                isConfirmingRemoval = true
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Card actions")
        .accessibilityHint("Open collection history, manage artwork, or remove this card.")
        .disabled(isOwnershipWritePending)
    }

    /// The printed card's corner. Shared with `CardFinishOverlay` so the sheen
    /// is masked to exactly the shape the artwork is clipped to.
    fileprivate static let cardCornerRadius: CGFloat = 20

    private var heroSection: some View {
        let movementEnabled = !reduceMotion
        return ZStack {
            if let accent = artworkAccent, !reduceTransparency {
                RadialGradient(
                    colors: [
                        accent.color.opacity(0.38),
                        accent.color.opacity(0.10),
                        .clear
                    ],
                    center: .center,
                    startRadius: 12,
                    endRadius: 220
                )
                .frame(width: 370, height: 470)
                .blur(radius: 26)
                .allowsHitTesting(false)
            }

            artwork
                .frame(maxWidth: 315)
                .clipShape(
                    RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                )
                .overlay {
                    // A printed card has an edge. Bleeding the artwork to the
                    // screen edge with square corners would read as wallpaper.
                    RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
                }
                .shadow(color: .black.opacity(0.55), radius: 24, x: 0, y: 14)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
            .scrollTransition(.interactive, axis: .vertical) { content, phase in
                content
                    .scaleEffect(!movementEnabled || phase.isIdentity ? 1 : 0.96)
                    .opacity(!movementEnabled || phase.isIdentity ? 1 : 0.94)
            }
            .visualEffect { content, proxy in
                let minY = proxy.frame(in: .named("CardDetailScroll")).minY
                let parallax = movementEnabled ? min(18, max(-18, minY * 0.045)) : 0
                return content.offset(y: parallax)
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Artwork for \(card.name)")
    }

    private var cardIdentitySection: some View {
        VStack(spacing: 6) {
            Text(card.name)
                .font(.system(size: titleFontSize, weight: .bold))
                .tracking(dynamicTypeSize <= .large ? -0.6 : 0)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !provenanceLine.isEmpty {
                if !card.setName.isEmpty {
                    NavigationLink {
                        setDestination
                    } label: {
                        Text(provenanceLine)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(minHeight: 44)
                            .contentShape(Rectangle())
                    }
                    .font(.subheadline)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHint("View this set")
                    .accessibilityIdentifier("collection-set-link")
                } else {
                    Text(provenanceLine)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }

            identityStatusRow

            if card.itemKind == .gradedCard {
                gradedVariantCorrectionBlock
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 18)
        .padding(.horizontal, 16)
        .padding(.bottom, 22)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var identityStatusRow: some View {
        switch card.itemKind {
        case .sealedProduct:
            identityStatusLine(
                label: card.itemKindLabel,
                dotStyle: nil,
                tint: .secondary,
                rarity: CardRarityToken(raw: card.rarity)
            )
        case .gradedCard:
            identityStatusLine(
                label: conditionLine ?? card.itemKindLabel,
                dotStyle: .flat(.finishGraded),
                tint: .finishGraded,
                rarity: CardRarityToken(raw: card.rarity)
            )
        case .rawCard:
            if let label = detailFinishLabel,
               let status = rawFinishStatus {
                identityStatusLine(
                    label: label,
                    dotStyle: status.style,
                    tint: status.tint,
                    rarity: CardRarityToken(raw: card.rarity)
                )
            } else if let rarity = CardRarityToken(raw: card.rarity) {
                identityStatusLine(
                    label: rarity.label,
                    dotStyle: nil,
                    tint: rarity.tint,
                    rarity: nil
                )
            }
        }
    }

    private func identityStatusLine(
        label: String,
        dotStyle: CollectionFinishDot.Style?,
        tint: Color,
        rarity: CardRarityToken?
    ) -> some View {
        HStack(spacing: 8) {
            if let dotStyle {
                CollectionFinishDot(style: dotStyle, size: 9)
            }

            Text(label)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)

            if let rarity {
                Text("·")
                    .foregroundStyle(.tertiary)
                Text(rarity.label)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(rarity.tint)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var rawFinishStatus: (style: CollectionFinishDot.Style, tint: Color)? {
        if !card.displayedMagicTreatmentEvidence.treatments.isEmpty {
            return (.treatment, .finishTreatment)
        }

        guard let variant = card.variant else { return nil }
        switch variant.id {
        case PhysicalVariant.reverse.id:
            return (.reverse, .finishReverse)
        case PhysicalVariant.foil.id,
             PhysicalVariant.holo.id,
             PhysicalVariant.etched.id:
            return (.foil, .finishFoil)
        case PhysicalVariant.normal.id,
             PhysicalVariant.nonfoil.id:
            return (.plain, .secondary)
        default:
            return (.flat(finishTint(for: variant)), finishTint(for: variant))
        }
    }

    private func finishTint(for variant: PhysicalVariant) -> Color {
        switch variant.id {
        case PhysicalVariant.reverse.id:
            return .finishReverse
        case PhysicalVariant.foil.id,
             PhysicalVariant.holo.id,
             PhysicalVariant.etched.id:
            return .finishFoil
        case PhysicalVariant.pokeBall.id,
             PhysicalVariant.masterBall.id,
             PhysicalVariant.firstEdition.id:
            return .orange
        case PhysicalVariant.normal.id,
             PhysicalVariant.nonfoil.id:
            return .secondary
        default:
            return .secondary
        }
    }

    /// The collector's canonical short form: where this printing comes from.
    ///
    /// This is one fact, so it stays on one line and uses one type treatment.
    /// The rarity chip is adjacent because rarity belongs to the printing, not
    /// to the physical copy being held.
    private var provenanceLine: String {
        var parts: [String] = []
        if !card.setName.isEmpty {
            parts.append(card.setName)
        }

        let designation = [card.setCode, card.cardNumber]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if !designation.isEmpty {
            parts.append(designation)
        }

        if let printRun = card.pokemonPrintRun {
            parts.append(printRun.label)
        }
        return parts.joined(separator: " · ")
    }

    /// The most specific true description of this copy, once.
    ///
    /// A treatment whose finish is known subsumes that finish for this compact
    /// row; the details list still keeps both facts. An unclassified treatment
    /// has no such relationship, so it is shown beside the finish rather than
    /// guessed into one.
    private var conditionLine: String? {
        if let company = card.gradingCompany {
            // `CardGrade.display(company:)` already includes the company and
            // qualifier, so do not prepend or append either a second time.
            return card.cardGrade?.display(company: company)
                ?? [company.label, card.gradeRaw].compactMap { $0 }.joined(separator: " ")
        }

        if card.itemKind != .rawCard {
            return card.itemKindLabel
        }

        let treatments = card.displayedMagicTreatmentEvidence.treatments
        guard !treatments.isEmpty else {
            return card.variant?.label
        }

        let subsumesFinish = card.variant != nil && treatments.contains { treatment in
            guard treatment.requiredFinishes.count == 1 else { return false }
            return treatment.requiredFinishes.contains { $0.id == card.variant?.id }
        }
        let names = treatments.map(\.label)
        if subsumesFinish {
            return names.joined(separator: " · ")
        }
        return ([card.variant?.label].compactMap { $0 } + names)
            .joined(separator: " · ")
    }

    /// `conditionLine` is a compact status row for every item kind. Only its
    /// raw-card branch is a printed finish; a slab's condition is its grade and
    /// a sealed product has no finish to claim here.
    private var detailFinishLabel: String? {
        if card.itemKind == .rawCard {
            return conditionLine
        }
        return card.variant?.label
    }

    @ViewBuilder
    private var gradedVariantCorrectionBlock: some View {
        if let activity = latestGradedAcquisition {
            let options = gradedVariantCorrectionOptions
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Printed finish")
                            .font(.subheadline.weight(.semibold))
                        Text(card.variant?.label ?? "Not determined")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    if !options.isEmpty {
                        Menu {
                            ForEach(options) { option in
                                Button(option.label) {
                                    correctGradedVariant(option, activity: activity)
                                }
                            }
                        } label: {
                            Label("Fix finish", systemImage: "pencil")
                                .font(.subheadline.weight(.semibold))
                        }
                        .accessibilityLabel("Fix graded card finish")
                        .disabled(isOwnershipWritePending)
                    }
                }
                if !options.isEmpty {
                    Text("The slab stays the same card; this only corrects its printed finish.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if isLoadingGradedFinishes {
                    ProgressView("Loading finish choices…")
                        .font(.caption)
                } else if gradedFinishLoadFailed {
                    Button("Retry finish choices") { gradedFinishRetry += 1 }
                        .font(.subheadline)
                }
            }
            .padding(.vertical, 2)
        }
    }

    static func gradedAcquisitionDescriptor(for collectionKey: String) -> FetchDescriptor<CollectionActivity> {
        let gradedKind = CollectionItemKind.gradedCard.rawValue
        let addedKind = CollectionActivityKind.added.rawValue
        let restoredKind = CollectionActivityKind.restored.rawValue
        var descriptor = FetchDescriptor<CollectionActivity>(
            predicate: #Predicate<CollectionActivity> {
                $0.collectionKey == collectionKey
                    && $0.itemKindRaw == gradedKind
                    && ($0.kindRaw == addedKind || $0.kindRaw == restoredKind)
                    && ($0.deltaQuantity > $0.resolvedQuantity
                        || -$0.deltaQuantity > $0.resolvedQuantity
                        || ($0.deltaQuantity == 0 && $0.kindRaw == addedKind
                            && $0.quantity > $0.resolvedQuantity))
            },
            sortBy: [SortDescriptor(\CollectionActivity.occurredAt, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return descriptor
    }

    private var latestGradedAcquisition: CollectionActivity? {
        collectionActivities.first {
            $0.itemKind == .gradedCard
                && $0.kind.hasQuantityClaim
                && $0.remainingQuantity > 0
        }
    }

    /// The finish evidence for an already-owned slab. The catalog id is the
    /// only reliable source for set routing because graded rows persist their
    /// collection namespace in `providerID`.
    static func gradedVariantEvidence(for card: CollectedCard, catalogCard: IdentifiedCard? = nil) -> VariantEvidence {
        let printingID = card.underlyingPrintingID ?? card.providerID
        let exactCatalogCard = catalogCard.flatMap {
            $0.game == card.cardGame && $0.providerID == printingID ? $0 : nil
        }
        var evidence = exactCatalogCard?.variantEvidence ?? VariantEvidence(
            game: card.cardGame,
            setID: printingID.split(separator: "-", maxSplits: 1)
                .first.map(String.init) ?? printingID,
            cardNumber: card.cardNumber,
            catalogVariants: card.variant.map { [$0] } ?? []
        )
        if card.cardGame == .pokemon {
            evidence = evidence.excludingFirstEditionPseudoFinish()
        }
        return evidence
    }

    static func gradedVariantOptions(for card: CollectedCard) -> [PhysicalVariant] {
        VariantResolver.options(for: gradedVariantEvidence(for: card))
    }

    static func gradedVariantCorrectionOptions(for card: CollectedCard, catalogCard: IdentifiedCard? = nil) -> [PhysicalVariant] {
        VariantResolver.options(for: gradedVariantEvidence(for: card, catalogCard: catalogCard))
            .filter { $0.id != card.variantID }
    }

    private var gradedVariantCorrectionOptions: [PhysicalVariant] {
        Self.gradedVariantCorrectionOptions(for: card, catalogCard: gradedCatalogCard)
    }

    private var gradedFinishSummary: CatalogCardSummary? {
        guard card.itemKind == .gradedCard, let printingID = card.underlyingPrintingID,
              card.cardGame == .pokemon || card.cardGame == .magic else { return nil }
        let setID = card.cardGame == .pokemon
            ? printingID.split(separator: "-", maxSplits: 1).first.map(String.init) ?? printingID
            : card.setCode.lowercased()
        return CatalogCardSummary(game: card.cardGame, providerID: printingID,
            setID: CatalogSetID(game: card.cardGame, providerID: setID, pokemonPrintRun: card.pokemonPrintRun),
            setName: card.setName, setCode: card.setCode, name: card.name,
            collectorNumber: card.cardNumber, thumbnailURL: nil, imageURL: nil,
            catalogGeneration: runtimes?.runtime(for: card.cardGame)?.browse?.generation)
    }

    private func loadGradedFinishes() async {
        gradedCatalogCard = nil
        isLoadingGradedFinishes = false
        gradedFinishLoadFailed = false
        guard let summary = gradedFinishSummary else { return }
        isLoadingGradedFinishes = true
        defer { if !Task.isCancelled { isLoadingGradedFinishes = false } }
        let catalog = runtimes?.makeBrowseCatalog() ?? BrowseCatalog()
        do {
            let details = try await catalog.details(for: summary)
            guard !Task.isCancelled, summary == gradedFinishSummary else { return }
            gradedCatalogCard = details.card
        } catch {
            guard !Task.isCancelled, summary == gradedFinishSummary else { return }
            gradedFinishLoadFailed = true
        }
    }

    private func correctGradedVariant(
        _ variant: PhysicalVariant,
        activity: CollectionActivity
    ) {
        guard !isOwnershipWritePending, variant != card.variant else { return }
        let collectionKey = card.collectionKey
        let treatments = card.magicTreatmentIDsRaw
        let activityID = activity.id
        let quantity = min(activity.remainingQuantity, card.quantity)
        let container = modelContext.container
        let generation = CollectionStorageGeneration.shared
        guard let token = generation.currentToken() else { return }
        let shouldContinue = generation.continuation(for: token)
        isOwnershipWritePending = true
        Task { @MainActor in
            defer { isOwnershipWritePending = false }
            do {
                let writer = await CollectionDetailWriter.makeBackground(modelContainer: container)
                try await CollectionExclusiveWrites.retryingIfRequired {
                    try await writer.correctFinish(collectionKey: collectionKey, treatments: treatments,
                        activityID: activityID, quantity: quantity, variant: variant, shouldContinue: shouldContinue)
                }
            } catch is CancellationError {
            } catch {
                guard generation.isCurrent(token) else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    /// Everything the app knows about this particular copy, in the order a
    /// collector would ask for it. Facts folded into the glance rows remain
    /// available here without competing with the quick scan.
    private var cardFacts: [CardDetailFact] {
        var raw: [(String, String)] = []

        if !card.setName.isEmpty {
            raw.append(("Set", card.setName))
        }
        if !card.setCode.isEmpty {
            raw.append(("Set code", card.setCode))
        }
        if !card.cardNumber.isEmpty {
            raw.append(("Number", card.cardNumber))
        }
        if let rarity = card.rarity, !rarity.isEmpty {
            raw.append(("Rarity", rarity.capitalized))
        }
        if let finish = card.variant?.label {
            raw.append(("Finish", finish))
        }

        for treatment in card.displayedMagicTreatmentEvidence.treatments {
            raw.append(("Treatment", treatment.label))
        }
        if let printRun = card.pokemonPrintRun {
            raw.append(("Print run", printRun.label))
        }
        if card.itemKind != .rawCard {
            raw.append(("Type", card.itemKindLabel))
        }

        if let company = card.gradingCompany {
            raw.append(("Grader", company.label))
        }

        if let grade = card.cardGrade {
            var gradeParts = [grade.value].compactMap { $0 }
            if let label = grade.label,
               label.caseInsensitiveCompare(grade.value ?? "") != .orderedSame {
                gradeParts.append(label)
            }
            if !gradeParts.isEmpty {
                raw.append(("Grade", gradeParts.joined(separator: " ")))
            }
        } else if let gradeRaw = card.gradeRaw {
            raw.append(("Grade", gradeRaw))
        }

        if let qualifier = card.gradingQualifier {
            raw.append(("Qualifier", qualifier))
        }

        raw.append((
            "Added",
            card.dateAdded.formatted(date: .abbreviated, time: .omitted)
        ))

        return raw.enumerated().map { index, element in
            CardDetailFact(id: index, label: element.0, value: element.1)
        }
    }

    /// The catalog's uncertainty is useful context for a price, not a made-up
    /// attribute of the card. This mirrors `CardFinishOverlay.isCatalogConfirmed`:
    /// a missing resolution is also unconfirmed, which keeps old/imported rows
    /// from silently disagreeing with the finish overlay.
    private var identityConfidenceNote: String? {
        guard card.variant == nil
                || card.variantResolution == nil
                || card.variantResolution == .catalogSilent
                || card.variantResolution == .imported else { return nil }
        return "The catalog hasn't confirmed this printing's finish, so its price may match a different one."
    }


    /// What the whole position is worth, as distinct from one copy of it.
    private var holdingTotal: String? {
        guard let amount = price.amount, displayedQuantity > 0 else { return nil }
        return (amount * Double(displayedQuantity))
            .formatted(.currency(code: price.currencyCode).precision(.fractionLength(2)))
    }

    private var printingDetailsDestination: some View {
        CardPrintingDetailsView(
            cardName: card.name,
            facts: cardFacts,
            confidenceNote: identityConfidenceNote,
            setDestination: setDestination
        )
    }

    private var setDestination: some View {
        CollectionSetDestination(
            game: card.cardGame, setName: card.setName, setCode: card.setCode,
            printRun: card.pokemonPrintRun, isSealed: card.itemKind == .sealedProduct
        )
    }

    private var ownershipSection: some View {
        VStack(spacing: 0) {
            CardDetailOwnershipPanel(
                quantity: displayedQuantity,
                holdingTotal: holdingTotal,
                allowsQuantityIncrease: card.allowsQuantityAggregation,
                isUpdating: isOwnershipWritePending,
                onDecrease: { updateQuantity(displayedQuantity - 1) },
                onIncrease: { updateQuantity(displayedQuantity + 1) }
            ) {
                printingDetailsDestination
            }
            Button {
                presentDisposition()
            } label: {
                Label("Record sale or trade", systemImage: "arrow.left.arrow.right")
                    .font(.body)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .disabled(isOwnershipWritePending || displayedQuantity <= 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
    }

    private func valuationSection(model: PriceHistoryChartModel) -> some View {
        VStack(spacing: 0) {
            if let selectedPriceDate {
                let sample = model.sample(at: selectedPriceDate)
                Text(sample?.amount.formatted(currencyCode: "USD") ?? "—")
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(sample.map { "JustTCG · \($0.date.formatted(date: .abbreviated, time: .omitted))" }
                     ?? "No market history for this date")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)
            } else {
                // History is a separate provider series, not the quote used by
                // collection/portfolio valuation. Never let it replace that quote.
                CardDetailHeroPrice(price: price)
                if let source = price.source {
                    Text(price.state() == .stale ? "\(source.label) · Saved price" : source.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 104)
        .padding(.horizontal, 16)
    }

    private func makePriceHistoryModel() -> PriceHistoryChartModel {
        PriceHistoryChartModel.market(points: marketHistory, range: history.range)
    }

    private var marketHistoryRequest: CardMarketHistoryRequest { .init(card: card) }

    @MainActor
    private func loadMarketHistory() async {
        let request = marketHistoryRequest
        isLoadingMarketHistory = true
        marketHistoryError = nil
        let resolved = await request.resolvingMarketMapping(in: runtimes)
        guard !Task.isCancelled, request == marketHistoryRequest else { return }
        if marketHistoryIdentity != resolved.historyIdentity {
            marketHistory = []
            selectedPriceDate = nil
            marketHistoryIdentity = resolved.historyIdentity
        }
        let cached = await CardMarketHistoryService.shared.cached(request, runtimes: runtimes)
        guard !Task.isCancelled, request == marketHistoryRequest else { return }
        guard await request.resolvingMarketMapping(in: runtimes) == resolved,
              !Task.isCancelled, request == marketHistoryRequest else { return }
        if !cached.isEmpty { marketHistory = cached }
        defer {
            if !Task.isCancelled, request == marketHistoryRequest {
                isLoadingMarketHistory = false
            }
        }
#if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "-ui_debug_state"), arguments.indices.contains(index + 1) {
            let state = arguments[index + 1]
            if state.hasPrefix("price-chart") {
                switch state {
                case "price-chart", "price-chart-refreshing", "price-chart-saved-error":
                    marketHistory = CardMarketHistoryFixture.points
                case "price-chart-range-empty":
                    marketHistory = [.init(p: 32, t: Date.now.addingTimeInterval(-400 * 86_400).timeIntervalSince1970)]
                default: marketHistory = []
                }
                marketHistoryError = state == "price-chart-error" || state == "price-chart-saved-error"
                    ? "JustTCG history could not be loaded. Try again." : nil
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }
                CardMarketHistoryFixture.markReady()
                if state == "price-chart-loading" || state == "price-chart-refreshing" {
                    try? await Task.sleep(for: .seconds(60))
                }
                return
            }
        }
#endif
        do {
            let points = try await CardMarketHistoryService.shared.history(for: request, runtimes: runtimes)
            try Task.checkCancellation()
            guard request == marketHistoryRequest else { return }
            guard await request.resolvingMarketMapping(in: runtimes) == resolved,
                  !Task.isCancelled, request == marketHistoryRequest else { return }
            marketHistory = points
        } catch is CancellationError { return }
        catch CardMarketHistoryService.HistoryError.noListing { return }
        catch {
            guard !Task.isCancelled, request == marketHistoryRequest else { return }
            marketHistoryError = error.localizedDescription
        }
    }

    private func movementDisplay(for model: PriceHistoryChartModel) -> CardDetailMovementDisplay {
        let amount = model.samples.count > 1 ? model.samples.last!.amount - model.samples.first!.amount : nil
        return CardDetailMovementDisplay(
            status: amount == nil ? .none : .recorded,
            direction: amount.map { $0 < .zero ? .negative : ($0 > .zero ? .positive : .flat) } ?? .flat,
            amount: amount,
            percentage: amount.flatMap { PortfolioHistoryDisplay.percentChange(amount: $0, anchor: model.samples.first!.amount) },
            periodText: history.range == .all ? "available history" : history.range.pastPeriodPhrase
        )
    }


    @ViewBuilder
    private func priceHistorySection(
        model: PriceHistoryChartModel,
        movement: CardDetailMovementDisplay
    ) -> some View {
        VStack(spacing: 0) {
            if model.samples.count > 1 {
                CardDetailMovementPill(display: movement, currencyCode: "USD")
                    .padding(.bottom, 16)
            }

            MarketHistoryChartContent(model: model, hasHistory: !marketHistory.isEmpty,
                                      isLoading: isLoadingMarketHistory, error: marketHistoryError,
                                      direction: movement.direction, range: $history.range,
                                      selection: $selectedPriceDate, retry: { marketHistoryRetry += 1 })
                .accessibilityIdentifier("price-history-\(priceHistoryInstrumentKey)")

            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(price.detailAttribution, id: \.self) { Text($0) }
                    MarketHistoryExplanation(points: marketHistory)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 8)
            } label: {
                Text("Price details").frame(minHeight: 44)
            }
            .font(.subheadline)
            .padding(.horizontal, 16)
            .padding(.top, 10)

            if price.refreshFailed {
                Label("Last refresh failed", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
            }

            if let unpricedReason, price.amount == nil {
                VStack(alignment: .leading, spacing: 4) {
                    Label(unpricedReason.title, systemImage: "exclamationmark.circle")
                        .font(.subheadline.weight(.semibold))
                    Text(unpricedReason.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let coverageText = gradedMarketCoverageText {
                        Text(coverageText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let rawReference = ungradedReferenceRecord,
                       let amount = rawReference.effectiveUnitMarketPriceUSD {
                        Label("Ungraded reference", systemImage: "tag")
                            .font(.caption.weight(.semibold))
                            .padding(.top, 4)
                        Text("\(amount.formatted(.currency(code: rawReference.currencyCode))) · \(rawReference.source?.label ?? "Market quote")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Shown for context only; this amount is not used as the slab’s value.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Text("Diagnostic: \(unpricedReason.rawValue)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }
        }
        .padding(.top, 28)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Price and market movement")
    }

    private var gradedMarketCoverageText: String? {
        guard unpricedReason == .gradedGradeNotTracked,
              let coverage = price.gradedMarketCoverage,
              !coverage.listedGrades.isEmpty else { return nil }
        let grades = coverage.listedGrades.prefix(6).map { listedGrade in
            let name = [listedGrade.displayName, listedGrade.printing].compactMap { $0 }.joined(separator: " · ")
            guard let amount = listedGrade.marketPriceUSD else {
                return name
            }
            return "\(name) \(amount.formatted(.currency(code: "USD")))"
        }
        return "JustTCG currently lists: \(grades.joined(separator: ", "))"
    }

    private var ungradedReferenceRecord: PriceRecord? {
        PriceStore.authoritativeRecord(in: ungradedReferenceRecords)
    }

    @ViewBuilder
    private var marketplaceSection: some View {
        if let url = exactTCGPlayerPrintingURL {
            CardDetailMarketplaceButton(url: url)
                .padding(.horizontal, 16)
                .padding(.top, 20)
        }
    }

    private var conflictNotice: some View {
        Label(
            "Multiple synced rows will be merged automatically when this position changes.",
            systemImage: "arrow.triangle.merge"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            reduceTransparency
                ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                : AnyShapeStyle(.thinMaterial),
            in: RoundedRectangle(cornerRadius: 14, style: .continuous)
        )
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var artwork: some View {
        Group {
            if let image = CollectionArtworkStore.image(filename: localArtworkFilename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                let source = CatalogCardArtworkSource(
                    collectedCard: card,
                    prefersFullSize: true
                )
                if source.primaryURL != nil {
                    CatalogCachedImage(
                        url: source.primaryURL,
                        fallbacks: source.fallbacks,
                        placeholderText: artworkReason?.title
                    )
                } else {
                    // AsyncImage with a nil URL remains in .empty forever. End
                    // the state explicitly so an unresolved catalog row is
                    // honest and usable instead of presenting an infinite
                    // spinner.
                    missingArtworkPlaceholder
                }
            }
        }
        .overlay {
            // An overlay follows the fitted artwork's bounds without adding
            // flexible height above and below the printed card.
            CardFinishOverlay(
                variant: card.variant,
                resolution: card.variantResolution,
                treatments: card.displayedMagicTreatmentEvidence.treatments,
                cornerRadius: Self.cardCornerRadius,
                motionSource: cardFinishMotion,
                motionUsage: .detail
            )
        }
    }

    private var missingArtworkPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "photo")
            Text(artworkReason?.title ?? "Artwork unavailable")
                .font(.subheadline.weight(.semibold))
            if let artworkReason {
                Text(artworkReason.detail)
                    .font(.caption)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.secondary)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .aspectRatio(0.716, contentMode: .fit)
    }

    @MainActor
    private func saveSelectedArtwork(
        _ item: PhotosPickerItem,
        requestID: Int,
        collectionKey: String
    ) async {
        guard !isOwnershipWritePending else { return }
        let container = modelContext.container
        let generation = CollectionStorageGeneration.shared
        guard let token = generation.currentToken() else { return }
        let shouldContinue = generation.continuation(for: token)
        isOwnershipWritePending = true
        defer { isOwnershipWritePending = false }
        let loadedData: Data?
        do {
            loadedData = try await item.loadTransferable(type: Data.self)
        } catch is CancellationError {
            if requestID == artworkGeneration { selectedArtwork = nil }
            return
        } catch {
            guard requestID == artworkGeneration, !Task.isCancelled, generation.isCurrent(token) else { return }
            selectedArtwork = nil
            errorMessage = "The photo couldn't be loaded."
            return
        }
        guard requestID == artworkGeneration, !Task.isCancelled, generation.isCurrent(token) else { return }
        guard let data = loadedData else {
            selectedArtwork = nil
            errorMessage = "The photo couldn't be loaded."
            return
        }
        do {
            let writer = await CollectionDetailWriter.makeBackground(modelContainer: container)
            let filename = try await writer.saveArtwork(data: data, collectionKey: collectionKey,
                shouldContinue: shouldContinue)
            guard requestID == artworkGeneration, !Task.isCancelled, generation.isCurrent(token) else { return }
            selectedArtwork = nil
            if filename == nil {
                errorMessage = "The photo couldn't be prepared."
            }
        } catch is CancellationError {
            if requestID == artworkGeneration { selectedArtwork = nil }
        } catch {
            if requestID == artworkGeneration, !Task.isCancelled, generation.isCurrent(token) {
                errorMessage = error.localizedDescription
                selectedArtwork = nil
            }
        }
    }

    private func removeUserArtwork() {
        guard !isOwnershipWritePending else { return }
        artworkGeneration &+= 1
        pendingArtwork = nil
        selectedArtwork = nil
        let container = modelContext.container
        let collectionKey = card.collectionKey
        let generation = CollectionStorageGeneration.shared
        guard let token = generation.currentToken() else { return }
        let shouldContinue = generation.continuation(for: token)
        isOwnershipWritePending = true
        Task { @MainActor in
            defer { isOwnershipWritePending = false }
            do {
                let writer = await CollectionDetailWriter.makeBackground(modelContainer: container)
                try await writer.removeArtwork(collectionKey: collectionKey, shouldContinue: shouldContinue)
            } catch is CancellationError {
            } catch {
                guard generation.isCurrent(token) else { return }
                errorMessage = error.localizedDescription
            }
        }
    }

    private var artworkSourceKey: String {
        if let localArtworkFilename {
            return "local:\(localArtworkFilename)"
        }
        if let remoteURL = card.highImageURL ?? card.lowImageURL {
            return "remote:\(remoteURL.absoluteString)"
        }
        return "missing:\(card.collectionKey)"
    }

    private var removalMessage: String {
        if displayedQuantity == 1 {
            return "This removes the card. You can undo it."
        }
        return "This removes all \(displayedQuantity) copies. You can undo it."
    }

    private var displayedQuantity: Int {
        quantityState.displayedQuantity(for: quantityInput)
    }

    private var quantityInput: CollectionDetailQuantityState.Input {
        .init(
            collectionKey: card.collectionKey,
            physicalQuantity: card.quantity,
            logicalQuantity: logicalQuantity,
            isLogicalConflict: isLogicalConflict,
            treatments: card.magicTreatmentIDsRaw
        )
    }

    /// Re-read only when ownership inputs change. Revision checks keep a read
    /// started before a saved edit from replacing that edit's newer receipt.
    private func refreshDisplayedQuantity(for input: CollectionDetailQuantityState.Input) async {
        let revision = quantityState.revision
        let reader = await CollectionDetailQuantityReader.makeBackground(modelContainer: modelContext.container)
        do {
            let liveQuantity = try await reader.logicalQuantity(
                forAnyKey: input.collectionKey,
                magicTreatmentIDsRaw: input.treatments
            )
            guard !Task.isCancelled, quantityInput == input else { return }
            quantityState.update(liveQuantity, for: input, expectedRevision: revision)
        } catch {
            // Keep the last displayed value; a later explicit refresh can retry.
        }
    }

    private func updateQuantity(_ newQuantity: Int) {
        guard !isOwnershipWritePending,
              (0...CollectionQuantityLimits.maximum).contains(newQuantity) else { return }
        if newQuantity == 0 {
            removeCard()
            return
        }
        let input = quantityInput
        let observedQuantity = quantityState.expectedQuantity(for: input)
        let container = modelContext.container
        let generation = CollectionStorageGeneration.shared
        guard let token = generation.currentToken() else { return }
        let shouldContinue = generation.continuation(for: token)
        isOwnershipWritePending = true
        Task { @MainActor in
            defer { isOwnershipWritePending = false }
            do {
                let expectedCurrent: Int
                if let saved = quantityState.savedQuantity(for: input) {
                    expectedCurrent = saved
                } else {
                    await refreshDisplayedQuantity(for: input)
                    guard generation.isCurrent(token), quantityInput == input else { return }
                    guard let refreshedQuantity = quantityState.savedQuantity(for: input) else {
                        errorMessage = "The current quantity could not be loaded. Try again in a moment."
                        return
                    }
                    try CollectionDetailQuantityState.validateIntent(observed: observedQuantity, refreshed: refreshedQuantity)
                    expectedCurrent = refreshedQuantity
                }
                let writer = await CollectionDetailWriter.makeBackground(modelContainer: container)
                let savedQuantity = try await CollectionExclusiveWrites.retryingIfRequired {
                    try await writer.setQuantity(newQuantity, collectionKey: input.collectionKey,
                        treatments: input.treatments, expectedCurrent: expectedCurrent, shouldContinue: shouldContinue)
                }
                guard generation.isCurrent(token), quantityInput == input else { return }
                quantityState.update(savedQuantity, for: input)
            } catch is CancellationError {
                // A canceled or retired-storage action must not publish success.
            } catch {
                guard generation.isCurrent(token) else { return }
                if case CollectionStoreError.staleQuantity = error {
                    await refreshDisplayedQuantity(for: input)
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func presentDisposition(kind: CollectionDispositionKind = .sold) {
        guard !isOwnershipWritePending, displayedQuantity > 0 else { return }
        dispositionTarget = CollectionDispositionTarget(
            collectionKey: card.collectionKey, treatments: card.magicTreatmentIDsRaw,
            cardName: card.name, quantity: displayedQuantity, kind: kind
        )
    }

    private func removeCard() {
        // Deleting the row from here is what made removals invisible to
        // history. Ownership changes go through the store, which is the only
        // thing that knows the ledger has to hear about them.
        guard !isOwnershipWritePending else { return }
        let input = quantityInput
        let expectedCurrent = quantityState.expectedQuantity(for: input)
        let container = modelContext.container
        let generation = CollectionStorageGeneration.shared
        guard let token = generation.currentToken() else { return }
        let shouldContinue = generation.continuation(for: token)
        isOwnershipWritePending = true
        Task { @MainActor in
            defer { isOwnershipWritePending = false }
            do {
                let writer = await CollectionDetailWriter.makeBackground(modelContainer: container)
                let snapshot = try await CollectionExclusiveWrites.retryingIfRequired {
                    try await writer.remove(collectionKey: input.collectionKey, treatments: input.treatments,
                        expectedCurrent: expectedCurrent, shouldContinue: shouldContinue)
                }
                guard generation.isCurrent(token) else { return }
                onRemoved(snapshot)
                dismiss()
            } catch is CancellationError {
            } catch {
                guard generation.isCurrent(token) else { return }
                if case CollectionStoreError.staleQuantity = error {
                    await refreshDisplayedQuantity(for: input)
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    /// The shared builder requires an exact marketplace product or a trusted
    /// provider URL. Pokémon products are just as eligible as Magic printings.
    private var exactTCGPlayerPrintingURL: URL? {
        TCGplayerLinkBuilder.url(for: card)
    }

    @MainActor
    private func loadMarketplaceLinkIfNeeded() async {
        let container = modelContext.container
        let generation = CollectionStorageGeneration.shared
        guard let token = generation.currentToken() else { return }
        let shouldContinue = generation.continuation(for: token)
        let collectionKey = card.collectionKey
        let game = card.cardGame
        let treatments = card.magicTreatmentIDsRaw
        let hasMarketplaceURL = card.tcgplayerURL != nil
        let providerID = card.catalogProviderID ?? card.providerID
        guard game == .magic,
              treatments.isEmpty,
              MagicTreatmentKeyCodec.collectionTreatmentIDs(from: collectionKey).isEmpty,
              !hasMarketplaceURL else { return }
        guard !providerID.hasPrefix("csv:") else { return }

        guard let resolved = try? await ScryfallService().fetchCard(id: providerID),
              !Task.isCancelled,
              let url = resolved.purchaseURIs?.tcgplayer else {
            return
        }
        let writer = await CollectionDetailWriter.makeBackground(modelContainer: container)
        try? await writer.updateMarketplaceLink(url.absoluteString, collectionKey: collectionKey,
            game: game, providerID: providerID, treatments: treatments, shouldContinue: shouldContinue)
    }
}

/// A compact, stable vocabulary for the common rarity families. The enum
/// classifies the provider value for tinting, but keeps the provider's exact
/// label because named rarities such as "Illustration Rare" are distinct facts.
enum CardRarityToken: Equatable, Hashable {
    case common(String)
    case uncommon(String)
    case rare(String)
    case mythic(String)
    case unknown(String)

    init?(raw: String?) {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
              !raw.isEmpty else {
            return nil
        }

        let normalized = raw.lowercased()
        // `uncommon` must be checked before `common` because it contains the
        // latter substring. More specific named families also win over the
        // broader `rare` match (for example, "mythic rare").
        if normalized.contains("mythic") {
            self = .mythic(raw)
        } else if normalized.contains("uncommon") {
            self = .uncommon(raw)
        } else if normalized.contains("common") {
            self = .common(raw)
        } else if normalized.contains("rare") {
            self = .rare(raw)
        } else {
            // An unfamiliar provider value is still a fact. Keep it visible,
            // but let the chip use the neutral styling below.
            self = .unknown(raw)
        }
    }

    var rawLabel: String {
        switch self {
        case let .common(raw), let .uncommon(raw), let .rare(raw),
             let .mythic(raw), let .unknown(raw):
            return raw
        }
    }

    var label: String {
        rawLabel
    }

    var tint: Color {
        switch self {
        case .common(_), .unknown(_):
            return .secondary
        case .uncommon(_):
            return .gray
        case .rare(_):
            return Color(red: 0.68, green: 0.44, blue: 0.08)
        case .mythic(_):
            return Color(red: 0.84, green: 0.28, blue: 0.09)
        }
    }
}

struct RarityChip: View {
    let rarity: CardRarityToken
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        Text(rarity.label.uppercased())
            .font(.caption.weight(.bold))
            .tracking(0.5)
            .foregroundStyle(rarity.tint)
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background {
                if reduceTransparency {
                    Capsule()
                        .fill(Color(uiColor: .secondarySystemBackground))
                } else {
                    Capsule()
                        .fill(rarity.tint.opacity(0.15))
                }
            }
            .overlay {
                Capsule()
                    .stroke(
                        rarity.tint.opacity(reduceTransparency ? 0.35 : 0.22),
                        lineWidth: 1
                    )
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Rarity")
            .accessibilityValue(rarity.label)
    }
}

private struct AppCardDetailBackdrop: View {
    var body: some View {
        Color.black
    }
}

private struct CardDetailFormattedPrice {
    let leading: String
    let fractional: String?
    let accessibilityValue: String

    init?(amount: Double, currencyCode: String) {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode
        formatter.maximumFractionDigits = 2
        guard let full = formatter.string(from: NSNumber(value: amount)) else { return nil }

        accessibilityValue = full
        guard let separator = formatter.decimalSeparator,
              let range = full.range(of: separator, options: .backwards) else {
            leading = full
            fractional = nil
            return
        }

        leading = String(full[..<range.lowerBound])
        fractional = String(full[range.lowerBound...])
    }
}

private struct CardDetailHeroPrice: View {
    let price: PriceDisplay

    var body: some View {
        VStack(alignment: .center, spacing: 2) {
            switch price.state() {
            case .current:
                formattedAmount
            case .stale:
                formattedAmount
                Text("Stale price")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .unavailable:
                Text("Price unavailable")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.secondary)
            case .unknown:
                Text("Not checked yet")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var formattedAmount: some View {
        if let amount = price.amount,
           let formatted = CardDetailFormattedPrice(
               amount: amount,
               currencyCode: price.currencyCode
           ) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(formatted.leading)
                    .font(.system(size: 52, weight: .bold, design: .rounded))
                if let fractional = formatted.fractional {
                    Text(fractional)
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.70)
        } else {
            Text("Price unavailable")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    private var accessibilityText: String {
        guard let amount = price.amount else {
            return price.state() == .unavailable ? "Price unavailable" : "Price not checked yet"
        }
        return amount.formatted(.currency(code: price.currencyCode))
    }
}

private struct CardDetailMovementPill: View {
    let display: CardDetailMovementDisplay
    let currencyCode: String

    var body: some View {
        HStack(spacing: 8) {
            movementLabel
            Text(display.periodText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var movementLabel: some View {
        switch display.status {
        case .recording:
            Text("History is being recorded")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .none:
            Text("Movement unavailable")
                .font(.footnote)
                .foregroundStyle(.secondary)
        case .recorded:
            if let amount = display.amount, !amount.isZero {
                HStack(spacing: 3) {
                    Image(systemName: display.direction == .negative ? "arrow.down" : "arrow.up")
                        .font(.system(size: 14, weight: .semibold))
                    Text(amount.magnitude.formatted(currencyCode: currencyCode))
                    if let percentage = display.percentage {
                        Text("· \(abs(percentage).formatted(.percent.precision(.fractionLength(2))))")
                    }
                }
                .font(.system(size: 14, weight: .semibold).monospacedDigit())
                .foregroundStyle(PortfolioPalette.direction(amount))
                .padding(.leading, 7)
                .padding(.trailing, 10)
                .padding(.vertical, 4)
                .background(PortfolioPalette.directionFill(amount), in: Capsule())
            } else {
                Text("No net movement")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct CardDetailRangeSelector: View {
    let selection: PortfolioHistoryRange
    let direction: CardDetailMovementDisplay.Direction
    let onSelect: (PortfolioHistoryRange) -> Void

    private var selectedTint: Color {
        switch direction {
        case .positive: return PortfolioPalette.gain
        case .negative: return PortfolioPalette.loss
        case .flat: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            ForEach(PortfolioHistoryRange.allCases, id: \.self) { range in
                Button {
                    onSelect(range)
                } label: {
                    Text(range.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selection == range ? selectedTint : .secondary)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(
                            selection == range ? selectedTint.opacity(0.16) : .clear,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(range.accessibilityName)
                .accessibilityAddTraits(selection == range ? .isSelected : [])
            }
        }
        .padding(.horizontal, 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Price history range")
        .accessibilityHint("Choose how much per-card price history to show.")
    }
}

struct CardDetailMarketplaceButton: View {
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 8) {
                Text("Buy on TCGplayer")
                Image(systemName: "arrow.up.right")
                    .imageScale(.small)
            }
            .font(.headline)
            .foregroundStyle(PortfolioPalette.money)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background(
                Color.white.opacity(0.07),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(PortfolioPalette.money.opacity(0.28), lineWidth: 1)
            }
        }
        .accessibilityLabel("Buy this exact printing on TCGplayer")
    }
}

private struct CollectionDispositionTarget: Identifiable {
    let id = UUID()
    let collectionKey: String
    let treatments: [String]
    let cardName: String
    let quantity: Int
    let kind: CollectionDispositionKind
}

private struct CollectionDispositionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    let target: CollectionDispositionTarget
    let onRecorded: (RemovedCardSnapshot) -> Void
    @State private var kind: CollectionDispositionKind
    @State private var quantity = 1
    @State private var amount = ""
    @State private var note = ""
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(target: CollectionDispositionTarget, onRecorded: @escaping (RemovedCardSnapshot) -> Void) {
        self.target = target
        self.onRecorded = onRecorded
        _kind = State(initialValue: target.kind)
    }

    private var amountIsValid: Bool {
        kind == .traded || (try? CollectionDisposition.parseSaleTotal(amount)) != nil
            || amount.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(target.cardName).font(.headline)
                    Picker("Transaction", selection: $kind) {
                        ForEach(CollectionDispositionKind.allCases) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    Stepper("Quantity: \(quantity)", value: $quantity, in: 1...target.quantity)
                } footer: {
                    Text("Saving reduces your owned quantity by \(quantity). The record stays in Collection Activity, even when you own no copies.")
                }

                if kind == .sold {
                    Section {
                        LabeledContent("Total sold for (USD)") {
                            TextField("Optional", text: $amount)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .accessibilityLabel("Total sold for in US dollars, optional")
                        }
                        if !amountIsValid {
                            Text(CollectionDisposition.ValidationError.invalidAmount.localizedDescription)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    } footer: {
                        Text(quantity == 1
                             ? "Enter the total for this copy, before fees. Leave blank if unknown."
                             : "Enter the total for all \(quantity) copies, before fees. Leave blank if unknown.")
                    }
                }

                Section {
                    TextField(kind == .traded ? "What did you receive? (optional)" : "Notes (optional)",
                              text: $note, axis: .vertical)
                        .lineLimit(3...6)
                        .accessibilityLabel(kind == .traded ? "Trade details, optional" : "Sale notes, optional")
                } footer: {
                    Text("Personal records are kept separately from market prices.")
                }

                if let errorMessage {
                    Section {
                        Label(errorMessage, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                    }
                }
            }
            .disabled(isSaving)
            .navigationTitle("Record sale or trade")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(isSaving || !amountIsValid)
                }
                ToolbarItem(placement: .status) {
                    if isSaving { ProgressView().accessibilityLabel("Saving transaction") }
                }
            }
            .interactiveDismissDisabled(isSaving)
        }
    }

    private func save() {
        guard !isSaving, amountIsValid else { return }
        let generation = CollectionStorageGeneration.shared
        guard let token = generation.currentToken() else {
            errorMessage = "Your collection is still loading. Try again in a moment."
            return
        }
        let shouldContinue = generation.continuation(for: token)
        let container = modelContext.container
        isSaving = true
        errorMessage = nil
        Task { @MainActor in
            defer { isSaving = false }
            do {
                let disposition = CollectionDisposition(kind: kind,
                    saleTotal: kind == .sold ? try CollectionDisposition.parseSaleTotal(amount) : nil,
                    note: note)
                let writer = await CollectionDetailWriter.makeBackground(modelContainer: container)
                let snapshot = try await CollectionExclusiveWrites.retryingIfRequired {
                    try await writer.remove(collectionKey: target.collectionKey, treatments: target.treatments,
                        expectedCurrent: target.quantity, quantity: quantity, disposition: disposition,
                        shouldContinue: shouldContinue)
                }
                guard generation.isCurrent(token) else { return }
                dismiss()
                onRecorded(snapshot)
            } catch is CancellationError {
            } catch {
                guard generation.isCurrent(token) else { return }
                errorMessage = error.localizedDescription
            }
        }
    }
}

private struct CardDetailOwnershipPanel<Details: View>: View {
    let quantity: Int
    let holdingTotal: String?
    let allowsQuantityIncrease: Bool
    let isUpdating: Bool
    let onDecrease: () -> Void
    let onIncrease: () -> Void
    private let details: Details

    init(
        quantity: Int,
        holdingTotal: String?,
        allowsQuantityIncrease: Bool,
        isUpdating: Bool,
        onDecrease: @escaping () -> Void,
        onIncrease: @escaping () -> Void,
        @ViewBuilder details: () -> Details
    ) {
        self.quantity = quantity
        self.holdingTotal = holdingTotal
        self.allowsQuantityIncrease = allowsQuantityIncrease
        self.isUpdating = isUpdating
        self.onDecrease = onDecrease
        self.onIncrease = onIncrease
        self.details = details()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Owned")
                    .font(.system(size: 17))
                if isUpdating {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("Saving collection change")
                }
                Spacer(minLength: 12)
                quantityControl
                    .disabled(isUpdating)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 60)

            divider

            HStack(spacing: 12) {
                Text("Collection value")
                    .font(.system(size: 17))
                Spacer(minLength: 12)
                Text(holdingTotal ?? "Unavailable")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(holdingTotal == nil ? .secondary : PortfolioPalette.money)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 56)

            divider

            NavigationLink {
                details
            } label: {
                HStack(spacing: 12) {
                    Text("Printing details")
                        .font(.system(size: 17))
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 56)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Printing details")
        }
        .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Ownership")
    }

    private var divider: some View {
        Rectangle()
            .fill(Color.white.opacity(0.14))
            .frame(height: 0.5)
            .padding(.leading, 14)
    }

    private var quantityControl: some View {
        HStack(spacing: 0) {
            Button(action: onDecrease) {
                Image(systemName: "minus")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(quantity <= 0)
            .accessibilityLabel("Decrease quantity")

            Text("\(quantity)")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .frame(minWidth: 28)
                .contentTransition(.numericText())

            Button(action: onIncrease) {
                Image(systemName: "plus")
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .disabled(!allowsQuantityIncrease || quantity >= CollectionQuantityLimits.maximum)
            .accessibilityLabel("Increase quantity")
        }
        .buttonStyle(.borderless)
        .background(Color.white.opacity(0.10), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Owned, \(quantity)")
    }
}

private struct CardPrintingDetailsView<SetDestination: View>: View {
    let cardName: String
    let facts: [CardDetailFact]
    let confidenceNote: String?
    let setDestination: SetDestination

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(cardName)
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(facts) { fact in
                    if fact.label == "Set" {
                        NavigationLink {
                            setDestination
                        } label: {
                            LabeledContent(fact.label) {
                                Text(fact.value).foregroundStyle(Color.accentColor)
                            }
                            .frame(minHeight: 44)
                        }
                        .font(.callout)
                    } else {
                        LabeledContent(fact.label) {
                            Text(fact.value)
                                .font(.callout.weight(.medium))
                                .multilineTextAlignment(.trailing)
                        }
                        .font(.callout)
                    }
                }

                if let confidenceNote {
                    Label(confidenceNote, systemImage: "questionmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
            }
            .padding(20)
            .contentWidthLimit(.standard)
        }
        .navigationTitle("Printing details")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityLabel("Printing details for \(cardName)")
    }
}

private struct CollectionSetDestination: View {
    @Environment(\.cardGameRuntimes) private var runtimes
    let game: CardGame
    let setName: String
    let setCode: String
    let printRun: PokemonPrintRun?
    let isSealed: Bool
    @State private var catalog: BrowseCatalog?
    @State private var set: CatalogSet?
    @State private var failure: String?

    var body: some View {
        Group {
            if isSealed {
                SealedProductSetDestination(
                    game: game, setName: setName, gameRegistry: runtimes?.registry ?? .standard
                )
            } else if let set, let catalog {
                CatalogSetCardsView(set: set, catalog: catalog)
            } else if let failure {
                ContentUnavailableView {
                    Label("Couldn't load this set", systemImage: "rectangle.stack")
                } description: {
                    Text(failure)
                } actions: {
                    Button("Retry") { Task { await load() } }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                ProgressView("Loading set…")
            }
        }
        .navigationTitle(setName)
        .navigationBarTitleDisplayMode(.inline)
        .task { if !isSealed, set == nil { await load() } }
    }

    private func load() async {
        failure = nil
        let catalog = catalog ?? runtimes?.makeBrowseCatalog() ?? BrowseCatalog()
        self.catalog = catalog
        do {
            let sets = try await catalog.sets(for: game)
            let matches = sets.filter {
                $0.catalogID.pokemonPrintRun == printRun &&
                ((!setCode.isEmpty && $0.code.caseInsensitiveCompare(setCode) == .orderedSame) ||
                 (setCode.isEmpty && $0.name.caseInsensitiveCompare(setName) == .orderedSame))
            }
            let named = matches.filter { $0.name.caseInsensitiveCompare(setName) == .orderedSame }
            set = matches.count == 1 ? matches.first : (named.count == 1 ? named.first : nil)
            if set == nil { failure = "This set isn't available in the card catalog." }
        } catch {
            failure = "The set catalog couldn't load. Please try again."
        }
    }
}

private struct CollectionCardHistoryView: View {
    @Query private var activities: [CollectionActivity]
    let cardName: String

    init(collectionKey: String, cardName: String) {
        self.cardName = cardName
        // SwiftData predicates should capture a stable local value. Capturing
        // the initializer parameter directly can leave the dynamic query with
        // an invalid expression when this destination is pushed from a detail
        // route, which was the source of the history-screen crash.
        let key = collectionKey
        self._activities = Query(
            filter: #Predicate<CollectionActivity> { $0.collectionKey == key },
            sort: [SortDescriptor(\CollectionActivity.occurredAt, order: .reverse)]
        )
    }

    var body: some View {
        List {
            if activities.isEmpty {
                ContentUnavailableView(
                    "No history recorded",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Collection changes for this card will appear here.")
                )
            } else {
                ForEach(activities) { activity in
                    NavigationLink {
                        CollectionActivityEditor(activity: activity)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: activity.actionSymbolName)
                                .foregroundStyle(historyColor(for: activity.kind))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activity.actionLabel)
                                    .font(.subheadline.weight(.semibold))
                                if let summary = activity.transactionSummary {
                                    Text(summary)
                                        .font(.subheadline)
                                }
                                Text(historyMetadata(for: activity))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(activity.occurredAt, format: .dateTime.month().day().year().hour().minute())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(signedQuantity(activity.signedQuantity))
                                .font(.subheadline.monospacedDigit().weight(.semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 44)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityLabel("Collection history for \(cardName)")
    }

    private func historyMetadata(for activity: CollectionActivity) -> String {
        [
            activity.magicContentKind == .regular ? nil : activity.magicContentKind.label,
            activity.variantLabel,
            activity.magicTreatmentEvidence.displayLabel
        ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    private func signedQuantity(_ quantity: Int) -> String {
        if quantity > 0 { return "+\(quantity)" }
        if quantity < 0 { return "−\(-quantity)" }
        return "—"
    }

    private func historyColor(for kind: CollectionActivityKind) -> Color {
        switch kind {
        case .added: return .green
        case .removed: return .red
        case .restored: return .mint
        case .corrected: return .orange
        case .quantityAdjusted: return Color.accentColor
        case .undone: return .purple
        }
    }
}

struct PriceHistorySample: Identifiable, Equatable {
    let id: String
    let date: Date
    let day: Date
    let amount: Money
    let kind: PriceObservationKind?
    let isObservation: Bool

    var annotationLabel: String? {
        kind?.chartLabel
    }
}

struct PriceHistorySegment: Identifiable, Equatable {
    let id: String
    let samples: [PriceHistorySample]
}

/// A pure projection of the two price-history tables. A line joins only days
/// for which the app has a successful check row; observations alone can create
/// points, but they cannot manufacture knowledge across an unchecked span.
struct PriceHistoryChartModel: Equatable {
    let currencyCode: String
    let timeZone: TimeZone
    let rangeStart: Date
    let rangeEnd: Date
    let plotRangeStart: Date
    let plotRangeEnd: Date
    let samples: [PriceHistorySample]
    let segments: [PriceHistorySegment]
    let observationCount: Int
    let checkedDayCount: Int
    var isProviderHistory = false

    static func market(points: [JustTCGHistoryPoint], range: PortfolioHistoryRange, now: Date = .now) -> Self {
        let timeZone = TimeZone(secondsFromGMT: 0)!
        let calendar = PortfolioCalendar.calendar(in: timeZone)
        let valid = points.filter { $0.p.isFinite && $0.p >= 0 && $0.t.isFinite && $0.t > 0 && $0.t <= now.timeIntervalSince1970 }
            .sorted { $0.t < $1.t }
        let start = range.requestedStart(now: now, calendar: calendar, earliest: valid.first.map { Date(timeIntervalSince1970: $0.t) })
        let samples = valid.compactMap { point -> PriceHistorySample? in
            let date = Date(timeIntervalSince1970: point.t)
            guard date >= start, let amount = Money(rounding: point.p) else { return nil }
            return PriceHistorySample(id: "market-\(point.t)", date: date, day: calendar.startOfDay(for: date),
                                      amount: amount, kind: nil, isObservation: true)
        }
        let lower = samples.first?.date ?? start
        let upper = max(samples.last?.date ?? now, lower.addingTimeInterval(60))
        return Self(currencyCode: "USD", timeZone: timeZone, rangeStart: start, rangeEnd: now,
                    plotRangeStart: lower, plotRangeEnd: upper, samples: samples,
                    segments: samples.isEmpty ? [] : [.init(id: "market", samples: samples)],
                    observationCount: samples.count, checkedDayCount: 0, isProviderHistory: true)
    }

    var hasGaps: Bool {
        segments.count > 1 && observationCount >= 2
    }

    var plotRange: ClosedRange<Date> {
        plotRangeStart...plotRangeEnd
    }

    var plotRangeSpan: TimeInterval {
        plotRangeEnd.timeIntervalSince(plotRangeStart)
    }

    var isPlotRangeFitted: Bool {
        plotRangeStart != rangeStart || plotRangeEnd != rangeEnd
    }

    static func recommendedXAxisTickCount(
        for span: TimeInterval,
        isAccessibilitySize: Bool
    ) -> Int {
        let daySpan = max(span / (24 * 60 * 60), 1)
        let estimatedCount = Int(ceil(daySpan / 3)) + 1
        let maximumCount = isAccessibilitySize ? 2 : 5
        return min(maximumCount, max(2, estimatedCount))
    }

    static func usesShortXAxisLabels(for span: TimeInterval) -> Bool {
        span < 2 * 24 * 60 * 60
    }

    var yDomain: ClosedRange<Double> {
        let values = samples.map { $0.amount.doubleValue }
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }
        let observedSpan = maximum - minimum
        let referencePrice = values.last ?? maximum
        let minimumVisualSpan = max(abs(referencePrice) * 0.02, 0.05)
        // Keep the two-percent floor despite subtraction rounding when the
        // chart is centered around a relatively expensive, nearly flat price.
        let floatingPointGuard = max(minimumVisualSpan * 1e-6, abs(referencePrice).ulp * 8)
        let desiredSpan = max(observedSpan * 1.24, minimumVisualSpan + floatingPointGuard)
        let midpoint = (minimum + maximum) / 2
        var lower = midpoint - desiredSpan / 2
        var upper = midpoint + desiredSpan / 2

        // A price chart cannot claim a negative price. When clamping the lower
        // bound, preserve a nonzero visual envelope so low-priced cards do not
        // collapse into a single line.
        if lower < 0 {
            lower = 0
            upper = max(upper, desiredSpan)
        }
        return lower...upper
    }

    var summary: String {
        if isProviderHistory { return "\(samples.count) historical market prices from JustTCG." }
        let observationLabel = observationCount == 1 ? "1 changed price" : "\(observationCount) changed prices"
        let checkLabel = checkedDayCount == 1 ? "1 checked day" : "\(checkedDayCount) checked days"
        return "\(observationLabel) across \(checkLabel)."
    }

    /// Scrubbing follows the known step within a checked span. A gap never
    /// borrows a distant price, even when that observation is the nearest one.
    func sample(at date: Date) -> PriceHistorySample? {
        guard plotRange.contains(date) else { return nil }
        if isProviderHistory {
            return samples.min { abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date)) }
        }
        for segment in segments {
            guard let first = segment.samples.first, let last = segment.samples.last else { continue }
            if date >= first.date && date <= last.date {
                return segment.samples.last(where: { $0.date <= date })
            }
        }
        let calendar = PortfolioCalendar.calendar(in: timeZone)
        return samples.filter { calendar.isDate($0.date, inSameDayAs: date) }.min {
            abs($0.date.timeIntervalSince(date)) < abs($1.date.timeIntervalSince(date))
        }
    }

    static func make(
        observations: [PriceObservation],
        checkDays: [PriceCheckDay],
        currencyCode: String,
        range: PortfolioHistoryRange,
        now: Date,
        timeZone: TimeZone
    ) -> Self {
        let calendar = PortfolioCalendar.calendar(in: timeZone)
        let orderedObservations = observations.sorted {
            if $0.receivedAt != $1.receivedAt { return $0.receivedAt < $1.receivedAt }
            return $0.id.uuidString < $1.id.uuidString
        }
        let orderedCheckDays = checkDays.sorted {
            if $0.lastSuccessfulCheckAt != $1.lastSuccessfulCheckAt {
                return $0.lastSuccessfulCheckAt < $1.lastSuccessfulCheckAt
            }
            return $0.portfolioDay < $1.portfolioDay
        }

        let earliestEvent = (orderedObservations.map(\.receivedAt) + orderedCheckDays.map(\.portfolioDay)).min()
        let start = range.requestedStart(now: now, calendar: calendar, earliest: earliestEvent)
        let requestedEnd = max(now, start)
        let end = requestedEnd > start
            ? requestedEnd
            : calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(24 * 60 * 60)

        let checkedDays = Set(orderedCheckDays.map { calendar.startOfDay(for: $0.portfolioDay) })
        let checkedDaysInRange = checkedDays.filter { $0 >= start && $0 <= end }.count

        var events: [TimelineEvent] = orderedObservations.map {
            TimelineEvent(
                date: $0.receivedAt,
                day: calendar.startOfDay(for: $0.receivedAt),
                priority: 0,
                orderKey: $0.id.uuidString,
                observation: $0,
                checkDay: nil
            )
        }
        events.append(contentsOf: orderedCheckDays.map {
            TimelineEvent(
                date: $0.lastSuccessfulCheckAt,
                day: calendar.startOfDay(for: $0.portfolioDay),
                priority: 1,
                orderKey: "\($0.portfolioDay.timeIntervalSinceReferenceDate)-\($0.lastSuccessfulCheckAt.timeIntervalSinceReferenceDate)",
                observation: nil,
                checkDay: $0
            )
        })
        events.sort {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.priority != $1.priority { return $0.priority < $1.priority }
            return $0.orderKey < $1.orderKey
        }

        var currentAmount: Money?
        var samples: [PriceHistorySample] = []
        var observationCount = 0
        var sampleIndex = 0

        for event in events {
            if let observation = event.observation {
                if observation.kind == .explicitInvalidation {
                    currentAmount = nil
                    continue
                }
                currentAmount = usableAmount(
                    for: observation,
                    currencyCode: currencyCode
                )
                guard let currentAmount,
                      observation.receivedAt >= start,
                      observation.receivedAt <= end else { continue }
                observationCount += 1
                append(
                    PriceHistorySample(
                        id: "observation-\(sampleIndex)",
                        date: observation.receivedAt,
                        day: event.day,
                        amount: currentAmount,
                        kind: observation.kind,
                        isObservation: true
                    ),
                    to: &samples
                )
                sampleIndex += 1
            } else if let checkDay = event.checkDay,
                      checkDay.lastSuccessfulCheckAt >= start,
                      checkDay.lastSuccessfulCheckAt <= end,
                      let currentAmount {
                append(
                    PriceHistorySample(
                        id: "check-\(sampleIndex)",
                        date: checkDay.lastSuccessfulCheckAt,
                        day: event.day,
                        amount: currentAmount,
                        kind: nil,
                        isObservation: false
                    ),
                    to: &samples
                )
                sampleIndex += 1
            }
        }

        // A single changed value is a point, not a fabricated flat series. The
        // check-day rows remain useful once a second observation gives the chart
        // two anchors for a step; until then they must not imply a trend.
        if observationCount < 2 {
            samples.removeAll { !$0.isObservation }
        }

        var segments: [PriceHistorySegment] = []
        var currentSegment: [PriceHistorySample] = []
        for sample in samples {
            guard let previous = currentSegment.last else {
                currentSegment = [sample]
                continue
            }
            if observationCount >= 2,
               allDaysChecked(from: previous.day, to: sample.day, in: checkedDays, calendar: calendar) {
                currentSegment.append(sample)
            } else {
                segments.append(
                    PriceHistorySegment(id: "segment-\(segments.count)", samples: currentSegment)
                )
                currentSegment = [sample]
            }
        }
        if !currentSegment.isEmpty {
            segments.append(
                PriceHistorySegment(id: "segment-\(segments.count)", samples: currentSegment)
            )
        }

        let plotRange = plotRange(
            for: samples,
            requestedStart: start,
            requestedEnd: end
        )

        return PriceHistoryChartModel(
            currencyCode: currencyCode,
            timeZone: timeZone,
            rangeStart: start,
            rangeEnd: end,
            plotRangeStart: plotRange.lowerBound,
            plotRangeEnd: plotRange.upperBound,
            samples: samples,
            segments: segments,
            observationCount: observationCount,
            checkedDayCount: checkedDaysInRange
        )
    }

    /// Keep the selected history range as the data contract, but do not force
    /// a pair of recent observations into the last few pixels of a month-long
    /// axis. The plot gets a small amount of context around the observed span;
    /// gaps between observations remain visible because the samples and segment
    /// rules are unchanged.
    private static func plotRange(
        for samples: [PriceHistorySample],
        requestedStart: Date,
        requestedEnd: Date
    ) -> ClosedRange<Date> {
        guard let first = samples.first?.date,
              let last = samples.last?.date else {
            return requestedStart...requestedEnd
        }

        let requestedSpan = max(requestedEnd.timeIntervalSince(requestedStart), 1)
        let observedSpan = max(last.timeIntervalSince(first), 0)
        guard observedSpan < requestedSpan * 0.65 else {
            return requestedStart...requestedEnd
        }

        let padding = max(observedSpan * 0.18, 6 * 60 * 60)
        var lower = first.addingTimeInterval(-padding)
        var upper = last.addingTimeInterval(padding)
        let minimumSpan: TimeInterval = 24 * 60 * 60
        if upper.timeIntervalSince(lower) < minimumSpan {
            let midpoint = first.addingTimeInterval(last.timeIntervalSince(first) / 2)
            lower = midpoint.addingTimeInterval(-minimumSpan / 2)
            upper = midpoint.addingTimeInterval(minimumSpan / 2)
        }
        return lower...upper
    }

    private struct TimelineEvent {
        let date: Date
        let day: Date
        let priority: Int
        let orderKey: String
        let observation: PriceObservation?
        let checkDay: PriceCheckDay?
    }

    private static func usableAmount(
        for observation: PriceObservation,
        currencyCode: String
    ) -> Money? {
        guard observation.currencyCode == currencyCode,
              let amount = observation.amount,
              amount.isValid,
              observation.kind != .explicitInvalidation else { return nil }
        return amount
    }

    private static func append(_ sample: PriceHistorySample, to samples: inout [PriceHistorySample]) {
        if let previous = samples.last,
           !sample.isObservation,
           previous.day == sample.day,
           previous.amount == sample.amount {
            return
        }
        samples.append(sample)
    }

    private static func allDaysChecked(
        from first: Date,
        to last: Date,
        in checkedDays: Set<Date>,
        calendar: Calendar
    ) -> Bool {
        var day = calendar.startOfDay(for: first)
        let finalDay = calendar.startOfDay(for: last)
        while true {
            guard checkedDays.contains(day) else { return false }
            if day >= finalDay { return true }
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { return false }
            day = calendar.startOfDay(for: next)
        }
    }
}

private extension PriceObservationKind {
    var chartLabel: String? {
        switch self {
        case .marketUpdate: return nil
        case .sourceRestatement: return "Source restatement"
        case .sourceTransition: return "Source changed"
        case .explicitInvalidation: return "Price withdrawn"
        }
    }
}

/// All surfaces describe the catalog currently supplying quote authority.
struct YuGiOhPricingNotice: View {
    @Environment(\.cardGameRuntimes) private var runtimes
    @State private var notice = YuGiOhCatalog.unavailablePricingNotice

    var body: some View {
        Text(notice)
            .task(id: runtimes?.runtime(for: .yuGiOh)?.catalog?.generation) {
                let source = runtimes?.runtime(for: .yuGiOh)?.activationSource
                let events = await source?.activationSnapshots()
                notice = await YuGiOhCatalog.activePricingNotice(in: runtimes)
                if let events {
                    for await _ in events {
                        guard !Task.isCancelled else { return }
                        notice = await YuGiOhCatalog.activePricingNotice(in: runtimes)
                    }
                }
            }
    }
}

/// Shared by catalog and collection details; no ownership is required.
struct CardMarketHistoryPanel: View {
    @Environment(\.cardGameRuntimes) private var runtimes
    let request: CardMarketHistoryRequest
    @State private var points: [JustTCGHistoryPoint] = []
    @State private var range: PortfolioHistoryRange = .threeMonths
    @State private var selection: Date?
    @State private var error: String?
    @State private var isLoading = true
    @State private var loadedIdentity: [String]?
    @State private var retryID = 0

    var body: some View {
        let model = PriceHistoryChartModel.market(points: points, range: range)
        let direction: CardDetailMovementDisplay.Direction = model.samples.first.flatMap { first in
            model.samples.last.map { $0.amount < first.amount ? .negative : ($0.amount > first.amount ? .positive : .flat) }
        } ?? .flat
        VStack(alignment: .leading, spacing: 12) {
            Text("Market price history").font(.headline).padding(.horizontal, 16)
            if let selection, let sample = model.sample(at: selection) {
                Text("\(sample.amount.formatted(currencyCode: "USD")) · \(sample.date.formatted(date: .abbreviated, time: .omitted))")
                    .font(.subheadline.monospacedDigit()).padding(.horizontal, 16)
            }
            MarketHistoryChartContent(model: model, hasHistory: !points.isEmpty, isLoading: isLoading,
                                      error: error, direction: direction, range: $range,
                                      selection: $selection, retry: { retryID += 1 })
            DisclosureGroup {
                MarketHistoryExplanation(points: points).font(.caption).foregroundStyle(.secondary)
            } label: {
                Text("Price details").frame(minHeight: 44)
            }
            .font(.subheadline).padding(.horizontal, 16)
        }
        .task(id: MarketHistoryLoadID(request: request, retry: retryID)) { await load() }
        .task(id: runtimes?.runtime(for: request.game)?.catalog?.generation) {
            guard request.requiresCatalogMapping else { return }
            let source = runtimes?.runtime(for: request.game)?.activationSource
            let events = await source?.activationSnapshots()
            retryID += 1
            guard let events else { return }
            for await _ in events {
                guard !Task.isCancelled else { return }
                points = []
                isLoading = true
                retryID += 1
            }
        }
    }

    @MainActor
    private func load() async {
        isLoading = true
        error = nil
#if DEBUG && LOCAL_ONLY_SIGNING
        if let state = YuGiOhHistoryDebugView.state, request.game == .yuGiOh {
            points = state == "chart" ? CardMarketHistoryFixture.points : []
            error = state == "missing-key" ? JustTCGTransport.TransportError.missingCredentials.localizedDescription : nil
            isLoading = false
            CardMarketHistoryFixture.markReady()
            return
        }
#endif
        let resolved = await request.resolvingMarketMapping(in: runtimes)
        guard !Task.isCancelled else { return }
        if loadedIdentity != resolved.historyIdentity {
            points = []
            selection = nil
            loadedIdentity = resolved.historyIdentity
        }
        let cached = await CardMarketHistoryService.shared.cached(request, runtimes: runtimes)
        guard !Task.isCancelled else { return }
        guard await request.resolvingMarketMapping(in: runtimes) == resolved, !Task.isCancelled else { return }
        if !cached.isEmpty { points = cached }
        defer { if !Task.isCancelled { isLoading = false } }
        do {
            let result = try await CardMarketHistoryService.shared.history(for: request, runtimes: runtimes)
            try Task.checkCancellation()
            guard await request.resolvingMarketMapping(in: runtimes) == resolved, !Task.isCancelled else { return }
            points = result
        } catch is CancellationError { return }
        catch CardMarketHistoryService.HistoryError.noListing { return }
        catch {
            guard !Task.isCancelled else { return }
            self.error = error.localizedDescription
        }
    }
}

#if DEBUG && LOCAL_ONLY_SIGNING
/// Read-only, deterministic presentation fixture for the same catalog panel.
/// Uses a real bundled identity and synthetic history, with no provider calls.
struct YuGiOhHistoryDebugView: View {
    @State private var card: IdentifiedCard?
    @State private var edition: PhysicalVariant = .yugiohFirstEdition

    static var state: String? {
        let args = ProcessInfo.processInfo.arguments
        guard let route = args.firstIndex(of: "-ui_debug_route"), args.indices.contains(route + 1),
              args[route + 1] == "YuGiOhHistoryReview",
              let state = args.firstIndex(of: "-ui_debug_state"), args.indices.contains(state + 1) else { return nil }
        return args[state + 1]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Synthetic history · Read-only QA").font(.caption).foregroundStyle(.secondary)
                    if let card {
                        Text(card.name).font(.title2.bold())
                        Text(card.identifier).font(.subheadline)
                        Picker("History edition", selection: $edition) {
                            ForEach(card.variantEvidence.catalogVariants) { Text($0.label).tag($0) }
                        }
                        CardMarketHistoryPanel(request: .init(card: card, variant: edition, printRun: nil))
                            .id(edition.id)
                    }
                }
                .padding(.vertical, 20)
            }
            .navigationTitle("Yu-Gi-Oh! history")
            .task {
                guard let catalog = try? YuGiOhCatalog.bundled.get(),
                      let p = catalog.printingByID.values.first(where: { $0.productID == 21792 }),
                      let resolved = try? YuGiOhCatalogAdapter(catalog: catalog).resolutionForExistingHolding(p.id) else { return }
                edition = p.editions.first?.variant ?? .yugiohFirstEdition
                card = resolved.card
            }
        }
        .foregroundStyle(.primary)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
    }
}
#endif

/// Loading, empty and filtered-out history are distinct states. Existing
/// samples always remain usable while a refresh runs or fails.
enum MarketHistoryPresentation: Equatable {
    case chart, outsideRange, loading, unavailable, failed

    init(model: PriceHistoryChartModel, hasHistory: Bool, isLoading: Bool, error: String?) {
        if !model.samples.isEmpty { self = .chart }
        else if hasHistory { self = .outsideRange }
        else if isLoading { self = .loading }
        else if error != nil { self = .failed }
        else { self = .unavailable }
    }
}

struct MarketHistoryChartContent: View {
    let model: PriceHistoryChartModel
    let hasHistory: Bool
    let isLoading: Bool
    let error: String?
    let direction: CardDetailMovementDisplay.Direction
    @Binding var range: PortfolioHistoryRange
    @Binding var selection: Date?
    let retry: () -> Void

    var body: some View {
        let presentation = MarketHistoryPresentation(model: model, hasHistory: hasHistory,
                                                     isLoading: isLoading, error: error)
        VStack(alignment: .leading, spacing: 8) {
            switch presentation {
            case .chart:
                PriceHistoryChartView(model: model, currencyCode: "USD", direction: direction, selectedDate: $selection)
            case .loading:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Loading price history…").font(.subheadline)
                }
                .frame(maxWidth: .infinity, minHeight: 64)
                .accessibilityElement(children: .combine)
            case .outsideRange:
                VStack(spacing: 4) {
                    Text("No prices in this period").font(.subheadline)
                    Button("View all history", action: showAllHistory)
                        .foregroundStyle(.tint)
                        .frame(minHeight: 44)
                }
                .frame(maxWidth: .infinity)
            case .unavailable:
                Text("Price history isn’t available yet.")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 64)
            case .failed:
                VStack(spacing: 4) {
                    Text("Couldn’t load price history").font(.subheadline)
                    if let error {
                        Text(error).font(.caption).multilineTextAlignment(.center)
                    }
                    Button("Retry", action: retry).foregroundStyle(.tint).frame(minHeight: 44)
                }
                .frame(maxWidth: .infinity)
            }

            if hasHistory {
                CardDetailRangeSelector(selection: range, direction: direction) { range = $0; selection = nil }
                HStack(spacing: 8) {
                    Text(model.samples.count > 1 ? "JustTCG · Drag to explore" : "JustTCG price history")
                    Spacer(minLength: 0)
                    if isLoading {
                        ProgressView().controlSize(.mini).accessibilityLabel("Updating price history")
                    }
                }
                .font(.caption).padding(.horizontal, 16)
                if !isLoading, error != nil {
                    HStack {
                        Text("Showing saved history. Couldn’t update.").font(.caption)
                        Button("Retry", action: retry).font(.subheadline).foregroundStyle(.tint).frame(minHeight: 44)
                    }
                    .padding(.horizontal, 16)
                }
            }
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func showAllHistory() {
        selection = nil
        range = .all
    }
}

private struct MarketHistoryExplanation: View {
    let points: [JustTCGHistoryPoint]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("History is provided by JustTCG for this printing and may differ from the current quote. It includes prices from before you added the card.")
            if let latest = points.last {
                Text("Latest history point · \(Date(timeIntervalSince1970: latest.t).formatted(date: .abbreviated, time: .shortened))")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
enum CardMarketHistoryFixture {
    static func markReady() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-ui_debug_ready_path"),
              arguments.indices.contains(index + 1) else { return }
        try? Data(#"{"marketHistoryReady":true}"#.utf8)
            .write(to: URL(fileURLWithPath: arguments[index + 1]), options: .atomic)
    }

    static var points: [JustTCGHistoryPoint] {
        let today = Calendar(identifier: .gregorian).startOfDay(for: .now)
        return (0..<365).map { (index: Int) -> JustTCGHistoryPoint in
            let trend: Double = 32.0 - Double(index) * 0.018
            let wave: Double = sin(Double(index) / 15.0) * 2.2
            let timestamp = today.addingTimeInterval(Double(index - 364) * 86_400.0).timeIntervalSince1970
            return JustTCGHistoryPoint(p: trend + wave, t: timestamp)
        }
    }
}
#endif

struct PriceHistoryChartView: View {
    let model: PriceHistoryChartModel
    let currencyCode: String
    let direction: CardDetailMovementDisplay.Direction
    @Binding var selectedDate: Date?
    @GestureState private var isScrubbing = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.isPlotRangeFitted && !model.isProviderHistory {
                Text("Fitted to available data")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .accessibilityLabel(
                        "Chart fitted to available data"
                    )
            }

            if model.samples.isEmpty {
                Label("No market history available", systemImage: "chart.xyaxis.line")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 174)
                Text("Historical prices appear here when JustTCG provides data for this exact printing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 32)
            } else if model.observationCount == 1,
                      let sample = model.samples.first(where: { $0.isObservation }) {
                CardDetailSinglePricePoint(
                    sample: sample,
                    currencyCode: currencyCode
                )
            } else {
                // Evaluate the full-series scale once, outside all mark loops.
                let yDomain = model.yDomain
                Chart {
                    ForEach(model.segments) { segment in
                        if segment.samples.count > 1 {
                            ForEach(segment.samples) { sample in
                                AreaMark(
                                    x: .value("Date", sample.date),
                                    yStart: .value("Floor", yDomain.lowerBound),
                                    yEnd: .value("Unit price", sample.amount.doubleValue),
                                    series: .value("Known span area", segment.id)
                                )
                                .interpolationMethod(.linear)
                                .foregroundStyle(areaGradient)

                                LineMark(
                                    x: .value("Date", sample.date),
                                    y: .value("Unit price", sample.amount.doubleValue),
                                    series: .value("Known span", segment.id)
                                )
                                .interpolationMethod(.linear)
                                .foregroundStyle(lineColor)
                                .lineStyle(
                                    StrokeStyle(
                                        lineWidth: 2.2,
                                        lineCap: .round,
                                        lineJoin: .round
                                    )
                                )
                            }
                        }
                    }

                    ForEach(model.samples) { sample in
                        PointMark(
                            x: .value("Date", sample.date),
                            y: .value("Unit price", sample.amount.doubleValue)
                        )
                        .foregroundStyle(sample.kind?.chartLabel == nil ? lineColor : .orange)
                        .symbolSize(model.isProviderHistory ? 0 : (sample.isObservation ? 18 : 0))
                        .annotation(position: .top, alignment: .leading) {
                            if let label = sample.annotationLabel {
                                Text(label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }

                    if let selectedDate {
                        RuleMark(x: .value("Selected date", selectedDate))
                            .foregroundStyle(.secondary)
                            .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        if let sample = model.sample(at: selectedDate) {
                            PointMark(
                                x: .value("Selected date", sample.date),
                                y: .value("Recorded unit price", sample.amount.doubleValue)
                            )
                            .foregroundStyle(.primary)
                            .symbolSize(64)
                        }
                    }
                }
                .chartXScale(domain: model.plotRange)
                .chartYScale(domain: yDomain)
                .chartYAxis {
                    AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                        AxisGridLine()
                            .foregroundStyle(.secondary.opacity(0.15))
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(amount.formatted(.currency(code: currencyCode).precision(.fractionLength(2))))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .chartXAxis(.hidden)
                .chartLegend(.hidden)
                .chartOverlay { proxy in
                    GeometryReader { geometry in
                        if let anchor = proxy.plotFrame {
                            let frame = geometry[anchor]
                            Rectangle()
                                .fill(.clear)
                                .contentShape(Rectangle())
                                .simultaneousGesture(
                                    DragGesture(minimumDistance: 8)
                                        .updating($isScrubbing) { _, state, _ in state = true }
                                        .onChanged { gesture in
                                            guard abs(gesture.translation.width) > abs(gesture.translation.height),
                                                  frame.height > 0 else { return }
                                            let x = min(max(gesture.location.x - frame.minX, 0), frame.width)
                                            selectedDate = proxy.value(atX: x, as: Date.self)
                                        }
                                        .onEnded { _ in selectedDate = nil }
                                )
                        }
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: dynamicTypeSize.isAccessibilitySize ? 240 : 196)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Unit price history")
                .accessibilityValue(selectedDate.map { date in
                    model.sample(at: date).map {
                        "\($0.amount.formatted(currencyCode: currencyCode)), \($0.date.formatted(date: .abbreviated, time: .shortened))"
                    } ?? "Not checked, \(date.formatted(date: .abbreviated, time: .omitted))"
                } ?? model.summary)
                .accessibilityHint("Drag horizontally to explore historical market prices. Lines connect provider observations.")
                .accessibilityAdjustableAction { direction in
                    let index = selectedDate.flatMap { date in model.samples.lastIndex(where: { $0.date <= date }) }
                    let next = direction == .increment
                        ? min((index ?? -1) + 1, model.samples.count - 1)
                        : max((index ?? model.samples.count) - 1, 0)
                    selectedDate = model.samples[next].date
                }
            }

            if let first = model.samples.first?.date,
               let last = model.samples.last?.date {
                HStack {
                    Text(contextLabel(for: first))
                    Spacer()
                    Text(contextLabel(for: last))
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: isScrubbing) { _, active in
            if !active { selectedDate = nil }
        }
        .onChange(of: model.samples) { _, _ in selectedDate = nil }
        .onDisappear { selectedDate = nil }
        .accessibilityAction(named: Text("Show current price")) { selectedDate = nil }
    }

    private var lineColor: Color {
        switch direction {
        case .positive: return PortfolioPalette.gain
        case .negative: return PortfolioPalette.loss
        case .flat: return .secondary
        }
    }

    private var areaGradient: LinearGradient {
        LinearGradient(
            colors: [
                lineColor.opacity(0.20),
                lineColor.opacity(0.07),
                lineColor.opacity(0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private func contextLabel(for date: Date) -> String {
        Calendar.current.isDateInToday(date)
            ? "today"
            : date.formatted(date: .abbreviated, time: .omitted)
    }
}

private struct CardDetailSinglePricePoint: View {
    let sample: PriceHistorySample
    let currencyCode: String

    var body: some View {
        VStack(alignment: .center, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(sample.kind?.chartLabel == nil ? PortfolioPalette.money : .orange)
                    .frame(width: 9, height: 9)
                Text(sample.amount.formatted(currencyCode: currencyCode))
                    .font(.title2.weight(.semibold).monospacedDigit())
            }
            .frame(maxWidth: .infinity)
            Text("Market price · \(sample.date.formatted(date: .abbreviated, time: .omitted))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let annotationLabel = sample.annotationLabel {
                Text(annotationLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            } else {
                Text("JustTCG has one price available for this period.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 174)
        .multilineTextAlignment(.center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("One recorded unit price")
        .accessibilityValue("\(sample.amount.formatted(currencyCode: currencyCode)), \(sample.date.formatted(date: .abbreviated, time: .shortened))")
    }
}

struct MovementDetailsView: View {
    let card: CollectedCard
    let price: PriceDisplay
    @ObservedObject var history: PortfolioHistoryStore
    let quantity: Int?

    init(
        card: CollectedCard,
        price: PriceDisplay,
        history: PortfolioHistoryStore,
        quantity: Int? = nil
    ) {
        self.card = card
        self.price = price
        self.history = history
        self.quantity = quantity
    }

    private var state: PortfolioCardMovementState {
        history.movementState(for: card.collectionKey)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(card.name)
                        .font(.title2.bold())
                    Text("Market movement · \(history.range.rawValue)")
                        .foregroundStyle(.secondary)
                }

                positionSection
                calculationSection
                guidanceSection
            }
            .padding(20)
            .contentWidthLimit(.standard)
        }
        .navigationTitle("Movement Details")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var positionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Current position")
                .font(.headline)
            LabeledContent("Unit price", value: currentUnitPrice)
            LabeledContent("Quantity", value: "\(displayedQuantity)")
            LabeledContent("Holding value", value: currentHoldingValue)
        }
        .font(.subheadline)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    @ViewBuilder
    private var calculationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Selected period")
                .font(.headline)

            switch state {
            case .historyRecording:
                Text("History is being recorded. Movement details will appear after enough portfolio history is available.")
                    .foregroundStyle(.secondary)
            case .noRecordedMarketMovement:
                Text("No recorded market movement for this card during \(history.range.rawValue).")
                    .foregroundStyle(.secondary)
            case let .recorded(detail):
                LabeledContent("Holding impact", value: signed(detail.totalImpact))
                if detail.hasConsistentQuantity,
                   let quantity = detail.affectedQuantities.first {
                    LabeledContent("Cumulative unit movement", value: signed(detail.cumulativeUnitMovement))
                    LabeledContent("Affected quantity", value: "\(quantity)")
                    Text("\(signed(detail.cumulativeUnitMovement)) per card × \(quantity) = \(signed(detail.totalImpact))")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(PortfolioPalette.direction(detail.totalImpact))
                } else if detail.affectedQuantities.count > 1 {
                    Text("Different quantities were affected")
                        .foregroundStyle(.secondary)
                    LabeledContent("Cumulative unit movement", value: signed(detail.cumulativeUnitMovement))
                } else {
                    Text("The total is available, but an exact per-card calculation is not.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .font(.subheadline)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var guidanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Included movement", systemImage: "checkmark.circle")
                .font(.headline)
            Text("Price changes recorded while this card was owned are included. Additions, removals, corrections, newly priced cards, and re-sourced values are excluded.")
                .foregroundStyle(.secondary)
            Text("Per-card figures cover locally observed updates while owned; they do not claim price history from before tracking began.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var currentUnitPrice: String {
        guard let amount = price.amount else { return "Unavailable" }
        return amount.formatted(.currency(code: price.currencyCode))
    }

    private var currentHoldingValue: String {
        guard let amount = price.amount else { return "Unavailable" }
        return (amount * Double(displayedQuantity)).formatted(.currency(code: price.currencyCode))
    }

    private var displayedQuantity: Int {
        quantity ?? card.quantity
    }

    private func signed(_ amount: Money) -> String {
        PortfolioHistoryDisplay.signedCurrency(amount)
    }
}

/// Everything needed to restore a removed row without another catalog request.
/// The value safely outlives the deleted SwiftData model.
struct ArtworkAccent: Equatable, Sendable {
    let red: Double
    let green: Double
    let blue: Double

    var color: Color {
        Color(red: red, green: green, blue: blue)
    }
}

enum ArtworkAccentExtractor {
    private static let context = CIContext()

    /// Reduce the artwork to one stable accent outside of `body`. A cropped
    /// area average ignores the card edge and the usual white border, so the
    /// detail backdrop follows the subject rather than turning every card gray.
    static func make(from image: UIImage) -> ArtworkAccent? {
        guard let cgImage = image.cgImage else { return nil }
        let input = CIImage(cgImage: cgImage)
        let insetX = input.extent.width * 0.08
        let insetY = input.extent.height * 0.08
        let sampleRect = input.extent.insetBy(dx: insetX, dy: insetY)
        guard !sampleRect.isEmpty,
              let filter = CIFilter(name: "CIAreaAverage") else { return nil }

        filter.setValue(input, forKey: kCIInputImageKey)
        filter.setValue(CIVector(cgRect: sampleRect), forKey: kCIInputExtentKey)
        guard let output = filter.outputImage else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        context.render(
            output,
            toBitmap: &pixel,
            rowBytes: 4,
            bounds: CGRect(x: 0, y: 0, width: 1, height: 1),
            format: .RGBA8,
            colorSpace: CGColorSpaceCreateDeviceRGB()
        )
        return ArtworkAccent(
            red: Double(pixel[0]) / 255,
            green: Double(pixel[1]) / 255,
            blue: Double(pixel[2]) / 255
        )
    }
}

enum ArtworkAccentStore {
    private static let samplingPixelDimension = 128
    private final class Box: NSObject {
        let value: ArtworkAccent

        init(_ value: ArtworkAccent) {
            self.value = value
        }
    }

    private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 2_000
        return cache
    }()

    /// Projection can reuse a local accent that was already decoded without
    /// doing asynchronous work while it is flattening the collection. Remote
    /// sources still use `accent(localFilename:remoteURL:)` from the tile or
    /// detail task.
    static func cachedAccent(localFilename: String?) -> ArtworkAccent? {
        guard let localFilename, !localFilename.isEmpty else { return nil }
        let key = "local:\(localFilename)" as NSString
        if let cached = cache.object(forKey: key)?.value {
            return cached
        }
        return nil
    }

    /// The image view keeps its existing `AsyncImage` behavior. This companion
    /// task has a separate, keyed color cache so accent extraction happens once
    /// per artwork source and never as part of a SwiftUI body evaluation.
    static func accent(
        localFilename: String?,
        remoteURL: URL?,
        fallbackRemoteURL: URL? = nil
    ) async -> ArtworkAccent? {
        let effectiveLocalFilename = localFilename?.isEmpty == false ? localFilename : nil
        let localKey = effectiveLocalFilename.map { "local:\($0)" }
        var remoteURLs: [URL] = []
        for url in [remoteURL, fallbackRemoteURL].compactMap({ $0 }) {
            guard !remoteURLs.contains(url) else { continue }
            remoteURLs.append(url)
        }
        let remoteKeys = remoteURLs.map { "remote:\($0.absoluteString)" }

        guard localKey != nil || !remoteURLs.isEmpty else {
            return nil
        }

        var cacheKeys = remoteKeys
        if let localKey {
            cacheKeys.insert(localKey, at: 0)
        }
        for cacheKey in cacheKeys {
            if let cached = cache.object(forKey: cacheKey as NSString)?.value {
                return cached
            }
        }

        var selectedImage: UIImage?
        var selectedKey: String?
        let localImage: UIImage? = if let effectiveLocalFilename {
            await Task.detached(priority: .utility) {
                CollectionArtworkStore.image(
                    filename: effectiveLocalFilename,
                    maximumPixelDimension: samplingPixelDimension
                )
            }.value
        } else { nil }
        if let localImage, let localKey {
            selectedImage = localImage
            selectedKey = localKey
        } else {
            for (url, key) in zip(remoteURLs, remoteKeys) {
                if let remoteImage = try? await CatalogImageCache.shared.image(
                    for: url,
                    targetPixelSize: samplingPixelDimension
                ) {
                    selectedImage = remoteImage
                    selectedKey = key
                    break
                }
            }
        }

        guard let selectedImage, let selectedKey else { return nil }
        let accent = await Task.detached(priority: .utility) {
            ArtworkAccentExtractor.make(from: selectedImage)
        }.value
        if let accent {
            cache.setObject(Box(accent), forKey: selectedKey as NSString)
        }
        return accent
    }
}

enum CollectionArtworkStore {
    /// A detail hero is the largest consumer of a local artwork image. Keeping
    /// the stored derivative below this bound still gives a sharp 3x image on
    /// current iPhones while preventing a camera-roll original from becoming a
    /// multi-hundred-megabyte decoded tile cache entry.
    static let maximumPixelDimension = 1_600

    private static var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CollectionArtwork", isDirectory: true)
    }

    /// Decoded artwork, kept in memory because the collection grid asks for it
    /// from inside `body`: every tile pass was re-reading and re-decompressing
    /// the file on the main thread, and scrolling back over a tile paid for it
    /// again. The ordinary `save` call mints a fresh UUID filename for every
    /// write, so an entry can never go stale under its key. Deterministic
    /// fixtures may pass a filename, which replaces that file and clears the
    /// decoded cache before it is read again.
    private static let imageCache: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.countLimit = 60
        cache.totalCostLimit = 48 * 1024 * 1024
        return cache
    }()

    static func filename(
        for collectionKey: String,
        legacyFilename: String?,
        in context: ModelContext
    ) -> String? {
        do {
            let rows = try context.fetch(
                FetchDescriptor<LocalArtworkOverride>(
                    predicate: #Predicate { $0.collectionKey == collectionKey },
                    sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
                )
            )
            if let row = rows.first {
                return row.filename.isEmpty ? nil : row.filename
            }
            // Legacy values remain readable until launch migration has moved
            // them. Do not cache that fallback because the synced bridge field
            // can be cleared by the caller during the same session.
            if let legacyFilename, !legacyFilename.isEmpty { return legacyFilename }
            return nil
        } catch {
            return legacyFilename
        }
    }

    static func set(filename: String?, for collectionKey: String, in context: ModelContext,
                    suppressLegacyFallback: Bool = false) throws {
        let rows = try context.fetch(
            FetchDescriptor<LocalArtworkOverride>(
                predicate: #Predicate { $0.collectionKey == collectionKey }
            )
        )
        if let filename, !filename.isEmpty {
            let override = rows.first ?? LocalArtworkOverride(collectionKey: collectionKey, filename: filename)
            override.filename = filename
            override.updatedAt = .now
            if rows.isEmpty { context.insert(override) }
        } else if suppressLegacyFallback {
            let override = rows.first ?? LocalArtworkOverride(collectionKey: collectionKey, filename: "")
            override.filename = ""
            override.updatedAt = .now
            if rows.isEmpty { context.insert(override) }
        } else {
            for row in rows { context.delete(row) }
        }
    }

    /// Move legacy synced filenames into the local mapping before any screen
    /// reads them. The old model field remains in the schema only so existing
    /// stores can migrate safely; it is cleared after the local copy exists.
    static func migrateLegacyMappings(in context: ModelContext) throws {
        var legacyDescriptor = FetchDescriptor<CollectedCard>(
            predicate: #Predicate { $0.userArtworkFilename != nil }
        )
        legacyDescriptor.sortBy = [
            SortDescriptor(\CollectedCard.collectionKey, order: .forward),
            SortDescriptor(\CollectedCard.dateAdded, order: .forward)
        ]
        let legacyCards = try context.fetch(legacyDescriptor)
            .filter { $0.userArtworkFilename?.isEmpty == false }
            .sorted {
                if $0.collectionKey != $1.collectionKey { return $0.collectionKey < $1.collectionKey }
                if $0.dateAdded != $1.dateAdded { return $0.dateAdded < $1.dateAdded }
                return ($0.userArtworkFilename ?? "") < ($1.userArtworkFilename ?? "")
            }
        guard !legacyCards.isEmpty else { return }

        let overrides = try context.fetch(FetchDescriptor<LocalArtworkOverride>())
        var keysWithOverrides = Set(overrides.map(\.collectionKey))

        var changed = false
        for card in legacyCards {
            guard CollectionStore(context: context).permitsSyncedMetadataWrite(for: card) else { continue }
            if !keysWithOverrides.contains(card.collectionKey),
               let filename = card.userArtworkFilename,
               !filename.isEmpty {
                context.insert(LocalArtworkOverride(collectionKey: card.collectionKey, filename: filename))
                keysWithOverrides.insert(card.collectionKey)
            }
            card.userArtworkFilename = nil
            changed = true
        }
        guard changed else { return }
        try CollectionStore(context: context).validatePendingGameWrites()
        try context.save()
    }

    static func save(_ data: Data, filename requestedFilename: String? = nil) -> String? {
        let filename = requestedFilename ?? (UUID().uuidString + ".image")
        guard !filename.isEmpty,
              filename != ".",
              filename != "..",
              URL(fileURLWithPath: filename).lastPathComponent == filename,
              let normalized = normalizedData(from: data),
              let directory else { return nil }
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try normalized.write(to: directory.appendingPathComponent(filename), options: .atomic)
            if requestedFilename != nil { imageCache.removeAllObjects() }
            return filename
        } catch {
            return nil
        }
    }

    static func image(
        filename: String?,
        maximumPixelDimension: Int = Self.maximumPixelDimension
    ) -> UIImage? {
        guard let filename, let directory else { return nil }
        let targetPixelSize = min(max(maximumPixelDimension, 1), Self.maximumPixelDimension)
        let cacheKey = "\(filename)#pixel=\(targetPixelSize)" as NSString
        if let cached = imageCache.object(forKey: cacheKey) { return cached }
        let fileURL = directory.appendingPathComponent(filename)
        guard let source = CGImageSourceCreateWithURL(fileURL as CFURL, nil),
              let image = downsampledImage(
                from: source,
                targetPixelSize: targetPixelSize
              ) else { return nil }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        imageCache.setObject(image, forKey: cacheKey, cost: cost)
        return image
    }

    private static func normalizedData(from data: Data) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = downsampledImage(from: source) else { return nil }
        return image.pngData()
    }

    private static func downsampledImage(
        from source: CGImageSource,
        targetPixelSize: Int = maximumPixelDimension
    ) -> UIImage? {
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: targetPixelSize
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(
            source,
            0,
            options as CFDictionary
        ) else { return nil }
        return UIImage(cgImage: image)
    }

    static func remove(filename: String?) {
        guard let filename, let directory else { return }
        // The cache is keyed by derivative size. Removing all derivatives for
        // one filename keeps an arbitrary caller-provided size from surviving
        // after the backing file is deleted.
        imageCache.removeAllObjects()
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
    }

    /// A partial quantity correction can legitimately map two collection keys
    /// to the same local image. Delete the file only after the row being changed
    /// has been saved and no remaining override points at it.
    @discardableResult
    static func removeIfUnreferenced(_ filename: String?, in context: ModelContext) -> Bool {
        guard let filename, !filename.isEmpty else { return true }
        do {
            let references = try context.fetchCount(
                FetchDescriptor<LocalArtworkOverride>(
                    predicate: #Predicate { $0.filename == filename }
                )
            )
            let legacyReferences = try context.fetchCount(
                FetchDescriptor<CollectedCard>(
                    predicate: #Predicate { $0.userArtworkFilename == filename }
                )
            )
            guard references == 0, legacyReferences == 0 else { return true }
            remove(filename: filename)
            return true
        } catch {
            // Keeping an orphan is safer than deleting a file while a reference
            // may still exist. Rekey cleanup retries this after a later save.
            return false
        }
    }

    /// Enumerates the artwork directory without holding the collection writer.
    static func agedFilenames(olderThan cutoff: Date) -> Set<String> {
        guard let directory,
              let urls = try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else { return [] }
        return Set(urls.compactMap { url in
            guard let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .contentModificationDateKey]
            ),
                  values.isRegularFile == true,
                  let modifiedAt = values.contentModificationDate,
                  modifiedAt < cutoff else { return nil }
            return url.lastPathComponent
        })
    }

    /// Removes a previously validated set of candidates after the model write
    /// has released `CollectionWriteSerializer`.
    @discardableResult
    static func removeFiles(named filenames: Set<String>) -> Int {
        guard let directory, !filenames.isEmpty else { return 0 }
        imageCache.removeAllObjects()
        return filenames.reduce(into: 0) { removed, filename in
            guard !filename.isEmpty,
                  filename != ".",
                  filename != "..",
                  URL(fileURLWithPath: filename).lastPathComponent == filename else { return }
            do {
                try FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
                removed += 1
            } catch {
                // A failed deletion is safe and will be retried by the next
                // store-ready sweep.
            }
        }
    }
}
