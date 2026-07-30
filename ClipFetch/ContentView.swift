import SwiftUI

struct ContentView: View {
    @State private var sourceURL = ""
    @State private var pendingInspection: URL?

    private let mint = Color(red: 0.20, green: 0.65, blue: 0.49)

    var body: some View {
        Group {
            if let pendingInspection {
                inspectionRequested(for: pendingInspection)
            } else {
                urlEntry
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

    private func inspectionRequested(for url: URL) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Inspection requested")
                    .font(.largeTitle.weight(.bold))
                Text("Media Details will appear here once Bundled yt-dlp is connected.")
                    .foregroundStyle(.secondary)
            }

            GroupBox {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Ready to inspect", systemImage: "magnifyingglass")
                        .font(.headline)
                    Text(url.absoluteString)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(8)
            }

            Button("Change URL") {
                pendingInspection = nil
            }
        }
    }

    private func requestInspection() {
        pendingInspection = SourceURL.parse(sourceURL)
    }
}
