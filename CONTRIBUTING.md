# Contributing to Strata

Thanks for helping improve Strata. Issues and pull requests are welcome.

## Start here

For a bug, include your macOS version, Strata version, expected result, actual result, and minimal reproduction steps. For grouping bugs, use synthetic filenames and the relevant folder structure. Do not upload client documents, private paths, signing credentials, or unredacted scanner output.

For a larger feature or design change, open an issue first so we can agree on the workflow and scope. Small fixes and documentation improvements can go straight to a pull request.

## Local workflow

Use macOS with a Swift 6 toolchain. Fork and clone the repository, then create a branch for your change.

```bash
swift run strata-selftest
Scripts/build-app.sh --open
```

Keep changes focused and explain the problem, resulting behavior, and validation in your PR. Add a small regression check in `Sources/strata-selftest/Checks.swift` for grouping or scanner behavior. For UI changes, include before/after screenshots and verify keyboard navigation, long filenames, and light/dark appearance as appropriate.

`Sources/StrataCore` contains scanning, metadata, and grouping. `Sources/Strata` contains the macOS interface. Avoid adding dependencies when the platform already provides the needed functionality. Do not commit `.build`, `build`, app bundles, local libraries, or personal settings.

## File safety

Preserve original files and make destructive actions explicit. Manual grouping corrections must take priority over automatic inference. Validate with temporary fixtures, not someone else's creative library.

## Releases

Publishing scripts are for maintainers with repository access and local signing credentials. Contributors do not need certificates to build: the build script falls back to ad-hoc signing. Use `Scripts/release.sh current "" --local` to prepare local release artifacts without pushing.

By contributing, you agree that your contributions are provided under the project's MIT license. Artwork shown in screenshots is not a reusable asset library.
