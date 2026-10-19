# Strata

A small native macOS app that finds every version of your design files — renamed copies, `(Recovered)` files after a crash, exports in Downloads — and shows each project as a timeline from first to latest.

Strata reads your files and never moves, renames or edits them on its own. The only changes it makes are ones you ask for: a status saved as a Finder tag, or duplicates moved to the Trash after you confirm. It works offline; the only network call is a daily update check you can turn off.

## What it does

- **Your work** — clients (Norvia, Velora…) as folders, each with its projects and version timelines.
- **Timeline** — drag, scroll, pinch / ⌘-scroll to zoom, ← → between versions, Replay plays the history.
- **Compare** — side by side, slider, overlay or difference between any two versions.
- **Corrections** — move a file to another project (drag it onto the sidebar), rename, merge, hide; saved in `~/Library/Application Support/Strata/corrections.json` and always win over the automatic grouping.
- **Status & notes** — Draft → Final saved as Finder tags; a note per version.
- **Brand kit** — each client's colours (from artwork), fonts (from Adobe files) and logo files.
- **Delivery** — zip the latest version + exports of a project or a whole client.
- **Tidy up** — exact duplicates and old crash copies, moved to the Trash only after you confirm.
- **Find anything** — ⌘K in the app; a floating Spotlight-style search from any app (default ⇧⌘Space, set your own in Settings); crash alerts when a "(Recovered)" file appears.
- **Settings** — light / dark / system, accent colour, artwork colours, reduce motion, folders, hidden clients.

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

## Clients (collections)

Projects and stray files are then gathered into clients — "Norvia", "Velora", "Solara":

- **Client folder**: the first meaningfully named folder under a watched root (`~/Documents/Velora Coffee`). A project spread over two clients' folders counts for the one holding most of its files.
- **Brand word**: a made-up or foreign word that starts names in several places (`Norvia …`, `Velora …`). Ordinary English words (`left`, `grid`) never count; spelling variants sharing 6 letters merge (`Solarastudio` = `Solara`); a folder named after a brand joins it.
- **Adobe family**: only adopts files with no client of their own — designers start one client's file from another's.

`swift run -c release strata-scan --collections` prints the clients found. `STRATA_EDGES=/tmp/edges.tsv` logs every link for debugging.

## Layout

- `Sources/StrataCore` — scanner (FSEvents watcher, XMP reader, metadata cache) and the grouping engine. No UI.
- `Sources/Strata` — SwiftUI app: project grid, version timeline, inspector, menu bar panel.
- `Sources/strata-scan`, `Sources/strata-selftest` — command-line tools.

Note: the macOS 27 SDK turns `@State` into a macro that only ships with Xcode, so views use `@ViewState` (a typealias of the same property wrapper, in `Support.swift`).

## Releasing

```bash
Scripts/release.sh patch "What changed"     # or minor / major / 1.2.3 / current
Scripts/release.sh current "" --local       # build the signed DMG only, publish nothing
```

The script bumps the version, runs the self-checks, builds a universal app (Apple Silicon + Intel) with the
hardened runtime, makes `build/Strata-<version>.dmg` plus a `.sha256`, then commits, tags and publishes a GitHub
release on `hachimkf/strata-releases`. The app checks that repo once a day and verifies the checksum before
opening an update.

Notarization (so other Macs open it without a warning) needs a **Developer ID Application** certificate from the
Apple Developer Program, plus a stored notary profile:

```bash
xcrun notarytool store-credentials strata --apple-id YOU@EXAMPLE.COM --team-id TEAMID
```

Then run releases with `STRATA_NOTARY_PROFILE=strata`. Without it, builds are signed ad-hoc and first launch on
another Mac needs right-click › Open.

App icon: put new artwork in `Resources/AppIcon-source.png` and run `Scripts/make-icon.sh`.
