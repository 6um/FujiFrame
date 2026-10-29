// Synthetic JPEGs for reproducible UI QA. Not real camera samples.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

@main struct MakeQAFixtures {
    static func main() async throws {
        let root = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let inputs = root.appendingPathComponent("JPEG Inputs")
        try fm.createDirectory(at: inputs, withIntermediateDirectories: true)
        let library = try PhotoLibrary(root: root.appendingPathComponent("QA Library"), create: true)
        let recipe = Recipe(name: "午后漫步 · 测试配方", summary: "用于界面验收的合成样片，并非富士相机实拍。", source: "https://fujifilm-dsc.com/en/manual/x-t5/")
        let version = try await library.saveRecipe(recipe, parameters: ["film": "CLASSIC CHROME", "drPriority": "OFF", "dr": "DR200", "wb": "日光", "wbR": "2", "wbB": "-3", "highlights": "-1", "shadows": "1", "color": "2", "noise": "-4", "clarity": "0", "grain": "WEAK", "grainSize": "SMALL"], firmware: "", exposureAdvice: "逆光时观察高光，曝光补偿按现场调整。", note: "合成测试数据")
        for i in 0..<8 {
            let width = 1200, height = 800
            let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
            let sky = CGColor(red: 0.28 + Double(i) * 0.04, green: 0.52, blue: 0.57, alpha: 1)
            ctx.setFillColor(sky); ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
            ctx.setFillColor(CGColor(red: 0.91, green: 0.74, blue: 0.45, alpha: 1)); ctx.fillEllipse(in: CGRect(x: 720 - i * 40, y: 440, width: 150, height: 150))
            ctx.setFillColor(CGColor(red: 0.22, green: 0.34, blue: 0.29, alpha: 1))
            ctx.move(to: CGPoint(x: 0, y: 0)); ctx.addLine(to: CGPoint(x: 0, y: 220)); ctx.addLine(to: CGPoint(x: 330, y: 480)); ctx.addLine(to: CGPoint(x: 700, y: 170)); ctx.addLine(to: CGPoint(x: 980, y: 390)); ctx.addLine(to: CGPoint(x: 1200, y: 120)); ctx.addLine(to: CGPoint(x: 1200, y: 0)); ctx.closePath(); ctx.fillPath()
            let url = inputs.appendingPathComponent("SYNTHETIC_\(i + 1).JPG")
            let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
            let exif: [CFString: Any] = [kCGImagePropertyExifFNumber: 2.8 + Double(i), kCGImagePropertyExifExposureTime: i == 7 ? 2.0 : 1.0 / 250, kCGImagePropertyExifISOSpeedRatings: [400], kCGImagePropertyExifFocalLength: 35, kCGImagePropertyExifLensModel: "Synthetic lens / QA", kCGImagePropertyExifDateTimeOriginal: "2026:10:28 16:30:00"]
            CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImagePropertyExifDictionary: exif, kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFModel: "X-T5 (Synthetic QA)"], kCGImagePropertyOrientation: i == 3 ? 6 : 1] as CFDictionary)
            guard CGImageDestinationFinalize(dest) else { throw FrameError("写入合成照片失败") }
            let result = await library.importPhoto(url, versionID: version.id)
            guard !result.failed else { throw FrameError(result.message) }
        }
        _ = try await library.saveRecipe(Recipe(name: "黑白街角", summary: "ACROS 黑白配方示例"), parameters: ["film": "ACROS", "monoWC": "2", "grain": "STRONG"], firmware: "", exposureAdvice: "", note: "合成测试配方")
        print(root.path)
    }
}
