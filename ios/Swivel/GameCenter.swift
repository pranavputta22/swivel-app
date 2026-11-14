import GameKit
import UIKit

// Game Center: Apple's own record of a player's achievements and scores, kept on their account.
// The game works out how far along each achievement is and what the three scores are, and says so
// whenever they change (the page's "game" message). This file passes that on, and nothing else.
//
//  - Nothing is shown at launch. If the player is not signed in to Game Center, Apple's sign-in
//    sheet is kept and shown only when they ask for Game Center in the game's Settings.
//  - An achievement is only ever reported going up, and a score only when it beats the last one sent
//    from this phone, so reopening the game sends nothing twice.
//  - The names here are the page's with "swivel." in front, exactly as set up in App Store Connect
//    (store/gamecenter.md has the whole list).
final class GameCenter {
    private let defaults = UserDefaults.standard
    private var signIn: UIViewController?
    private var latest: (feats: [String: Int], scores: [String: Int])?
    private weak var host: UIViewController?
    private static let prefix = "swivel."

    @MainActor func start(host: UIViewController) {
        self.host = host
        GKAccessPoint.shared.isActive = false // the game has its own button for this, in Settings
        GKLocalPlayer.local.authenticateHandler = { [weak self] sheet, _ in
            guard let self = self else { return }
            if let sheet = sheet {
                self.signIn = sheet // not signed in: kept until the player asks
                return
            }
            self.signIn = nil
            if GKLocalPlayer.local.isAuthenticated { self.flush() }
        }
    }

    // feats: achievement name -> 0...100. scores: leaderboard name -> value.
    func report(feats: [String: Int], scores: [String: Int]) {
        latest = (feats, scores)
        flush()
    }

    private func flush() {
        guard GKLocalPlayer.local.isAuthenticated, let latest = latest else { return }
        // what has been sent is remembered for each Game Center player, so a second player on the same phone starts clean
        let player = GKLocalPlayer.local.gamePlayerID
        let featKey = "gc.feats." + player, scoreKey = "gc.scores." + player
        let sentFeats = defaults.dictionary(forKey: featKey) as? [String: Int] ?? [:]
        let sentScores = defaults.dictionary(forKey: scoreKey) as? [String: Int] ?? [:]

        var due: [GKAchievement] = []
        var dueValues: [String: Int] = [:]
        for (name, value) in latest.feats {
            let percent = min(100, max(0, value))
            guard percent > (sentFeats[name] ?? 0) else { continue }
            let achievement = GKAchievement(identifier: GameCenter.prefix + name)
            achievement.percentComplete = Double(percent)
            achievement.showsCompletionBanner = true
            due.append(achievement)
            dueValues[name] = percent
        }
        if !due.isEmpty {
            let reported = dueValues // (a copy that cannot change, for the answer that comes later)
            GKAchievement.report(due) { [weak self] error in
                guard error == nil, let self = self else { return }
                var sent = self.defaults.dictionary(forKey: featKey) as? [String: Int] ?? [:]
                for (name, percent) in reported { sent[name] = max(sent[name] ?? 0, percent) }
                self.defaults.set(sent, forKey: featKey)
            }
        }

        for (name, value) in latest.scores where value > (sentScores[name] ?? 0) {
            GKLeaderboard.submitScore(value, context: 0, player: GKLocalPlayer.local,
                                      leaderboardIDs: [GameCenter.prefix + name]) { [weak self] error in
                guard error == nil, let self = self else { return }
                var sent = self.defaults.dictionary(forKey: scoreKey) as? [String: Int] ?? [:]
                sent[name] = max(sent[name] ?? 0, value)
                self.defaults.set(sent, forKey: scoreKey)
            }
        }
    }

    // The player asked for Game Center. Signed in: Apple's own screen, over the game. Not signed in:
    // Apple's sign-in sheet if there is one, and otherwise a line saying where to sign in.
    @MainActor func open() {
        guard let host = host else { return }
        if GKLocalPlayer.local.isAuthenticated {
            // (the access point's own screen: the older view controller is deprecated from iOS 26.
            // Its handler is not relied on: on some versions it is never called.)
            GKAccessPoint.shared.trigger(state: .dashboard) { }
        } else if let sheet = signIn, sheet.presentingViewController == nil, host.presentedViewController == nil {
            host.present(sheet, animated: true)
        } else if host.presentedViewController == nil {
            let alert = UIAlertController(title: "Game Center",
                                          message: "Sign in to Game Center in the Settings app to keep your achievements and scores.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            host.present(alert, animated: true)
        }
    }
}
