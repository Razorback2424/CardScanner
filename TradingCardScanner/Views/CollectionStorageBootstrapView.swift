import SwiftUI
import UIKit

struct CollectionStorageBootstrapView: View {
    @ObservedObject var bootstrap: CollectionStorageBootstrap

    var body: some View {
        Group {
            switch bootstrap.state {
            case .loading:
                progressView(
                    title: "Checking collection storage…",
                    systemImage: "externaldrive"
                )
            case let .restoringFromCloud(readiness):
                restorationView(readiness)
            case let .confirmationRequired(request):
                confirmationView(request)
            case let .accountConflict(summary):
                conflictView(summary)
            case let .temporarilyUnavailable(message):
                actionView(
                    title: "iCloud unavailable",
                    message: message,
                    primaryTitle: "Retry",
                    primaryAction: { await bootstrap.retry() },
                    secondaryTitle: "Open Settings",
                    secondaryAction: openSystemSettings
                )
            case let .recoveryRequired(message):
                actionView(
                    title: "Storage recovery required",
                    message: message,
                    primaryTitle: "Retry",
                    primaryAction: { await bootstrap.retry() },
                    secondaryTitle: nil,
                    secondaryAction: nil
                )
            case .ready:
                EmptyView()
            }
        }
        .padding(24)
    }

    private func progressView(title: String, systemImage: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)
            Label(title, systemImage: systemImage)
                .font(.headline)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func restorationView(_ readiness: CloudRestorationReadiness) -> some View {
        switch readiness {
        case .checkingRemoteCollection, .importingRemoteCollection:
            progressView(
                title: "Restoring collection from iCloud…",
                systemImage: "icloud.and.arrow.down"
            )
        case .failed:
            actionView(
                title: "iCloud restoration needs attention",
                message: "CardScanner could not prove that the iCloud collection is ready yet. Retry after the device is online.",
                primaryTitle: "Retry",
                primaryAction: { await bootstrap.retry() },
                secondaryTitle: "Open Settings",
                secondaryAction: openSystemSettings
            )
        case .notApplicable:
            actionView(
                title: "iCloud restoration needs attention",
                message: "CardScanner did not receive a safe restoration proof, so it did not show an empty collection.",
                primaryTitle: "Retry",
                primaryAction: { await bootstrap.retry() },
                secondaryTitle: nil,
                secondaryAction: nil
            )
        case .readyEmpty, .readyPopulated:
            progressView(
                title: "Opening collection…",
                systemImage: "checkmark.icloud"
            )
        }
    }

    private func confirmationView(_ request: AccountAttachmentRequest) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Attach this collection to iCloud?", systemImage: "person.crop.circle.badge.questionmark")
                .font(.title3.weight(.semibold))
            Text("CardScanner found an existing on-device collection. It will remain unchanged unless you confirm attaching it to the current iCloud account.")
                .foregroundStyle(.secondary)
            Button("Attach to iCloud") {
                Task { await bootstrap.confirmAttachment() }
            }
            .buttonStyle(.borderedProminent)
            Button("Keep on This Device") {
                Task { await bootstrap.keepOnDevice() }
            }
            .buttonStyle(.bordered)
            Button("Open Settings", action: openSystemSettings)
                .buttonStyle(.borderless)
        }
        .frame(maxWidth: 480, alignment: .leading)
    }

    private func conflictView(_: AccountConflictSummary) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("Different iCloud collection found", systemImage: "exclamationmark.icloud")
                .font(.title3.weight(.semibold))
            Text("This iCloud account already contains a different CardScanner collection. CardScanner will not merge or overwrite either collection.")
                .foregroundStyle(.secondary)
            Button("Retry") {
                Task { await bootstrap.retry() }
            }
            .buttonStyle(.borderedProminent)
            Button("Open Settings", action: openSystemSettings)
                .buttonStyle(.bordered)
            if let support = CardScannerExternalLinks.support {
                Link("Contact Support", destination: support)
                    .accessibilityHint("Opens CardScanner support in your browser")
            }
        }
        .frame(maxWidth: 480, alignment: .leading)
    }

    private func actionView(
        title: String,
        message: String,
        primaryTitle: String,
        primaryAction: @escaping () async -> Void,
        secondaryTitle: String?,
        secondaryAction: (() -> Void)?
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(title, systemImage: "externaldrive.badge.exclamationmark")
                .font(.title3.weight(.semibold))
            Text(message)
                .foregroundStyle(.secondary)
            Button(primaryTitle) {
                Task { await primaryAction() }
            }
            .buttonStyle(.borderedProminent)
            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .buttonStyle(.bordered)
            }
            if let support = CardScannerExternalLinks.support {
                Link("Contact Support", destination: support)
            }
        }
        .frame(maxWidth: 480, alignment: .leading)
    }

    private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
