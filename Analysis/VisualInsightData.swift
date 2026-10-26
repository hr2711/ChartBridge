import Foundation

/// All findings retain Decimal precision. Double conversion is drawing-only.
struct VisualInsightData: Sendable {
    let snapshot: BarChart.TrustedSnapshot
    let explorer: ChartExplorer
    var insights: ChartInsights { explorer.insights }
    var points: [CalculationPoint] { insights.points }
    init(_ snapshot: BarChart.TrustedSnapshot) {
        self.snapshot = snapshot
        explorer = ChartExplorer(snapshot)
    }
    func isCurrent(for snapshot: BarChart.TrustedSnapshot?) -> Bool { self.snapshot == snapshot }
    func extrema(_ operation: CalculationOperation) -> [CalculationPoint] {
        guard case .available(.points(let ids))? = insights.result(operation)?.availability else { return [] }
        return ids.compactMap { id in points.first { $0.id == id } }
    }
    var ranking: [RankedPoint] {
        guard case .available(.ranking(let groups))? = insights.result(.descending)?.availability else { return [] }
        return groups.flatMap { group in group.points.compactMap { id in
            points.first { $0.id == id }.map { RankedPoint(point: $0, rank: group.rank, tied: group.points.count > 1) }
        } }
    }
    static func axisDomain(_ points: [CalculationPoint]) -> ClosedRange<Double> {
        let values = points.map { NSDecimalNumber(decimal: $0.value).doubleValue }.filter(\.isFinite)
        let low = min(0, values.min() ?? 0), high = max(0, values.max() ?? 0)
        let padding = (high - low) * 0.08
        guard padding.isFinite, padding > 0 else { return -1...1 }
        return (low < 0 ? low - padding : 0)...(high > 0 ? high + padding : 0)
    }
    /// A hit-test only; never a source of percentages or mathematical findings.
    func pieSelection(_ angle: Double) -> Int? {
        guard angle.isFinite, angle >= 0 else { return nil }
        var edge = 0.0
        for point in points {
            edge += NSDecimalNumber(decimal: point.value).doubleValue
            if angle < edge { return point.id.order }
        }
        return nil
    }
    func comparison(_ selection: VisualComparisonSelection) -> VisualComparison {
        let first = points.first { $0.id.order == selection.first }
        let second = points.first { $0.id.order == selection.second }
        let results = ChartCalculations.compare(snapshot,
            from: .init(chartID: snapshot.id, order: selection.first),
            to: .init(chartID: snapshot.id, order: selection.second))
        let relationship: String
        if let first, let second {
            relationship = first.value == second.value ? "The first value equals the second value." :
                first.value > second.value ? "The first value is higher than the second value." : "The first value is lower than the second value."
        } else { relationship = CalculationUnavailable.unknownPoint.rawValue }
        return .init(selection: selection, results: results, relationship: relationship)
    }
}
struct RankedPoint: Identifiable, Sendable {
    let point: CalculationPoint
    let rank: Int
    let tied: Bool
    var id: CalculationPoint.ID { point.id }
}
struct VisualComparisonSelection: Hashable, Sendable {
    var first = 0
    var second = 1
}
struct VisualComparison: Sendable {
    let selection: VisualComparisonSelection
    let results: [ChartCalculation]
    let relationship: String
}
extension ChartInsightsWorker {
    func visual(_ snapshot: BarChart.TrustedSnapshot) -> VisualInsightData { VisualInsightData(snapshot) }
    func visualComparison(_ data: VisualInsightData, selection: VisualComparisonSelection) -> VisualComparison {
        data.comparison(selection)
    }
}
