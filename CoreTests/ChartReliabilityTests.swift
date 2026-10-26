import Foundation
import Testing
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import PDFKit
#if SWIFT_PACKAGE
@testable import ChartBridgeMath
#endif

@Suite struct ChartImportSafetyTests {
    @Test(arguments: [0, 90, 180, 270])
    func rotatedPDFKeepsItsCompletePage(_ rotation: Int) async throws {
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data))
        var bounds = CGRect(x: 20, y: 40, width: 100, height: 200)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(bounds)
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 20, y: 40, width: 100, height: 100))
        context.endPDFPage(); context.closePDF()
        let document = try #require(PDFDocument(data: data as Data))
        let page = try #require(document.page(at: 0))
        page.rotation = rotation
        // Keep the raw nonzero MediaBox for the unrotated case. PDFKit may
        // normalize its origin while serializing the rotated test pages.
        let serialized = rotation == 0 ? data as Data : try #require(document.dataRepresentation())
        let imported = try await ChartImporter().decode(data: serialized, fileName: "synthetic.pdf")
        #expect(imported.pixelWidth == (rotation % 180 == 0 ? 200 : 400))
        #expect(imported.pixelHeight == (rotation % 180 == 0 ? 400 : 200))
        let raster = try Raster(data: imported.previewPNG)
        let filled = (0..<raster.height).reduce(0) { count, y in
            count + (0..<raster.width).filter { raster.color($0, y).chroma > 0.8 }.count
        }
        #expect(Double(filled) / Double(raster.width * raster.height) > 0.98, "Rotation and nonzero page origins must not crop the page")
    }
    private func png(width: Int = 8, height: Int = 8) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height,
            bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    @Test func contentsOverrideExtensionAndIdentityIsPerImport() async throws {
        let importer = ChartImporter(), data = try png()
        let first = try await importer.decode(data: data, fileName: "misleading.pdf")
        let second = try await importer.decode(data: data, fileName: "misleading.pdf")
        #expect(first.source.mediaType == "image/png")
        #expect(first.originalData == data && first.previewPNG == second.previewPNG)
        #expect(first.id != second.id)
        #expect(first.pixelWidth == 8 && first.pixelHeight == 8)
    }

    @Test func emptyMalformedAndOversizedInputs() async throws {
        let importer = ChartImporter()
        let cases: [(Data, ImportFailure)] = [
            (Data(), .empty), (Data("not an image".utf8), .unsupported),
            (Data("%PDF-1.7\ntruncated".utf8), .malformed),
            (Data(repeating: 0, count: ChartImporter.maximumBytes + 1), .tooLarge)
        ]
        for (data, expected) in cases {
            do { _ = try await importer.decode(data: data, fileName: "chart.png"); Issue.record("Invalid input accepted") }
            catch { #expect(error as? ImportFailure == expected) }
        }
        do { _ = try await importer.decode(data: png(width: 20_001, height: 1), fileName: "wide.png"); Issue.record("Oversized dimensions accepted") }
        catch { #expect(error as? ImportFailure == .dimensions) }
    }

    @Test func multiplePagePDFIsNotSilentlyReduced() async throws {
        let data = NSMutableData()
        let consumer = try #require(CGDataConsumer(data: data))
        var bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
        let context = try #require(CGContext(consumer: consumer, mediaBox: &bounds, nil))
        for _ in 0..<2 { context.beginPDFPage(nil); context.endPDFPage() }
        context.closePDF()
        do { _ = try await ChartImporter().decode(data: data as Data, fileName: "chart.pdf"); Issue.record("Multiple pages silently accepted") }
        catch { #expect(error as? ImportFailure == .multiplePages) }
    }

    @Test func boundedFileReadAndNonFileURL() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ChartBridge-Import-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        try png().write(to: url, options: .atomic)
        let imported = try await ChartImporter().load(url: url)
        #expect(imported.source.mediaType == "image/png")
        try Data(repeating: 0, count: ChartImporter.maximumBytes + 1).write(to: url, options: .atomic)
        do { _ = try await ChartImporter().load(url: url); Issue.record("Oversized file accepted") }
        catch { #expect(error as? ImportFailure == .tooLarge) }
        do { _ = try await ChartImporter().load(url: URL(string: "https://example.invalid/chart.png")!); Issue.record("Remote URL accepted") }
        catch { #expect(error as? ImportFailure == .unreadable) }
    }

    @Test func cancelledImportDoesNotReturnAChart() async throws {
        let data = try png()
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ChartImporter().decode(data: data, fileName: "chart.png")
        }
        do { _ = try await task.value; Issue.record("Cancelled import returned a chart") }
        catch { #expect(error is CancellationError) }
    }
}

@Suite struct ChartReliabilityTests {
    @Test func missingBarGeometryCannotSilentlyDropARecognizedCategory() async throws {
        let bytes = try await SampleChartRenderer().render(.vertical)
        let chart = try await ChartImporter().decode(data: bytes, fileName: "synthetic.png")
        let ocr = try await VisionTextEngine().recognize(chart.previewPNG)
        let raster = try Raster(data: chart.previewPNG)
        let mask = try raster.foregroundMask(excluding: ocr.observations)
        let components = try raster.components(mask: mask)
        let rectangles = components.filter { $0.fill > 0.90 && $0.box.width > 0.015 && $0.box.height > 0.015 }
        #expect(rectangles.count == 3)
        let removed = try #require(rectangles.min(by: { $0.area < $1.area }))
        let incomplete = components.filter { $0.box != removed.box }
        do {
            _ = try BarExtractor.extract(vertical: true, raster: raster, components: incomplete, ocr: ocr, source: chart.source)
            Issue.record("Incomplete geometry must not quietly remove a recognized category")
        } catch let issue as ExtractionIssue { #expect(issue.message.contains("counts disagree")) }
    }
    @Test func missingUnitWhitespaceIsConsistentInComparisons() throws {
        let chart = try ChartInsightsTests().chart(["1", "3"], labels: ["A", "B"], unit: "  Not specified \n")
        let snapshot = try chart.trustedSnapshot()
        let insights = ChartCalculations.calculate(snapshot)
        let compared = ChartCalculations.compare(snapshot, from: insights.points[0].id, to: insights.points[1].id)
        #expect(insights.unit == .unspecified)
        #expect(compared[0].unit == .unspecified)
        #expect(ChartQuestionEngine(snapshot).answer("compare A and B").text == "B is 2 higher than A.")
    }

    @MainActor @Test func reportDeliveryRejectsSameRevisionDifferentData() async throws {
        let first = try ChartInsightsTests().chart(["1", "2"]).trustedSnapshot()
        let other = try ChartInsightsTests().chart(["8", "9"]).trustedSnapshot().copyForLibrary(id: first.id)
        #expect(InsightKey(first) == InsightKey(other))
        let report = try await ChartReportBuilder().prepare(first)
        let authorization = ReportAuthorization()
        authorization.synchronize(with: other)
        #expect(!authorization.isCurrent(first))
        #expect(throws: ChartReportError.self) { try authorization.data(for: report, pdf: false) }
        #expect(!ChartCalculations.calculate(first).isCurrent(for: other))
        #expect(!ChartExplorer(first).isCurrent(for: other))
        let explanation = ChartExplanation(snapshot: first, text: "Old trusted findings", origin: .deterministic, fallbackReason: nil)
        #expect(!explanation.isCurrent(for: other))
        #expect(VerifiedSpeechContent.explanation(explanation, snapshot: other) == nil)
        do {
            _ = try await ChartReportBuilder().prepare(other, explanation: explanation)
            Issue.record("An explanation from different same-key data must not be exported")
        } catch { #expect(error as? ChartReportError == .stale) }
        var playback = SpeechPlayback()
        playback.synchronize(first)
        let oldSpeech = VerifiedSpeechContent.chart(ChartExplorer(first))
        let started = playback.start(oldSpeech, requestID: UUID())
        #expect(started)
        let invalidated = playback.synchronize(other)
        #expect(invalidated && playback.content == nil && !playback.active)
        let restarted = playback.start(oldSpeech, requestID: UUID())
        #expect(!restarted)
        let newStarted = playback.start(VerifiedSpeechContent.chart(ChartExplorer(other)), requestID: UUID())
        #expect(newStarted)
    }

    @MainActor @Test func textExportDoesNotRenderAnUnusedPDF() async throws {
        let snapshot = try ChartInsightsTests().chart(["1", "2"]).trustedSnapshot()
        let builder = ChartReportBuilder(), date = Date(timeIntervalSince1970: 100)
        let textOnly = try await builder.prepare(snapshot, exportedAt: date, includePDF: false)
        let complete = try await builder.prepare(snapshot, exportedAt: date)
        #expect(textOnly.text == complete.text)
        #expect(textOnly.pdf.isEmpty && !complete.pdf.isEmpty)
        let authorization = ReportAuthorization(); authorization.synchronize(with: snapshot)
        #expect(try authorization.data(for: textOnly, pdf: false) == Data(complete.text.utf8))
        #expect(throws: ChartReportError.self) { try authorization.data(for: textOnly, pdf: true) }
    }

    @Test func libraryCannotSaveBeyondItsReadableCapacity() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ChartBridge-Capacity-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = ChartLibrary(directory: root)
        let original = try ChartLibraryTests().chart().trustedSnapshot()
        let saved = try await library.store(original)
        for _ in 1..<ChartLibrary.maximumRecords {
            try Data().write(to: root.appendingPathComponent(UUID().uuidString + ".json"))
        }
        let copy = original.copyForLibrary(id: UUID())
        do { _ = try await library.store(copy); Issue.record("A save must not make the library exceed its readable capacity") }
        catch { #expect(error as? ChartLibraryError == .tooLarge) }
        #expect(try await library.load(saved.id).digest == saved.digest)
        // Existing idempotent saves and explicit updates remain usable at capacity.
        #expect(try await library.store(original).digest == saved.digest)
        #expect(try await library.list().charts.count == 1)
        #expect(!FileManager.default.fileExists(atPath: root.appendingPathComponent(copy.id.uuidString + ".json").path))
    }
    @Test func cacheComparesAllTrustedDataNotOnlyRevision() throws {
        let id = UUID()
        func snapshot(_ value: String) throws -> BarChart.TrustedSnapshot {
            var chart = try BarChart(id: id, title: "Totals", horizontalAxis: "Category", verticalAxis: "Amount",
                unit: "items", source: SourceProvenance(fileName: "chart.png", mediaType: "image/png"), categories: [("A", 0)])
            try chart.edit(at: 0, text: value); try chart.confirm(at: 0)
            return try chart.trustedSnapshot()
        }
        let first = try snapshot("1"), other = try snapshot("9")
        #expect(InsightKey(first) == InsightKey(other))
        #expect(first != other)
        var cache = VerifiedInsightsCache()
        let original = cache.calculate(first).result(.total)?.summary
        #expect(cache.calculate(first).result(.total)?.summary == original)
        #expect(cache.calculate(other).result(.total)?.summary != original)
        #expect(cache.calculate(first).result(.total)?.summary == original)
    }

    @Test(arguments: ["list", "open", "save", "rename", "delete"])
    func cancelledLibraryOperationsPreserveRecord(_ operation: String) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ChartBridge-Cancellation-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let library = ChartLibrary(directory: root)
        let chart = try ChartLibraryTests().chart()
        let snapshot = try chart.trustedSnapshot()
        let saved = try await library.save(snapshot)
        let file = root.appendingPathComponent(saved.id.uuidString + ".json")
        let original = try Data(contentsOf: file)
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            switch operation {
            case "list": _ = try await library.list()
            case "open": _ = try await library.open(saved.id)
            case "save": _ = try await library.save(snapshot, replacing: saved.digest)
            case "rename": _ = try await library.rename(saved.id, title: "New title", expectedDigest: saved.digest)
            default: try await library.delete(saved.id, expectedDigest: saved.digest)
            }
        }
        do { try await task.value; Issue.record("Cancelled operation succeeded") }
        catch { #expect(error is CancellationError) }
        #expect(try Data(contentsOf: file) == original)
        #expect(try await library.open(saved.id).status == .userVerified)
    }

    @Test func libraryRejectsNonFileRoot() async throws {
        let library = ChartLibrary(directory: URL(string: "https://example.invalid/library")!)
        do { _ = try await library.list(); Issue.record("Non-file library root accepted") }
        catch { #expect(error as? ChartLibraryError == .unsafeFile) }
    }
}
