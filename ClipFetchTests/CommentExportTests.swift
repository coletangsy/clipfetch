import Foundation
import XCTest
@testable import ClipFetch

final class CommentExportParserTests: XCTestCase {
    func testParsesLiveChatTextAndEmojiAndFiltersExactAuthorChronologically() throws {
        let data = Data(
            """
            {"replayChatItemAction":{"actions":[{"addChatItemAction":{"item":{"liveChatTextMessageRenderer":{"id":"second","message":{"runs":[{"text":"later"}]},"authorName":{"simpleText":"@Target"},"authorExternalChannelId":"UCtarget"}}}}]},"videoOffsetTimeMsec":"2000"}
            {"replayChatItemAction":{"actions":[{"addChatItemAction":{"item":{"liveChatViewerEngagementMessageRenderer":{"message":{"runs":[{"text":"ignore"}]}}}}}]},"videoOffsetTimeMsec":"1500"}
            {"replayChatItemAction":{"actions":[{"addChatItemAction":{"item":{"liveChatTextMessageRenderer":{"id":"first","message":{"runs":[{"text":"Hi "},{"emoji":{"emojiId":"UCcustom/face-green-smiling","isCustomEmoji":true,"shortcuts":[":face-green-smiling:"]}},{"emoji":{"emojiId":"💔"}},{"text":"\\nnext"}]},"authorName":{"simpleText":"@TARGET"},"authorExternalChannelId":"UCtarget"}}}}]},"videoOffsetTimeMsec":"1000"}
            {"replayChatItemAction":{"actions":[{"addChatItemAction":{"item":{"liveChatTextMessageRenderer":{"id":"other","message":{"runs":[{"text":"other"}]},"authorName":{"simpleText":"@other"},"authorExternalChannelId":"UCother"}}}}]},"videoOffsetTimeMsec":"500"}
            """.utf8
        )

        let discussion = try CommentExportParser.parseLiveChat(data, title: "Video", videoID: "video")
        let entries = CommentExportParser.matchingEntries(in: discussion, for: try XCTUnwrap(YouTubeAuthor("@target")))

        XCTAssertEqual(entries.map(\.id), ["first", "second"])
        XCTAssertEqual(entries.first?.text, "Hi :face-green-smiling:💔\nnext")
        XCTAssertEqual(entries.first?.authorChannelID, "UCtarget")
    }

    func testIgnoresMissingLiveChatMessagePayload() {
        let data = Data(
            """
            {"replayChatItemAction":{"actions":[{"addChatItemAction":{"item":{"liveChatTextMessageRenderer":{"id":"missing-message","authorName":{"simpleText":"@target"}}}}}]},"videoOffsetTimeMsec":"1000"}
            """.utf8
        )

        XCTAssertNoThrow(try CommentExportParser.parseLiveChat(data, title: "Video", videoID: "video"))
    }

    func testParsesCommentsWithRepliesAndTranslationOnlyParentContext() throws {
        let data = Data(
            """
            {
              "title": "A video",
              "id": "abc123",
              "comments": [
                {"id":"reply","parent":"parent","text":"Reply\\nline","author":"@Target","author_id":"UCtarget","timestamp":200},
                {"id":"parent","text":"Parent only","author":"@other","author_id":"UCother","timestamp":100}
              ]
            }
            """.utf8
        )

        let discussion = try CommentExportParser.parseVideoComments(data)
        let entries = CommentExportParser.matchingEntries(in: discussion, for: try XCTUnwrap(YouTubeAuthor("@target")))

        XCTAssertEqual(discussion.entries.map(\.id), ["parent", "reply"])
        XCTAssertEqual(entries.map(\.id), ["reply"])
        XCTAssertEqual(entries.first?.parentText, "Parent only")
        XCTAssertEqual(entries.first?.text, "Reply\nline")
    }

    func testChannelIDMatchingIsExact() throws {
        let entries = [
            CommentEntry(id: "one", parentID: nil, authorHandle: "@target", authorChannelID: "UCtarget", text: "one", publishedAt: Date(), videoOffsetTimeMsec: nil, parentText: nil),
            CommentEntry(id: "two", parentID: nil, authorHandle: "@target2", authorChannelID: "UCtarget2", text: "two", publishedAt: Date(), videoOffsetTimeMsec: nil, parentText: nil),
        ]
        let discussion = FetchedDiscussion(title: "Video", videoID: "id", entries: entries)

        XCTAssertEqual(
            CommentExportParser.matchingEntries(in: discussion, for: try XCTUnwrap(YouTubeAuthor("UCtarget"))).map(\.id),
            ["one"]
        )
    }

    func testUsesHandleFromAuthorURLWhenAuthorIsDisplayName() throws {
        let data = Data(
            """
            {"title":"Video","id":"id","comments":[{"id":"one","text":"hello","author":"Target Display Name","author_url":"https://www.youtube.com/@Target","timestamp":100}]}
            """.utf8
        )

        let discussion = try CommentExportParser.parseVideoComments(data)
        let entries = CommentExportParser.matchingEntries(in: discussion, for: try XCTUnwrap(YouTubeAuthor("@target")))

        XCTAssertEqual(entries.map(\.id), ["one"])
        XCTAssertEqual(discussion.entries.first?.authorHandle, "@Target")
    }
}

final class CommentExportWriterTests: XCTestCase {
    func testWritesOriginalAndTranslatedEntriesWithoutParentOutput() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let entries = [
            CommentEntry(
                id: "reply",
                parentID: "parent",
                authorHandle: "@target",
                authorChannelID: "UCtarget",
                text: "Reply",
                publishedAt: Date(timeIntervalSince1970: 1_700_000_000),
                videoOffsetTimeMsec: nil,
                parentText: "Parent only"
            )
        ]
        let writer = CommentExportWriter(downloadsURL: directory)
        let original = try writer.saveOriginal(entries, source: .videoComments, title: "A/video", videoID: "abc", author: try XCTUnwrap(YouTubeAuthor("@target")))
        let result = try writer.saveTranslated(
            entries,
            source: .videoComments,
            author: try XCTUnwrap(YouTubeAuthor("@target")),
            translations: ["reply": "回覆"],
            alongside: original
        )

        XCTAssertEqual(original.folderURL.lastPathComponent, "Avideo [abc]")
        XCTAssertEqual(original.originalURL.lastPathComponent, "target.original.txt")
        XCTAssertEqual(result.translatedURL?.lastPathComponent, "target.zh-Hant.txt")
        XCTAssertTrue(try String(contentsOf: original.originalURL, encoding: .utf8).contains("Reply"))
        XCTAssertFalse(try String(contentsOf: original.originalURL, encoding: .utf8).contains("Parent only"))
        XCTAssertTrue(try String(contentsOf: try XCTUnwrap(result.translatedURL), encoding: .utf8).contains("回覆"))
    }

    func testUsesNumericFolderSuffixInsteadOfOverwriting() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let entry = CommentEntry(id: "one", parentID: nil, authorHandle: "@target", authorChannelID: nil, text: "one", publishedAt: Date(), videoOffsetTimeMsec: nil, parentText: nil)
        let writer = CommentExportWriter(downloadsURL: directory)
        let first = try writer.saveOriginal([entry], source: .videoComments, title: "Video", videoID: "abc", author: try XCTUnwrap(YouTubeAuthor("@target")))
        let second = try writer.saveOriginal([entry], source: .videoComments, title: "Video", videoID: "abc", author: try XCTUnwrap(YouTubeAuthor("@target")))

        XCTAssertEqual(first.folderURL.lastPathComponent, "Video [abc]")
        XCTAssertEqual(second.folderURL.lastPathComponent, "Video [abc] (2)")
    }
}

final class YTDLPCommentFetcherTests: XCTestCase {
    func testFetchesCommentsWithAllRepliesAndCleansTemporaryData() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let argumentsURL = directory.appendingPathComponent("arguments.txt")
        let toolURL = directory.appendingPathComponent("yt-dlp")
        try """
        #!/bin/sh
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--extractor-args" ]; then printf '%s' "$2" > "\(argumentsURL.path)"; fi
          shift
        done
        printf '%s' '{"title":"A video","id":"abc123","comments":[{"id":"comment","text":"hello","author":"@target","author_id":"UCtarget","timestamp":100}]}'
        """.write(to: toolURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: toolURL.path)

        let temporaryDirectory = directory.appendingPathComponent("temporary", isDirectory: true)
        let request = CommentExportRequest(sourceURL: URL(string: "https://www.youtube.com/watch?v=abc123")!, source: .videoComments, author: try XCTUnwrap(YouTubeAuthor("@target")), translate: false)
        let discussion = try await YTDLPCommentFetcher(executableURL: toolURL, temporaryDirectory: temporaryDirectory).fetch(request) { _ in }

        XCTAssertEqual(discussion.entries.map(\.id), ["comment"])
        XCTAssertEqual(try String(contentsOf: argumentsURL, encoding: .utf8), "youtube:comment_sort=new;max_comments=all,all,all,all,all")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(at: temporaryDirectory, includingPropertiesForKeys: nil).count, 0)
    }

    func testRejectsActiveLiveChatBeforeFetchingReplay() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let launchedURL = directory.appendingPathComponent("replay-launched")
        let toolURL = directory.appendingPathComponent("yt-dlp")
        try """
        #!/bin/sh
        for value in "$@"; do
          if [ "$value" = "--write-subs" ]; then touch "\(launchedURL.path)"; fi
        done
        printf '%s' '{"title":"Live","id":"live123","is_live":true,"live_status":"is_live"}'
        """.write(to: toolURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: toolURL.path)

        let request = CommentExportRequest(sourceURL: URL(string: "https://youtu.be/live123")!, source: .liveChatReplay, author: try XCTUnwrap(YouTubeAuthor("@target")), translate: false)
        do {
            _ = try await YTDLPCommentFetcher(executableURL: toolURL, temporaryDirectory: directory.appendingPathComponent("temporary", isDirectory: true)).fetch(request) { _ in }
            XCTFail("Expected active live chat to fail")
        } catch let error as CommentExportError {
            XCTAssertEqual(error, .activeLiveChat)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: launchedURL.path))
    }

    func testFetchesLiveChatReplayFromNDJSON() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let toolURL = directory.appendingPathComponent("yt-dlp")
        try """
        #!/bin/sh
        metadata=1
        output=""
        while [ "$#" -gt 0 ]; do
          if [ "$1" = "--write-subs" ]; then metadata=0; fi
          if [ "$1" = "--output" ]; then output="$2"; shift; fi
          shift
        done
        if [ "$metadata" -eq 1 ]; then
          printf '%s' '{"title":"Replay","id":"replay123","is_live":false,"live_status":"was_live"}'
        else
          printf '%s\\n' '{"replayChatItemAction":{"actions":[{"addChatItemAction":{"item":{"liveChatTextMessageRenderer":{"id":"one","message":{"runs":[{"text":"hello"}]},"authorName":{"simpleText":"@target"},"authorExternalChannelId":"UCtarget"}}}}]},"videoOffsetTimeMsec":"1000"}' > "${output%/*}/replay123.live_chat.json"
        fi
        """.write(to: toolURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: toolURL.path)

        let request = CommentExportRequest(sourceURL: URL(string: "https://www.youtube.com/watch?v=replay123")!, source: .liveChatReplay, author: try XCTUnwrap(YouTubeAuthor("@target")), translate: false)
        let discussion = try await YTDLPCommentFetcher(executableURL: toolURL, temporaryDirectory: directory.appendingPathComponent("temporary", isDirectory: true)).fetch(request) { _ in }

        XCTAssertEqual(discussion.entries.first?.text, "hello")
    }
}

@MainActor
final class BundledCommentExportClientTests: XCTestCase {
    func testCancellingTranslationDoesNotPoisonTheNextFetch() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let toolURL = directory.appendingPathComponent("yt-dlp")
        try """
        #!/bin/sh
        printf '%s' '{"title":"A video","id":"abc123","comments":[{"id":"comment","text":"hello","author":"@target","author_id":"UCtarget","timestamp":100}]}'
        """.write(to: toolURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: toolURL.path)

        BlockingURLProtocol.reset()
        let requestStarted = expectation(description: "translation request started")
        BlockingURLProtocol.onStart = { requestStarted.fulfill() }
        defer {
            BlockingURLProtocol.onStart = nil
            BlockingURLProtocol.reset()
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BlockingURLProtocol.self]
        let client = BundledCommentExportClient(
            fetcher: YTDLPCommentFetcher(executableURL: toolURL),
            downloadsURL: directory.appendingPathComponent("downloads", isDirectory: true),
            credentialStore: TestCredentialStore(storedValue: "secret"),
            session: URLSession(configuration: configuration)
        )
        let sourceURL = URL(string: "https://www.youtube.com/watch?v=abc123")!
        let translatedRequest = CommentExportRequest(
            sourceURL: sourceURL,
            source: .videoComments,
            author: try XCTUnwrap(YouTubeAuthor("@target")),
            translate: true
        )
        let firstTask = Task { try await client.start(translatedRequest) { _ in } }

        await fulfillment(of: [requestStarted], timeout: 5)
        client.cancel()
        do {
            _ = try await firstTask.value
            XCTFail("Expected translation cancellation")
        } catch let error as CommentExportError {
            guard case .cancelled = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }

        let secondRequest = CommentExportRequest(
            sourceURL: sourceURL,
            source: .videoComments,
            author: try XCTUnwrap(YouTubeAuthor("@target")),
            translate: false
        )
        let result = try await client.start(secondRequest) { _ in }
        XCTAssertEqual(result.entryCount, 1)
    }
}

@MainActor
final class CommentExportTests: XCTestCase {
    func testRejectsNonYouTubeURLsAndInvalidAuthors() {
        let client = CommentExportTestClient(hasTranslationKey: true)
        let export = CommentExport(client: client)
        export.updateSourceURL("https://example.com/video")
        export.updateAuthor("target")

        XCTAssertFalse(export.canStart)
        XCTAssertEqual(export.validationMessage, "Comments & Live Chat supports YouTube URLs only.")

        export.updateSourceURL("https://www.youtube.com/watch?v=video")
        XCTAssertEqual(export.validationMessage, "Enter one @handle or UC… external channel ID.")
        XCTAssertFalse(export.canStart)
    }

    func testTranslationIsOfferedByDefaultButRequiresAKey() {
        let client = CommentExportTestClient(hasTranslationKey: false)
        let export = CommentExport(client: client)
        export.updateSourceURL("https://www.youtube.com/watch?v=video")
        export.updateAuthor("@target")

        XCTAssertTrue(export.translate)
        XCTAssertFalse(export.canStart)
        XCTAssertEqual(export.validationMessage, "Add an OpenRouter API key in Settings or turn off translation.")

        export.setTranslate(false)
        XCTAssertTrue(export.canStart)
    }

    func testTranslationFailureKeepsOriginalAndRetriesWithoutStartingAnotherFetch() async {
        let original = CommentExportResult(
            folderURL: URL(fileURLWithPath: "/Downloads/Video [id]"),
            originalURL: URL(fileURLWithPath: "/Downloads/Video [id]/target.original.txt"),
            translatedURL: nil,
            entryCount: 2
        )
        let translated = CommentExportResult(
            folderURL: original.folderURL,
            originalURL: original.originalURL,
            translatedURL: URL(fileURLWithPath: "/Downloads/Video [id]/target.zh-Hant.txt"),
            entryCount: 2
        )
        let client = CommentExportTestClient(
            hasTranslationKey: true,
            startResults: [.failure(CommentExportError.translationFailed(original, "temporarily unavailable"))],
            retryResults: [.success(translated)]
        )
        let export = CommentExport(client: client)
        export.updateSourceURL("https://www.youtube.com/watch?v=video")
        export.updateAuthor("@target")

        await export.start()
        if case let .failed(_, diagnostics, canRetryTranslation, result) = export.state {
            XCTAssertEqual(diagnostics, "temporarily unavailable")
            XCTAssertTrue(canRetryTranslation)
            XCTAssertEqual(result, original)
        } else {
            XCTFail("Expected translation failure")
        }

        await export.retryTranslation()
        XCTAssertEqual(export.state, .completed(translated))
        XCTAssertEqual(client.startCount, 1)
        XCTAssertEqual(client.retryTranslationCount, 1)
    }

    func testCancellationIgnoresLateSuccessAndReleasesOperation() async {
        let result = CommentExportResult(
            folderURL: URL(fileURLWithPath: "/Downloads/Video [id]"),
            originalURL: URL(fileURLWithPath: "/Downloads/Video [id]/target.original.txt"),
            translatedURL: nil,
            entryCount: 1
        )
        let operation = ActiveOperation()
        let client = DelayedCommentExportTestClient(result: result)
        let export = CommentExport(client: client, operation: operation)
        export.updateSourceURL("https://www.youtube.com/watch?v=video")
        export.updateAuthor("@target")

        let task = Task { await export.start() }
        while client.startCount == 0 {
            await Task.yield()
        }
        export.cancel()
        await task.value

        XCTAssertEqual(export.state, .cancelled(result))
        XCTAssertFalse(operation.isActive)
    }

    func testDownloadAndExportShareOneActiveOperation() {
        let operation = ActiveOperation()
        let download = Download(operation: operation)
        let export = CommentExport(client: CommentExportTestClient(hasTranslationKey: true), operation: operation)
        download.updateSourceURL("https://example.com/video")
        export.updateSourceURL("https://www.youtube.com/watch?v=video")
        export.updateAuthor("@target")

        XCTAssertTrue(operation.acquire())
        XCTAssertFalse(download.canInspect)
        XCTAssertFalse(export.canStart)
        operation.release()
        XCTAssertTrue(download.canInspect)
        XCTAssertTrue(export.canStart)
    }
}

@MainActor
final class OpenRouterTranslationClientTests: XCTestCase {
    func testSendsFixedModelZDRSchemaAndParentContext() async throws {
        let expectation = expectation(description: "request received")
        var capturedRequest: URLRequest?
        TestURLProtocol.handler = { request in
            capturedRequest = request
            expectation.fulfill()
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("{\"choices\":[{\"message\":{\"content\":\"{\\\"translations\\\":[{\\\"id\\\":\\\"reply\\\",\\\"translation\\\":\\\"回覆\\\"}]}\"}}]}".utf8)
            )
        }
        defer { TestURLProtocol.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let client = OpenRouterTranslationClient(apiKey: "secret-key", session: session)
        let entry = CommentEntry(id: "reply", parentID: "parent", authorHandle: "@target", authorChannelID: nil, text: "Reply", publishedAt: nil, videoOffsetTimeMsec: 1_000, parentText: "Parent")

        let translations = try await client.translate([entry]) { _ in }
        await fulfillment(of: [expectation], timeout: 1)

        let request = try XCTUnwrap(capturedRequest)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["model"] as? String, OpenRouterTranslationClient.model)
        XCTAssertEqual((body["provider"] as? [String: Any])?["zdr"] as? Bool, true)
        XCTAssertEqual((body["provider"] as? [String: Any])?["require_parameters"] as? Bool, true)
        XCTAssertEqual((body["response_format"] as? [String: Any])?["type"] as? String, "json_schema")
        let messages = try XCTUnwrap(body["messages"] as? [[String: Any]])
        XCTAssertTrue(try XCTUnwrap(messages.last?["content"] as? String).contains("parent_context"))
        XCTAssertEqual(translations["reply"], "回覆")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer secret-key")
    }

    func testRejectsMissingOrDuplicateTranslationIDs() async throws {
        TestURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("{\"choices\":[{\"message\":{\"content\":\"{\\\"translations\\\":[{\\\"id\\\":\\\"wrong\\\",\\\"translation\\\":\\\"x\\\"}]}\"}}]}".utf8)
            )
        }
        defer { TestURLProtocol.handler = nil }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TestURLProtocol.self]
        let client = OpenRouterTranslationClient(apiKey: "secret", session: URLSession(configuration: configuration))
        let entry = CommentEntry(id: "expected", parentID: nil, authorHandle: "@target", authorChannelID: nil, text: "text", publishedAt: nil, videoOffsetTimeMsec: 0, parentText: nil)

        do {
            _ = try await client.translate([entry]) { _ in }
            XCTFail("Expected an invalid batch")
        } catch let error as TranslationError {
            if case .invalidBatch = error {
                return
            }
            XCTFail("Unexpected translation error: \(error)")
        }
    }
}

@MainActor
private final class CommentExportTestClient: CommentExportClient {
    let hasTranslationKey: Bool
    var startResults: [Result<CommentExportResult, Error>]
    var retryResults: [Result<CommentExportResult, Error>]
    private(set) var startCount = 0
    private(set) var retryTranslationCount = 0

    init(
        hasTranslationKey: Bool,
        startResults: [Result<CommentExportResult, Error>] = [],
        retryResults: [Result<CommentExportResult, Error>] = []
    ) {
        self.hasTranslationKey = hasTranslationKey
        self.startResults = startResults
        self.retryResults = retryResults
    }

    func start(
        _ request: CommentExportRequest,
        onProgress: @escaping @Sendable (CommentExportProgress) -> Void
    ) async throws -> CommentExportResult {
        startCount += 1
        return try startResults.removeFirst().get()
    }

    func retryTranslation(
        onProgress: @escaping @Sendable (CommentExportProgress) -> Void
    ) async throws -> CommentExportResult {
        retryTranslationCount += 1
        return try retryResults.removeFirst().get()
    }

    func cancel() {}
}

private final class TestURLProtocol: URLProtocol {
    static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else { return }
        var request = self.request
        if request.httpBody == nil, let stream = request.httpBodyStream {
            stream.open()
            var body = Data()
            var buffer = [UInt8](repeating: 0, count: 4_096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                guard count > 0 else { break }
                body.append(buffer, count: count)
            }
            request.httpBody = body
            stream.close()
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
private final class DelayedCommentExportTestClient: CommentExportClient {
    let hasTranslationKey = true
    let result: CommentExportResult
    private(set) var startCount = 0
    private var continuation: CheckedContinuation<CommentExportResult, Error>?

    init(result: CommentExportResult) {
        self.result = result
    }

    func start(
        _ request: CommentExportRequest,
        onProgress: @escaping @Sendable (CommentExportProgress) -> Void
    ) async throws -> CommentExportResult {
        startCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
        }
    }

    func retryTranslation(
        onProgress: @escaping @Sendable (CommentExportProgress) -> Void
    ) async throws -> CommentExportResult {
        throw CommentExportError.noTranslationToRetry
    }

    func cancel() {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private final class BlockingURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var cancelled = false
    static var onStart: (() -> Void)?

    static func reset() {
        lock.lock()
        cancelled = false
        lock.unlock()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.onStart?()
        while !Self.isCancelled() {
            Thread.sleep(forTimeInterval: 0.01)
        }
        client?.urlProtocol(self, didFailWithError: URLError(.cancelled))
    }

    override func stopLoading() {
        Self.lock.lock()
        Self.cancelled = true
        Self.lock.unlock()
    }

    private static func isCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

private struct TestCredentialStore: CredentialStore {
    let storedValue: String?

    func value() -> String? { storedValue }
    func save(_ value: String) throws {}
    func remove() throws {}
}
