import AppKit
import SwiftUI

enum ArtworkColors {

    static func extract(from image: NSImage?) -> [Color] {
        let fallback: [Color] = [.indigo, .teal, .purple]
        guard let image = image else { return fallback }
        let size = NSSize(width: 16, height: 16)
        let small = NSImage(size: size)
        small.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size))
        small.unlockFocus()
        guard let tiff = small.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return fallback }
        var buckets: [Int: (r: CGFloat, g: CGFloat, b: CGFloat, n: Int)] = [:]
        for x in 0..<16 {
            for y in 0..<16 {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
                c.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
                guard b > 0.08, b < 0.95, s > 0.18 else { continue }
                var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0
                c.getRed(&r, green: &g, blue: &bl, alpha: &a)
                let bucket = Int(h * 12) % 12
                if var cur = buckets[bucket] {
                    cur.r += r; cur.g += g; cur.b += bl; cur.n += 1
                    buckets[bucket] = cur
                } else {
                    buckets[bucket] = (r, g, bl, 1)
                }
            }
        }
        let top = buckets.values.sorted { $0.n > $1.n }.prefix(3)
        guard !top.isEmpty else { return fallback }
        return top.map { Color(red: Double($0.r / CGFloat($0.n)), green: Double($0.g / CGFloat($0.n)), blue: Double($0.b / CGFloat($0.n))) }
    }
}
