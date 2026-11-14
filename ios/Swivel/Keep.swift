import Foundation

// The app's second copy of what the page stores.
//  - "store": the page's own storage, whole, kept on this device. It is handed back when the page
//    starts, and the page uses it only if its own storage has come back empty.
//  - "progress": the player's record, also put in their iCloud key-value store, so it reaches their
//    other devices and a new phone. The page merges it with its own: the better result for each level.
final class Keep: NSObject {
    private let defaults = UserDefaults.standard
    private let cloud = NSUbiquitousKeyValueStore.default
    private let limit = 400_000 // far above any real record; a guard, not a budget
    var onCloudChange: ((String) -> Void)?

    func start() {
        NotificationCenter.default.addObserver(self, selector: #selector(cloudChanged(_:)),
                                               name: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
                                               object: cloud)
        cloud.synchronize()
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func save(store: [String: String]) {
        guard store.values.reduce(0, { $0 + $1.utf8.count }) < limit else { return }
        defaults.set(store, forKey: "store")
    }

    func save(progress: String) {
        guard progress.utf8.count < limit else { return }
        defaults.set(progress, forKey: "progress")
        if cloud.string(forKey: "progress") != progress {
            cloud.set(progress, forKey: "progress")
            cloud.synchronize()
        }
    }

    // window.__swivelShell = { store: {...}, progress: "...", otherAudio: true/false, ... }, as a script for
    // the start of the page. otherAudio says the player's own music is playing, so the game keeps its own quiet.
    // extra: whatever else the page should know as it starts (the reminder's state, whether Rate has
    // anywhere to go, a link the app was opened with).
    func handover(otherAudio: Bool, extra: [String: Any] = [:]) -> String {
        var given: [String: Any] = extra
        given["otherAudio"] = otherAudio
        if let store = defaults.dictionary(forKey: "store") as? [String: String] { given["store"] = store }
        if let progress = cloud.string(forKey: "progress") ?? defaults.string(forKey: "progress") { given["progress"] = progress }
        guard let data = try? JSONSerialization.data(withJSONObject: given),
              var json = String(data: data, encoding: .utf8) else { return "window.__swivelShell = {};" }
        // the two characters JSON allows and a script does not
        json = json.replacingOccurrences(of: "\u{2028}", with: "\\u2028")
                   .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        return "window.__swivelShell = \(json);"
    }

    @objc private func cloudChanged(_ note: Notification) {
        guard let progress = cloud.string(forKey: "progress") else { return }
        DispatchQueue.main.async { [weak self] in self?.onCloudChange?(progress) }
    }
}
