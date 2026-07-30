import AppKit
import XCTest
@testable import ClipFetch

final class ContentViewTests: XCTestCase {
    func testCopiesDiagnosticsToPasteboard() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name(UUID().uuidString))

        copyDiagnostics("yt-dlp failed", to: pasteboard)

        XCTAssertEqual(pasteboard.string(forType: .string), "yt-dlp failed")
    }
}
