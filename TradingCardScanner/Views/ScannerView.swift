import SwiftData
import SwiftUI

/// One continuous session. The camera is the product surface and never goes
/// away: there is no result screen, no confirm step, and no dismiss animation
/// between cards. Success is a receipt that appears underneath while the next
/// card is already being read.
struct ScannerView: View {
    @EnvironmentObject private var model: ScannerViewModel
    @Environment(\.modelContext) private var modelContext

    @State private var isShowingSettings = false
    @State private var reviewing: RecentScan?
    @State private var isShowingUnresolved = false

    var body: some View {
        ZStack {
            CameraPreview(scanner: model.scanner, successCount: model.successCount)
                .ignoresSafeArea()

            ScannerChrome(
                model: model,
                scanner: model.scanner,
                openSettings: {
                    model.pauseForPresentation()
                    isShowingSettings = true
                },
                openReview: { scan in
                    model.pauseForPresentation()
                    reviewing = scan
                },
                openUnresolved: {
                    model.pauseForPresentation()
                    isShowingUnresolved = true
                }
            )
        }
        .onAppear { model.start(context: modelContext) }
        .onDisappear { model.viewDisappeared() }
        .sheet(isPresented: $isShowingSettings, onDismiss: model.resumeAfterPresentation) {
            SettingsView()
        }
        .sheet(item: $reviewing, onDismiss: model.resumeAfterPresentation) { scan in
            ScanReviewSheet(scan: scan) { variant in
                model.correct(scanID: scan.id, to: variant)
            }
        }
        .sheet(isPresented: $isShowingUnresolved, onDismiss: model.resumeAfterPresentation) {
            UnresolvedScansSheet(
                scans: model.unresolvedScans,
                onClear: model.clearUnresolvedScans
            )
        }
    }
}

/// Everything that reads `CardScanner` state lives here, behind an `@ObservedObject`.
///
/// `ScannerView` observes the view model, and the scanner is a *second*
/// `ObservableObject` hanging off it. SwiftUI does not follow that second hop: a
/// `@Published` change on the scanner invalidates nothing unless some view holds the
/// scanner itself as an observed object. Reading `model.scanner.lens` from
/// `ScannerView` compiles and returns the right value, but never redraws — the lens
/// switched while the UI stayed frozen on the old selection.
private struct ScannerChrome: View {
    @ObservedObject var model: ScannerViewModel
    @ObservedObject var scanner: CardScanner
    let openSettings: () -> Void
    let openReview: (RecentScan) -> Void
    let openUnresolved: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            topBar

            if let note = model.note {
                ScanNoteView(note: note)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }

            Spacer(minLength: 0)

            bottomStack
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
        .overlay {
            if let issue = scanner.cameraIssue {
                cameraIssueMessage(issue)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.receipt)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.pendingChoice)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.pendingPrintRunChoice)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.pendingIdentityChoice)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: model.pendingHistoricalTitleScan)
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: model.recent)
        .animation(.easeOut(duration: 0.18), value: model.note)
    }

    // MARK: - Top

    /// Almost nothing. There is no game picker because the printed identifier
    /// already says which game the card is, and asking the user to pre-declare it
    /// was asking for information the card carries.
    private var topBar: some View {
        HStack(spacing: 8) {
            if model.isSlowIdentifying {
                ProgressView()
                    .tint(.white)
                    .controlSize(.small)
                    .transition(.opacity)
            }

            Spacer(minLength: 0)

            // Finish Lock is configured in Settings, but a lock silently
            // resolving finishes is exactly the kind of thing that must never be
            // invisible. This says one is on and goes straight to where it lives.
            if !model.activeFinishLocks.isEmpty {
                finishLockIndicator
            }

            settingsButton
        }
        .animation(.easeOut(duration: 0.2), value: model.isSlowIdentifying)
    }

    private var finishLockIndicator: some View {
        Button(action: openSettings) {
            HStack(spacing: 5) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(model.activeFinishLocks.map { $0.variant.label }.joined(separator: " · "))
                    .font(.footnote.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(.black)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .background(Color.yellow, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Finish lock active: \(model.activeFinishLocks.map { $0.variant.label }.joined(separator: ", ")). Opens settings.")
    }

    private var settingsButton: some View {
        Button(action: openSettings) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(.black.opacity(0.55), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }

    // MARK: - Bottom

    private var bottomStack: some View {
        VStack(spacing: 9) {
            if let titleScan = model.pendingHistoricalTitleScan {
                HistoricalTitleScanBar(
                    scan: titleScan,
                    onDismiss: model.cancelHistoricalTitleScan
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let choice = model.pendingIdentityChoice {
                IdentityChoiceBar(
                    choice: choice,
                    onChoose: model.choose,
                    onDismiss: model.dismissIdentityChoice
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let choice = model.pendingPrintRunChoice {
                PrintRunChoiceBar(
                    choice: choice,
                    onChoose: model.choose,
                    onDismiss: model.dismissPrintRunChoice
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let choice = model.pendingChoice {
                VariantChoiceBar(
                    choice: choice,
                    onChoose: model.choose,
                    onDismiss: model.dismissChoice
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            } else if let receipt = model.receipt {
                ScanReceiptCard(
                    receipt: receipt,
                    onUndo: model.undoLastAdd,
                    onOpen: {
                        guard let scan = model.recent.first(where: { $0.id == receipt.scanID }) else { return }
                        openReview(scan)
                    }
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            HStack(alignment: .bottom, spacing: 8) {
                if !model.recent.isEmpty {
                    RecentScanRail(scans: model.recent, onSelect: openReview)
                }

                Spacer(minLength: 0)

                if model.unresolvedCount > 0 {
                    unresolvedChip
                }
            }

        }
    }

    private var unresolvedChip: some View {
        Button(action: openUnresolved) {
            Text("\(model.unresolvedCount) need\(model.unresolvedCount == 1 ? "s" : "") attention")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(.orange.opacity(0.85), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityHint("Shows what was read and why it was not added")
    }

    private func cameraIssueMessage(_ issue: CameraIssue) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
            Text(issue.message)
                .multilineTextAlignment(.center)
        }
        .padding(24)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(30)
    }
}

private struct UnresolvedScansSheet: View {
    @Environment(\.dismiss) private var dismiss
    let scans: [UnresolvedScan]
    let onClear: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("Nothing in this list was added to your collection. Use the details below to reposition and scan again.")
                        .foregroundStyle(.secondary)
                }

                Section("Needs attention") {
                    ForEach(scans) { scan in
                        VStack(alignment: .leading, spacing: 5) {
                            Text(scan.identifier.displayIdentifier)
                                .font(.headline.monospacedDigit())
                            if !scan.titleCandidates.isEmpty {
                                Text("Title read: \(scan.titleCandidates.joined(separator: ", "))")
                                    .font(.subheadline)
                            }
                            Text("No unique catalog match was confirmed")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .navigationTitle("Unresolved Scans")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if !scans.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear", role: .destructive) {
                            onClear()
                            dismiss()
                        }
                    }
                }
            }
        }
    }
}
