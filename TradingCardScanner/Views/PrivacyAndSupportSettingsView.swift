import SwiftUI

struct PrivacyAndSupportSettingsView: View {
    var body: some View {
        Form {
            Section("Legal") {
                if let privacy = CardScannerExternalLinks.privacyPolicy {
                    Link("Privacy Policy", destination: privacy)
                        .accessibilityHint("Opens the CardScanner privacy policy in your browser")
                } else {
                    Text("Privacy Policy link is configured for the release build.")
                        .foregroundStyle(.secondary)
                }

                if let support = CardScannerExternalLinks.support {
                    Link("Support Website", destination: support)
                        .accessibilityHint("Opens CardScanner support in your browser")
                } else {
                    Text("Support Website link is configured for the release build.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Collection sync") {
                Text("CardScanner syncs structured collection records—cards, prices, product identities, activity, and inventory events—to your private iCloud database when storage is attached.")
                Text("Value History, price observations, reference quotes, check days, and custom artwork are stored on this device and are not currently synced with iCloud.")
            }

            Section("Custom artwork") {
                Text("Custom artwork is stored on this device and is not currently synced with iCloud.")
            }

            Section("Export and deletion") {
                Text("CSV export is available from Collection & Portfolio settings. Deleting the collection removes the local records; iCloud copies follow the storage and account controls shown by the system.")
            }
        }
        .navigationTitle("Privacy & Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}
