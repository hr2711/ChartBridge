import Foundation

struct VerifiedSpeechContent: Equatable, Sendable {
    fileprivate let snapshot: BarChart.TrustedSnapshot
    var key: InsightKey { InsightKey(snapshot) }
    let label: String
    let text: String
    private init(snapshot: BarChart.TrustedSnapshot, label: String, text: String) {
        self.snapshot = snapshot; self.label = label; self.text = text
    }
    static func chart(_ explorer: ChartExplorer) -> Self {
        .init(snapshot: explorer.insights.snapshot, label: "Chart summary", text: explorer.naturalSummary)
    }
    static func answer(_ answer: ChartAnswer, snapshot: BarChart.TrustedSnapshot) -> Self? {
        guard answer.kind == .answer, answer.isCurrent(for: snapshot) else { return nil }
        return .init(snapshot: snapshot, label: "Chart answer", text: answer.spokenText)
    }
    static func point(_ explorer: ChartExplorer) -> Self? {
        explorer.current.map { .init(snapshot: explorer.insights.snapshot, label: "Selected value", text: $0.spokenDescription) }
    }
    static func explanation(_ explanation: ChartExplanation, snapshot: BarChart.TrustedSnapshot) -> Self? {
        guard explanation.isCurrent(for: snapshot), !explanation.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return .init(snapshot: snapshot, label: "Chart explanation", text: explanation.spokenText)
    }
}

/// Pure state logic, independent of audio hardware/delegate timing.
struct SpeechPlayback: Sendable {
    enum State: String, Sendable {
        case idle = "Not reading"
        case speaking = "Reading"
        case paused = "Reading paused"
        case completed = "Reading completed"
        case stopped = "Reading stopped"
        case interrupted = "Reading interrupted. Start again when ready."
    }
    enum Event: Equatable, Sendable { case started, paused, resumed, finished, cancelled }
    private(set) var state: State = .idle
    private var snapshot: BarChart.TrustedSnapshot?
    var key: InsightKey? { snapshot.map(InsightKey.init) }
    private(set) var content: VerifiedSpeechContent?
    private(set) var requestID: UUID?
    var active: Bool { state == .speaking || state == .paused }

    /// Changing verification immediately revokes both current and replay content.
    @discardableResult mutating func synchronize(_ snapshot: BarChart.TrustedSnapshot?) -> Bool {
        guard self.snapshot != snapshot else { return false }
        self.snapshot = snapshot; content = nil; requestID = nil; state = .idle
        return true
    }
    @discardableResult mutating func start(_ content: VerifiedSpeechContent, requestID: UUID) -> Bool {
        guard snapshot == content.snapshot, !content.text.isEmpty else { return false }
        guard !(self.content == content && active) else { return false }
        self.content = content; self.requestID = requestID; state = .speaking
        return true
    }
    mutating func receive(_ event: Event, requestID: UUID) {
        guard self.requestID == requestID else { return }
        switch event {
        case .started: break // Starting was recorded synchronously; a late callback cannot undo pause.
        case .resumed: state = .speaking
        case .paused: state = .paused
        case .finished: state = .completed; self.requestID = nil
        case .cancelled: state = .stopped; self.requestID = nil
        }
    }
    mutating func stop(interrupted: Bool = false) {
        guard active else { return }
        requestID = nil
        state = interrupted ? .interrupted : .stopped
    }
}
