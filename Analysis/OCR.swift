import Foundation
import Vision
import ImageIO
import CryptoKit

/// All geometry uses normalized top-left coordinates after orientation normalization.
struct ImageBox: Equatable, Sendable {
    let x: Double
    let y: Double
    let width: Double
    let height: Double
    var midX: Double { x + width / 2 }
    var midY: Double { y + height / 2 }
    var maxX: Double { x + width }
    var maxY: Double { y + height }
    init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    init(vision: CGRect) {
        self.init(x: vision.minX, y: 1 - vision.maxY, width: vision.width, height: vision.height)
    }
    func contains(_ px: Double, _ py: Double, padding: Double = 0) -> Bool {
        px >= x - padding && px <= maxX + padding && py >= y - padding && py <= maxY + padding
    }
}

struct OCRText: Equatable, Sendable, Identifiable {
    let id: Int
    let raw: String
    let alternatives: [String]
    let confidence: Float
    let box: ImageBox
    let sourceID: String
}

struct OCRDocument: Sendable {
    let sourceID: String
    let observations: [OCRText]
    let width: Int
    let height: Int
    let orientation: UInt32
}

enum AnalysisFailure: Error { case invalidImage, imageTooSmall }

actor VisionTextEngine {
    /// Imported preview images are already orientation-normalized, including PDF pages.
    /// Explicit orientation is available for independent callers and orientation regression tests.
    func recognize(_ data: Data, orientation: CGImagePropertyOrientation = .up) throws -> OCRDocument {
        try Task.checkCancellation()
        guard data.count <= ChartImporter.maximumBytes,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int,
              width > 0, height > 0, width <= 1600, height <= 1600,
              let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary),
              image.width <= 1600, image.height <= 1600 else { throw AnalysisFailure.invalidImage }
        let request = VNRecognizeTextRequest()
        request.revision = VNRecognizeTextRequestRevision3
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = false
        request.minimumTextHeight = 0.008
        let handler = VNImageRequestHandler(cgImage: image, orientation: orientation, options: [:])
        try handler.perform([request])
        try Task.checkCancellation()
        let sourceID = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let observations = (request.results ?? []).enumerated().compactMap { index, observation -> OCRText? in
            let candidates = observation.topCandidates(3)
            guard let first = candidates.first else { return nil }
            return OCRText(id: index, raw: first.string, alternatives: candidates.dropFirst().map(\.string),
                           confidence: first.confidence, box: ImageBox(vision: observation.boundingBox), sourceID: sourceID)
        }
        return OCRDocument(sourceID: sourceID, observations: observations, width: image.width,
                           height: image.height, orientation: orientation.rawValue)
    }
}

/// Formatting is explicit: grouped English thousands and a trailing % are parsed without
/// changing raw OCR. Letters such as O or l are never substituted with digits.
enum OCRNumber {
    struct Parsed: Equatable, Sendable { let value: Double; let isPercent: Bool }
    static func parse(_ text: String) -> Parsed? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.range(of: #"\A[-+]?(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]+)?%?\z"#,
                            options: .regularExpression) != nil else { return nil }
        let percent = trimmed.hasSuffix("%")
        let clean = trimmed.replacingOccurrences(of: ",", with: "").replacingOccurrences(of: "%", with: "")
        guard let value = Double(clean), value.isFinite else { return nil }
        return Parsed(value: value, isPercent: percent)
    }
}
