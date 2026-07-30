import Foundation
import XCTest
@testable import ClipFetch

final class YTDLPDownloaderTests: XCTestCase {
    func testMovesCompletedBestMP4ToDownloadsAndReportsProgress() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let toolURL = directory.appendingPathComponent("yt-dlp")
        try """
        #!/bin/sh
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--output" ]; then
            output="$2"
            break
          fi
          shift
        done
        printf 'download:42.0%%|'
        sleep 1
        printf '1.0MiB/s|00:10\\n'
        touch "${output%/*}/public-clip.mp4"
        """.write(to: toolURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: toolURL.path)

        let progress = expectation(description: "download progress")
        let downloadsURL = directory.appendingPathComponent("Downloads", isDirectory: true)
        let downloadedFile = try await YTDLPDownloader(
            executableURL: toolURL,
            ffmpegURL: toolURL,
            downloadsURL: downloadsURL
        ).download(URL(string: "https://example.com/video")!) { status in
            if status.percentage == "42.0%", status.speed == "1.0MiB/s", status.eta == "00:10" {
                progress.fulfill()
            }
        }

        await fulfillment(of: [progress], timeout: 1)
        XCTAssertEqual(downloadedFile.lastPathComponent, "public-clip.mp4")
        XCTAssertTrue(FileManager.default.fileExists(atPath: downloadedFile.path))
    }

    func testCancellationRemovesIncompleteOutput() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let toolURL = directory.appendingPathComponent("yt-dlp")
        let outputDirectoryPathURL = directory.appendingPathComponent("output-directory.txt")
        try """
        #!/bin/sh
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--output" ]; then
            output="$2"
            break
          fi
          shift
        done
        touch "${output%/*}/partial.mp4.part"
        printf '%s' "${output%/*}" > "\(outputDirectoryPathURL.path)"
        printf 'download:1.0%%|1.0MiB/s|01:00\\n'
        sleep 30
        """.write(to: toolURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: toolURL.path)

        let downloadStarted = expectation(description: "download started")
        let downloader = YTDLPDownloader(
            executableURL: toolURL,
            ffmpegURL: toolURL,
            downloadsURL: directory.appendingPathComponent("Downloads", isDirectory: true)
        )
        let download = Task {
            try await downloader.download(URL(string: "https://example.com/video")!) { _ in
                downloadStarted.fulfill()
            }
        }

        await fulfillment(of: [downloadStarted], timeout: 1)
        downloader.cancel()

        do {
            _ = try await download.value
            XCTFail("Expected cancelled download to fail")
        } catch {
            let outputDirectory = URL(fileURLWithPath: try XCTUnwrap(String(data: Data(contentsOf: outputDirectoryPathURL), encoding: .utf8)))
            XCTAssertFalse(FileManager.default.fileExists(atPath: outputDirectory.path))
        }
    }

    func testEarlyCancellationPreventsYTDLPFromLaunching() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let launchedURL = directory.appendingPathComponent("launched")
        let toolURL = directory.appendingPathComponent("yt-dlp")
        try """
        #!/bin/sh
        touch "\(launchedURL.path)"
        sleep 1
        """.write(to: toolURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: toolURL.path)

        let downloader = YTDLPDownloader(
            executableURL: toolURL,
            ffmpegURL: toolURL,
            downloadsURL: directory.appendingPathComponent("Downloads", isDirectory: true)
        )
        downloader.cancel()

        do {
            _ = try await downloader.download(URL(string: "https://example.com/video")!) { _ in }
            XCTFail("Expected cancelled download to fail")
        } catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: launchedURL.path))
        }
    }
}
