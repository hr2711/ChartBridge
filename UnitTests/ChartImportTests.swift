import Foundation
import Testing
import UniformTypeIdentifiers
import ImageIO

struct ChartImportTests {
    @Test func acceptsActualTypesAndBoundsPreview() async throws {
        let importer = ChartImporter()
        for type in [UTType.jpeg, .png] {
            let data = ImportFixtures.image(type: type, width: 2000, height: 1000)
            let result = try await importer.decode(data: data, fileName: "misleading.pdf")
            #expect(result.source.mediaType == (type == .png ? "image/png" : "image/jpeg"))
            #expect(result.originalData == data)
            #expect(result.pixelWidth <= 1600)
            #expect(result.pixelHeight <= 1600)
            #expect(!result.previewPNG.isEmpty)
        }
        let pdf = try await importer.decode(data: ImportFixtures.pdf(), fileName: "chart.png")
        #expect(pdf.source.mediaType == "application/pdf")
        #expect(pdf.source.page == 1)
    }

    @Test func rejectsUnsafeContent() async throws {
        let importer = ChartImporter()
        for (data, expected) in [
            (Data(), ImportFailure.empty),
            (Data(repeating: 0, count: ChartImporter.maximumBytes + 1), .tooLarge),
            (Data("not an image".utf8), .unsupported),
            (Data("%PDF-damaged".utf8), .malformed),
            (ImportFixtures.pdf(pages: 2), .multiplePages),
            (ImportFixtures.pdf(encrypted: true), .encrypted),
            (ImportFixtures.image(width: 20001, height: 1), .dimensions)
        ] {
            do {
                _ = try await importer.decode(data: data, fileName: "chart.png")
                Issue.record("Unsafe fixture was accepted")
            } catch {
                #expect(error as? ImportFailure == expected)
            }
        }
        let truncated = ImportFixtures.image().prefix(40)
        await #expect(throws: (any Error).self) {
            try await importer.decode(data: Data(truncated), fileName: "chart.png")
        }
    }

    @Test func readsLocalFileAndHandlesCancellation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("chart.png")
        let data = ImportFixtures.image()
        try data.write(to: url)
        let imported = try await ChartImporter().load(url: url)
        #expect(imported.originalData == data)
        let (gate, continuation) = AsyncStream<Void>.makeStream()
        let task = Task {
            for await _ in gate { break }
            return try await ChartImporter().load(url: url)
        }
        task.cancel()
        continuation.finish()
        do {
            _ = try await task.value
            Issue.record("Cancelled task succeeded")
        } catch { #expect(error is CancellationError) }
        await #expect(throws: ImportFailure.unreadable) {
            try await ChartImporter().load(url: directory.appendingPathComponent("absent.png"))
        }
    }
}
