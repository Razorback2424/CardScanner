import PhotosUI
import Charts
import CoreMotion
import SwiftData
import SwiftUI
import UIKit

struct CollectionCardDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Bindable var card: CollectedCard
    @Query private var priceObservations: [PriceObservation]
    @Query private var priceCheckDays: [PriceCheckDay]
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

    @State private var isConfirmingRemoval = false
    @State private var selectedArtwork: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var artworkGeneration = 0
    @State private var pendingArtwork: ArtworkRequest?

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
        onRemoved: @escaping (RemovedCardSnapshot) -> Void
    ) {
        let resolvedInstrumentKey = instrumentKey ?? card.priceKey
        self._card = Bindable(card)
        self._priceObservations = Query(
            filter: #Predicate<PriceObservation> { $0.instrumentKey == resolvedInstrumentKey },
            sort: [SortDescriptor(\PriceObservation.receivedAt, order: .forward)]
        )
        self._priceCheckDays = Query(
            filter: #Predicate<PriceCheckDay> { $0.instrumentKey == resolvedInstrumentKey },
            sort: [SortDescriptor(\PriceCheckDay.portfolioDay, order: .forward)]
        )
        self.price = price
        self.history = history
        self.unpricedReason = unpricedReason
        self.artworkReason = artworkReason
        self.logicalQuantity = logicalQuantity
        self.isLogicalConflict = isLogicalConflict
        self.priceHistoryInstrumentKey = resolvedInstrumentKey
        self.onRemoved = onRemoved
    }

    var body: some View {
        ZStack {
            AppCardDetailBackdrop()
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: true) {
                VStack(spacing: 0) {
                    heroSection

                    VStack(alignment: .leading, spacing: 24) {
                        identityBlock
                        priceMovementBlock

                        if isLogicalConflict {
                            conflictNotice
                        }

                        actionStrip
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 24)
                    .contentWidthLimit(.standard)
                }
            }
            .coordinateSpace(name: "CardDetailScroll")
        }
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
        // The detail destination is a focused surface. Leaving the collection
        // tab bar visible puts it over the identity block at the hero's resting
        // height, clipping the card name before the user can scroll.
        .toolbar(.hidden, for: .tabBar)
        .task(id: card.catalogProviderID ?? card.providerID) {
            await loadMarketplaceLinkIfNeeded()
        }
        .task(id: pendingArtwork?.id) {
            guard let request = pendingArtwork else { return }
            await saveSelectedArtwork(request.item, requestID: request.id)
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
        .confirmationDialog(
            "Remove \(card.name)?",
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                removeCard()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(removalMessage)
        }
    }

    @ViewBuilder
    private var artworkMenu: some View {
        Menu {
            PhotosPicker(selection: $selectedArtwork, matching: .images) {
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
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .padding(4)
                .background(.black.opacity(0.55), in: Circle())
        }
        .accessibilityLabel("Artwork actions")
        .accessibilityHint("Choose a personal photo, replace it, or return to catalog artwork.")
        .onChange(of: selectedArtwork) { _, item in
            guard let item else { return }
            artworkGeneration &+= 1
            pendingArtwork = ArtworkRequest(id: artworkGeneration, item: item)
        }
    }

    private var heroSection: some View {
        let movementEnabled = !reduceMotion
        return ZStack(alignment: .bottom) {
            artwork
                .overlay(alignment: .topTrailing) {
                    artworkMenu
                        .padding(12)
                }
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

            LinearGradient(
                colors: [.clear, .black.opacity(reduceTransparency ? 0 : 0.18)],
                startPoint: .center,
                endPoint: .bottom
            )
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(0.716, contentMode: .fit)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Artwork for \(card.name)")
    }

    private var identityBlock: some View {
        AppCardSurface {
            VStack(alignment: .leading, spacing: 10) {
                Text(card.name)
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(card.setName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)

                Text([card.setCode, card.cardNumber]
                    .filter { !$0.isEmpty }
                    .joined(separator: "  ·  "))
                    .font(.headline.monospacedDigit())

                if let rarity = card.rarity, !rarity.isEmpty {
                    Text(rarity)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                identityBadges
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var identityBadges: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 8) {
                AppCardBadge(
                    text: card.variant?.label ?? "Finish unknown",
                    systemImage: "sparkles",
                    tint: .teal
                )

                if let printRun = card.pokemonPrintRun {
                    AppCardBadge(text: printRun.label, systemImage: "number", tint: .orange)
                }

                if card.itemKind != .rawCard {
                    AppCardBadge(
                        text: card.itemKindLabel,
                        systemImage: card.itemKind.symbolName,
                        tint: .indigo
                    )
                }

                if let gradingCompany = card.gradingCompany {
                    let grade = card.cardGrade?.display(company: gradingCompany) ?? card.gradeRaw
                    AppCardBadge(
                        text: grade.map { "\(gradingCompany.label) \($0)" } ?? gradingCompany.label,
                        systemImage: "checkmark.seal",
                        tint: .purple
                    )
                } else if let gradeRaw = card.gradeRaw {
                    AppCardBadge(text: gradeRaw, systemImage: "checkmark.seal", tint: .purple)
                }

                ForEach(card.displayedMagicTreatmentEvidence.treatments) { treatment in
                    AppCardBadge(text: treatment.label, systemImage: "wand.and.stars", tint: .pink)
                }
            }
        }
    }

    private var priceMovementBlock: some View {
        AppCardSurface {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    CardDetailPriceValue(price: price)
                    Spacer(minLength: 12)
                    Text("unit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let source = price.source, price.amount != nil {
                    Text(priceSourceDescription(source))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if price.refreshFailed {
                    Label("Last refresh failed", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Picker("Price history range", selection: Binding(
                    get: { history.range },
                    set: { history.range = $0 }
                )) {
                    ForEach(PortfolioHistoryRange.allCases, id: \.rawValue) { item in
                        Text(item.rawValue)
                            .accessibilityLabel(item.accessibilityName)
                            .tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityHint("Choose how much per-card price history to show.")

                PriceHistoryChartView(
                    observations: priceObservations,
                    checkDays: priceCheckDays,
                    currencyCode: price.currencyCode,
                    range: history.range
                )
                .accessibilityIdentifier("price-history-\(priceHistoryInstrumentKey)")

                movementSummary

                if let unpricedReason, price.amount == nil {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(unpricedReason.title, systemImage: "exclamationmark.circle")
                            .font(.subheadline.weight(.semibold))
                        Text(unpricedReason.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("Diagnostic: \(unpricedReason.rawValue)")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Price and market movement")
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
    private var actionStrip: some View {
        HStack(spacing: 0) {
            if let url = exactTCGPlayerPrintingURL {
                Link(destination: url) {
                    CardDetailActionLabel(title: "Market", systemImage: "cart")
                }
                .accessibilityLabel("Open this printing on TCGplayer")
                .frame(maxWidth: .infinity)

                Divider()
            }

            NavigationLink {
                CollectionCardHistoryView(
                    collectionKey: card.collectionKey,
                    cardName: card.name
                )
            } label: {
                CardDetailActionLabel(title: "History", systemImage: "clock.arrow.circlepath")
            }
            .frame(maxWidth: .infinity)

            Divider()

            Menu {
                Button {
                    updateQuantity(displayedQuantity - 1)
                } label: {
                    Label("Decrease quantity", systemImage: "minus")
                }
                .disabled(displayedQuantity <= 1)

                Button {
                    updateQuantity(displayedQuantity + 1)
                } label: {
                    Label("Increase quantity", systemImage: "plus")
                }

                Button("Remove from Collection", role: .destructive) {
                    isConfirmingRemoval = true
                }
            } label: {
                CardDetailActionLabel(
                    title: "Quantity ×\(displayedQuantity)",
                    systemImage: "number"
                )
            }
            .frame(maxWidth: .infinity)
        }
        .padding(6)
        .frame(minHeight: 52)
        .background(
            reduceTransparency
                ? AnyShapeStyle(Color(uiColor: .secondarySystemBackground))
                : AnyShapeStyle(.thinMaterial),
            in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.primary.opacity(0.08), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Card actions")
    }

    @ViewBuilder
    private var artwork: some View {
        ZStack {
            if let image = CollectionArtworkStore.image(filename: localArtworkFilename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else if let imageURL = card.highImageURL ?? card.lowImageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                    case .empty:
                        ProgressView()
                    case .failure:
                        missingArtworkPlaceholder
                    @unknown default:
                        missingArtworkPlaceholder
                    }
                }
            } else {
                // AsyncImage with a nil URL remains in .empty forever. End the
                // state explicitly so an unresolved catalog row is honest and
                // usable instead of presenting an infinite spinner.
                missingArtworkPlaceholder
            }

            CardFinishOverlay(
                variant: card.variant,
                resolution: card.variantResolution,
                treatments: card.displayedMagicTreatmentEvidence.treatments
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    }

    @MainActor
    private func saveSelectedArtwork(_ item: PhotosPickerItem, requestID: Int) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              requestID == artworkGeneration,
              !Task.isCancelled else {
            if requestID == artworkGeneration { selectedArtwork = nil }
            return
        }
        guard let filename = CollectionArtworkStore.save(data) else {
            // Clear the picker binding on a rejected/undecodable asset so the
            // user can choose the same photo again after correcting the issue.
            selectedArtwork = nil
            return
        }
        guard requestID == artworkGeneration, !Task.isCancelled else {
            CollectionArtworkStore.remove(filename: filename)
            return
        }
        let oldFilename = localArtworkFilename
        CollectionArtworkStore.set(
            filename: filename,
            for: card.collectionKey,
            in: modelContext
        )
        // Kept only as a migration bridge for stores written before local
        // artwork ownership existed. New writes never publish a device-local
        // file reference through the synced card row.
        card.userArtworkFilename = nil
        do {
            try modelContext.save()
            CollectionArtworkStore.remove(filename: oldFilename)
            if requestID == artworkGeneration {
                selectedArtwork = nil
            }
        } catch {
            CollectionArtworkStore.set(
                filename: oldFilename,
                for: card.collectionKey,
                in: modelContext
            )
            CollectionArtworkStore.remove(filename: filename)
            errorMessage = error.localizedDescription
            if requestID == artworkGeneration { selectedArtwork = nil }
        }
    }

    private func removeUserArtwork() {
        artworkGeneration &+= 1
        let oldFilename = localArtworkFilename
        CollectionArtworkStore.set(
            filename: nil,
            for: card.collectionKey,
            in: modelContext
        )
        card.userArtworkFilename = nil
        do {
            try modelContext.save()
            CollectionArtworkStore.remove(filename: oldFilename)
        } catch {
            CollectionArtworkStore.set(
                filename: oldFilename,
                for: card.collectionKey,
                in: modelContext
            )
            errorMessage = error.localizedDescription
        }
    }

    private var localArtworkFilename: String? {
        CollectionArtworkStore.filename(
            for: card.collectionKey,
            legacyFilename: card.userArtworkFilename,
            in: modelContext
        )
    }

    private var removalMessage: String {
        if displayedQuantity == 1 {
            return "This removes the card. You can undo it."
        }
        return "This removes all \(displayedQuantity) copies. You can undo it."
    }

    private var displayedQuantity: Int {
        // The projected quantity is authoritative while duplicate rows are
        // being healed. Recompute it from the query rather than retaining the
        // route-time snapshot: the first Stepper tap merges the physical rows,
        // and the next tap must start from the merged quantity.
        guard isLogicalConflict else { return card.quantity }
        let cards = (try? modelContext.fetch(FetchDescriptor<CollectedCard>())) ?? []
        let projection = LogicalCollection.project(cards: cards) { $0.priceKey }
        return projection.byKey[card.collectionKey]?.quantity
            ?? logicalQuantity
            ?? card.quantity
    }

    private func updateQuantity(_ newQuantity: Int) {
        guard (1...999).contains(newQuantity) else { return }
        do {
            try CollectionStore(context: modelContext).setQuantity(
                newQuantity,
                for: card
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeCard() {
        // Deleting the row from here is what made removals invisible to
        // history. Ownership changes go through the store, which is the only
        // thing that knows the ledger has to hear about them.
        do {
            let snapshot = try CollectionStore(context: modelContext).remove(card)
            onRemoved(snapshot)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    /// The price belongs to this printing *and* this finish. When the provider
    /// exposes nothing for the variant the user owns, the app says so instead of
    /// borrowing a different finish's number.
    private func priceSourceDescription(_ source: PriceSource) -> String {
        if source.publishesSourceTimestamp {
            return "\(source.label) · current as of \(price.effectiveAsOf?.formatted(date: .abbreviated, time: .shortened) ?? "unknown")"
        }
        return "\(source.label) · checked \(price.fetchedAt?.formatted(date: .abbreviated, time: .shortened) ?? "never")"
    }

    /// The compact, route-independent disclosure surface. Its state comes from
    /// the app-scoped history store rather than from the route that opened this
    /// card, so Portfolio and Collection always make the same claim.
    private var movementSummary: some View {
        NavigationLink {
            MovementDetailsView(
                card: card,
                price: price,
                history: history,
                quantity: displayedQuantity
            )
        } label: {
            PortfolioMovementSummaryCard(
                state: history.movementState(for: card.collectionKey),
                range: history.range
            )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
    }

    /// Scryfall's purchase URL identifies the exact Magic printing, but its URL
    /// does not promise a preselected finish. Say that plainly and never expose
    /// it for an unsupported or unknown finish.
    private var exactTCGPlayerPrintingURL: URL? {
        guard card.cardGame == .magic,
              let variantID = card.variantID,
              variantID == PhysicalVariant.nonfoil.id || variantID == PhysicalVariant.foil.id else {
            return nil
        }
        return TCGplayerLinkBuilder.url(for: card)
    }

    @MainActor
    private func loadMarketplaceLinkIfNeeded() async {
        guard card.cardGame == .magic,
              card.magicTreatmentIDsRaw.isEmpty,
              MagicTreatmentKeyCodec.collectionTreatmentIDs(from: card.collectionKey).isEmpty,
              card.tcgplayerURL == nil else { return }
        let providerID = card.catalogProviderID ?? card.providerID
        guard !providerID.hasPrefix("csv:") else { return }

        guard let resolved = try? await ScryfallService().fetchCard(id: providerID),
              !Task.isCancelled,
              let url = resolved.purchaseURIs?.tcgplayer else {
            return
        }
        card.tcgplayerURL = url.absoluteString
        try? modelContext.save()
    }
}

struct AppCardBadge: View {
    let text: String
    let systemImage: String?
    let tint: Color
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(text: String, systemImage: String? = nil, tint: Color = .accentColor) {
        self.text = text
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Group {
            if let systemImage {
                Label(text, systemImage: systemImage)
            } else {
                Text(text)
            }
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .lineLimit(2)
        .multilineTextAlignment(.leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background {
            if reduceTransparency {
                Capsule().fill(Color(uiColor: .secondarySystemBackground))
            } else {
                Capsule().fill(tint.opacity(0.15))
            }
        }
        .overlay {
            Capsule().stroke(tint.opacity(reduceTransparency ? 0.35 : 0.2), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
    }
}

struct AppCardSurface<Content: View>: View {
    private let content: Content
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background {
                if reduceTransparency {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemBackground))
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(.ultraThinMaterial)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct AppCardDetailBackdrop: View {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Color(uiColor: .systemBackground)
        } else {
            LinearGradient(
                colors: [
                    Color(uiColor: .systemBackground),
                    Color(uiColor: .secondarySystemBackground),
                    Color(uiColor: .systemBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }
}

private struct CardDetailActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .imageScale(.medium)
            Text(title)
                .font(.caption.weight(.semibold))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .contentShape(Rectangle())
    }
}

private struct CardDetailPriceValue: View {
    let price: PriceDisplay

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            switch price.state() {
            case .current:
                amount
            case .stale:
                amount
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
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
    }

    private var amount: some View {
        Text(price.amount ?? 0, format: .currency(code: price.currencyCode))
            .font(.system(.largeTitle, design: .rounded).weight(.bold))
            .monospacedDigit()
            .foregroundStyle(.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
    }

    private var accessibilityText: String {
        guard let amount = price.amount else {
            return price.state() == .unavailable ? "Price unavailable" : "Price not checked yet"
        }
        return amount.formatted(.currency(code: price.currencyCode))
    }
}

private struct CollectionCardHistoryView: View {
    @Query private var activities: [CollectionActivity]
    let cardName: String

    init(collectionKey: String, cardName: String) {
        self.cardName = cardName
        self._activities = Query(
            filter: #Predicate<CollectionActivity> { $0.collectionKey == collectionKey },
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
                            Image(systemName: activity.kind.symbolName)
                                .foregroundStyle(historyColor(for: activity.kind))
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(activity.kind.label)
                                    .font(.subheadline.weight(.semibold))
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
        case .quantityAdjusted: return .blue
        case .undone: return .purple
        }
    }
}

private final class CardFinishMotionModel: ObservableObject {
    @Published private(set) var offset: CGSize = .zero
    private let motionManager = CMMotionManager()
    private var isRunning = false

    func start() {
        guard !isRunning, motionManager.isDeviceMotionAvailable else { return }
        isRunning = true
        motionManager.deviceMotionUpdateInterval = 1 / 30
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let gravity = motion?.gravity else { return }
            let target = CGSize(
                width: max(-1, min(1, gravity.x)) * 12,
                height: max(-1, min(1, gravity.y)) * -12
            )
            self.offset = CGSize(
                width: self.offset.width * 0.84 + target.width * 0.16,
                height: self.offset.height * 0.84 + target.height * 0.16
            )
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        motionManager.stopDeviceMotionUpdates()
        offset = .zero
    }
}

/// A treatment-aware finish cue. It only appears for catalog-confirmed rows;
/// imported and catalog-silent rows remain visually plain so sheen never becomes
/// an unsupported identity claim. Motion is deliberately bounded and optional.
private struct CardFinishOverlay: View {
    let variant: PhysicalVariant?
    let resolution: VariantResolution?
    let treatments: [MagicTreatment]
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var motion = CardFinishMotionModel()

    private var isCatalogConfirmed: Bool {
        guard variant != nil, let resolution else { return false }
        return resolution != .catalogSilent && resolution != .imported
    }

    private var activeTreatment: MagicTreatment? {
        treatments.first
    }

    private var isFoilSurface: Bool {
        guard let variant else { return false }
        return variant.id == PhysicalVariant.holo.id || variant.id == PhysicalVariant.foil.id
    }

    var body: some View {
        Group {
            if isCatalogConfirmed, !reduceTransparency, let variant {
                GeometryReader { proxy in
                    ZStack {
                        if isFoilSurface {
                            RoundedRectangle(
                                cornerRadius: max(8, proxy.size.width * 0.035),
                                style: .continuous
                            )
                            .fill(
                                AngularGradient(
                                    colors: shimmerColors,
                                    center: .center
                                )
                            )
                            .frame(
                                width: proxy.size.width * 0.82,
                                height: proxy.size.height * 0.48
                            )
                            .position(
                                x: proxy.size.width / 2 + motion.offset.width * 0.3,
                                y: proxy.size.height * 0.37 + motion.offset.height * 0.3
                            )
                            .blendMode(.screen)
                            .opacity(activeTreatment == nil ? 0.72 : 0.84)
                        }

                        if variant.id == PhysicalVariant.reverse.id {
                            RoundedRectangle(
                                cornerRadius: max(8, proxy.size.width * 0.035),
                                style: .continuous
                            )
                            .stroke(
                                LinearGradient(
                                    colors: shimmerColors,
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: max(3, proxy.size.width * 0.018)
                            )
                            .padding(proxy.size.width * 0.025)
                            .blendMode(.screen)
                            .opacity(0.78)
                        }
                    }
                }
                .allowsHitTesting(false)
            }
        }
        .onAppear { updateMotion() }
        .onDisappear { motion.stop() }
        .onChange(of: reduceMotion) { _, _ in updateMotion() }
        .onChange(of: reduceTransparency) { _, _ in updateMotion() }
    }

    private var shimmerColors: [Color] {
        switch activeTreatment {
        case .surgeFoil:
            return [.white.opacity(0.08), .pink.opacity(0.42), .blue.opacity(0.38), .cyan.opacity(0.28), .white.opacity(0.08)]
        case .neonInk:
            return [.white.opacity(0.08), .pink.opacity(0.42), .orange.opacity(0.35), .green.opacity(0.34), .white.opacity(0.08)]
        case .unclassified:
            return [.white.opacity(0.08), .cyan.opacity(0.34), .purple.opacity(0.28), .yellow.opacity(0.22), .white.opacity(0.08)]
        case nil:
            return [.white.opacity(0.06), .cyan.opacity(0.28), .purple.opacity(0.24), .yellow.opacity(0.18), .white.opacity(0.06)]
        }
    }

    private func updateMotion() {
        if isCatalogConfirmed,
           !reduceMotion,
           !reduceTransparency,
           (isFoilSurface || variant?.id == PhysicalVariant.reverse.id) {
            motion.start()
        } else {
            motion.stop()
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
    let rangeStart: Date
    let rangeEnd: Date
    let samples: [PriceHistorySample]
    let segments: [PriceHistorySegment]
    let observationCount: Int
    let checkedDayCount: Int

    var hasGaps: Bool {
        segments.count > 1 && observationCount >= 2
    }

    var yDomain: ClosedRange<Double> {
        let values = samples.map { $0.amount.doubleValue }
        guard let minimum = values.min(), let maximum = values.max() else { return 0...1 }
        if minimum == maximum {
            let padding = max(abs(minimum) * 0.12, 0.5)
            return max(0, minimum - padding)...(maximum + padding)
        }
        let padding = max((maximum - minimum) * 0.12, 0.01)
        return max(0, minimum - padding)...(maximum + padding)
    }

    var summary: String {
        let observationLabel = observationCount == 1 ? "1 changed price" : "\(observationCount) changed prices"
        let checkLabel = checkedDayCount == 1 ? "1 checked day" : "\(checkedDayCount) checked days"
        return "\(observationLabel) across \(checkLabel)."
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

        return PriceHistoryChartModel(
            currencyCode: currencyCode,
            rangeStart: start,
            rangeEnd: end,
            samples: samples,
            segments: segments,
            observationCount: observationCount,
            checkedDayCount: checkedDaysInRange
        )
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

struct PriceHistoryChartView: View {
    let observations: [PriceObservation]
    let checkDays: [PriceCheckDay]
    let currencyCode: String
    let range: PortfolioHistoryRange

    private var model: PriceHistoryChartModel {
        PriceHistoryChartModel.make(
            observations: observations,
            checkDays: checkDays,
            currencyCode: currencyCode,
            range: range,
            now: .now,
            timeZone: PortfolioCalendar.pinnedTimeZone() ?? .current
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.samples.isEmpty {
                Label("History is being recorded", systemImage: "chart.xyaxis.line")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("Price history is recorded on this device. It will appear after the first successful check here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if model.observationCount == 1,
                      let sample = model.samples.first(where: { $0.isObservation }) {
                CardDetailSinglePricePoint(
                    sample: sample,
                    currencyCode: currencyCode
                )
            } else {
                Chart {
                    ForEach(model.segments) { segment in
                        if segment.samples.count > 1 {
                            ForEach(segment.samples) { sample in
                                LineMark(
                                    x: .value("Date", sample.date),
                                    y: .value("Unit price", sample.amount.doubleValue),
                                    series: .value("Known span", segment.id)
                                )
                                .interpolationMethod(.stepEnd)
                                .foregroundStyle(Color.accentColor)
                            }
                        }
                    }

                    ForEach(model.samples) { sample in
                        PointMark(
                            x: .value("Date", sample.date),
                            y: .value("Unit price", sample.amount.doubleValue)
                        )
                        .foregroundStyle(sample.kind?.chartLabel == nil ? Color.accentColor : .orange)
                        .symbolSize(sample.isObservation ? 42 : 18)
                        .annotation(position: .top, alignment: .leading) {
                            if let label = sample.annotationLabel {
                                Text(label)
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                .chartXScale(domain: model.rangeStart...model.rangeEnd)
                .chartYScale(domain: model.yDomain)
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine()
                        AxisTick()
                        AxisValueLabel {
                            if let amount = value.as(Double.self) {
                                Text(amount.formatted(.currency(code: currencyCode).precision(.fractionLength(0...2))))
                            }
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(values: .automatic(desiredCount: 4)) {
                        AxisGridLine()
                        AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    }
                }
                .frame(height: 210)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Unit price history")
                .accessibilityValue(model.summary)

                if model.observationCount < 2 {
                    Text("One changed price is shown as a point until another value is recorded.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if model.hasGaps {
                    Text("Gaps mean the app did not have a successful price check for that span.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text(model.summary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CardDetailSinglePricePoint: View {
    let sample: PriceHistorySample
    let currencyCode: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Circle()
                    .fill(sample.kind?.chartLabel == nil ? Color.accentColor : .orange)
                    .frame(width: 14, height: 14)
                Text(sample.amount.formatted(currencyCode: currencyCode))
                    .font(.title2.weight(.semibold).monospacedDigit())
                Spacer()
            }
            Text("First recorded price · \(sample.date.formatted(date: .abbreviated, time: .shortened))")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let annotationLabel = sample.annotationLabel {
                Text(annotationLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            } else {
                Text("A line appears after another changed price is recorded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.32), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("One recorded unit price")
        .accessibilityValue("\(sample.amount.formatted(currencyCode: currencyCode)), \(sample.date.formatted(date: .abbreviated, time: .shortened))")
    }
}

struct PortfolioMovementSummaryCard: View {
    let state: PortfolioCardMovementState
    let range: PortfolioHistoryRange

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Market movement · \(range.rawValue)")
                    .font(.subheadline.weight(.semibold))

                switch state {
                case .historyRecording:
                    Text("History is being recorded")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                case .noRecordedMarketMovement:
                    Text("No recorded market movement")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                case let .recorded(detail):
                    Text("\(signed(detail.totalImpact)) holding impact")
                        .font(.headline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(PortfolioPalette.direction(detail.totalImpact))
                    if let secondaryText = secondaryText(for: detail) {
                        Text(secondaryText)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Movement Details")
    }

    private func secondaryText(for detail: PortfolioContributionDetail) -> String? {
        if detail.hasConsistentQuantity,
           let quantity = detail.affectedQuantities.first,
           quantity > 1,
           !detail.cumulativeUnitMovement.isZero {
            return "\(signed(detail.cumulativeUnitMovement)) per card × \(quantity)"
        }
        if detail.affectedQuantities.count > 1 {
            return "Different quantities were affected"
        }
        return nil
    }

    private func signed(_ amount: Money) -> String {
        PortfolioHistoryDisplay.signedCurrency(amount)
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
enum CollectionArtworkStore {
    private static var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CollectionArtwork", isDirectory: true)
    }

    /// Decoded artwork, kept in memory because the collection grid asks for it
    /// from inside `body`: every tile pass was re-reading and re-decompressing
    /// the file on the main thread, and scrolling back over a tile paid for it
    /// again. `save` mints a fresh UUID filename for every write, so an entry
    /// can never go stale under its key and only deletion has to evict.
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
            if let filename = rows.first?.filename, !filename.isEmpty {
                return filename
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

    static func set(filename: String?, for collectionKey: String, in context: ModelContext) {
        do {
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
            } else {
                for row in rows { context.delete(row) }
            }
        } catch {
            // The caller's model save reports the durable failure. Keeping the
            // image file intact until that save succeeds makes this reversible.
        }
    }

    /// Move legacy synced filenames into the local mapping before any screen
    /// reads them. The old model field remains in the schema only so existing
    /// stores can migrate safely; it is cleared after the local copy exists.
    static func migrateLegacyMappings(in context: ModelContext) {
        do {
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
            try context.save()
        } catch {
            context.rollback()
        }
    }

    static func save(_ data: Data) -> String? {
        guard UIImage(data: data) != nil, let directory else { return nil }
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let filename = UUID().uuidString + ".image"
            try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
            return filename
        } catch {
            return nil
        }
    }

    static func image(filename: String?) -> UIImage? {
        guard let filename, let directory else { return nil }
        let cacheKey = filename as NSString
        if let cached = imageCache.object(forKey: cacheKey) { return cached }
        guard let image = UIImage(
            contentsOfFile: directory.appendingPathComponent(filename).path
        ) else { return nil }
        let cost = image.cgImage.map { $0.bytesPerRow * $0.height } ?? 0
        imageCache.setObject(image, forKey: cacheKey, cost: cost)
        return image
    }

    static func remove(filename: String?) {
        guard let filename, let directory else { return }
        imageCache.removeObject(forKey: filename as NSString)
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
    }
}
