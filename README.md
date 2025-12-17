# IDM for Mac (SwiftUI, SwiftData, Async/Await)

Modern, minimalist download manager for macOS 14+ that mirrors IDM’s core capabilities—multi-part HTTP range downloads with resume—wrapped in an Apple-native SwiftUI interface.

## Features
- Multi-part downloads (4–8 segments) via HTTP `Range` headers; sequential merge on completion.
- Automatic single-stream fallback when servers don’t support ranges.
- Resume support with per-chunk metadata persisted via SwiftData.
- Clipboard monitoring toggle to auto-capture URLs.
- Automatic category tagging (documents, images, audio, video, archives).
- Minimal UI: hidden title bar, translucent sidebar, circular progress ring with pause/resume, smooth insert animations.
- Dark mode support.

## Requirements
- macOS 14 Sonoma or later
- Xcode 15 or later

## Project Structure
- `Package.swift` – SwiftPM manifest targeting macOS 14.
- `Sources/IDMMacApp/Models` – `DownloadItem`, chunk state, categories.
- `Sources/IDMMacApp/Engine` – `DownloadEngine` actor handling head probe, range splitting, concurrent chunk download, single-stream fallback, merge.
- `Sources/IDMMacApp/ViewModels` – `DownloadViewModel` (MVVM bridge, filters, clipboard monitor, start/pause/resume).
- `Sources/IDMMacApp/Views` – SwiftUI views (Content, Sidebar, Row).
- `Sources/IDMMacApp/IDMMacApp.swift` – App entrypoint.

## Running (Xcode)
1) Open `Package.swift` in Xcode 15+.
2) Select the `IDMMacApp` scheme targeting “My Mac”.
3) Run (⌘R).

## Usage Tips
- Add URLs via the “+” button; clipboard monitor can auto-add copied URLs.
- Range downloads rely on server `Accept-Ranges: bytes`; if absent, the engine falls back to a single-stream download.
- Segment count is clamped (max 8) and scaled to avoid tiny chunks on small/slow files (min 2 MB per chunk).

## Notes
- No third-party dependencies; pure URLSession, SwiftData, SwiftUI.
- If you see permission or cache errors when building via CLI, open in Xcode where toolchain caches are managed automatically.
