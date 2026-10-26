import Foundation

/// Immutable factual content can only be prepared from an existing trusted snapshot.
/// Selection is the only mutable part; no OCR or guessed intermediate values enter it.
struct ChartExplorer: Sendable {
    struct Point: Identifiable, Sendable {
        let id: CalculationPoint.ID
        let description: String
        let spokenDescription: String
    }
    let insights: ChartInsights
    let points: [Point]
    let largestOrders: [Int]
    let smallestOrders: [Int]
    let summary: String
    let naturalSummary: String
    let entireChart: String
    private(set) var selectedIndex: Int?

    init(_ snapshot: BarChart.TrustedSnapshot) {
        let narration = ChartNarration(snapshot)
        let report = narration.insights
        insights = report
        naturalSummary = narration.summary
        func extrema(_ operation: CalculationOperation) -> [Int] {
            if case .available(.points(let ids))? = report.result(operation)?.availability { return ids.map(\.order) }
            return []
        }
        let largest = extrema(.largest), smallest = extrema(.smallest)
        largestOrders = largest; smallestOrders = smallest
        let largestSet = Set(largest), smallestSet = Set(smallest)
        let unit = report.unit.label
        points = report.points.enumerated().map { index, point in
            var text = "Item \(index + 1) of \(report.points.count). \(point.label): \(ChartNumberFormat.readable(point.value)) \(unit). Confirmed by you."
            if largestSet.contains(index) { text += largest.count > 1 ? " Tied for highest value." : " Highest value." }
            if smallestSet.contains(index) { text += smallest.count > 1 ? " Tied for lowest value." : " Lowest value." }
            if report.kind == .line {
                if index == 0 { text += " First observed point; no previous observed point." }
                if index == report.points.count - 1 { text += " Last observed point." }
            }
            if index > 0 {
                let previous = report.points[index - 1]
                switch CheckedDecimal.calculate(point.value, previous.value, .subtract) {
                case .success(let change):
                    let magnitude = CalculationNumber(value: abs(change.value), precision: change.precision).text
                    let comparisonUnit = report.kind == .pie ? "percentage points" : unit
                    if change.value == 0 {
                        text += " Unchanged from \(previous.label)."
                    } else {
                        text += " \(magnitude) \(comparisonUnit) \(change.value > 0 ? "more" : "fewer") than \(previous.label)."
                    }
                    if report.kind == .line { text += " This compares adjacent observed points, not behavior between them." }
                case .failure(let reason): text += " Previous-point comparison unavailable. " + reason.rawValue
                }
            }
            if report.kind == .pie { text += " A share of the chart's percentage distribution, not a physical count." }
            return Point(id: point.id, description: text, spokenDescription: narration.pointDescriptions[index])
        }
        let catalog = ExplanationPayload.prepare(report)
        summary = snapshot.kind.rawValue + ". " + catalog.render(catalog.facts)
        entireChart = summary + " Ordered verified data. " + points.map(\.description).joined(separator: " ")
    }

    var key: InsightKey { insights.key }
    var current: Point? { selectedIndex.flatMap { points.indices.contains($0) ? points[$0] : nil } }
    var canMovePrevious: Bool { selectedIndex.map { $0 > 0 } ?? false }
    var canMoveNext: Bool { selectedIndex.map { $0 + 1 < points.count } ?? !points.isEmpty }
    mutating func next() {
        guard canMoveNext else { return }
        selectedIndex = selectedIndex.map { $0 + 1 } ?? 0
    }
    mutating func previous() {
        guard canMovePrevious, let selectedIndex else { return }
        self.selectedIndex = selectedIndex - 1
    }
    mutating func jumpToLargest() { selectedIndex = largestOrders.first }
    mutating func jumpToSmallest() { selectedIndex = smallestOrders.first }
    mutating func returnToSummary() { selectedIndex = nil }
    func isCurrent(for snapshot: BarChart.TrustedSnapshot?) -> Bool { insights.isCurrent(for: snapshot) }
}

extension ChartInsightsWorker {
    func explore(_ snapshot: BarChart.TrustedSnapshot) -> ChartExplorer { ChartExplorer(snapshot) }
}
