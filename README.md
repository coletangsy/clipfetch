# ClipFetch

ClipFetch is a personal macOS learning project for downloading video through a native interface backed by bundled yt-dlp and ffmpeg.

## Install

For v1, open `dist/ClipFetch-v1-unsigned.dmg`, drag ClipFetch to Applications, then right-click and choose Open the first time. For later releases, use the unsigned `.pkg` in the GitHub release to install or upgrade ClipFetch in `/Applications`; Installer updates the existing app instead of requiring a manual removal. The `.dmg` remains available for drag-and-drop installation. The app supports macOS 26 or later on Apple-silicon and Intel Macs.

Downloads are saved to `~/Downloads`. ClipFetch works with anonymous source URLs; sources that need sign-in or browser cookies are unsupported.

## Swift learning guide

Open `lessons/0001-build-a-macos-app-with-swift.html` in a browser for an interactive introduction to Swift and native macOS app development using ClipFetch. The page has English and Traditional Chinese modes, uses `assets/lesson.css`, and needs no build step.

## Release artifact

The distributable v1 DMG lives in `dist/`. New releases include both an unsigned DMG and an unsigned PKG; the PKG is the recommended upgrade path. The app is ad-hoc signed but the containers are not notarized, so they are for local sharing rather than public distribution.

## Releases

In GitHub's Release UI, create a `v<version>` tag targeting `main`, then publish the release. The release workflow tests and builds the universal app, then uploads matching unsigned DMG and PKG installers; no separate tag push is needed.
