import Foundation

enum ChartKind: String, CaseIterable, Sendable {
    case verticalBar = "Vertical bar chart"
    case horizontalBar = "Horizontal bar chart"
    case line = "Line graph"
    case pie = "Pie chart"
}

enum ChartValidationError: Error, Equatable {
    case emptyLabel, duplicateCategory, invalidNumber, invalidConfidence, invalidOrder, unknownCategory, unconfirmed, invalidPercentages
}

struct SourceProvenance: Equatable, Sendable {
    let fileName: String
    let mediaType: String
    let page: Int?
    init(fileName: String, mediaType: String, page: Int? = nil) throws {
        guard !fileName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !mediaType.isEmpty else { throw ChartValidationError.emptyLabel }
        if let page, page < 1 { throw ChartValidationError.invalidOrder }
        self.fileName = fileName
        self.mediaType = mediaType
        self.page = page
    }
}

struct ValueCandidate: Equatable, Sendable {
    let rawText: String
    let value: Decimal?
    let confidence: Double?
    let origin: Origin
    enum Origin: Equatable, Sendable { case ocr, geometricEstimate, userCorrection }
}

enum ValueReviewState: Equatable, Sendable {
    case missing
    case candidate(ValueCandidate)
    case ambiguous(ValueCandidate)
    case rejected(ValueCandidate)
    case verified(ValueCandidate)
}

struct ChartCategory: Equatable, Sendable {
    fileprivate(set) var label: String
    let order: Int
    fileprivate(set) var state: ValueReviewState = .missing
    fileprivate(set) var history: [ValueReviewState] = []
}

enum ChartReviewStatus: Equatable, Sendable { case needsReview, partiallyVerified, userVerified }

/// No writable status or deserialization path can manufacture a trusted chart.
struct BarChart: Sendable {
    let kind: ChartKind
    let id: UUID
    private(set) var revision: UInt64 = 0
    private(set) var title: String
    let horizontalAxis: String
    let verticalAxis: String
    private(set) var unit: String
    let source: SourceProvenance
    private(set) var categories: [ChartCategory]

    init(id: UUID = UUID(), initialRevision: UInt64 = 0, kind: ChartKind = .verticalBar, title: String, horizontalAxis: String, verticalAxis: String,
         unit: String, source: SourceProvenance, categories: [(label: String, order: Int)]) throws {
        let labels = [title, horizontalAxis, verticalAxis, unit] + categories.map(\.label)
        guard !categories.isEmpty, labels.allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        else { throw ChartValidationError.emptyLabel }
        let normalized = categories.map { $0.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard Set(normalized).count == categories.count else { throw ChartValidationError.duplicateCategory }
        guard categories.map(\.order) == Array(0..<categories.count) else { throw ChartValidationError.invalidOrder }
        self.id = id
        self.revision = initialRevision
        self.kind = kind
        self.title = title
        self.horizontalAxis = horizontalAxis
        self.verticalAxis = verticalAxis
        self.unit = unit
        self.source = source
        self.categories = categories.map { ChartCategory(label: $0.label, order: $0.order) }
    }

    /// Canonical decimal grammar: ASCII optional sign, integer, optional fractional digits.
    /// No grouping, exponent, locale inference, rounding, or partial parsing.
    static func parse(_ text: String) throws -> Decimal {
        guard text.count <= 40,
              text.range(of: #"\A[+-]?[0-9]+(?:\.[0-9]+)?\z"#, options: .regularExpression) != nil
        else { throw ChartValidationError.invalidNumber }
        let digits = text.filter(\.isNumber)
        guard digits.count <= 28,
              let result = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              !result.isNaN else { throw ChartValidationError.invalidNumber }
        return result
    }

    var status: ChartReviewStatus {
        let count = categories.filter { if case .verified = $0.state { true } else { false } }.count
        return count == categories.count && validationMessages.isEmpty ? .userVerified : count == 0 ? .needsReview : .partiallyVerified
    }

    /// Editable drafts may be invalid; they never become a complete trusted snapshot.
    /// Pie tolerance is 0.5 percentage points for raster/printed rounding, never normalization.
    var validationMessages: [String] {
        var messages: [String] = []
        if [title, unit].contains(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            messages.append("Enter a chart title and units, or explicitly state that units are not specified.")
        }
        let labels = categories.map { $0.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        if labels.contains("") { messages.append("Every category or point needs a label.") }
        if Set(labels).count != labels.count { messages.append("Category or point labels must be distinct.") }
        if kind == .pie {
            if unit != "%" { messages.append("Pie chart units must be percent (%). Values are never converted automatically.") }
            let values = categories.compactMap { $0.state.valueCandidate?.value }
            if values.count != categories.count { messages.append("Every pie slice needs a valid percentage.") }
            if values.contains(where: { $0 < 0 || $0 > 100 }) { messages.append("Pie percentages must be between 0 and 100.") }
            if values.count == categories.count {
                let total = values.reduce(Decimal.zero, +)
                if abs(total - 100) > Decimal(string: "0.5")! {
                    messages.append("Pie percentages total \(ChartNumberFormat.readable(total)), not 100 within the allowed tolerance at full precision. Correct the values; they are never normalized automatically.")
                }
            }
        }
        return messages
    }

    /// Point-level issues drive correction progress and accessible inline errors.
    /// A pie-total mismatch is chart-level: no particular slice is guessed to be wrong.
    func validationMessages(at index: Int) -> [String] {
        guard categories.indices.contains(index) else { return ["Unknown category or point."] }
        let category = categories[index]
        let label = category.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var issues: [String] = []
        if label.isEmpty { issues.append("Enter a label for this category or point.") }
        else if categories.filter({ $0.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == label }).count > 1 {
            issues.append("This label is duplicated. Use a distinct label without changing the source order.")
        }
        switch category.state {
        case .missing: issues.append("Enter a value for this category or point.")
        case .ambiguous(let c):
            issues.append(c.value == nil ? "Enter a valid decimal number using your locale's decimal separator, without grouping." : "Resolve this ambiguous candidate with Use Entered Value before confirming.")
        default: break
        }
        if kind == .pie, let value = category.state.valueCandidate?.value, value < 0 || value > 100 {
            issues.append("This pie percentage must be between 0 and 100.")
        }
        return issues
    }

    mutating func updateTitle(_ title: String) {
        revision &+= 1
        self.title = title
        revokeAllConfirmations()
    }

    mutating func updateUnit(_ unit: String) {
        revision &+= 1
        self.unit = unit
        revokeAllConfirmations()
    }

    mutating func updateLabel(at index: Int, label: String) throws {
        guard categories.indices.contains(index) else { throw ChartValidationError.unknownCategory }
        revision &+= 1
        categories[index].label = label
        if case .verified(let candidate) = categories[index].state {
            try transition(at: index, to: .candidate(candidate))
        }
        // A duplicate changes the meaning of both labels; neither confirmation
        // can remain valid until the conflict has been resolved explicitly.
        for affected in categories.indices where !validationMessages(at: affected).isEmpty {
            if case .verified(let candidate) = categories[affected].state {
                try transition(at: affected, to: .candidate(candidate))
            }
        }
    }

    /// Retains exact entered text. Even incomplete/invalid keystrokes revoke confirmation.
    mutating func editLocalized(at index: Int, text: String, locale: Locale) throws {
        let value = try? LocalizedChartNumber.parse(text, locale: locale)
        let candidate = ValueCandidate(rawText: text, value: value, confidence: nil, origin: .userCorrection)
        try transition(at: index, to: text.isEmpty ? .missing : value == nil ? .ambiguous(candidate) : .candidate(candidate))
    }

    private mutating func revokeAllConfirmations() {
        for index in categories.indices {
            if case .verified(let candidate) = categories[index].state {
                try? transition(at: index, to: .candidate(candidate))
            }
        }
    }

    mutating func propose(at index: Int, text: String, confidence: Double? = nil, ambiguous: Bool = false) throws {
        if let confidence, !confidence.isFinite || !(0...1).contains(confidence) {
            throw ChartValidationError.invalidConfidence
        }
        let value = try? Self.parse(text)
        let candidate = ValueCandidate(rawText: text, value: value, confidence: confidence, origin: .ocr)
        try transition(at: index, to: ambiguous || value == nil ? .ambiguous(candidate) : .candidate(candidate))
    }

    mutating func edit(at index: Int, text: String) throws {
        let candidate = ValueCandidate(rawText: text, value: try Self.parse(text), confidence: nil, origin: .userCorrection)
        try transition(at: index, to: .candidate(candidate))
    }

    mutating func proposeEstimate(at index: Int, text: String, ambiguous: Bool = false) throws {
        let value = try? Self.parse(text)
        let candidate = ValueCandidate(rawText: text, value: value, confidence: nil, origin: .geometricEstimate)
        try transition(at: index, to: ambiguous || value == nil ? .ambiguous(candidate) : .candidate(candidate))
    }

    mutating func reject(at index: Int) throws {
        guard categories.indices.contains(index) else { throw ChartValidationError.unknownCategory }
        switch categories[index].state {
        case .candidate(let c), .ambiguous(let c), .verified(let c): try transition(at: index, to: .rejected(c))
        default: throw ChartValidationError.unconfirmed
        }
    }

    mutating func confirm(at index: Int) throws {
        guard categories.indices.contains(index) else { throw ChartValidationError.unknownCategory }
        guard [title, unit].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw ChartValidationError.emptyLabel
        }
        guard case .candidate(let candidate) = categories[index].state, candidate.value != nil else {
            throw ChartValidationError.unconfirmed
        }
        let labels = categories.map { $0.label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        guard !labels.contains("") else { throw ChartValidationError.emptyLabel }
        guard Set(labels).count == labels.count else { throw ChartValidationError.duplicateCategory }
        if kind == .pie, let value = candidate.value, value < 0 || value > 100 {
            throw ChartValidationError.invalidPercentages
        }
        if kind == .pie, unit != "%" { throw ChartValidationError.invalidPercentages }
        try transition(at: index, to: .verified(candidate))
    }

    private mutating func transition(at index: Int, to state: ValueReviewState) throws {
        guard categories.indices.contains(index) else { throw ChartValidationError.unknownCategory }
        revision &+= 1
        categories[index].history.append(categories[index].state)
        categories[index].state = state
    }

    struct TrustedSnapshot: Equatable, Sendable {
        let kind: ChartKind
        let id: UUID
        let revision: UInt64
        let title: String
        let horizontalAxis: String
        let verticalAxis: String
        let unit: String
        let source: SourceProvenance
        let values: [Entry]
        struct Entry: Equatable, Sendable {
            let label: String
            let order: Int
            let value: Decimal
            let confirmedCandidate: ValueCandidate
        }
        fileprivate init(chart: BarChart, values: [Entry]) {
            kind = chart.kind
            revision = chart.revision
            id = chart.id; title = chart.title; horizontalAxis = chart.horizontalAxis
            verticalAxis = chart.verticalAxis; unit = chart.unit; source = chart.source
            self.values = values
        }
        /// Only an existing trusted snapshot can be copied. Values, metadata
        /// and explicit confirmations remain unchanged; no unverified input enters.
        func copyForLibrary(id: UUID) -> Self { Self(copying: self, id: id) }
        private init(copying snapshot: Self, id: UUID) {
            self.id = id; kind = snapshot.kind; revision = snapshot.revision
            title = snapshot.title; horizontalAxis = snapshot.horizontalAxis
            verticalAxis = snapshot.verticalAxis; unit = snapshot.unit
            source = snapshot.source; values = snapshot.values
        }
    }

    func trustedSnapshot() throws -> TrustedSnapshot {
        guard validationMessages.isEmpty else { throw ChartValidationError.unconfirmed }
        let values = try categories.map { category -> TrustedSnapshot.Entry in
            guard case .verified(let candidate) = category.state, let value = candidate.value else {
                throw ChartValidationError.unconfirmed
            }
            return .init(label: category.label, order: category.order, value: value, confirmedCandidate: candidate)
        }
        return TrustedSnapshot(chart: self, values: values)
    }
}

extension ValueReviewState {
    var valueCandidate: ValueCandidate? {
        switch self {
        case .candidate(let c), .ambiguous(let c), .rejected(let c), .verified(let c): c
        case .missing: nil
        }
    }
    var label: String {
        switch self {
        case .missing: "Missing"
        case .candidate: "Unverified"
        case .ambiguous: "Needs correction or explicit resolution"
        case .rejected: "Rejected"
        case .verified: "Confirmed by you"
        }
    }
}

enum LocalizedChartNumber {
    /// Locale decimal separator and decimal digits; grouping/exponents are deliberately
    /// disallowed to prevent ambiguous partial parsing. No rounding or OCR repair.
    static func parse(_ text: String, locale: Locale) throws -> Decimal {
        guard !text.isEmpty, text.count <= 40 else { throw ChartValidationError.invalidNumber }
        let separator = locale.decimalSeparator ?? "."
        let formatter = NumberFormatter()
        formatter.locale = locale
        let minus = formatter.minusSign ?? "-"
        let plus = formatter.plusSign ?? "+"
        var canonical = ""
        var remainder = text[...]
        if remainder.hasPrefix(minus) { canonical = "-"; remainder.removeFirst(minus.count) }
        else if remainder.hasPrefix(plus) { canonical = "+"; remainder.removeFirst(plus.count) }
        while !remainder.isEmpty {
            if remainder.hasPrefix(separator) {
                canonical += "."; remainder.removeFirst(separator.count)
            } else {
                let character = remainder.removeFirst()
                if let digit = character.wholeNumberValue, (0...9).contains(digit), character.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) }) {
                    canonical += String(digit)
                } else if character == "-" || character == "+" { canonical.append(character) }
                else { throw ChartValidationError.invalidNumber }
            }
        }
        return try BarChart.parse(canonical)
    }
}
