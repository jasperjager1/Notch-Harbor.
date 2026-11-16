import SwiftUI
import AppKit

final class HarborState: ObservableObject {
    var sharePickerOpen = false
    @Published var converterSelected = false
    @Published var presentation: HarborPresentation = .hidden
    var expanded: Bool {
        get { presentation == .expanded }
        set { presentation = newValue ? .expanded : .hidden }
    }
    @Published var targeted = false
    @Published var topInset: CGFloat = 34
    @Published var expandedWidth: CGFloat = 640
    @Published var collapsedWidth: CGFloat = 210
    var contentHeight: CGFloat { 132 }
    var peekWidth: CGFloat { collapsedWidth + 16 }
    var compactHitHeight: CGFloat { islandHeight }
    var notchWidth: CGFloat = 198
    var islandWidth: CGFloat {
        switch presentation {
        case .expanded: return expandedWidth
        case .song: return min(expandedWidth, max(320, collapsedWidth + 90))
        case .peek: return peekWidth
        case .hidden: return collapsedWidth
        }
    }
    func interactionRect(in frame: NSRect) -> NSRect {
        let width = presentation == .hidden || presentation == .peek ? notchWidth : islandWidth
        let height = presentation == .hidden ? topInset : islandHeight
        return NSRect(x: frame.midX - width / 2, y: frame.maxY - height, width: width, height: height)
    }
    var islandHeight: CGFloat {
        switch presentation {
        case .expanded: return topInset + contentHeight
        case .song: return topInset + 42
        case .peek: return topInset + 10
        case .hidden: return topInset
        }
    }
    var toggle: (() -> Void)?
    var expand: (() -> Void)?
    var expandForDrop: (() -> Void)?
}

struct HarborView: View {
    @ObservedObject var state: HarborState
    @ObservedObject var shelf: ShelfStore
    @ObservedObject var player: Player
    private let mint = Color(red: 0.48, green: 0.91, blue: 0.77)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var revealAnimation: Animation { reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.48, dampingFraction: 0.9) }
    private var islandShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(bottomLeadingRadius: state.expanded ? 24 : 10, bottomTrailingRadius: state.expanded ? 24 : 10)
    }
    private var islandWidth: CGFloat { state.islandWidth }
    private var islandHeight: CGFloat { state.islandHeight }
    var body: some View {
        ZStack(alignment: .top) {
            islandShape
                .fill(Color.black)
                .frame(width: islandWidth, height: islandHeight)
                .opacity(state.presentation.isVisible ? 1 : 0)
            VStack(spacing: 0) {
                expanded
                    .accessibilityHidden(!state.expanded)
                    .opacity(state.expanded ? 1 : 0)
                    .offset(y: state.expanded || reduceMotion ? 0 : -8)
                    .animation(.easeInOut(duration: reduceMotion ? 0.15 : 0.25), value: state.expanded)
            }
            .frame(width: state.expandedWidth, height: state.topInset + state.contentHeight, alignment: .top)
            .mask(alignment: .top) { islandShape.frame(width: islandWidth, height: islandHeight) }
            compact
                .opacity(state.presentation == .peek || state.presentation == .song ? 1 : 0)
                .allowsHitTesting(state.presentation == .peek || state.presentation == .song)
                .accessibilityHidden(state.presentation != .peek && state.presentation != .song)
                .animation(.easeInOut(duration: 0.2), value: state.presentation)
            if state.targeted {
                islandShape.stroke(mint.opacity(0.75), lineWidth: 1.5)
                    .frame(width: islandWidth - 2, height: islandHeight - 1)
            }
        }
        .frame(width: state.expandedWidth, height: state.topInset + state.contentHeight, alignment: .top)
        .foregroundColor(.white)
        .preferredColorScheme(.dark)
        .animation(revealAnimation, value: state.presentation)
        .animation(.easeInOut(duration: 0.2), value: state.targeted)
    }
    private var compact: some View {
        Button(action: { state.expand?() }) {
            VStack(spacing: 0) {
                Color.clear.frame(height: state.topInset)
                if state.presentation == .song {
                    HStack(spacing: 9) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08))
                            if let art = player.artwork {
                                Image(nsImage: art).resizable().scaledToFit()
                                    .id(player.artworkVersion).transition(.opacity)
                            } else {
                                Image(systemName: "music.note").font(.system(size: 12)).foregroundColor(.secondary)
                            }
                        }
                        .frame(width: 28, height: 28)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .animation(.easeInOut(duration: 0.25), value: player.artworkVersion)
                        Text(player.title).font(.system(size: 11, weight: .medium)).lineLimit(1).truncationMode(.tail)
                        Spacer(minLength: 0)
                    }.padding(.horizontal, 12).frame(height: 42)
                } else {
                    Capsule().fill(Color.white.opacity(0.3)).frame(width: 22, height: 2)
                        .frame(height: 10)
                }
            }
            .frame(width: islandWidth, height: state.compactHitHeight, alignment: .top)
            // Keep the compact control clickable within its visible shape.
            .background(Color.black.opacity(0.01))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state.presentation == .song ? "Now playing: \(player.title). Open NotchNook" : "Open NotchNook")
    }
    private var expanded: some View {
        VStack(spacing: 0) {
            toolbar
            if state.converterSelected {
                FileConverterView(shelf: shelf)
            } else {
            HStack(alignment: .top, spacing: 12) {
                shelfColumn.frame(width: (state.expandedWidth - 53) / 2)
                Rectangle().fill(Color.white.opacity(0.08)).frame(width: 1, height: 104)
                playerColumn.frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 10)
            .frame(height: state.contentHeight, alignment: .top)
            }
        }.frame(width: state.expandedWidth, alignment: .top)
    }
    private var toolbar: some View {
        let wing = max(0, (state.expandedWidth - state.collapsedWidth) / 2 - 14)
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                Picker("Tab", selection: $state.converterSelected) {
                    Text("Files").tag(false)
                    Text("File Converter").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(maxWidth: .infinity)
                    .onChange(of: state.converterSelected) { _ in HarborFeedback.play() }
                Button(action: shelf.chooseFiles) {
                    Image(systemName: "plus").frame(width: 20, height: 22)
                }.help("Add files or folders").disabled(shelf.busy)
            }.frame(width: wing)
            Color.clear.frame(width: state.collapsedWidth)
            HStack(spacing: 7) {
                Circle().fill(mint).frame(width: 4, height: 4).opacity(player.connected ? 1 : 0)
                    .accessibilityLabel(player.connected ? "Player connected" : "Player disconnected")
                Picker("Player", selection: $player.selected) {
                    ForEach(MusicApp.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().frame(width: 112).controlSize(.mini)
                    .onChange(of: player.selected) { _ in HarborFeedback.play(); player.disconnect() }
                Spacer(minLength: 0)
                Button(action: { state.toggle?() }) {
                    Image(systemName: "chevron.up").frame(width: 20, height: 22)
                }.help("Collapse NotchNook")
            }.frame(width: wing)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(.white.opacity(0.75))
        .buttonStyle(HarborPressStyle(reduceMotion: reduceMotion))
        .padding(.horizontal, 14)
        .frame(width: state.expandedWidth, height: state.topInset)
    }
    private var shelfColumn: some View {
        VStack(alignment: .leading, spacing: 7) {
            if shelf.items.isEmpty {
                HStack(spacing: 11) {
                    Image(systemName: state.targeted ? "tray.and.arrow.down.fill" : "tray.and.arrow.down")
                        .font(.system(size: 23, weight: .light)).foregroundColor(state.targeted ? mint : .white.opacity(0.5))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(state.targeted ? "Let go to save" : "Drop files here").font(.system(size: 11, weight: .medium))
                        Text("Any file or folder").font(.system(size: 9)).foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 90)
                .background(Color.white.opacity(state.targeted ? 0.06 : 0.025), in: RoundedRectangle(cornerRadius: 13))
                .overlay { RoundedRectangle(cornerRadius: 13).strokeBorder(Color.white.opacity(state.targeted ? 0.25 : 0.1), style: StrokeStyle(lineWidth: 0.7, dash: [3, 4])) }
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: 7) {
                        ForEach(shelf.items) { item in FileCard(item: item, shelf: shelf, state: state) }
                    }.padding(.vertical, 2).padding(.horizontal, 1)
                }.frame(height: 90)
                    .animation(.easeInOut(duration: 0.22), value: shelf.items.map(\.id))
            }
            HStack(alignment: .top, spacing: 5) {
                if shelf.busy { ProgressView().controlSize(.mini) }
                Text(state.targeted ? "Release to save" : shelf.message.hasPrefix("Drop files") ? "Drag out to retrieve · double-click to preview" : shelf.message)
                    .font(.system(size: 9)).foregroundColor(state.targeted ? mint : .white.opacity(0.35)).lineLimit(1)
                    .help(shelf.message)
            }.frame(height: 14, alignment: .top)
        }
    }
    private var playerColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.065))
                    if let artwork = player.artwork {
                        Image(nsImage: artwork).resizable().scaledToFit()
                            .id(player.artworkVersion).transition(.opacity)
                    } else {
                        Image(systemName: "music.note").font(.system(size: 23, weight: .light)).foregroundColor(.white.opacity(0.4))
                    }
                }
                .frame(width: 44, height: 44)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay { RoundedRectangle(cornerRadius: 11).strokeBorder(Color.white.opacity(0.09), lineWidth: 0.5) }
                .animation(.easeInOut(duration: reduceMotion ? 0.12 : 0.32), value: player.artworkVersion)
                .accessibilityLabel(player.artwork == nil ? "No album artwork available" : "Album artwork")
                VStack(alignment: .leading, spacing: 4) {
                    Text(player.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                    Text(player.artist).font(.system(size: 10)).foregroundColor(.secondary).lineLimit(1)
                    if !player.album.isEmpty {
                        Text(player.album).font(.system(size: 9)).foregroundColor(.white.opacity(0.35)).lineLimit(1)
                    }
                }
                .id(player.trackKey)
                .transition(.opacity.combined(with: .offset(y: reduceMotion ? 0 : 3)))
                Spacer(minLength: 0)
            }.frame(height: 46)
                .animation(.easeInOut(duration: 0.22), value: player.trackKey)
            if player.problem == nil { playbackProgress }
            HStack(spacing: 22) {
                Spacer()
                Button(action: { player.command("previous track") }) {
                    Image(systemName: "backward.end.fill").font(.system(size: 13, weight: .medium)).frame(width: 28, height: 30)
                }.help("Previous track")
                Button(action: { player.command("playpause") }) {
                    ZStack {
                        Circle().fill(Color.white.opacity(0.11))
                        Image(systemName: player.playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .id(player.playing).transition(.opacity)
                    }.frame(width: 30, height: 30)
                        .animation(.easeInOut(duration: 0.16), value: player.playing)
                }.help("Play or pause")
                Button(action: { player.command("next track") }) {
                    Image(systemName: "forward.end.fill").font(.system(size: 13, weight: .medium)).frame(width: 28, height: 30)
                }.help("Next track")
                Spacer()
            }
            .buttonStyle(HarborPressStyle(reduceMotion: reduceMotion))
            .disabled(!player.connected || player.commandPending)
            .opacity(player.connected ? 1 : 0)
            .overlay {
                if !player.connected {
                    Button(player.busy ? "Connecting…" : (player.problem != nil ? "Reconnect \(player.selected.rawValue)" : player.remembersConnection ? "Open \(player.selected.rawValue)" : "Connect to \(player.selected.rawValue)"), action: player.connect)
                        .controlSize(.small).disabled(player.busy)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: player.connected)
            if let problem = player.problem {
                Text(problem).font(.system(size: 10)).foregroundColor(.orange).lineLimit(2).help(problem)
            }
        }
    }
    private var playbackProgress: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let position = player.currentPosition(at: context.date)
            HStack(spacing: 7) {
                Text(Player.timeLabel(position))
                GeometryReader { geometry in
                    Capsule().fill(Color.white.opacity(0.09))
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.55))
                                .frame(width: player.duration > 0 ? geometry.size.width * position / player.duration : 0)
                        }
                }.frame(height: 3)
                Text(Player.timeLabel(player.duration))
            }
            .font(.system(size: 8, weight: .medium, design: .monospaced))
            .foregroundColor(.white.opacity(0.35))
            .frame(height: 12)
            .opacity(player.connected && player.duration > 0 ? 1 : 0)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Playback progress")
            .accessibilityValue("\(Player.timeLabel(position)) of \(Player.timeLabel(player.duration))")
        }
    }
}

struct HarborPressStyle: ButtonStyle {
    var reduceMotion = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.65 : 1)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.92 : 1)
            .animation(.easeOut(duration: 0.16), value: configuration.isPressed)
    }
}

// Native drag destination: expand on entry without resizing the window under the drag.
final class DropHost: NSHostingView<HarborView> {
    var state: HarborState
    var shelf: ShelfStore
    required init(rootView: HarborView) {
        self.state = rootView.state; self.shelf = rootView.shelf
        super.init(rootView: rootView)
        registerForDraggedTypes(ShelfTransfer.dragTypes)
    }
    @available(*, unavailable) required init(coder: NSCoder) { fatalError() }
    static func fileURLs(on pasteboard: NSPasteboard) -> [URL] { ShelfTransfer.fileURLs(on: pasteboard) }

    private func canAccept(_ sender: NSDraggingInfo) -> Bool {
        guard !shelf.busy, sender.draggingSourceOperationMask.contains(.copy),
              ShelfTransfer.canRead(sender.draggingPasteboard) else { return false }
        if let source = sender.draggingSource as? NSView, source.window === window { return false }
        return true
    }
    private func updateTarget(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard canAccept(sender), let window,
              notchContains(state.interactionRect(in: window.frame), window.convertPoint(toScreen: sender.draggingLocation)) else {
            state.targeted = false
            return []
        }
        if !state.targeted {
            state.targeted = true
            state.expandForDrop?()
            HarborFeedback.play(.alignment)
        }
        return .copy
    }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { updateTarget(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { updateTarget(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { state.targeted = false }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { updateTarget(sender) == .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        defer { state.targeted = false }
        guard updateTarget(sender) == .copy, ShelfTransfer.receive(sender.draggingPasteboard, into: shelf, allowPromises: true) else { return false }
        HarborFeedback.play()
        return true
    }
    override func draggingEnded(_ sender: NSDraggingInfo) { state.targeted = false }
}
