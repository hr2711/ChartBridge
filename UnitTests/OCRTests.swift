import Testing
import Foundation
import UIKit

struct OCRTests {
    @MainActor @Test func optionalEvidenceCropIsBoundedAndTopLeftOriented() async throws {
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 800), format: format).image { c in
            UIColor.blue.setFill(); c.fill(CGRect(x: 0, y: 0, width: 1000, height: 800))
            UIColor.red.setFill(); c.fill(CGRect(x: 0, y: 0, width: 500, height: 400))
        }
        let preview = try #require(image.pngData())
        let data = try await EvidenceImageRenderer().crop(preview: preview, region: ImageBox(x: 0, y: 0, width: 0.5, height: 0.5))
        let result = try #require(UIImage(data: data)?.cgImage)
        #expect(result.width == 400 && result.height == 320)
        let raster = try Raster(data: data)
        let center = raster.color(raster.width / 2, raster.height / 2)
        #expect(center.r > 0.8 && center.b < 0.2)
        for region in [ImageBox(x: -0.1, y: 0, width: 0.5, height: 0.5), ImageBox(x: 0, y: 0, width: 0, height: 0.5), ImageBox(x: .nan, y: 0, width: 1, height: 1)] {
            do { _ = try await EvidenceImageRenderer().crop(preview: preview, region: region); Issue.record("Invalid source region must be rejected") }
            catch { #expect(error is AnalysisFailure) }
        }
        do {
            _ = try await EvidenceImageRenderer().crop(preview: Data("malformed".utf8), region: ImageBox(x: 0, y: 0, width: 1, height: 1))
            Issue.record("Malformed optional preview must be rejected")
        } catch { #expect(error is AnalysisFailure) }
        let cancelled = Task { try await EvidenceImageRenderer().crop(preview: preview, region: ImageBox(x: 0, y: 0, width: 1, height: 1)) }
        cancelled.cancel()
        do { _ = try await cancelled.value; Issue.record("Cancelled optional crop must not finish") }
        catch { #expect(error is CancellationError) }
    }
    @MainActor
    @Test func importedJPEGAndPDF() async throws {
        let fixture = ExtractionFixtures.make(kind: .verticalBar, variant: "negative")
        let image = try #require(UIImage(data: fixture.data))
        let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 1000, height: 800)).pdfData { context in
            context.beginPage()
            image.draw(in: CGRect(x: 0, y: 0, width: 1000, height: 800))
        }
        for data in [try #require(image.jpegData(compressionQuality: 0.9)), pdf] {
            let imported = try await ChartImporter().decode(data: data, fileName: "synthetic")
            let result = try await ChartAnalyzer().analyze(imported)
            let output = try #require(result.output)
            #expect(output.kind == .verticalBar)
            #expect(output.values.count == 3)
            for value in output.values {
                let i = try #require(fixture.categories.firstIndex(of: value.category))
                #expect(abs(value.value-fixture.values[i]) <= 2)
            }
        }
    }
    @Test func numberParsingAndCoordinates() {
        #expect(OCRNumber.parse("-1,250.5")?.value == -1250.5)
        #expect(OCRNumber.parse("25%")?.isPercent == true)
        for text in ["1O", "1,23", "NaN", "1e3", "l0", ""] {
            #expect(OCRNumber.parse(text) == nil)
        }
        let box = ImageBox(vision: CGRect(x: 0.1, y: 0.7, width: 0.2, height: 0.1))
        #expect(abs(box.y - 0.2) < 0.0001)
    }

    @MainActor
    @Test func realVisionEnglishAndOrientation() async throws {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 600), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 600))
            ("Revenue" as NSString).draw(at: CGPoint(x: 80, y: 60),
                                        withAttributes: [.font: UIFont.systemFont(ofSize: 42), .foregroundColor: UIColor.black])
            ("North -1,250.5 25%" as NSString).draw(at: CGPoint(x: 80, y: 180),
                                        withAttributes: [.font: UIFont.systemFont(ofSize: 36), .foregroundColor: UIColor.black])
        }
        let data = try #require(image.pngData())
        let document = try await VisionTextEngine().recognize(data)
        #expect(document.observations.contains { $0.raw.contains("Revenue") })
        #expect(document.observations.contains { $0.raw.contains("25%") })
        #expect(document.observations.allSatisfy { $0.sourceID == document.sourceID && $0.confidence >= 0 && $0.confidence <= 1 })
        #expect(document.observations.first { $0.raw.contains("Revenue") }!.box.y < 0.2)
        // Physically rotate pixels; pass the matching orientation back to Vision.
        let rotated = UIGraphicsImageRenderer(size: CGSize(width: 600, height: 1000), format: format).image { c in
            c.cgContext.translateBy(x: 600, y: 0)
            c.cgContext.rotate(by: .pi / 2)
            image.draw(in: CGRect(x: 0, y: 0, width: 1000, height: 600))
        }
        let rotatedDocument = try await VisionTextEngine().recognize(try #require(rotated.pngData()), orientation: .left)
        #expect(rotatedDocument.observations.contains { $0.raw.contains("Revenue") })
    }
}
