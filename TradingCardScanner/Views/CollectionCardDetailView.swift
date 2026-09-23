import PhotosUI
import Charts
import CoreImage
import ImageIO
import SwiftData
import SwiftUI
import UIKit

private struct CardDetailFact: Identifiable {
    let id: Int
    let label: String
    let value: String
}

private struct CardDetailMovementDisplay: Equatable {
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
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.cardFinishMotionSource) private var cardFinishMotion
    @Bindable var card: CollectedCard
    @Query private var priceObservations: [PriceObservation]
    @Query private var priceCheckDays: [PriceCheckDay]
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

    @State private var isConfirmingRemoval = false
    @State private var selectedArtwork: PhotosPickerItem?
    @State private var errorMessage: String?
    @State private var artworkGeneration = 0
    @State private var pendingArtwork: ArtworkRequest?
    @State private var artworkAccent: ArtworkAccent?
    @State private var projectedQuantity: Int?
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
        self._priceObservations = Query(
            filter: #Predicate<PriceObservation> { $0.instrumentKey == resolvedInstrumentKey },
            sort: [SortDescriptor(\PriceObservation.receivedAt, order: .forward)]
        )
        self._priceCheckDays = Query(
            filter: #Predicate<PriceCheckDay> { $0.instrumentKey == resolvedInstrumentKey },
            sort: [SortDescriptor(\PriceCheckDay.portfolioDay, order: .forward)]
        )
        let resolvedCollectionKey = card.collectionKey
        if card.itemKind == .gradedCard {
            let gradedKindRaw = CollectionItemKind.gradedCard.rawValue
            let addedKindRaw = CollectionActivityKind.added.rawValue
            let restoredKindRaw = CollectionActivityKind.restored.rawValue
            var descriptor = FetchDescriptor<CollectionActivity>(
                predicate: #Predicate<CollectionActivity> {
                    $0.collectionKey == resolvedCollectionKey
                        && $0.itemKindRaw == gradedKindRaw
                        && ($0.kindRaw == addedKindRaw || $0.kindRaw == restoredKindRaw)
                },
                sortBy: [SortDescriptor(\CollectionActivity.occurredAt, order: .reverse)]
            )
            descriptor.fetchLimit = 1
            self._collectionActivities = Query(descriptor)
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
        self.onRemoved = onRemoved
    }

    var body: some View {
        let chartModel = makePriceHistoryModel()
        let movement = movementDisplay(for: chartModel)

        return ZStack {
            AppCardDetailBackdrop()
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    heroSection
                    cardIdentitySection
                    valuationSection(movement: movement)
                    priceHistorySection(model: chartModel, movement: movement)
                    marketplaceSection
                    ownershipSection

                    if isLogicalConflict {
                        conflictNotice
                            .padding(.horizontal, 16)
                            .padding(.top, 20)
                    }
                }
                .padding(.bottom, 24)
            }
            .coordinateSpace(name: "CardDetailScroll")
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Color.black, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
        // Capture-only hook for the deterministic details route. Normal
        // launches do not pass this argument, so the destination remains a
        // normal user-driven navigation row.
        .onAppear {
            if CommandLine.arguments.contains("-ui_card_details_route") {
                isShowingPrintingDetailsRoute = true
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
        .task(id: card.collectionKey) {
            refreshDisplayedQuantity()
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
            NavigationLink {
                CollectionCardHistoryView(
                    collectionKey: card.collectionKey,
                    cardName: card.name
                )
            } label: {
                Label("Collection History", systemImage: "clock.arrow.circlepath")
            }

            Divider()

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
                .aspectRatio(0.716, contentMode: .fit)
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
                .font(.system(size: 32, weight: .bold))
                .tracking(-0.6)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            if !provenanceLine.isEmpty {
                Text(provenanceLine)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
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
    private var conditionRow: some View {
        if let conditionLine {
            Text(conditionLine)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
        }
    }

    @ViewBuilder
    private var gradedVariantCorrectionBlock: some View {
        if let activity = latestGradedAcquisition {
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
                    Menu {
                        ForEach(gradedVariantOptions) { option in
                            Button {
                                correctGradedVariant(option, activity: activity)
                            } label: {
                                if option == card.variant {
                                    Label(option.label, systemImage: "checkmark")
                                } else {
                                    Text(option.label)
                                }
                            }
                        }
                    } label: {
                        Label("Fix finish", systemImage: "pencil")
                            .font(.subheadline.weight(.semibold))
                    }
                    .accessibilityLabel("Fix graded card finish")
                }
                Text("The slab stays the same card; this only corrects its printed finish.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 2)
        }
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
    static func gradedVariantEvidence(for card: CollectedCard) -> VariantEvidence {
        let printingID = card.underlyingPrintingID ?? card.providerID
        var evidence = VariantEvidence(
            game: card.cardGame,
            setID: printingID.split(separator: "-", maxSplits: 1)
                .first.map(String.init) ?? printingID,
            cardNumber: card.cardNumber,
            catalogVariants: card.variant.map { [$0] } ?? []
        )
        if card.pokemonPrintRun != nil {
            evidence = evidence.excludingFirstEditionPseudoFinish()
        }
        return evidence
    }

    static func gradedVariantOptions(for card: CollectedCard) -> [PhysicalVariant] {
        VariantResolver.options(for: gradedVariantEvidence(for: card))
    }

    private var gradedVariantOptions: [PhysicalVariant] {
        // The persisted row is the only catalog finish fact available to this
        // offline detail surface. Do not widen it to the UI's global selectable
        // list, and do not re-add 1st Edition after it has been removed from the
        // finish axis above.
        return Self.gradedVariantOptions(for: card)
    }

    private func correctGradedVariant(
        _ variant: PhysicalVariant,
        activity: CollectionActivity
    ) {
        guard variant != card.variant else { return }
        do {
            let corrected = ResolvedVariant(variant: variant, resolution: .userConfirmed)
            _ = try CollectionStore(context: modelContext).recordVariantCorrection(
                for: card,
                to: corrected,
                activityID: activity.id,
                quantity: min(activity.remainingQuantity, card.quantity)
            )
        } catch {
            errorMessage = error.localizedDescription
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
            confidenceNote: identityConfidenceNote
        )
    }

    private var ownershipSection: some View {
        CardDetailOwnershipPanel(
            quantity: displayedQuantity,
            holdingTotal: holdingTotal,
            onDecrease: { updateQuantity(displayedQuantity - 1) },
            onIncrease: { updateQuantity(displayedQuantity + 1) }
        ) {
            printingDetailsDestination
        }
        .padding(.horizontal, 16)
        .padding(.top, 24)
    }

    private func valuationSection(movement: CardDetailMovementDisplay) -> some View {
        VStack(spacing: 0) {
            CardDetailHeroPrice(price: price)
            CardDetailMovementPill(
                display: movement,
                currencyCode: price.currencyCode
            )
            .padding(.top, 10)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }

    private func makePriceHistoryModel() -> PriceHistoryChartModel {
        PriceHistoryChartModel.make(
            observations: priceObservations,
            checkDays: priceCheckDays,
            currencyCode: price.currencyCode,
            range: history.range,
            now: .now,
            timeZone: PortfolioCalendar.pinnedTimeZone() ?? .current
        )
    }

    private func movementDisplay(for model: PriceHistoryChartModel) -> CardDetailMovementDisplay {
        let periodText = history.range.pastPeriodPhrase
        switch history.movementState(for: card.collectionKey) {
        case .historyRecording:
            return CardDetailMovementDisplay(
                status: .recording,
                direction: .flat,
                amount: nil,
                percentage: nil,
                periodText: periodText
            )
        case .noRecordedMarketMovement:
            return CardDetailMovementDisplay(
                status: .none,
                direction: .flat,
                amount: nil,
                percentage: nil,
                periodText: periodText
            )
        case let .recorded(detail):
            let unitMovement = detail.cumulativeUnitMovement
            // The hero reports per-copy market movement. `totalImpact` can
            // include quantity effects and is intentionally not a substitute
            // when the replay cannot reconstruct a unit-price delta.
            let amount = unitMovement
            let direction: CardDetailMovementDisplay.Direction
            if amount.isZero {
                direction = .flat
            } else if amount < .zero {
                direction = .negative
            } else {
                direction = .positive
            }

            return CardDetailMovementDisplay(
                status: .recorded,
                direction: direction,
                amount: amount,
                percentage: unitMovement.isZero ? nil : movementPercentage(
                    for: detail,
                    amount: unitMovement,
                    model: model
                ),
                periodText: periodText
            )
        }
    }

    /// A percentage is only honest when the selected history provides a
    /// continuous, market-only path whose starting price can be reconstructed
    /// from the eligible movement projection. Source repairs, gaps, and
    /// changing quantities deliberately fall back to the dollar movement.
    private func movementPercentage(
        for detail: PortfolioContributionDetail,
        amount: Money,
        model: PriceHistoryChartModel
    ) -> Double? {
        guard detail.hasConsistentQuantity,
              model.observationCount >= 2,
              !model.hasGaps,
              model.samples.allSatisfy({ $0.kind == nil || $0.kind == .marketUpdate }),
              let first = model.samples.first,
              let last = model.samples.last else { return nil }

        let baseline = last.amount - amount
        guard baseline > .zero, baseline == first.amount else { return nil }
        return PortfolioHistoryDisplay.percentChange(amount: amount, anchor: baseline)
    }

    @ViewBuilder
    private func priceHistorySection(
        model: PriceHistoryChartModel,
        movement: CardDetailMovementDisplay
    ) -> some View {
        VStack(spacing: 0) {
            PriceHistoryChartView(
                model: model,
                currencyCode: price.currencyCode,
                direction: movement.direction
            )
            .accessibilityIdentifier("price-history-\(priceHistoryInstrumentKey)")

            CardDetailRangeSelector(
                selection: history.range,
                direction: movement.direction,
                onSelect: { history.range = $0 }
            )
            .padding(.top, 10)

            CardDetailSourceLegend(
                sourceDescription: price.source.map(priceSourceDescription),
                hasGaps: model.hasGaps
            )
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
            guard let amount = listedGrade.marketPriceUSD else {
                return listedGrade.displayName
            }
            return "\(listedGrade.displayName) \(amount.formatted(.currency(code: "USD")))"
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
        ZStack {
            if let image = CollectionArtworkStore.image(filename: localArtworkFilename) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                let source = CatalogCardArtworkSource(
                    game: card.cardGame,
                    setCode: card.setCode,
                    collectorNumber: card.cardNumber,
                    thumbnailURL: card.lowImageURL,
                    imageURL: card.highImageURL,
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

            CardFinishOverlay(
                variant: card.variant,
                resolution: card.variantResolution,
                treatments: card.displayedMagicTreatmentEvidence.treatments,
                cornerRadius: Self.cardCornerRadius,
                motionSource: cardFinishMotion,
                motionUsage: .detail
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
            CollectionArtworkStore.removeIfUnreferenced(oldFilename, in: modelContext)
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
            CollectionArtworkStore.removeIfUnreferenced(oldFilename, in: modelContext)
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
        guard isLogicalConflict else { return card.quantity }
        return projectedQuantity ?? logicalQuantity ?? card.quantity
    }

    /// The projected quantity is authoritative while duplicate rows are being
    /// healed. Read it on appearance and after a quantity mutation rather than
    /// rebuilding a full projection for every unrelated detail-view render.
    private func refreshDisplayedQuantity() {
        guard isLogicalConflict else {
            projectedQuantity = nil
            return
        }
        let cards = (try? modelContext.fetch(FetchDescriptor<CollectedCard>())) ?? []
        let projection = LogicalCollection.project(cards: cards) { $0.priceKey }
        projectedQuantity = projection.byKey[card.collectionKey]?.quantity
            ?? logicalQuantity
            ?? card.quantity
    }

    private func updateQuantity(_ newQuantity: Int) {
        guard (1...CollectionQuantityLimits.maximum).contains(newQuantity) else { return }
        do {
            try CollectionStore(context: modelContext).setQuantity(
                newQuantity,
                for: card
            )
            refreshDisplayedQuantity()
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
            Text("No recorded movement")
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

private struct CardDetailSourceLegend: View {
    let sourceDescription: String?
    let hasGaps: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(sourceDescription ?? "Price source unavailable")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            if hasGaps {
                HStack(spacing: 6) {
                    Canvas { context, size in
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: size.height / 2))
                        path.addLine(to: CGPoint(x: size.width, y: size.height / 2))
                        context.stroke(
                            path,
                            with: .color(Color.secondary.opacity(0.7)),
                            style: StrokeStyle(lineWidth: 1.5, dash: [3, 3])
                        )
                    }
                    .frame(width: 16, height: 6)

                    Text("not checked")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
        }
        .padding(.horizontal, 16)
    }
}

private struct CardDetailMarketplaceButton: View {
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

private struct CardDetailOwnershipPanel<Details: View>: View {
    let quantity: Int
    let holdingTotal: String?
    let onDecrease: () -> Void
    let onIncrease: () -> Void
    private let details: Details

    init(
        quantity: Int,
        holdingTotal: String?,
        onDecrease: @escaping () -> Void,
        onIncrease: @escaping () -> Void,
        @ViewBuilder details: () -> Details
    ) {
        self.quantity = quantity
        self.holdingTotal = holdingTotal
        self.onDecrease = onDecrease
        self.onIncrease = onIncrease
        self.details = details()
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text("Owned")
                    .font(.system(size: 17))
                Spacer(minLength: 12)
                quantityControl
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
            .disabled(quantity <= 1)
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
            .disabled(quantity >= CollectionQuantityLimits.maximum)
            .accessibilityLabel("Increase quantity")
        }
        .buttonStyle(.borderless)
        .background(Color.white.opacity(0.10), in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Owned, \(quantity)")
    }
}

private struct CardPrintingDetailsView: View {
    let cardName: String
    let facts: [CardDetailFact]
    let confidenceNote: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(cardName)
                    .font(.title2.bold())
                    .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(facts) { fact in
                    LabeledContent(fact.label) {
                        Text(fact.value)
                            .font(.callout.weight(.medium))
                            .multilineTextAlignment(.trailing)
                    }
                    .font(.callout)
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
        let observedSpan = maximum - minimum
        let referencePrice = values.last ?? maximum
        let minimumVisualSpan = max(abs(referencePrice) * 0.02, 0.05)
        let desiredSpan = max(observedSpan * 1.24, minimumVisualSpan)
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

private struct PriceHistoryChartView: View {
    let model: PriceHistoryChartModel
    let currencyCode: String
    let direction: CardDetailMovementDisplay.Direction

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if model.isPlotRangeFitted {
                Text("Fitted to available data")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
                    .accessibilityLabel(
                        "Chart fitted to available data"
                    )
            }

            if model.samples.isEmpty {
                Label("History is being recorded", systemImage: "chart.xyaxis.line")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 174)
                Text("Price history is recorded on this device. It will appear after the first successful check here.")
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
                Chart {
                    RuleMark(y: .value("Floor", model.yDomain.lowerBound))
                        .foregroundStyle(.secondary.opacity(0.22))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))

                    ForEach(model.segments) { segment in
                        if segment.samples.count > 1 {
                            ForEach(segment.samples) { sample in
                                AreaMark(
                                    x: .value("Date", sample.date),
                                    yStart: .value("Floor", model.yDomain.lowerBound),
                                    yEnd: .value("Unit price", sample.amount.doubleValue),
                                    series: .value("Known span area", segment.id)
                                )
                                .interpolationMethod(.stepEnd)
                                .foregroundStyle(areaGradient)

                                LineMark(
                                    x: .value("Date", sample.date),
                                    y: .value("Unit price", sample.amount.doubleValue),
                                    series: .value("Known span", segment.id)
                                )
                                .interpolationMethod(.stepEnd)
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
                        .symbolSize(sample.isObservation ? 34 : 12)
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
                .chartYAxis(.hidden)
                .chartXAxis(.hidden)
                .chartLegend(.hidden)
                .frame(height: 174)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Unit price history")
                .accessibilityValue(model.summary)
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
        .frame(maxWidth: .infinity, minHeight: 174)
        .multilineTextAlignment(.center)
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
        guard let image = CollectionArtworkStore.image(filename: localFilename),
              let accent = ArtworkAccentExtractor.make(from: image) else {
            return nil
        }
        cache.setObject(Box(accent), forKey: key)
        return accent
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
        if let effectiveLocalFilename,
           let localKey,
           let localImage = CollectionArtworkStore.image(filename: effectiveLocalFilename) {
            selectedImage = localImage
            selectedKey = localKey
        } else {
            for (url, key) in zip(remoteURLs, remoteKeys) {
                if let remoteImage = try? await CatalogImageCache.shared.image(for: url) {
                    selectedImage = remoteImage
                    selectedKey = key
                    break
                }
            }
        }

        guard let selectedImage, let selectedKey else { return nil }
        let accent = ArtworkAccentExtractor.make(from: selectedImage)
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
            imageCache.removeAllObjects()
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
            guard references == 0 else { return true }
            remove(filename: filename)
            return true
        } catch {
            // Keeping an orphan is safer than deleting a file while a reference
            // may still exist. Rekey cleanup retries this after a later save.
            return false
        }
    }
}
