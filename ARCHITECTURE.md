# ClipFetch architecture

ClipFetch is a native Swift/macOS application that provides a small interface
around local media download and comment or live-chat export. The repository
ships the app source, tests, an interactive learning lesson, and unsigned local
release artifacts.

## Components and flow

```text
source URL
   ↓
SourceURL / MediaDetails
   ↓
YTDLPDownloader → bundled yt-dlp + ffmpeg
   ↓
ContentView and Download state
   ↓
local Downloads folder

downloaded metadata/transcript → CommentExport
                             → text / translated text output
```

- `ClipFetch/` contains the SwiftUI application and focused helpers for URL
  parsing, media inspection, downloading, and export.
- `ClipFetchTests/` covers these helpers and UI-facing behavior without making
  network access part of the test contract.
- `ClipFetch/Resources/` contains the bundled command-line tools used by the
  downloader; keep their licensing and update process aligned with releases.
- `lessons/` and `assets/` are the bilingual learning material, not runtime
  application code.
- `dist/` contains unsigned local installers; the GitHub release workflow builds
  the matching artifacts from a tag on `main`.

The app supports anonymous source URLs. Sign-in and browser-cookie flows are
outside the supported trust boundary. Downloaded files belong in the user's
Downloads directory, while release packaging remains separate from source and
tests.

## Maintenance

Update this document when the app's download/export boundary, bundled tool
contract, supported platform, or release workflow changes. Keep teaching details
in the lesson and update `CHANGELOG.md` for user-visible changes.
