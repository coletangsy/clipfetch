import AppKit
import Foundation
import SwiftUI

func copyDiagnostics(_ diagnostics: String, to pasteboard: NSPasteboard = .general) {
    pasteboard.clearContents()
    pasteboard.setString(diagnostics, forType: .string)
}

struct ContentView: View {
    @StateObject private var download = Download()

    private let mint = Color(red: 0.20, green: 0.65, blue: 0.49)

    var body: some View {
        Group {
            switch download.state {
            case .urlEntry:
                urlEntry
            case .inspecting:
                inspectionInProgress
            case let .details(details):
                mediaDetails(for: details)
            case let .downloading(details, quality, status):
                downloadInProgress(for: details, quality: quality, status: status)
            case let .completed(fileURL):
                downloadCompleted(fileURL: fileURL)
            case let .failed(message, diagnostics):
                downloadFailed(message: message, diagnostics: diagnostics)
            }
        }
        .frame(width: 560)
        .padding(32)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var urlEntry: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("ClipFetch")
                    .font(.largeTitle.weight(.bold))
                Text("Inspect an Anonymous Source URL before downloading it.")
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Source URL")
                        .font(.headline)

                    TextField(
                        "https://example.com/video",
                        text: Binding(get: { download.sourceURL }, set: download.updateSourceURL)
                    )
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("Source URL")
                        .onSubmit(requestInspection)

                    HStack {
                        Text("Paste an Anonymous Source URL.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Inspect", action: requestInspection)
                            .buttonStyle(.borderedProminent)
                            .tint(mint)
                            .keyboardShortcut(.defaultAction)
                            .disabled(!download.canInspect)
                    }
                }
                .padding(8)
            }
        }
    }

    private var inspectionInProgress: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Inspecting Source URL")
                    .font(.largeTitle.weight(.bold))
                Text("ClipFetch is selecting the Best MP4 with Bundled yt-dlp.")
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                ProgressView("Inspecting…")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
        }
    }

    private func mediaDetails(for details: MediaDetails) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Media Details")
                    .font(.largeTitle.weight(.bold))
                Text("Best MP4 selected")
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                HStack(alignment: .top, spacing: 16) {
                    thumbnail(for: details.thumbnailURL)

                    VStack(alignment: .leading, spacing: 10) {
                        Text(details.title)
                            .font(.title2.weight(.semibold))
                        LabeledContent("Duration", value: durationText(for: details.duration))
                        LabeledContent("Estimated size", value: sizeText(for: details.estimatedSize))
                        LabeledContent("Resolution", value: details.resolution)
                        Picker(
                            "Quality",
                            selection: Binding(
                                get: { download.selectedQuality },
                                set: download.selectQuality
                            )
                        ) {
                            ForEach(details.qualityOptions, id: \.self) { quality in
                                Text(quality.displayName).tag(quality)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            HStack {
                Button("Change URL") {
                    download.showSourceURLEntry()
                }
                Button("Download \(download.selectedQuality.displayName) MP4") {
                    requestDownload()
                }
                .buttonStyle(.borderedProminent)
                .tint(mint)
            }
        }
    }

    private func downloadInProgress(
        for details: MediaDetails,
        quality: QualityOption,
        status: DownloadStatus?
    ) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Downloading \(quality.displayName) MP4")
                    .font(.largeTitle.weight(.bold))
                Text(details.title)
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    ProgressView(value: percentage(for: status?.percentage))
                    LabeledContent("Progress", value: status?.percentage ?? "Preparing…")
                    LabeledContent("Transfer speed", value: status?.speed ?? "—")
                    LabeledContent("Time remaining", value: status?.eta ?? "—")
                }
                .padding(8)
            }

            Button("Cancel", action: cancelDownload)
        }
    }

    private func downloadCompleted(fileURL: URL) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Download Complete")
                    .font(.largeTitle.weight(.bold))
                Text(fileURL.lastPathComponent)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Change URL") {
                    download.showSourceURLEntry()
                }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
                .buttonStyle(.borderedProminent)
                .tint(mint)
            }
        }
    }

    private func downloadFailed(
        message: String,
        diagnostics: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Download Error")
                    .font(.largeTitle.weight(.bold))
                Text(message)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Change URL") {
                    download.showSourceURLEntry()
                }
                if let diagnostics {
                    Button("Copy diagnostics") {
                        copyDiagnostics(diagnostics)
                    }
                }
                Button("Retry") {
                    Task { await download.retry() }
                }
                    .buttonStyle(.borderedProminent)
                    .tint(mint)
            }
        }
    }

    private func requestInspection() {
        Task { await download.inspect() }
    }

    private func requestDownload() {
        Task { await download.startDownload() }
    }

    private func cancelDownload() {
        download.cancel()
    }

    @ViewBuilder
    private func thumbnail(for url: URL?) -> some View {
        if let url {
            AsyncImage(url: url) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                ProgressView()
            }
            .frame(width: 160, height: 90)
            .clipShape(.rect(cornerRadius: 6))
        } else {
            Image(systemName: "photo")
                .font(.largeTitle)
                .frame(width: 160, height: 90)
                .background(.quaternary, in: .rect(cornerRadius: 6))
        }
    }

    private func durationText(for duration: TimeInterval?) -> String {
        guard let duration else { return "Unknown" }
        let totalSeconds = Int(duration.rounded())
        return String(format: "%d:%02d", totalSeconds / 60, totalSeconds % 60)
    }

    private func sizeText(for size: Int64?) -> String {
        guard let size else { return "Unknown" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func percentage(for value: String?) -> Double? {
        guard let value else { return nil }
        return Double(value.replacing("%", with: "")).map { $0 / 100 }
    }
}
