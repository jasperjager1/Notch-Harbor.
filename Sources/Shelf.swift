import AppKit
import Combine

struct ShelfItem: Identifiable {
    let url: URL
    var id: String { url.lastPathComponent }
    var name: String { url.lastPathComponent }
}

// Each import is a copy. Enumerating the directory is the persistence format.
final class ShelfStore: ObservableObject {
    @Published var items: [ShelfItem] = []
    @Published var message = "Drop files or folders here · copies stay on this Mac"
    @Published var busy = false
    let root: URL
    let queue = DispatchQueue(label: "local.notchharbor.import", qos: .userInitiated)

    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchHarbor/Shelf", isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
            try reload()
        } catch { message = error.localizedDescription }
    }
    func reload() throws {
        items = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey], options: [])
            .filter { !$0.lastPathComponent.hasPrefix(".import-") }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { ShelfItem(url: $0) }
    }
    static func copy(_ source: URL, into root: URL) throws -> URL {
        let fm = FileManager.default
        let src = source.standardizedFileURL.resolvingSymlinksInPath()
        let destRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        guard src.path != destRoot.path, !destRoot.path.hasPrefix(src.path + "/"),
              src.deletingLastPathComponent().path != destRoot.path else {
            throw NSError(domain: "Shelf", code: 1, userInfo: [NSLocalizedDescriptionKey: "That item is already in this folder, or contains the destination folder."])
        }
        var destination = root.appendingPathComponent(source.lastPathComponent)
        var n = 2
        while fm.fileExists(atPath: destination.path) {
            let ext = source.pathExtension
            let base = source.deletingPathExtension().lastPathComponent
            destination = root.appendingPathComponent("\(base) (\(n))" + (ext.isEmpty ? "" : ".\(ext)"))
            n += 1
        }
        let staging = root.appendingPathComponent(".import-" + UUID().uuidString)
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: source, to: staging)
        try fm.moveItem(at: staging, to: destination)
        return destination
    }
    func add(_ urls: [URL]) {
        guard !busy, !urls.isEmpty else { return }
        busy = true
        message = "Copying \(urls.count) item(s)…"
        let root = root
        queue.async {
            var failures: [String] = []
            var count = 0
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do { _ = try Self.copy(url, into: root); count += 1 }
                catch { failures.append("\(url.lastPathComponent): \(error.localizedDescription)") }
            }
            let result = failures.isEmpty ? "Saved \(count) item(s). Drag back out or use Save a Copy." : failures.joined(separator: "\n")
            DispatchQueue.main.async {
                self.busy = false
                do {
                    try self.reload()
                    self.message = result
                    if count > 0 { HarborFeedback.confirm() }
                }
                catch { self.message = error.localizedDescription }
            }
        }
    }
    func chooseFiles() {
        HarborFeedback.play()
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.allowsOtherFileTypes = true
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { add(panel.urls) }
    }
    func export(_ item: ShelfItem) {
        HarborFeedback.play()
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Save a copy to…"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let folder = panel.url {
            do {
                let saved = try Self.copy(item.url, into: folder)
                HarborFeedback.confirm()
                NSWorkspace.shared.activateFileViewerSelecting([saved])
            }
            catch { message = error.localizedDescription }
        }
    }
    func move(_ item: ShelfItem) {
        guard !busy else { return }
        HarborFeedback.play()
        NSApp.activate(ignoringOtherApps: true)
        let panel = NSOpenPanel()
        panel.title = "Move shelf file to…"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        do {
            let saved = try Self.copy(item.url, into: folder)
            do {
                try FileManager.default.removeItem(at: item.url)
                message = "Moved to " + folder.lastPathComponent + "."
            } catch {
                message = "Saved a copy, but couldn’t remove the shelf copy."
            }
            try reload()
            HarborFeedback.confirm()
            NSWorkspace.shared.activateFileViewerSelecting([saved])
        } catch { message = error.localizedDescription }
    }
    func remove(_ item: ShelfItem) {
        guard !busy else { return }
        do {
            _ = try FileManager.default.trashItem(at: item.url, resultingItemURL: nil)
            try reload()
            HarborFeedback.confirm()
            message = "Shelf copy moved to Trash. Your original is untouched."
        }
        catch { message = error.localizedDescription }
    }
}
