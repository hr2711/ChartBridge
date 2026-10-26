import SwiftUI

@MainActor
@Observable
final class ReviewStore {
    var session: ReviewSession? {
        didSet {
            speech.synchronize(with: session?.snapshot)
            authorization.synchronize(with: session?.snapshot)
        }
    }
    let speech = ChartSpeechService()
    let authorization = ReportAuthorization()
    let imageRenderer = EvidenceImageRenderer()
    func update(_ change: (inout ReviewSession) throws -> Void) rethrows {
        guard var copy = session else { return }
        try change(&copy)
        session = copy
    }
}

struct ReviewView: View {
    @Environment(ChartLibraryModel.self) private var library
    @Environment(\.dynamicTypeSize) private var textSize
    let output: ExtractionOutput
    let preview: Data
    @Bindable var store: ReviewStore
    private var session: ReviewSession? { store.session }
    @State private var message = ""
    @State private var valueDraft: ReviewValueDraft?
    @FocusState private var inputFocus: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ChartBridgeDesign.Spacing.page) {
                if let review = session {
                    summary(review)
                    progress(review)
                    warnings(review)
                    Text("Your values").font(ChartBridgeDesign.sectionTitle).accessibilityAddTraits(.isHeader)
                    ForEach(review.chart.categories.indices, id: \.self) { index in
                        row(index, review: review)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text(review.snapshot == nil ? "Confirm each value to unlock insights." : "Chart verified")
                            .font(.headline).accessibilityIdentifier("trustedAvailability")
                        if let snapshot = review.snapshot {
                            DisclosureGroup("Confirmed values") {
                                ForEach(snapshot.values, id: \.order) { entry in
                                    Text(entry.label + ": " + ChartNumberFormat.readable(entry.value) + (snapshot.kind == .pie ? " percent" : ""))
                                }
                            }.accessibilityIdentifier("confirmedValues")
                        }
                    }
                    if textSize.isAccessibilitySize { InformationCard { reviewActions } }
                    if let snapshot = review.snapshot {
                        ChartInsightsSection(snapshot: snapshot, speech: store.speech, authorization: store.authorization).id(InsightKey(snapshot))
                    } else {
                        InformationCard {
                            ChartNotice(title: "Insights come next", message: "Confirm every value to explore, listen and save your chart.", symbol: "chart.bar")
                            DisclosureGroup("Need help reviewing?") { Text(RecoveryTopic.verification.guidance) }
                                .font(.subheadline).accessibilityIdentifier("insightsRequireVerification")
                        }
                    }
                } else {
                    Text("Review could not be opened because the extracted structure is invalid. No values were confirmed.")
                }
                if !message.isEmpty { Text(message).accessibilityIdentifier("reviewMessage") }
            }
            .padding(ChartBridgeDesign.Spacing.page)
            .frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
        .background(ChartBridgeDesign.Colors.canvas)
        .accessibilityIdentifier("reviewScroll")
        .navigationTitle("Review and Verify")
        .navigationBarTitleDisplayMode(.inline)
        .font(.body)
        .safeAreaInset(edge: .bottom) {
            if inputFocus != nil {
                Button("Done Editing") { inputFocus = nil }
                    .font(.body).frame(minWidth: 44, minHeight: 44)
                    .padding(8).frame(maxWidth: .infinity).background(.bar)
            } else if !textSize.isAccessibilitySize { reviewActions.padding(16).background(.bar) }
        }
        .disabled(library.saving)
        .scrollDismissesKeyboard(.interactively)
        .onAppear {
            if store.session == nil { store.session = try? ReviewSession(output: output, locale: .current) }
        }
        .sheet(item: $valueDraft) { draft in
            ReviewValueEditor(draft: draft, label: session?.chart.categories[draft.index].label ?? "Value", locale: session?.locale ?? .current) { edited in
                guard session != nil else { throw ChartValidationError.unconfirmed }
                try store.update { _ = try $0.commitValueEdit(edited) }
            }
        }
        .onDisappear { store.speech.stop() }
    }

    private var reviewActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let snapshot = session?.snapshot {
                SaveChartControls(snapshot: snapshot, authorization: store.authorization).id(InsightKey(snapshot))
            } else if let review = session, let index = review.nextConfirmationIndex {
                Text("Next: " + review.chart.categories[index].label + " · " + review.displayedValue(at: index))
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                Button {
                    perform("Value confirmed by you.") { try store.update { try $0.confirm(at: index) } }
                } label: {
                    Text("Confirm " + review.chart.categories[index].label).frame(maxWidth: .infinity, minHeight: 44)
                }
                .modifier(PrimaryAction()).accessibilityIdentifier("confirmNextValue")
                .accessibilityHint("Accepts only the named value and its label with the current chart title and units. Does not confirm other values.")
            } else if session != nil {
                Text("Resolve the highlighted values to continue.").font(.subheadline)
            }
        }
    }

    private func summary(_ review: ReviewSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(review.chart.title.isEmpty ? "Review your chart" : review.chart.title)
                .font(ChartBridgeDesign.title).accessibilityAddTraits(.isHeader).accessibilityIdentifier("chartSummary")
            Label(output.kind.rawValue, systemImage: output.kind.symbolName).font(.subheadline).foregroundStyle(.secondary)
            Text("Check the values. Confirm only what you accept.").font(.subheadline)
            DisclosureGroup("Edit chart details") {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("Chart title", text: Binding(get: { session?.chart.title ?? "" }, set: { text in store.update { $0.title(text) } }), axis: .vertical)
                        .accessibilityLabel("Chart title").accessibilityIdentifier("reviewTitle").focused($inputFocus, equals: -1).frame(minHeight: 44)
                    if output.kind == .pie {
                        Text("Units: percent (%). Pie values are shares, not counts.").accessibilityIdentifier("reviewPieUnits")
                    } else {
                        TextField("Units", text: Binding(get: { session?.chart.unit ?? "" }, set: { text in store.update { $0.unit(text) } }), axis: .vertical)
                            .accessibilityLabel("Chart units").accessibilityIdentifier("reviewUnit").focused($inputFocus, equals: -2).frame(minHeight: 44)
                    }
                    Text("Changing the title or units means confirming all values again.").font(.subheadline).foregroundStyle(.secondary)
                }.padding(.top, 8)
            }.accessibilityIdentifier("editChartDetails")
        }.textFieldStyle(.roundedBorder)
    }

    private func progress(_ review: ReviewSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: Double(review.confirmedCount), total: Double(review.chart.categories.count))
                .tint(ChartBridgeDesign.Colors.accent)
                .accessibilityLabel("Values confirmed").accessibilityValue("\(review.confirmedCount) of \(review.chart.categories.count)")
            Text("\(review.confirmedCount) confirmed · \(review.chart.categories.count) total" + (review.correctionCount > 0 ? " · \(review.correctionCount) need correction" : ""))
                .font(.subheadline).accessibilityIdentifier("verificationProgress")
        }
    }

    private func warnings(_ review: ReviewSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if !review.chart.validationMessages.isEmpty {
                Text(review.chart.validationMessages.joined(separator: " ")).font(.subheadline)
                    .accessibilityIdentifier("chartValidation")
            }
            DisclosureGroup("Review guidance and extraction notes") {
                Text("Confirming accepts a value, its label and the current title and units based on the available evidence. Visual inspection is not required; recognition confidence never confirms data.")
                Text("Estimates stay estimates. Editing a confirmed label or value requires confirming it again.")
                ForEach(Array(output.diagnostics.enumerated()), id: \.offset) { _, warning in Text(warning) }
                if output.kind == .pie { Text("Percentages must be 0–100 and total 100 within 0.5 percentage points. They are never normalized automatically.") }
                if output.kind == .line { Text("Points follow source order. X labels are categories, not calibrated time or distance.") }
            }.font(.subheadline)
        }
    }

    private func row(_ index: Int, review: ReviewSession) -> some View {
        let category = review.chart.categories[index]
        let isConfirmed: Bool = if case .verified = category.state { true } else { false }
        let needsResolution: Bool = switch category.state { case .ambiguous, .rejected: true; default: false }
        return InformationCard {
            Text(category.label)
                .font(.headline).accessibilityAddTraits(.isHeader)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: isConfirmed ? "checkmark.circle" : needsResolution ? "exclamationmark.circle" : "circle").accessibilityHidden(true)
                Text(category.state.label).accessibilityIdentifier("reviewStatus-\(index)")
            }.font(.subheadline)
            DisclosureGroup("Edit label") {
                TextField("Label", text: Binding(get: { session?.chart.categories[index].label ?? "" }, set: { text in
                    perform { try store.update { try $0.label(at: index, text: text) } }
                }), axis: .vertical)
                .accessibilityLabel("Label for point \(index + 1)")
                .accessibilityIdentifier("reviewLabel-\(index)")
                .focused($inputFocus, equals: index * 2)
                .frame(minHeight: 44)
            }.accessibilityIdentifier("editLabel-\(index)")
            Text("Value: " + review.displayedValue(at: index) + (output.kind == .pie ? " percent" : ""))
                .font(.headline).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("reviewDisplayedValue-\(index)")
            Button("Edit Value") { perform { valueDraft = try session?.beginValueEdit(at: index) } }
                .accessibilityLabel("Edit value for \(category.label)")
                .accessibilityHint("Opens the original full-precision value. Only saving a changed value removes its confirmation.")
                .accessibilityIdentifier("editValue-\(index)")
                .frame(minHeight: 44)
            if !review.chart.validationMessages(at: index).isEmpty {
                Text(review.chart.validationMessages(at: index).joined(separator: " "))
                    .accessibilityIdentifier("rowValidation-\(index)")
            }
            if needsResolution {
                Button("Use Entered Value") { perform("Value accepted for review, but not confirmed.") { try store.update { try $0.resolve(at: index) } } }
                .accessibilityLabel("Use entered value for \(category.label)")
                .accessibilityHint("Resolves an ambiguous or rejected candidate. Confirm separately when you accept it.")
                .accessibilityIdentifier("resolveValue-\(index)")
            }
            Button("Confirm Value") { perform("Value confirmed by you.") { try store.update { try $0.confirm(at: index) } } }
                .buttonStyle(.bordered).tint(ChartBridgeDesign.Colors.accent)
                .frame(minHeight: 44).disabled(isConfirmed)
                .accessibilityLabel("Confirm value for \(category.label)")
                .accessibilityHint("Accepts this valid candidate based on the available evidence, without requiring visual inspection.")
                .accessibilityIdentifier("confirmValue-\(index)")
            Button("Reject Value", role: .destructive) { perform("Value rejected. It is excluded from a trusted snapshot.") { try store.update { try $0.reject(at: index) } } }
                .accessibilityLabel("Reject value for \(category.label)")
                .accessibilityIdentifier("rejectValue-\(index)").buttonStyle(.borderless).frame(minHeight: 44)
            DisclosureGroup {
                EvidenceDetails(output: output, value: output.values[index])
                DisclosureGroup {
                    SourceRegionImage(preview: preview, region: output.values[index].region, renderer: store.imageRenderer)
                } label: {
                    Text("Optional source-region image").accessibilityIdentifier("sourceRegion-\(index)")
                }
            } label: {
                Text("Evidence for \(category.label)").accessibilityIdentifier("evidence-\(index)")
            }
        }
        .textFieldStyle(.roundedBorder)
        .buttonStyle(.bordered)
        .controlSize(.large)
        .frame(minHeight: 44)
    }

    private func perform(_ success: String? = nil, operation: () throws -> Void) {
        do {
            try operation()
            if let success {
                message = success + (success == "Value confirmed by you." && session?.chart.status == .userVerified ? " Verification completed. Chart insights and exploration are available." : "")
                AccessibilityNotification.Announcement(message).post()
            }
        } catch {
            message = "Unable to accept this change. Check for empty or duplicate labels, invalid numbers, or an unresolved or rejected candidate. Use Entered Value to resolve a valid number before confirming."
            AccessibilityNotification.Announcement(message).post()
        }
    }
}

private struct ReviewValueEditor: View {
    @State var draft: ReviewValueDraft
    let label: String
    let locale: Locale
    let commit: (ReviewValueDraft) throws -> Void
    @State private var errorMessage = ""
    @Environment(\.dismiss) private var dismiss
    private var isValid: Bool { (try? LocalizedChartNumber.parse(draft.text, locale: locale)) != nil }

    var body: some View {
        NavigationStack {
            Form {
                Section(label) {
                    TextField("Value at original precision", text: $draft.text, axis: .vertical)
                        .keyboardType(.numbersAndPunctuation)
                        .accessibilityIdentifier("reviewValue-\(draft.index)")
                        .accessibilityHint("Full precision is available here. Changes are applied only with Save Changes.")
                        .frame(minHeight: 44)
                    Text("Use \(locale.decimalSeparator ?? ".") as the decimal separator, without grouping separators.")
                    if !isValid { Text("Enter a valid decimal number.").foregroundStyle(.primary) }
                }
                Section {
                    Text("The original value is shown without rounding. Cancel leaves the value and verification unchanged. Saving a changed value requires you to confirm it again.")
                }
                if !errorMessage.isEmpty { Section { Text(errorMessage).accessibilityIdentifier("valueEditError") } }
            }
            .navigationTitle("Edit Value").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save Changes") {
                        do {
                            try commit(draft)
                            AccessibilityNotification.Announcement("Value updated. Confirm it again when ready.").post()
                            dismiss()
                        } catch {
                            errorMessage = "This value could not be updated. The chart may have changed; cancel and reopen the editor."
                            AccessibilityNotification.Announcement(errorMessage).post()
                        }
                    }
                    .disabled(!draft.hasChanges || !isValid)
                    .accessibilityIdentifier("saveValueEdit")
                }
            }
        }
    }
}

private struct SourceRegionImage: View {
    let preview: Data
    let region: ImageBox
    let renderer: EvidenceImageRenderer
    @State private var imageData: Data?
    @State private var finished = false

    var body: some View {
        VStack(alignment: .leading) {
            Text("Optional visual reference only. The text evidence above is sufficient to review a value without seeing this image.")
            if let imageData, let image = UIImage(data: imageData) {
                Image(uiImage: image).resizable().scaledToFit()
                    .accessibilityLabel("Cropped source region used for the original estimate. Not a verification of the value.")
                    .accessibilityIdentifier("sourceRegionImage")
            } else if finished {
                Text("The optional image could not be shown. Text evidence and verification remain available.")
            } else { ProgressView("Preparing optional source image…") }
        }
        .task {
            let result = try? await renderer.crop(preview: preview, region: region)
            guard !Task.isCancelled else { return }
            imageData = result; finished = true
        }
    }
}

private struct EvidenceDetails: View {
    let output: ExtractionOutput
    let value: ExtractedValue

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(EvidenceSupport.label(output: output, value: value)).font(.headline)
            Text(output.kind == .pie ? "Estimated from raster slice angle." : output.kind == .line ? "Estimated from a visible point marker and recognized axis labels." : "Estimated from bar length and recognized axis labels.")
            Text("Original geometric estimate: \(ChartNumberFormat.readable(value.value))\(output.kind == .pie ? " percent" : " axis units"). Not human verified.")
            Text("Measurement uncertainty: \(ChartNumberFormat.readable(value.uncertainty)) \(output.kind == .pie ? "percentage points" : "axis units"). This covers raster measurement only; OCR and calibration errors may add uncertainty.")
            if let printed = value.printedValue { Text("Original printed-value candidate: \(ChartNumberFormat.readable(printed)). Not human verified.") }
            Text(EvidenceSupport.agreement(output: output, value: value).rawValue)
                .accessibilityIdentifier("evidenceAgreement-\(value.order)")
            if let calibration = output.calibration {
                Text("Based on \(calibration.ticks.count) recognized axis labels. \(calibration.ticks.count >= 3 ? "Spacing passed the linearity check." : "The axis scale could not be confirmed from only two labels.")")
                Text("Recognized ticks: " + calibration.ticks.map { $0.observation.raw }.joined(separator: ", "))
            }
            ForEach(Array(value.observations.enumerated()), id: \.offset) { _, observation in
                if observation.confidence.isFinite, (0...1).contains(observation.confidence) {
                    Text("Recognized text: \(observation.raw). Text recognition confidence: \(Int(observation.confidence * 100)) percent. Not verification.")
                } else { Text("Recognized text: \(observation.raw). Text recognition confidence is unavailable. Not verification.") }
            }
            ForEach(Array(value.diagnostics.enumerated()), id: \.offset) { _, warning in Text(warning) }
            Text("Source region: \(Int(value.region.x * 100)) percent from the left, \(Int(value.region.y * 100)) percent from the top; width \(Int(value.region.width * 100)) percent, height \(Int(value.region.height * 100)) percent.")
            DisclosureGroup("Advanced Technical Details") {
                if let calibration = output.calibration {
                    Text("Linear calibration slope: \(ChartNumberFormat.readable(calibration.slope)). Offset: \(ChartNumberFormat.readable(calibration.intercept)). Display rounding does not change calibration calculations.")
                } else {
                    Text(output.kind == .pie ? "Shares are estimated from source-pixel slice angles; no physical total is inferred." : "Geometry is estimated from source pixels. Calibration details are unavailable.")
                }
                Text("Source image identity: " + output.sourceID).textSelection(.enabled)
                Text("Normalized source region: x \(ChartNumberFormat.readable(value.region.x)), y \(ChartNumberFormat.readable(value.region.y)), width \(ChartNumberFormat.readable(value.region.width)), height \(ChartNumberFormat.readable(value.region.height)).")
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}
