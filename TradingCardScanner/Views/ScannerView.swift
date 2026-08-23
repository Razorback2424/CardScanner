import SwiftUI
import UIKit

struct ScannerView: View {
    @StateObject private var model = ScannerViewModel()

    var body: some View {
        ZStack(alignment: .top) {
            CameraPreview(scanner: model.scanner)
                .ignoresSafeArea()

            ScannerOverlay(
                scanner: model.scanner,
                phase: model.phase,
                lookupMessage: model.lookupMessage
            )
        }
        .animation(.easeOut(duration: 0.18), value: model.lookupMessage)
        .onAppear { model.start() }
        .onDisappear { model.viewDisappeared() }
        .fullScreenCover(item: $model.resultCard, onDismiss: {
            model.resetForNextScan()
        }) { card in
            CardResultView(card: card, setCode: model.resultSetCode)
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
private struct ScannerOverlay: View {
    @ObservedObject var scanner: CardScanner
    let phase: ScannerViewModel.Phase
    let lookupMessage: String?

    @State private var isShowingSettings = false

    var body: some View {
        ZStack(alignment: .top) {
            // The scan band sits in the lower half of the preview, so every piece of
            // chrome lives at the top. Nothing may overlap the band the user is
            // trying to line a card up inside.
            VStack(spacing: 10) {
                HStack {
                    Spacer()
                    settingsButton
                }

                statusPill

                if let lookupMessage {
                    Text(lookupMessage)
                        .font(.footnote.weight(.semibold))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .background(.red.opacity(0.85), in: Capsule())
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            if let issue = scanner.cameraIssue {
                cameraIssueMessage(issue)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            ScannerSettingsView(scanner: scanner)
        }
    }

    private var settingsButton: some View {
        Button {
            isShowingSettings = true
        } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 38)
                .background(.black.opacity(0.55), in: Circle())
                .overlay(Circle().stroke(.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Settings")
    }

    private var statusPill: some View {
        Group {
            if phase == .identifying {
                HStack(spacing: 8) {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                    Text("Identifying…")
                        .font(.subheadline.weight(.semibold))
                }
            } else {
                // The lens hint is the actionable half: knowing to move to ~5cm is
                // what makes macro work, and it changes with the selected lens.
                Text("\(scanner.lens.hint) · line the code up in the yellow box")
                    .font(.footnote.weight(.medium))
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.55), in: Capsule())
        .animation(.easeOut(duration: 0.15), value: phase)
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
