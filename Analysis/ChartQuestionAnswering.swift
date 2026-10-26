import Foundation

struct ChartAnswer: Sendable {
    enum Kind: Sendable { case answer, clarification, unsupported, unavailable, verificationRequired }
    let kind: Kind
    let text: String
    let rows: [String]
    let clarification: ChartQuestionClarification?
    private let snapshot: BarChart.TrustedSnapshot?
    fileprivate init(_ kind: Kind, _ text: String, rows: [String] = [],
                     clarification: ChartQuestionClarification? = nil, snapshot: BarChart.TrustedSnapshot?) {
        self.kind = kind; self.text = text; self.rows = rows
        self.clarification = clarification; self.snapshot = snapshot
    }
    func isCurrent(for snapshot: BarChart.TrustedSnapshot?) -> Bool {
        self.snapshot != nil && self.snapshot == snapshot
    }
    var spokenText: String { ([text] + rows.prefix(3)).joined(separator: " ") + (rows.count > 3 ? " More results are on screen." : "") }
    static var verificationRequired: Self {
        .init(.verificationRequired, "Verify all chart values first, then return to ask a question.", snapshot: nil)
    }
}

/// Numerical truth comes exclusively from the existing checked Decimal engine.
/// This layer selects and describes findings; it does not recalculate them.
struct ChartQuestionEngine: Sendable {
    let snapshot: BarChart.TrustedSnapshot
    private let narration: ChartNarration
    private let locale: Locale
    private var report: ChartInsights { narration.insights }
    private var estimated: Bool { snapshot.values.contains { $0.confirmedCandidate.origin == .geometricEstimate } }

    init(_ snapshot: BarChart.TrustedSnapshot, locale: Locale = .current) {
        self.snapshot = snapshot; self.locale = locale
        narration = ChartNarration(snapshot, locale: locale)
    }

    func answer(_ question: String) -> ChartAnswer {
        switch ChartQuestionParser.parse(question, labels: snapshot.values.map(\.label)) {
        case .intent(let intent): return answer(intent)
        case .clarify(let choice): return clarify(choice)
        case .unsupported:
            return response(.unsupported, "I can't answer that from this chart yet. Try asking about the highest value, average, or a comparison.")
        }
    }

    func answer(_ intent: ChartQuestionIntent) -> ChartAnswer {
        switch intent {
        case .highest, .lowest:
            let operation: CalculationOperation = intent == .highest ? .largest : .smallest
            guard case .available(.points(let ids))? = report.result(operation)?.availability else { return unavailable(operation) }
            let points = ids.compactMap(point)
            guard let first = points.first else { return response(.unavailable, "There are no values to compare.") }
            let names = points.prefix(3).map(\.label).joined(separator: ", ") + (points.count > 3 ? " and \(points.count - 3) others" : "")
            return response(.answer, "\(names) \(points.count > 1 ? "are tied for" : "has") the \(intent == .highest ? "highest" : "lowest") value: \(number(first.value))\(suffix(report.unit)).")
        case .total, .average:
            guard snapshot.kind == .verticalBar || snapshot.kind == .horizontalBar else {
                return response(.unavailable, snapshot.kind == .pie ? "Pie segments show shares, not the underlying total or average. Ask for a segment's share instead." : "I don't total or average observations across a line chart. Ask about its overall change or trend instead.")
            }
            let op: CalculationOperation = intent == .total ? .total : .mean
            return numerical(op, introduction: intent == .total ? "The sum of the shown category values is" : "The arithmetic average of the shown category values is")
        case .difference(let a, let b), .relativeDifference(let a, let b):
            guard report.points.indices.contains(a), report.points.indices.contains(b) else { return clarify(.comparison(relative: false)) }
            let first = report.points[a], second = report.points[b]
            let relative: Bool
            if case .relativeDifference = intent { relative = true } else { relative = false }
            let results = ChartCalculations.compare(snapshot, from: first.id, to: second.id)
            let op: CalculationOperation = relative ? .relativeDifference : .absoluteDifference
            guard let result = results.first(where: { $0.operation == op }) else { return response(.unavailable, "This comparison is unavailable.") }
            guard let value = result.number else { return unavailable(result) }
            if relative {
                let direction = value.value == 0 ? "did not change" : "\(value.value > 0 ? "increased" : "decreased") by \(number(abs(value.value), rounded: value.precision == .rounded)) percent"
                return response(.answer, "From \(first.label) (the baseline) to \(second.label), the value \(direction).")
            }
            if first.value == second.value { return response(.answer, "\(first.label) and \(second.label) have equal values. The difference is 0\(suffix(result.unit)).") }
            return response(.answer, "\(second.label) is \(number(value.value, rounded: value.precision == .rounded))\(suffix(result.unit)) \(second.value > first.value ? "higher" : "lower") than \(first.label).")
        case .ranking:
            guard snapshot.kind != .line else { return response(.unavailable, "A line chart keeps its observation order. Ask about the trend or highest value instead.") }
            guard case .available(.ranking(let groups))? = report.result(.descending)?.availability else { return unavailable(.descending) }
            let rows = groups.flatMap { group in group.points.compactMap(point).map {
                "\(group.rank). \($0.label): \(number($0.value))\(suffix(report.unit))\(group.points.count > 1 ? " (tied)" : "")."
            } }
            return response(.answer, "Highest to lowest. Equal values share a rank." + (rows.count > 20 ? " Showing the first 20 of \(rows.count) categories; use the chart explorer for all values." : ""), rows: Array(rows.prefix(20)))
        case .share(let index):
            guard snapshot.kind == .pie else { return response(.unavailable, "Segment shares are available for pie charts only. I won't infer a whole from these values.") }
            guard report.points.indices.contains(index) else { return clarify(.share) }
            let value = report.points[index]
            return response(.answer, "\(value.label) represents \(number(value.value)) percent of the whole shown. Shares use the confirmed percentages without rescaling.")
        case .explain: return response(.answer, narration.summary)
        case .first, .last, .netChange, .relativeChange, .trend, .largestStep, .largestIncrease, .largestDecrease:
            guard snapshot.kind == .line else { return response(.unavailable, "Changes over ordered observations are supported for line charts. Try comparing two named categories instead.") }
            return lineAnswer(intent)
        }
    }

    private func lineAnswer(_ intent: ChartQuestionIntent) -> ChartAnswer {
        switch intent {
        case .first, .last:
            let op: CalculationOperation = intent == .first ? .first : .last
            guard let value = (intent == .first ? report.points.first : report.points.last) else { return unavailable(op) }
            return response(.answer, "The \(intent == .first ? "first" : "last") observation is \(value.label): \(number(value.value))\(suffix(report.unit)).")
        case .netChange, .relativeChange:
            guard let first = report.points.first, let last = report.points.last else { return unavailable(.netChange) }
            let op: CalculationOperation = intent == .netChange ? .netChange : .relativeChange
            guard let value = report.result(op)?.number else { return unavailable(op) }
            let direction = value.value == 0 ? "stayed the same" : "\(value.value > 0 ? "increased" : "decreased") by \(number(abs(value.value), rounded: value.precision == .rounded))\(suffix(intent == .relativeChange ? .percent : report.unit))"
            return response(.answer, "From \(first.label)\(intent == .relativeChange ? " (the baseline)" : "") to \(last.label), the value \(direction). This compares only the endpoints.")
        case .trend:
            guard case .available(.trend(let trend))? = report.result(.trend)?.availability else { return unavailable(.trend) }
            let wording: String
            switch trend {
            case .increasing: wording = "The observed values rise or stay equal from one point to the next."
            case .decreasing: wording = "The observed values fall or stay equal from one point to the next."
            case .constant: wording = "All observed values are equal."
            case .mixed: wording = "The observed values go both up and down."
            }
            return response(.answer, wording + " This describes the shown observations, not what happens between them or what will happen next.")
        default:
            let ops: [CalculationOperation] = intent == .largestIncrease ? [.largestIncrease] : intent == .largestDecrease ? [.largestDecrease] : [.largestIncrease, .largestDecrease]
            var steps: [ObservedStep] = []
            for op in ops {
                if case .available(.steps(let found))? = report.result(op)?.availability { steps += found }
                else if case .unavailable(let reason)? = report.result(op)?.availability,
                        reason != .noIncrease && reason != .noDecrease { return unavailable(op) }
            }
            guard let magnitude = steps.map({ abs($0.change.value) }).max() else {
                return response(.answer, intent == .largestStep ? "All observed values are equal; there is no consecutive change." : "No consecutive observed \(intent == .largestIncrease ? "increase" : "decrease") was found.")
            }
            let largest = steps.filter { abs($0.change.value) == magnitude }.sorted { $0.from.order < $1.from.order }
            let rows = largest.prefix(20).compactMap { step -> String? in
                guard let a = point(step.from), let b = point(step.to) else { return nil }
                return "\(a.label) to \(b.label): \(step.change.value > 0 ? "up" : "down") \(number(abs(step.change.value), rounded: step.change.precision == .rounded))\(suffix(report.unit))."
            }
            return response(.answer, "The largest consecutive \(intent == .largestIncrease ? "increase" : intent == .largestDecrease ? "decrease" : "change")\(largest.count > 1 ? " is tied across \(largest.count) pairs" : " is shown below")." + (largest.count > 20 ? " Showing the first 20 pairs." : ""), rows: rows)
        }
    }

    private func numerical(_ op: CalculationOperation, introduction: String) -> ChartAnswer {
        guard let result = report.result(op), let value = result.number else { return unavailable(op) }
        return response(.answer, "\(introduction) \(number(value.value, rounded: value.precision == .rounded))\(suffix(result.unit)).")
    }
    private func unavailable(_ op: CalculationOperation) -> ChartAnswer {
        report.result(op).map(unavailable) ?? response(.unavailable, "That calculation is not available for this chart.")
    }
    private func unavailable(_ result: ChartCalculation) -> ChartAnswer {
        if case .unavailable(let reason) = result.availability { return response(.unavailable, reason.rawValue) }
        return response(.unavailable, "That calculation is not available for this chart.")
    }
    private func clarify(_ choice: ChartQuestionClarification) -> ChartAnswer {
        let text: String
        switch choice {
        case .comparison(let relative): text = relative ? "Choose the baseline and the category to compare with it. Percentage change needs an explicit starting value." : "Choose the two categories you want to compare. Use their full names when typing."
        case .share: text = "Choose the segment whose share you want to know."
        case .oneQuestion: text = "Please ask about one finding at a time, such as the highest value or the lowest value."
        }
        return .init(.clarification, text, clarification: choice, snapshot: snapshot)
    }
    private func response(_ kind: ChartAnswer.Kind, _ text: String, rows: [String] = []) -> ChartAnswer {
        .init(kind, text, rows: rows, snapshot: snapshot)
    }
    private func point(_ id: CalculationPoint.ID) -> CalculationPoint? { report.points.first { $0.id == id } }
    private func suffix(_ unit: CalculationUnit) -> String { unit == .unspecified || unit == .none ? "" : " " + unit.label }
    private func number(_ value: Decimal, rounded: Bool = false) -> String {
        ChartNumberFormat.readable(value, approximate: rounded || estimated, locale: locale)
            .replacingOccurrences(of: "approximately ", with: "about ")
    }
}

struct ChartQuestionHistory: Sendable {
    struct Exchange: Identifiable, Sendable {
        let id = UUID()
        let question: String
        let answer: ChartAnswer
    }
    private var snapshot: BarChart.TrustedSnapshot?
    private(set) var exchanges: [Exchange] = []
    mutating func synchronize(_ snapshot: BarChart.TrustedSnapshot?) {
        if self.snapshot != snapshot { exchanges = []; self.snapshot = snapshot }
    }
    @discardableResult mutating func append(_ question: String, answer: ChartAnswer, current: BarChart.TrustedSnapshot?) -> Bool {
        guard let current, snapshot == current, answer.isCurrent(for: current) else { return false }
        exchanges.append(.init(question: String(question.prefix(ChartQuestionParser.maximumLength)), answer: answer))
        if exchanges.count > 12 { exchanges.removeFirst(exchanges.count - 12) }
        return true
    }
}

actor ChartQuestionWorker {
    private var engine: ChartQuestionEngine?
    enum Request: Sendable { case text(String), intent(ChartQuestionIntent) }
    func answer(_ request: Request, snapshot: BarChart.TrustedSnapshot?) throws -> ChartAnswer {
        try Task.checkCancellation()
        guard let snapshot else { engine = nil; return .verificationRequired }
        guard snapshot.values.count <= 256 else {
            return .init(.unavailable, "Ask Your Chart supports up to 256 confirmed values. Use the chart explorer for this larger chart.", snapshot: snapshot)
        }
        if engine?.snapshot != snapshot { engine = ChartQuestionEngine(snapshot) }
        guard let engine else { return .verificationRequired }
        let answer: ChartAnswer
        switch request {
        case .text(let question): answer = engine.answer(question)
        case .intent(let intent): answer = engine.answer(intent)
        }
        try Task.checkCancellation()
        return answer
    }
}
