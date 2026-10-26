import Foundation

enum OnboardingStep: Int, CaseIterable, Sendable {
    case importChart, verify, explore
    var title: String {
        switch self {
        case .importChart: "Turn a chart into accessible data."
        case .verify: "Check the numbers before trusting them."
        case .explore: "Understand charts through text and speech."
        }
    }
    var detail: String {
        switch self {
        case .importChart: "Choose a JPEG, PNG, or single-page PDF, or try a fictional sample. ChartBridge processes supported charts on this device."
        case .verify: "Recognition and measurement can be imperfect. Review labels, units, evidence and values, correct mistakes, then explicitly confirm each value. Nothing is verified automatically."
        case .explore: "After verification, explore calculated insights, request an optional on-device explanation, listen, and save verified values or share a report."
        }
    }
}

struct OnboardingProgress: Equatable, Sendable {
    private(set) var step: OnboardingStep = .importChart
    private(set) var completed = false
    mutating func advance() {
        if let next = OnboardingStep(rawValue: step.rawValue + 1) { step = next }
        else { completed = true }
    }
    mutating func skip() { completed = true }
}

enum OnboardingPreferences {
    static let completionKey = "chartbridge.onboarding.v1.completed"
    static func isComplete(in defaults: UserDefaults) -> Bool { defaults.bool(forKey: completionKey) }
    static func complete(in defaults: UserDefaults) { defaults.set(true, forKey: completionKey) }
}

enum ChartSample: String, CaseIterable, Identifiable, Sendable {
    case vertical, horizontal, line, pie
    var id: String { rawValue }
    var kind: ChartKind {
        switch self { case .vertical: .verticalBar; case .horizontal: .horizontalBar; case .line: .line; case .pie: .pie }
    }
    var title: String {
        switch self {
        case .vertical: "Library Activities"
        case .horizontal: "Volunteer Hours"
        case .line: "Weekly Visitors"
        case .pie: "Travel Choices"
        }
    }
    var scenario: String {
        switch self {
        case .vertical: "Fictional attendance at three library activities. Recommended first demo."
        case .horizontal: "Fictional hours contributed by three volunteer teams."
        case .line: "Fictional visitor counts over four ordered weeks."
        case .pie: "Fictional travel choices as shares of a whole."
        }
    }
    var labels: [String] {
        switch self {
        case .vertical: ["Art", "Music", "Coding"]
        case .horizontal: ["Garden", "Library", "Shelter"]
        case .line: ["Week A", "Week B", "Week C", "Week D"]
        case .pie: ["Walk", "Bus", "Cycle"]
        }
    }
    /// Public reference guidance and rendering inputs only—not extraction answers.
    var referenceValues: [Int] { self == .line ? [20, 60, 40, 80] : self == .pie ? [20, 30, 50] : [20, 60, 80] }
    var reference: String {
        zip(labels, referenceValues).map { "\($0): \($1)\(self == .pie ? "%" : "")" }.joined(separator: "; ")
    }
}

enum RecoveryTopic: CaseIterable, Sendable {
    case analysis, verification, intelligence, storage
    var guidance: String {
        switch self {
        case .analysis: "Use one upright, clear chart with readable labels and axis ticks. Try a closer crop or a sharper image. Grouped, stacked, multi-series, markerless lines and unlabeled pies are outside the supported scope. If recognition still fails, try a sample or another file."
        case .verification: "Insights require every value to be valid and explicitly confirmed. Correct missing or duplicate labels and invalid numbers, use Entered Value to resolve ambiguity, then confirm each value. Check title and units too. Pie percentages must total 100 within 0.5 percentage points."
        case .intelligence: "Apple Intelligence depends on compatible hardware, settings and model readiness. If unavailable or its response is invalid, ChartBridge still explains verified values deterministically. AI never verifies data or changes calculations."
        case .storage: "If saving or export fails, keep this preview open. Unlock the device, check available storage and retry. Reload the library after a conflict. Prepare reports again after changes. Sharing occurs only when you choose a destination."
        }
    }
}
