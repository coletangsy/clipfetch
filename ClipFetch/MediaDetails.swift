import Foundation

enum QualityOption: Hashable, Sendable {
    case best
    case resolution(width: Int, height: Int)

    var displayName: String {
        switch self {
        case .best:
            "Best"
        case let .resolution(width, height):
            "\(width) × \(height)"
        }
    }
}

struct MediaDetails: Equatable, Sendable {
    let title: String
    let thumbnailURL: URL?
    let duration: TimeInterval?
    let estimatedSize: Int64?
    let width: Int?
    let height: Int?
    let qualityOptions: [QualityOption]

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
        let qualityOptions = Set((output.formats ?? []).compactMap { format -> QualityOption? in
            guard format.fileExtension == "mp4",
                  format.vcodec != "none",
                  let width = format.width,
                  let height = format.height else {
                return nil
            }
            return .resolution(width: width, height: height)
        })
        .sorted { lhs, rhs in
            guard case let .resolution(leftWidth, leftHeight) = lhs,
                  case let .resolution(rightWidth, rightHeight) = rhs else {
                return false
            }
            return leftHeight == rightHeight ? leftWidth > rightWidth : leftHeight > rightHeight
        }

        return Self(
            title: output.title,
            thumbnailURL: output.thumbnail.flatMap(URL.init(string:)),
            duration: output.duration,
            estimatedSize: selectedSize > 0 ? selectedSize : output.filesize ?? output.filesizeApprox,
            width: videoFormat?.width ?? output.width,
            height: videoFormat?.height ?? output.height,
            qualityOptions: [.best] + qualityOptions
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
    let formats: [InspectionFormat]?

    enum CodingKeys: String, CodingKey {
        case title, thumbnail, duration, filesize, width, height, formats
        case filesizeApprox = "filesize_approx"
        case requestedFormats = "requested_formats"
    }
}

private struct InspectionFormat: Decodable {
    let filesize: Int64?
    let filesizeApprox: Int64?
    let width: Int?
    let height: Int?
    let fileExtension: String?
    let vcodec: String?

    enum CodingKeys: String, CodingKey {
        case filesize, width, height, vcodec
        case fileExtension = "ext"
        case filesizeApprox = "filesize_approx"
    }
}
