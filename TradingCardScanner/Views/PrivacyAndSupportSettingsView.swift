import SwiftUI

struct PrivacyAndSupportSettingsView: View {
    var body: some View {
        Form {
            Section("Legal") {
                if let privacy = CardScannerExternalLinks.privacyPolicy {
                    Link("Privacy Policy", destination: privacy)
                        .accessibilityHint("Opens the CardScanner privacy policy in your browser")
                } else {
                    Text("Privacy policy link is not available in this build.")
                        .foregroundStyle(.secondary)
                }

                if let support = CardScannerExternalLinks.support {
                    Link("Support Website", destination: support)
                        .accessibilityHint("Opens CardScanner support in your browser")
                } else {
                    Text("Support link is not available in this build.")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Collection storage") {
                Text("CardScanner 1.0 stores your collection on this device. iCloud sync is not available in this release.")
                Text("Value History, price observations, reference quotes, check days, and custom artwork also stay on this device.")
            }

            Section("Custom artwork") {
                Text("Custom artwork is stored on this device and is not currently synced with iCloud.")
            }

            Section("Export and deletion") {
                Text("CSV export is available from Collection & Portfolio settings. Deleting the collection removes its card records and current ownership. Removal activity, price records, and Value History remain on this device.")
            }
        }
        .navigationTitle("Privacy & Support")
        .navigationBarTitleDisplayMode(.inline)
    }
}
