import UIKit

// The phone's own taps, by the names the game uses for them.
final class Haptics {
    private let light = UIImpactFeedbackGenerator(style: .light)
    private let soft = UIImpactFeedbackGenerator(style: .soft)
    private let rigid = UIImpactFeedbackGenerator(style: .rigid)
    private let selection = UISelectionFeedbackGenerator()
    private let notice = UINotificationFeedbackGenerator()

    func prepare() {
        light.prepare()
        notice.prepare()
    }

    func play(_ kind: String) {
        switch kind {
        case "wave":    soft.impactOccurred(intensity: 0.7)   // a rocket set off by another
        case "blocked": rigid.impactOccurred()                // a tap on a rocket that cannot go
        case "jam":     notice.notificationOccurred(.error)
        case "win":     notice.notificationOccurred(.success)
        case "switch":  selection.selectionChanged()
        default:        light.impactOccurred()                // a launch
        }
        light.prepare()
    }
}
