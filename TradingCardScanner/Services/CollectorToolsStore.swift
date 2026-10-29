import StoreKit
import SwiftUI

/// Only the StoreKit adapter constructs verified deliveries in production.
struct CollectorToolsDelivery: Sendable {
    let id: UInt64
    let isVerified: Bool
    let isIntendedProduct: Bool
}

enum CollectorToolsPurchaseResult {
    case delivery(CollectorToolsDelivery), cancelled, pending
}

@MainActor
protocol CollectorToolsClient: AnyObject {
    func loadPrice() async throws -> String?
    func purchase() async throws -> CollectorToolsPurchaseResult
    func currentOwnership() async -> Bool
    func updates() -> AsyncStream<CollectorToolsDelivery>
    func finish(_ delivery: CollectorToolsDelivery) async
    func sync() async throws
}

@MainActor
final class CollectorToolsStore: ObservableObject {
    static let productID = "com.seankeller.CardScanner.collectorTools"
    static let shared = CollectorToolsStore(client: StoreKitCollectorToolsClient())

    enum Ownership { case loading, unowned, owned }
    @Published private(set) var ownership: Ownership = .loading
    @Published private(set) var displayPrice: String?
    @Published private(set) var isLoadingProduct = false
    @Published private(set) var isBusy = false
    @Published private(set) var message: String?
#if LOCAL_COLLECTOR_TOOLS
    /// ProfileLocal is a release-optimized, locally signed build without the
    /// production iCloud entitlement. Enable paid UI for owner device testing;
    /// this condition is absent from every production configuration.
    var isOwned: Bool { true }
#else
    var isOwned: Bool { ownership == .owned }
#endif
    var canUseCentering: Bool { isOwned }
    func canPreparePhotos(cardCount: Int) -> Bool { cardCount == 1 || isOwned }

    private let client: any CollectorToolsClient
    private var listener: Task<Void, Never>?
    private var reconciliation = 0

    init(client: any CollectorToolsClient) { self.client = client }
    convenience init() { self.init(client: StoreKitCollectorToolsClient()) }
    deinit { listener?.cancel() }

    /// Called by the app, not by the offer's presentation lifecycle.
    func start() {
        guard listener == nil else { return }
        let stream = client.updates()
        listener = Task { [weak self] in
            for await delivery in stream {
                guard !Task.isCancelled else { return }
                await self?.handle(delivery)
            }
        }
        Task { await reconcile() }
        Task { await loadProduct() }
    }

    func reconcile() async {
        reconciliation &+= 1
        let revision = reconciliation
        let owned = await client.currentOwnership()
        guard revision == reconciliation else { return }
        // An authoritative empty snapshot removes access. Product lookup is independent.
        ownership = owned ? .owned : .unowned
    }

    func loadProduct() async {
        guard !isLoadingProduct else { return }
        isLoadingProduct = true
        defer { isLoadingProduct = false }
        do {
            displayPrice = try await client.loadPrice()
        } catch {
            displayPrice = nil
        }
    }

    func purchase() async {
        guard !isBusy, !isOwned, displayPrice != nil, ownership != .loading else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            switch try await client.purchase() {
            case .cancelled: message = "Purchase cancelled. Your work is still here."
            case .pending: message = "Awaiting approval. Your work is still here."
            case .delivery(let delivery): await handle(delivery)
            }
        } catch {
            message = "Purchase could not be completed. Please try again. Your work is still here."
        }
    }

    func restore() async {
        guard !isBusy else { return }
        isBusy = true
        message = nil
        defer { isBusy = false }
        do {
            try await client.sync()
            await reconcile()
            message = isOwned ? "Collector Tools restored." : "No Collector Tools purchase was found."
        } catch {
            message = "Purchases could not be restored. Please try again."
        }
    }

    private func handle(_ delivery: CollectorToolsDelivery) async {
        guard delivery.isVerified else {
            message = "The purchase could not be verified. Please try Restore Purchases."
            return
        }
        guard delivery.isIntendedProduct else { return }
        // Re-query even for duplicate deliveries: an older transaction must never
        // re-grant a revoked purchase. There are no export or navigation side effects.
        await reconcile()
        await client.finish(delivery)
    }
}

@MainActor
private final class StoreKitCollectorToolsClient: CollectorToolsClient {
    private var product: Product?
    private var transactions: [UInt64: StoreKit.Transaction] = [:]

    func loadPrice() async throws -> String? {
        product = try await Product.products(for: [CollectorToolsStore.productID])
            .first { $0.id == CollectorToolsStore.productID && $0.type == .nonConsumable }
        return product?.displayPrice
    }

    func purchase() async throws -> CollectorToolsPurchaseResult {
        guard let product else { throw StoreError.productUnavailable }
        switch try await product.purchase() {
        case .success(let result): return .delivery(delivery(result))
        case .userCancelled: return .cancelled
        case .pending: return .pending
        @unknown default: throw StoreError.productUnavailable
        }
    }

    func currentOwnership() async -> Bool {
        for await result in StoreKit.Transaction.currentEntitlements {
            if case .verified(let transaction) = result, eligible(transaction) { return true }
        }
        return false
    }

    func updates() -> AsyncStream<CollectorToolsDelivery> {
        AsyncStream { continuation in
            let task = Task {
                for await result in StoreKit.Transaction.updates {
                    guard !Task.isCancelled else { break }
                    continuation.yield(delivery(result))
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func eligible(_ transaction: StoreKit.Transaction) -> Bool {
        transaction.productID == CollectorToolsStore.productID
            && transaction.productType == .nonConsumable && transaction.revocationDate == nil
    }

    private func delivery(_ result: VerificationResult<StoreKit.Transaction>) -> CollectorToolsDelivery {
        switch result {
        case .verified(let transaction):
            if transaction.productID == CollectorToolsStore.productID,
               transaction.productType == .nonConsumable {
                transactions[transaction.id] = transaction
            }
            return .init(id: transaction.id, isVerified: true,
                         isIntendedProduct: transaction.productID == CollectorToolsStore.productID
                            && transaction.productType == .nonConsumable)
        case .unverified(let transaction, _):
            return .init(id: transaction.id, isVerified: false, isIntendedProduct: false)
        }
    }

    func finish(_ delivery: CollectorToolsDelivery) async {
        guard let transaction = transactions.removeValue(forKey: delivery.id) else { return }
        await transaction.finish()
    }
    func sync() async throws { try await AppStore.sync() }
    private enum StoreError: Error { case productUnavailable }
}
