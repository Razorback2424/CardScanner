import SwiftUI

/// Settings sheet for the scanner. Built as a `Form` from the start so that adding
/// the next setting is a new row rather than a layout rewrite.
struct ScannerSettingsView: View {
    @ObservedObject var scanner: CardScanner
    let finishLock: (CardGame) -> PhysicalVariant?
    let setFinishLock: (PhysicalVariant?, CardGame) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                finishLockSection
                cameraSection
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    /// Contextual evidence the user already has: a stack of reverses really is a
    /// stack of reverses. Set here rather than on the camera because it is a
    /// property of the pile being worked through, not of the card in frame.
    ///
    /// One lock per game. The scanner no longer knows which game is coming next,
    /// so a single shared lock would either be wrong half the time or would have
    /// to be re-set every time the pile changed game.
    private var finishLockSection: some View {
        Section {
            ForEach(CardGame.allCases) { game in
                Picker(game.label, selection: lockBinding(for: game)) {
                    Text("Auto").tag(PhysicalVariant?.none)
                    ForEach(PhysicalVariant.selectable(for: game)) { variant in
                        Text(variant.label).tag(PhysicalVariant?.some(variant))
                    }
                }
            }
        } header: {
            Text("Finish Lock")
        } footer: {
            Text("On Auto, a card whose finish cannot be determined asks for one tap. A lock answers that question in advance — but only where the catalog agrees the finish is physically possible, so it can never record a variant that was never printed.")
        }
    }

    @ViewBuilder
    private var cameraSection: some View {
        Section {
            if scanner.availableLenses.count > 1 {
                Picker("Lens", selection: lensBinding) {
                    ForEach(scanner.availableLenses) { lens in
                        Text(lens.label).tag(lens)
                    }
                }
                .pickerStyle(.segmented)
            } else {
                LabeledContent("Lens", value: scanner.lens.label)
            }
        } header: {
            Text("Camera")
        } footer: {
            if scanner.availableLenses.contains(.macro) {
                Text("Macro uses the ultra wide lens, which focuses down to a few centimetres. The standard lens cannot focus close enough to read a card's set code.")
            } else {
                Text("This device has no ultra wide camera that can focus close, so only the standard lens is available.")
            }
        }
    }

    private func lockBinding(for game: CardGame) -> Binding<PhysicalVariant?> {
        Binding(
            get: { finishLock(game) },
            set: { setFinishLock($0, game) }
        )
    }

    /// `scanner.lens` is `private(set)` and only changes once the capture session has
    /// actually swapped inputs, so the picker writes through `setLens` and reads back
    /// the hardware's answer rather than holding its own selection state.
    private var lensBinding: Binding<CameraLens> {
        Binding(
            get: { scanner.lens },
            set: { scanner.setLens($0) }
        )
    }
}
