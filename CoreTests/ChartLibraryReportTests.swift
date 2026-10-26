import Foundation
import Testing
import CryptoKit
import PDFKit
#if SWIFT_PACKAGE
@testable import ChartBridgeMath
#endif

@Suite struct ChartLibraryTests {
    func directory() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("ChartBridge-Test-" + UUID().uuidString, isDirectory: true) }
    func chart(_ kind: ChartKind = .verticalBar) throws -> BarChart {
        var chart = try BarChart(kind: kind, title: "Community totals", horizontalAxis: "Category", verticalAxis: "Amount",
            unit: kind == .pie ? "%" : "USD", source: SourceProvenance(fileName: "private-original.png", mediaType: "image/png"),
            categories: [("First", 0), ("Second", 1)])
        try chart.proposeEstimate(at: 0, text: kind == .pie ? "20" : "-5")
        try chart.confirm(at: 0)
        try chart.edit(at: 1, text: kind == .pie ? "80" : "10")
        try chart.confirm(at: 1)
        return chart
    }

    @Test(arguments: ChartKind.allCases)
    func saveReopenRoundTrip(_ kind: ChartKind) async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let library = ChartLibrary(directory: root, clock: { Date(timeIntervalSince1970: 1_000) })
        let original = try chart(kind).trustedSnapshot()
        let saved = try await library.save(original)
        let reopened = try await library.open(saved.id, expectedDigest: saved.digest)
        let snapshot = try reopened.trustedSnapshot()
        #expect(snapshot.id == original.id && snapshot.revision == original.revision)
        #expect(snapshot.kind == kind && snapshot.title == original.title && snapshot.unit == original.unit)
        #expect(snapshot.values.map(\.value) == original.values.map(\.value))
        #expect(snapshot.values[0].confirmedCandidate.origin == .geometricEstimate)
        let allExplicitlyConfirmed = saved.record.points.allSatisfy { $0.explicitlyConfirmed }
        #expect(allExplicitlyConfirmed)
        #expect(saved.record.createdAt == Date(timeIntervalSince1970: 1_000))
        #expect(try await library.list().charts.count == 1)
        let bytes = try Data(contentsOf: root.appendingPathComponent(saved.id.uuidString + ".json"))
        #expect(!String(decoding: bytes, as: UTF8.self).contains("private-original.png"))
        #expect(try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).count == 1)
    }

    @Test func duplicateReplacementRenameAndDelete() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let library = ChartLibrary(directory: root, clock: { Date(timeIntervalSince1970: 2_000) })
        var chart = try chart()
        let saved = try await library.save(chart.trustedSnapshot())
        do { try await library.save(chart.trustedSnapshot()); Issue.record("Duplicate insert accepted") }
        catch { #expect(error as? ChartLibraryError == .duplicate) }
        try chart.edit(at: 1, text: "12.5"); try chart.confirm(at: 1)
        let updated = try await library.save(chart.trustedSnapshot(), replacing: saved.digest)
        #expect(updated.digest != saved.digest && updated.record.createdAt == saved.record.createdAt)
        do { try await library.save(chart.trustedSnapshot(), replacing: saved.digest); Issue.record("Stale replacement accepted") }
        catch { #expect(error as? ChartLibraryError == .conflict) }
        let renamed = try await library.rename(saved.id, title: "Renamed results", expectedDigest: updated.digest)
        let reopened = try await library.open(saved.id)
        #expect(reopened.title == "Renamed results")
        #expect(reopened.status == .userVerified && reopened.revision > chart.revision)
        #expect(try reopened.trustedSnapshot().values[1].value == Decimal(string: "12.5"))
        do { try await library.delete(saved.id, expectedDigest: updated.digest); Issue.record("Stale delete accepted") }
        catch { #expect(error as? ChartLibraryError == .conflict) }
        try await library.delete(saved.id, expectedDigest: renamed.digest)
        #expect(try await library.list().charts.isEmpty)
        do { _ = try await library.open(saved.id); Issue.record("Deleted record reopened") }
        catch { #expect(error as? ChartLibraryError == .missing) }
    }

    @Test func corruptAndUnsupportedRecordsAreRetained() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let library = ChartLibrary(directory: root)
        let saved = try await library.save(chart().trustedSnapshot())
        let file = root.appendingPathComponent(saved.id.uuidString + ".json")
        let original = try Data(contentsOf: file)
        try Data("malformed JSON".utf8).write(to: file, options: .atomic)
        var listing = try await library.list()
        #expect(listing.charts.isEmpty && listing.issues.count == 1)
        #expect(FileManager.default.fileExists(atPath: file.path))
        var object = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        var record = try #require(object["record"] as? [String: Any])
        record["schemaVersion"] = 99; object["record"] = record
        try JSONSerialization.data(withJSONObject: object).write(to: file, options: .atomic)
        do { _ = try await library.open(saved.id); Issue.record("Unknown schema trusted") }
        catch { #expect(error as? ChartLibraryError == .incompatible) }
        record["schemaVersion"] = 1
        var points = try #require(record["points"] as? [[String: Any]])
        points[0]["explicitlyConfirmed"] = false
        record["points"] = points
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .secondsSince1970
        let decoded = try decoder.decode(SavedChartRecord.self, from: JSONSerialization.data(withJSONObject: record))
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; encoder.dateEncodingStrategy = .secondsSince1970
        object["record"] = record
        object["sha256"] = SHA256.hash(data: try encoder.encode(decoded)).map { String(format: "%02x", $0) }.joined()
        try JSONSerialization.data(withJSONObject: object).write(to: file, options: .atomic)
        do { _ = try await library.open(saved.id); Issue.record("Unconfirmed record trusted") }
        catch { #expect(error as? ChartLibraryError == .corrupt) }
        listing = try await library.list()
        #expect(listing.charts.isEmpty && !listing.issues.isEmpty)
    }

    @Test func failedAtomicWritePreservesExistingRecord() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let good = ChartLibrary(directory: root)
        var chart = try chart()
        let saved = try await good.save(chart.trustedSnapshot())
        let original = try Data(contentsOf: root.appendingPathComponent(saved.id.uuidString + ".json"))
        try chart.edit(at: 1, text: "99"); try chart.confirm(at: 1)
        let failing = ChartLibrary(directory: root, writer: FailingWriter())
        do { try await failing.save(chart.trustedSnapshot(), replacing: saved.digest); Issue.record("Injected failure ignored") }
        catch { #expect(error as? ChartLibraryError == .storage) }
        #expect(try Data(contentsOf: root.appendingPathComponent(saved.id.uuidString + ".json")) == original)
        #expect(try await good.open(saved.id).trustedSnapshot().values[1].value == 10)
    }

    @Test func checksumAndSymbolicLinkRejection() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let library = ChartLibrary(directory: root)
        let snapshot = try chart().trustedSnapshot()
        let saved = try await library.save(snapshot)
        let file = root.appendingPathComponent(saved.id.uuidString + ".json")
        let original = try Data(contentsOf: file)
        var object = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
        object["sha256"] = "incorrect"
        try JSONSerialization.data(withJSONObject: object).write(to: file)
        do { _ = try await library.load(saved.id); Issue.record("Bad checksum accepted") }
        catch { #expect(error as? ChartLibraryError == .corrupt) }
        try FileManager.default.removeItem(at: file)
        let linkTarget = root.appendingPathComponent("synthetic-target")
        try original.write(to: linkTarget)
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: linkTarget)
        do { _ = try await library.load(saved.id); Issue.record("Symbolic link accepted") }
        catch { #expect(error as? ChartLibraryError == .unsafeFile) }
        try FileManager.default.removeItem(at: file)
        let missingTarget = root.appendingPathComponent("missing-target")
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: missingTarget)
        do { try await library.save(snapshot); Issue.record("Broken link accepted for save") }
        catch { #expect(error as? ChartLibraryError == .unsafeFile) }
        #expect(!FileManager.default.fileExists(atPath: missingTarget.path))
    }
}
private struct FailingWriter: ChartFileWriting {
    func write(_ data: Data, to url: URL) throws { throw ChartLibraryError.storage }
}

@Suite struct ChartReportTests {
    func chart() throws -> BarChart {
        var chart = try BarChart(title: "Accessible results", horizontalAxis: "Category", verticalAxis: "Amount", unit: "USD",
            source: SourceProvenance(fileName: "never-export-this-path.png", mediaType: "image/png"),
            categories: [("First", 0), ("Second", 1)])
        try chart.edit(at: 0, text: "-2.5"); try chart.confirm(at: 0)
        try chart.edit(at: 1, text: "12.5"); try chart.confirm(at: 1)
        return chart
    }

    @MainActor @Test func reportsAndLiveStaleAuthorization() async throws {
        var chart = try chart()
        let snapshot = try chart.trustedSnapshot(), builder = ChartReportBuilder()
        let date = Date(timeIntervalSince1970: 1_000)
        let report = try await builder.prepare(snapshot, exportedAt: date)
        let again = try await builder.prepare(snapshot, exportedAt: date)
        #expect(report.text == again.text)
        #expect(report.text.contains("-2.50 USD") && report.text.contains("12.50 USD"))
        #expect(report.text.contains("Total: 10 USD"))
        #expect(!report.text.contains("never-export-this-path.png"))
        let document = try #require(PDFDocument(data: report.pdf))
        #expect(document.pageCount > 0)
        #expect(document.string?.contains("Accessible results") == true)
        #expect(document.string?.contains("12.50") == true)
        let authorization = ReportAuthorization()
        authorization.synchronize(with: snapshot)
        #expect(try authorization.data(for: report, pdf: false) == Data(report.text.utf8))
        try chart.edit(at: 0, text: "8")
        authorization.synchronize(with: try? chart.trustedSnapshot())
        #expect(throws: ChartReportError.self) { try authorization.data(for: report, pdf: true) }
        try chart.confirm(at: 0)
        authorization.synchronize(with: try chart.trustedSnapshot())
        #expect(throws: ChartReportError.self) { try authorization.data(for: report, pdf: false) }
        let updated = try await builder.prepare(chart.trustedSnapshot(), exportedAt: date)
        #expect(updated.text.contains("8 USD") && !updated.text.contains("-2.50 USD"))
        #expect(try authorization.data(for: updated, pdf: true).starts(with: Data("%PDF".utf8)))
        try chart.reject(at: 1)
        #expect(throws: ChartValidationError.self) { try chart.trustedSnapshot() }
    }

    @MainActor @Test func paginationAndStaleExplanationRejection() async throws {
        var chart = try BarChart(title: "Long report", horizontalAxis: "Categories", verticalAxis: "Amount", unit: "items",
            source: SourceProvenance(fileName: "synthetic.png", mediaType: "image/png"),
            categories: (0..<45).map { ("Category \($0) with a long descriptive label to exercise wrapping and page breaks", $0) })
        for index in chart.categories.indices { try chart.edit(at: index, text: String(index)); try chart.confirm(at: index) }
        let old = try chart.trustedSnapshot()
        let report = try await ChartReportBuilder().prepare(old, exportedAt: Date(timeIntervalSince1970: 1_000))
        let pdf = try #require(PDFDocument(data: report.pdf))
        #expect(pdf.pageCount > 1)
        #expect(pdf.string?.contains("Category 44") == true)
        let stale = ChartExplanation(snapshot: old, text: "Old facts", origin: .deterministic, fallbackReason: nil)
        try chart.edit(at: 0, text: "99"); try chart.confirm(at: 0)
        do { _ = try await ChartReportBuilder().prepare(chart.trustedSnapshot(), explanation: stale); Issue.record("Stale explanation exported") }
        catch { #expect(error as? ChartReportError == .stale) }
    }
}
