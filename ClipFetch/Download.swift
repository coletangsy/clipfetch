import Combine
import Foundation

@MainActor
protocol DownloadClient {
    func inspect(_ sourceURL: URL) async throws -> MediaDetails
    func download(
        _ sourceURL: URL,
        quality: QualityOption,
        onProgress: @escaping @Sendable (DownloadStatus) -> Void
    ) async throws -> URL
    func cancel()
}

@MainActor
struct BundledYTDLPDownloadClient: DownloadClient {
    private let inspector = YTDLPInspector()
    private let downloader = YTDLPDownloader()

    func inspect(_ sourceURL: URL) async throws -> MediaDetails {
        try await inspector.inspect(sourceURL)
    }

    func download(
        _ sourceURL: URL,
        quality: QualityOption,
        onProgress: @escaping @Sendable (DownloadStatus) -> Void
    ) async throws -> URL {
        try await downloader.download(sourceURL, quality: quality, onProgress: onProgress)
    }

    func cancel() {
        downloader.cancel()
    }
}

@MainActor
final class Download: ObservableObject {
    enum State: Equatable {
        case urlEntry
        case inspecting
        case details(MediaDetails)
        case downloading(MediaDetails, QualityOption, DownloadStatus?)
        case completed(URL)
        case failed(message: String, diagnostics: String?)
    }

    private enum RetryAction {
        case inspection
        case download(MediaDetails, URL, QualityOption)
    }

    private enum CancellationDestination {
        case details(MediaDetails)
        case urlEntry
    }

    @Published private(set) var sourceURL = ""
    @Published private(set) var selectedQuality = QualityOption.best
    @Published private(set) var state = State.urlEntry

    var canInspect: Bool {
        !operation.isActive && SourceURL.parse(sourceURL) != nil
    }

    private let client: any DownloadClient
    private let operation: ActiveOperation
    private var activeRequest = UUID()
    private var retryAction: RetryAction?
    private var cancellationDestination: CancellationDestination?

    convenience init() {
        self.init(client: BundledYTDLPDownloadClient(), operation: ActiveOperation())
    }

    convenience init(client: any DownloadClient) {
        self.init(client: client, operation: ActiveOperation())
    }

    init(client: any DownloadClient, operation: ActiveOperation) {
        self.client = client
        self.operation = operation
    }

    convenience init(operation: ActiveOperation) {
        self.init(client: BundledYTDLPDownloadClient(), operation: operation)
    }

    func updateSourceURL(_ value: String) {
        guard sourceURL != value,
              !(operation.isActive && isInspecting) else { return }

        let isCancelling = requestActiveDownloadCancellation()
        sourceURL = value
        selectedQuality = .best
        if !isCancelling {
            state = .urlEntry
        }
    }

    func showSourceURLEntry() {
        guard !isInspecting else { return }
        if !requestActiveDownloadCancellation() {
            state = .urlEntry
        }
    }

    func selectQuality(_ quality: QualityOption) {
        guard case let .details(details) = state,
              details.qualityOptions.contains(quality) else {
            return
        }

        selectedQuality = quality
    }

    func inspect() async {
        guard canInspect,
              !isInspectingOrDownloading,
              let sourceURL = SourceURL.parse(sourceURL),
              operation.acquire() else {
            return
        }

        let request = beginRequest()
        selectedQuality = .best
        state = .inspecting

        do {
            let details = try await client.inspect(sourceURL)
            guard request == activeRequest else {
                operation.release()
                return
            }
            state = .details(details)
            operation.release()
        } catch {
            guard request == activeRequest else {
                operation.release()
                return
            }
            let failure = inspectionFailure(for: error)
            retryAction = .inspection
            state = .failed(message: failure.message, diagnostics: failure.diagnostics)
            operation.release()
        }
    }

    func startDownload() async {
        guard case let .details(details) = state,
              details.qualityOptions.contains(selectedQuality),
              let sourceURL = SourceURL.parse(sourceURL) else {
            return
        }

        await download(details, from: sourceURL, quality: selectedQuality)
    }

    func retry() async {
        guard let retryAction else { return }

        switch retryAction {
        case .inspection:
            await inspect()
        case let .download(details, sourceURL, quality):
            await download(details, from: sourceURL, quality: quality)
        }
    }

    func cancel() {
        guard case let .downloading(details, _, _) = state,
              cancellationDestination == nil else {
            return
        }

        retryAction = nil
        cancellationDestination = .details(details)
        client.cancel()
    }

    private var isInspectingOrDownloading: Bool {
        switch state {
        case .inspecting, .downloading:
            true
        default:
            false
        }
    }

    private var isInspecting: Bool {
        if case .inspecting = state { return true }
        return false
    }

    private func beginRequest() -> UUID {
        let request = UUID()
        activeRequest = request
        retryAction = nil
        cancellationDestination = nil
        return request
    }

    private func requestActiveDownloadCancellation() -> Bool {
        guard case .downloading = state else {
            activeRequest = UUID()
            retryAction = nil
            cancellationDestination = nil
            return false
        }

        guard cancellationDestination == nil else { return true }

        retryAction = nil
        cancellationDestination = .urlEntry
        client.cancel()
        return true
    }

    private func download(_ details: MediaDetails, from sourceURL: URL, quality: QualityOption) async {
        guard operation.acquire() else { return }

        let request = beginRequest()
        state = .downloading(details, quality, nil)

        do {
            let fileURL = try await client.download(sourceURL, quality: quality) { [weak self] status in
                Task { @MainActor [weak self] in
                    self?.receive(status, for: request)
                }
            }
            guard request == activeRequest else {
                operation.release()
                return
            }
            if finishCancellationIfNeeded() {
                operation.release()
                return
            }
            state = .completed(fileURL)
            operation.release()
        } catch {
            guard request == activeRequest else {
                operation.release()
                return
            }
            if finishCancellationIfNeeded() {
                operation.release()
                return
            }
            let failure = downloadFailure(for: error)
            retryAction = failure.requiresInspection
                ? .inspection
                : .download(details, sourceURL, quality)
            state = .failed(message: failure.message, diagnostics: failure.diagnostics)
            operation.release()
        }
    }

    private func receive(_ status: DownloadStatus, for request: UUID) {
        guard request == activeRequest,
              cancellationDestination == nil,
              case let .downloading(details, quality, _) = state else {
            return
        }

        state = .downloading(details, quality, status)
    }

    private func finishCancellationIfNeeded() -> Bool {
        guard let cancellationDestination else { return false }

        self.cancellationDestination = nil
        switch cancellationDestination {
        case let .details(details):
            state = .details(details)
        case .urlEntry:
            state = .urlEntry
        }
        return true
    }

    private func inspectionFailure(for error: Error) -> (message: String, diagnostics: String?) {
        guard let error = error as? YTDLPInspector.InspectionError else {
            return ("ClipFetch couldn’t inspect this Source URL. Try again.", error.localizedDescription)
        }

        return (
            error.errorDescription ?? "ClipFetch couldn’t inspect this Source URL.",
            error.diagnostics
        )
    }

    private func downloadFailure(for error: Error) -> (message: String, diagnostics: String?, requiresInspection: Bool) {
        guard let error = error as? YTDLPDownloader.DownloadError else {
            return ("ClipFetch couldn’t download this Source URL. Try again.", error.localizedDescription, false)
        }

        return (
            error.errorDescription ?? "ClipFetch couldn’t download this Source URL.",
            error.diagnostics,
            error.requiresInspection
        )
    }
}
