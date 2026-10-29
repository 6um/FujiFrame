import Foundation
import ImageIO
import CryptoKit
import UniformTypeIdentifiers

public enum Imaging {
    public static func hash(_ url: URL) throws -> String {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var hash = SHA256()
        while let chunk = try file.read(upToCount: 1024 * 1024), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public static func inspect(_ url: URL) throws -> PhotoMetadata {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetType(source) as String? == UTType.jpeg.identifier,
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any],
              CGImageSourceGetStatus(source) == .statusComplete,
              CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 32] as CFDictionary) != nil else {
            throw FrameError("不是可读取的完整 JPEG 照片")
        }
        let exif = props[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = props[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let aux = props[kCGImagePropertyExifAuxDictionary as String] as? [String: Any] ?? [:]
        var m = PhotoMetadata()
        m.aperture = (exif[kCGImagePropertyExifFNumber as String] as? NSNumber)?.doubleValue
        m.exposure = (exif[kCGImagePropertyExifExposureTime as String] as? NSNumber)?.doubleValue
        m.iso = (exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber])?.first?.intValue
        m.compensation = (exif[kCGImagePropertyExifExposureBiasValue as String] as? NSNumber)?.doubleValue
        m.focalLength = (exif[kCGImagePropertyExifFocalLength as String] as? NSNumber)?.doubleValue
        m.lens = exif[kCGImagePropertyExifLensModel as String] as? String ?? aux[kCGImagePropertyExifAuxLensModel as String] as? String
        m.camera = tiff[kCGImagePropertyTIFFModel as String] as? String
        m.captured = exif[kCGImagePropertyExifDateTimeOriginal as String] as? String
        m.width = props[kCGImagePropertyPixelWidth as String] as? Int
        m.height = props[kCGImagePropertyPixelHeight as String] as? Int
        m.orientation = props[kCGImagePropertyOrientation as String] as? Int
        return m
    }
    public static func thumbnail(_ sourceURL: URL, to destination: URL) throws {
        guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 640,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary),
              let dest = CGImageDestinationCreateWithURL(destination as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { throw FrameError("生成缩略图失败") }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw FrameError("保存缩略图失败") }
    }
}
