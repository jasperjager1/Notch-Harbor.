import AppKit
import ImageIO
import SwiftUI

enum ShelfClipboard {
    @discardableResult
    static func copy(_ url: URL, asImage: Bool, to board: NSPasteboard) -> Bool {
        let contents: any NSPasteboardWriting
        if asImage {
            guard let data = try? Data(contentsOf: url),
                  let image = CGImageSourceCreateWithData(data as CFData, nil),
                  let type = CGImageSourceGetType(image) else { return false }
            let item = NSPasteboardItem()
            guard item.setData(data, forType: NSPasteboard.PasteboardType(type as String)) else { return false }
            contents = item
        } else {
            guard FileManager.default.fileExists(atPath: url.path) else { return false }
            contents = url as NSURL
        }
        board.clearContents()
        return board.writeObjects([contents])
    }
}

// Anchor the system picker to a native button in the shelf, not a new app window.
struct ShelfShareButton: NSViewRepresentable {
    let url: URL
    let shelf: ShelfStore
    let state: HarborState

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton()
        button.isBordered = false
        button.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        button.imagePosition = .imageOnly
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        button.contentTintColor = .white
        button.target = context.coordinator
        button.action = #selector(Coordinator.share(_:))
        button.sendAction(on: .leftMouseDown)
        return button
    }

    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.parent = self
        button.toolTip = "Share \(url.lastPathComponent)"
        button.setAccessibilityLabel(button.toolTip)
    }

    static func dismantleNSView(_ nsView: NSButton, coordinator: Coordinator) {
        coordinator.close()
    }

    final class Coordinator: NSObject, NSSharingServicePickerDelegate {
        var parent: ShelfShareButton
        private var picker: NSSharingServicePicker?

        init(_ parent: ShelfShareButton) { self.parent = parent }

        @objc func share(_ button: NSButton) {
            guard let window = button.window, !parent.state.sharePickerOpen else { return }
            guard FileManager.default.fileExists(atPath: parent.url.path) else {
                parent.shelf.message = "This file is no longer on the shelf."
                try? parent.shelf.reload()
                return
            }
            HarborFeedback.play()
            window.makeKey()
            // A file URL shares the file itself, preserving its name and original bytes.
            let picker = NSSharingServicePicker(items: [parent.url as NSURL])
            self.picker = picker
            picker.delegate = self
            parent.state.sharePickerOpen = true
            picker.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }

        func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, didChoose service: NSSharingService?) {
            guard picker === sharingServicePicker else { return }
            if service != nil { HarborFeedback.confirm() }
            picker = nil
            parent.state.sharePickerOpen = false
        }

        func close() {
            guard let picker else { return }
            self.picker = nil
            picker.delegate = nil
            picker.close()
            parent.state.sharePickerOpen = false
        }
    }
}
