import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import ChartBridgeMath
#endif

@Suite struct ChartAccessibilityTests {
    func chart(_ values: [String] = ["10", "30", "30"], kind: ChartKind = .verticalBar) throws -> BarChart {
        var chart = try BarChart(kind: kind, title: "Community results", horizontalAxis: "Category", verticalAxis: "Value",
            unit: kind == .pie ? "%" : "participants", source: SourceProvenance(fileName: "private.png", mediaType: "image/png"),
            categories: values.indices.map { ("Category \($0 + 1)", $0) })
        for index in values.indices { try chart.edit(at: index, text: values[index]); try chart.confirm(at: index) }
        return chart
    }

    @Test(arguments: ChartKind.allCases)
    func navigationAndOrdering(_ kind: ChartKind) throws {
        var explorer = ChartExplorer(try chart(kind == .pie ? ["20", "40", "40"] : ["10", "30", "30"], kind: kind).trustedSnapshot())
        #expect(explorer.current == nil)
        #expect(!explorer.canMovePrevious && explorer.canMoveNext)
        explorer.previous()
        #expect(explorer.current == nil)
        explorer.next()
        #expect(explorer.selectedIndex == 0 && !explorer.canMovePrevious)
        #expect(explorer.current?.description.contains("Item 1 of 3") == true)
        explorer.next(); explorer.next(); explorer.next()
        #expect(explorer.selectedIndex == 2 && !explorer.canMoveNext)
        explorer.previous()
        #expect(explorer.selectedIndex == 1)
        #expect(explorer.points.map(\.id.order) == [0, 1, 2])
        explorer.returnToSummary()
        #expect(explorer.current == nil)
        #expect(explorer.summary.contains(kind.rawValue))
        #expect(explorer.entireChart.contains("Ordered verified data"))
    }

    @Test func extremaTiesAndSinglePoint() throws {
        var explorer = ChartExplorer(try chart().trustedSnapshot())
        explorer.jumpToLargest()
        #expect(explorer.selectedIndex == 1 && explorer.largestOrders == [1, 2])
        #expect(explorer.current?.description.contains("Tied for highest") == true)
        explorer.jumpToSmallest()
        #expect(explorer.selectedIndex == 0 && explorer.current?.description.contains("Lowest value") == true)
        var single = ChartExplorer(try chart(["0"]).trustedSnapshot())
        single.next(); single.next(); single.previous()
        #expect(single.selectedIndex == 0)
        #expect(!single.canMoveNext && !single.canMovePrevious)
        #expect(single.current?.description.contains("Highest value") == true)
        #expect(single.current?.description.contains("Lowest value") == true)
    }

    @Test func lineDescriptionsUseOnlyObservedChanges() throws {
        var explorer = ChartExplorer(try chart(["10", "17", "17", "-2"], kind: .line).trustedSnapshot())
        explorer.next()
        #expect(explorer.current?.description.contains("First observed point") == true)
        explorer.next()
        #expect(explorer.current?.description.contains("7 participants more than Category 1") == true)
        #expect(explorer.current?.description.contains("not behavior between them") == true)
        explorer.next()
        #expect(explorer.current?.description.contains("Unchanged from Category 2") == true)
        explorer.next()
        #expect(explorer.current?.description.contains("19 participants fewer than Category 3") == true)
        #expect(explorer.current?.description.contains("Last observed point") == true)
        #expect(explorer.summary.contains("Net observed change"))
        #expect(!explorer.current!.description.contains("per day"))
    }

    @Test func pieWordingAndInconsistentRestriction() throws {
        var explorer = ChartExplorer(try chart(["20", "40", "40"], kind: .pie).trustedSnapshot())
        explorer.next(); explorer.next()
        #expect(explorer.current?.description.contains("40 percent") == true)
        #expect(explorer.current?.description.contains("20 percentage points more") == true)
        #expect(explorer.summary.contains("not normalized"))
        #expect(throws: ChartValidationError.self) { try chart(["20", "30"], kind: .pie).trustedSnapshot() }
    }

    @Test func trustAndImmediateSpeechInvalidation() throws {
        var chart = try chart()
        let snapshot = try chart.trustedSnapshot()
        var explorer = ChartExplorer(snapshot)
        explorer.next()
        let point = try #require(VerifiedSpeechContent.point(explorer))
        var playback = SpeechPlayback()
        playback.synchronize(snapshot)
        let oldRequest = UUID()
        let accepted1 = playback.start(point, requestID: oldRequest)
        #expect(accepted1)
        try chart.edit(at: 0, text: "11")
        let invalidSnapshot = try? chart.trustedSnapshot()
        #expect(!explorer.isCurrent(for: invalidSnapshot))
        playback.synchronize(invalidSnapshot)
        #expect(playback.content == nil && playback.requestID == nil && playback.state == .idle)
        playback.receive(.finished, requestID: oldRequest)
        #expect(playback.state == .idle)
        let accepted2 = playback.start(point, requestID: UUID())
        #expect(!accepted2)
        try chart.confirm(at: 0)
        let changed = try chart.trustedSnapshot()
        #expect(!explorer.isCurrent(for: changed))
        playback.synchronize(changed)
        let accepted3 = playback.start(point, requestID: UUID())
        #expect(!accepted3)
        let explanation = ChartExplanation(snapshot: snapshot, text: "Old explanation", origin: .deterministic, fallbackReason: nil)
        #expect(VerifiedSpeechContent.explanation(explanation, snapshot: changed) == nil)
        try chart.reject(at: 1)
        #expect(throws: ChartValidationError.self) { try chart.trustedSnapshot() }
    }

    @Test func speechStateTransitionsAndDuplicateRequests() throws {
        let explorer = ChartExplorer(try chart().trustedSnapshot())
        let content = VerifiedSpeechContent.chart(explorer)
        var playback = SpeechPlayback()
        let accepted4 = playback.start(content, requestID: UUID())
        #expect(!accepted4)
        playback.synchronize(explorer.insights.snapshot)
        let first = UUID()
        let accepted5 = playback.start(content, requestID: first)
        #expect(accepted5 && playback.state == .speaking)
        let accepted6 = playback.start(content, requestID: UUID())
        #expect(!accepted6)
        playback.receive(.paused, requestID: first)
        #expect(playback.state == .paused)
        playback.receive(.started, requestID: first)
        #expect(playback.state == .paused, "Late start callback cannot undo pause")
        playback.receive(.resumed, requestID: first)
        #expect(playback.state == .speaking)
        playback.receive(.finished, requestID: first)
        #expect(playback.state == .completed && playback.content == content)
        let replay = UUID()
        let accepted7 = playback.start(content, requestID: replay)
        #expect(accepted7)
        playback.receive(.cancelled, requestID: first)
        #expect(playback.state == .speaking)
        playback.stop()
        #expect(playback.state == .stopped && !playback.active)
        playback.receive(.finished, requestID: replay)
        #expect(playback.state == .stopped)
    }

    @Test func speechReplacementAndInterruptionNeverAutoResume() throws {
        var explorer = ChartExplorer(try chart().trustedSnapshot())
        explorer.next()
        var playback = SpeechPlayback()
        playback.synchronize(explorer.insights.snapshot)
        let chartContent = VerifiedSpeechContent.chart(explorer)
        let pointContent = try #require(VerifiedSpeechContent.point(explorer))
        let first = UUID(), second = UUID()
        let accepted8 = playback.start(chartContent, requestID: first)
        #expect(accepted8)
        let accepted9 = playback.start(pointContent, requestID: second)
        #expect(accepted9)
        playback.receive(.cancelled, requestID: first)
        #expect(playback.content == pointContent && playback.state == .speaking)
        playback.stop(interrupted: true)
        #expect(playback.state == .interrupted && playback.requestID == nil)
        playback.receive(.resumed, requestID: second)
        #expect(playback.state == .interrupted)
        let accepted10 = playback.start(pointContent, requestID: UUID())
        #expect(accepted10, "Explicit replay remains possible after interruption")
    }

    @Test func speechPayloadSeparatesNaturalContentFromTechnicalMetadata() throws {
        let snapshot = try chart().trustedSnapshot()
        let explorer = ChartExplorer(snapshot)
        let whole = VerifiedSpeechContent.chart(explorer)
        #expect(whole.text == explorer.naturalSummary)
        #expect(!whole.text.contains(snapshot.kind.rawValue))
        #expect(!whole.text.contains("Total") && !whole.text.contains("Confirmed by you"))
        #expect(whole.text.contains("Category 2") && whole.text.contains("participants"))
        #expect(explorer.summary.contains(snapshot.title) && explorer.summary.contains(snapshot.kind.rawValue), "Technical information remains available separately")
        #expect(!whole.text.contains("private.png"))
        #expect(VerifiedSpeechContent.point(explorer) == nil)
        let explanation = ChartExplanation(snapshot: snapshot, text: "Confirmed findings.", origin: .appleIntelligenceAssisted, fallbackReason: nil)
        let spoken = try #require(VerifiedSpeechContent.explanation(explanation, snapshot: snapshot))
        #expect(spoken.text == explanation.text)
        #expect(explanation.attribution.contains("Apple Intelligence assisted on this device"), "Attribution remains in the interface, not prepended to speech")
    }
}
