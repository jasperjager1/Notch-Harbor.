# Notch Harbor

The installed app is currently named **NotchNook**. Its internal bundle and storage names retain **NotchHarbor** for compatibility.

A native macOS notch companion with a persistent file shelf, image conversion, and Apple Music / Spotify controls. Built with SwiftUI and AppKit for Apple Silicon, with the MacBook Air M2 as the primary development machine.

This is an independent project, inspired by notch utilities. It is unaffiliated with Lo.cafe or the commercial NotchNook product. The implementation and bundled icon are original.

## What it does

- Hover directly over the camera notch to reveal a small preview, then click to open.
- Drag a file to the notch to open the tray automatically.
- Keep local copies of files and folders on a shelf across restarts.
- Preview, share, copy, move, export, or remove shelf items.
- Convert single images between JPEG, PNG, HEIC, TIFF, BMP, and GIF.
- Control the Apple Music or Spotify desktop app, including album artwork and a brief new-song banner.
- Provide Force Touch feedback for actions, with a menu setting to disable it.
- Optionally start at login and recover after abnormal exits.

## Requirements

| Item | Needed for |
| --- | --- |
| Apple Silicon Mac, such as M1 or M2 | Running this arm64 build |
| macOS 13 or newer | Declared deployment target |
| Mac with a camera notch | Intended placement and interaction |
| Force Touch trackpad | Optional haptic feedback |
| Apple Music or Spotify desktop app | Optional music controls |
| Apple Command Line Tools or Xcode with a current macOS SDK | Building from source |
| Python 3 | Optional login-startup management |

A non-notched display uses a top-center fallback. The project has been developed on an M2 MacBook Air. Other screen configurations and older supported macOS versions need further hands-on testing.

The app has no third-party package dependencies. Homebrew, Node.js, a Spotify API key, and a paid Apple Developer membership are unnecessary for a local build. Apple Music and Spotify manage their own accounts, subscriptions, and playback queues.

## Install from source

### 1. Install Apple's developer tools

Open Terminal and run the following command. Finish the macOS installer before continuing.

```sh
xcode-select --install
```

If the tools are already installed, macOS tells you so. Full Xcode is also supported. Apple provides the tools through its developer resources. [Apple developer tools](https://developer.apple.com/xcode/resources/)

Check that the compiler is available.

```sh
xcrun swiftc --version
```

### 2. Download the project

On this repository's GitHub page, choose **Code → Download ZIP**, extract the source, and open Terminal in that extracted folder. In Finder, you can type `cd ` in Terminal, drag the folder into the Terminal window, and press Return.

Alternatively, clone it with Git.

```sh
git clone https://github.com/jasperjager1/Notch-Harbor..git
cd Notch-Harbor.
```

### 3. Build and install

Run these commands from the project folder.

```sh
chmod +x build.sh install.sh
./build.sh
./install.sh
```

The build compiles the Swift files, packages the icon and instructions, signs the app locally, verifies the signature, runs self-tests, and creates `NotchNook.zip`. Compilation uses temporary storage and removes it afterward.

The installer extracts the app into **your home folder → Applications → NotchNook.app** and launches it. This is `~/Applications`, which is separate from the system-wide Applications folder.

The installer refuses to overwrite an existing installation. Follow the update instructions below if you already have the app.

### 4. Find the app

Look for the tray icon in the menu bar. NotchNook runs as a menu-bar accessory and has no Dock icon. Hover directly over the notch to reveal the small lip, then click to expand it. Use the tray menu to show it manually, open instructions, manage feedback, or quit.

## Install a packaged build

If a release includes `NotchNook.zip`, download that asset, extract it, and move **NotchNook.app** into `~/Applications`. Create that folder in your home folder if needed. Open the app there.

Packaged builds are locally signed and have no Apple notarization or Developer ID signature. If macOS blocks a downloaded copy, review its source and origin. For an app you trust, Apple's supported process is to attempt opening it, then use **System Settings → Privacy & Security → Open Anyway** when offered. A damaged-app warning can indicate a broken download or modified signature. Download a fresh copy or build from source. [Apple's app-opening guidance](https://support.apple.com/en-us/102445)

## Everyday use

### Open and close

Hover over the camera notch itself. A small lip appears below it. Click the notch or visible lip to open the full panel. Click elsewhere or move away to collapse it. Hovering around nearby browser tabs should leave the notch hidden.

Dragging a supported file onto the notch opens the tray automatically so you can release it there.

### Keep and retrieve files

Drop files and folders from Finder, or click **+** to choose them. The shelf accepts readable files of any type, including STL, 3MF, images, and files without extensions. The tray menu also provides **Paste Image or File**. Press Command-V while the notch panel has focus to paste copied files or images.

Imports create local copies. Your original stays in its original location. Shelf copies persist until you move or remove them.

- Drag a shelf card to Finder or an app that accepts files.
- Double-click a card for Quick Look.
- Click the share arrow for native macOS sharing.
- Click **×** to remove the shelf copy to Trash.
- Right-click a card for Copy Image, Copy File, Open, Reveal in Finder, Save a Copy, Move to Folder, and removal.

**Save a Copy** keeps the shelf item. **Move to Folder** copies to your chosen destination, then removes the shelf copy after a successful copy. If removal fails, the app reports that a copy was saved. Existing destination filenames receive numbered suffixes.

Opening a shelf file edits the shelf copy. Finder and other receiving apps determine whether a drag operation copies or moves the file.

### Share and AirDrop

Click the arrow on a card to open the macOS sharing picker. Available services depend on your Mac and file type. Select AirDrop, Messages, Mail, or another service, then complete the system's sharing flow. AirDrop availability also depends on nearby devices and their discoverability settings.

### Convert images

1. Open **File Converter** beside the Files tab.
2. Add an image with **+**, or use an image already on the shelf.
3. Choose the source image and the output format.
4. Click **Convert**.
5. Drag the result out, choose **Save a Copy**, or choose **Move**.

The converter offers the output formats supported by macOS on your machine, drawn from PNG, JPEG, HEIC, TIFF, BMP, and GIF. It runs locally and saves a separate converted file on the shelf.

Only single images are supported. Animated and multipage files are rejected. JPEG and other output formats without transparency use a white background. Lossy formats use high quality and can change the image appearance. Orientation is retained where supported; other source metadata is omitted. Audio, video, CAD, and document conversion are outside this version.

### Connect music

Choose Apple Music or Spotify in the player picker, then click **Connect**. Allow macOS Automation access when prompted. Start a track in the chosen desktop app if its queue is empty.

Use previous, play/pause, and next in the notch. The selected player is remembered and reconnects when it is running. The app waits while the player is closed. An explicit Connect action can launch it.

Each new playing track shows its artwork and title for about 2.5 seconds. Repeated metadata refreshes and pause/resume do not repeat the banner. Missing artwork uses a music-note placeholder. Playback progress is displayed but cannot be dragged to seek.

Choose **Disconnect Music Player** in the tray menu to clear the saved connection. Selecting another player also clears the previous preference.

### Trackpad feedback

Use **Trackpad Feedback** in the tray menu to toggle feedback. Actions such as opening the notch, skipping tracks, copying, sharing, and saving files have short pulses. Feedback depends on your trackpad and macOS settings.

## Permissions and privacy

Music integration uses Apple Events. macOS asks for Automation permission separately for each player. If denied, enable the player under **System Settings → Privacy & Security → Automation**, then reconnect. Rebuilding or replacing a locally signed app can require approval again.

The app's file and music features do not request camera, microphone, Screen Recording, Accessibility, or Full Disk Access permissions. macOS may ask for normal access to protected folders. Cloud files must be downloaded and readable before import.

Files and settings stay on your Mac. There is no application account, analytics service, or upload backend. Sharing sends files only through the macOS service you choose. Apple Music artwork comes from its local scripting interface. Spotify artwork downloads over HTTPS from the artwork URL supplied by its desktop app.

## Storage

| Location | Contents |
| --- | --- |
| `~/Applications/NotchNook.app` | Installed application |
| `~/Library/Application Support/NotchHarbor/Shelf` | Persistent shelf copies |
| `~/Library/LaunchAgents/local.notchharbor.startup.plist` | Optional login service |
| `~/Library/Logs/NotchHarbor/` | Login-service diagnostic logs |
| Preferences domain `local.notchharbor.app` | Player and feedback settings |

The internal NotchHarbor names are retained for compatibility with saved files and preferences. Shelf files consume disk space and have no expiry. Disk encryption is provided by your Mac's own configuration.

A stopped import can leave a hidden `.import-…` item in the shelf folder. Close the app and verify no import is active before removing an abandoned staging item. Completed files are displayed separately from staging items.

## Start at login

Install the app at `~/Applications/NotchNook.app` first. From the source folder, run the following commands with Python 3.

```sh
python3 startup.py enable
python3 startup.py status
```

This installs a per-user LaunchAgent and starts the app. Administrator access is unnecessary. macOS may show it under **General → Login Items & Extensions**.

To stop the managed instance and disable startup, run the following command.

```sh
python3 startup.py disable
```

The script preserves the startup configuration with a `.disabled` suffix. A deliberate Quit is respected until the next login or manual launch. Startup recovery applies to abnormal exits. The app cannot operate while the computer is off, logged out, or asleep.

## Update

1. Finish any file imports.
2. If login startup is enabled, run `python3 startup.py disable`.
3. Quit NotchNook from its tray menu.
4. Build the new source with `./build.sh`.
5. Move the previous installed app to temporary storage, then run `./install.sh`.
6. Check that the new app opens and your shelf is present.
7. Re-enable startup with `python3 startup.py enable` if you use it.
8. Remove the superseded app and generated ZIP after verification.

Keep the source, shelf folder, and preferences. Avoid accumulating duplicate app installations or running copies from cloud-synced folders.

## Uninstall

Disable login startup with `python3 startup.py disable`, quit the app, then move `~/Applications/NotchNook.app` to Trash.

Your shelf files and preferences remain available. Export any files you want before deleting the shelf folder. Optional leftover startup configuration and logs are listed in the storage table.

## Troubleshooting

| Symptom | What to try |
| --- | --- |
| No notch interface | Find the tray icon, choose Show / Collapse, and hover directly over the camera housing. |
| No tray icon | Open the installed app. If using startup, run `python3 startup.py status`. |
| Drag does not open the tray | Start with a local Finder file and drag to the notch itself. Confirm the shelf is not already copying. The + button provides another import route. |
| Music will not connect | Install and open the chosen desktop player, start a track, check Automation permission, then reconnect. |
| No album art | Some tracks provide none. Spotify artwork also needs network access. |
| Image absent from converter | Add an image through +. Only files macOS identifies as images appear in the source picker. |
| Conversion fails | Try a single, readable image. Animated and multipage images are rejected. |
| A CAD file has a plain icon | Quick Look depends on installed preview providers. File storage still accepts the original bytes. |
| Installer says already installed | Follow the update procedure. The installer avoids overwriting an existing app. |
| Compiler or SDK error | Check `xcrun swiftc --version`, update Apple's developer tools, and rebuild. |
| No haptic feedback | Check Trackpad Feedback and your macOS trackpad settings. Feedback requires compatible hardware. |
| App disappears in full screen | Other notch utilities, menu-bar layouts, and full-screen spaces can affect this window. |

## Development and verification

The build targets arm64 macOS 13 and uses the SDK supplied by your selected Apple developer tools.

```sh
./build.sh
"$HOME/Applications/NotchNook.app/Contents/MacOS/NotchHarbor" --self-test
```

The second command tests the installed app. Self-tests use temporary files and cover persistence, duplicate names, byte fidelity, file URL pasteboards, image conversion, invalid inputs, preference restoration, hover policy, timed song banners, and installed-player script compilation.

The app can render its own view for layout inspection without capturing the user's desktop.

```sh
"$HOME/Applications/NotchNook.app/Contents/MacOS/NotchHarbor" \
  --render-preview /tmp/notchnook-preview.png --preview-populated
```

Add `--preview-converter`, `--preview-peek`, or `--preview-song` for other views.

| Source | Responsibility |
| --- | --- |
| `Sources/main.swift` | Panel, screen geometry, pointer handling, menu, self-tests |
| `Sources/HarborView.swift` | Notch layout and native drag destination |
| `Sources/HoverPolicy.swift` | Hover and song-banner timing |
| `Sources/Shelf.swift`, `ShelfTransfer.swift` | Local files, imports, exports, moves |
| `Sources/FileExperience.swift`, `ShelfSharing.swift` | Cards, Quick Look, clipboard, sharing |
| `Sources/FileConverter.swift` | Image conversion and converter UI |
| `Sources/Player.swift` | Player automation and artwork |
| `Sources/HarborFeedback.swift` | Haptic feedback |
| `Tools/MakeIcon.swift` | Icon generation source |
| `Resources/AppIcon.icns` | Bundled application icon |

Automated tests and rendered layout checks pass for the current build. Live music playback, permission prompts, AirDrop delivery, full Finder drag flows, and the physical feel of haptics require hands-on checks. Spotify integration is implemented but has not been verified end to end on this development machine.

The app uses desktop-player scripting, rather than a universal system media service. Browser playback, seeking, playlist management, and account sign-in are outside its scope.
