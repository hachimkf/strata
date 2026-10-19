# Strata

A small native macOS app that finds every version of your design files — renamed copies, `(Recovered)` files after a crash, exports in Downloads — and shows each project as a timeline from first to latest.

Strata only **reads** files. It never moves, renames or deletes anything.

## Build & run

No Xcode needed — Command Line Tools are enough.

```bash
Scripts/build-app.sh --open
```

The app lands in `build/Strata.app`. On first launch macOS asks for access to Desktop, Documents and Downloads.

Other tools:

```bash
swift run strata-selftest          # 16 checks for the grouping engine
swift run -c release strata-scan   # print what Strata finds on this Mac (add --all for every project)
```

## How files are grouped

| Signal | Example |
| --- | --- |
| Same Adobe **DocumentID** | `logo.ai` and `logo (Recovered).ai` |
| Same Adobe **OriginalDocumentID** (Save As family) | `atlas_v2.ai` → `atlas_final.ai` |
| **DerivedFrom** (export → source) | `export-01.png` from `atlas_final.ai` |
| Same name after cleanup | `Atlas Logo final final (Recovered) 2.ai` = `atlas_logo_FINAL_v2.ai` |
| Identical bytes | `promo.mp4` and `promo (1).mp4` → flagged as duplicate |

Guards learned from real folders:
- Adobe IDs only link files whose **names agree** — designers often Save As last month's file to start a new job.
- Generic names (`Untitled-1`, `Screenshot…`, `IMG_1234`, `ChatGPT Image…`) never form projects on their own.
- A file name repeated across many folders (`01_Product/photos/room.jpg`, `02_Product/photos/room.jpg`) is a naming convention; those are split by their parent folder name.

## Layout

- `Sources/StrataCore` — scanner (FSEvents watcher, XMP reader, metadata cache) and the grouping engine. No UI.
- `Sources/Strata` — SwiftUI app: project grid, version timeline, inspector, menu bar panel.
- `Sources/strata-scan`, `Sources/strata-selftest` — command-line tools.

Note: the macOS 27 SDK turns `@State` into a macro that only ships with Xcode, so views use `@ViewState` (a typealias of the same property wrapper, in `Support.swift`).
