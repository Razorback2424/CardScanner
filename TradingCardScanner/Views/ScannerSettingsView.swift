import SwiftUI

/// Settings sheet for the scanner. Built as a `Form` from the start so that adding
/// the next setting is a new row rather than a layout rewrite.
struct ScannerSettingsView: View {
    @ObservedObject var scanner: CardScanner
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
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
