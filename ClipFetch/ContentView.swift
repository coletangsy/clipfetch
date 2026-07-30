import AppKit
import Foundation
import SwiftUI

func copyDiagnostics(_ diagnostics: String, to pasteboard: NSPasteboard = .general) {
    pasteboard.clearContents()
    pasteboard.setString(diagnostics, forType: .string)
}

struct ContentView: View {
    @State private var sourceURL = ""
    @State private var viewState = ViewState.urlEntry
    @State private var downloader = YTDLPDownloader()
    @State private var downloadWasCancelled = false
    @State private var selectedQuality = QualityOption.best

    private let mint = Color(red: 0.20, green: 0.65, blue: 0.49)

    var body: some View {
        Group {
            switch viewState {
            case .urlEntry:
                urlEntry
            case .inspecting:
                inspectionInProgress
            case .details(let details):
                mediaDetails(for: details)
            case .downloading(let details, let quality, let status):
                downloadInProgress(for: details, quality: quality, status: status)
            case .completed(let fileURL):
                downloadCompleted(fileURL: fileURL)
            case .failed(let message, let diagnostics, let details):
                downloadFailed(message: message, diagnostics: diagnostics, details: details)
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

                    TextField("https://example.com/video", text: $sourceURL)
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
                            .disabled(SourceURL.parse(sourceURL) == nil)
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
                        Picker("Quality", selection: $selectedQuality) {
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
                    viewState = .urlEntry
                }
                Button("Download \(selectedQuality.displayName) MP4") {
                    requestDownload(details, quality: selectedQuality)
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
                    viewState = .urlEntry
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
        diagnostics: String?,
        details: MediaDetails?
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
                    viewState = .urlEntry
                }
                if let diagnostics {
                    Button("Copy diagnostics") {
                        copyDiagnostics(diagnostics)
                    }
                }
                Button("Retry") {
                    if let details {
                        requestDownload(details, quality: selectedQuality)
                    } else {
                        requestInspection()
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .tint(mint)
            }
        }
    }

    private func requestInspection() {
        guard let url = SourceURL.parse(sourceURL) else { return }

        selectedQuality = .best
        viewState = .inspecting

        Task {
            do {
                viewState = .details(try await YTDLPInspector().inspect(url))
            } catch let error as YTDLPInspector.InspectionError {
                viewState = .failed(
                    message: error.errorDescription ?? "ClipFetch couldn’t inspect this Source URL.",
                    diagnostics: error.diagnostics,
                    details: nil
                )
            } catch {
                viewState = .failed(
                    message: "ClipFetch couldn’t inspect this Source URL. Try again.",
                    diagnostics: error.localizedDescription,
                    details: nil
                )
            }
        }
    }

    private func requestDownload(_ details: MediaDetails, quality: QualityOption) {
        guard let url = SourceURL.parse(sourceURL) else { return }

        downloadWasCancelled = false
        viewState = .downloading(details, quality: quality, status: nil)

        Task {
            do {
                let fileURL = try await downloader.download(url, quality: quality) { status in
                    Task { @MainActor in
                        guard case .downloading(let details, let quality, _) = viewState else { return }
                        viewState = .downloading(details, quality: quality, status: status)
                    }
                }
                guard !downloadWasCancelled else { return }
                viewState = .completed(fileURL)
            } catch {
                if downloadWasCancelled {
                    viewState = .details(details)
                } else {
                    let downloadError = error as? YTDLPDownloader.DownloadError
                    viewState = .failed(
                        message: downloadError?.errorDescription ?? "ClipFetch couldn’t download this Source URL. Try again.",
                        diagnostics: downloadError?.diagnostics ?? error.localizedDescription,
                        details: downloadError?.requiresInspection == true ? nil : details
                    )
                }
            }
        }
    }

    private func cancelDownload() {
        downloadWasCancelled = true
        downloader.cancel()
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

private enum ViewState {
    case urlEntry
    case inspecting
    case details(MediaDetails)
    case downloading(MediaDetails, quality: QualityOption, status: DownloadStatus?)
    case completed(URL)
    case failed(message: String, diagnostics: String?, details: MediaDetails?)
}
