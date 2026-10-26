import SwiftUI

@MainActor
@Observable
final class AnalysisModel {
    enum State { case idle, processing, finished(ExtractionResult), cancelled }
    var state: State = .idle
    private var task: Task<Void, Never>?
    private var requestID = UUID()
    private let analyzer = ChartAnalyzer()

    func start(_ chart: ImportedChart) {
        cancel()
        let id = UUID(); requestID = id
        state = .processing
        AccessibilityNotification.Announcement("Recognizing chart text and geometry on device.").post()
        task = Task {
            do {
                let result = try await analyzer.analyze(chart)
                try Task.checkCancellation()
                guard requestID == id else { return }
                state = .finished(result)
                AccessibilityNotification.Announcement(result.summary + ". All extracted values remain unverified.").post()
            } catch is CancellationError {
                // Explicit cancellation owns the visible state.
            } catch {
                guard requestID == id else { return }
                state = .finished(.failure("The image could not be analyzed. Try a clearer, upright image."))
                AccessibilityNotification.Announcement("Analysis could not finish.").post()
            }
        }
    }
    func cancel() {
        requestID = UUID(); task?.cancel(); task = nil; state = .cancelled
    }
}

struct AnalysisView: View {
    let chart: ImportedChart
    @State private var model = AnalysisModel()
    @State private var reviewStore = ReviewStore()
    @State private var confirmsReanalysis = false

    var body: some View {
        VStack(alignment: .leading, spacing: ChartBridgeDesign.Spacing.medium) {
            switch model.state {
            case .idle:
                ChartSectionHeading(title: "Find the values", subtitle: "Works with simple bar, line and pie charts. You'll confirm the results yourself.")
                startButton("Analyze Chart")
            case .processing:
                ProgressView("Reading your chart…").accessibilityIdentifier("analysisProcessing")
                Text("Processing on this device.").font(.subheadline).foregroundStyle(.secondary)
                Button("Cancel Analysis") {
                    model.cancel()
                    AccessibilityNotification.Announcement("Analysis cancelled. No values were confirmed.").post()
                }.frame(minHeight: 44).accessibilityIdentifier("cancelAnalysis")
            case .cancelled:
                Text("Analysis cancelled. Your file is still open.").accessibilityIdentifier("analysisCancelled")
                startButton("Try Again")
            case .finished(let result):
                Text(result.output == nil ? result.summary : "Your values are ready to review")
                    .font(ChartBridgeDesign.sectionTitle).accessibilityAddTraits(.isHeader).accessibilityIdentifier("analysisResult")
                if let output = result.output {
                    Text(output.kind.rawValue).font(.subheadline).foregroundStyle(.secondary).accessibilityIdentifier("detectedChartType")
                    ChartStatus(title: "Not verified yet", symbol: "exclamationmark.circle")
                    Text("Check the labels and values before confirming them.").font(.subheadline)
                    NavigationLink {
                        ReviewView(output: output, preview: chart.previewPNG, store: reviewStore)
                    } label: {
                        Label(reviewStore.session == nil ? "Review and Verify" : "Continue Review", systemImage: "checklist")
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                    .modifier(PrimaryAction()).accessibilityIdentifier("reviewAndVerify")
                    .accessibilityHint("Review and correct each value. Nothing is confirmed automatically.")
                    DisclosureGroup("Preview unverified estimates") {
                        ForEach(output.values) { value in
                            CandidateRow(value: value, isPie: output.kind == .pie)
                            Divider().accessibilityHidden(true)
                        }
                    }
                    DisclosureGroup("Analysis details") {
                        Text("Values are estimated from chart geometry and recognized labels. Recognition confidence does not confirm a value.")
                        Text("Recognized text observations: \(output.ocr.observations.count)")
                        if let calibration = output.calibration {
                            Text("Calibration slope: \(ChartNumberFormat.readable(calibration.slope)). Offset: \(ChartNumberFormat.readable(calibration.intercept)). Calculations retain full precision.")
                        }
                        Text("Source image identity: " + output.sourceID)
                        ForEach(Array(result.diagnostics.enumerated()), id: \.offset) { _, diagnostic in Text(diagnostic) }
                    }.font(.subheadline)
                    Button("Analyze Again", systemImage: "arrow.clockwise") { requestAnalysis() }
                        .frame(minHeight: 44).buttonStyle(.bordered)
                } else {
                    Text("Try a clearer image or choose another file below.").font(.subheadline)
                    startButton("Try Again")
                    DisclosureGroup("Tips and details") {
                        Text(RecoveryTopic.analysis.guidance)
                        ForEach(Array(result.diagnostics.enumerated()), id: \.offset) { _, diagnostic in Text(diagnostic) }
                    }.font(.subheadline)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .confirmationDialog("Start analysis again?", isPresented: $confirmsReanalysis, titleVisibility: .visible) {
            Button("Replace This Review", role: .destructive) { startAnalysis() }
            Button("Keep Current Review", role: .cancel) {}
        } message: { Text("This replaces your current corrections and confirmations. Saved charts in My Charts are unchanged.") }
        .onDisappear { if case .processing = model.state { model.cancel() } }
    }
    private func startButton(_ title: String) -> some View {
        Button { requestAnalysis() } label: {
            Label(title, systemImage: "viewfinder").frame(maxWidth: .infinity, minHeight: 44)
        }
        .modifier(PrimaryAction()).accessibilityIdentifier("analyzeChart")
        .accessibilityHint("Finds chart values on this device. You must review and confirm them.")
    }
    private func requestAnalysis() {
        if reviewStore.session != nil { confirmsReanalysis = true }
        else { startAnalysis() }
    }
    private func startAnalysis() { reviewStore.session = nil; model.start(chart) }
}

private struct CandidateRow: View {
    let value: ExtractedValue
    let isPie: Bool

    private var estimate: String {
        let number = ChartNumberFormat.readable(value.value)
        return "Estimated value: " + number + (isPie ? " percent" : "")
    }
    private var uncertainty: String {
        let number = ChartNumberFormat.readable(value.uncertainty)
        return "Unverified. " + value.method + ". Raster measurement uncertainty: " + number
            + (isPie ? " percentage points." : " axis units.") + " OCR and calibration errors may add uncertainty."
    }
    var body: some View {
        VStack(alignment: .leading, spacing: ChartBridgeDesign.Spacing.small) {
            Text(value.category).font(.headline)
            Text(estimate)
            Text(uncertainty)
            if let printed = value.printedValue {
                Text("Printed candidate: " + ChartNumberFormat.readable(printed) + ". Also unverified.")
            }
            ForEach(Array(value.diagnostics.enumerated()), id: \.offset) { _, diagnostic in Text(diagnostic) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("candidate-\(value.order)")
    }
}
