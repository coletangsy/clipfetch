import Foundation
import XCTest
@testable import ClipFetch

final class MediaDetailsTests: XCTestCase {
    func testDecodesSelectedBestMP4Details() throws {
        let output = """
        {
          "title": "A public clip",
          "thumbnail": "https://example.com/thumbnail.jpg",
          "duration": 125.5,
          "requested_formats": [
            { "width": 1920, "height": 1080, "filesize": 25000000 },
            { "filesize_approx": 4000000 }
          ]
        }
        """

        let details = try MediaDetails.decode(Data(output.utf8))

        XCTAssertEqual(details.title, "A public clip")
        XCTAssertEqual(details.thumbnailURL, URL(string: "https://example.com/thumbnail.jpg"))
        XCTAssertEqual(details.duration, 125.5)
        XCTAssertEqual(details.estimatedSize, 29000000)
        XCTAssertEqual(details.resolution, "1920 × 1080")
    }
}
