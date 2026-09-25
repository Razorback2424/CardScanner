import SwiftUI

struct UnresolvedScanDetailView: View {
    @ObservedObject var model: ScannerViewModel
    let scan: UnresolvedScan
    let onDismissRow: () -> Void
    let onResolve: (UnresolvedResolutionChoice) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var candidates: [PokemonCatalogCardIdentity] = []
    @State private var isLoadingCandidates = false
    @State private var isShowingCatalogSearch = false

    private var canChooseCard: Bool {
        scan.game == .pokemon && scan.pokemonNumber != nil
    }

    var body: some View {
        List {
            Section("Read") {
                LabeledContent("Identifier", value: scan.displayIdentifier)
                LabeledContent("Catalog request", value: scan.requestEvidence.catalogIdentifier)
                if !scan.requestEvidence.titleReadings.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Title readings")
                            .font(.subheadline.weight(.medium))
                        Text(scan.requestEvidence.titleReadings.joined(separator: ", "))
                            .foregroundStyle(.secondary)
                    }
                }
                LabeledContent("Reason", value: scan.reason.detail)
                Text(scan.createdAt, style: .date)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if scan.isReadOnly {
                Section {
                    Label("This saved identifier is not available in the installed catalog, so it can only be dismissed.", systemImage: "info.circle")
                        .foregroundStyle(.secondary)
                }
            } else {
                if canChooseCard {
                    Section("Choose card") {
                        if isLoadingCandidates && candidates.isEmpty {
                            ProgressView("Finding matching cards…")
                        } else if candidates.isEmpty {
                            Text("No offline candidates are available for this number.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(candidates, id: \.providerID) { candidate in
                                Button {
                                    onResolve(.choose(candidate))
                                } label: {
                                    candidateRow(candidate)
                                }
                                .buttonStyle(.plain)
                                .accessibilityHint("Use this catalog printing for the saved scan")
                            }
                        }
                    }
                }

                Section("Actions") {
                    switch scan.reason {
                    case .lookupFailed, .providerUnavailable, .noCatalogEntry:
                        Button("Retry lookup", systemImage: "arrow.clockwise") {
                            onResolve(.retryLookup)
                        }
                    case .saveFailed:
                        if scan.pendingCommit != nil {
                            Button("Retry save", systemImage: "square.and.arrow.down") {
                                onResolve(.retrySave)
                            }
                        } else {
                            Button("Retry lookup", systemImage: "arrow.clockwise") {
                                onResolve(.retryLookup)
                            }
                        }
                    case .noConfirmedMatch:
                        EmptyView()
                    }

                    Button("Search catalog", systemImage: "magnifyingglass") {
                        isShowingCatalogSearch = true
                    }
                }
            }

            Section {
                Button("Dismiss", role: .destructive) {
                    onDismissRow()
                    dismiss()
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("Needs attention")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: scan.id) {
            guard canChooseCard, !scan.isReadOnly else { return }
            isLoadingCandidates = true
            candidates = await model.unresolvedCandidates(for: scan.id)
            isLoadingCandidates = false
        }
        .sheet(isPresented: $isShowingCatalogSearch) {
            NavigationStack {
                BrowseView(catalog: BrowseCatalog())
            }
        }
    }

    @ViewBuilder
    private func candidateRow(_ candidate: PokemonCatalogCardIdentity) -> some View {
        HStack(spacing: 12) {
            AsyncImage(url: candidate.thumbnailURL) { image in
                image.resizable().scaledToFit()
            } placeholder: {
                RoundedRectangle(cornerRadius: 6)
                    .fill(.quaternary)
                    .overlay { Image(systemName: "rectangle.portrait") }
            }
            .frame(width: 48, height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            VStack(alignment: .leading, spacing: 3) {
                Text(candidate.name.isEmpty ? "Unknown card name" : candidate.name)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text("\(candidate.setName) · \(candidate.localID)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "checkmark.circle")
                .foregroundStyle(.tint)
        }
        .contentShape(Rectangle())
    }
}
