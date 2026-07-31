import Foundation
import XCTest
@testable import ClipFetch

@MainActor
final class DownloadTests: XCTestCase {
    func testInspectionShowsMediaDetailsAndDefaultsToBestQuality() async throws {
        let details = mediaDetails(qualities: [.best, .resolution(width: 1280, height: 720)])
        let client = DownloadTestClient(inspectionResults: [.success(details), .success(details)])
        let download = Download(client: client)
        download.updateSourceURL("https://example.com/first")
        await download.inspect()
        download.selectQuality(.resolution(width: 1280, height: 720))
        download.updateSourceURL("https://example.com/video")

        await download.inspect()

        XCTAssertEqual(download.state, .details(details))
        XCTAssertEqual(download.selectedQuality, .best)
        XCTAssertEqual(client.inspectionCount, 2)
    }

    func testInvalidSourceURLIsUnavailableForInspection() async {
        let client = DownloadTestClient(inspectionResults: [])
        let download = Download(client: client)
        download.updateSourceURL("example.com/video")

        await download.inspect()

        XCTAssertFalse(download.canInspect)
        XCTAssertEqual(download.state, .urlEntry)
        XCTAssertEqual(client.inspectionCount, 0)
    }

    func testCompletesDownloadAndRetainsSavedFile() async throws {
        let details = mediaDetails()
        let fileURL = URL(fileURLWithPath: "/Downloads/public-clip.mp4")
        let client = DownloadTestClient(
            inspectionResults: [.success(details)],
            downloadOutcomes: [.result(.success(fileURL))]
        )
        let download = Download(client: client)
        download.updateSourceURL("https://example.com/video")

        await download.inspect()
        await download.startDownload()

        XCTAssertEqual(download.state, .completed(fileURL))
        XCTAssertEqual(client.downloadCount, 1)
    }

    func testReportsDownloadStatus() async throws {
        let details = mediaDetails()
        let client = DownloadTestClient(
            inspectionResults: [.success(details)],
            downloadOutcomes: [.pending]
        )
        let download = Download(client: client)
        download.updateSourceURL("https://example.com/video")
        await download.inspect()

        let downloadTask = Task { await download.startDownload() }
        await waitForPendingDownload(in: client)
        let status = DownloadStatus(percentage: "42.0%", speed: "1.0MiB/s", eta: "00:10")
        client.send(status, forDownload: 0)
        await waitForState(.downloading(details, .best, status), in: download)
        client.finishDownload(0, with: .success(URL(fileURLWithPath: "/Downloads/public-clip.mp4")))
        await downloadTask.value
    }

    func testCancellationReturnsToInspectedMediaDetails() async throws {
        let details = mediaDetails()
        let client = DownloadTestClient(
            inspectionResults: [.success(details)],
            downloadOutcomes: [.pending]
        )
        let download = Download(client: client)
        download.updateSourceURL("https://example.com/video")
        await download.inspect()

        let downloadTask = Task { await download.startDownload() }
        await waitForPendingDownload(in: client)
        download.cancel()
        await downloadTask.value

        XCTAssertEqual(download.state, .details(details))
        XCTAssertEqual(client.cancelCount, 1)
    }

    func testCancellationPreventsAnotherDownloadUntilTheFirstHasStopped() async throws {
        let details = mediaDetails()
        let client = DownloadTestClient(
            inspectionResults: [.success(details)],
            downloadOutcomes: [
                .pending,
                .result(.success(URL(fileURLWithPath: "/Downloads/public-clip.mp4"))),
            ]
        )
        let download = Download(client: client)
        download.updateSourceURL("https://example.com/video")
        await download.inspect()

        let firstDownload = Task { await download.startDownload() }
        await waitForPendingDownload(in: client)
        download.cancel()
        await download.startDownload()

        XCTAssertEqual(client.downloadCount, 1)
        await firstDownload.value
        XCTAssertEqual(download.state, .details(details))
    }

    func testInspectionFailureRetriesInspection() async throws {
        let details = mediaDetails()
        let client = DownloadTestClient(inspectionResults: [
            .failure(YTDLPInspector.InspectionError.commandFailed("not public")),
            .success(details),
        ])
        let download = Download(client: client)
        download.updateSourceURL("https://example.com/video")

        await download.inspect()

        XCTAssertEqual(
            download.state,
            .failed(
                message: "ClipFetch couldn’t inspect this Source URL. Check that it is publicly available and try again.",
                diagnostics: "not public"
            )
        )
        await download.retry()
        XCTAssertEqual(download.state, .details(details))
        XCTAssertEqual(client.inspectionCount, 2)
    }

    func testDownloadFailureRetriesDownload() async throws {
        let details = mediaDetails()
        let fileURL = URL(fileURLWithPath: "/Downloads/public-clip.mp4")
        let client = DownloadTestClient(
            inspectionResults: [.success(details)],
            downloadOutcomes: [
                .result(.failure(YTDLPDownloader.DownloadError.commandFailed("network failed"))),
                .result(.success(fileURL)),
            ]
        )
        let download = Download(client: client)
        download.updateSourceURL("https://example.com/video")
        await download.inspect()

        await download.startDownload()

        XCTAssertEqual(
            download.state,
            .failed(
                message: "ClipFetch couldn’t download this Source URL. Check that it is publicly available and try again.",
                diagnostics: "network failed"
            )
        )
        await download.retry()
        XCTAssertEqual(download.state, .completed(fileURL))
        XCTAssertEqual(client.inspectionCount, 1)
        XCTAssertEqual(client.downloadCount, 2)
    }

    func testUnavailableQualityRetriesInspection() async throws {
        let quality = QualityOption.resolution(width: 1280, height: 720)
        let details = mediaDetails(qualities: [.best, quality])
        let client = DownloadTestClient(
            inspectionResults: [.success(details), .success(details)],
            downloadOutcomes: [
                .result(.failure(YTDLPDownloader.DownloadError.selectedQualityUnavailable("format unavailable"))),
            ]
        )
        let download = Download(client: client)
        download.updateSourceURL("https://example.com/video")
        await download.inspect()
        download.selectQuality(quality)

        await download.startDownload()
        await download.retry()

        XCTAssertEqual(download.state, .details(details))
        XCTAssertEqual(download.selectedQuality, .best)
        XCTAssertEqual(client.inspectionCount, 2)
        XCTAssertEqual(client.downloadCount, 1)
    }

    func testIgnoresStaleDownloadStatus() async throws {
        let details = mediaDetails()
        let client = DownloadTestClient(
            inspectionResults: [.success(details)],
            downloadOutcomes: [.pending, .pending]
        )
        let download = Download(client: client)
        download.updateSourceURL("https://example.com/video")
        await download.inspect()

        let firstDownload = Task { await download.startDownload() }
        await waitForPendingDownload(in: client)
        download.cancel()
        await firstDownload.value

        let secondDownload = Task { await download.startDownload() }
        await waitForPendingDownload(in: client)
        let current = DownloadStatus(percentage: "10.0%", speed: "1.0MiB/s", eta: "00:10")
        client.send(current, forDownload: 1)
        await waitForState(.downloading(details, .best, current), in: download)
        client.send(DownloadStatus(percentage: "90.0%", speed: "9.0MiB/s", eta: "00:01"), forDownload: 0)
        await Task.yield()

        XCTAssertEqual(download.state, .downloading(details, .best, current))
        client.finishDownload(1, with: .success(URL(fileURLWithPath: "/Downloads/public-clip.mp4")))
        await secondDownload.value
    }

    func testPermitsOnlyOneActiveDownload() async throws {
        let details = mediaDetails()
        let client = DownloadTestClient(
            inspectionResults: [.success(details)],
            downloadOutcomes: [.pending]
        )
        let download = Download(client: client)
        download.updateSourceURL("https://example.com/video")
        await download.inspect()

        let firstDownload = Task { await download.startDownload() }
        await waitForPendingDownload(in: client)
        await download.startDownload()

        XCTAssertEqual(client.downloadCount, 1)
        download.cancel()
        await firstDownload.value
    }

    private func mediaDetails(qualities: [QualityOption] = [.best]) -> MediaDetails {
        MediaDetails(
            title: "Public clip",
            thumbnailURL: nil,
            duration: 60,
            estimatedSize: 1_000,
            width: 1920,
            height: 1080,
            qualityOptions: qualities
        )
    }

    private func waitForPendingDownload(in client: DownloadTestClient) async {
        for _ in 0..<100 where client.pendingDownloadCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(client.pendingDownloadCount, 1)
    }

    private func waitForState(_ expected: Download.State, in download: Download) async {
        for _ in 0..<100 where download.state != expected {
            await Task.yield()
        }
        XCTAssertEqual(download.state, expected)
    }
}

@MainActor
private final class DownloadTestClient: DownloadClient {
    enum DownloadOutcome {
        case result(Result<URL, Error>)
        case pending
    }

    private var inspectionResults: [Result<MediaDetails, Error>]
    private var downloadOutcomes: [DownloadOutcome]
    private var progressHandlers: [@Sendable (DownloadStatus) -> Void] = []
    private var pendingDownloads: [Int: CheckedContinuation<URL, Error>] = [:]
    private(set) var inspectionCount = 0
    private(set) var downloadCount = 0
    private(set) var cancelCount = 0
    var pendingDownloadCount: Int { pendingDownloads.count }

    init(
        inspectionResults: [Result<MediaDetails, Error>],
        downloadOutcomes: [DownloadOutcome] = []
    ) {
        self.inspectionResults = inspectionResults
        self.downloadOutcomes = downloadOutcomes
    }

    func inspect(_ sourceURL: URL) async throws -> MediaDetails {
        inspectionCount += 1
        return try inspectionResults.removeFirst().get()
    }

    func download(
        _ sourceURL: URL,
        quality: QualityOption,
        onProgress: @escaping @Sendable (DownloadStatus) -> Void
    ) async throws -> URL {
        downloadCount += 1
        progressHandlers.append(onProgress)

        switch downloadOutcomes.removeFirst() {
        case .result(let result):
            return try result.get()
        case .pending:
            let index = downloadCount - 1
            return try await withCheckedThrowingContinuation { continuation in
                pendingDownloads[index] = continuation
            }
        }
    }

    func cancel() {
        cancelCount += 1
        let downloads = pendingDownloads.values
        pendingDownloads.removeAll()
        for download in downloads {
            download.resume(throwing: CancellationError())
        }
    }

    func send(_ status: DownloadStatus, forDownload index: Int) {
        progressHandlers[index](status)
    }

    func finishDownload(_ index: Int, with result: Result<URL, Error>) {
        pendingDownloads.removeValue(forKey: index)?.resume(with: result)
    }
}
