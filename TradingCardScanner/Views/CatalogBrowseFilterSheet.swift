import SwiftUI

/// Filter choices for one game's Browse grid. Options come from the catalog
/// (sets) and from what the game's rows have shown (finishes, treatments).
struct CatalogBrowseFilterSheet: View {
    /// A binding rather than `\.dismiss`: in a wide window this is an inspector
    /// column, not a sheet.
    @Binding var isPresented: Bool
    @Binding var filters: CatalogBrowseFilters
    let game: CardGame
    let sets: [CatalogSet]
    let finishOptions: [PhysicalVariant]
    let treatmentIDs: [String]

    var body: some View {
        NavigationStack {
            Form {
                Section("Show") {
                    Picker("Ownership", selection: $filters.ownership) {
                        ForEach(CatalogOwnershipFilter.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Details") {
                    NavigationLink {
                        MultiSelectFilterView(
                            title: "Sets", options: setOptions, selection: setSelection, showsCounts: false
                        )
                    } label: {
                        detailRow("Sets", value: selectionLabel(filters.setIDs.count, singular: "set"))
                    }
                    if !finishOptions.isEmpty {
                        NavigationLink {
                            MultiSelectFilterView(
                                title: "Finish",
                                options: finishOptions.map {
                                    FilterOption(id: $0.id, label: $0.label, group: nil, count: 0)
                                },
                                selection: $filters.variantIDs,
                                showsCounts: false
                            )
                        } label: {
                            detailRow("Finish", value: selectionLabel(filters.variantIDs.count, singular: "finish"))
                        }
                    }
                    if !treatmentIDs.isEmpty {
                        NavigationLink {
                            MultiSelectFilterView(
                                title: "Treatment",
                                options: treatmentIDs.map {
                                    FilterOption(id: $0, label: MagicTreatment(id: $0)?.label ?? $0, group: nil, count: 0)
                                },
                                selection: $filters.magicTreatmentIDs,
                                showsCounts: false
                            )
                        } label: {
                            detailRow(
                                "Treatment",
                                value: selectionLabel(filters.magicTreatmentIDs.count, singular: "treatment")
                            )
                        }
                    }
                }

                if filters.isActive {
                    Section {
                        Button("Clear All Filters", role: .destructive) { filters = .none }
                    }
                }
            }
            .navigationTitle("Filter \(game.label)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { isPresented = false }
                }
            }
        }
    }

    /// Newest first, grouped by release year so a long directory stays scannable.
    private var setOptions: [FilterOption] {
        sets.map { set in
            let year = set.releaseDate.map { String(Calendar.current.component(.year, from: $0)) }
            return FilterOption(id: set.catalogID.id, label: set.name, group: year ?? "Other", count: 0)
        }
    }

    private var setSelection: Binding<Set<String>> {
        Binding(
            get: { Set(filters.setIDs.map(\.id)) },
            set: { ids in
                filters.setIDs = Set(sets.lazy.map(\.catalogID).filter { ids.contains($0.id) })
            }
        )
    }

    private func detailRow(_ title: String, value: String) -> some View {
        LabeledContent(title, value: value)
    }

    private func selectionLabel(_ count: Int, singular: String) -> String {
        switch count {
        case 0: return "Any"
        case 1: return "1 \(singular)"
        default: return "\(count) \(singular == "finish" ? "finishes" : singular + "s")"
        }
    }
}

/// One removable chip per active filter, under the search field, so a short
/// grid always explains itself.
struct CatalogBrowseFilterChips: View {
    @Binding var filters: CatalogBrowseFilters
    let sets: [CatalogSet]

    private struct Chip: Identifiable {
        let id: String
        let label: String
        let remove: (inout CatalogBrowseFilters) -> Void
    }

    private var chips: [Chip] {
        var chips: [Chip] = []
        if filters.ownership != .all {
            chips.append(Chip(id: "ownership", label: filters.ownership.label) { $0.ownership = .all })
        }
        if filters.setIDs.count > 2 {
            chips.append(Chip(id: "sets", label: "\(filters.setIDs.count) sets") { $0.setIDs.removeAll() })
        } else {
            for set in sets where filters.setIDs.contains(set.catalogID) {
                chips.append(Chip(id: "set-\(set.catalogID.id)", label: set.name) { $0.setIDs.remove(set.catalogID) })
            }
        }
        for id in filters.variantIDs.sorted() {
            chips.append(Chip(id: "finish-\(id)", label: PhysicalVariant.resolving(id).label) { $0.variantIDs.remove(id) })
        }
        for id in filters.magicTreatmentIDs.sorted() {
            chips.append(Chip(id: "treatment-\(id)", label: MagicTreatment(id: id)?.label ?? id) {
                $0.magicTreatmentIDs.remove(id)
            })
        }
        if let price = filters.price {
            chips.append(Chip(id: "price", label: price.label) { $0.price = nil })
        }
        return chips
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips) { chip in
                    Button {
                        chip.remove(&filters)
                    } label: {
                        HStack(spacing: 4) {
                            Text(chip.label).lineLimit(1)
                            Image(systemName: "xmark").font(.caption2.weight(.bold))
                        }
                        .font(.subheadline.weight(.medium))
                        .padding(.horizontal, 12)
                        .frame(minHeight: 32)
                        .background(Color("RefreshAccent").opacity(0.18), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Remove filter \(chip.label)")
                }
                Button("Clear") { filters = .none }
                    .font(.subheadline.weight(.medium))
                    .frame(minHeight: 44)
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 4)
        .background(Color(uiColor: .systemBackground))
    }
}

/// The toolbar control. The badge counts filter groups, matching the label.
struct CatalogBrowseFilterButton: View {
    let activeCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Filters", systemImage: "line.3.horizontal.decrease")
                .foregroundStyle(activeCount > 0 ? Color("RefreshAccent") : .primary)
                .overlay(alignment: .topTrailing) {
                    if activeCount > 0 {
                        Text("\(activeCount)")
                            .font(.caption2.weight(.bold))
                            .monospacedDigit()
                            .foregroundStyle(.black)
                            .padding(.horizontal, 4)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(Color("RefreshAccent"), in: Capsule())
                            .offset(x: 8, y: -6)
                    }
                }
        }
        .accessibilityLabel(activeCount > 0 ? "Filters, \(activeCount) active" : "Filters")
    }
}
