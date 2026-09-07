import SwiftUI

/// The way back into one record without leaving the session.
///
/// There is no "Add to Collection" button here because the card is already in
/// the collection — that decision was made the moment identity and variant were
/// both known. This sheet exists for the rarer, more useful question: is the
/// variant right, and what is it worth.
struct ScanReviewSheet: View {
    @Environment(\.dismiss) private var dismiss

    let scan: RecentScan
    let onCorrect: (PhysicalVariant) async -> ScanCorrectionOutcome
    let onDelete: () async -> Bool

    @State private var variant: PhysicalVariant?
    @State private var resolution: VariantResolution
    @State private var isConfirmingDelete = false
    @State private var correctionFailure: String?
    @State private var isUpdatingCorrection = false

    init(
        scan: RecentScan,
        onCorrect: @escaping (PhysicalVariant) async -> ScanCorrectionOutcome,
        onDelete: @escaping () async -> Bool
    ) {
        self.scan = scan
        self.onCorrect = onCorrect
        self.onDelete = onDelete
        _variant = State(initialValue: scan.resolved.variant)
        _resolution = State(initialValue: scan.resolved.resolution)
    }

    /// Source-compatible convenience for lightweight construction and previews.
    /// Production callers use the async form so the sheet reflects the writer's
    /// durable result instead of optimistically changing the selected finish.
    init(
        scan: RecentScan,
        onCorrect: @escaping (PhysicalVariant) -> ScanCorrectionOutcome,
        onDelete: @escaping () -> Void
    ) {
        self.scan = scan
        self.onCorrect = { variant in onCorrect(variant) }
        self.onDelete = {
            onDelete()
            return true
        }
        _variant = State(initialValue: scan.resolved.variant)
        _resolution = State(initialValue: scan.resolved.resolution)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    AsyncImage(url: scan.displayImageURL) { phase in
                        switch phase {
                        case let .success(image):
                            image.resizable().scaledToFit()
                        case .failure:
                            ContentUnavailableView("Image unavailable", systemImage: "photo")
                                .frame(height: 380)
                        default:
                            ProgressView().frame(height: 380)
                        }
                    }
                    .frame(maxHeight: 420)
                    .clipShape(RoundedRectangle(cornerRadius: 16))

                    identity
                    if scan.subject.slab == nil {
                        variantSection
                    }
                    scanPrice

                    if let correctionFailure {
                        Label(correctionFailure, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(.orange)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("Correction error: \(correctionFailure)")
                    }

                }
                .padding(20)
                .contentWidthLimit(.standard)
            }
            .navigationTitle("Scanned")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .destructiveAction) {
                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        Label("Undo Scan", systemImage: "arrow.uturn.backward")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmationDialog(
                "Undo this scan?",
                isPresented: $isConfirmingDelete,
                titleVisibility: .visible
            ) {
                Button("Undo Scan", role: .destructive) {
                    Task { @MainActor in
                        if await onDelete() {
                            dismiss()
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private var identity: some View {
        VStack(spacing: 6) {
            Text(scan.card.name)
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(scan.displaySetName)
                .foregroundStyle(.secondary)

            Text(scan.identifier.scannerDisplayIdentifier(for: scan.card))
                .font(.headline.monospacedDigit())

            if let slab = scan.subject.slab {
                Text(slab.grade.display(company: slab.company))
                    .font(.subheadline.weight(.semibold))
                if let certificationNumber = slab.certificationNumber {
                    Text("Cert \(certificationNumber)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let printRun = scan.pokemonPrintRun {
                Text(printRun.label)
                    .font(.subheadline.weight(.semibold))
            }

            if let rarity = scan.card.rarity {
                Text(rarity)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var variantSection: some View {
        VStack(spacing: 10) {
            HStack {
                Text("Finish")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                // Identity and finish are two different facts with two different
                // sources, so the record says where each one came from.
                Text(resolution.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if scan.options.count > 1 {
                Picker("Finish", selection: Binding<PhysicalVariant?>(
                    get: { variant },
                    set: { newValue in
                        guard let newValue,
                              newValue != variant,
                              !isUpdatingCorrection else { return }
                        isUpdatingCorrection = true
                        Task { @MainActor in
                            let outcome = await onCorrect(newValue)
                            isUpdatingCorrection = false
                            guard case .saved = outcome else {
                                correctionFailure = outcome.failureMessage
                                return
                            }
                            correctionFailure = nil
                            variant = newValue
                            resolution = .userConfirmed
                        }
                    }
                )) {
                    ForEach(scan.options) { option in
                        Text(option.label).tag(Optional(option))
                    }
                }
                .pickerStyle(.segmented)
                .disabled(isUpdatingCorrection)
                if isUpdatingCorrection {
                    ProgressView("Saving correction…")
                        .font(.caption)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack {
                    Text(variant?.label ?? "Unknown finish")
                        .font(.body.weight(.medium))
                    Spacer()
                }
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
    }

    private var scanPrice: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Label("Unit price", systemImage: "tag")
                    .font(.headline)
                Spacer(minLength: 12)
                ScanPriceValue(lookup: scan.price, style: .review)
            }

            switch scan.price {
            case let .price(price):
                if let sourceUpdatedAt = price.sourceUpdatedAt {
                    Text("Catalog price · current as of \(sourceUpdatedAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Catalog unit price")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            case .unavailable:
                Text("No price was returned for this printing and finish.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 14))
        .accessibilityElement(children: .contain)
    }
}

/// The complete history for one visit to the scanner. The camera keeps only a
/// compact five-card rail; this sheet is deliberately fed by the uncapped
/// session projection so older successful scans remain correctable and undoable.
struct ScanSessionReviewSheet: View {
    @EnvironmentObject private var model: ScannerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedScan: RecentScan?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    sessionSummary
                }

                Section("This session") {
                    ForEach(model.sessionScans) { scan in
                        Button {
                            selectedScan = scan
                        } label: {
                            SessionScanRow(scan: scan)
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Undo", role: .destructive) {
                                Task { @MainActor in
                                    _ = await model.undoScan(scanID: scan.id)
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Review session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $selectedScan) { scan in
                ScanReviewSheet(
                    scan: scan,
                    onCorrect: { variant in
                        await model.correct(scanID: scan.id, to: variant)
                    },
                    onDelete: {
                        await model.undoScan(scanID: scan.id)
                    }
                )
            }
        }
    }

    private var sessionSummary: some View {
        let pricedScans = model.sessionScans.compactMap { scan -> Money? in
            guard case let .price(price) = scan.price else { return nil }
            return Money(rounding: price.unitMarketPriceUSD)
        }
        let knownValue = pricedScans.sum()
        let unpricedCount = model.sessionScans.count - pricedScans.count

        return VStack(alignment: .leading, spacing: 4) {
            Text("\(model.sessionScans.count) card\(model.sessionScans.count == 1 ? "" : "s") added")
                .font(.headline)
            if unpricedCount == model.sessionScans.count, !model.sessionScans.isEmpty {
                Text("Value unavailable")
                    .foregroundStyle(.secondary)
            } else {
                Text("\(knownValue.formatted()) known value\(unpricedCount > 0 ? " · \(unpricedCount) unpriced" : "")")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct SessionScanRow: View {
    let scan: RecentScan

    private var variantLabel: String {
        if let slab = scan.subject.slab {
            return slab.grade.display(company: slab.company)
        }
        return [
            scan.pokemonPrintRun?.label,
            scan.card.finishAndTreatmentDisplayLabel(for: scan.resolved.variant)
        ]
            .compactMap { $0 }
            .joined(separator: " · ")
    }

    var body: some View {
        HStack(spacing: 12) {
            CardThumbnail(url: scan.thumbnailURL, width: 42)

            VStack(alignment: .leading, spacing: 3) {
                Text(scan.card.name)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)
                Text(scan.identifier.scannerDisplayIdentifier(for: scan.card))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Text(variantLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)
            ScanPriceValue(lookup: scan.price, style: .review)
                .scaleEffect(0.72, anchor: .trailing)
                .fixedSize(horizontal: true, vertical: false)
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(scan.card.name), \(scan.identifier.scannerDisplayIdentifier(for: scan.card))")
    }
}
