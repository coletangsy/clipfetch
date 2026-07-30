import Foundation

struct YTDLPInspector: Sendable {
    enum InspectionError: LocalizedError, Sendable {
        case bundledToolUnavailable
        case commandFailed(String)
        case invalidOutput(String)

        var errorDescription: String? {
            switch self {
            case .bundledToolUnavailable:
                "Bundled yt-dlp is unavailable. Reinstall ClipFetch and try again."
            case .commandFailed:
                "ClipFetch couldn’t inspect this Source URL. Check that it is publicly available and try again."
            case .invalidOutput:
                "ClipFetch received an unexpected response while inspecting this Source URL. Try again."
            }
        }

        var diagnostics: String? {
            switch self {
            case .bundledToolUnavailable:
                nil
            case .commandFailed(let diagnostics), .invalidOutput(let diagnostics):
                diagnostics.isEmpty ? nil : diagnostics
            }
        }
    }

    func inspect(_ sourceURL: URL) async throws -> MediaDetails {
        try await Task.detached(priority: .userInitiated) {
            try Self.inspectSynchronously(sourceURL)
        }.value
    }

    private static func inspectSynchronously(_ sourceURL: URL) throws -> MediaDetails {
        guard let executableURL = Bundle.main.url(forResource: "yt-dlp", withExtension: nil) else {
            throw InspectionError.bundledToolUnavailable
        }

        let output = Pipe()
        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "--ignore-config",
            "--no-playlist",
            "--skip-download",
            "--quiet",
            "--dump-single-json",
            "--format", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]",
            sourceURL.absoluteString,
        ]
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
        } catch {
            throw InspectionError.commandFailed(error.localizedDescription)
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw InspectionError.commandFailed(String(decoding: data, as: UTF8.self))
        }

        do {
            return try MediaDetails.decode(data)
        } catch {
            throw InspectionError.invalidOutput(error.localizedDescription)
        }
    }
}
