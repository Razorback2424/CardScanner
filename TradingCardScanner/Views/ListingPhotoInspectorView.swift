import SwiftUI
import UIKit

/// Full-screen review of one exported listing photo. The zoom and pan gestures
/// mirror `CardCenteringView.imageReview` so the two Pro tools behave the same
/// way under the finger.
struct ListingPhotoInspectorView: View {
    let url: URL
    let nativeDimensions: EbayListingPhotoExport.PixelDimensions

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var loadError: String?
    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero

    private var isDownsampled: Bool {
        max(nativeDimensions.width, nativeDimensions.height)
            > EbayListingPhotoExport.inspectionMaximumPixelDimension
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .scaleEffect(zoom)
                        .offset(panOffset)
                        .contentShape(Rectangle())
                        .gesture(
                            MagnifyGesture()
                                .onChanged { value in
                                    zoom = min(6, max(1, lastZoom * value.magnification))
                                }
                                .onEnded { _ in
                                    lastZoom = zoom
                                    if zoom == 1 {
                                        panOffset = .zero
                                        lastPanOffset = .zero
                                    }
                                }
                        )
                        .simultaneousGesture(
                            DragGesture()
                                .onChanged { value in
                                    guard zoom > 1 else { return }
                                    panOffset = CGSize(
                                        width: lastPanOffset.width + value.translation.width,
                                        height: lastPanOffset.height + value.translation.height
                                    )
                                }
                                .onEnded { _ in
                                    if zoom > 1 {
                                        lastPanOffset = panOffset
                                    } else {
                                        panOffset = .zero
                                        lastPanOffset = .zero
                                    }
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation(.easeOut(duration: 0.2)) {
                                zoom = zoom > 1 ? 1 : 3
                                panOffset = .zero
                            }
                            lastZoom = zoom > 1 ? 3 : 1
                            lastPanOffset = .zero
                        }
                        .accessibilityLabel(
                            "\(url.deletingPathExtension().lastPathComponent), \(nativeDimensions.width) by \(nativeDimensions.height) pixels"
                        )
                } else if let loadError {
                    ContentUnavailableView(
                        "Cannot Open Photo",
                        systemImage: "exclamationmark.triangle",
                        description: Text(loadError)
                    )
                } else {
                    ProgressView()
                        .controlSize(.large)
                        .tint(.white)
                }

                VStack {
                    Spacer()
                    caption
                }
            }
            .navigationTitle(url.deletingPathExtension().lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .task {
            do {
                image = try await EbayListingPhotoExport.makeInspectionImage(at: url)
            } catch is CancellationError {
                return
            } catch {
                loadError = error.localizedDescription
            }
        }
    }

    private var caption: some View {
        VStack(spacing: 3) {
            Text("\(nativeDimensions.width) × \(nativeDimensions.height) px")
                .font(.caption.monospacedDigit())
            if isDownsampled {
                Text("Shown at reduced size for review. Share → Files keeps every pixel.")
                    .font(.caption2)
                    .multilineTextAlignment(.center)
            }
        }
        .foregroundStyle(.white.opacity(0.85))
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.black.opacity(0.55), in: Capsule())
        .padding(.bottom, 24)
    }
}
