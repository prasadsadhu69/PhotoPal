import CoreImage
import Foundation
import ImageIO
import Vision

/// "Match my real pet": lifts your pet out of a photo with Apple's on-device
/// image recognition, then reads its fur colors. Nothing leaves the phone.
enum PhotoMatch {
    /// Returns a custom coat for your pal, or nil if no colors could be read
    static func palette(from imageData: Data, name: String) async -> PetPalette? {
        let values = await Task.detached(priority: .userInitiated) {
            PhotoMatch.analyze(imageData)
        }.value
        guard let v = values, v.count == 10 else { return nil }
        return PetPalette(id: "custom", name: name,
                          main: RGB(v[0], v[1], v[2]),
                          accent: RGB(v[3], v[4], v[5]),
                          belly: RGB(v[6], v[7], v[8]),
                          blaze: v[9] > 0.5,
                          price: 0)
    }

    /// [main r,g,b, accent r,g,b, belly r,g,b, blaze 0/1]
    nonisolated static func analyze(_ data: Data) -> [Double]? {
        let thumbOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 1024,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let photo = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary) else { return nil }

        // 1. Cut the pet out of the background (falls back to the whole photo)
        var subject = photo
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: photo, options: [:])
        if (try? handler.perform([request])) != nil,
           let observation = request.results?.first,
           let buffer = try? observation.generateMaskedImage(ofInstances: observation.allInstances,
                                                              from: handler,
                                                              croppedToInstancesExtent: true) {
            let ci = CIImage(cvPixelBuffer: buffer)
            if let cut = CIContext().createCGImage(ci, from: ci.extent) {
                subject = cut
            }
        }

        // 2. Shrink to 48x48 and read the pixels
        let side = 48
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drew: Bool = pixels.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: side, height: side,
                                      bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            ctx.draw(subject, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drew else { return nil }

        // 3. Keep only the pet's pixels, sorted from darkest to lightest
        var colors: [(r: Double, g: Double, b: Double, lum: Double)] = []
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let a = Double(pixels[i + 3])
            guard a > 200 else { continue }
            let r = Double(pixels[i]) / a
            let g = Double(pixels[i + 1]) / a
            let b = Double(pixels[i + 2]) / a
            colors.append((r, g, b, 0.299 * r + 0.587 * g + 0.114 * b))
        }
        guard colors.count >= 30 else { return nil }
        colors.sort { $0.lum < $1.lum }

        func average(_ from: Double, _ to: Double) -> (Double, Double, Double) {
            let lo = Int(Double(colors.count) * from)
            let hi = max(lo + 1, Int(Double(colors.count) * to))
            let slice = colors[lo..<min(hi, colors.count)]
            let n = Double(slice.count)
            return (slice.reduce(0) { $0 + $1.r } / n,
                    slice.reduce(0) { $0 + $1.g } / n,
                    slice.reduce(0) { $0 + $1.b } / n)
        }

        let main = average(0.35, 0.8)     // the fur most of the pet is covered in
        let accent = average(0.05, 0.3)   // darker bits like ears and patches
        let light = average(0.9, 1.0)     // lightest bits like a white chest or muzzle
        let mainLum = 0.299 * main.0 + 0.587 * main.1 + 0.114 * main.2
        let lightLum = 0.299 * light.0 + 0.587 * light.1 + 0.114 * light.2
        let belly = lightLum > mainLum + 0.12 ? light : (min(1, main.0 + 0.1), min(1, main.1 + 0.1), min(1, main.2 + 0.1))
        let blaze = lightLum > 0.82 && mainLum < 0.75

        return [main.0, main.1, main.2, accent.0, accent.1, accent.2, belly.0, belly.1, belly.2, blaze ? 1 : 0]
    }
}
