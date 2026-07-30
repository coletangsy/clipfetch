# ClipFetch

ClipFetch is a personal macOS learning project for downloading video through a graphical interface backed by yt-dlp.

## Language

**Personal Learning App**:
A locally run macOS application built to learn the native app-development workflow, not a product intended for public distribution.
_Avoid_: Product, public app

**Native App**:
The SwiftUI macOS application that provides ClipFetch's interface and invokes yt-dlp through the operating system.
_Avoid_: Web wrapper, Electron app

**Bundled yt-dlp**:
The yt-dlp executable shipped inside the Native App and run locally by it.
_Avoid_: Homebrew dependency, system yt-dlp

**Bundled ffmpeg**:
The ffmpeg executable shipped inside the Native App so yt-dlp can merge separate video and audio streams into a Best MP4.
_Avoid_: System ffmpeg, Homebrew dependency

**Bundled Tool Update**:
A development-time replacement of the yt-dlp and ffmpeg executables in the Native App; ClipFetch has no in-app updater.
_Avoid_: Automatic update, background update

**Download**:
One user-requested yt-dlp operation, from a submitted video URL until it succeeds, fails, or is cancelled. ClipFetch permits one active Download at a time.
_Avoid_: Job, task, queue item

**Download Folder**:
The user's standard `~/Downloads` directory, where ClipFetch saves completed Downloads.
_Avoid_: App bundle, app-internal storage

**Source URL**:
A valid URL submitted by the user for a Download; it may be any source supported by Bundled yt-dlp.
_Avoid_: YouTube URL, supported-site URL

**Anonymous Source URL**:
A Source URL ClipFetch can inspect and download without any account credentials or browser cookies.
_Avoid_: Signed-in source, private URL

**Best MP4**:
The highest-quality MP4 video with audio available for a Source URL, selected when the user chooses the Best Quality Option.
_Avoid_: Format preset

**Quality Option**:
Either Best or an actual video resolution available for a Source URL. ClipFetch shows Quality Options after Inspection and defaults to Best. It displays Best first, then each available resolution once, highest to lowest. If individual resolutions are unavailable, Best is the only Quality Option. A Quality Option controls video resolution only; Bundled yt-dlp selects compatible audio and produces an MP4. If a selected resolution becomes unavailable before Download, the Download fails rather than choosing a different Quality Option.
_Avoid_: Audio-quality setting, fixed quality tier, unavailable resolution

**Media Details**:
The title, thumbnail, duration, estimated size, actual resolution of the Best MP4, and available Quality Options shown after ClipFetch inspects a Source URL.
_Avoid_: Format selector

**Inspection**:
The pre-download yt-dlp operation that resolves an Anonymous Source URL into Media Details and its available Quality Options.
_Avoid_: Download

**Cancelled Download**:
A Download stopped by the user before completion; its yt-dlp process is terminated and its incomplete output is removed.
_Avoid_: Paused download, resumable download

**Download Status**:
The live transfer percentage, transfer speed, and estimated time remaining shown while a Download is active. It reaches 100% before Bundled yt-dlp may finish merging and saving the MP4.
_Avoid_: Raw yt-dlp log, download console

**Download Error**:
A failed inspection or Download shown with a plain-language explanation, Retry action, and optional copyable diagnostics.
_Avoid_: Visible log console, opaque failure

**Completed Download**:
A successful Download confirmed with its saved filename and a Reveal in Finder action.
_Avoid_: Download-history item, silent completion
