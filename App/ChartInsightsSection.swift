import SwiftUI

/// This view exists only while verification can produce a complete snapshot.
/// Parent identity includes the snapshot revision, so edits immediately remove
/// old insights/explanations and cancel their structured view tasks.
struct ChartInsightsSection: View {
    let snapshot: BarChart.TrustedSnapshot
    @Bindable var speech: ChartSpeechService
    let authorization: ReportAuthorization
    @State private var worker = ChartInsightsWorker()
    @State private var service = ChartExplanationService()
    @State private var provider = AppleChartExplanationProvider()
    @State private var visual: VisualInsightData?
    @State private var explorer: ChartExplorer?
    @State private var explanation: ChartExplanation?
    @State private var explanationRequest: UUID?
    @State private var isExplaining = false
    @State private var notice = ""
    @State private var questionHistory = ChartQuestionHistory()
    @AccessibilityFocusState private var explanationFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ChartBridgeDesign.Spacing.section) {
            if !authorization.isCurrent(snapshot) {
                ChartNotice(title: "Verification changed", message: "Return to the chart and verify its current values before viewing insights.", symbol: "checkmark.shield")
            } else if let visual, visual.isCurrent(for: snapshot) {
                VisualInsightsOverview(data: visual, authorization: authorization)
                if authorization.isCurrent(snapshot) {
                    InformationCard {
                        NavigationLink {
                            AskChartView(snapshot: snapshot, authorization: authorization, speech: speech, history: $questionHistory)
                        } label: {
                            ChartActionRow(title: "Ask Your Chart", subtitle: "Get clear answers about the values you confirmed.", symbol: "text.bubble")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("openAskYourChart")
                        .accessibilityHint("Opens supported questions and comparisons for this verified chart.")
                    }
                }
                InformationCard { explanationControls }
                if let explorer {
                    InformationCard {
                        ChartExplorerView(explorer: explorer, speech: speech)
                    }
                }
                InformationCard {
                    ChartSaveShareControls(snapshot: snapshot, explanation: explanation, authorization: authorization)
                }
            } else { ProgressView("Calculating insights…") }
        }
        .task {
            let value = await worker.visual(snapshot)
            guard !Task.isCancelled, authorization.isCurrent(snapshot), value.isCurrent(for: snapshot) else { return }
            visual = value; explorer = value.explorer
            if value.insights.results.contains(where: { if case .unavailable = $0.availability { true } else { false } }) {
                AccessibilityNotification.Announcement("Some chart calculations are unavailable. Their reasons are listed with the findings.").post()
            }
        }
        .task(id: explanationRequest) {
            guard explanationRequest != nil, authorization.isCurrent(snapshot) else { return }
            do {
                let value = try await service.explain(snapshot, provider: provider)
                guard !Task.isCancelled, authorization.isCurrent(snapshot), value.isCurrent(for: snapshot) else { return }
                explanation = value; isExplaining = false
                AccessibilityNotification.Announcement("Chart explanation ready. " + value.attribution).post()
            } catch is CancellationError {
                // Cancellation/removal owns visible state; never publish an old response.
            } catch {
                guard !Task.isCancelled else { return }
                isExplaining = false; notice = "The explanation could not finish. Try again."
                AccessibilityNotification.Announcement(notice).post()
            }
        }
        .onChange(of: authorization.isCurrent(snapshot)) { _, current in
            guard !current else { return }
            explanationRequest = nil; isExplaining = false
            explanation = nil; visual = nil; explorer = nil
            questionHistory.synchronize(nil); speech.stop()
        }
        .onDisappear { explanationRequest = nil; isExplaining = false; speech.stop() }
    }

    private var explanationControls: some View {
        VStack(alignment: .leading, spacing: ChartBridgeDesign.Spacing.medium) {
            ChartSectionHeading(title: "In plain English", subtitle: "What it shows and why it matters.")
            if isExplaining {
                ProgressView("Preparing your explanation…")
                Button("Cancel Explanation") {
                    explanationRequest = nil; isExplaining = false; explanation = nil
                    notice = "Explanation cancelled."
                    AccessibilityNotification.Announcement(notice).post()
                }
                .frame(minHeight: 44)
            } else {
                Button(explanation == nil ? "Explain Chart" : "Refresh Explanation", systemImage: "sparkles") {
                    speech.stop()
                    explanation = nil; notice = ""; isExplaining = true; explanationRequest = UUID()
                }
                .buttonStyle(.bordered).controlSize(.large)
                .frame(minHeight: 44)
                .accessibilityIdentifier("explainChart")
                .accessibilityHint("Explains only this completely verified chart. Does not verify or change values.")
            }
            if let explanation, authorization.isCurrent(snapshot), explanation.isCurrent(for: snapshot) {
                Label(explanation.attribution, systemImage: explanation.origin == .appleIntelligenceAssisted ? "sparkles" : "text.alignleft")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(explanation.text).textSelection(.enabled).accessibilityIdentifier("chartExplanation")
                    .accessibilityFocused($explanationFocused)
                Button("Listen to Takeaways") {
                    if speech.voiceOverActive { explanationFocused = true }
                    else if let content = VerifiedSpeechContent.explanation(explanation, snapshot: snapshot) { speech.play(content) }
                }
                .frame(minHeight: 44)
                .accessibilityHint("With VoiceOver, focuses the readable explanation. Otherwise speaks its short takeaways; notes and attribution stay on screen. Playback controls follow.")
            }
            DisclosureGroup("About explanations") {
                Text("Apple Intelligence can select grounded takeaways on this device. A built-in explanation works when it is unavailable. Neither confirms values or invents causes.")
                if let reason = explanation?.fallbackReason { Text(reason.rawValue) }
            }.font(.subheadline)
            if !notice.isEmpty { Text(notice) }
        }
    }
}
