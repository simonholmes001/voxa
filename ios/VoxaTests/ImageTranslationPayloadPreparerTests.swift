#if canImport(UIKit)
import UIKit
import XCTest
@testable import VoxaHome

final class ImageTranslationPayloadPreparerTests: XCTestCase {
    func testInvalidPhotoDataIsRejectedBeforeUpload() {
        XCTAssertThrowsError(try ImageTranslationPayloadPreparer.prepareJPEG(from: Data("not-image".utf8))) { error in
            XCTAssertEqual(error as? ImageTranslationPayloadPreparationError, .unreadable)
        }
    }

    func testPngPhotoDataIsNormalizedToJpegPayload() throws {
        let pngData = try XCTUnwrap(Self.imageData(size: CGSize(width: 64, height: 64), format: .png))

        let payload = try ImageTranslationPayloadPreparer.prepareJPEG(from: pngData)

        XCTAssertEqual(payload.mimeType, "image/jpeg")
        XCTAssertTrue(payload.data.starts(with: [0xFF, 0xD8]))
        XCTAssertLessThanOrEqual(payload.data.count, ImageTranslationPayloadPreparer.maxBytes)
    }

    func testLargePhotoIsCompressedBelowServerLimit() throws {
        let image = Self.image(size: CGSize(width: 3_200, height: 2_400))

        let payload = try ImageTranslationPayloadPreparer.prepareJPEG(from: image)

        XCTAssertEqual(payload.mimeType, "image/jpeg")
        XCTAssertLessThanOrEqual(payload.data.count, ImageTranslationPayloadPreparer.maxBytes)
    }

    private static func imageData(size: CGSize, format: ImageFormat) -> Data? {
        let image = image(size: size)
        switch format {
        case .png:
            return image.pngData()
        }
    }

    private static func image(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: size.width / 2, height: size.height / 2))
        }
    }

    private enum ImageFormat {
        case png
    }
}
#endif
