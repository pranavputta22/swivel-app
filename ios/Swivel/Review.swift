import StoreKit
import UIKit

// Asking for a rating, and the Rate button in the game's Settings.
//
// The game tells the app of its good moments (the page's "moment" message): a world finished, the
// ending, the seventh day of a streak. The app picks at most one of them for each version of the
// app, and only for a player who has come back on a second day (or reached the ending). The phone
// then decides whether its rating question is actually shown: never more than three times a year,
// never in TestFlight, and not at all if the player has turned such questions off.
final class Review {
    private let defaults = UserDefaults.standard

    // The app's number on the App Store, set in Info.plist once the app has a page there (SwivelAppStoreID).
    private static var storeID: String {
        (Bundle.main.object(forInfoDictionaryKey: "SwivelAppStoreID") as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // whether the Rate button has anywhere to go
    var canRate: Bool {
        let id = Review.storeID
        return !id.isEmpty && id.allSatisfy { $0.isASCII && $0.isNumber }
    }

    // called whenever the app comes to the front: the days it has been opened on are counted
    func noteDay() {
        let stamp = DateFormatter()
        stamp.calendar = Calendar(identifier: .gregorian)
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd"
        let today = stamp.string(from: Date())
        var days = defaults.stringArray(forKey: "review.days") ?? []
        guard days.last != today else { return }
        days.append(today)
        if days.count > 30 { days.removeFirst(days.count - 30) }
        defaults.set(days, forKey: "review.days")
    }

    func moment(_ kind: String, in scene: UIWindowScene?) {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let days = (defaults.stringArray(forKey: "review.days") ?? []).count
        guard kind == "ending" || days >= 2 else { return }
        guard defaults.string(forKey: "review.version") != version else { return }
        if let last = defaults.object(forKey: "review.asked") as? Date, Date().timeIntervalSince(last) < 60 * 86_400 { return }
        defaults.set(version, forKey: "review.version")
        defaults.set(Date(), forKey: "review.asked")
        // a moment after the fireworks, so the question does not land on top of them
        // (on the main actor: the newer of the two calls insists on it)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            guard let scene = scene, scene.activationState == .foregroundActive else { return }
            if #available(iOS 16.0, *) {
                AppStore.requestReview(in: scene)
            } else {
                SKStoreReviewController.requestReview(in: scene)
            }
        }
    }

    // The Rate button: straight to the place on the App Store where a review is written.
    @MainActor func rate() {
        guard canRate, let url = URL(string: "https://apps.apple.com/app/id\(Review.storeID)?action=write-review") else { return }
        UIApplication.shared.open(url)
    }
}
