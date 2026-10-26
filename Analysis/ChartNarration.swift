import Foundation

/// A short offline explanation, separate from technical reports and VoiceOver
/// control guidance. No unverified input or generated numerical claim can enter.
struct ChartNarration: Sendable {
    let insights: ChartInsights
    let summary: String
    let pointDescriptions: [String]

    init(_ snapshot: BarChart.TrustedSnapshot, locale: Locale = .current) {
        let report = ChartCalculations.calculate(snapshot)
        insights = report
        let estimated = Set(snapshot.values.filter { $0.confirmedCandidate.origin == .geometricEstimate }.map(\.order))
        let unit = report.unit == .unspecified ? "" : report.unit.label
        let suffix = unit.isEmpty ? "" : " " + unit
        func number(_ value: Decimal, estimate: Bool = false) -> String {
            ChartNumberFormat.spoken(value, estimated: estimate, preferWhole: report.kind != .pie, locale: locale)
        }
        func value(_ point: CalculationPoint) -> String { number(point.value, estimate: estimated.contains(point.id.order)) + suffix }
        func names(_ points: [CalculationPoint]) -> String {
            var labels = Array(points.prefix(3)).map(\.label)
            if points.count > 3 { labels.append("\(points.count - 3) other categories") }
            if labels.count < 2 { return labels.first ?? "" }
            return labels.dropLast().joined(separator: ", ") + " and " + labels.last!
        }
        pointDescriptions = report.points.map { $0.label + ": " + value($0) + "." }
        guard let first = report.points.first else {
            summary = "There are no confirmed values to describe."
            return
        }
        guard report.points.count > 1, let last = report.points.last else {
            summary = report.kind == .pie ? "\(first.label) accounts for \(value(first)). It is the only segment shown." :
                "\(first.label) has a value of \(value(first)). It is the only value shown."
            return
        }
        if report.kind == .line {
            if case .available(.trend(.constant))? = report.result(.trend)?.availability {
                summary = "Every observed value stays at \(value(first)). The observations run from \(first.label) to \(last.label)."
                return
            }
            var sentences = ["Values go from \(value(first)) at \(first.label) to \(value(last)) at \(last.label)."]
            if let change = report.result(.netChange)?.number {
                if change.value == 0 { sentences.append("The first and last values are equal.") }
                else {
                    sentences.append("They finish \(number(abs(change.value), estimate: !estimated.isEmpty || change.precision == .rounded))\(suffix) \(change.value > 0 ? "higher" : "lower") than they started.")
                }
            }
            if case .available(.trend(let trend))? = report.result(.trend)?.availability {
                switch trend {
                case .mixed: sentences.append("The observed values rise and fall along the way.")
                case .constant: sentences.append("Every observed value stays the same.")
                case .increasing: if report.points.count > 2 { sentences.append("The observed values rise or stay the same.") }
                case .decreasing: if report.points.count > 2 { sentences.append("The observed values fall or stay the same.") }
                }
            }
            summary = sentences.joined(separator: " ")
            return
        }
        let ordered = report.points.sorted { $0.value == $1.value ? $0.id.order < $1.id.order : $0.value > $1.value }
        let highest = ordered[0], lowest = ordered[ordered.count - 1]
        if highest.value == lowest.value {
            summary = report.kind == .pie ? "All segments have equal shares of \(value(highest)). No segment is larger or smaller than another." :
                "All values are equal at \(value(highest)). No category is higher or lower than another."
            return
        }
        let highTies = report.points.filter { $0.value == highest.value }
        let lowTies = report.points.filter { $0.value == lowest.value }
        var sentences: [String] = []
        if report.kind == .pie {
            sentences.append(highTies.count == 1 ? "\(highest.label) has the largest share at \(value(highest))." :
                "\(names(highTies)) are tied for the largest share at \(value(highest)) each.")
            sentences.append(lowTies.count == 1 ? "\(lowest.label) has the smallest share at \(value(lowest))." :
                "\(names(lowTies)) are tied for the smallest share at \(value(lowest)) each.")
        } else {
            var lead = highTies.count == 1 ? "\(highest.label) has the highest value at \(value(highest))" :
                "\(names(highTies)) are tied for the highest value at \(value(highest)) each"
            if highTies.count == 1, report.points.count <= 4 {
                let middle = ordered.filter { $0.value < highest.value && $0.value > lowest.value }
                if !middle.isEmpty {
                    lead += ", followed by " + middle.map { $0.label + " at " + value($0) }.joined(separator: " and ")
                }
            }
            sentences.append(lead + ".")
            sentences.append(lowTies.count == 1 ? "\(lowest.label) has the lowest value at \(value(lowest))." :
                "\(names(lowTies)) are tied for the lowest value at \(value(lowest)) each.")
        }
        if case .success(let gap) = CheckedDecimal.calculate(highest.value, lowest.value, .subtract) {
            let estimate = !estimated.isEmpty || gap.precision == .rounded
            sentences.append(report.kind == .pie ? "The gap between the largest and smallest shares is \(number(gap.value, estimate: estimate)) percentage points." :
                "The gap between the highest and lowest values is \(number(gap.value, estimate: estimate))\(suffix).")
        }
        summary = sentences.joined(separator: " ")
    }
}
