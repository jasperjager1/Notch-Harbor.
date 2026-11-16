import AppKit
import SwiftUI
import ImageIO
import UniformTypeIdentifiers

enum ConversionFormat: String, CaseIterable, Identifiable {
    case png = "PNG", jpeg = "JPEG", heic = "HEIC", tiff = "TIFF", bmp = "BMP", gif = "GIF"
    var id: String { rawValue }
    var type: UTType {
        switch self {
        case .png: return .png
        case .jpeg: return .jpeg
        case .heic: return .heic
        case .tiff: return .tiff
        case .bmp: return .bmp
        case .gif: return .gif
        }
    }
    static var available: [Self] {
        let supported = CGImageDestinationCopyTypeIdentifiers() as! [String]
        return allCases.filter { supported.contains($0.type.identifier) }
    }
}

enum ImageConverter {
    static func convert(_ source: URL, format: ConversionFormat, into root: URL) throws -> URL {
        guard let input = CGImageSourceCreateWithURL(source as CFURL, nil),
              CGImageSourceGetCount(input) == 1,
              let image = CGImageSourceCreateImageAtIndex(input, 0, nil) else {
            throw NSError(domain: "Converter", code: 1, userInfo: [NSLocalizedDescriptionKey:
                "Choose a single image. Animated and multipage files need a different converter."])
        }
        let temp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: temp) }
        let filename = source.deletingPathExtension().lastPathComponent + "." + (format.type.preferredFilenameExtension ?? "png")
        let output = temp.appendingPathComponent(filename)
        guard let destination = CGImageDestinationCreateWithURL(output as CFURL, format.type.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(input, 0, nil) as? [CFString: Any]
        var options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.92,
            kCGImageDestinationBackgroundColor: CGColor(gray: 1, alpha: 1)
        ]
        if let orientation = properties?[kCGImagePropertyOrientation] {
            options[kCGImagePropertyOrientation] = orientation
        }
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        return try ShelfStore.copy(output, into: root)
    }
}

struct FileConverterView: View {
    @ObservedObject var shelf: ShelfStore
    @State private var selected = ""
    @State private var format: ConversionFormat = .png
    @State private var result: URL?
    @State private var converting = false
    private var images: [ShelfItem] {
        shelf.items.filter { item in
            (try? item.url.resourceValues(forKeys: [.contentTypeKey]).contentType?.conforms(to: .image)) == true
        }
    }
    private var source: URL? { images.first { $0.id == selected }?.url }
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 7) {
                Picker("File", selection: $selected) {
                    Text("Choose a shelf file").tag("")
                    ForEach(images) { Text($0.name).tag($0.id) }
                }.labelsHidden()
                HStack {
                    Picker("Convert to", selection: $format) {
                        ForEach(ConversionFormat.available) { Text($0.rawValue).tag($0) }
                    }.frame(width: 145)
                    Button(converting ? "Converting…" : "Convert") { convert() }
                        .disabled(source == nil || converting || shelf.busy)
                }
                Text("Single images · JPEG, PNG, HEIC, TIFF, BMP, GIF")
                    .font(.system(size: 9)).foregroundColor(.secondary)
            }.frame(width: 300)
            VStack(alignment: .leading, spacing: 7) {
                if let result, FileManager.default.fileExists(atPath: result.path) {
                    Label(result.lastPathComponent, systemImage: "doc.badge.arrow.up")
                        .font(.system(size: 11)).lineLimit(1).truncationMode(.middle)
                        .onDrag { HarborFeedback.play(); return NSItemProvider(object: result as NSURL) }
                    HStack {
                        Button("Save a Copy…") { shelf.export(ShelfItem(url: result)) }
                        Button("Move…") { shelf.move(ShelfItem(url: result)) }
                    }.controlSize(.small).disabled(shelf.busy)
                } else {
                    Text("Converted files appear here and on your shelf.")
                        .font(.system(size: 11)).foregroundColor(.secondary)
                }
                Text(shelf.message).font(.system(size: 9)).foregroundColor(.secondary).lineLimit(2).help(shelf.message)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        .controlSize(.small)
        .onAppear { if selected.isEmpty { selected = images.first?.id ?? "" } }
        .padding(.horizontal, 14).padding(.top, 12)
        .frame(height: 132, alignment: .top)
    }
    private func convert() {
        guard let source, !shelf.busy else { return }
        converting = true
        shelf.busy = true
        shelf.message = "Converting…"
        HarborFeedback.play()
        let format = format
        shelf.queue.async {
            let outcome = Result { try ImageConverter.convert(source, format: format, into: shelf.root) }
            DispatchQueue.main.async {
                converting = false
                shelf.busy = false
                switch outcome {
                case .success(let url):
                    result = url
                    try? shelf.reload()
                    shelf.message = "Converted. Drag out or choose Move."
                    HarborFeedback.confirm()
                case .failure(let error): shelf.message = error.localizedDescription
                }
            }
        }
    }
}
