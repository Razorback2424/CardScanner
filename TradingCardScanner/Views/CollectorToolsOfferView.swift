import SwiftUI

struct CollectorToolsOfferView: View {
    @ObservedObject var store: CollectorToolsStore = .shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("One-time purchase")
                        .font(.headline)
                    Label("Unlimited batch listing-photo preparation and export", systemImage: "photo.stack")
                    Label("Unlimited guided card-centering measurement and annotated output", systemImage: "square.dashed.inset.filled")
                    Text("Single-card photos are free. Scanning, collection management, corrections and basic collection-data import/export stay free.")
                    Text("Centering is a guided estimate, not professional grading or a predicted grade. Review and confirm both frames.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    if store.isOwned {
                        Label("Collector Tools unlocked", systemImage: "checkmark.circle")
                        Button("Continue") { dismiss() }
                    } else if store.ownership == .loading {
                        ProgressView("Checking purchases…")
                    } else if let price = store.displayPrice {
                        Button("Unlock Collector Tools — \(price)") {
                            Task { await store.purchase() }
                        }
                        .disabled(store.isBusy)
                    } else if store.isLoadingProduct {
                        ProgressView("Loading price…")
                    } else {
                        Text("Purchase information is unavailable. Please try again.")
                        Button("Retry") { Task { await store.loadProduct() } }
                    }
                    Button("Restore Purchases") { Task { await store.restore() } }
                        .disabled(store.isBusy)
                    if store.isBusy { ProgressView("Contacting the App Store…") }
                    if let message = store.message { Text(message) }
                }
            }
            .navigationTitle("Collector Tools")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
            .task { await store.loadProduct() }
        }
    }
}
