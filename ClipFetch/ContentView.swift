import Foundation
import SwiftUI

struct ContentView: View {
    @State private var sourceURL = ""
    @State private var inspectionState = InspectionState.urlEntry

    private let mint = Color(red: 0.20, green: 0.65, blue: 0.49)

    var body: some View {
        Group {
            switch inspectionState {
            case .urlEntry:
                urlEntry
            case .inspecting:
                inspectionInProgress
            case .details(let details):
                mediaDetails(for: details)
            case .failed(let message, let diagnostics):
                inspectionFailed(message: message, diagnostics: diagnostics)
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
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            Button("Change URL") {
                inspectionState = .urlEntry
            }
        }
    }

    private func inspectionFailed(message: String, diagnostics: String?) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Download Error")
                    .font(.largeTitle.weight(.bold))
                Text(message)
                    .foregroundStyle(.secondary)
            }

            if let diagnostics {
                DisclosureGroup("Show diagnostics") {
                    Text(diagnostics)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .padding(.top, 8)
                }
            }

            HStack {
                Button("Change URL") {
                    inspectionState = .urlEntry
                }
                Button("Retry", action: requestInspection)
                    .buttonStyle(.borderedProminent)
                    .tint(mint)
            }
        }
    }

    private func requestInspection() {
        guard let url = SourceURL.parse(sourceURL) else { return }

        inspectionState = .inspecting

        Task {
            do {
                inspectionState = .details(try await YTDLPInspector().inspect(url))
            } catch let error as YTDLPInspector.InspectionError {
                inspectionState = .failed(
                    message: error.errorDescription ?? "ClipFetch couldn’t inspect this Source URL.",
                    diagnostics: error.diagnostics
                )
            } catch {
                inspectionState = .failed(
                    message: "ClipFetch couldn’t inspect this Source URL. Try again.",
                    diagnostics: error.localizedDescription
                )
            }
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
}

private enum InspectionState {
    case urlEntry
    case inspecting
    case details(MediaDetails)
    case failed(message: String, diagnostics: String?)
}
