import PhotosUI
import Charts
import CoreMotion
import CoreImage
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
    @State private var artworkAccent: ArtworkAccent?
    @State private var isShowingCardDetails = false

    private struct ArtworkRequest: Identifiable {
        let id: Int
        let item: PhotosPickerItem
    }

    private struct CardFact: Identifiable {
        let id: Int
        let label: String
        let value: String
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
            AppCardDetailBackdrop(accent: artworkAccent)
                .ignoresSafeArea()

            ScrollViewReader { proxy in
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
#if DEBUG
                .onChange(of: isShowingCardDetails) { _, isShowing in
                    guard isShowing,
                          CommandLine.arguments.contains("-ui_card_details_expanded") else { return }
                    // Keep the capture-only expanded route focused on the
                    // disclosed facts instead of requiring a gesture in the
                    // deterministic screenshot loop.
                    DispatchQueue.main.async {
                        withAnimation(nil) {
                            proxy.scrollTo("card-detail-facts", anchor: .top)
                        }
                    }
                }
#endif
            }
        }
        .navigationTitle(card.name)
        .navigationBarTitleDisplayMode(.inline)
        // Artwork actions belong in the navigation chrome so they never cover
        // printed card content in the full-bleed hero.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                artworkMenu
            }
        }
        // The detail destination is a focused surface. Leaving the collection
        // tab bar visible puts it over the identity block at the hero's resting
        // height, clipping the card name before the user can scroll.
        .toolbar(.hidden, for: .tabBar)
#if DEBUG
        // Capture-only hook for the deterministic screenshot route. Normal
        // launches do not pass this argument, so the disclosure always starts
        // collapsed and never persists across cards.
        .onAppear {
            if CommandLine.arguments.contains("-ui_card_details_expanded") {
                isShowingCardDetails = true
            }
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

            Divider()

            // Destructive, and rare. The overflow is the right home for it now
            // that quantity — the control people actually use — has moved up
            // into the identity block.
            Button("Remove from Collection", role: .destructive) {
                isConfirmingRemoval = true
            }
        } label: {
            Image(systemName: "ellipsis.circle.fill")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                .padding(4)
                .background(.black.opacity(0.55), in: Circle())
        }
        .accessibilityLabel("Card actions")
        .accessibilityHint("Choose a personal photo, replace it, or return to catalog artwork.")
        .onChange(of: selectedArtwork) { _, item in
            guard let item else { return }
            artworkGeneration &+= 1
            pendingArtwork = ArtworkRequest(id: artworkGeneration, item: item)
        }
    }

    /// The printed card's corner. Shared with `CardFinishOverlay` so the sheen
    /// is masked to exactly the shape the artwork is clipped to.
    fileprivate static let cardCornerRadius: CGFloat = 20

    private var heroSection: some View {
        let movementEnabled = !reduceMotion
        return artwork
            .aspectRatio(0.716, contentMode: .fit)
            .clipShape(
                RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
            )
            .overlay {
                // A printed card has an edge. Bleeding the artwork to the screen
                // edge with square corners read as wallpaper — the wrong claim
                // for an app whose other half measures borders for a living.
                RoundedRectangle(cornerRadius: Self.cardCornerRadius, style: .continuous)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.55), radius: 24, x: 0, y: 14)
            .padding(.horizontal, 18)
            .padding(.top, 4)
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
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Artwork for \(card.name)")
    }

    private var identityBlock: some View {
        AppCardSurface(accent: artworkAccent?.color) {
            VStack(alignment: .leading, spacing: 12) {
                provenanceRow
                conditionRow

                Divider()
                    .overlay(Color.primary.opacity(0.08))

                quantityControl

                Divider()
                    .overlay(Color.primary.opacity(0.08))

                detailsToggle
                if isShowingCardDetails {
                    cardDetailsList
                        .id("card-detail-facts")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
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

    private var provenanceRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(provenanceLine)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)

            Spacer(minLength: 8)

            if let rarity = CardRarityToken(raw: card.rarity) {
                RarityChip(rarity: rarity)
            }
        }
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
            guard let requiredFinish = treatment.requiredFinish else { return false }
            return requiredFinish == card.variant
        }
        let names = treatments.map(\.label)
        if subsumesFinish {
            return names.joined(separator: " · ")
        }
        return ([card.variant?.label].compactMap { $0 } + names)
            .joined(separator: " · ")
    }

    @ViewBuilder
    private var conditionRow: some View {
        if let conditionLine {
            Text(conditionLine)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    /// Everything the app knows about this particular copy, in the order a
    /// collector would ask for it. Facts folded into the glance rows remain
    /// available here without competing with the quick scan.
    private var cardFacts: [CardFact] {
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
            CardFact(id: index, label: element.0, value: element.1)
        }
    }

    @ViewBuilder
    private var cardDetailsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(cardFacts) { fact in
                LabeledContent(fact.label) {
                    Text(fact.value)
                        .font(.callout.weight(.medium))
                        .multilineTextAlignment(.trailing)
                }
                .font(.callout)
            }

            if let note = identityConfidenceNote {
                Label(note, systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 2)
            }
        }
        .transition(.opacity.combined(with: .move(edge: .top)))
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

    private var detailsToggle: some View {
        Button {
            if reduceMotion {
                isShowingCardDetails.toggle()
            } else {
                withAnimation(.snappy(duration: 0.28)) {
                    isShowingCardDetails.toggle()
                }
            }
        } label: {
            HStack {
                Text(isShowingCardDetails ? "Hide details" : "Card details")
                Spacer()
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isShowingCardDetails ? 90 : 0))
                    .font(.footnote.weight(.semibold))
            }
            .font(.subheadline.weight(.medium))
            .contentShape(.rect)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isShowingCardDetails ? "Hide card details" : "Show card details")
        .accessibilityIdentifier("card-details-toggle")
    }

    /// How many you own, beside what you own.
    ///
    /// This lived at the very bottom of the screen behind a menu, under the
    /// chart — the one control on the page a collector reaches for repeatedly,
    /// placed where it could not be found. Quantity is an attribute of the
    /// holding, so it belongs in the block that describes the holding.
    private var quantityControl: some View {
        HStack(spacing: 12) {
            Text("Quantity")
                .font(.headline)

            Spacer(minLength: 12)

            Button {
                updateQuantity(displayedQuantity - 1)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .disabled(displayedQuantity <= 1)
            .accessibilityLabel("Decrease quantity")

            Text("\(displayedQuantity)")
                .font(.title3.weight(.semibold).monospacedDigit())
                .frame(minWidth: 32)
                .contentTransition(.numericText())
                .animation(.snappy, value: displayedQuantity)

            Button {
                updateQuantity(displayedQuantity + 1)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .accessibilityLabel("Increase quantity")
        }
        .buttonStyle(.borderless)
        .padding(.top, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quantity, \(displayedQuantity)")
    }

    /// What the whole position is worth, as distinct from one copy of it.
    private var holdingTotal: String? {
        guard let amount = price.amount, displayedQuantity > 0 else { return nil }
        return (amount * Double(displayedQuantity))
            .formatted(.currency(code: price.currencyCode))
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

                // The `unit` qualifier only earns its keep if the total it is
                // distinguished from is somewhere on the screen. Shown only
                // when the two genuinely differ.
                if displayedQuantity > 1, let holdingTotal {
                    Text("\(holdingTotal) for \(displayedQuantity) copies")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .accessibilityLabel(
                            "Holding value \(holdingTotal) for \(displayedQuantity) copies"
                        )
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
                treatments: card.displayedMagicTreatmentEvidence.treatments,
                cornerRadius: Self.cardCornerRadius
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

struct AppCardSurface<Content: View>: View {
    private let content: Content
    private let accent: Color?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(accent: Color? = nil, @ViewBuilder content: () -> Content) {
        self.accent = accent
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background {
                ZStack {
                    if reduceTransparency {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemBackground))
                    } else {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.ultraThinMaterial)
                    }

                    if let accent {
                        // A small, local tint makes the identity surface feel
                        // connected to its artwork without recolouring every
                        // card surface on the page.
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(accent.opacity(reduceTransparency ? 0.07 : 0.11))
                    }
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(.primary.opacity(0.08), lineWidth: 1)
            }
    }
}

private struct AppCardDetailBackdrop: View {
    let accent: ArtworkAccent?
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        if reduceTransparency {
            Color(uiColor: .systemBackground)
        } else {
            // Layered over the system background rather than mixed into a list
            // of stops, so the strength is a real blend and light and dark both
            // stay correct without a second palette.
            //
            // Weighted to the top, where the card is: the point of extracting a
            // colour is that The One Ring's page should not look like a bulk
            // common's, and a single 20%-opacity stop in the middle of a
            // diagonal was invisible on a device.
            Color(uiColor: .systemBackground)
                .overlay {
                    LinearGradient(
                        stops: [
                            .init(color: (accent?.color ?? .clear).opacity(0.34), location: 0),
                            .init(color: (accent?.color ?? .clear).opacity(0.12), location: 0.34),
                            .init(color: .clear, location: 0.68)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
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

/// Device tilt, normalised and smoothed, for the foil sheen.
///
/// Neutral is wherever the phone was held when the card appeared, not flat on a
/// table, so the sheen is centred for someone reading in bed as much as at a
/// desk.
///
/// The model this replaced reported a raw gravity vector scaled to ±12pt, which
/// the view then multiplied by 0.3: a peak travel of 3.6 points on a 400pt card,
/// damped at 0.84 per frame. The motion was running the whole time. It was
/// simply far too small to see.
private final class CardFinishMotionModel: ObservableObject {
    /// Roll and pitch as −1…1, where ±1 is a comfortable wrist tilt.
    @Published private(set) var tilt: CGSize = .zero

    private let motionManager = CMMotionManager()
    private var reference: (roll: Double, pitch: Double)?
    private var isRunning = false

    /// Full travel at roughly 25°, which is a wrist movement rather than a
    /// shoulder one.
    private static let fullTravel = 0.44

    func start() {
        guard !isRunning, motionManager.isDeviceMotionAvailable else { return }
        isRunning = true
        reference = nil
        motionManager.deviceMotionUpdateInterval = 1 / 60
        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let attitude = motion?.attitude else { return }
            if self.reference == nil {
                self.reference = (attitude.roll, attitude.pitch)
            }
            guard let reference = self.reference else { return }

            let target = CGSize(
                width: Self.normalised(attitude.roll - reference.roll),
                height: Self.normalised(attitude.pitch - reference.pitch)
            )
            // Tracks the hand rather than trailing it. At the previous 0.84
            // coefficient the sheen took most of a second to arrive, which
            // reads as no movement at all during the quick tilt people
            // actually use to look for foil.
            self.tilt = CGSize(
                width: self.tilt.width * 0.55 + target.width * 0.45,
                height: self.tilt.height * 0.55 + target.height * 0.45
            )
        }
    }

    func stop() {
        guard isRunning else { return }
        isRunning = false
        motionManager.stopDeviceMotionUpdates()
        reference = nil
        tilt = .zero
    }

    private static func normalised(_ radians: Double) -> Double {
        max(-1, min(1, radians / fullTravel))
    }
}

/// The card's finish, rendered rather than captioned.
///
/// Foil is a *directional band* that sweeps across the surface as the viewing
/// angle changes. What this replaced drew a rounded rectangle at 82% of the
/// card's width and screen-blended it at 0.72 — a hard-edged translucent box
/// sitting on the artwork, lifting its blacks and showing its own corners on
/// every card. Three rules come out of what foil actually does:
///
/// - The band is wider than the card's diagonal and masked to the card, so its
///   own edges are never in frame.
/// - It blends with `.softLight`, which brightens light areas and leaves dark
///   ones alone. That is the luminance-modulated bloom, achieved by blend maths
///   rather than by loading and masking a second copy of the artwork.
/// - It travels far enough to read as movement: most of the card across a
///   comfortable tilt.
///
/// Subtle by intent. On a card worth several hundred dollars a sheen that
/// announces itself looks like a filter; the narrow specular core is the only
/// element allowed to go bright.
private struct CardFinishOverlay: View {
    let variant: PhysicalVariant?
    let resolution: VariantResolution?
    let treatments: [MagicTreatment]
    let cornerRadius: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @StateObject private var motion = CardFinishMotionModel()

    /// How far the sweep travels at full tilt, as a fraction of the gradient's
    /// own length. Chosen to preserve the travel distance the previous
    /// `0.55 × diagonal` produced.
    private static let driveSpan = 0.275

    /// One band of the sweep. Several out of phase is what separates a Surge
    /// Foil ripple from a plain foil's single pass.
    ///
    /// `phase` and `width` are both fractions of the gradient's own length,
    /// which is twice the card's diagonal. Expressing them in one unit is the
    /// whole point: they were previously measured against different lengths —
    /// width against the full gradient, phase against `0.55 × diagonal` — so
    /// numbers that looked comparable were off by a factor of 3.6. A plain
    /// foil's "band" had an 830pt falloff on a 629pt card, which is not a band
    /// at all but a wash over the whole surface, and Surge Foil's three bands
    /// were 415pt wide and 69pt apart, overlapping into a single smear. Both
    /// read exactly as reported: hard to notice until moved, and never like
    /// three of anything.
    private struct SheenBand {
        /// Where the band rests when the card is held still.
        var phase: Double
        /// Chromatic offset from the band's centre, which opens as the card is
        /// tilted. Real dispersion separates at glancing angles and closes when
        /// you look straight on, so a fixed fringe reads as a permanently
        /// rainbow band. Held still this collapses to near-white; moving, the
        /// colour blooms out of the shoulders.
        var fringe: Double = 0
        /// How the band answers tilt. Negative counter-moves, which is what
        /// makes two highlights converge and separate rather than slide
        /// together as one rigid pattern.
        var travelScale: Double = 1
        var width: Double
        var tint: Color
        var intensity: Double
        /// Carries the additive specular core. Exactly one band should.
        var isPrimary: Bool = false
    }

    /// A dimmer second reflection, resting up and left of the primary and
    /// travelling against it.
    ///
    /// Two things wrong were fixed by one addition. A single band centred at
    /// rest is easy to miss until you happen to move the phone — you have to
    /// already know the effect is there. And simply parking the primary
    /// somewhere more obvious would have staged the card rather than lit it.
    /// A counter-moving secondary is what foil actually does, puts light in the
    /// opposite corner so something is visible the moment the card opens, and
    /// turns the sweep into a scissor that reads far more like a surface than
    /// one sliding gradient did.
    private var counterBand: SheenBand {
        SheenBand(
            phase: -0.20,
            travelScale: -0.55,
            width: 0.09,
            tint: activeTreatment == .neonInk ? .purple : .white,
            intensity: 0.42
        )
    }

    private var isCatalogConfirmed: Bool {
        guard variant != nil, let resolution else { return false }
        return resolution != .catalogSilent && resolution != .imported
    }

    private var activeTreatment: MagicTreatment? { treatments.first }

    private var isFoilSurface: Bool {
        guard let variant else { return false }
        return variant.id == PhysicalVariant.holo.id || variant.id == PhysicalVariant.foil.id
    }

    private var isReverseSurface: Bool {
        variant?.id == PhysicalVariant.reverse.id
    }

    private var hasSurface: Bool { isFoilSurface || isReverseSurface }

    /// The primary is the band that rests at centre and carries the specular
    /// core. It was previously `bands.first`, which for Surge Foil is the band
    /// at phase −0.20 — so on a treatment-qualified card the one bright element
    /// sat off to a corner and the sheen only became legible once the card was
    /// moved.
    /// One dispersed band, and for now the finish every foil surface uses.
    ///
    /// This began as Surge Foil's treatment and turned out to be the better
    /// plain foil: three colour components overlapping so heavily that they
    /// fringe a single band rather than multiplying it. Separating them far
    /// enough to resolve individually — the earlier attempt — produces stripes,
    /// which is not what any foil looks like.
    ///
    /// It does not yet read as *specifically* a Surge Foil. That is a known
    /// gap and a later piece of work; what a Surge Foil needs beyond this is a
    /// pattern, not more colour. The band with the card either side of it is
    /// the part worth keeping, so it is shared rather than duplicated.
    private var dispersedFoil: [SheenBand] {
        [
            SheenBand(
                phase: 0,
                fringe: -0.035,
                width: 0.095,
                tint: .pink,
                intensity: 0.7
            ),
            SheenBand(
                phase: 0,
                width: 0.105,
                tint: .cyan,
                intensity: 1,
                isPrimary: true
            ),
            SheenBand(
                phase: 0,
                fringe: 0.035,
                width: 0.095,
                tint: .blue,
                intensity: 0.7
            ),
            counterBand
        ]
    }

    private var bands: [SheenBand] {
        switch activeTreatment {
        case .neonInk:
            // Held back deliberately: Neon Ink's identity is the hue shift, and
            // giving it its own look is later work.
            return [
                SheenBand(phase: 0, fringe: -0.04, width: 0.10, tint: .orange, intensity: 0.85),
                SheenBand(phase: 0, width: 0.10, tint: .green, intensity: 1, isPrimary: true),
                SheenBand(phase: 0, fringe: 0.04, width: 0.10, tint: .purple, intensity: 0.85),
                counterBand
            ]
        case .surgeFoil, .unclassified, .none:
            return dispersedFoil
        }
    }

    var body: some View {
        Group {
            if isCatalogConfirmed, !reduceTransparency, hasSurface {
                GeometryReader { proxy in
                    ZStack {
                        ForEach(bands.indices, id: \.self) { index in
                            sheen(bands[index], in: proxy.size, specular: false)
                        }
                        // A single narrow additive core, on the band that rests
                        // at centre. Everything else is soft-light, so this is
                        // the only place the sheen is allowed to look like a
                        // light source.
                        if let primary = bands.first(where: \.isPrimary) {
                            sheen(primary, in: proxy.size, specular: true)
                        }
                    }
                    .mask {
                        if isReverseSurface {
                            // A reverse holo foils the border, not the art
                            // window, so the sheen is masked to the frame the
                            // printing actually applies it to.
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                                .strokeBorder(.white, lineWidth: proxy.size.width * 0.10)
                        } else {
                            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
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

    private func sheen(_ band: SheenBand, in size: CGSize, specular: Bool) -> some View {
        let diagonal = sqrt(size.width * size.width + size.height * size.height)
        // Roll dominates: turning the phone in the hand is how anyone looks for
        // foil. Pitch contributes so the band still answers a nod.
        let drive = max(-1, min(1, motion.tilt.width * 0.85 + motion.tilt.height * 0.45))
        // Closed to roughly a third at rest, fully open at the extremes of a
        // comfortable tilt.
        let spread = 0.32 + 0.68 * abs(drive)
        let travel = (
            drive * band.travelScale * Self.driveSpan
                + band.phase
                + band.fringe * spread
        ) * diagonal * 2

        return LinearGradient(
            stops: stops(for: band, specular: specular),
            startPoint: .top,
            endPoint: .bottom
        )
        // Twice the diagonal in both directions, so no edge of the gradient can
        // enter the card at any travel position or rotation.
        .frame(width: diagonal * 2, height: diagonal * 2)
        .offset(y: travel)
        .rotationEffect(.degrees(-24))
        .position(x: size.width / 2, y: size.height / 2)
        .blendMode(specular ? .plusLighter : .softLight)
    }

    private func stops(for band: SheenBand, specular: Bool) -> [Gradient.Stop] {
        let half = (specular ? band.width * 0.34 : band.width) / 2
        let core = specular ? 0.13 * band.intensity : 0.5 * band.intensity
        let shoulder = specular ? 0 : 0.13 * band.intensity
        let outer = min(0.5, half * 2.2)
        return [
            .init(color: .clear, location: 0),
            .init(color: .clear, location: 0.5 - outer),
            .init(color: band.tint.opacity(shoulder), location: 0.5 - half),
            .init(color: .white.opacity(core), location: 0.5),
            .init(color: band.tint.opacity(shoulder), location: 0.5 + half),
            .init(color: .clear, location: 0.5 + outer),
            .init(color: .clear, location: 1)
        ]
    }

    /// Reduce Motion keeps the finish and stops the sweep: the band simply
    /// rests at centre, which is still a foil rather than a flat print.
    private func updateMotion() {
        if isCatalogConfirmed, !reduceMotion, !reduceTransparency, hasSurface {
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
    let plotRangeStart: Date
    let plotRangeEnd: Date
    let samples: [PriceHistorySample]
    let segments: [PriceHistorySegment]
    let observationCount: Int
    let checkedDayCount: Int

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

        let plotRange = plotRange(
            for: samples,
            requestedStart: start,
            requestedEnd: end
        )

        return PriceHistoryChartModel(
            currencyCode: currencyCode,
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

struct PriceHistoryChartView: View {
    let observations: [PriceObservation]
    let checkDays: [PriceCheckDay]
    let currencyCode: String
    let range: PortfolioHistoryRange
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

    private var xAxisTickCount: Int {
        PriceHistoryChartModel.recommendedXAxisTickCount(
            for: model.plotRangeSpan,
            isAccessibilitySize: dynamicTypeSize.isAccessibilitySize
        )
    }

    private var xAxisTickDates: [Date] {
        let count = xAxisTickCount
        guard count > 1 else { return [model.plotRangeStart] }
        let span = model.plotRangeSpan
        return (0..<count).map { index in
            model.plotRangeStart.addingTimeInterval(
                span * Double(index) / Double(count - 1)
            )
        }
    }

    private var usesShortAxisLabels: Bool {
        PriceHistoryChartModel.usesShortXAxisLabels(for: model.plotRangeSpan)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.isPlotRangeFitted {
                Text("Fitted to available data · \(range.rawValue) selected")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(
                        "Chart fitted to available data for \(range.accessibilityName)"
                    )
            }

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
                .chartXScale(domain: model.plotRange)
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
                    AxisMarks(values: xAxisTickDates) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let date = value.as(Date.self) {
                                if usesShortAxisLabels {
                                    Text(
                                        date,
                                        format: .dateTime
                                            .month(.abbreviated)
                                            .day()
                                            .hour(.defaultDigits(amPM: .abbreviated))
                                    )
                                } else {
                                    Text(date, format: .dateTime.month(.abbreviated).day())
                                }
                            }
                        }
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
    private final class Box: NSObject {
        let value: ArtworkAccent

        init(_ value: ArtworkAccent) {
            self.value = value
        }
    }

    private static let cache: NSCache<NSString, Box> = {
        let cache = NSCache<NSString, Box>()
        cache.countLimit = 120
        return cache
    }()

    /// The image view keeps its existing `AsyncImage` behavior. This companion
    /// task has a separate, keyed color cache so accent extraction happens once
    /// per artwork source and never as part of a SwiftUI body evaluation.
    static func accent(
        localFilename: String?,
        remoteURL: URL?
    ) async -> ArtworkAccent? {
        let key: String
        if let localFilename {
            key = "local:\(localFilename)"
        } else if let remoteURL {
            key = "remote:\(remoteURL.absoluteString)"
        } else {
            return nil
        }

        if let cached = cache.object(forKey: key as NSString)?.value {
            return cached
        }

        let image: UIImage?
        if let localFilename {
            image = CollectionArtworkStore.image(filename: localFilename)
        } else if let remoteURL {
            guard let (data, _) = try? await URLSession.shared.data(from: remoteURL) else {
                return nil
            }
            image = UIImage(data: data)
        } else {
            return nil
        }
        guard let image else { return nil }
        let accent = ArtworkAccentExtractor.make(from: image)
        if let accent {
            cache.setObject(Box(accent), forKey: key as NSString)
        }
        return accent
    }
}

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
