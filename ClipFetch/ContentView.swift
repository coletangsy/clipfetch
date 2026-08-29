import AppKit
import Foundation
import SwiftUI

func copyDiagnostics(_ diagnostics: String, to pasteboard: NSPasteboard = .general) {
    pasteboard.clearContents()
    pasteboard.setString(diagnostics, forType: .string)
}

@MainActor
struct ContentView: View {
    @StateObject private var operation: ActiveOperation
    @StateObject private var download: Download
    @StateObject private var export: CommentExport
    @State private var sourceURL = ""
    @State private var mode = ClipFetchMode.videoDownload

    private let mint = Color(red: 0.20, green: 0.65, blue: 0.49)

    init() {
        let operation = ActiveOperation()
        _operation = StateObject(wrappedValue: operation)
        _download = StateObject(wrappedValue: Download(operation: operation))
        _export = StateObject(wrappedValue: CommentExport(operation: operation))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Picker("Mode", selection: $mode) {
                ForEach(ClipFetchMode.allCases) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .disabled(operation.isActive)

            Group {
                switch mode {
                case .videoDownload:
                    downloadContent
                case .commentsAndLiveChat:
                    exportContent
                }
            }
        }
        .frame(width: 560)
        .padding(32)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var downloadContent: some View {
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
    }

    private var exportContent: some View {
        Group {
            switch export.state {
            case .urlEntry:
                exportEntry
            case let .exporting(progress):
                exportInProgress(progress)
            case let .completed(result):
                exportCompleted(result)
            case let .failed(message, diagnostics, canRetryTranslation, result):
                exportFailed(message: message, diagnostics: diagnostics, canRetryTranslation: canRetryTranslation, result: result)
            case let .cancelled(result):
                exportCancelled(result)
            }
        }
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
                        text: Binding(get: { sourceURL }, set: updateSourceURL)
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

    private var exportEntry: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Comments & Live Chat")
                    .font(.largeTitle.weight(.bold))
                Text("Export one YouTube Author’s entries from a finite discussion source.")
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Discussion Source")
                        .font(.headline)

                    Text("Source URL")
                    TextField(
                        "https://www.youtube.com/watch?v=video",
                        text: Binding(get: { sourceURL }, set: updateSourceURL)
                    )
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("YouTube Source URL")
                        .onSubmit(requestExport)

                    Picker(
                        "Source",
                        selection: Binding(get: { export.discussionSource }, set: export.selectDiscussionSource)
                    ) {
                        ForEach(DiscussionSource.allCases) { source in
                            Text(source.title).tag(source)
                        }
                    }

                    Text("YouTube Author")
                    TextField(
                        "@handle or UC… channel ID",
                        text: Binding(get: { export.author }, set: export.updateAuthor)
                    )
                        .textFieldStyle(.roundedBorder)
                        .accessibilityLabel("YouTube Author")

                    Toggle(
                        "Create Translated Entries",
                        isOn: Binding(get: { export.translate }, set: export.setTranslate)
                    )
                    Text("Translation uses OpenRouter credits and produces Taiwanese Traditional Chinese. Manage the API key in Settings.")
                        .font(.callout)
                        .foregroundStyle(.secondary)

                    if let validationMessage = export.validationMessage {
                        Text(validationMessage)
                            .foregroundStyle(.red)
                            .accessibilityAddTraits(.isStaticText)
                    }

                    HStack {
                        Spacer()
                        Button("Export") {
                            requestExport()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(mint)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!export.canStart)
                    }
                }
                .padding(8)
            }
        }
    }

    private func exportInProgress(_ progress: CommentExportProgress) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text(exportStageTitle(progress.stage))
                    .font(.largeTitle.weight(.bold))
                Text("ClipFetch is keeping the Original Entries safe while this operation runs.")
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    if case let .translating(completed, total) = progress.stage {
                        ProgressView(value: Double(completed), total: Double(max(total, 1)))
                        LabeledContent("Translation", value: "\(completed) of \(total)")
                    } else {
                        ProgressView()
                    }
                    if let matchedCount = progress.matchedCount {
                        LabeledContent("Entries", value: "\(matchedCount)")
                    }
                }
                .padding(8)
            }

            Button("Cancel", action: cancelExport)
                .disabled({ if case .cancelling = progress.stage { return true }; return false }())
        }
    }

    private func exportCompleted(_ result: CommentExportResult) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Export Complete")
                    .font(.largeTitle.weight(.bold))
                Text("\(result.entryCount) entries saved")
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    Text(result.originalURL.lastPathComponent)
                    if let translatedURL = result.translatedURL {
                        Text(translatedURL.lastPathComponent)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            HStack {
                Button("Change URL") { export.showSourceURLEntry() }
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([result.folderURL])
                }
                .buttonStyle(.borderedProminent)
                .tint(mint)
            }
        }
    }

    private func exportFailed(
        message: String,
        diagnostics: String?,
        canRetryTranslation: Bool,
        result: CommentExportResult?
    ) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Export Error")
                    .font(.largeTitle.weight(.bold))
                Text(message)
                    .foregroundStyle(.secondary)
                if let result {
                    Text("Original Entries: \(result.originalURL.lastPathComponent)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Button("Change URL") { export.showSourceURLEntry() }
                if let diagnostics {
                    Button("Copy diagnostics") { copyDiagnostics(diagnostics) }
                }
                if canRetryTranslation {
                    Button("Retry Translation") { requestRetryTranslation() }
                        .buttonStyle(.borderedProminent)
                        .tint(mint)
                } else {
                    Button("Retry") { requestExportRetry() }
                        .buttonStyle(.borderedProminent)
                        .tint(mint)
                }
            }
        }
    }

    private func exportCancelled(_ result: CommentExportResult?) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Export Cancelled")
                    .font(.largeTitle.weight(.bold))
                Text(result.map { "Original Entries kept at \($0.originalURL.lastPathComponent)." } ?? "Temporary data was removed.")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Change URL") { export.showSourceURLEntry() }
                if let result {
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([result.folderURL])
                    }
                }
                Button("Start Again") { export.showSourceURLEntry() }
                    .buttonStyle(.borderedProminent)
                    .tint(mint)
            }
        }
    }

    private func requestInspection() {
        Task { await download.inspect() }
    }

    private func updateSourceURL(_ value: String) {
        sourceURL = value
        download.updateSourceURL(value)
        export.updateSourceURL(value)
    }

    private func requestDownload() {
        Task { await download.startDownload() }
    }

    private func requestExport() {
        Task { await export.start() }
    }

    private func requestExportRetry() {
        Task { await export.retry() }
    }

    private func requestRetryTranslation() {
        Task { await export.retryTranslation() }
    }

    private func cancelDownload() {
        download.cancel()
    }

    private func cancelExport() {
        export.cancel()
    }

    private func exportStageTitle(_ stage: CommentExportStage) -> String {
        switch stage {
        case .fetching:
            "Fetching Discussion Source"
        case .filtering:
            "Filtering YouTube Author"
        case .translating:
            "Translating Entries"
        case .saving:
            "Saving Export"
        case .cancelling:
            "Cancelling Export"
        }
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

@MainActor
struct SettingsView: View {
    private let store: any CredentialStore
    @State private var apiKey: String
    @State private var message: String?

    init(store: any CredentialStore = KeychainCredentialStore()) {
        self.store = store
        _apiKey = State(initialValue: store.value() ?? "")
    }

    var body: some View {
        Form {
            Section("OpenRouter") {
                SecureField("API key", text: $apiKey)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("OpenRouter API key")
                Text("The key is stored in macOS Keychain and is only used when translation is enabled.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                HStack {
                    Button("Save") { save() }
                    Button("Remove") { remove() }
                }
            }
            if let message {
                Text(message)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(24)
        .frame(width: 420)
    }

    private func save() {
        let value = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else {
            message = "Enter an OpenRouter API key."
            return
        }
        do {
            try store.save(value)
            apiKey = value
            message = "OpenRouter API key saved."
        } catch {
            message = error.localizedDescription
        }
    }

    private func remove() {
        do {
            try store.remove()
            apiKey = ""
            message = "OpenRouter API key removed."
        } catch {
            message = error.localizedDescription
        }
    }
}
