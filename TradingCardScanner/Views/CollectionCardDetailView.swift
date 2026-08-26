import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct CollectionCardDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Bindable var card: CollectedCard
    let price: PriceDisplay
    let unpricedReason: PricingDiagnosticReason?
    let artworkReason: ArtworkDiagnosticReason?
    let onRemoved: (RemovedCardSnapshot) -> Void

    @State private var isConfirmingRemoval = false
    @State private var selectedArtwork: PhotosPickerItem?

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
                Task { await saveSelectedArtwork(item) }
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
            finish
            marketplaceLinks

            Stepper(
                "Quantity: \(card.quantity)",
                value: Binding(
                    get: { card.quantity },
                    set: { newQuantity in
                        try? CollectionStore(context: modelContext).setQuantity(
                            newQuantity,
                            for: card
                        )
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
    private func saveSelectedArtwork(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let filename = CollectionArtworkStore.save(
                  data,
                  replacing: card.userArtworkFilename
              ) else { return }
        card.userArtworkFilename = filename
        selectedArtwork = nil
        try? modelContext.save()
    }

    private func removeUserArtwork() {
        CollectionArtworkStore.remove(filename: card.userArtworkFilename)
        card.userArtworkFilename = nil
        try? modelContext.save()
    }

    private var removalMessage: String {
        if card.quantity == 1 {
            return "This removes the card. You can undo it."
        }
        return "This removes all \(card.quantity) copies. You can undo it."
    }

    private func removeCard() {
        // Deleting the row from here is what made removals invisible to
        // history. Ownership changes go through the store, which is the only
        // thing that knows the ledger has to hear about them.
        guard let snapshot = try? CollectionStore(context: modelContext).remove(card) else { return }
        onRemoved(snapshot)
        dismiss()
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
              variantID == PhysicalVariant.nonfoil.id || variantID == PhysicalVariant.foil.id,
              let value = card.tcgplayerURL else {
            return nil
        }
        return URL(string: value)
    }

    @MainActor
    private func loadMarketplaceLinkIfNeeded() async {
        guard card.cardGame == .magic,
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

/// Everything needed to restore a removed row without another catalog request.
/// The value safely outlives the deleted SwiftData model.
enum CollectionArtworkStore {
    private static var directory: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CollectionArtwork", isDirectory: true)
    }

    static func save(_ data: Data, replacing oldFilename: String?) -> String? {
        guard UIImage(data: data) != nil, let directory else { return nil }
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            let filename = UUID().uuidString + ".image"
            try data.write(to: directory.appendingPathComponent(filename), options: .atomic)
            remove(filename: oldFilename)
            return filename
        } catch {
            return nil
        }
    }

    static func image(filename: String?) -> UIImage? {
        guard let filename, let directory else { return nil }
        return UIImage(contentsOfFile: directory.appendingPathComponent(filename).path)
    }

    static func remove(filename: String?) {
        guard let filename, let directory else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(filename))
    }
}
