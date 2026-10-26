import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import ChartBridgeMath
#endif

@Suite struct ChartInsightsTests {
    func chart(_ values: [String], kind: ChartKind = .verticalBar, labels: [String]? = nil, unit: String? = nil) throws -> BarChart {
        var chart = try BarChart(kind: kind, title: "Verified example", horizontalAxis: "Category", verticalAxis: "Value",
            unit: unit ?? (kind == .pie ? "%" : "USD"),
            source: SourceProvenance(fileName: "private-original.png", mediaType: "image/png"),
            categories: values.indices.map { (labels?[$0] ?? "Point \($0)", $0) })
        for i in values.indices { try chart.edit(at: i, text: values[i]); try chart.confirm(at: i) }
        return chart
    }

    @Test(arguments: [ChartKind.verticalBar, .horizontalBar])
    func barsAndStableTies(_ kind: ChartKind) throws {
        let snapshot = try chart(["-2", "0", "4", "4"], kind: kind).trustedSnapshot()
        let report = ChartCalculations.calculate(snapshot)
        #expect(report.result(.total)?.number?.exactValue == 6)
        #expect(report.result(.mean)?.number?.exactValue == Decimal(string: "1.5"))
        #expect(report.result(.minimum)?.number?.value == -2)
        #expect(report.result(.maximum)?.number?.value == 4)
        guard case .available(.points(let largest))? = report.result(.largest)?.availability,
              case .available(.ranking(let ranks))? = report.result(.descending)?.availability else {
            Issue.record("Expected typed tied ranking"); return
        }
        #expect(largest.map(\.order) == [2, 3])
        #expect(ranks.map(\.rank) == [1, 3, 4])
        #expect(ranks[0].points.map(\.order) == [2, 3])
        #expect(report.unit == .chart("USD"))
        #expect(report.result(.count)?.unit == CalculationUnit.none)
        #expect(report.points.map(\.id.order) == [0, 1, 2, 3])
        let compared = ChartCalculations.compare(snapshot, from: report.points[1].id, to: report.points[2].id)
        #expect(compared[0].number?.value == 4)
        if case .unavailable(.zeroBaseline) = compared[1].availability {} else { Issue.record("Zero baseline must be unavailable") }
        let negative = ChartCalculations.compare(snapshot, from: report.points[0].id, to: report.points[2].id)
        if case .unavailable(.negativeBaseline) = negative[1].availability {} else { Issue.record("Negative baseline policy must be explicit") }
        let relative = ChartCalculations.compare(snapshot, from: report.points[2].id, to: report.points[0].id)
        #expect(relative[1].number?.value == -150)
        #expect(ChartCalculations.calculate(snapshot).results.map(\.id) == report.results.map(\.id))
    }

    @Test func negativeTotalsSingleValueAndSmallDecimals() throws {
        let negative = ChartCalculations.calculate(try chart(["-4", "-6"]).trustedSnapshot())
        #expect(negative.result(.total)?.number?.value == -10)
        let single = ChartCalculations.calculate(try chart(["0.000000000000000000000000001"]).trustedSnapshot())
        #expect(single.result(.total)?.number?.exactValue == Decimal(string: "0.000000000000000000000000001"))
        #expect(single.result(.mean)?.number?.exactValue == single.points[0].value)
        let large = ChartCalculations.calculate(try chart(["9999999999999999999999999999", "1"]).trustedSnapshot())
        #expect(large.result(.total)?.number?.value == Decimal(string: "10000000000000000000000000000"))
        let unknown = ChartCalculations.calculate(try chart(["1"], unit: "Not specified").trustedSnapshot())
        #expect(unknown.unit == .unspecified)
        #expect(unknown.result(.total)?.summary.contains("units not specified") == true)
        let repeating = ChartCalculations.calculate(try chart(["1", "0", "0"]).trustedSnapshot())
        #expect(repeating.result(.mean)?.number?.precision == .rounded)
        #expect(repeating.result(.mean)?.number?.exactValue == nil)
    }

    @Test func observedLineChangesAndAmbiguousX() throws {
        let report = ChartCalculations.calculate(try chart(["10", "15", "15", "12"], kind: .line, labels: ["1", "1.0", "8", "100"]).trustedSnapshot())
        #expect(report.result(.first)?.number?.value == 10)
        #expect(report.result(.last)?.number?.value == 12)
        #expect(report.result(.netChange)?.number?.value == 2)
        #expect(report.result(.relativeChange)?.number?.value == 20)
        if case .available(.trend(.mixed))? = report.result(.trend)?.availability {} else { Issue.record("Expected mixed observed trend") }
        if case .available(.steps(let steps))? = report.result(.largestIncrease)?.availability {
            #expect(steps.count == 1); #expect(steps[0].change.value == 5)
            #expect(steps[0].from.order == 0 && steps[0].to.order == 1)
        } else { Issue.record("Expected largest observed increase") }
        if case .available(.steps(let steps))? = report.result(.largestDecrease)?.availability {
            #expect(steps[0].change.value == -3)
        } else { Issue.record("Expected observed decrease") }
        if case .unavailable(.ambiguousX)? = report.result(.xBasedRate)?.availability {} else { Issue.record("Numerically repeated x labels must be explained") }
        #expect(report.scope.contains("No intermediate behavior"))
    }

    @Test func lineTrendBoundariesAndTiedSteps() throws {
        for (values, expected) in [(["1", "1", "2"], ObservedTrend.increasing), (["3", "2", "2"], .decreasing), (["0", "0"], .constant)] {
            let report = ChartCalculations.calculate(try chart(values, kind: .line).trustedSnapshot())
            if case .available(.trend(let trend))? = report.result(.trend)?.availability { #expect(trend == expected) }
            else { Issue.record("Expected an observed trend") }
        }
        let tied = ChartCalculations.calculate(try chart(["0", "2", "4"], kind: .line).trustedSnapshot())
        if case .available(.steps(let steps)) = tied.result(.largestIncrease)?.availability { #expect(steps.count == 2) }
        else { Issue.record("Expected tied consecutive increases") }
        if case .unavailable(.zeroBaseline) = tied.result(.relativeChange)?.availability {} else { Issue.record("Zero start") }
        let single = ChartCalculations.calculate(try chart(["5"], kind: .line).trustedSnapshot())
        if case .unavailable(.insufficientPoints) = single.result(.trend)?.availability {} else { Issue.record("One observation cannot establish trend") }
        let negative = ChartCalculations.calculate(try chart(["-5", "-2"], kind: .line).trustedSnapshot())
        if case .unavailable(.negativeBaseline) = negative.result(.relativeChange)?.availability {} else { Issue.record("Negative start") }
    }

    @Test func pieTotalsAndPercentagePoints() throws {
        let snapshot = try chart(["40", "40", "20"], kind: .pie).trustedSnapshot()
        let report = ChartCalculations.calculate(snapshot)
        #expect(report.result(.pieTotal)?.number?.value == 100)
        if case .available(.pieConsistency(_, let valid))? = report.result(.pieConsistency)?.availability { #expect(valid) }
        else { Issue.record("Expected pie consistency") }
        let comparison = ChartCalculations.compare(snapshot, from: report.points[0].id, to: report.points[2].id)
        #expect(comparison[0].number?.value == 20)
        #expect(comparison[1].operation == .percentagePointDifference)
        #expect(comparison[1].number?.value == -20 && comparison[1].unit == .percentagePoints)
        if case .unavailable(.percentageComparison) = comparison[2].availability {} else { Issue.record("No relative pie percent") }
        if case .unavailable(.physicalTotal)? = report.result(.physicalTotal)?.availability {} else { Issue.record("No invented physical total") }
        #expect(throws: ChartValidationError.self) { try chart(["40", "59.4"], kind: .pie).trustedSnapshot() }
        let rounded = ChartCalculations.calculate(try chart(["40", "59.5"], kind: .pie).trustedSnapshot())
        #expect(rounded.result(.pieTotal)?.number?.value == Decimal(string: "99.5"))
        #expect(throws: ChartValidationError.self) { try chart(["101"], kind: .pie) }
    }

    @Test func trustBoundaryAndStaleInvalidation() throws {
        var c = try chart(["1", "2"])
        let snapshot = try c.trustedSnapshot()
        let report = ChartCalculations.calculate(snapshot)
        #expect(report.isCurrent(for: snapshot))
        try c.edit(at: 0, text: "3")
        #expect(!report.isCurrent(for: try? c.trustedSnapshot()))
        try c.confirm(at: 0)
        #expect(!report.isCurrent(for: try c.trustedSnapshot()))
        let after = ChartCalculations.calculate(try c.trustedSnapshot())
        c.updateTitle("Changed")
        #expect(!after.isCurrent(for: try? c.trustedSnapshot()))
        for i in c.categories.indices { try c.confirm(at: i) }
        try c.reject(at: 1)
        #expect(throws: ChartValidationError.self) { try c.trustedSnapshot() }
        #expect(throws: ChartValidationError.self) { try chart([]) }
        #expect(throws: ChartValidationError.self) { try chart(["1"], unit: "") }
        #expect(throws: ChartValidationError.self) { try chart(["1", "2"], labels: ["A", "A"]) }
        let alien = CalculationPoint.ID(chartID: UUID(), order: 0)
        let invalid = ChartCalculations.compare(snapshot, from: alien, to: report.points[0].id)
        if case .unavailable(.unknownPoint) = invalid[0].availability {} else { Issue.record("Foreign point accepted") }
    }

    @Test func checkedArithmeticNeverPublishesNonfiniteValues() throws {
        if case .failure(.overflow) = CheckedDecimal.calculate(Decimal(string: "1e127")!, 100, .multiply) {} else { Issue.record("Overflow must be unavailable") }
        if case .failure(.underflow) = CheckedDecimal.calculate(Decimal(string: "1e-128")!, 100, .divide) {} else { Issue.record("Underflow must be unavailable") }
        if case .failure(.invalidData) = CheckedDecimal.calculate(.nan, 1, .add) {} else { Issue.record("NaN must be rejected") }
        if case .failure(.zeroBaseline) = CheckedDecimal.calculate(1, 0, .divide) {} else { Issue.record("Division by zero") }
    }

    @Test(arguments: ChartKind.allCases)
    func deterministicFallbackAndPrivateInput(_ kind: ChartKind) async throws {
        let snapshot = try chart(kind == .pie ? ["40", "60"] : ["10", "20"], kind: kind).trustedSnapshot()
        let provider = MockExplanationProvider(state: .unavailable(.deviceUnsupported))
        let service = ChartExplanationService()
        let first = try await service.explain(snapshot, provider: provider)
        let second = try await service.explain(snapshot, provider: provider)
        #expect(first.text == second.text)
        #expect(first.origin == .deterministic && first.fallbackReason == .deviceUnsupported)
        let expected = ExplanationPayload.meaning(ChartCalculations.calculate(snapshot))
        #expect(first.text == expected.renderMeaning(Array(expected.facts.prefix(4))))
        let payload = ExplanationPayload.prepare(ChartCalculations.calculate(snapshot))
        let encoded = try payload.encoded()
        #expect(!encoded.contains("private-original.png"))
        let object = try #require(JSONSerialization.jsonObject(with: Data(encoded.utf8)) as? [String: Any])
        #expect(Set(object.keys) == Set(["title", "chartType", "unit", "points", "facts", "requiredFactIDs", "scope"]))
        #expect(!encoded.contains("confirmedCandidate") && !encoded.contains("rawText") && !encoded.contains("\"sourceID\""))
        #expect(await provider.calls == 0)
    }

    @Test func structuredAIValidationAndFallback() async throws {
        let snapshot = try chart(["10", "20"]).trustedSnapshot()
        let payload = ExplanationPayload.meaning(ChartCalculations.calculate(snapshot))
        let required = payload.requiredFactIDs
        #expect(payload.validatedSelection([]) == nil)
        #expect(payload.validatedSelection(required + [required[0]]) == nil)
        #expect(payload.validatedSelection(required + ["invented total 999"]) == nil)
        #expect(payload.validatedSelection(["count"]) == nil)
        let service = ChartExplanationService()
        let accepted = try await service.explain(snapshot, provider: MockExplanationProvider(ids: required))
        #expect(accepted.origin == .appleIntelligenceAssisted)
        #expect(accepted.text == payload.renderMeaning(try #require(payload.validatedSelection(required))))
        for ids in [[], required + ["unknown-category-900"]] {
            let rejected = try await service.explain(snapshot, provider: MockExplanationProvider(ids: ids))
            #expect(rejected.origin == .deterministic && rejected.fallbackReason == .invalidOutput)
            #expect(!rejected.text.contains("900"))
        }
        let failed = try await service.explain(snapshot, provider: MockExplanationProvider(shouldFail: true))
        #expect(failed.fallbackReason == .generationFailed && failed.origin == .deterministic)
    }

    @Test func unavailableReasonsBoundsAndCancellation() async throws {
        let snapshot = try chart(["5"]).trustedSnapshot()
        for reason in [ExplanationFallbackReason.frameworkUnavailable, .intelligenceDisabled, .modelNotReady] {
            let result = try await ChartExplanationService().explain(snapshot, provider: MockExplanationProvider(state: .unavailable(reason)))
            #expect(result.fallbackReason == reason)
        }
        let longSnapshot = try chart(["1"], labels: [String(repeating: "A", count: 257)]).trustedSnapshot()
        let bounded = try await ChartExplanationService().explain(longSnapshot, provider: MockExplanationProvider())
        #expect(bounded.fallbackReason == .inputTooLarge)
        do {
            _ = try await ChartExplanationService().explain(snapshot, provider: MockExplanationProvider(cancel: true))
            Issue.record("Cancellation must not appear as an AI success or failure fallback")
        } catch is CancellationError {}
    }

    @Test(arguments: ChartKind.allCases)
    func explanationIsBriefMeaningNotStatistics(_ kind: ChartKind) async throws {
        let values = kind == .pie ? ["25", "75"] : ["15.123456789", "42.987654321"]
        let snapshot = try chart(values, kind: kind, labels: ["First", "Second"]).trustedSnapshot()
        let payload = ExplanationPayload.meaning(ChartCalculations.calculate(snapshot))
        let selected = payload.requiredFactIDs + ["scope"]
        for provider in [MockExplanationProvider(ids: selected),
                         MockExplanationProvider(state: .unavailable(.deviceUnsupported))] {
            let explanation = try await ChartExplanationService().explain(snapshot, provider: provider)
            let sentences = explanation.text.split(separator: ".").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            #expect((3...5).contains(sentences.count))
            #expect(explanation.text.contains("Use it to"))
            #expect(!explanation.text.contains("15.123456789") && !explanation.text.contains("42.987654321"))
            #expect(!explanation.text.contains("Total:") && !explanation.text.contains("Arithmetic mean"))
            #expect(explanation.key == InsightKey(snapshot))
        }
    }

    @Test func meaningHandlesTiesSinglePointAndUnspecifiedUnits() throws {
        let tied = ExplanationPayload.meaning(ChartCalculations.calculate(try chart(["4","4"]).trustedSnapshot()))
        #expect(tied.facts.first { $0.id == "pattern" }?.text == "All the categories shown have equal values.")
        let one = ExplanationPayload.meaning(ChartCalculations.calculate(try chart(["4"], kind: .line).trustedSnapshot()))
        #expect(one.facts.first { $0.id == "pattern" }?.text.contains("Only one") == true)
        let unknown = ExplanationPayload.meaning(ChartCalculations.calculate(try chart(["1","2"], unit: "Not specified").trustedSnapshot()))
        #expect(unknown.facts.contains { $0.id == "units" && $0.text.contains("do not assume") })
        #expect(unknown.validatedSelection(["overview", "pattern", "invented cause"]) == nil)
    }
}

private actor MockExplanationProvider: ExplanationModelProvider {
    let state: ExplanationModelAvailability
    let ids: [String]
    let shouldFail: Bool
    let cancel: Bool
    private(set) var calls = 0
    init(state: ExplanationModelAvailability = .available, ids: [String] = [], shouldFail: Bool = false, cancel: Bool = false) {
        self.state = state; self.ids = ids; self.shouldFail = shouldFail; self.cancel = cancel
    }
    func availability() async -> ExplanationModelAvailability { state }
    func selectFacts(_ payload: ExplanationPayload) async throws -> [String] {
        calls += 1
        if cancel { throw CancellationError() }
        if shouldFail { throw ExplanationFallbackReason.generationFailed }
        return ids
    }
}
