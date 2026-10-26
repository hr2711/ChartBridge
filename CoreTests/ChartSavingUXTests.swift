import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import ChartBridgeMath
#endif

@Suite struct ChartSavingUXTests {
    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("ChartBridge-SaveUX-" + UUID().uuidString)
    }

    @Test func repeatedAndConcurrentSaveIsIdempotent() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let library = ChartLibrary(directory: root, clock: { Date(timeIntervalSince1970: 100) })
        let snapshot = try ChartLibraryTests().chart().trustedSnapshot()
        let first = try await library.store(snapshot)
        try await withThrowingTaskGroup(of: SavedChart.self) { group in
            for _ in 0..<8 { group.addTask { try await library.store(snapshot) } }
            for try await saved in group {
                #expect(saved.id == first.id && saved.digest == first.digest)
                #expect(saved.record.modifiedAt == first.record.modifiedAt)
            }
        }
        #expect(try await library.list().charts.count == 1)
        #expect(try await library.open(first.id).trustedSnapshot().values == snapshot.values)
    }

    @Test func changedChartNeedsExplicitUpdateAndStaleUpdatesFail() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let library = ChartLibrary(directory: root)
        var chart = try ChartLibraryTests().chart()
        let first = try await library.store(chart.trustedSnapshot())
        try chart.edit(at: 1, text: "42")
        #expect(throws: ChartValidationError.self) { try chart.trustedSnapshot() }
        try chart.confirm(at: 1)
        let changed = try chart.trustedSnapshot()
        do { _ = try await library.store(changed); Issue.record("Changed chart silently overwrote a saved record") }
        catch { #expect(error as? ChartLibraryError == .duplicate) }
        #expect(try await library.open(chart.id).trustedSnapshot().values[1].value == 10)
        let updated = try await library.store(changed, intent: .update(expectedDigest: first.digest))
        #expect(updated.id == first.id && updated.digest != first.digest)
        #expect(try await library.list().charts.count == 1)
        #expect(try await library.open(chart.id).trustedSnapshot().values[1].value == 42)
        do {
            _ = try await library.store(changed, intent: .update(expectedDigest: first.digest))
            Issue.record("Stale update accepted")
        } catch { #expect(error as? ChartLibraryError == .conflict) }
    }

    @Test func separateCopyPreservesOriginalAndRetryDoesNotDuplicate() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let library = ChartLibrary(directory: root)
        var chart = try ChartLibraryTests().chart()
        let original = try await library.store(chart.trustedSnapshot())
        try chart.edit(at: 1, text: "99"); try chart.confirm(at: 1)
        let snapshot = try chart.trustedSnapshot(), copyID = UUID()
        let copy = try await library.store(snapshot, intent: .copy(id: copyID))
        let retried = try await library.store(snapshot, intent: .copy(id: copyID))
        #expect(copy.id == copyID && copy.id != original.id && retried.digest == copy.digest)
        #expect(try await library.list().charts.count == 2)
        #expect(try await library.open(original.id).trustedSnapshot().values[1].value == 10)
        let reopened = try await library.open(copy.id).trustedSnapshot()
        #expect(reopened.values == snapshot.values && reopened.title == snapshot.title)
        #expect(reopened.id == copyID)
    }

    @Test func failedSaveProducesNoRecordOrFalseSuccess() async throws {
        let root = directory(); defer { try? FileManager.default.removeItem(at: root) }
        let library = ChartLibrary(directory: root, writer: FailingWriter())
        let snapshot = try ChartLibraryTests().chart().trustedSnapshot()
        do { _ = try await library.store(snapshot); Issue.record("Failed save returned success") }
        catch { #expect(error as? ChartLibraryError == .storage) }
        #expect(try await library.list().charts.isEmpty)
    }

    @Test func libraryNavigationReopensExactlyOneChart() {
        var state = LibraryNavigation()
        #expect(state.tab == .home && state.chartPath.isEmpty)
        let first = UUID(), second = UUID()
        state.openChart(first); state.openChart(first)
        #expect(state.tab == .charts && state.chartPath == [first])
        state.openChart(second)
        #expect(state.chartPath == [second])
        state.tab = .help
        state.showLibrary()
        #expect(state.tab == .charts && state.chartPath.isEmpty)
    }

    @Test func switchingTabsDoesNotResetAnOpenChart() {
        var state = LibraryNavigation()
        let id = UUID()
        state.openChart(id)
        state.tab = .home
        state.tab = .help
        state.tab = .charts
        #expect(state.chartPath == [id])
        state.showLibrary()
        #expect(state.chartPath.isEmpty, "Only an explicit library-root action clears the chart path")
    }
    private struct FailingWriter: ChartFileWriting {
        func write(_ data: Data, to url: URL) throws { throw CocoaError(.fileWriteOutOfSpace) }
    }
}
