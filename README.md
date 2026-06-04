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
Opening that package installs `BuildBrowser.app` into `/Applications`.
To build and install in one command:

```bash
./package.sh --install
```

The same command also writes `dist/BuildBrowser-<version>-<build>.app.zip`,
which can be used by the built-in updater manifest as the app bundle archive.

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
