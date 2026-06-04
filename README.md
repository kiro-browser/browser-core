# BuildBrowser

A high-performance, native macOS web browser built with **Cocoa** + **WebKit**.

BuildBrowser is designed to be lightweight and deeply integrated into the macOS ecosystem, offering a clean interface and robust feature set without the overhead of heavy cross-platform frameworks.

## Features

- **WebKit-Powered Rendering**: Utilizes the native Apple WebKit engine for fast and secure web browsing.
- **Tab Management**: Advanced multi-tab support with reordering and fluid transitions.
- **Integrated Sidebar**: Quick access to bookmarks and history via a native side panel.
- **Download Management**: Dedicated panel to track and manage files.
- **Bookmarks & History**: robust local storage for your frequent sites and navigation history.
- **Customizable Settings**: Native macOS settings panel for fine-grained configuration.
- **Deep macOS Integration**: Follows system themes (Light/Dark mode) and utilizes native AppKit components.

## Requirements

- **macOS**: 12.0 (Monterey) or later.
- **CMake**: 3.16 or later.
- **Xcode Command Line Tools**: Required for compilation.

## Build & Run

Ensure you have CMake installed, then run the convenience script:

```bash
chmod +x build.sh
./build.sh
```

To run the application:

```bash
open build/BuildBrowser.app
```

## Generate an Installer

Build an installable macOS package:

```bash
chmod +x package.sh
./package.sh
```

The generated installer is written to `dist/BuildBrowser-<version>-<build>.pkg`.
Opening that package installs `BuildBrowser.app` into `/Applications` and
registers it with macOS so it appears in Launchpad and application search.
To build and install in one command:

```bash
./package.sh --install
```

The same command also writes `dist/BuildBrowser-<version>-<build>.app.zip`,
which can be used by the built-in updater manifest as the app bundle archive.

To generate the auto-updater manifest at the same time, pass the public URL
where the `dist` files will be hosted:

```bash
./package.sh --base-url=https://example.com/buildbrowser
```

Upload these files from `dist/` to that URL:

- `manifest.json`
- `BuildBrowser-<version>-<build>.app.zip`

Then set Settings -> Updates -> Manifest URL to:

```text
https://example.com/buildbrowser/manifest.json
```

### Git-Backed Updates

If you want the git repo to host the updater manifest and archive, use:

```bash
./package.sh --git-updates
```

For this repo, that writes:

```text
updates/manifest.json
updates/BuildBrowser-<version>-<build>.app.zip
```

Commit and push those files. Then set Settings -> Updates -> Manifest URL to:

```text
https://raw.githubusercontent.com/kiro-browser/browser-core/dev/updates/manifest.json
```

The manifest points the app at the matching zip in the same `updates/`
directory on the `dev` branch. This GitHub raw manifest is the app's default
update feed. If you publish updates from a different branch,
pass it explicitly:

```bash
./package.sh --git-updates --branch=main
```

## Project Structure

```
browser/
├── CMakeLists.txt              # Build system definition
├── build.sh                    # Build orchestration script
├── include/                    # Header files (.h)
│   ├── AppDelegate.h
│   ├── BrowserWindowController.h
│   ├── TabManager.h
│   └── ...
└── src/                        # Implementation files (.mm)
    ├── main.mm                 # App entry point
    ├── AppDelegate.mm          # App lifecycle management
    ├── BrowserWindowController.mm # Main window logic
    ├── TabManager.mm           # Tabs & Navigation logic
    └── ...
```

## Tech Stack

- **Languge**: Objective-C++ (C++17)
- **Frameworks**: Foundation, AppKit (Cocoa), WebKit
- **Build System**: CMake 3.16+
- **Memory Management**: Automatic Reference Counting (ARC)

## Note for Developers
This project has transitioned from a GTK-based Linux implementation to a native macOS Cocoa application. The previous GTK source files (`src/main.cpp`, `src/browser_window.cpp`) are deprecated and are not included in the primary macOS build.
