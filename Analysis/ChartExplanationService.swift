import Foundation

enum ExplanationModelAvailability: Equatable, Sendable {
    case available
    case unavailable(ExplanationFallbackReason)
}

enum ExplanationFallbackReason: String, Error, Sendable {
    case frameworkUnavailable = "The on-device model is unavailable on this OS."
    case deviceUnsupported = "This device does not support Apple Intelligence."
    case intelligenceDisabled = "Apple Intelligence is not enabled."
    case modelNotReady = "The on-device model is not ready; it may still be downloading."
    case generationFailed = "Apple Intelligence could not complete this request."
    case invalidOutput = "The model response could not be validated and was discarded."
    case inputTooLarge = "This chart exceeds the bounded on-device explanation input size."
}

struct ExplanationFact: Codable, Equatable, Sendable {
    let id: String
    let text: String
    let pointOrders: [Int]
}

/// Explicit whitelist. No source provenance, OCR text/confidence, pixels, paths,
/// hashes, geometry or calibration can be encoded into model input.
struct ExplanationPayload: Codable, Sendable {
    struct Point: Codable, Sendable {
        let id: String
        let label: String
        let value: String
    }
    let title: String
    let chartType: String
    let unit: String
    let points: [Point]
    let facts: [ExplanationFact]
    let requiredFactIDs: [String]
    let scope: String

    static func prepare(_ report: ChartInsights) -> ExplanationPayload {
        let operations: [CalculationOperation]
        switch report.kind {
        case .verticalBar, .horizontalBar: operations = [.count, .largest, .smallest, .total, .mean, .absoluteDifference]
        case .line: operations = [.count, .first, .last, .netChange, .relativeChange, .trend, .largestIncrease, .largestDecrease]
        case .pie: operations = [.count, .largest, .smallest, .pieTotal, .pieConsistency, .percentagePointDifference, .physicalTotal]
        }
        let facts = operations.compactMap { operation -> ExplanationFact? in
            guard let result = report.result(operation) else { return nil }
            return .init(id: operation.rawValue, text: result.summary, pointOrders: result.inputs.map(\.id.order))
        }
        let required: [CalculationOperation]
        switch report.kind {
        case .verticalBar, .horizontalBar: required = [.count, .largest, .smallest, .total]
        case .line: required = [.count, .first, .last, .netChange, .trend]
        case .pie: required = [.count, .largest, .smallest, .pieTotal, .pieConsistency]
        }
        return .init(title: report.title, chartType: report.kind.rawValue, unit: report.unit.label,
                     points: report.points.map { .init(id: "p\($0.id.order)", label: $0.label, value: NSDecimalNumber(decimal: $0.value).stringValue) },
                     facts: facts, requiredFactIDs: required.map(\.rawValue),
                     scope: report.scope + (report.kind == .pie ? " Physical totals cannot be inferred from percentages alone." : ""))
    }

    func encoded() throws -> String {
        let data = try JSONEncoder().encode(self)
        guard data.count <= 8_000, points.count <= 64, title.count <= 256,
              points.allSatisfy({ $0.label.count <= 256 }) else { throw ExplanationFallbackReason.inputTooLarge }
        return String(decoding: data, as: UTF8.self)
    }

    /// Qualitative, grounded takeaways for the short explanation—not a list of
    /// arithmetic outputs. The original payload remains for detailed reports.
    static func meaning(_ report: ChartInsights) -> Self {
        func label(_ id: CalculationPoint.ID) -> String {
            let name = report.points.first { $0.id == id }?.label ?? "a category"
            return String(name.prefix(80)).components(separatedBy: CharacterSet(charactersIn: ".!?\n\r")).joined(separator: " ")
        }
        func names(_ ids: [CalculationPoint.ID]) -> String {
            ids.count > 3 ? "Several categories" : ids.map(label).joined(separator: " and ")
        }
        let overview: String
        let useful: String
        var pattern: String
        switch report.kind {
        case .verticalBar, .horizontalBar:
            overview = "This bar chart compares the values of the categories shown."
            useful = "Use it to see which categories are larger or smaller without reading every number."
        case .line:
            overview = "This line chart shows how values change across the points in the order shown."
            useful = "Use it to follow the observed direction of change, rather than to predict what happens next."
        case .pie:
            overview = "This pie chart shows how a whole is divided among the categories shown."
            useful = "Use it to see which parts account for more or less of the whole."
        }
        if report.points.count == 1 {
            pattern = "Only one category or point is shown, so there is nothing else to compare it with."
        } else if report.kind == .line {
            if case .available(.trend(let trend))? = report.result(.trend)?.availability {
                switch trend {
                case .increasing: pattern = "The observed values rise or stay the same as you move through the chart."
                case .decreasing: pattern = "The observed values fall or stay the same as you move through the chart."
                case .constant: pattern = "The values stay the same at all the points shown."
                case .mixed: pattern = "The values move both up and down, rather than following one steady direction."
                }
            } else { pattern = "There is not enough reliable information to describe a direction of change." }
        } else if let first = report.points.first, report.points.allSatisfy({ $0.value == first.value }) {
            pattern = report.kind == .pie ? "All the categories shown have equal shares." : "All the categories shown have equal values."
        } else if case .available(.points(let high))? = report.result(.largest)?.availability,
                  case .available(.points(let low))? = report.result(.smallest)?.availability {
            let noun = report.kind == .pie ? "share" : "value"
            let highest = high.count == 1 ? "\(names(high)) has the highest \(noun)" : "\(names(high)) share the highest \(noun)"
            let lowest = low.count == 1 ? "\(names(low)) has the lowest \(noun)" : "\(names(low)) share the lowest \(noun)"
            pattern = highest + ", while " + lowest + "."
        } else { pattern = "A reliable comparison of the largest and smallest values is unavailable." }
        let scope = "These takeaways describe the values you confirmed, not why they occurred."
        var facts: [ExplanationFact] = [
            .init(id: "overview", text: overview, pointOrders: []),
            .init(id: "pattern", text: pattern, pointOrders: report.points.map(\.id.order)),
            .init(id: "usefulness", text: useful, pointOrders: []),
            .init(id: "scope", text: scope, pointOrders: [])
        ]
        if report.unit == .unspecified {
            facts.append(.init(id: "units", text: "The units are not specified, so do not assume these values measure people, money or time.", pointOrders: []))
        }
        // Labels/title are bounded as before; the model sees only approved
        // qualitative sentences, not long decimals or a numeric answer list.
        return .init(title: report.title, chartType: report.kind.rawValue, unit: report.unit.label,
            points: report.points.map { .init(id: "p\($0.id.order)", label: $0.label, value: "") },
            facts: facts, requiredFactIDs: ["overview", "pattern", "usefulness"], scope: scope)
    }

    func renderMeaning(_ facts: [ExplanationFact]) -> String {
        facts.map(\.text).joined(separator: " ")
    }

    func renderSpokenMeaning(_ facts: [ExplanationFact]) -> String {
        // Required, grounded takeaways only. Intro/type, unit caveats, scope and
        // attribution remain visible rather than becoming spoken boilerplate.
        facts.filter { $0.id == "pattern" || $0.id == "usefulness" }.map(\.text).joined(separator: " ")
    }

    /// The model can select/order facts but cannot author displayable prose or
    /// numbers. Strict ID allowlisting is structural validation, not a regex
    /// pretending to prove arbitrary generated language mathematically correct.
    func validatedSelection(_ ids: [String]) -> [ExplanationFact]? {
        guard (1...6).contains(ids.count), Set(ids).count == ids.count,
              Set(requiredFactIDs).isSubset(of: Set(ids)) else { return nil }
        let allowedOrders = Set(points.indices)
        var selected: [ExplanationFact] = []
        for id in ids {
            guard let fact = facts.first(where: { $0.id == id }),
                  fact.pointOrders.allSatisfy({ allowedOrders.contains($0) }) else { return nil }
            selected.append(fact)
        }
        return selected
    }

    func render(_ facts: [ExplanationFact]) -> String {
        // Scope is mandatory, independent of model selection.
        "Verified chart: “\(title)”. " + facts.map(\.text).joined(separator: " ") + " " + scope
    }
}

protocol ExplanationModelProvider: Sendable {
    func availability() async -> ExplanationModelAvailability
    func selectFacts(_ payload: ExplanationPayload) async throws -> [String]
}

struct ChartExplanation: Sendable {
    enum Origin: Equatable, Sendable { case deterministic, appleIntelligenceAssisted }
    let snapshot: BarChart.TrustedSnapshot
    var key: InsightKey { InsightKey(snapshot) }
    let text: String
    let origin: Origin
    let fallbackReason: ExplanationFallbackReason?
    let spokenText: String
    init(snapshot: BarChart.TrustedSnapshot, text: String, origin: Origin, fallbackReason: ExplanationFallbackReason?, spokenText: String? = nil) {
        self.snapshot = snapshot; self.text = text; self.origin = origin; self.fallbackReason = fallbackReason
        self.spokenText = spokenText ?? text
    }
    func isCurrent(for snapshot: BarChart.TrustedSnapshot?) -> Bool { self.snapshot == snapshot }
    var attribution: String {
        switch origin {
        case .deterministic: "ChartBridge summary"
        case .appleIntelligenceAssisted:
            "Apple Intelligence assisted on this device"
        }
    }
}

actor ChartExplanationService {
    private var cache = VerifiedInsightsCache()
    func explain(_ snapshot: BarChart.TrustedSnapshot, provider: any ExplanationModelProvider) async throws -> ChartExplanation {
        try Task.checkCancellation()
        let report = cache.calculate(snapshot)
        let payload = ExplanationPayload.meaning(report)
        func fallback(_ reason: ExplanationFallbackReason) -> ChartExplanation {
            .init(snapshot: snapshot, text: payload.renderMeaning(Array(payload.facts.prefix(4))), origin: .deterministic, fallbackReason: reason,
                  spokenText: payload.renderSpokenMeaning(payload.facts))
        }
        switch await provider.availability() {
        case .unavailable(let reason):
            try Task.checkCancellation()
            return fallback(reason)
        case .available: break
        }
        do {
            _ = try payload.encoded()
            let ids = try await provider.selectFacts(payload)
            try Task.checkCancellation()
            guard let selection = payload.validatedSelection(ids), (3...5).contains(selection.count) else { return fallback(.invalidOutput) }
            // Maintain a natural opening and ending even if selection order varies.
            let ordered = payload.facts.filter { fact in selection.contains { $0.id == fact.id } }
            return .init(snapshot: snapshot, text: payload.renderMeaning(ordered), origin: .appleIntelligenceAssisted, fallbackReason: nil,
                         spokenText: payload.renderSpokenMeaning(ordered))
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            return fallback((error as? ExplanationFallbackReason) ?? .generationFailed)
        }
    }
}
