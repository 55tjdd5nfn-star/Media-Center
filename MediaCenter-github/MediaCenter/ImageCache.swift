import AppKit
import CoreGraphics
import ImageIO

final class ImageCache {
    static let shared = ImageCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {

        cache.totalCostLimit = 120 * 1024 * 1024
        cache.countLimit = 200
    }

    func image(at path: String, maxDimension: CGFloat) -> NSImage? {
        guard !path.isEmpty else { return nil }
        let key = "\(path)|\(Int(maxDimension))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard let image = Self.downscaledImage(at: path, maxDimension: maxDimension) else { return nil }
        let cost = Int(image.size.width * image.size.height * 4)
        cache.setObject(image, forKey: key, cost: cost)
        return image
    }

    static func downscaledImage(at path: String, maxDimension: CGFloat) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(Int(maxDimension), 1)
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }

    static func downscaledJPEGData(_ data: Data, maxDimension: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let h = props[kCGImagePropertyPixelHeight] as? CGFloat else { return nil }

        guard max(w, h) > maxDimension else { return data }
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(Int(maxDimension), 1)
        ] as CFDictionary) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cg)
        return rep.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    }
}
