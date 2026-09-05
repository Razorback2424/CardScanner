import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct CollectionCardDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var card: CollectedCard
    @Query private var collectionCards: [CollectedCard]
    @Query(sort: \CollectionActivity.occurredAt, order: .reverse)
    private var collectionActivities: [CollectionActivity]
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
        onRemoved: @escaping (RemovedCardSnapshot) -> Void
    ) {
        self._card = Bindable(card)
        self.price = price
        self.history = history
        self.unpricedReason = unpricedReason
        self.artworkReason = artworkReason
        self.logicalQuantity = logicalQuantity
        self.isLogicalConflict = isLogicalConflict
        self.onRemoved = onRemoved
    }

    var body: some View {
        ScrollView {
            // Side by side when the window can hold both columns, stacked when it
            // cannot. `ViewThatFits` asks the space rather than the device, so the
            // same view answers correctly at every window width without ever
            // consulting an idiom or an orientation. The `minWidth` is the
            // threshold: it is the width the two-column arrangement needs, not an
            // assumption about any particular screen.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 28) {
                    artworkColumn
                        .frame(maxWidth: 360)
                    detailsColumn
                        .frame(minWidth: 380, maxWidth: 440)
                }
                .frame(minWidth: 780)

                VStack(spacing: 20) {
                    artworkColumn
                    detailsColumn
                }
                .contentWidthLimit(.standard)
            }
            .padding(20)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Card")
        .navigationBarTitleDisplayMode(.inline)
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
    }

    @ViewBuilder
    private var artworkColumn: some View {
        VStack(spacing: 16) {
            artwork
                .frame(maxHeight: 460)
                .clipShape(RoundedRectangle(cornerRadius: 16))

            PhotosPicker(selection: $selectedArtwork, matching: .images) {
                Label(
                    card.userArtworkFilename == nil ? "Choose Photo" : "Replace Photo",
                    systemImage: "photo.badge.plus"
                )
            }
            .buttonStyle(.bordered)
            .onChange(of: selectedArtwork) { _, item in
                guard let item else { return }
                artworkGeneration &+= 1
                pendingArtwork = ArtworkRequest(id: artworkGeneration, item: item)
            }

            if card.userArtworkFilename != nil {
                Button("Use Catalog Artwork", role: .destructive) {
                    removeUserArtwork()
                }
                .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    private var detailsColumn: some View {
        VStack(spacing: 20) {
            VStack(spacing: 7) {
                Text(card.name)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text(card.setName)
                    .foregroundStyle(.secondary)
                if let printRun = card.pokemonPrintRun {
                    Text(printRun.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
                Text("\(card.setCode)  \(card.cardNumber)")
                    .font(.headline.monospacedDigit())
                if let rarity = card.rarity {
                    Text(rarity)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            pricing
            movementSummary
            finish
            treatment
            marketplaceLinks
            activityHistory

            if isLogicalConflict {
                Label(
                    "Multiple synced rows will be merged automatically when this position changes.",
                    systemImage: "arrow.triangle.merge"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Stepper(
                "Quantity: \(displayedQuantity)",
                value: Binding(
                    get: { displayedQuantity },
                    set: { newQuantity in
                        do {
                            try CollectionStore(context: modelContext).setQuantity(
                                newQuantity,
                                for: card
                            )
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                ),
                in: 1...999
            )
                .padding(.horizontal)

            Button("Remove from Collection", role: .destructive) {
                isConfirmingRemoval = true
            }
            .buttonStyle(.bordered)
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
    }

    @ViewBuilder
    private var artwork: some View {
        if let image = CollectionArtworkStore.image(filename: card.userArtworkFilename) {
            Image(uiImage: image).resizable().scaledToFit()
        } else {
            AsyncImage(url: card.highImageURL) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFit()
                case .empty:
                    ProgressView().frame(height: 410)
                case .failure:
                    missingArtworkPlaceholder
                @unknown default:
                    missingArtworkPlaceholder
                }
            }
        }
    }

    private var missingArtworkPlaceholder: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(.quaternary)
            .aspectRatio(0.727, contentMode: .fit)
            .overlay {
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
            }
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
        let oldFilename = card.userArtworkFilename
        card.userArtworkFilename = filename
        do {
            try modelContext.save()
            CollectionArtworkStore.remove(filename: oldFilename)
            if requestID == artworkGeneration {
                selectedArtwork = nil
            }
        } catch {
            card.userArtworkFilename = oldFilename
            CollectionArtworkStore.remove(filename: filename)
            errorMessage = error.localizedDescription
            if requestID == artworkGeneration { selectedArtwork = nil }
        }
    }

    private func removeUserArtwork() {
        artworkGeneration &+= 1
        let oldFilename = card.userArtworkFilename
        card.userArtworkFilename = nil
        do {
            try modelContext.save()
            CollectionArtworkStore.remove(filename: oldFilename)
        } catch {
            card.userArtworkFilename = oldFilename
            errorMessage = error.localizedDescription
        }
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
        let projection = LogicalCollection.project(cards: collectionCards) { $0.priceKey }
        return projection.byKey[card.collectionKey]?.quantity
            ?? logicalQuantity
            ?? card.quantity
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

    /// Straight from the number to the market it came from.
    ///
    /// Sits directly under the price because that is the question it answers:
    /// "this says it is worth $31 — show me". Absent entirely when the app has
    /// no marketplace identity it can stand behind, rather than falling back to
    /// a search that might open the wrong reprint.
    @ViewBuilder
    private var marketplaceLink: some View {
        if let url = TCGplayerLinkBuilder.url(for: card) {
            Link(destination: url) {
                Label("View on TCGplayer", systemImage: "arrow.up.forward.app")
                    .font(.subheadline.weight(.semibold))
            }
            .frame(minHeight: 44)
            .padding(.top, 2)
            .accessibilityLabel("View \(card.name) on TCGplayer")
            .accessibilityHint("Opens the marketplace page for this printing.")
        }
    }

    /// The price belongs to this printing *and* this finish. When the provider
    /// exposes nothing for the variant the user owns, the app says so instead of
    /// borrowing a different finish's number.
    private var pricing: some View {
        VStack(spacing: 6) {
            PriceLabel(price: price, style: .detailed)

            if let source = price.source, price.amount != nil {
                Text(source.publishesSourceTimestamp
                     ? "\(source.label) · current as of \(price.effectiveAsOf?.formatted(date: .abbreviated, time: .shortened) ?? "unknown")"
                     : "\(source.label) · checked \(price.fetchedAt?.formatted(date: .abbreviated, time: .shortened) ?? "never")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if price.refreshFailed {
                Label("Last refresh failed", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            marketplaceLink

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
                .padding(.top, 4)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }

    private var finish: some View {
        VStack {
            LabeledContent("Finish", value: card.variant?.label ?? "Unknown")
        }
        .font(.subheadline)
        .padding(14)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var treatment: some View {
        if let label = card.displayedMagicTreatmentEvidence.displayLabel {
            VStack {
                LabeledContent("Treatment", value: label)
            }
            .font(.subheadline)
            .padding(14)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
        }
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

    private var activityHistory: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("History")
                .font(.headline)

            if cardHistory.isEmpty {
                Text("No history recorded for this collection entry.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(cardHistory) { activity in
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
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }

    private var cardHistory: [CollectionActivity] {
        collectionActivities.filter { $0.collectionKey == card.collectionKey }
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

    @ViewBuilder
    private var marketplaceLinks: some View {
        if let url = exactTCGPlayerPrintingURL,
           let variant = card.variant {
            VStack(alignment: .leading, spacing: 0) {
                Text("Marketplace")
                    .font(.headline)
                    .padding(.bottom, 6)

                Link(destination: url) {
                    HStack(spacing: 12) {
                        Image(systemName: "cart")
                            .frame(width: 24)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("TCGplayer")
                                .foregroundStyle(.primary)
                            Text("Exact printing · select \(variant.label)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .foregroundStyle(.secondary)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .accessibilityLabel("Open this printing on TCGplayer")
                .accessibilityHint("Select \(variant.label) on TCGplayer")
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
        }
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
            Spacer(minLength: 8)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Movement Details")
    }

    private func secondaryText(for detail: PortfolioContributionDetail) -> String? {
        if detail.hasConsistentQuantity,
           let quantity = detail.affectedQuantities.first,
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
