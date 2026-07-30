import Foundation

struct DownloadStatus: Equatable, Sendable {
    let percentage: String
    let speed: String
    let eta: String
}

struct YTDLPDownloader: Sendable {
    private let executableURL: URL?
    private let ffmpegURL: URL?
    private let downloadsURL: URL
    private let processBox = ProcessBox()

    enum DownloadError: LocalizedError, Sendable {
        case bundledToolUnavailable
        case commandFailed(String)
        case missingOutput
        case saveFailed(String)

        var errorDescription: String? {
            switch self {
            case .bundledToolUnavailable:
                "Bundled yt-dlp or ffmpeg is unavailable. Reinstall ClipFetch and try again."
            case .commandFailed:
                "ClipFetch couldn’t download this Source URL. Check that it is publicly available and try again."
            case .missingOutput:
                "ClipFetch couldn’t find the completed Best MP4. Try again."
            case .saveFailed:
                "ClipFetch couldn’t save the Best MP4 to Downloads. Check the folder and try again."
            }
        }

        var diagnostics: String? {
            switch self {
            case .bundledToolUnavailable, .missingOutput:
                nil
            case .commandFailed(let diagnostics), .saveFailed(let diagnostics):
                diagnostics.isEmpty ? nil : diagnostics
            }
        }
    }

    init(
        executableURL: URL? = Bundle.main.url(forResource: "yt-dlp", withExtension: nil),
        ffmpegURL: URL? = Bundle.main.url(forResource: "ffmpeg", withExtension: nil),
        downloadsURL: URL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    ) {
        self.executableURL = executableURL
        self.ffmpegURL = ffmpegURL
        self.downloadsURL = downloadsURL
    }

    func download(
        _ sourceURL: URL,
        onProgress: @escaping @Sendable (DownloadStatus) -> Void
    ) async throws -> URL {
        let executableURL = executableURL
        let ffmpegURL = ffmpegURL
        let downloadsURL = downloadsURL

        return try await withTaskCancellationHandler {
            try await Task.detached(priority: .userInitiated) {
                try Self.downloadSynchronously(
                    sourceURL,
                    executableURL: executableURL,
                    ffmpegURL: ffmpegURL,
                    downloadsURL: downloadsURL,
                    processBox: processBox,
                    onProgress: onProgress
                )
            }.value
        } onCancel: {
            processBox.terminate()
        }
    }

    func cancel() {
        processBox.terminate()
    }

    private static func downloadSynchronously(
        _ sourceURL: URL,
        executableURL: URL?,
        ffmpegURL: URL?,
        downloadsURL: URL,
        processBox: ProcessBox,
        onProgress: @escaping @Sendable (DownloadStatus) -> Void
    ) throws -> URL {
        defer { processBox.clear() }

        guard let executableURL, let ffmpegURL else {
            throw DownloadError.bundledToolUnavailable
        }

        let fileManager = FileManager.default
        let outputDirectory = fileManager.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: outputDirectory) }

        let diagnosticsURL = outputDirectory.appendingPathComponent("diagnostics.txt")
        guard fileManager.createFile(atPath: diagnosticsURL.path, contents: nil) else {
            throw DownloadError.commandFailed("ClipFetch couldn’t prepare diagnostics.")
        }
        let standardError: FileHandle
        do {
            standardError = try FileHandle(forWritingTo: diagnosticsURL)
        } catch {
            throw DownloadError.commandFailed(error.localizedDescription)
        }
        defer { try? standardError.close() }

        var pendingProgressOutput = ""
        let standardOutput = Pipe()
        standardOutput.fileHandleForReading.readabilityHandler = { handle in
            let output = handle.availableData
            guard !output.isEmpty else { return }

            pendingProgressOutput += String(decoding: output, as: UTF8.self)
            let lines = pendingProgressOutput.split(
                omittingEmptySubsequences: false,
                whereSeparator: \ .isNewline
            )
            pendingProgressOutput = String(lines.last ?? "")

            for line in lines.dropLast() {
                if let status = status(from: String(line)) {
                    onProgress(status)
                }
            }
        }

        let process = Process()
        process.executableURL = executableURL
        process.arguments = [
            "--ignore-config",
            "--no-playlist",
            "--newline",
            "--format", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]",
            "--merge-output-format", "mp4",
            "--ffmpeg-location", ffmpegURL.deletingLastPathComponent().path,
            "--progress-template", "download:%(progress._percent_str)s|%(progress._speed_str)s|%(progress._eta_str)s",
            "--output", outputDirectory.appendingPathComponent("%(title)s.%(ext)s").path,
            sourceURL.absoluteString,
        ]
        process.standardOutput = standardOutput
        process.standardError = standardError
        guard processBox.set(process) else {
            throw CancellationError()
        }

        do {
            try process.run()
        } catch {
            throw DownloadError.commandFailed(error.localizedDescription)
        }
        processBox.terminateIfRequested(process)

        process.waitUntilExit()
        standardOutput.fileHandleForReading.readabilityHandler = nil
        let diagnostics = (try? Data(contentsOf: diagnosticsURL)) ?? Data()

        guard process.terminationStatus == 0 else {
            throw DownloadError.commandFailed(String(decoding: diagnostics, as: UTF8.self))
        }

        let files = try fileManager.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        guard let output = files.first(where: { $0.pathExtension.lowercased() == "mp4" }) else {
            throw DownloadError.missingOutput
        }

        do {
            try fileManager.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
            let destination = availableDestination(for: output, in: downloadsURL, fileManager: fileManager)
            try fileManager.moveItem(at: output, to: destination)
            return destination
        } catch {
            throw DownloadError.saveFailed(error.localizedDescription)
        }
    }

    private static func status(from line: String) -> DownloadStatus? {
        guard line.hasPrefix("download:") else { return nil }

        let values = line.dropFirst("download:".count)
            .split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard values.count == 3 else { return nil }

        return DownloadStatus(percentage: values[0], speed: values[1], eta: values[2])
    }

    private static func availableDestination(for output: URL, in downloadsURL: URL, fileManager: FileManager) -> URL {
        let fileExtension = output.pathExtension
        let filename = output.deletingPathExtension().lastPathComponent
        var suffix = 1
        var destination = downloadsURL.appendingPathComponent(output.lastPathComponent)

        while fileManager.fileExists(atPath: destination.path) {
            suffix += 1
            destination = downloadsURL.appendingPathComponent("\(filename) (\(suffix)).\(fileExtension)")
        }

        return destination
    }
}

private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var isCancellationRequested = false

    func set(_ process: Process) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        guard !isCancellationRequested else { return false }
        self.process = process
        return true
    }

    func clear() {
        lock.lock()
        process = nil
        isCancellationRequested = false
        lock.unlock()
    }

    func terminate() {
        lock.lock()
        isCancellationRequested = true
        let process = process
        lock.unlock()

        if process?.isRunning == true {
            process?.terminate()
        }
    }

    func terminateIfRequested(_ process: Process) {
        lock.lock()
        let isCancellationRequested = isCancellationRequested
        lock.unlock()

        if isCancellationRequested, process.isRunning {
            process.terminate()
        }
    }
}
