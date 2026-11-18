import StoreKit
import UIKit

// The one thing Swivel sells: the full game, a single purchase that is never used up
// (product id com.brightfold.swivel.full, set up in App Store Connect as a non-consumable,
// with Family Sharing on).
//
// The page asks for it (the page's "buy" and "restore" messages) and is told what the App Store
// said, through window.__swivelFull, as {"owned": Bool, "price": String, "result": String}.
// result is one of bought, restored, none, pending, cancelled or failed, or empty when the app is
// only passing on a change (a purchase made on another device, approved by a parent, or refunded).
// The page never sees a payment. Whether the player owns it is kept here too, so the page knows at
// once on the next start, even with no network.
@MainActor
final class Store {
    static let productID = "com.brightfold.swivel.full"

    var onChange: ((String) -> Void)?
    private let defaults = UserDefaults.standard
    private var product: Product?
    private var updates: Task<Void, Never>? // (the store lives as long as the app)

    private(set) var owned: Bool {
        get { defaults.bool(forKey: "full.owned") }
        set { defaults.set(newValue, forKey: "full.owned") }
    }
    private var price: String {
        product?.displayPrice ?? defaults.string(forKey: "full.price") ?? ""
    }

    // what the page is handed before its own script runs
    var handover: [String: Any] { ["owned": owned, "price": price] }

    func start() {
        // purchases finished elsewhere: on another device, approved by a parent, refunded
        updates = Task { [weak self] in
            for await update in Transaction.updates {
                await self?.take(update)
            }
        }
        Task { [weak self] in
            await self?.check()
            await self?.loadProduct()
        }
    }

    // what the phone already knows the player owns (it works without a network)
    func check() async {
        var has = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let t) = entitlement, t.productID == Store.productID, t.revocationDate == nil { has = true }
        }
        if has != owned {
            owned = has
            send(result: "")
        }
    }

    private func loadProduct() async {
        guard product == nil else { return }
        guard let found = try? await Product.products(for: [Store.productID]).first else { return }
        product = found
        if defaults.string(forKey: "full.price") != found.displayPrice {
            defaults.set(found.displayPrice, forKey: "full.price")
            send(result: "")
        }
    }

    func buy(in scene: UIWindowScene?) async {
        await loadProduct()
        guard let product = product else { send(result: "failed"); return }
        do {
            let outcome: Product.PurchaseResult
            if #available(iOS 17.0, *), let scene = scene {
                outcome = try await product.purchase(confirmIn: scene)
            } else {
                outcome = try await product.purchase()
            }
            switch outcome {
            case .success(let verification):
                guard case .verified(let t) = verification else { send(result: "failed"); return }
                await t.finish()
                owned = t.revocationDate == nil
                send(result: owned ? "bought" : "failed")
            case .userCancelled:
                send(result: "cancelled")
            case .pending:
                send(result: "pending") // a parent's Ask to Buy, or a payment to confirm: it arrives through updates
            @unknown default:
                send(result: "failed")
            }
        } catch {
            send(result: "failed")
        }
    }

    // Restore purchases: asks the App Store for this Apple Account's purchases again.
    func restore() async {
        try? await AppStore.sync()
        var has = false
        for await entitlement in Transaction.currentEntitlements {
            if case .verified(let t) = entitlement, t.productID == Store.productID, t.revocationDate == nil { has = true }
        }
        owned = has
        send(result: has ? "restored" : "none")
    }

    private func take(_ update: VerificationResult<Transaction>) async {
        guard case .verified(let t) = update, t.productID == Store.productID else { return }
        await t.finish()
        let has = t.revocationDate == nil
        if has != owned {
            owned = has
            send(result: "")
        }
    }

    private func send(result: String) {
        let message: [String: Any] = ["owned": owned, "price": price, "result": result]
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let json = String(data: data, encoding: .utf8) else { return }
        onChange?(json)
    }
}
