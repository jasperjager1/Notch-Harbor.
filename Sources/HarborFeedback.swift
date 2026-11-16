import AppKit

enum HarborFeedback {
    private static let key = "harborHapticsEnabled"
    private static var lastPulse: TimeInterval = 0
    static var enabled: Bool {
        get { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: key) }
    }
    static func play(_ pattern: NSHapticFeedbackManager.FeedbackPattern = .generic) {
        guard enabled, NSApp?.isRunning == true else { return }
        lastPulse = ProcessInfo.processInfo.systemUptime
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
    }

    static func confirm() {
        guard enabled, NSApp?.isRunning == true else { return }
        // An immediate drop or button pulse can serve as the first tap.
        if ProcessInfo.processInfo.systemUptime - lastPulse >= 0.09 { play() }
        let precedingPulse = lastPulse
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.09) {
            guard lastPulse == precedingPulse else { return }
            play()
        }
    }
}
