import AppKit
import ImageIO
import UniformTypeIdentifiers

enum ShelfTransfer {
    static let imageTypes = ["public.png", "public.jpeg", "public.tiff", "public.heic", "public.heif", "com.compuserve.gif", "org.webmproject.webp", "public.image"].map { NSPasteboard.PasteboardType($0) }
    static let promiseTypes = NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }
    static var dragTypes: [NSPasteboard.PasteboardType] { [.fileURL] + imageTypes + promiseTypes }

    static func fileURLs(on board: NSPasteboard) -> [URL] {
        board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }
    static func canRead(_ board: NSPasteboard) -> Bool {
        board.availableType(from: dragTypes) != nil
    }
    static func receive(_ board: NSPasteboard, into shelf: ShelfStore, allowPromises: Bool) -> Bool {
        guard !shelf.busy else { return false }
        if allowPromises, board.availableType(from: promiseTypes) != nil,
           let promises = board.readObjects(forClasses: [NSFilePromiseReceiver.self]) as? [NSFilePromiseReceiver],
           !promises.isEmpty {
            return shelf.addPromises(promises)
        }
        let files = fileURLs(on: board).filter {
            $0.standardizedFileURL.resolvingSymlinksInPath().deletingLastPathComponent().path != shelf.root.standardizedFileURL.resolvingSymlinksInPath().path
        }
        if !files.isEmpty { shelf.add(files); return true }
        // Do not turn a shelf card dragged back into Harbor into another copy.
        if board.availableType(from: [.fileURL]) != nil { return false }
        let images = (board.pasteboardItems ?? []).compactMap { item in
            imageTypes.lazy.compactMap { item.data(forType: $0) }.first
        }
        guard !images.isEmpty else { return false }
        shelf.addImages(images)
        return true
    }
    static func saveImage(_ data: Data, to root: URL) throws -> URL {
        guard let image = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(image) > 0,
              CGImageSourceGetStatus(image) == .statusComplete,
              let type = CGImageSourceGetType(image), let ext = UTType(type as String)?.preferredFilenameExtension else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var destination = root.appendingPathComponent("Image." + ext)
        var index = 2
        while FileManager.default.fileExists(atPath: destination.path) {
            destination = root.appendingPathComponent("Image (\(index))." + ext)
            index += 1
        }
        let staging = root.appendingPathComponent(".import-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        try data.write(to: staging)
        try FileManager.default.moveItem(at: staging, to: destination)
        return destination
    }
}

private final class PromiseBatch {
    var remaining = 0
    var saved = 0
    var failures: [String] = []
}

extension ShelfStore {
    func paste() {
        if ShelfTransfer.receive(.general, into: self, allowPromises: false) {
            HarborFeedback.play()
        } else if !busy {
            message = "Copy an image or file first, then paste it here."
        }
    }
    func addImages(_ images: [Data]) {
        guard !busy, !images.isEmpty else { return }
        busy = true
        message = "Saving images…"
        let root = root
        queue.async {
            var count = 0
            var errors: [String] = []
            for image in images {
                do { _ = try ShelfTransfer.saveImage(image, to: root); count += 1 }
                catch { errors.append("Couldn’t save an image: \(error.localizedDescription)") }
            }
            self.finishImport(count: count, errors: errors)
        }
    }
    func addPromises(_ receivers: [NSFilePromiseReceiver]) -> Bool {
        guard !busy, !receivers.isEmpty else { return false }
        let staging = root.appendingPathComponent(".import-promise-" + UUID().uuidString, isDirectory: true)
        do { try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false) }
        catch { message = error.localizedDescription; return false }

        busy = true
        message = "Receiving files…"
        let operations = OperationQueue()
        operations.maxConcurrentOperationCount = 1
        operations.qualityOfService = .userInitiated
        operations.isSuspended = true
        let batch = PromiseBatch()
        for receiver in receivers {
            receiver.receivePromisedFiles(atDestination: staging, options: [:], operationQueue: operations) { url, error in
                do {
                    if let error { throw error }
                    guard url.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(staging.standardizedFileURL.resolvingSymlinksInPath().path + "/") else {
                        throw CocoaError(.fileReadInvalidFileName)
                    }
                    _ = try Self.copy(url, into: self.root)
                    batch.saved += 1
                } catch { batch.failures.append(error.localizedDescription) }
                batch.remaining -= 1
                if batch.remaining == 0 {
                    self.finishImport(count: batch.saved, errors: batch.failures)
                    // Let the coordinated read finish before deleting the staging directory.
                    operations.addOperation { try? FileManager.default.removeItem(at: staging) }
                }
            }
            batch.remaining += max(1, receiver.fileNames.count)
        }
        operations.isSuspended = false
        return true
    }
    func finishImport(count: Int, errors: [String]) {
        DispatchQueue.main.async {
            self.busy = false
            do {
                try self.reload()
                self.message = (["Saved \(count) item(s)."] + errors).joined(separator: " ")
                if count > 0 { HarborFeedback.confirm() }
            } catch { self.message = error.localizedDescription }
        }
    }
}
