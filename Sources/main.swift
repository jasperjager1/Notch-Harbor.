import AppKit
import SwiftUI
import Combine
import ImageIO

final class HarborPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let state = HarborState()
    let shelf = ShelfStore()
    let player = Player()
    var panel: HarborPanel!
    var statusItem: NSStatusItem!
    var escapeMonitor: Any?
    var screenObserver: NSObjectProtocol?
    var outsideClickMonitor: Any?
    var hoverTimer: Timer?
    var policy = NotchPolicy()
    var cameraFrame: NSRect?
    var idleDragChangeCount = NSPasteboard(name: .drag).changeCount
    var playerObserver: AnyCancellable?
    var menuTrackingDepth = 0
    var menuObservers: [NSObjectProtocol] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        panel = HarborPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.hidesOnDeactivate = false
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isMovable = false
        panel.isReleasedWhenClosed = false
        let view = HarborView(state: state, shelf: shelf, player: player)
        panel.contentView = DropHost(rootView: view)
        state.toggle = { [weak self] in self?.toggle() }
        state.expand = { [weak self] in self?.openFromClick() }
        state.expandForDrop = { [weak self] in
            guard let self, !self.state.expanded else { return }
            self.setExpanded(true)
        }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "tray", accessibilityDescription: "NotchNook")
        let menu = NSMenu()
        menu.addItem(withTitle: "Show / Collapse NotchNook", action: #selector(toggle), keyEquivalent: "")
        menu.addItem(withTitle: "Add Files…", action: #selector(addFiles), keyEquivalent: "")
        menu.addItem(withTitle: "Paste Image or File", action: #selector(pasteToShelf), keyEquivalent: "v")
        let haptics = menu.addItem(withTitle: "Trackpad Feedback", action: #selector(toggleHaptics(_:)), keyEquivalent: "")
        haptics.state = HarborFeedback.enabled ? .on : .off
        menu.addItem(withTitle: "Open Shelf Folder", action: #selector(openShelf), keyEquivalent: "")
        menu.addItem(withTitle: "Disconnect Music Player", action: #selector(disconnectPlayer), keyEquivalent: "")
        menu.addItem(withTitle: "About NotchNook", action: #selector(about), keyEquivalent: "")
        menu.addItem(withTitle: "Read Instructions", action: #selector(help), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit NotchNook", action: #selector(quit), keyEquivalent: "q")
        menu.items.forEach { $0.target = self }
        statusItem.menu = menu
        menuObservers.append(NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self else { return }
            self.menuTrackingDepth += 1
            if notification.object as? NSMenu === self.statusItem.menu || (self.state.expanded && NSApp.modalWindow == nil) {
                HarborFeedback.play()
            }
        })
        menuObservers.append(NotificationCenter.default.addObserver(forName: NSMenu.didEndTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.menuTrackingDepth = max(0, self.menuTrackingDepth - 1)
        })
        // Mouse monitoring only: no key logging, Accessibility, or Input Monitoring permission.
        // On the camera housing itself, macOS may route the click to the menu bar.
        // Never use this fallback over visible screen content, where another app can receive the click.
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return }
            if event.type == .leftMouseDown, self.canOpenCompact,
               let camera = self.cameraFrame, notchContains(camera, NSEvent.mouseLocation) {
                self.openFromClick()
            } else {
                self.dismissIfOutside()
            }
        }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            if let self, event.type == .leftMouseDown, event.window === self.panel, self.canOpenCompact,
               self.pointerIsInside(self.panel.convertPoint(toScreen: event.locationInWindow)) {
                self.openFromClick()
                return nil
            }
            if event.type == .keyDown, let self, event.window === self.panel, NSApp.modalWindow == nil {
                if event.keyCode == 53 && self.state.expanded && !self.state.sharePickerOpen {
                    HarborFeedback.play()
                    self.setExpanded(false)
                    return nil
                }
                if self.state.expanded,
                   event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command,
                   event.charactersIgnoringModifiers?.lowercased() == "v" {
                    if !event.isARepeat { self.shelf.paste() }
                    return nil
                }
            } else if event.type != .keyDown { self?.dismissIfOutside() }
            return event
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in self?.position() }
        playerObserver = player.$trackKey.combineLatest(player.$playing)
            .receive(on: RunLoop.main)
            .sink { [weak self] key, playing in
                guard let self else { return }
                self.policy.trackChanged(key: key, playing: playing, now: ProcessInfo.processInfo.systemUptime)
                self.applyPresentation()
            }
        position()
        panel.orderFrontRegardless()
        let timer = Timer(timeInterval: 0.06, repeats: true) { [weak self] _ in self?.checkHover() }
        RunLoop.main.add(timer, forMode: .common)
        hoverTimer = timer
        if CommandLine.arguments.contains("--expanded") { setExpanded(true) }
    }
    func targetScreen() -> NSScreen? {
        NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main ?? NSScreen.screens.first
    }
    func position() {
        guard let screen = targetScreen() else { return }
        let inset = screen.safeAreaInsets.top
        if inset > 0, let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea,
           right.minX > left.maxX {
            cameraFrame = NSRect(x: left.maxX, y: screen.frame.maxY - inset,
                                 width: right.minX - left.maxX, height: inset)
        } else {
            cameraFrame = nil
        }
        state.topInset = inset > 0 ? inset : NSStatusBar.system.thickness + 4
        state.expandedWidth = min(640, screen.frame.width - 40)
        state.notchWidth = cameraFrame?.width ?? 198
        state.collapsedWidth = max(210, state.notchWidth + 24)
        // Keep the hosting window stable. Only the SwiftUI island animates, so its content
        // never reflows or clips against a shrinking native window during a transition.
        let width = state.expandedWidth
        let height = state.topInset + state.contentHeight
        panel.ignoresMouseEvents = !state.presentation.isVisible
        panel.hasShadow = false
        let center = cameraFrame?.midX ?? screen.frame.midX
        panel.setFrame(NSRect(x: center - width / 2, y: screen.frame.maxY - height, width: width, height: height), display: true)
    }
    var canOpenCompact: Bool {
        (state.presentation == .peek || state.presentation == .song) && NSApp.modalWindow == nil && menuTrackingDepth == 0
    }
    func setExpanded(_ value: Bool) {
        policy.setExpanded(value)
        applyPresentation()
    }
    func applyPresentation() {
        let next = policy.presentation(at: ProcessInfo.processInfo.systemUptime)
        if state.presentation != next {
            state.presentation = next
            if next.isVisible { panel.orderFrontRegardless() }
        }
        panel.ignoresMouseEvents = !state.presentation.isVisible || !pointerIsInside(NSEvent.mouseLocation)
    }
    func pointerIsInside(_ point: NSPoint) -> Bool {
        notchContains(state.interactionRect(in: panel.frame), point)
    }
    func checkHover() {
        // A hidden, click-through window cannot receive draggingEntered. Detect the
        // live drag at the housing first, then expose the native drop destination.
        let dragBoard = NSPasteboard(name: .drag)
        let leftPressed = NSEvent.pressedMouseButtons & 1 != 0
        if !leftPressed { idleDragChangeCount = dragBoard.changeCount }
        let draggingFile = leftPressed && dragBoard.changeCount != idleDragChangeCount && ShelfTransfer.canRead(dragBoard)
        if draggingFile, !shelf.busy, !state.expanded, NSApp.modalWindow == nil,
           pointerIsInside(NSEvent.mouseLocation) {
            state.expandForDrop?()
        }
        let interacting = state.sharePickerOpen || NSApp.modalWindow != nil || menuTrackingDepth > 0 || (state.presentation.isVisible && NSEvent.pressedMouseButtons != 0) || state.targeted
        policy.pointer(inside: pointerIsInside(NSEvent.mouseLocation), interacting: interacting,
                       now: ProcessInfo.processInfo.systemUptime)
        applyPresentation()
    }
    func dismissIfOutside() {
        guard state.presentation.isVisible, !state.sharePickerOpen, NSApp.modalWindow == nil, menuTrackingDepth == 0,
              !pointerIsInside(NSEvent.mouseLocation) else { return }
        if state.expanded { HarborFeedback.play() }
        policy.dismiss()
        applyPresentation()
    }
    func openFromClick() {
        HarborFeedback.confirm()
        setExpanded(true)
        panel.makeKey()
    }
    @objc func toggle() {
        if state.expanded { HarborFeedback.play(); setExpanded(false) }
        else { openFromClick() }
    }
    @objc func addFiles() { setExpanded(true); shelf.chooseFiles() }
    @objc func pasteToShelf() { setExpanded(true); shelf.paste() }
    @objc func toggleHaptics(_ sender: NSMenuItem) {
        if HarborFeedback.enabled { HarborFeedback.play(); HarborFeedback.enabled = false }
        else { HarborFeedback.enabled = true; HarborFeedback.play() }
        sender.state = HarborFeedback.enabled ? .on : .off
    }
    @objc func disconnectPlayer() { HarborFeedback.play(); player.disconnect() }
    @objc func openShelf() { HarborFeedback.play(); NSWorkspace.shared.open(shelf.root) }
    @objc func about() {
        HarborFeedback.play()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "NotchNook",
            .credits: NSAttributedString(string: "Your local notch utility.\n\nDrop or paste files to keep them handy, and control music from the notch.")
        ])
    }
    @objc func help() {
        HarborFeedback.play()
        let url = Bundle.main.resourceURL!.appendingPathComponent("README.md")
        if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
        else {
            let alert = NSAlert()
            alert.messageText = "Welcome to NotchNook"
            alert.informativeText = "Hover for a small notch preview, then click to open the full panel. New songs show a compact artwork banner for 2.5 seconds. Move away or click elsewhere to hide. Drop files onto it to keep local copies; drag them out or use the ⋯ menu to save a copy. Connect your desktop music player to enable controls. Automation permission is requested only on connection. Use the tray menu to quit."
            alert.runModal()
        }
    }
    @objc func quit() { HarborFeedback.play(); NSApp.terminate(nil) }
}

func selfTest() throws {
    let fm = FileManager.default
    let temp = fm.temporaryDirectory.appendingPathComponent("NotchHarbor-tests-" + UUID().uuidString)
    defer { try? fm.removeItem(at: temp) }
    let input = temp.appendingPathComponent("Input")
    let root = temp.appendingPathComponent("Shelf")
    try fm.createDirectory(at: input, withIntermediateDirectories: true)
    let store = ShelfStore(root: root)
    let file = input.appendingPathComponent("hello.txt")
    try Data("Harbor test".utf8).write(to: file)
    let first = try ShelfStore.copy(file, into: root)
    let second = try ShelfStore.copy(file, into: root)
    precondition(first != second, "Duplicate names must not overwrite")
    let originalData = try Data(contentsOf: file)
    let copiedData = try Data(contentsOf: first)
    precondition(copiedData == originalData)
    let folder = input.appendingPathComponent("Folder")
    try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    try Data("nested".utf8).write(to: folder.appendingPathComponent("inside.txt"))
    let copiedFolder = try ShelfStore.copy(folder, into: root)
    precondition(fm.fileExists(atPath: copiedFolder.appendingPathComponent("inside.txt").path))
    try store.reload()
    precondition(store.items.count == 3)
    let hidden = input.appendingPathComponent(".example")
    try Data("hidden".utf8).write(to: hidden)
    _ = try ShelfStore.copy(hidden, into: root)
    try store.reload()
    precondition(store.items.contains { $0.name == ".example" }, "Hidden imports must be visible in shelf")
    precondition(ShelfStore(root: root).items.count == 4, "Shelf must survive relaunch")
    try fm.removeItem(at: first)
    precondition(fm.fileExists(atPath: file.path), "Removing shelf copy must preserve original")
    do { _ = try ShelfStore.copy(temp, into: root); fatalError("Recursive copy accepted") } catch {}
    do { _ = try ShelfStore.copy(second, into: root); fatalError("Self import accepted") } catch {}
    let exportRoot = temp.appendingPathComponent("Export")
    try fm.createDirectory(at: exportRoot, withIntermediateDirectories: true)
    let exported = try ShelfStore.copy(second, into: exportRoot)
    let exportedData = try Data(contentsOf: exported)
    precondition(exportedData == originalData)
    do { _ = try ShelfStore.copy(input.appendingPathComponent("missing"), into: root); fatalError("Missing file accepted") } catch {}
    let remaining = try fm.contentsOfDirectory(atPath: root.path)
    precondition(remaining.filter { $0.hasPrefix(".import-") }.isEmpty)
    // Files are opaque bytes to the shelf. No decoder or extension registration is required.
    for name in ["part.3mf", "mesh.stl", "custom.unregistered", "NoExtension"] {
        let source = input.appendingPathComponent(name)
        let bytes = Data([0x50, 0x4b, 0, 0xff, 0x42, 0x00, 0x13])
        try bytes.write(to: source)
        let saved = try ShelfStore.copy(source, into: root)
        let savedBytes = try Data(contentsOf: saved)
        precondition(savedBytes == bytes)
        let retrieved = try ShelfStore.copy(saved, into: exportRoot)
        let retrievedBytes = try Data(contentsOf: retrieved)
        precondition(retrievedBytes == bytes)
        let pasteboard = NSPasteboard.withUniqueName()
        defer { pasteboard.releaseGlobally() }
        precondition(pasteboard.writeObjects([source as NSURL]))
        precondition(DropHost.fileURLs(on: pasteboard) == [source])
        let provider = NSItemProvider(object: saved as NSURL)
        precondition(provider.hasItemConformingToTypeIdentifier("public.file-url"))
    }
    precondition(ArtworkImage.spotifyURL("https://i.scdn.co/image/example") != nil)
    precondition(ArtworkImage.spotifyURL("http://i.scdn.co/image/example") == nil)
    precondition(ArtworkImage.spotifyURL("https://scdn.co.evil.example/image") == nil)
    precondition(ArtworkImage.spotifyURL("file:///private/example") == nil)
    precondition(ArtworkImage.decode(Data()) == nil)
    let pixels = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 2,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                 isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let imageBytes = pixels.representation(using: .png, properties: [:])!
    let imageBoard = NSPasteboard.withUniqueName()
    defer { imageBoard.releaseGlobally() }
    precondition(imageBoard.setData(imageBytes, forType: .png))
    precondition(ShelfTransfer.canRead(imageBoard))
    precondition(ShelfTransfer.receive(imageBoard, into: store, allowPromises: false))
    let deadline = Date().addingTimeInterval(3)
    while store.busy && Date() < deadline { RunLoop.main.run(until: Date().addingTimeInterval(0.01)) }
    let firstImage = root.appendingPathComponent("Image.png")
    let savedImage = try Data(contentsOf: firstImage)
    let clipboard = NSPasteboard.withUniqueName()
    defer { clipboard.releaseGlobally() }
    precondition(ShelfClipboard.copy(firstImage, asImage: true, to: clipboard))
    precondition(clipboard.data(forType: .png) == imageBytes)
    precondition(ShelfClipboard.copy(firstImage, asImage: false, to: clipboard))
    precondition(ShelfTransfer.fileURLs(on: clipboard).first?.lastPathComponent == firstImage.lastPathComponent)
    precondition(!ShelfClipboard.copy(input.appendingPathComponent("missing.png"), asImage: true, to: clipboard))
    precondition(ShelfTransfer.fileURLs(on: clipboard).count == 1)
    print("PASS: original image bytes and native file URLs copied from the shelf")

    precondition(!store.busy && savedImage == imageBytes)
    for format in ConversionFormat.available {
        let converted = try ImageConverter.convert(firstImage, format: format, into: exportRoot)
        guard let decoded = CGImageSourceCreateWithURL(converted as CFURL, nil),
              let bitmap = CGImageSourceCreateImageAtIndex(decoded, 0, nil) else {
            fatalError("Converted image must decode")
        }
        precondition(CGImageSourceGetType(decoded) as String? == format.type.identifier)
        precondition(bitmap.width == 4 && bitmap.height == 2)
        precondition(converted != firstImage)
    }
    let unchangedImage = try Data(contentsOf: firstImage)
    precondition(unchangedImage == imageBytes, "Conversion preserves the source")
    do {
        _ = try ImageConverter.convert(second, format: .png, into: root)
        fatalError("Non-image accepted")
    } catch {}
    print("PASS: every available image conversion decodes with correct dimensions and type, originals preserved, invalid input rejected")
    let duplicateImage = try ShelfTransfer.saveImage(imageBytes, to: root)
    precondition(duplicateImage.lastPathComponent == "Image (2).png")
    precondition(ShelfStore(root: root).items.contains { $0.name == firstImage.lastPathComponent })
    do { _ = try ShelfTransfer.saveImage(Data([1, 2, 3]), to: root); fatalError("Corrupt image accepted") }
    catch {}
    print("PASS: raw image pasteboard import, byte preservation, duplicate names and persistent storage")
    guard let cover = ArtworkImage.decode(imageBytes) else { fatalError("Valid cover failed to decode") }
    precondition(abs(cover.size.width / cover.size.height - 2) < 0.01, "Artwork must preserve its aspect ratio")
    precondition(max(cover.size.width, cover.size.height) <= 256)

    for playerApp in MusicApp.allCases where NSWorkspace.shared.urlForApplication(withBundleIdentifier: playerApp.bundleID) != nil {
        let scripts = [Player.metadataScript(app: playerApp, command: nil, connecting: true), Player.artworkScript(app: playerApp)] +
            ["playpause", "next track", "previous track"].map { Player.metadataScript(app: playerApp, command: $0, connecting: false) }
        for source in scripts {
            var scriptError: NSDictionary?
            guard NSAppleScript(source: source)?.compileAndReturnError(&scriptError) == true else {
                throw NSError(domain: "Player script", code: 1, userInfo: [NSLocalizedDescriptionKey: "\(playerApp.rawValue): \(String(describing: scriptError))"])
            }
        }
    }
    print("PASS: .3mf/.stl/unknown/no-extension imports and exports, native file URL pasteboards and drag providers, artwork URL validation, installed-player script compilation")
    let testDomain = "Harbor-Preferences-Test-" + UUID().uuidString
    let testPreferences = UserDefaults(suiteName: testDomain)!
    defer { testPreferences.removePersistentDomain(forName: testDomain) }
    testPreferences.set(MusicApp.music.rawValue, forKey: Player.savedPlayerKey)
    let restoredPlayer = Player(preferences: testPreferences, startPolling: false)
    precondition(restoredPlayer.selected == .music)
    precondition(restoredPlayer.shouldReconnect(playerIsRunning: true))
    precondition(!restoredPlayer.shouldReconnect(playerIsRunning: false), "Do not launch a closed player automatically")
    restoredPlayer.disconnect()
    precondition(!restoredPlayer.shouldReconnect(playerIsRunning: true))
    precondition(testPreferences.string(forKey: Player.savedPlayerKey) == nil)
    let anchor = Date(timeIntervalSince1970: 0)
    precondition(Player.projectedPosition(sample: 20, sampledAt: anchor, now: anchor.addingTimeInterval(5), playing: true, duration: 100) == 25)
    precondition(Player.projectedPosition(sample: 20, sampledAt: anchor, now: anchor.addingTimeInterval(5), playing: false, duration: 100) == 20)
    precondition(Player.projectedPosition(sample: 98, sampledAt: anchor, now: anchor.addingTimeInterval(5), playing: true, duration: 100) == 100)
    precondition(Player.timeLabel(65) == "1:05")
    print("PASS: saved-player restoration, reconnect only when running, disconnect preference clearing, elapsed-time projection")
    let ancestorExport = try ShelfStore.copy(second, into: temp)
    let ancestorBytes = try Data(contentsOf: ancestorExport)
    precondition(ancestorBytes == originalData, "Saving into an ancestor folder must remain possible")
    let state = HarborState()
    let panelFrame = NSRect(x: -1250, y: 840, width: state.expandedWidth, height: state.topInset + state.contentHeight)
    let hiddenTarget = state.interactionRect(in: panelFrame)
    state.presentation = .peek
    let peekTarget = state.interactionRect(in: panelFrame)
    precondition(peekTarget.width == hiddenTarget.width && hiddenTarget.height == state.topInset, "Hidden activation must fit the camera housing")
    precondition(!notchContains(hiddenTarget, NSPoint(x: hiddenTarget.midX, y: hiddenTarget.minY - 1)), "Browser tabs below the notch must remain available")
    for x in [peekTarget.minX, peekTarget.midX, peekTarget.maxX] {
        precondition(notchContains(peekTarget, NSPoint(x: x, y: panelFrame.maxY)), "Include the full top edge")
        precondition(notchContains(peekTarget, NSPoint(x: x, y: peekTarget.minY)), "Include the strip below the camera")
    }
    precondition(!notchContains(peekTarget, NSPoint(x: peekTarget.midX, y: peekTarget.minY - 1)))
    precondition(!notchContains(peekTarget, NSPoint(x: peekTarget.maxX + 1, y: peekTarget.midY)))
    print("PASS: entire notch and strip below it are interactive, with a stable target as the lip appears")
    var policy = NotchPolicy()
    policy.pointer(inside: true, interacting: false, now: 0)
    policy.pointer(inside: true, interacting: false, now: 0.1)
    precondition(policy.presentation(at: 0.1) == .peek, "Hover must only peek")
    policy.pointer(inside: true, interacting: false, now: 10)
    precondition(policy.presentation(at: 10) == .peek, "Dwelling must never open full panel")
    policy.setExpanded(true)
    precondition(policy.presentation(at: 10) == .expanded, "Explicit click opens full panel")
    policy.pointer(inside: false, interacting: false, now: 11)
    policy.pointer(inside: false, interacting: false, now: 11.4)
    precondition(policy.presentation(at: 11.4) == .hidden)
    for cycle in 0..<20 {
        let t = Double(cycle) * 3 + 12
        policy.pointer(inside: true, interacting: false, now: t)
        policy.pointer(inside: true, interacting: false, now: t + 0.1)
        precondition(policy.presentation(at: t + 0.1) == .peek)
        policy.pointer(inside: false, interacting: false, now: t + 1)
        policy.pointer(inside: false, interacting: false, now: t + 1.4)
        precondition(policy.presentation(at: t + 1.4) == .hidden)
    }
    policy.trackChanged(key: "song-A", playing: true, now: 100)
    precondition(policy.presentation(at: 100) == .song)
    policy.trackChanged(key: "song-A", playing: true, now: 102)
    precondition(policy.presentation(at: 102.49) == .song)
    precondition(policy.presentation(at: 102.51) == .hidden, "Refresh must not extend banner")
    policy.trackChanged(key: "song-A", playing: false, now: 103)
    policy.trackChanged(key: "song-A", playing: true, now: 104)
    precondition(policy.presentation(at: 104) == .hidden, "Pause/resume must not reannounce")
    policy.trackChanged(key: "song-B", playing: false, now: 105)
    precondition(policy.presentation(at: 105) == .hidden)
    policy.trackChanged(key: "song-B", playing: true, now: 106)
    precondition(policy.presentation(at: 106) == .song)
    policy.setExpanded(true)
    policy.trackChanged(key: "song-C", playing: true, now: 107)
    precondition(policy.presentation(at: 107) == .expanded, "New songs must not replace full panel")
    policy.dismiss()
    precondition(policy.presentation(at: 107) == .hidden)
    policy.pointer(inside: true, interacting: false, now: 110)
    policy.pointer(inside: true, interacting: false, now: 110.1)
    policy.trackChanged(key: "song-D", playing: true, now: 111)
    precondition(policy.presentation(at: 111) == .song)
    precondition(policy.presentation(at: 113.51) == .peek, "Hovered notch returns to its small lip")
    print("PASS: hover only peeks, explicit open, 20 hover cycles, click-away, 2.5-second song banners, duplicate/pause suppression, full-panel priority")
    print("PASS: file content, duplicate names, folder copies, persistence, original preservation, recursive/self copy rejection, export, failed-import cleanup")
}

// Render only this app's own view into an image for layout QA, without showing or
// activating a window, moving the pointer, or capturing anything on the user's screen.
if let index = CommandLine.arguments.firstIndex(of: "--render-preview"), CommandLine.arguments.count > index + 1 {
    let application = NSApplication.shared
    application.setActivationPolicy(.prohibited)
    let state = HarborState()
    state.presentation = CommandLine.arguments.contains("--preview-peek") ? .peek :
        (CommandLine.arguments.contains("--preview-song") ? .song : .expanded)
    let previewPlayer = Player(startPolling: false)
    if state.presentation == .song { previewPlayer.title = "A Moment in Motion" }
    let previewRoot = FileManager.default.temporaryDirectory.appendingPathComponent("Harbor-preview-" + UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: previewRoot) }
    state.converterSelected = CommandLine.arguments.contains("--preview-converter")
    let shelf = ShelfStore(root: previewRoot)
    if CommandLine.arguments.contains("--preview-populated") {
        for name in ["Bracket.3mf", "Assembly.stl", "Notes.txt"] {
            try! Data("Preview fixture".utf8).write(to: previewRoot.appendingPathComponent(name))
        }
        try! shelf.reload()
        previewPlayer.connected = true
        previewPlayer.title = "A Moment in Motion"
        previewPlayer.artist = "Harbor Sessions"
        previewPlayer.album = "Evening Light"
        previewPlayer.duration = 240
        previewPlayer.playbackPosition = 65
    }
    let view = NSHostingView(rootView: HarborView(state: state, shelf: shelf, player: previewPlayer))
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: state.expandedWidth, height: state.topInset + state.contentHeight), styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = view
    view.frame = NSRect(x: 0, y: 0, width: state.expandedWidth, height: state.topInset + state.contentHeight)
    RunLoop.main.run(until: Date().addingTimeInterval(0.2))
    view.layoutSubtreeIfNeeded()
    guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { fatalError("Cannot render preview") }
    view.cacheDisplay(in: view.bounds, to: bitmap)
    guard let data = bitmap.representation(using: .png, properties: [:]) else { fatalError("Cannot encode preview") }
    do { try data.write(to: URL(fileURLWithPath: CommandLine.arguments[index + 1])); exit(0) }
    catch { fputs("Preview failed: \(error)\n", stderr); exit(1) }
}

if CommandLine.arguments.contains("--self-test") {
    do { try selfTest(); exit(0) } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
}
let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
