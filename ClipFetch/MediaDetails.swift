import Foundation

struct MediaDetails: Equatable, Sendable {
    let title: String
    let thumbnailURL: URL?
    let duration: TimeInterval?
    let estimatedSize: Int64?
    let width: Int?
    let height: Int?

    var resolution: String {
        guard let width, let height else { return "Unknown" }
        return "\(width) × \(height)"
    }

    static func decode(_ data: Data) throws -> Self {
        let output = try JSONDecoder().decode(InspectionOutput.self, from: data)
        let selectedFormats = output.requestedFormats ?? []
        let videoFormat = selectedFormats.first { $0.width != nil && $0.height != nil }
        let selectedSize = selectedFormats.reduce(Int64.zero) { size, format in
            size + (format.filesize ?? format.filesizeApprox ?? 0)
        }

        return Self(
            title: output.title,
            thumbnailURL: output.thumbnail.flatMap(URL.init(string:)),
            duration: output.duration,
            estimatedSize: selectedSize > 0 ? selectedSize : output.filesize ?? output.filesizeApprox,
            width: videoFormat?.width ?? output.width,
            height: videoFormat?.height ?? output.height
        )
    }
}

private struct InspectionOutput: Decodable {
    let title: String
    let thumbnail: String?
    let duration: TimeInterval?
    let filesize: Int64?
    let filesizeApprox: Int64?
    let width: Int?
    let height: Int?
    let requestedFormats: [InspectionFormat]?

    enum CodingKeys: String, CodingKey {
        case title, thumbnail, duration, filesize, width, height
        case filesizeApprox = "filesize_approx"
        case requestedFormats = "requested_formats"
    }
}

private struct InspectionFormat: Decodable {
    let filesize: Int64?
    let filesizeApprox: Int64?
    let width: Int?
    let height: Int?

    enum CodingKeys: String, CodingKey {
        case filesize, width, height
        case filesizeApprox = "filesize_approx"
    }
}
