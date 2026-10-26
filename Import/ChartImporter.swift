import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

enum ImportFailure: Error, LocalizedError, Equatable {
    case empty, tooLarge, unsupported, malformed, encrypted, multiplePages, dimensions, unreadable
    var errorDescription: String? {
        switch self {
        case .empty: "The file is empty. Choose a JPEG, PNG, or single-page PDF."
        case .tooLarge: "The file exceeds the 20 MB limit. Choose a smaller file."
        case .unsupported: "The file contents are not a supported JPEG, PNG, or PDF."
        case .malformed: "The file could not be decoded. It may be damaged or incomplete."
        case .encrypted: "Encrypted or password-protected PDFs are not supported. Choose an unencrypted copy."
        case .multiplePages: "Only single-page PDFs are supported. Export the page you want as a separate PDF."
        case .dimensions: "The image or page dimensions exceed the safe import limits."
        case .unreadable: "The file could not be read. Please select it again."
        }
    }
}

struct ImportedChart: Sendable {
    /// Stable UI identity, without hashing or comparing image bytes during layout.
    let id = UUID()
    let originalData: Data
    let previewPNG: Data
    let source: SourceProvenance
    let pixelWidth: Int
    let pixelHeight: Int
}

/// Serial, off-main decoding; only immutable data crosses actor boundaries.
actor ChartImporter {
    static let maximumBytes = 20 * 1024 * 1024
    static let previewDimension = 1600

    func load(url: URL) throws -> ImportedChart {
        guard url.isFileURL else { throw ImportFailure.unreadable }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        try Task.checkCancellation()
        do {
            let info = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard info.isRegularFile == true else { throw ImportFailure.unreadable }
            if let size = info.fileSize, size > Self.maximumBytes { throw ImportFailure.tooLarge }
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var data = Data()
            while data.count <= Self.maximumBytes {
                try Task.checkCancellation()
                let chunk = try handle.read(upToCount: min(65536, Self.maximumBytes + 1 - data.count)) ?? Data()
                if chunk.isEmpty { break }
                data.append(chunk)
            }
            return try decode(data: data, fileName: url.lastPathComponent)
        } catch let error as ImportFailure { throw error }
        catch is CancellationError { throw CancellationError() }
        catch { throw ImportFailure.unreadable }
    }

    func decode(data: Data, fileName: String) throws -> ImportedChart {
        try Task.checkCancellation()
        guard !data.isEmpty else { throw ImportFailure.empty }
        guard data.count <= Self.maximumBytes else { throw ImportFailure.tooLarge }
        let image: CGImage
        let type: String
        let pageNumber: Int?
        if data.starts(with: Data("%PDF-".utf8)) {
            guard let document = PDFDocument(data: data) else { throw ImportFailure.malformed }
            guard !document.isEncrypted, !document.isLocked else { throw ImportFailure.encrypted }
            guard document.pageCount > 0 else { throw ImportFailure.empty }
            guard document.pageCount == 1 else { throw ImportFailure.multiplePages }
            guard let page = document.page(at: 0), let pageRef = page.pageRef else { throw ImportFailure.malformed }
            let bounds = pageRef.getBoxRect(.mediaBox)
            guard bounds.minX.isFinite, bounds.minY.isFinite,
                  bounds.width.isFinite, bounds.height.isFinite,
                  bounds.width > 0, bounds.height > 0,
                  bounds.width <= 14400, bounds.height <= 14400 else { throw ImportFailure.dimensions }
            let rotation = (pageRef.rotationAngle % 360 + 360) % 360
            guard rotation % 90 == 0 else { throw ImportFailure.malformed }
            let pageWidth = rotation % 180 == 0 ? bounds.width : bounds.height
            let pageHeight = rotation % 180 == 0 ? bounds.height : bounds.width
            let scale = min(2, CGFloat(Self.previewDimension) / max(pageWidth, pageHeight))
            let width = max(1, Int(ceil(pageWidth * scale)))
            let height = max(1, Int(ceil(pageHeight * scale)))
            guard let context = CGContext(data: nil, width: width, height: height,
                                          bitsPerComponent: 8, bytesPerRow: width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { throw ImportFailure.malformed }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            // Quartz handles both the page's /Rotate and a nonzero /MediaBox
            // origin. Applying PDFKit's rotation again would double-rotate it.
            context.scaleBy(x: scale, y: scale)
            context.concatenate(pageRef.getDrawingTransform(.mediaBox,
                rect: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight), rotate: 0, preserveAspectRatio: true))
            try Task.checkCancellation()
            context.drawPDFPage(pageRef)
            guard let rendered = context.makeImage() else { throw ImportFailure.malformed }
            image = rendered; type = "application/pdf"; pageNumber = 1
        } else {
            guard let source = CGImageSourceCreateWithData(data as CFData,
                      [kCGImageSourceShouldCache: false] as CFDictionary),
                  let identifier = CGImageSourceGetType(source) as String?,
                  identifier == UTType.png.identifier || identifier == UTType.jpeg.identifier
            else { throw ImportFailure.unsupported }
            guard CGImageSourceGetCount(source) == 1,
                  CGImageSourceGetStatus(source) == .statusComplete,
                  let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                  let width = properties[kCGImagePropertyPixelWidth] as? Int,
                  let height = properties[kCGImagePropertyPixelHeight] as? Int,
                  width > 0, height > 0 else { throw ImportFailure.malformed }
            guard width <= 20000, height <= 20000, width * height <= 40_000_000 else { throw ImportFailure.dimensions }
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Self.previewDimension,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
            else { throw ImportFailure.malformed }
            image = thumbnail
            type = identifier == UTType.png.identifier ? "image/png" : "image/jpeg"
            pageNumber = nil
        }
        try Task.checkCancellation()
        let buffer = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(buffer, UTType.png.identifier as CFString, 1, nil)
        else { throw ImportFailure.malformed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImportFailure.malformed }
        try Task.checkCancellation()
        return ImportedChart(originalData: data, previewPNG: buffer as Data,
                             source: try SourceProvenance(fileName: fileName, mediaType: type, page: pageNumber),
                             pixelWidth: image.width, pixelHeight: image.height)
    }
}
