import UIKit
import AVFoundation

// Swivel for iPhone and iPad.
// The game itself is the page in Web/index.html, carried inside the app. This shell shows it,
// gives it the phone's haptics, keeps a second copy of what it stores, and does the few things only
// an app can: Game Center, the share sheet, a daily reminder, the rating question, and opening links.
//
// The app starts here. Its window is made in SceneDelegate.swift: an app built with the iOS 27 tools
// or later has to take its place on the screen as a "scene", or it does not start at all.

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    // The one game. It is made as the app starts, before there is a window, so that a tap on a
    // reminder that starts the app is heard. It is kept for as long as the app runs.
    private(set) var game: GameViewController?

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // The game's sounds play over the player's own music (mixed, never stopping it), as Apple advises for games.
        // Like other games they follow the silent switch: on silent the speaker stays quiet, while headphones and
        // AirPods still play. Without a background audio mode, nothing plays once the app is in the background.
        try? AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default, options: [])
        try? AVAudioSession.sharedInstance().setActive(true)
        game = GameViewController()
        return true
    }

    // The game has one window (Info.plist says the same). Anything else iOS offers, such as a second
    // screen, is given nothing of its own, so it goes on mirroring the game.
    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        guard connectingSceneSession.role == .windowApplication else {
            return UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        }
        let configuration = UISceneConfiguration(name: "Default Configuration", sessionRole: .windowApplication)
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

enum Sky {
    // the top of the game's night sky, so nothing flashes white before the page has drawn
    static let color = UIColor(red: 0x1C / 255.0, green: 0x22 / 255.0, blue: 0x54 / 255.0, alpha: 1)
}
