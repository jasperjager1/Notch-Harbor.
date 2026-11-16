import Foundation

func notchContains(_ rect: CGRect, _ point: CGPoint) -> Bool {
    // The pointer can rest exactly on the screen's top edge.
    point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
}

enum HarborPresentation: Equatable {
    case hidden, peek, song, expanded
    var isVisible: Bool { self != .hidden }
}

// Pointer movement may reveal a small lip, but only an explicit action opens the full panel.
struct NotchPolicy {
    private(set) var expanded = false
    private var peeking = false
    private var enteredAt: TimeInterval?
    private var exitedAt: TimeInterval?
    private var bannerDeadline: TimeInterval?
    private var announcedTrack = ""

    mutating func pointer(inside: Bool, interacting: Bool, now: TimeInterval) {
        if let deadline = bannerDeadline, now >= deadline { bannerDeadline = nil }
        if interacting { enteredAt = nil; exitedAt = nil; return }
        if inside {
            exitedAt = nil
            if enteredAt == nil { enteredAt = now }
            if now - enteredAt! >= 0.08 { peeking = true }
        } else {
            enteredAt = nil
            if exitedAt == nil { exitedAt = now }
            if now - exitedAt! >= 0.18 { peeking = false }
            if now - exitedAt! >= 0.35 { expanded = false }
        }
    }
    mutating func setExpanded(_ value: Bool) {
        expanded = value
        enteredAt = nil
        exitedAt = nil
        bannerDeadline = nil
    }
    mutating func dismiss() {
        expanded = false
        peeking = false
        enteredAt = nil
        bannerDeadline = nil
    }
    mutating func trackChanged(key: String, playing: Bool, now: TimeInterval) {
        guard playing, !key.isEmpty, key != announcedTrack else { return }
        announcedTrack = key
        if !expanded { bannerDeadline = now + 2.5 }
    }
    func presentation(at now: TimeInterval) -> HarborPresentation {
        if expanded { return .expanded }
        if let deadline = bannerDeadline, now < deadline { return .song }
        return peeking ? .peek : .hidden
    }
}
