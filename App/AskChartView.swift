import SwiftUI

/// A local, temporary conversation attached to one completely verified snapshot.
/// There is no network request, model dependency, or persisted question history.
@MainActor
struct AskChartView: View {
    let snapshot: BarChart.TrustedSnapshot
    let authorization: ReportAuthorization
    @Bindable var speech: ChartSpeechService
    @Binding var history: ChartQuestionHistory
    @State private var worker = ChartQuestionWorker()
    @State private var question = ""
    @State private var request: PendingQuestion?
    @State private var failure = ""
    @State private var first = 0
    @State private var second = 0
    @FocusState private var inputFocused: Bool
    @AccessibilityFocusState private var answerFocused: UUID?

    private struct PendingQuestion: Identifiable {
        let id = UUID()
        let title: String
        let value: ChartQuestionWorker.Request
    }
    private var current: Bool { authorization.isCurrent(snapshot) }
    private var suggestions: [String] {
        switch snapshot.kind {
        case .verticalBar, .horizontalBar:
            ["Which category is highest?", "Which category is lowest?", "What is the average?", "What is the total?", "Rank the categories.", "Explain this chart simply."]
        case .line:
            ["What is the overall trend?", "What is the overall change?", "Which point changed the most?", "Which point is highest?", "Explain this chart simply."]
        case .pie:
            ["Which segment is largest?", "Which segment is smallest?", "Rank the segments.", "Explain this chart simply."]
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: ChartBridgeDesign.Spacing.section) {
                    if current {
                        introduction
                        input
                        if history.exchanges.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Try a question").font(.headline).accessibilityAddTraits(.isHeader)
                                ForEach(Array(suggestions.prefix(3)), id: \.self) { suggestion in
                                    Button(suggestion) { submit(suggestion) }
                                        .frame(minHeight: 44, alignment: .leading)
                                }
                            }
                        }
                        ForEach(history.exchanges) { exchange in
                            exchangeView(exchange)
                        }
                        if let choice = history.exchanges.last?.answer.clarification {
                            clarification(choice)
                        }
                        if request != nil { ProgressView("Finding your answer…").id("pending") }
                        if !failure.isEmpty { Text(failure).foregroundStyle(.secondary) }
                        if !history.exchanges.isEmpty {
                            Button("Clear Conversation", systemImage: "trash") {
                                request = nil; speech.stop()
                                history = ChartQuestionHistory(); history.synchronize(snapshot)
                            }.frame(minHeight: 44)
                            Text("Up to 12 recent answers stay here while this verified chart is open. They aren't saved to your library.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    } else {
                        ContentUnavailableView("Verify Your Chart", systemImage: "checkmark.shield",
                            description: Text("Return to the chart and confirm its current values before asking questions. Previous answers are no longer available."))
                    }
                }
                .padding(ChartBridgeDesign.Spacing.page)
                .frame(maxWidth: 600).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: history.exchanges.last?.id) { _, id in
                if let id { proxy.scrollTo(id, anchor: .top) }
            }
        }
        .background(ChartBridgeDesign.Colors.canvas)
        .navigationTitle("Ask Your Chart").navigationBarTitleDisplayMode(.inline)
        .onAppear {
            history.synchronize(current ? snapshot : nil)
            second = snapshot.values.count > 1 ? 1 : 0
        }
        .onChange(of: current) { _, valid in
            guard !valid else { return }
            request = nil; history.synchronize(nil); speech.stop()
        }
        .onChange(of: question) { _, value in
            if value.count > ChartQuestionParser.maximumLength { question = String(value.prefix(ChartQuestionParser.maximumLength)) }
        }
        .task(id: request?.id) {
            guard let pending = request, current else { return }
            do {
                let answer = try await worker.answer(pending.value, snapshot: snapshot)
                guard !Task.isCancelled, current, request?.id == pending.id else { return }
                if history.append(pending.title, answer: answer, current: snapshot) {
                    request = nil
                    AccessibilityNotification.Announcement("Answer ready.").post()
                }
            } catch is CancellationError {
                // A new request, navigation or changed verification owns cleanup.
            } catch {
                guard !Task.isCancelled, current, request?.id == pending.id else { return }
                request = nil; failure = "Your answer couldn't finish. Please try again."
                AccessibilityNotification.Announcement(failure).post()
            }
        }
        .onDisappear { request = nil; speech.stop() }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(snapshot.title).font(.headline).accessibilityAddTraits(.isHeader)
            Text("Ask about the values you confirmed. Answers use on-device calculations, not generative AI.")
                .font(.subheadline).foregroundStyle(.primary)
            DisclosureGroup("What can I ask?") {
                Text(snapshot.kind == .line ? "Ask about highest or lowest values, start and end, trends, overall change, or consecutive changes. Compare two named points using their full labels." : snapshot.kind == .pie ? "Ask about largest or smallest segments, rankings, a segment's share, or comparisons in percentage points. Physical totals can't be inferred from shares." : "Ask about highest or lowest values, rankings, the sum or arithmetic average of the shown categories, or comparisons.")
                Text("For percentage change, say ‘percentage change from [baseline] to [category]’. The baseline must be positive. I can't infer causes, predict the future, or answer arbitrary questions.")
                Text(ChartNumberFormat.note)
            }.font(.subheadline)
        }
    }

    private var input: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your question").font(.headline).accessibilityAddTraits(.isHeader)
            TextField("For example, which category is highest?", text: $question, axis: .vertical)
                .textFieldStyle(.roundedBorder).focused($inputFocused)
                .accessibilityLabel("Question about your chart")
                .accessibilityHint("Use full category names. Up to 512 characters.")
                .accessibilityIdentifier("chartQuestionInput")
                .submitLabel(.send).onSubmit { submit(question) }
            if inputFocused {
                Button("Done Editing") { inputFocused = false }
                    .font(.body).frame(minWidth: 44, minHeight: 44)
            }
            Button("Ask", systemImage: "arrow.up.message") { submit(question) }
                .modifier(PrimaryAction()).frame(minHeight: 44)
                .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || request != nil)
                .accessibilityIdentifier("askChartQuestion")
            Menu("Suggested Questions", systemImage: "text.bubble") {
                ForEach(suggestions, id: \.self) { value in Button(value) { submit(value) } }
                if snapshot.kind == .pie { Button("A segment's share") { submit("Share of", value: .text("share of")) } }
                Button("Compare two categories") { submit("Compare categories", value: .text("compare categories")) }
                if snapshot.kind != .pie { Button("Percentage change between categories") { submit("Choose a percentage baseline", value: .text("percentage difference between categories")) } }
            }.frame(minHeight: 44)
        }
    }

    private func exchangeView(_ exchange: ChartQuestionHistory.Exchange) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Divider().accessibilityHidden(true)
            Text(exchange.question).font(.headline).accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 8) {
                Text(exchange.answer.text)
                ForEach(Array(exchange.answer.rows.enumerated()), id: \.offset) { _, row in Text(row) }
            }
            .font(.body).foregroundStyle(.primary)
            .textSelection(.enabled).accessibilityElement(children: .combine)
            .accessibilityFocused($answerFocused, equals: exchange.id)
            .accessibilityIdentifier("chartQuestionAnswer")
            if exchange.answer.kind == .answer {
                Button("Listen", systemImage: "speaker.wave.2") {
                    guard current else { return }
                    if speech.voiceOverActive { answerFocused = exchange.id }
                    else if let content = VerifiedSpeechContent.answer(exchange.answer, snapshot: snapshot) { speech.play(content) }
                }.frame(minHeight: 44)
                .accessibilityLabel("Listen to answer: " + exchange.question)
                .accessibilityHint("With VoiceOver, focuses the answer. Otherwise reads a short answer aloud.")
                if speech.playback.active { Button("Stop Reading", systemImage: "stop.fill") { speech.stop() }.frame(minHeight: 44) }
            }
        }.id(exchange.id)
    }

    @ViewBuilder private func clarification(_ choice: ChartQuestionClarification) -> some View {
        switch choice {
        case .oneQuestion: EmptyView()
        case .share:
            categoryPicker("Segment", selection: $first)
            Button("Show Share") { submit("Share of \(snapshot.values[first].label)", value: .intent(.share(first))) }
                .buttonStyle(.bordered).frame(minHeight: 44)
        case .comparison(let relative):
            categoryPicker(relative ? "Baseline" : "First category", selection: $first)
            categoryPicker(relative ? "Compare with" : "Second category", selection: $second)
            Button(relative ? "Show Percentage Change" : "Compare Values") {
                let title = relative ? "Percentage change from \(snapshot.values[first].label) to \(snapshot.values[second].label)" : "Compare \(snapshot.values[first].label) and \(snapshot.values[second].label)"
                submit(title, value: .intent(relative ? .relativeDifference(first, second) : .difference(first, second)))
            }.buttonStyle(.bordered).frame(minHeight: 44)
        }
    }
    private func categoryPicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(Array(snapshot.values.enumerated()), id: \.offset) { index, value in
                Text("\(index + 1). \(value.label)").tag(index)
            }
        }.pickerStyle(.menu).frame(minHeight: 44)
    }
    private func submit(_ text: String, value: ChartQuestionWorker.Request? = nil) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard current, request == nil, !trimmed.isEmpty else { return }
        inputFocused = false; question = ""; failure = ""; speech.stop()
        request = .init(title: String(trimmed.prefix(ChartQuestionParser.maximumLength)), value: value ?? .text(trimmed))
    }
}
