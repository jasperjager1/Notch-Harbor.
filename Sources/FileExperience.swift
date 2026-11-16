import SwiftUI
import AppKit
import QuickLookThumbnailing
import QuickLookUI
import UniformTypeIdentifiers

final class FilePreview: NSObject, NSWindowDelegate {
    static let shared = FilePreview()
    private var window: NSWindow?
    func show(_ url: URL) {
        HarborFeedback.play()
        window?.close()
        let preview = QLPreviewView(frame: NSRect(x: 0, y: 0, width: 680, height: 480), style: .normal)!
        preview.autoresizingMask = [.width, .height]
        preview.shouldCloseWithWindow = false
        preview.previewItem = url as NSURL
        let window = NSWindow(contentRect: preview.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.title = url.lastPathComponent
        window.contentView = preview
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }
    func windowWillClose(_ notification: Notification) {
        // Release preview-provider resources as soon as the preview window closes.
        (window?.contentView as? QLPreviewView)?.close()
        window?.contentView = nil
        window = nil
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        HarborFeedback.play()
        return true
    }
}

private enum ThumbnailCache {
    static let images: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 64
        cache.totalCostLimit = 8 * 1024 * 1024
        return cache
    }()
}

struct FileCard: View {
    let item: ShelfItem
    @ObservedObject var shelf: ShelfStore
    let state: HarborState
    @State private var thumbnail: NSImage?
    @State private var hovered = false
    @State private var request: QLThumbnailGenerator.Request?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(spacing: 5) {
            Image(nsImage: thumbnail ?? NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable().scaledToFit().frame(width: 36, height: 36)
                .shadow(color: .black.opacity(0.22), radius: 3, y: 2)
                .animation(.easeInOut(duration: 0.2), value: thumbnail != nil)
            Text(item.name).font(.system(size: 10, weight: .medium)).lineLimit(1).truncationMode(.middle)
            Text(item.url.pathExtension.isEmpty ? "FILE" : item.url.pathExtension.uppercased())
                .font(.system(size: 8, weight: .medium)).foregroundColor(.white.opacity(0.35)).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(width: 90, height: 86)
        .background(RoundedRectangle(cornerRadius: 13, style: .continuous).fill(Color.white.opacity(hovered ? 0.085 : 0.035)))
        .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(Color.white.opacity(hovered ? 0.13 : 0.045), lineWidth: 0.6) }
        .overlay(alignment: .topLeading) {
            ShelfShareButton(url: item.url, shelf: shelf, state: state)
                .frame(width: 20, height: 20)
                .background(.black.opacity(0.72), in: Circle())
                .padding(3)
        }
        .overlay(alignment: .topTrailing) {
            Button { shelf.remove(item) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                    .frame(width: 20, height: 20).background(.black.opacity(0.75), in: Circle())
            }.buttonStyle(.plain).padding(3)
                .help("Remove from notch — moves the shelf copy to Trash")
                .accessibilityLabel("Remove " + item.name + " from notch")
                .disabled(shelf.busy)
        }
        .scaleEffect(hovered && !reduceMotion ? 1.025 : 1)
        .animation(.easeOut(duration: 0.18), value: hovered)
        .onHover { hovered = $0 }
        .onTapGesture(count: 2) { FilePreview.shared.show(item.url) }
        .onDrag { HarborFeedback.play(.alignment); return NSItemProvider(object: item.url as NSURL) }
        .contextMenu { actions }
        .help("\(item.name)\nDouble-click to preview · right-click for actions · × to remove")
        .accessibilityElement(children: .contain)
        .accessibilityLabel(item.name)
        .accessibilityAction(named: "Quick Look") { FilePreview.shared.show(item.url) }
        .onAppear { loadThumbnail() }
        .onDisappear { if let request { QLThumbnailGenerator.shared.cancel(request) } }
    }
    private var isImage: Bool {
        (try? item.url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .image)) == true
    }
    private func copy(asImage: Bool) {
        if ShelfClipboard.copy(item.url, asImage: asImage, to: .general) {
            HarborFeedback.confirm()
            shelf.message = asImage ? "Image copied." : "File copied."
        } else {
            shelf.message = "Couldn’t copy this item."
        }
    }
    @ViewBuilder private var actions: some View {
        if isImage { Button("Copy Image") { copy(asImage: true) } }
        Button("Copy File") { copy(asImage: false) }
        Button("Quick Look") { FilePreview.shared.show(item.url) }
        Button("Open") { HarborFeedback.play(); NSWorkspace.shared.open(item.url) }
        Button("Reveal in Finder") { HarborFeedback.play(); NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
        Button("Save a Copy…") { shelf.export(item) }
        Button("Move to Folder…") { shelf.move(item) }
        Divider()
        Button("Remove from Notch", role: .destructive) { shelf.remove(item) }
    }
    private func loadThumbnail() {
        if let cached = ThumbnailCache.images.object(forKey: item.url as NSURL) { thumbnail = cached; return }
        let request = QLThumbnailGenerator.Request(fileAt: item.url, size: NSSize(width: 64, height: 64), scale: 2, representationTypes: .all)
        self.request = request
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { result, _ in
            guard let image = result?.nsImage else { return }
            DispatchQueue.main.async {
                ThumbnailCache.images.setObject(image, forKey: item.url as NSURL, cost: 128 * 128 * 4)
                thumbnail = image
            }
        }
    }
}
