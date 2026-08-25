import SwiftUI

/// One of the four dimensions. Neutral until it is doing something, and then it
/// says what it is doing — the chip itself is the state readout, so there is no
/// filter drawer to keep open and no advanced-search screen to go to.
struct FilterChip: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.subheadline.weight(isActive ? .semibold : .regular))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(isActive ? Color.white : Color.primary)
            .background(
                isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }
}

/// A choice with the number of cards behind it, so filtering is never a guess
/// about what is on the other side.
struct FilterOption: Identifiable, Equatable {
    let id: String
    let label: String
    let group: String?
    let count: Int
}

/// One entry point for every collection filter and sort choice. Detailed
/// multi-select dimensions stay nested so the first screen remains scannable.
struct CollectionFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var filters: CollectionFilters
    @Binding var sort: CollectionSort
    let setOptions: [FilterOption]
    let finishOptions: [FilterOption]
    let gradingCompanyOptions: [FilterOption]
    let gradeOptions: [FilterOption]

    @State private var nestedSheet: NestedSheet?

    private enum NestedSheet: String, Identifiable {
        case sets, finishes, price, gradingCompanies, grades
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Show") {
                    Picker("Game", selection: gameSelection) {
                        Text("All Games").tag(nil as CardGame?)
                        ForEach(CardGame.allCases) { game in
                            Text(game.label).tag(game as CardGame?)
                        }
                    }
                }

                Section("Item Type") {
                    itemKindRow(
                        title: "All Items",
                        symbolName: "square.grid.2x2",
                        isSelected: filters.itemKinds.isEmpty
                    ) {
                        filters.itemKinds.removeAll()
                    }

                    ForEach(CollectionItemKind.allCases, id: \.self) { kind in
                        itemKindRow(
                            title: kind.label,
                            symbolName: kind.symbolName,
                            isSelected: filters.itemKinds.contains(kind)
                        ) {
                            if filters.itemKinds.contains(kind) {
                                filters.itemKinds.remove(kind)
                                if kind == .gradedCard {
                                    filters.gradingCompanies.removeAll()
                                    filters.gradeValues.removeAll()
                                }
                            } else {
                                filters.itemKinds.insert(kind)
                            }
                        }
                    }
                }

                Section("Details") {
                    detailRow("Sets", value: selectionLabel(filters.setCodes, singular: "set")) {
                        nestedSheet = .sets
                    }
                    detailRow("Price", value: filters.price?.label ?? "Any") {
                        nestedSheet = .price
                    }
                    detailRow("Finish", value: selectionLabel(filters.variantIDs, singular: "finish")) {
                        nestedSheet = .finishes
                    }
                }

                if filters.itemKinds.isEmpty || filters.itemKinds.contains(.gradedCard) {
                    Section("Graded") {
                        detailRow(
                            "Grading Company",
                            value: selectionLabel(filters.gradingCompanies, singular: "company")
                        ) {
                            nestedSheet = .gradingCompanies
                        }
                        detailRow(
                            "Grade",
                            value: selectionLabel(filters.gradeValues, singular: "grade")
                        ) {
                            nestedSheet = .grades
                        }
                    }
                }

                Section("Order") {
                    Picker("Sort By", selection: $sort) {
                        ForEach(CollectionSort.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                }

                if filters.isActive {
                    Section {
                        Button("Clear All Filters", role: .destructive) {
                            filters = .none
                        }
                    }
                }
            }
            .navigationTitle("Filter Collection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sheet(item: $nestedSheet) { sheet in
            switch sheet {
            case .sets:
                MultiSelectFilterSheet(
                    title: "Sets",
                    options: setOptions,
                    selection: $filters.setCodes
                )
            case .finishes:
                MultiSelectFilterSheet(
                    title: "Finish",
                    options: finishOptions,
                    selection: $filters.variantIDs
                )
            case .price:
                PriceFilterSheet(selection: $filters.price)
            case .gradingCompanies:
                MultiSelectFilterSheet(
                    title: "Grading Company",
                    options: gradingCompanyOptions,
                    selection: gradingCompanySelection
                )
            case .grades:
                MultiSelectFilterSheet(
                    title: "Grade",
                    options: gradeOptions,
                    selection: $filters.gradeValues
                )
            }
        }
    }

    private var gradingCompanySelection: Binding<Set<String>> {
        Binding(
            get: { Set(filters.gradingCompanies.map(\.rawValue)) },
            set: { values in
                filters.gradingCompanies = Set(values.compactMap(GradingCompany.init(rawValue:)))
            }
        )
    }

    private var gameSelection: Binding<CardGame?> {
        Binding(
            get: { filters.game },
            set: { game in
                guard filters.game != game else { return }
                filters.game = game
                filters.setCodes.removeAll()
                filters.variantIDs.removeAll()
            }
        )
    }

    private func selectionLabel<Value: Hashable>(_ selection: Set<Value>, singular: String) -> String {
        switch selection.count {
        case 0: return "Any"
        case 1: return "1 \(singular)"
        default: return "\(selection.count) \(singular)s"
        }
    }

    private func itemKindRow(
        title: String,
        symbolName: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: symbolName)
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .fontWeight(.semibold)
                        .foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
    }

    private func detailRow(
        _ title: String,
        value: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack {
                Text(title).foregroundStyle(.primary)
                Spacer()
                Text(value).foregroundStyle(.secondary)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Multi-select list used for both Set and Finish. Options come from the
/// collection itself: a set the user owns nothing from is not a choice, and a
/// finish they own none of would only be clutter.
struct MultiSelectFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let options: [FilterOption]
    @Binding var selection: Set<String>

    private var groups: [String] {
        var seen: [String] = []
        for option in options {
            let group = option.group ?? ""
            if !seen.contains(group) { seen.append(group) }
        }
        return seen
    }

    var body: some View {
        NavigationStack {
            Group {
                if options.isEmpty {
                    ContentUnavailableView(
                        "Nothing to filter yet",
                        systemImage: "line.3.horizontal.decrease.circle",
                        description: Text("Scan some cards first.")
                    )
                } else {
                    List {
                        ForEach(groups, id: \.self) { group in
                            Section {
                                ForEach(options.filter { ($0.group ?? "") == group }) { option in
                                    row(option)
                                }
                            } header: {
                                if !group.isEmpty { Text(group) }
                            }
                        }
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Clear") { selection.removeAll() }
                        .disabled(selection.isEmpty)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(_ option: FilterOption) -> some View {
        Button {
            if selection.contains(option.id) {
                selection.remove(option.id)
            } else {
                selection.insert(option.id)
            }
        } label: {
            HStack {
                Image(systemName: selection.contains(option.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selection.contains(option.id) ? Color.accentColor : Color.secondary)
                Text(option.label)
                Spacer()
                Text("\(option.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .buttonStyle(.plain)
    }
}

/// Bands rather than a slider: card prices are distributed far too unevenly for
/// a slider to land anywhere useful. Custom covers everything else.
struct PriceFilterSheet: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selection: PriceFilter?

    @State private var customMin: String = ""
    @State private var customMax: String = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    row(title: "Any", isSelected: selection == nil) { selection = nil }
                    ForEach(PriceBand.allCases) { band in
                        row(title: band.label, isSelected: selection == .band(band)) {
                            selection = .band(band)
                        }
                    }
                } footer: {
                    Text("Price is the current market price of one copy. Ten copies of a $2 card is still a $2 card.")
                }

                // Its own section because it asks a different question from the
                // bands above: not how much a card is worth, but which cards the
                // app still has no price for.
                Section {
                    row(title: "Unpriced", isSelected: selection == .unpriced) {
                        selection = .unpriced
                    }
                } footer: {
                    Text("Cards no price source covers yet.")
                }

                Section("Custom") {
                    HStack {
                        Text("Min")
                        TextField("Any", text: $customMin)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Max")
                        TextField("Any", text: $customMax)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    Button("Apply range") { applyCustom() }
                        .disabled(Double(customMin) == nil && Double(customMax) == nil)
                }
            }
            .navigationTitle("Price")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if case let .custom(min, max) = selection {
                    customMin = min.map { String($0) } ?? ""
                    customMax = max.map { String($0) } ?? ""
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func applyCustom() {
        selection = .custom(min: Double(customMin), max: Double(customMax))
        dismiss()
    }

    private func row(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(title)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .foregroundStyle(Color.accentColor)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
