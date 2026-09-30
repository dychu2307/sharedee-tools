# Sharedee Tools

[Tiếng Việt](README.vi.md)

Sharedee Tools is a free, native macOS app with a main tools window and a menu bar icon for capturing and annotating screenshots. The source code is available under the [Apache License 2.0](LICENSE).

## Features

- Capture a selected area, a window, the full screen, or scrolling content.
- Copy a capture directly, or use the floating thumbnail to choose Copy, Edit, Save, or Drive. Drive uploads show their progress on the thumbnail and run only once per click.
- Annotate with arrows, rectangles, ellipses, freehand strokes, highlights, text, blur, and solid covers.
- Crop, undo and redo, and save PNG.
- Configure global keyboard shortcuts, capture delay, and scrolling capture length.
- Choose a local save folder and a default post-capture action. The default is copying the PNG to the clipboard.
- Connect Google Drive with your own Desktop OAuth Client ID. The app checks the Client ID and secret as you paste them, creates a Sharedee Tools folder by default, and lets you create folders or switch between them from Settings.
- **Capture and copy text:** select an area and its text goes straight to the clipboard, recognized on-device by Apple's Vision framework (Vietnamese, English, and your system languages). A small notice confirms what was copied; the capture itself is not kept, uploaded, or saved. On macOS 13 or newer, the editor's **Live Text** button lets you select and copy part of the text in any capture.
- Optionally open at login (macOS 13 or newer), and use the app in English or Vietnamese.

Sharedee Tools does not record video. Drive uploads occur only when you choose Upload or set it as the default action.

## Requirements

- macOS 12 or newer on Intel (`x86_64`) or Apple Silicon (`arm64`).
- Xcode to build from source. The checked-in Xcode project can be opened directly; [XcodeGen](https://github.com/yonaskolb/XcodeGen) is needed only after editing `project.yml`.
- macOS Screen Recording permission for captures. Auto-scroll in scrolling capture also needs Accessibility permission.

The app and its tests have been built on macOS 27 with Xcode 26.6. The Intel executable was also launched through Rosetta. An older physical Intel Mac has not been tested yet.

## Build from source

```sh
git clone https://github.com/dychu2307/sharedee-tools.git
cd sharedee-tools
open SharedeCapture.xcodeproj
```

In Xcode, select the `SharedeCapture` scheme and run it. The built app is named **Sharedee Tools** and uses Apple Development signing by default. Forks should select their own Development Team in Xcode's Signing settings. To build and test from the command line without signing:

```sh
xcodebuild -project SharedeCapture.xcodeproj -scheme SharedeCapture \
  -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project SharedeCapture.xcodeproj -scheme SharedeCapture \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

If you edit `project.yml`, run `xcodegen generate` before opening or building the project.

## Keeping macOS permissions across builds

For a local app that keeps Screen & System Audio Recording permission through updates, sign every build with the **same signing certificate** and keep the bundle ID (`com.sharedecapture.app`) unchanged. The unsigned or ad hoc builds produced by the commands above are useful for tests, but macOS treats each changed ad hoc build as a new app for privacy permissions. To package a signed local app:

```sh
security find-identity -v -p codesigning
SHAREDEE_SIGNING_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/build-signed-app.sh
```

The script writes `Sharedee Tools.app` to the repository root. Use an Apple Development identity for local builds, or the same Developer ID identity for each distributed release. Moving between signing identities requires granting the permission once again. After granting it, use **Settings → Restart Sharedee Tools** so macOS applies the new permission. Avoid launching old or ad hoc builds.

If an old **SharedeCapture** entry is enabled but the app still reports missing permission, add the repository-root `Sharedee Tools.app` in **System Settings → Privacy & Security → Screen & System Audio Recording**, enable that entry, and restart the app. The old entry can then be removed.

## Usage

Launch the app to open its main tools window. It also runs from the menu bar; closing the main window leaves the app running, and **Open Sharedee Tools** in the menu bar brings the window back. Captures appear as an ordered thumbnail stack in the lower right, with the newest at the bottom; scroll to reach older captures. Each thumbnail has its own **Copy**, **Edit**, and **Save** actions. **Edit** opens an image-sized floating panel containing only the capture and annotation tools. Settings is part of the main window, with General, Shortcuts, and Google Drive in its sidebar. **Settings → General** holds the language, **Open Sharedee Tools at login**, and the app version under **About**; the menu bar menu also has **About Sharedee Tools**. While the main window or editor is open, Sharedee Tools appears in the Dock and app switcher and remains visible when you switch apps. The Settings page stays visible during capture, so you can capture it. The editor closes after a successful **Copy**, **Save**, or **Drive upload**; canceling the save dialog keeps it open.

**Scrolling capture:** start it from the menu bar or its shortcut, drag to select the area that scrolls, and click **Capture**. Then either scroll inside the area with your mouse or trackpad, or click **Auto-scroll** inside the area (needs Accessibility permission) and point at the content to scroll: like a mouse wheel, it scrolls whatever is under the pointer. Auto-scroll stops at the end of the content and finishes by itself. Click **Done** (Return) to finish or **Cancel** (Esc) to discard. Frames are stitched as you go, sticky headers and footers appear only once, and scrolling back up is ignored. A playing video or animation inside the area is tolerated as long as the rest of the area has enough detail to line frames up; if frames stop matching, the app asks you to scroll more slowly or to pause the video. The maximum length is set in **Settings → General → Scrolling capture**.

## Google Drive

In **Settings → Google Drive**, paste a **Desktop app** OAuth Client ID and its client secret. Each field is checked with Google as you paste and shows a green check mark when it is valid; then click **Save Client ID**. Then click **Connect Google Drive**, sign in, and approve access. The app creates or reuses a **Sharedee Tools** folder in My Drive. Under **Upload folder** you can switch between the folders the app can use, create a new folder inside the current one or in My Drive, or pick any other existing folder with **Choose another folder on Google Drive…** (Google's picker cannot create folders). Then use **Drive** on the capture thumbnail, or make Drive upload the default post-capture action. After you approve access, the browser page confirms the connection and tries to close itself, and Sharedee Tools comes to the front.

**Creating a Client ID:** In a Google Cloud project, enable the **Google Drive API** and **Google Picker API**, configure the OAuth consent screen, and create a **Desktop app** OAuth Client ID. Copy both its Client ID and client secret; Google requires the secret on token requests even for desktop apps. If the OAuth app is in Testing, Google only permits configured test users. Anyone building a fork can use their own Google Cloud project.

**Optional publisher setup:** To let users connect without entering their own ID, set the target build settings `SHAREDEE_GOOGLE_CLIENT_ID` and `SHAREDEE_GOOGLE_CLIENT_SECRET` before building. For example, pass `SHAREDEE_GOOGLE_CLIENT_ID=your-id.apps.googleusercontent.com SHAREDEE_GOOGLE_CLIENT_SECRET=GOCSPX-…` to `xcodebuild`, or set them in `project.yml` and regenerate the Xcode project. Do not commit them to a public repository.

A user-entered Client ID, client secret, and refresh token are stored in the user's macOS Keychain. The app requests Google's narrow `drive.file` scope. A Client ID and secret supplied at build time are visible in the app bundle. For a Desktop app client, Google does not treat the client secret as confidential either.

## Versioning and app icons

Versions follow [Semantic Versioning](https://semver.org) and are computed from git at build time: the latest `vX.Y.Z` tag, bumped by the [Conventional Commits](https://www.conventionalcommits.org) made since (`feat:` → minor, `fix:` and others → patch, `feat!:` → major). The build number is the commit count. Run `scripts/version.sh` to see the current version; it appears in **Settings → General → About**. See [CONTRIBUTING.md](CONTRIBUTING.md) and [CHANGELOG.md](CHANGELOG.md). The app icon and the menu bar template icon are drawn by the scripts in `scripts/app-icon/`; see the comment at the top of each script for how to regenerate the assets.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the build and test checklist.

## License

Copyright 2026 Duy Chu. Licensed under [Apache License 2.0](LICENSE). See [NOTICE](NOTICE).
