import Foundation

struct YTDLPInspector: Sendable {
    private let executableURL: URL?

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

    init(executableURL: URL? = Bundle.main.url(forResource: "yt-dlp", withExtension: nil)) {
        self.executableURL = executableURL
    }

    func inspect(_ sourceURL: URL) async throws -> MediaDetails {
        let bundledExecutableURL = executableURL

        try await Task.detached(priority: .userInitiated) {
            try Self.inspectSynchronously(sourceURL, executableURL: bundledExecutableURL)
        }.value
    }

    private static func inspectSynchronously(_ sourceURL: URL, executableURL: URL?) throws -> MediaDetails {
        guard let executableURL else {
            throw InspectionError.bundledToolUnavailable
        }

        let standardOutput = Pipe()
        let diagnosticsURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        guard FileManager.default.createFile(atPath: diagnosticsURL.path, contents: nil) else {
            throw InspectionError.commandFailed("ClipFetch couldn’t prepare diagnostics.")
        }
        defer { try? FileManager.default.removeItem(at: diagnosticsURL) }

        let standardError: FileHandle
        do {
            standardError = try FileHandle(forWritingTo: diagnosticsURL)
        } catch {
            throw InspectionError.commandFailed(error.localizedDescription)
        }
        defer { try? standardError.close() }

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
        process.standardOutput = standardOutput
        process.standardError = standardError

        do {
            try process.run()
        } catch {
            throw InspectionError.commandFailed(error.localizedDescription)
        }

        let output = standardOutput.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        try? standardError.close()
        let diagnostics = (try? Data(contentsOf: diagnosticsURL)) ?? Data()

        return try inspectionResult(
            output: output,
            diagnostics: diagnostics,
            terminationStatus: process.terminationStatus
        )
    }

    static func inspectionResult(
        output: Data,
        diagnostics: Data,
        terminationStatus: Int32
    ) throws -> MediaDetails {
        guard terminationStatus == 0 else {
            throw InspectionError.commandFailed(String(decoding: diagnostics, as: UTF8.self))
        }

        do {
            return try MediaDetails.decode(output)
        } catch {
            throw InspectionError.invalidOutput(error.localizedDescription)
        }
    }
}
