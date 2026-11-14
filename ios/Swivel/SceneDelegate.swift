import UIKit

// The game's window, and the links the app is opened with.
//
// iOS hands an app its place on the screen as a "scene". Swivel has one. The game itself belongs to
// the app (AppDelegate.game), not to the scene: if iOS takes the scene away while the app is in the
// background and gives one back later, the same game is shown again, where the player left it.
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    private var game: GameViewController? {
        (UIApplication.shared.delegate as? AppDelegate)?.game
    }

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene, session.role == .windowApplication, let game = game else { return }
        // A link the app was started with is handed to the game before its page starts.
        if let url = connectionOptions.urlContexts.first?.url {
            follow(url)
        } else if let activity = connectionOptions.userActivities.first(where: { $0.activityType == NSUserActivityTypeBrowsingWeb }) {
            follow(activity.webpageURL)
        }
        // (A tap on a reminder that starts the app is not read from these options: the reminder's own
        // delegate is told of it, in Reminder.swift, and telling the game twice would restart the board.)

        let window = UIWindow(windowScene: scene)
        window.backgroundColor = Sky.color
        window.rootViewController = game
        window.makeKeyAndVisible()
        self.window = window
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        // the game is let go of, so that the next window can take it
        window?.rootViewController = nil
        window = nil
    }

    // swivel://daily, swivel://d=2026-12-31, swivel://l=SW-...: the game's own links, opened while the app is running
    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        follow(URLContexts.first?.url)
    }

    // The same boards as links to the game's page on the web. This only ever runs once the app is
    // tied to that address (an associated domain), which it is not yet.
    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        guard userActivity.activityType == NSUserActivityTypeBrowsingWeb else { return }
        follow(userActivity.webpageURL)
    }

    private func follow(_ url: URL?) {
        guard let url = url, let scheme = url.scheme?.lowercased(),
              scheme == "swivel" || scheme == "https" else { return }
        game?.open(link: url.absoluteString)
    }
}
