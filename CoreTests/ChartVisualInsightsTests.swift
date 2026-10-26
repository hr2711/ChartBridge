import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import ChartBridgeMath
#endif

@Suite struct ChartVisualInsightsTests {
    private let english = Locale(identifier: "en_US")
    private func decimal(_ text: String) -> Decimal { Decimal(string: text, locale: Locale(identifier: "en_US_POSIX"))! }
    private func data(_ values: [String], kind: ChartKind = .verticalBar) throws -> VisualInsightData {
        VisualInsightData(try ChartInsightsTests().chart(values, kind: kind).trustedSnapshot())
    }

    @Test func roundedPresentationDoesNotChangeValues() {
        let original = decimal("42.101983298687145")
        #expect(ChartNumberFormat.number(original, locale: english) == "42.10")
        #expect(ChartNumberFormat.readable(original, locale: english) == "approximately 42.10")
        #expect(original == decimal("42.101983298687145"))
        #expect(ChartNumberFormat.number(decimal("26.956149159744903"), locale: english) == "26.96")
        #expect(ChartNumberFormat.number(decimal("1.005"), locale: english) == "1.01")
        #expect(ChartNumberFormat.number(decimal("-1.005"), locale: english) == "-1.01")
        #expect(ChartNumberFormat.number(Decimal.zero, locale: english) == "0")
        #expect(ChartNumberFormat.number(decimal("-12.5"), locale: english) == "-12.50")
        #expect(ChartNumberFormat.readable(decimal("0.001"), locale: english) == "between 0 and 0.01")
        #expect(ChartNumberFormat.readable(decimal("-0.001"), locale: english) == "between -0.01 and 0")
        #expect(ChartNumberFormat.number(Double.infinity, locale: english) == "Unavailable")
        #expect(ChartNumberFormat.number(Decimal.nan, locale: english) == "Unavailable")
    }

    @Test func percentagesLargeValuesAndLocales() {
        #expect(ChartNumberFormat.percent(decimal("40"), locale: english) == "40%")
        #expect(ChartNumberFormat.percent(decimal("12.345"), locale: english) == "12.35%")
        #expect(ChartNumberFormat.number(decimal("1234567.895"), locale: english) == "1,234,567.90")
        #expect(ChartNumberFormat.number(decimal("1234.567"), locale: Locale(identifier: "de_DE")) == "1.234,57")
        #expect(ChartNumberFormat.number(decimal("1234.567"), locale: Locale(identifier: "fr_FR")) == "1\u{202F}234,57")
        let large = ChartNumberFormat.number(decimal("9999999999999999999999999999"), locale: english)
        #expect(!large.contains("E") && !large.contains("e"))
    }

    @Test func fullPrecisionDeterminesTiesAndCompetitionRanks() throws {
        let visual = try data(["1.001", "1.002", "1.002", "0"])
        #expect(visual.extrema(.largest).map(\.id.order) == [1, 2])
        #expect(visual.extrema(.smallest).map(\.id.order) == [3])
        #expect(visual.ranking.map(\.rank) == [1, 1, 3, 4])
        #expect(visual.ranking.map(\.point.id.order) == [1, 2, 0, 3])
        #expect(visual.ranking.map(\.tied) == [true, true, false, false])
        #expect(ChartNumberFormat.number(visual.points[0].value, locale: english) == ChartNumberFormat.number(visual.points[1].value, locale: english))
        #expect(visual.comparison(.init(first: 0, second: 1)).relationship == "The first value is lower than the second value.")
    }

    @Test func scalesIncludeZeroAndDefensiveEmpty() throws {
        #expect(VisualInsightData.axisDomain([]) == (-1...1))
        for values in [["-4", "-2"], ["0"], ["8"], ["-9", "5"]] {
            let visual = try data(values)
            let domain = VisualInsightData.axisDomain(visual.points)
            #expect(domain.contains(0) && domain.lowerBound.isFinite && domain.upperBound.isFinite)
            for point in visual.points { #expect(domain.contains(NSDecimalNumber(decimal: point.value).doubleValue)) }
        }
        let single = try data(["-5"])
        #expect(single.extrema(.largest) == single.extrema(.smallest))
        #expect(single.ranking.map(\.rank) == [1])
        let equal = single.comparison(.init(first: 0, second: 0))
        #expect(equal.results.first?.number?.value == 0)
        #expect(equal.relationship == "The first value equals the second value.")
    }

    @Test func comparisonBaselineAndInvalidSelection() throws {
        let visual = try data(["0", "-2", "10", "15"])
        let zero = visual.comparison(.init(first: 0, second: 2))
        if case .unavailable(.zeroBaseline)? = zero.results.last?.availability {} else { Issue.record("Zero must remain unavailable") }
        let negative = visual.comparison(.init(first: 1, second: 2))
        if case .unavailable(.negativeBaseline)? = negative.results.last?.availability {} else { Issue.record("Negative baseline must remain unavailable") }
        let positive = visual.comparison(.init(first: 2, second: 3))
        #expect(positive.results.first?.number?.value == 5)
        #expect(positive.results.last?.number?.value == 50)
        #expect(positive.relationship == "The first value is lower than the second value.")
        #expect(visual.comparison(.init(first: 3, second: 2)).relationship == "The first value is higher than the second value.")
        let invalid = visual.comparison(.init(first: 99, second: 2))
        if case .unavailable(.unknownPoint)? = invalid.results.first?.availability {} else { Issue.record("No substituted selection") }
    }

    @Test func pieSharesAndLineOrder() throws {
        let pie = try data(["40", "35", "25"], kind: .pie)
        let comparison = pie.comparison(.init(first: 0, second: 1))
        #expect(comparison.results.first?.unit == .percentagePoints)
        #expect(comparison.results.first?.number?.value == 5)
        #expect(comparison.results[1].unit == .percentagePoints)
        #expect(comparison.results[1].number?.value == -5)
        if case .unavailable(.percentageComparison)? = comparison.results.last?.availability {} else { Issue.record("Do not present a relative pie change") }
        #expect(pie.pieSelection(0) == 0 && pie.pieSelection(40) == 1 && pie.pieSelection(99.9) == 2)
        #expect(pie.pieSelection(-1) == nil && pie.pieSelection(.nan) == nil && pie.pieSelection(100) == nil)
        let line = try data(["10", "30", "15"], kind: .line)
        #expect(line.points.map(\.value) == [10, 30, 15])
        #expect(line.insights.result(.netChange)?.number?.value == 5)
        if case .available(.trend(.mixed))? = line.insights.result(.trend)?.availability {} else { Issue.record("Observed mixed trend") }
    }

    @MainActor @Test func editingRevokesVisualAuthorization() throws {
        var chart = try ChartInsightsTests().chart(["1", "2"])
        let old = try chart.trustedSnapshot()
        let visual = VisualInsightData(old)
        let authorization = ReportAuthorization()
        authorization.synchronize(with: old)
        #expect(authorization.isCurrent(old) && visual.isCurrent(for: old))
        try chart.edit(at: 0, text: "3")
        authorization.synchronize(with: nil)
        #expect(!authorization.isCurrent(old) && !visual.isCurrent(for: nil))
        #expect(throws: ChartReportError.stale) { try authorization.validate(old) }
        try chart.confirm(at: 0)
        let new = try chart.trustedSnapshot()
        authorization.synchronize(with: new)
        #expect(!visual.isCurrent(for: new) && !authorization.isCurrent(old))
        #expect(authorization.isCurrent(new))
    }

    @Test func readableReportsExplorerAndMachineFactsRetainIntegrity() async throws {
        let visual = try data(["42.101983298687145", "15.145834138942242"])
        let report = try await ChartReportBuilder().prepare(visual.snapshot)
        #expect(report.text.contains("42.10") && report.text.contains("15.15"))
        #expect(!report.text.contains("42.101983298687145"))
        #expect(visual.explorer.entireChart.contains("42.10"))
        #expect(!visual.explorer.entireChart.contains("42.101983298687145"))
        let facts = ExplanationPayload.prepare(visual.insights)
        #expect(facts.points[0].value == "42.101983298687145")
        #expect(!facts.render(facts.facts).contains("42.101983298687145"))
        #expect(visual.snapshot.values[0].value == decimal("42.101983298687145"))
    }
}
