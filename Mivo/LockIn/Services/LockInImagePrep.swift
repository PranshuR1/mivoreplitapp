import UIKit

/// Shrinks a photo before it is shown to Milo. A screenshot or a camera shot is
/// several megabytes; Milo only needs enough to read it, and the smaller the upload
/// the faster the answer.
enum LockInImagePrep {
    static let maxSide: CGFloat = 1280
    static let quality: CGFloat = 0.6

    static func jpeg(from image: UIImage) -> Data? {
        let longest = max(image.size.width, image.size.height)
        guard longest > 0 else { return nil }
        let scale = min(1, maxSide / longest)
        let size = CGSize(width: (image.size.width * scale).rounded(), height: (image.size.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let resized = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    static func jpeg(fromData data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return jpeg(from: image)
    }
}
