import Foundation
import XCTest
@testable import ClipFetch

final class SourceURLTests: XCTestCase {
    func testAcceptsWebSourceURLsOnly() {
        XCTAssertEqual(
            SourceURL.parse(" https://example.com/watch?v=clip "),
            URL(string: "https://example.com/watch?v=clip")
        )
        XCTAssertNil(SourceURL.parse("youtube.com/watch?v=clip"))
        XCTAssertNil(SourceURL.parse("ftp://example.com/video.mp4"))
        XCTAssertNil(SourceURL.parse("https://user:password@example.com/video"))
        XCTAssertNil(SourceURL.parse("https://"))
    }
}
