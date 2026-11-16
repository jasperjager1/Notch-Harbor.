import AppKit
import Combine
import ImageIO

// Desktop players expose their own metadata; no private system Now Playing APIs are used.
enum MusicApp: String, CaseIterable, Identifiable {
    case music = "Apple Music", spotify = "Spotify"
    var id: String { rawValue }
    var bundleID: String { self == .music ? "com.apple.Music" : "com.spotify.client" }
    var trackIdentity: String { self == .music ? "persistent ID" : "id" }
}

struct ArtworkImage {
    static func decode(_ data: Data) -> NSImage? {
        guard !data.isEmpty, data.count <= 8 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 256,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        // Decode off the main thread and retain only a small, correctly proportioned image.
        return NSImage(cgImage: thumbnail, size: NSSize(width: thumbnail.width, height: thumbnail.height))
    }
    static func spotifyURL(_ string: String) -> URL? {
        guard let url = URL(string: string), url.scheme == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil,
              ["scdn.co", "spotifycdn.com", "spotify.com"].contains(where: { host == $0 || host.hasSuffix("." + $0) }) else { return nil }
        return url
    }
}

final class Player: ObservableObject {
    @Published var selected: MusicApp = .music
    @Published var connected = false
    @Published var title = "Your music, within reach"
    @Published var artist = "Choose a player to connect"
    @Published var album = ""
    @Published var duration: Double = 0
    @Published var playbackPosition: Double = 0
    private var positionSampledAt = Date()
    private var wantsConnection = false
    private var permissionDenied = false
    private var retryAfter = Date.distantPast
    static let savedPlayerKey = "preferredConnectedPlayer"
    private let preferences: UserDefaults
    @Published var playing = false
    @Published var busy = false
    @Published var commandPending = false
    @Published var problem: String?
    @Published var artwork: NSImage?
    @Published var artworkVersion = UUID()
    @Published private(set) var trackKey = ""
    private let queue = DispatchQueue(label: "local.notchharbor.player", qos: .userInitiated)
    private var timer: Timer?
    private var waitingCommands: [String] = []
    private var generation = 0
    private var artworkTask: URLSessionDataTask?
    private var lastArtworkAttempt = Date.distantPast
    private let artworkCache = NSCache<NSString, NSImage>()
    private lazy var artworkSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 10
        return URLSession(configuration: config)
    }()
    init(preferences: UserDefaults = .standard, startPolling: Bool = true) {
        self.preferences = preferences
        if let saved = preferences.string(forKey: Self.savedPlayerKey), let app = MusicApp(rawValue: saved) {
            selected = app
            wantsConnection = true
            artist = "Waiting for \(app.rawValue)…"
        }
        artworkCache.countLimit = 24
        artworkCache.totalCostLimit = 8 * 1024 * 1024
        guard startPolling else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            guard let self, !self.busy else { return }
            if self.connected { self.run(nil) }
            else if self.shouldReconnect(playerIsRunning: !NSRunningApplication.runningApplications(withBundleIdentifier: self.selected.bundleID).isEmpty) {
                self.run(nil)
            }
        }
        timer?.fire()
    }
    var remembersConnection: Bool { wantsConnection }
    func shouldReconnect(playerIsRunning: Bool, at date: Date = Date()) -> Bool {
        wantsConnection && !permissionDenied && playerIsRunning && date >= retryAfter
    }
    func disconnect() {
        wantsConnection = false; permissionDenied = false
        preferences.removeObject(forKey: Self.savedPlayerKey)
        generation += 1
        artworkTask?.cancel()
        waitingCommands.removeAll()
        connected = false; title = "Your music, within reach"; artist = "Choose a player to connect"
        album = ""; trackKey = ""; playing = false; duration = 0; playbackPosition = 0
        problem = nil; artwork = nil; artworkVersion = UUID()
    }
    func connect() {
        HarborFeedback.play()
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: selected.bundleID) != nil else {
            problem = "Install the \(selected.rawValue) desktop app first."; return
        }
        wantsConnection = true; permissionDenied = false
        preferences.set(selected.rawValue, forKey: Self.savedPlayerKey)
        run(nil, connecting: true)
    }
    func currentPosition(at date: Date) -> Double {
        Self.projectedPosition(sample: playbackPosition, sampledAt: positionSampledAt, now: date, playing: playing, duration: duration)
    }
    static func projectedPosition(sample: Double, sampledAt: Date, now: Date, playing: Bool, duration: Double) -> Double {
        guard sample.isFinite, duration.isFinite, duration > 0 else { return 0 }
        return min(duration, max(0, sample + (playing ? max(0, now.timeIntervalSince(sampledAt)) : 0)))
    }
    static func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite else { return "0:00" }
        let total = Int(min(359999, max(0, seconds)))
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
    func command(_ command: String) {
        guard connected, ["playpause", "next track", "previous track"].contains(command) else { return }
        if busy {
            guard waitingCommands.count < 4 else { return }
            waitingCommands.append(command)
        } else {
            run(command)
        }
        if command == "playpause" { HarborFeedback.play() }
        else { HarborFeedback.confirm() }
    }
    static func metadataScript(app: MusicApp, command: String?, connecting: Bool) -> String {
        let action = command.map { "\($0)\n" } ?? ""
        return """
        with timeout of 8 seconds
            tell application id "\(app.bundleID)"
                \(connecting ? "launch" : "if not running then return {\"Player closed\", \"Open \(app.rawValue) to resume automatically\", \"stopped\", \"\", \"\"}")
                \(action)
                set playbackState to player state as string
                if playbackState is "stopped" then return {"Nothing playing", "Start a track in \(app.rawValue)", playbackState, "", ""}
                set trackName to name of current track as string
                set trackArtist to artist of current track as string
                set trackAlbum to ""
                try
                    set trackAlbum to album of current track as string
                end try
                set trackIdentity to trackName & trackArtist & trackAlbum
                try
                    set trackIdentity to \(app.trackIdentity) of current track as string
                end try
                set trackPosition to 0
                set trackDuration to 0
                try
                    set trackPosition to player position as real
                    set trackDuration to (duration of current track as real) / \(app == .spotify ? "1000" : "1")
                end try
                return {trackName, trackArtist, playbackState, trackIdentity, trackAlbum, trackPosition, trackDuration}
            end tell
        end timeout
        """
    }
    static func artworkScript(app: MusicApp) -> String {
        """
        with timeout of 5 seconds
            tell application id "\(app.bundleID)"
                if not running then return {}
                set trackName to name of current track as string
                set trackArtist to artist of current track as string
                set trackAlbum to ""
                try
                    set trackAlbum to album of current track as string
                end try
                set trackIdentity to trackName & trackArtist & trackAlbum
                try
                    set trackIdentity to \(app.trackIdentity) of current track as string
                end try
                try
                    return {trackIdentity, \(app == .music ? "raw data of artwork 1 of current track" : "artwork url of current track")}
                on error
                    return {trackIdentity, ""}
                end try
            end tell
        end timeout
        """
    }
    private func run(_ command: String?, connecting: Bool = false) {
        guard !busy else { return }
        busy = true; commandPending = command != nil
        let app = selected
        let version = generation
        let script = Self.metadataScript(app: app, command: command, connecting: connecting)
        queue.async {
            var error: NSDictionary?
            let value = NSAppleScript(source: script)?.executeAndReturnError(&error)
            let errorText: String? = error.map { e in
                let code = e[NSAppleScript.errorNumber] as? Int ?? 0
                if code == -1743 { return "Allow NotchNook in System Settings → Privacy & Security → Automation, then reconnect." }
                return (e[NSAppleScript.errorMessage] as? String ?? "Player connection failed") + " (\(code))"
            }
            let denied = (error?[NSAppleScript.errorNumber] as? Int) == -1743
            let name = value?.atIndex(1)?.stringValue
            let artist = value?.atIndex(2)?.stringValue
            let state = value?.atIndex(3)?.stringValue
            let identity = value?.atIndex(4)?.stringValue ?? ""
            let album = value?.atIndex(5)?.stringValue ?? ""
            let position = value?.atIndex(6)?.doubleValue ?? 0
            let duration = value?.atIndex(7)?.doubleValue ?? 0
            DispatchQueue.main.async {
                self.busy = false; self.commandPending = false
                guard self.selected == app, self.generation == version else { return }
                if let errorText {
                    self.problem = errorText; self.connected = false; self.permissionDenied = denied
                    self.retryAfter = Date().addingTimeInterval(10)
                    self.waitingCommands.removeAll(); return
                }
                guard let name, let artist, let state else {
                    self.problem = "No response from player. Open it and reconnect."; self.connected = false; return
                }
                self.positionSampledAt = Date()
                self.playbackPosition = position.isFinite ? max(0, position) : 0
                self.duration = duration.isFinite ? max(0, duration) : 0
                self.title = name; self.artist = artist; self.album = album; self.playing = state == "playing"
                self.connected = name != "Player closed"; self.problem = nil
                let key = identity.isEmpty ? "" : app.bundleID + ":" + identity
                if self.trackKey != key {
                    self.artworkTask?.cancel()
                    self.trackKey = key; self.artwork = nil; self.artworkVersion = UUID()
                    self.lastArtworkAttempt = .distantPast
                }
                if !key.isEmpty, self.artwork == nil, Date().timeIntervalSince(self.lastArtworkAttempt) > 20 {
                    self.fetchArtwork(app: app, identity: identity, key: key, generation: version)
                }
                if self.connected, !self.waitingCommands.isEmpty {
                    let next = self.waitingCommands.removeFirst()
                    self.run(next)
                }
            }
        }
    }
    private func fetchArtwork(app: MusicApp, identity: String, key: String, generation: Int) {
        lastArtworkAttempt = Date()
        if let cached = artworkCache.object(forKey: key as NSString) { applyArtwork(cached, key: key, generation: generation); return }
        queue.async {
            var error: NSDictionary?
            let value = NSAppleScript(source: Self.artworkScript(app: app))?.executeAndReturnError(&error)
            guard error == nil, value?.atIndex(1)?.stringValue == identity, let descriptor = value?.atIndex(2) else { return }
            if app == .music {
                if let image = ArtworkImage.decode(descriptor.data) {
                    DispatchQueue.main.async { self.applyArtwork(image, key: key, generation: generation) }
                }
            } else if let source = descriptor.stringValue, let url = ArtworkImage.spotifyURL(source) {
                DispatchQueue.main.async {
                    guard self.trackKey == key, self.generation == generation else { return }
                    self.artworkTask = self.artworkSession.dataTask(with: url) { data, response, error in
                        guard error == nil, let response = response as? HTTPURLResponse,
                              response.statusCode == 200, let data, let image = ArtworkImage.decode(data) else { return }
                        DispatchQueue.main.async { self.applyArtwork(image, key: key, generation: generation) }
                    }
                    self.artworkTask?.resume()
                }
            }
        }
    }
    private func applyArtwork(_ image: NSImage, key: String, generation: Int) {
        guard self.generation == generation, trackKey == key else { return }
        artworkCache.setObject(image, forKey: key as NSString, cost: 256 * 256 * 4)
        artwork = image; artworkVersion = UUID()
    }
}
