import Foundation
import XCTest
@testable import ClipFetch

final class YTDLPInspectorTests: XCTestCase {
    func testUsesValidToolOutputWhenDiagnosticsArePresent() throws {
        let output = Data("{ \"title\": \"A public clip\" }".utf8)
        let diagnostics = Data("WARNING: external JavaScript runtime unavailable\n".utf8)

        let details = try YTDLPInspector.inspectionResult(
            output: output,
            diagnostics: diagnostics,
            terminationStatus: 0
        )

        XCTAssertEqual(details.title, "A public clip")
    }

    func testReportsFailureAfterLargeDiagnostics() async throws {
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try """
        #!/bin/sh
        i=0
        while [ "$i" -lt 2048 ]; do
          printf 'diagnostic output large enough to fill a pipe buffer\\n' >&2
          i=$((i + 1))
        done
        exit 1
        """.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        defer { try? FileManager.default.removeItem(at: scriptURL) }

        let completed = expectation(description: "inspection failure")
        Task {
            defer { completed.fulfill() }

            do {
                _ = try await YTDLPInspector(executableURL: scriptURL)
                    .inspect(URL(string: "https://example.com/video")!)
                XCTFail("Expected inspection to fail")
            } catch let error as YTDLPInspector.InspectionError {
                XCTAssertFalse(error.diagnostics?.isEmpty ?? true)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }

        await fulfillment(of: [completed], timeout: 2)
    }

    func testReportsAPlainLanguageErrorWhenTheToolFails() async {
        let inspector = YTDLPInspector(executableURL: URL(fileURLWithPath: "/usr/bin/false"))

        do {
            _ = try await inspector.inspect(URL(string: "https://example.com/video")!)
            XCTFail("Expected inspection to fail")
        } catch let error as YTDLPInspector.InspectionError {
            XCTAssertEqual(
                error.errorDescription,
                "ClipFetch couldn’t inspect this Source URL. Check that it is publicly available and try again."
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
