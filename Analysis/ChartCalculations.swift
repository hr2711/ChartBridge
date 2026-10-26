import Foundation

struct InsightKey: Hashable, Sendable {
    let chartID: UUID
    let revision: UInt64
    init(_ snapshot: BarChart.TrustedSnapshot) {
        chartID = snapshot.id; revision = snapshot.revision
    }
}

struct CalculationPoint: Identifiable, Equatable, Sendable {
    struct ID: Hashable, Sendable {
        let chartID: UUID
        let order: Int
    }
    let id: ID
    let label: String
    let value: Decimal
}

enum CalculationUnit: Equatable, Sendable {
    case chart(String), unspecified, percent, percentagePoints, count, none
    var label: String {
        switch self {
        case .chart(let value): value
        case .unspecified: "units not specified"
        case .percent: "percent"
        case .percentagePoints: "percentage points"
        case .count: "observations"
        case .none: ""
        }
    }
}

enum CalculationUnavailable: String, Error, Sendable {
    case invalidData = "The trusted data is empty or invalid."
    case overflow = "The calculation exceeds supported decimal precision or range."
    case underflow = "The result is too small for supported decimal arithmetic."
    case zeroBaseline = "Relative change is undefined because the starting value is zero."
    case negativeBaseline = "Relative change is not reported with a negative starting value; use the absolute change."
    case insufficientPoints = "At least two observed points are required."
    case noIncrease = "No consecutive observed increase was found."
    case noDecrease = "No consecutive observed decrease was found."
    case unknownPoint = "The selected point does not belong to this trusted chart."
    case physicalTotal = "Physical totals cannot be inferred from percentages alone."
    case percentageComparison = "Pie comparisons use percentage points, not relative percentage change."
    case uncalibratedX = "X labels are categories, not calibrated coordinates. Rates and spacing-based calculations are unsupported."
    case ambiguousX = "Some labels represent the same numeric x-value. No x-based rate or spacing is inferred."
}

struct CalculationNumber: Equatable, Sendable {
    enum Precision: Equatable, Sendable { case exact, rounded }
    let value: Decimal
    let precision: Precision
    var exactValue: Decimal? { precision == .exact ? value : nil }
    var text: String {
        ChartNumberFormat.readable(value, approximate: precision == .rounded)
    }
}

enum ObservedTrend: String, Sendable {
    case increasing = "Increasing or equal across the observed points"
    case decreasing = "Decreasing or equal across the observed points"
    case constant = "Constant across the observed points"
    case mixed = "Mixed changes across the observed points"
}

struct ObservedStep: Sendable {
    let from: CalculationPoint.ID
    let to: CalculationPoint.ID
    let change: CalculationNumber
}

struct RankingGroup: Sendable {
    let rank: Int
    let points: [CalculationPoint.ID]
}

enum CalculationValue: Sendable {
    case number(CalculationNumber)
    case points([CalculationPoint.ID])
    case ranking([RankingGroup])
    case steps([ObservedStep])
    case trend(ObservedTrend)
    case pieConsistency(total: CalculationNumber, withinTolerance: Bool)
}

enum CalculationAvailability: Sendable {
    case available(CalculationValue)
    case unavailable(CalculationUnavailable)
}

enum CalculationOperation: String, Sendable {
    case count, total, mean, minimum, maximum, smallest, largest, ascending, descending
    case absoluteDifference, relativeDifference, percentagePointDifference
    case first, last, netChange, relativeChange, largestIncrease, largestDecrease, trend
    case pieTotal, pieConsistency, physicalTotal, xBasedRate
}

struct ChartCalculation: Identifiable, Sendable {
    let operation: CalculationOperation
    let label: String
    let inputs: [CalculationPoint]
    let unit: CalculationUnit
    let explanation: String
    let availability: CalculationAvailability
    var id: String { operation.rawValue + ":" + inputs.map { String($0.id.order) }.joined(separator: ",") }
    var number: CalculationNumber? {
        if case .available(.number(let number)) = availability { number } else { nil }
    }
    var summary: String {
        let result: String
        switch availability {
        case .unavailable(let reason): return label + ": unavailable. " + reason.rawValue
        case .available(let value):
            func describe(_ ids: [CalculationPoint.ID]) -> String {
                ids.compactMap { id in inputs.first { $0.id == id } }.map {
                    "\($0.label), \(ChartNumberFormat.readable($0.value))"
                }.joined(separator: "; ")
            }
            switch value {
            case .number(let number): result = number.text
            case .points(let ids): result = describe(ids) + (ids.count > 1 ? " (tied)" : "")
            case .ranking(let groups):
                result = groups.map { "Rank \($0.rank): " + describe($0.points) + ($0.points.count > 1 ? " (tied)" : "") }.joined(separator: ". ")
            case .steps(let steps):
                result = steps.map { step in
                    let a = inputs.first { $0.id == step.from }?.label ?? ""
                    let b = inputs.first { $0.id == step.to }?.label ?? ""
                    return "\(a) to \(b): \(step.change.text)"
                }.joined(separator: "; ") + (steps.count > 1 ? " (tied changes)" : "")
            case .trend(let trend): result = trend.rawValue
            case .pieConsistency(let total, let consistent):
                result = "\(total.text) percent. " + (consistent ? "Within 0.5 percentage points of 100; not normalized." : "Not consistent with 100 percent.")
            }
        }
        let suffix = unit.label.isEmpty ? "" : " " + unit.label
        return label + ": " + result + suffix + "."
    }
}

struct ChartInsights: Sendable {
    let snapshot: BarChart.TrustedSnapshot
    let key: InsightKey
    let kind: ChartKind
    let title: String
    let unit: CalculationUnit
    let points: [CalculationPoint]
    let results: [ChartCalculation]
    let scope: String
    func isCurrent(for snapshot: BarChart.TrustedSnapshot?) -> Bool {
        self.snapshot == snapshot
    }
    func result(_ operation: CalculationOperation) -> ChartCalculation? { results.first { $0.operation == operation } }
}

/// Checks every Decimal operation. Rounded division is explicitly marked; overflow,
/// underflow and NaN never become numeric findings. No Double arithmetic.
enum CheckedDecimal {
    enum Operation { case add, subtract, multiply, divide }
    static func calculate(_ a: Decimal, _ b: Decimal, _ operation: Operation,
                          roundedInput: Bool = false) -> Result<CalculationNumber, CalculationUnavailable> {
        guard !a.isNaN, !b.isNaN else { return .failure(.invalidData) }
        var lhs = a, rhs = b, output = Decimal()
        let error: Decimal.CalculationError
        switch operation {
        case .add: error = NSDecimalAdd(&output, &lhs, &rhs, .plain)
        case .subtract: error = NSDecimalSubtract(&output, &lhs, &rhs, .plain)
        case .multiply: error = NSDecimalMultiply(&output, &lhs, &rhs, .plain)
        case .divide: error = NSDecimalDivide(&output, &lhs, &rhs, .plain)
        }
        switch error {
        case .noError, .lossOfPrecision:
            guard !output.isNaN else { return .failure(.overflow) }
            var rounded = roundedInput || error == .lossOfPrecision
            if case .divide = operation {
                // Some Foundation implementations return noError for a bounded
                // repeating quotient. Reverse-check without assuming that it is exact.
                var quotient = output, divisor = b, reverse = Decimal()
                let reverseError = NSDecimalMultiply(&reverse, &quotient, &divisor, .plain)
                rounded = rounded || reverseError != .noError || reverse != a
            }
            return .success(.init(value: output, precision: rounded ? .rounded : .exact))
        case .divideByZero: return .failure(.zeroBaseline)
        case .underflow: return .failure(.underflow)
        case .overflow: return .failure(.overflow)
        @unknown default: return .failure(.overflow)
        }
    }
    static func sum(_ values: [Decimal]) -> Result<CalculationNumber, CalculationUnavailable> {
        var number = CalculationNumber(value: 0, precision: .exact)
        for value in values {
            switch calculate(number.value, value, .add, roundedInput: number.precision == .rounded) {
            case .success(let next): number = next
            case .failure(let reason): return .failure(reason)
            }
        }
        return .success(number)
    }
    static func relative(from: Decimal, to: Decimal) -> Result<CalculationNumber, CalculationUnavailable> {
        guard from != 0 else { return .failure(.zeroBaseline) }
        guard from > 0 else { return .failure(.negativeBaseline) }
        return calculate(to, from, .subtract).flatMap { delta in
            calculate(delta.value, from, .divide, roundedInput: delta.precision == .rounded)
        }.flatMap { ratio in
            calculate(ratio.value, 100, .multiply, roundedInput: ratio.precision == .rounded)
        }
    }
}

enum ChartCalculations {
    private static func unit(_ snapshot: BarChart.TrustedSnapshot) -> CalculationUnit {
        if snapshot.kind == .pie { return .percent }
        let text = snapshot.unit.trimmingCharacters(in: .whitespacesAndNewlines)
        return ["", "not specified", "not recognized"].contains(text.lowercased()) ? .unspecified : .chart(text)
    }
    // Only TrustedSnapshot can enter this engine; it has no public/memberwise initializer.
    static func calculate(_ snapshot: BarChart.TrustedSnapshot) -> ChartInsights {
        let points = snapshot.values.map { CalculationPoint(id: .init(chartID: snapshot.id, order: $0.order), label: $0.label, value: $0.value) }
        let unit = unit(snapshot)
        var results: [ChartCalculation] = []
        func append(_ operation: CalculationOperation, _ label: String, _ availability: CalculationAvailability,
                    unit outputUnit: CalculationUnit? = nil, inputs: [CalculationPoint]? = nil, explanation: String) {
            results.append(.init(operation: operation, label: label, inputs: inputs ?? points, unit: outputUnit ?? unit, explanation: explanation, availability: availability))
        }
        func numeric(_ result: Result<CalculationNumber, CalculationUnavailable>) -> CalculationAvailability {
            switch result { case .success(let value): .available(.number(value)); case .failure(let reason): .unavailable(reason) }
        }
        let scope = snapshot.kind == .line ?
            "Only observed points in original source order are compared. No intermediate behavior, equal x-spacing, causal explanation or prediction is inferred." :
            "These calculations use only explicitly confirmed values. Confirmation accepts an estimate; it does not turn it into an exact physical measurement."
        guard !points.isEmpty, points.allSatisfy({ !$0.value.isNaN && !$0.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }),
              points.map(\.id.order) == Array(points.indices),
              !snapshot.unit.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            append(.total, "Findings", .unavailable(.invalidData), explanation: "No unsupported result is substituted.")
            return .init(snapshot: snapshot, key: InsightKey(snapshot), kind: snapshot.kind, title: snapshot.title, unit: unit, points: points, results: results, scope: scope)
        }
        append(.count, snapshot.kind == .pie ? "Number of slices" : snapshot.kind == .line ? "Number of observations" : "Number of categories",
               .available(.number(.init(value: Decimal(points.count), precision: .exact))), unit: CalculationUnit.none, explanation: "Count of verified source-order points.")
        let ascending = points.sorted { $0.value == $1.value ? $0.id.order < $1.id.order : $0.value < $1.value }
        let descending = points.sorted { $0.value == $1.value ? $0.id.order < $1.id.order : $0.value > $1.value }
        let minimum = ascending[0].value, maximum = descending[0].value
        append(.minimum, "Lowest value", .available(.number(.init(value: minimum, precision: .exact))), explanation: "Minimum verified value.")
        append(.maximum, "Highest value", .available(.number(.init(value: maximum, precision: .exact))), explanation: "Maximum verified value.")
        append(.smallest, "Smallest " + (snapshot.kind == .pie ? "slices" : "points"), .available(.points(points.filter { $0.value == minimum }.map(\.id))), explanation: "All tied minima, in original order.")
        append(.largest, "Largest " + (snapshot.kind == .pie ? "slices" : "points"), .available(.points(points.filter { $0.value == maximum }.map(\.id))), explanation: "All tied maxima, in original order.")
        func groups(_ ordered: [CalculationPoint]) -> [RankingGroup] {
            var groups: [RankingGroup] = []
            var previous: Decimal?
            var currentIDs: [CalculationPoint.ID] = []
            var rank = 1
            for (position, point) in ordered.enumerated() {
                if previous != nil, previous != point.value {
                    groups.append(.init(rank: rank, points: currentIDs))
                    currentIDs = []; rank = position + 1
                }
                currentIDs.append(point.id)
                previous = point.value
            }
            if !currentIDs.isEmpty { groups.append(.init(rank: rank, points: currentIDs)) }
            return groups
        }
        append(.ascending, "Ascending ranking", .available(.ranking(groups(ascending))), explanation: "Competition ranking; ties share rank and retain source order.")
        append(.descending, "Descending ranking", .available(.ranking(groups(descending))), explanation: "Competition ranking; ties share rank and retain source order.")
        switch snapshot.kind {
        case .verticalBar, .horizontalBar:
            let total = CheckedDecimal.sum(points.map(\.value))
            append(.total, "Total", numeric(total), explanation: "Sum of all verified categories; a negative total can be valid.")
            let mean = total.flatMap { CheckedDecimal.calculate($0.value, Decimal(points.count), .divide, roundedInput: $0.precision == .rounded) }
            append(.mean, "Arithmetic mean", numeric(mean), explanation: "Total divided by category count, using checked decimal arithmetic.")
        case .line:
            let first = points[0], last = points[points.count - 1]
            append(.first, "First observed value", .available(.number(.init(value: first.value, precision: .exact))), inputs: [first], explanation: "First in original source order.")
            append(.last, "Last observed value", .available(.number(.init(value: last.value, precision: .exact))), inputs: [last], explanation: "Last in original source order.")
            append(.netChange, "Net observed change", numeric(CheckedDecimal.calculate(last.value, first.value, .subtract)), inputs: [first, last], explanation: "Last minus first; not a rate.")
            append(.relativeChange, "Relative start-to-end change", numeric(CheckedDecimal.relative(from: first.value, to: last.value)), unit: .percent, inputs: [first, last], explanation: "(Last − first) / first × 100; requires a positive starting value.")
            var steps: [ObservedStep] = []
            var arithmeticFailure: CalculationUnavailable?
            for (a, b) in zip(points, points.dropFirst()) {
                switch CheckedDecimal.calculate(b.value, a.value, .subtract) {
                case .success(let change): steps.append(.init(from: a.id, to: b.id, change: change))
                case .failure(let reason): arithmeticFailure = reason
                }
            }
            let positives = steps.filter { $0.change.value > 0 }, negatives = steps.filter { $0.change.value < 0 }
            if let arithmeticFailure {
                for op in [CalculationOperation.largestIncrease, .largestDecrease, .trend] {
                    append(op, op == .trend ? "Observed pattern" : op == .largestIncrease ? "Largest consecutive increase" : "Largest consecutive decrease", .unavailable(arithmeticFailure), explanation: "A consecutive difference could not be calculated safely.")
                }
            } else {
                let largest = positives.map(\.change.value).max(), smallest = negatives.map(\.change.value).min()
                append(.largestIncrease, "Largest consecutive increase", largest.map { target in .available(.steps(positives.filter { $0.change.value == target })) } ?? .unavailable(points.count < 2 ? .insufficientPoints : .noIncrease), explanation: "All tied largest positive changes between adjacent observed points; no interval length assumed.")
                append(.largestDecrease, "Largest consecutive decrease", smallest.map { target in .available(.steps(negatives.filter { $0.change.value == target })) } ?? .unavailable(points.count < 2 ? .insufficientPoints : .noDecrease), explanation: "All tied most negative changes between adjacent observed points.")
                // Compare inputs directly: even a rounded difference cannot alter the trend classification.
                let up = zip(points, points.dropFirst()).contains { $1.value > $0.value }
                let down = zip(points, points.dropFirst()).contains { $1.value < $0.value }
                let trend: ObservedTrend = up && down ? .mixed : up ? .increasing : down ? .decreasing : .constant
                append(.trend, "Observed pattern", points.count < 2 ? .unavailable(.insufficientPoints) : .available(.trend(trend)), unit: CalculationUnit.none, explanation: "Nondecreasing/nonincreasing across observed values, allowing equal neighbors. No claim about the line between points.")
            }
            let numericLabels = points.compactMap { try? BarChart.parse($0.label) }
            let repeatedX = numericLabels.count == points.count && Set(numericLabels).count != numericLabels.count
            append(.xBasedRate, "X-based rate", .unavailable(repeatedX ? .ambiguousX : .uncalibratedX), unit: CalculationUnit.none, explanation: "The current domain has ordered labels, not verified numerical x coordinates.")
        case .pie:
            let total = CheckedDecimal.sum(points.map(\.value))
            append(.pieTotal, "Sum of shares", numeric(total), unit: .percent, explanation: "Sum of verified percentages; never normalized.")
            let consistency: CalculationAvailability
            switch total {
            case .failure(let reason): consistency = .unavailable(reason)
            case .success(let number):
                let valid = points.allSatisfy { (0...100).contains($0.value) } && snapshot.unit == "%"
                let delta = CheckedDecimal.calculate(number.value, 100, .subtract)
                if case .success(let difference) = delta {
                    consistency = .available(.pieConsistency(total: number, withinTolerance: valid && abs(difference.value) <= Decimal(string: "0.5")!))
                } else { consistency = .unavailable(.overflow) }
            }
            append(.pieConsistency, "Percentage consistency", consistency, unit: CalculationUnit.none, explanation: "Same 0.5 percentage-point acceptance bound as verification; a rounding tolerance, not a claim of measurement accuracy.")
            append(.physicalTotal, "Physical total", .unavailable(.physicalTotal), unit: CalculationUnit.none, explanation: "No count or physical quantity is inferred from shares.")
        }
        if points.count > 1 {
            results += compare(snapshot, from: descending[0].id, to: ascending[0].id)
        }
        return .init(snapshot: snapshot, key: InsightKey(snapshot), kind: snapshot.kind, title: snapshot.title, unit: unit, points: points, results: results, scope: scope)
    }

    static func compare(_ snapshot: BarChart.TrustedSnapshot, from: CalculationPoint.ID, to: CalculationPoint.ID) -> [ChartCalculation] {
        let points = snapshot.values.map { CalculationPoint(id: .init(chartID: snapshot.id, order: $0.order), label: $0.label, value: $0.value) }
        let unit: CalculationUnit = snapshot.kind == .pie ? .percentagePoints : unit(snapshot)
        guard let a = points.first(where: { $0.id == from }), let b = points.first(where: { $0.id == to }) else {
            return [.init(operation: .absoluteDifference, label: "Selected comparison", inputs: [], unit: unit, explanation: "Only points from this trusted snapshot may be compared.", availability: .unavailable(.unknownPoint))]
        }
        let delta = CheckedDecimal.calculate(b.value, a.value, .subtract)
        let absolute = delta.map { CalculationNumber(value: abs($0.value), precision: $0.precision) }
        func number(_ value: Result<CalculationNumber, CalculationUnavailable>) -> CalculationAvailability {
            switch value { case .success(let v): .available(.number(v)); case .failure(let r): .unavailable(r) }
        }
        var values = [ChartCalculation(operation: .absoluteDifference, label: "Absolute difference: \(a.label) and \(b.label)", inputs: [a, b], unit: snapshot.kind == .pie ? .percentagePoints : unit,
                                      explanation: "Magnitude of the second value minus the first.", availability: number(absolute))]
        if snapshot.kind == .pie {
            values.append(.init(operation: .percentagePointDifference, label: "Share change: \(a.label) to \(b.label)", inputs: [a, b], unit: .percentagePoints,
                                explanation: "Second percentage minus first percentage. Not relative percent change.", availability: number(delta)))
        }
        values.append(.init(operation: .relativeDifference, label: "Relative change: \(a.label) to \(b.label)", inputs: [a, b], unit: .percent,
                            explanation: "(Second − first) / first × 100, only for a positive baseline; not a symmetric percent difference.",
                            availability: snapshot.kind == .pie ? .unavailable(.percentageComparison) : number(CheckedDecimal.relative(from: a.value, to: b.value))))
        return values
    }
}

/// One-entry, in-memory cache owned by a consumer actor. Compare the complete
/// trusted input, not just ID/revision: independent chart copies can share both.
struct VerifiedInsightsCache: Sendable {
    private var snapshot: BarChart.TrustedSnapshot?
    private var report: ChartInsights?

    mutating func calculate(_ snapshot: BarChart.TrustedSnapshot) -> ChartInsights {
        if self.snapshot == snapshot, let report { return report }
        let report = ChartCalculations.calculate(snapshot)
        self.snapshot = snapshot; self.report = report
        return report
    }
}

actor ChartInsightsWorker {
    func calculate(_ snapshot: BarChart.TrustedSnapshot) -> ChartInsights { ChartCalculations.calculate(snapshot) }
    func compare(_ snapshot: BarChart.TrustedSnapshot, from: CalculationPoint.ID, to: CalculationPoint.ID) -> [ChartCalculation] {
        ChartCalculations.compare(snapshot, from: from, to: to)
    }
}
