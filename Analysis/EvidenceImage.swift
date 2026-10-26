import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Optional, off-main visual aid. Input is the orientation-normalized import preview,
/// never the original large file. No content is saved, uploaded, or cached here.
actor EvidenceImageRenderer {
    func crop(preview: Data, region: ImageBox) throws -> Data {
        try Task.checkCancellation()
        guard !preview.isEmpty, preview.count <= ChartImporter.maximumBytes,
              [region.x, region.y, region.width, region.height].allSatisfy(\.isFinite),
              region.x >= 0, region.y >= 0, region.width > 0, region.height > 0,
              region.maxX <= 1.000001, region.maxY <= 1.000001,
              let source = CGImageSourceCreateWithData(preview as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= ChartImporter.previewDimension, height <= ChartImporter.previewDimension
        else { throw AnalysisFailure.invalidImage }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 800, kCGImageSourceShouldCacheImmediately: true]
        guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw AnalysisFailure.invalidImage }
        try Task.checkCancellation()
        // CGImage pixel coordinates use the same top-left origin as ImageBox.
        let rect = CGRect(x: region.x * Double(thumbnail.width), y: region.y * Double(thumbnail.height),
            width: region.width * Double(thumbnail.width), height: region.height * Double(thumbnail.height))
            .integral.intersection(CGRect(x: 0, y: 0, width: thumbnail.width, height: thumbnail.height))
        guard !rect.isEmpty, let crop = thumbnail.cropping(to: rect) else { throw AnalysisFailure.invalidImage }
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { throw AnalysisFailure.invalidImage }
        CGImageDestinationAddImage(destination, crop, nil)
        guard CGImageDestinationFinalize(destination) else { throw AnalysisFailure.invalidImage }
        try Task.checkCancellation()
        return data as Data
    }
}
