import Foundation

struct AxisCalibration: Sendable {
    struct Tick: Sendable { let position: Double; let value: Double; let observation: OCRText }
    let slope: Double
    let intercept: Double
    let ticks: [Tick]
    let residual: Double
    var span: Double { (ticks.map(\.value).max() ?? 0) - (ticks.map(\.value).min() ?? 0) }
    func value(at coordinate: Double) -> Double { slope * coordinate + intercept }
    func position(of value: Double) -> Double { (value - intercept) / slope }

    init(ticks: [Tick]) throws {
        guard ticks.count >= 2, Set(ticks.map(\.value)).count == ticks.count else {
            throw ExtractionIssue("At least two distinct tick labels are required; three are needed to check linearity.")
        }
        let meanX = ticks.map(\.position).reduce(0, +) / Double(ticks.count)
        let meanY = ticks.map(\.value).reduce(0, +) / Double(ticks.count)
        let variance = ticks.reduce(0) { $0 + pow($1.position - meanX, 2) }
        guard variance > 0.0001 else { throw ExtractionIssue("Tick positions do not span an axis.") }
        let slope = ticks.reduce(0) { $0 + ($1.position - meanX) * ($1.value - meanY) } / variance
        let intercept = meanY - slope * meanX
        let span = (ticks.map(\.value).max() ?? 0) - (ticks.map(\.value).min() ?? 0)
        let residual = ticks.map { abs(slope * $0.position + intercept - $0.value) }.max() ?? .infinity
        guard slope.isFinite, intercept.isFinite, span.isFinite, residual.isFinite,
              abs(slope) > 0.0001, residual <= max(0.01, span * 0.015) else {
            throw ExtractionIssue("Tick spacing is inconsistent with a linear axis; logarithmic or misread axes are unsupported.")
        }
        self.slope = slope; self.intercept = intercept; self.ticks = ticks; self.residual = residual
    }
}

struct ExtractionIssue: Error, Sendable { let message: String; init(_ message: String) { self.message = message } }

struct ExtractedValue: Sendable, Identifiable {
    var id: Int { order }
    let order: Int
    let category: String
    let value: Double
    let printedValue: Double?
    let method: String
    let region: ImageBox
    let observations: [OCRText]
    let uncertainty: Double
    let diagnostics: [String]
    var isVerified: Bool { false }
}

struct ExtractionOutput: Sendable {
    let sourceID: String
    let source: SourceProvenance
    let kind: ChartKind
    let title: String?
    let xAxisTitle: String?
    let yAxisTitle: String?
    let unit: String?
    let values: [ExtractedValue]
    let calibration: AxisCalibration?
    let geometryEvidence: String
    let ocr: OCRDocument
    let diagnostics: [String]

    /// The same verification engine is used for all series. No confirmation is performed.
    /// Metadata must be supplied explicitly if it was not reliably recognized.
    func reviewChart(title: String, horizontalAxis: String, verticalAxis: String, unit: String) throws -> BarChart {
        var chart = try BarChart(kind: kind, title: title, horizontalAxis: horizontalAxis, verticalAxis: verticalAxis,
                                 unit: unit, source: source,
                                 categories: values.map { ($0.category, $0.order) })
        for item in values {
            // Preserve the estimate's shortest decimal representation without
            // quantizing tiny measurements to zero. Unsupported precision stays ambiguous.
            let decimal = Decimal(string: String(item.value), locale: Locale(identifier: "en_US_POSIX"))
            let number = decimal.map { NSDecimalNumber(decimal: $0).stringValue } ?? String(item.value)
            try chart.proposeEstimate(at: item.order, text: number, ambiguous: diagnostics.count > 1 || !item.diagnostics.isEmpty)
        }
        return chart
    }
}

enum ExtractionResult: Sendable {
    case candidates(ExtractionOutput)
    case needsReview(ExtractionOutput)
    case ambiguous([ChartKind], [String], OCRDocument)
    case unsupported([String], OCRDocument)
    case failure(String)

    var output: ExtractionOutput? {
        switch self { case .candidates(let o), .needsReview(let o): o; default: nil }
    }
    var summary: String {
        switch self {
        case .candidates: "Unverified candidates"
        case .needsReview: "Needs review — conflicting evidence"
        case .ambiguous: "Ambiguous chart type"
        case .unsupported: "Chart not supported reliably"
        case .failure: "Analysis could not finish"
        }
    }
    var diagnostics: [String] {
        switch self {
        case .candidates(let o), .needsReview(let o): o.diagnostics
        case .ambiguous(_, let d, _), .unsupported(let d, _): d
        case .failure(let d): [d]
        }
    }
}

/// In-memory review editing over the existing verification engine, not a second
/// authority for confirmation. Original OCR and geometry remain immutable.
struct ReviewSession: Sendable {
    let evidence: ExtractionOutput
    let locale: Locale
    private(set) var chart: BarChart
    private(set) var inputs: [String]

    init(output: ExtractionOutput, locale: Locale) throws {
        self.evidence = output; self.locale = locale
        chart = try output.reviewChart(title: output.title ?? "Title not recognized",
            horizontalAxis: output.xAxisTitle ?? "Not recognized",
            verticalAxis: output.yAxisTitle ?? "Not recognized", unit: output.unit ?? "Not specified")
        inputs = chart.categories.map {
            ($0.state.valueCandidate?.rawText ?? "").replacingOccurrences(of: ".", with: locale.decimalSeparator ?? ".")
        }
    }
    var confirmedCount: Int { chart.categories.filter { if case .verified = $0.state { true } else { false } }.count }
    var rejectedCount: Int { chart.categories.filter { if case .rejected = $0.state { true } else { false } }.count }
    var correctionCount: Int { chart.categories.indices.filter { index in
        if case .rejected = chart.categories[index].state { return false }
        return !chart.validationMessages(at: index).isEmpty
    }.count }
    var awaitingCount: Int { chart.categories.count - confirmedCount - rejectedCount - correctionCount }
    var snapshot: BarChart.TrustedSnapshot? { try? chart.trustedSnapshot() }
    /// A suggested next action, never a bulk confirmation. Ambiguous, rejected,
    /// missing and invalid values still require their explicit correction flow.
    var nextConfirmationIndex: Int? {
        chart.categories.indices.first { index in
            guard case .candidate(let candidate) = chart.categories[index].state else { return false }
            return candidate.value != nil && chart.validationMessages(at: index).isEmpty
        }
    }
    func displayedValue(at index: Int) -> String {
        guard chart.categories.indices.contains(index) else { return "Value unavailable" }
        guard let value = chart.categories[index].state.valueCandidate?.value else {
            return inputs[index].isEmpty ? "Enter a value" : "Needs correction"
        }
        return ChartNumberFormat.readable(value, locale: locale)
    }
    /// Opening or cancelling a draft does not touch the chart or its trust state.
    func beginValueEdit(at index: Int) throws -> ReviewValueDraft {
        guard inputs.indices.contains(index) else { throw ChartValidationError.unknownCategory }
        return .init(index: index, revision: chart.revision, originalText: inputs[index], text: inputs[index])
    }
    @discardableResult mutating func commitValueEdit(_ draft: ReviewValueDraft) throws -> Bool {
        guard inputs.indices.contains(draft.index) else { throw ChartValidationError.unknownCategory }
        guard chart.revision == draft.revision, inputs[draft.index] == draft.originalText else { throw ChartValidationError.unconfirmed }
        guard draft.hasChanges else { return false }
        _ = try LocalizedChartNumber.parse(draft.text, locale: locale)
        try value(at: draft.index, text: draft.text)
        return true
    }
    mutating func title(_ text: String) { chart.updateTitle(text) }
    mutating func unit(_ text: String) { chart.updateUnit(text) }
    mutating func label(at index: Int, text: String) throws { try chart.updateLabel(at: index, label: text) }
    mutating func value(at index: Int, text: String) throws {
        guard inputs.indices.contains(index) else { throw ChartValidationError.unknownCategory }
        inputs[index] = text
        try chart.editLocalized(at: index, text: text, locale: locale)
    }
    mutating func resolve(at index: Int) throws {
        guard inputs.indices.contains(index) else { throw ChartValidationError.unknownCategory }
        // Explicit acceptance of the entered number resolves extraction ambiguity,
        // but still does NOT confirm it. Confirmation is a separate user action.
        _ = try LocalizedChartNumber.parse(inputs[index], locale: locale)
        try chart.editLocalized(at: index, text: inputs[index], locale: locale)
    }
    mutating func confirm(at index: Int) throws { try chart.confirm(at: index) }
    mutating func reject(at index: Int) throws { try chart.reject(at: index) }
}

struct ReviewValueDraft: Identifiable, Sendable {
    let index: Int
    let revision: UInt64
    let originalText: String
    var text: String
    var id: Int { index }
    var hasChanges: Bool { text != originalText }
}

enum EvidenceSupport {
    /// Deterministic support labels, NOT probabilities: a conflict diagnostic wins;
    /// strong requires a printed value, no extra warnings, all OCR >=0.8, and
    /// at least three linear calibration ticks (or complete pie geometry).
    /// Anything else is limited. Human verification is separate in every case.
    static func label(output: ExtractionOutput, value: ExtractedValue) -> String {
        guard value.value.isFinite, value.uncertainty.isFinite, value.uncertainty >= 0 else { return "Unable to estimate reliably" }
        let diagnostics = value.diagnostics + output.diagnostics
        if diagnostics.contains(where: { $0.localizedCaseInsensitiveContains("conflict") || $0.localizedCaseInsensitiveContains("disagree") }) {
            return "Conflicting evidence"
        }
        if agreement(output: output, value: value) == .conflicts { return "Conflicting evidence" }
        let calibrated = output.kind == .pie || (output.calibration?.ticks.count ?? 0) >= 3
        guard calibrated, output.diagnostics.count <= 1, value.diagnostics.isEmpty,
              !value.observations.isEmpty, value.observations.allSatisfy({ $0.confidence.isFinite && (0.8...1).contains($0.confidence) }),
              agreement(output: output, value: value) == .agrees else { return "Limited supporting evidence" }
        return "Strong supporting evidence"
    }

    enum Agreement: String, Sendable {
        case unavailable = "No uniquely associated printed value was recognized. Evidence agreement cannot be assessed."
        case agrees = "The printed value agrees with the geometric estimate within the measurement comparison tolerance. Neither is automatically verified."
        case conflicts = "The printed value conflicts with the geometric estimate. Resolve the disagreement before accepting a value."
        case unreliable = "The evidence contains an invalid measurement; agreement cannot be assessed reliably."
    }

    /// Same comparison budget as extraction: pie 2 percentage points; bars and
    /// lines max(raster uncertainty, 2% of observed axis span). Not an accuracy score.
    static func agreement(output: ExtractionOutput, value: ExtractedValue) -> Agreement {
        guard let printed = value.printedValue else { return .unavailable }
        guard printed.isFinite, value.value.isFinite, value.uncertainty.isFinite, value.uncertainty >= 0 else { return .unreliable }
        let tolerance = output.kind == .pie ? 2 : max(value.uncertainty, (output.calibration?.span ?? 0) * 0.02)
        return abs(printed - value.value) <= tolerance ? .agrees : .conflicts
    }
}
