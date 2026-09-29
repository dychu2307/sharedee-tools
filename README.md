# Sharedee Tools

[Tiếng Việt](README.vi.md)

Sharedee Tools is a free, native macOS menu bar app for capturing and annotating screenshots. The source code is available under the [Apache License 2.0](LICENSE).

## Features

- Capture a selected area, a window, the full screen, or scrolling content.
- Copy a capture directly, or use the floating thumbnail to choose Copy, Edit, or Save.
- Annotate with arrows, rectangles, ellipses, freehand strokes, highlights, text, blur, and solid covers.
- Crop, undo and redo, save PNG, and pin an image above other windows.
- Configure global keyboard shortcuts, capture delay, automatic clipboard copy, and scrolling capture length.
- Recognize text in a captured image using the macOS Vision framework.

Sharedee Tools does not record video or upload captures to a cloud service.

## Requirements

- macOS 12 or newer on Intel (`x86_64`) or Apple Silicon (`arm64`).
- Xcode to build from source. The checked-in Xcode project can be opened directly; [XcodeGen](https://github.com/yonaskolb/XcodeGen) is needed only after editing `project.yml`.
- macOS Screen Recording permission for captures. Scrolling capture also needs Accessibility permission.

The app and its tests have been built on macOS 27 with Xcode 26.6. The Intel executable was also launched through Rosetta. An older physical Intel Mac has not been tested yet.

## Build from source

```sh
git clone https://github.com/dychu2307/sharedee-tools.git
cd sharedee-tools
open SharedeCapture.xcodeproj
```

In Xcode, select the `SharedeCapture` scheme and run it. The built app is named **Sharedee Tools**. To build and test from the command line:

```sh
xcodebuild -project SharedeCapture.xcodeproj -scheme SharedeCapture \
  -destination 'generic/platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project SharedeCapture.xcodeproj -scheme SharedeCapture \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test
```

If you edit `project.yml`, run `xcodegen generate` before opening or building the project.

## Usage

Launch the app and use its menu bar icon. A small thumbnail appears after a capture; choose **Copy**, **Edit**, or **Save**. The editor opens only when requested. Use **Settings** in the menu bar to change shortcuts and capture options.

For scrolling capture, bring the target window forward and scroll to the start of its content before capturing. Dynamic pages may not stitch perfectly.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the build and test checklist.

## License

Copyright 2026 Duy Chu. Licensed under [Apache License 2.0](LICENSE). See [NOTICE](NOTICE).
