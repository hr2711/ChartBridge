import SwiftUI

struct ChartExplorerView: View {
    @State private var explorer: ChartExplorer
    @Bindable var speech: ChartSpeechService
    private enum Focus: Hashable { case summary, point }
    @AccessibilityFocusState private var focus: Focus?

    init(explorer: ChartExplorer, speech: ChartSpeechService) {
        _explorer = State(initialValue: explorer)
        self.speech = speech
    }

    var body: some View {
        VStack(alignment: .leading, spacing: ChartBridgeDesign.Spacing.medium) {
            Text("Listen to your chart").font(ChartBridgeDesign.sectionTitle).accessibilityAddTraits(.isHeader)
            Text(explorer.naturalSummary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("explorerSummary")
                .accessibilityFocused($focus, equals: .summary)
            SpeechPlaybackControls(speech: speech, summary: .chart(explorer)) { focus = .summary }

            Divider().accessibilityHidden(true)
            Text("Explore data points").font(.headline).accessibilityAddTraits(.isHeader)
            if let point = explorer.current {
                Text("Selected value · \(point.id.order + 1) of \(explorer.points.count)")
                    .font(.caption).foregroundStyle(.secondary).accessibilityHidden(true)
                Text(point.spokenDescription).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("explorerCurrentPoint")
                    .accessibilityFocused($focus, equals: .point)
                    .accessibilityValue("Item \(point.id.order + 1) of \(explorer.points.count)")
            } else { Text("Choose Next to explore a value.").foregroundStyle(.secondary) }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { previous; next }
                VStack(alignment: .leading, spacing: 8) { previous; next }
            }
            if explorer.current != nil {
                Button {
                    if speech.voiceOverActive { focus = .point }
                    else if let content = VerifiedSpeechContent.point(explorer) { speech.play(content) }
                } label: { Label("Listen to This Value", systemImage: "speaker.wave.2") }
                .frame(minHeight: 44).accessibilityIdentifier("readCurrentPoint")
                .accessibilityHint("Reads only the selected value. With VoiceOver, focuses its readable text.")
            }
            DisclosureGroup("More details") {
                VStack(alignment: .leading, spacing: 16) {
                    Text(explorer.insights.title).font(.headline)
                    Text(explorer.insights.kind.rawValue)
                    Text("These values were explicitly confirmed by you. Estimates remain estimates; confirmation does not establish physical accuracy.")
                    Text(ChartNumberFormat.note)
                    Text(explorer.insights.scope)
                    Button("Jump to Highest Value") { navigate { $0.jumpToLargest() } }
                        .disabled(explorer.largestOrders.isEmpty).frame(minHeight: 44)
                    Button("Jump to Lowest Value") { navigate { $0.jumpToSmallest() } }
                        .disabled(explorer.smallestOrders.isEmpty).frame(minHeight: 44)
                    Text("Jumps select the first tied item in source order. All tied values remain available through Previous and Next.")
                    Button("Return to Summary") {
                        speech.stop(); explorer.returnToSummary(); focus = .summary
                    }.frame(minHeight: 44)
                    if let point = explorer.current { Text(point.description).fixedSize(horizontal: false, vertical: true) }
                    DisclosureGroup("Full calculation details") {
                        Text(explorer.entireChart).textSelection(.enabled)
                    }
                }.font(.subheadline)
            }
        }
        .buttonStyle(.bordered).controlSize(.large)
    }

    private var previous: some View {
        Button("Previous") { navigate { $0.previous() } }
            .disabled(!explorer.canMovePrevious).frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Previous Data Point")
            .accessibilityHint("Moves in source order without wrapping. Stops separate speech playback.")
    }
    private var next: some View {
        Button("Next") { navigate { $0.next() } }
            .disabled(!explorer.canMoveNext).frame(minWidth: 44, minHeight: 44)
            .accessibilityLabel("Next Data Point")
            .accessibilityHint("Moves in source order without wrapping. Stops separate speech playback.")
    }
    private func navigate(_ action: (inout ChartExplorer) -> Void) {
        speech.stop(); action(&explorer); focus = .point
    }
}

struct SpeechPlaybackControls: View {
    @Bindable var speech: ChartSpeechService
    let summary: VerifiedSpeechContent
    let focusSummary: () -> Void
    private var summaryIsActive: Bool { speech.playback.content == summary && speech.playback.active }
    private var primaryTitle: String {
        if speech.voiceOverActive { return "Read Summary" }
        if summaryIsActive { return speech.playback.state == .paused ? "Resume" : "Pause" }
        return "Play Summary"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: ChartBridgeDesign.Spacing.small) {
            Button {
                if speech.voiceOverActive { focusSummary() }
                else if summaryIsActive {
                    if speech.playback.state == .paused { speech.resume() } else { speech.pause() }
                } else { speech.play(summary) }
            } label: {
                Label(primaryTitle, systemImage: summaryIsActive && speech.playback.state == .speaking ? "pause.fill" : "play.fill")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
            .modifier(PrimaryAction()).accessibilityIdentifier("playChartSummary")
            .accessibilityHint(speech.voiceOverActive ? "Focuses the summary for VoiceOver. Separate audio stays off." : "Plays or controls the short chart summary on this device.")
            if speech.playback.content != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { replay; stop }
                    VStack(alignment: .leading, spacing: 8) { replay; stop }
                }
                if !summaryIsActive && speech.playback.active {
                    Button(speech.playback.state == .paused ? "Resume Selected Reading" : "Pause Selected Reading") {
                        if speech.playback.state == .paused { speech.resume() } else { speech.pause() }
                    }.frame(minHeight: 44).disabled(speech.voiceOverActive)
                }
            }
            if speech.voiceOverActive {
                Text("Use VoiceOver gestures to read the summary.").font(.subheadline).foregroundStyle(.secondary)
            }
            if !speech.statusMessage.isEmpty {
                Text(speech.statusMessage).font(.subheadline).accessibilityIdentifier("speechState")
            }
        }
    }
    private var replay: some View {
        Button("Replay Summary") {
            if speech.voiceOverActive { focusSummary() }
            else { speech.stop(); speech.play(summary) }
        }.frame(minHeight: 44).accessibilityHint("Starts the short summary again, not the technical details.")
    }
    private var stop: some View {
        Button("Stop") { speech.stop() }.frame(minHeight: 44).disabled(!speech.playback.active)
            .accessibilityHint("Stops the current reading. It will not resume automatically.")
    }
}
