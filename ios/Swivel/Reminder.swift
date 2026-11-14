import UserNotifications
import UIKit

// The daily reminder: one notice a day, made on this phone, and only if the player asks for it.
// Nothing is sent anywhere and no server is involved.
//
// The page sends a plan (its "remind" message): two weeks of days with the name of each day's board,
// the hour, whether today's board is already done, and the streak. Every plan replaces the last one,
// and the page sends a new one each time the game is opened. So a player who stops opening the game
// stops being reminded after two weeks, by construction.
//
// The answer goes back to the page as 'on', 'off' or 'denied' (notifications are off for Swivel in
// the phone's Settings).
//
// apply and recheck are called on the main queue and answer on it. The phone answers its own
// questions on another queue; each answer is brought back to the main queue before anything here is
// touched, so the two properties below are only ever read and written there.
final class Reminder: NSObject, UNUserNotificationCenterDelegate {
    private let center = UNUserNotificationCenter.current()
    private let defaults = UserDefaults.standard
    private var saidDenied = false
    private var waiting: [String: Any]? // a plan the phone's Settings would not allow, kept in case they are changed
    var onOpen: (() -> Void)?           // the player tapped a reminder

    // what was last chosen here: handed to the page as it starts, without waiting on the phone
    var remembered: String { defaults.string(forKey: "reminder") ?? "unset" }

    func start() {
        center.delegate = self
    }

    func apply(_ plan: [String: Any], answer: @escaping (String) -> Void) {
        guard plan["on"] as? Bool == true else {
            waiting = nil
            center.removeAllPendingNotificationRequests()
            defaults.set("off", forKey: "reminder")
            answer("off")
            return
        }
        allowed { [weak self] status in
            guard let self = self else { return }
            switch status {
            case .notDetermined:
                // the phone asks its own question, once; the game asked first, in its own words
                self.center.requestAuthorization(options: [.alert]) { granted, _ in
                    DispatchQueue.main.async {
                        if granted {
                            self.turnOn(plan)
                            answer("on")
                        } else {
                            self.saidDenied = true
                            self.waiting = plan
                            answer("denied")
                        }
                    }
                }
            case .denied:
                // Told once already this visit and asked again: the player wants it, and only the
                // phone's Settings can allow it, so that is where they are taken.
                if self.saidDenied {
                    DispatchQueue.main.async {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                self.saidDenied = true
                self.waiting = plan
                answer("denied")
            default: // allowed
                self.turnOn(plan)
                answer("on")
            }
        }
    }

    // Back from the phone's Settings: if the player has allowed notifications there, the plan that
    // was waiting is carried out and the page is told.
    func recheck(answer: @escaping (String) -> Void) {
        guard waiting != nil else { return }
        allowed { [weak self] status in
            guard let self = self, let plan = self.waiting, status != .notDetermined, status != .denied else { return }
            self.saidDenied = false
            self.turnOn(plan)
            answer("on")
        }
    }

    // What the phone's Settings say about notices from Swivel, brought back to the main queue.
    private func allowed(_ then: @escaping (UNAuthorizationStatus) -> Void) {
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            DispatchQueue.main.async { then(status) }
        }
    }

    private func turnOn(_ plan: [String: Any]) {
        waiting = nil
        schedule(plan)
        defaults.set("on", forKey: "reminder")
    }

    private func schedule(_ plan: [String: Any]) {
        center.removeAllPendingNotificationRequests()
        guard let days = plan["days"] as? [[String: Any]] else { return }
        let hour = min(23, max(0, plan["hour"] as? Int ?? 9))
        let done = plan["done"] as? String ?? ""
        let streak = plan["streak"] as? Int ?? 0
        let calendar = Calendar.current
        let stamp = DateFormatter()
        stamp.calendar = Calendar(identifier: .gregorian)
        stamp.locale = Locale(identifier: "en_US_POSIX")
        stamp.dateFormat = "yyyy-MM-dd"
        let now = Date()
        let today = stamp.string(from: now)
        let tomorrow = stamp.string(from: calendar.date(byAdding: .day, value: 1, to: now) ?? now)
        // the one day whose board would carry the streak on: tomorrow if today is done, otherwise today
        let streakDay = done == today ? tomorrow : today

        for day in days.prefix(21) {
            guard let date = day["date"] as? String, date != done, let name = day["name"] as? String else { continue }
            let parts = date.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { continue }
            var when = DateComponents()
            when.year = parts[0]; when.month = parts[1]; when.day = parts[2]
            when.hour = hour; when.minute = 0
            guard let fire = calendar.date(from: when), fire > now.addingTimeInterval(60) else { continue }

            let content = UNMutableNotificationContent()
            content.title = "Swivel"
            content.body = streak >= 2 && date == streakDay
                ? "Day \(streak + 1) of your streak is waiting: \(name)."
                : "Today's board is ready: \(name)."
            content.threadIdentifier = "daily"
            let trigger = UNCalendarNotificationTrigger(dateMatching: when, repeats: false)
            center.add(UNNotificationRequest(identifier: "daily-" + date, content: content, trigger: trigger))
        }
    }

    // A reminder that comes due while the game is open is not shown: the player is already here.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }

    // Tapped: the game opens on today's board.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.notification.request.identifier.hasPrefix("daily-") {
            DispatchQueue.main.async { [weak self] in self?.onOpen?() }
        }
        completionHandler()
    }
}
