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
