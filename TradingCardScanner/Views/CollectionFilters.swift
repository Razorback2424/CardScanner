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
