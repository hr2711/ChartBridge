import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import ChartBridgeMath
#endif

@Suite struct ChartListeningTests {
    private let english = Locale(identifier: "en_US")
    private func snapshot(_ values: [String], kind: ChartKind = .verticalBar,
                          labels: [String]? = nil, unit: String? = nil) throws -> BarChart.TrustedSnapshot {
        try ChartInsightsTests().chart(values, kind: kind, labels: labels, unit: unit).trustedSnapshot()
    }
    private func review(locale: Locale = Locale(identifier: "en_US")) throws -> ReviewSession {
        let output = ExtractionOutput(sourceID: "synthetic", source: try SourceProvenance(fileName: "synthetic.png", mediaType: "image/png"),
            kind: .verticalBar, title: "Fictional activities", xAxisTitle: "Category", yAxisTitle: "Value", unit: "participants",
            values: [42.101983298687145, 15.145834138942242].enumerated().map { index, value in
                ExtractedValue(order: index, category: "Activity \(index + 1)", value: value, printedValue: nil,
                    method: "Synthetic geometry", region: ImageBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2),
                    observations: [], uncertainty: 0.25, diagnostics: [])
            }, calibration: nil, geometryEvidence: "Synthetic geometry", ocr: OCRDocument(sourceID: "synthetic", observations: [], width: 100, height: 100, orientation: 1), diagnostics: [])
        var session = try ReviewSession(output: output, locale: locale)
        for index in session.chart.categories.indices { try session.confirm(at: index) }
        return session
    }

    @Test func verificationDisplaysRoundedButOpeningAndCancellingKeepPrecision() throws {
        var session = try review()
        let original = try #require(session.snapshot)
        let originalInput = session.inputs[0]
        #expect(session.displayedValue(at: 0) == "approximately 42.10")
        var draft = try session.beginValueEdit(at: 0)
        #expect(draft.text == originalInput && originalInput.count > 5)
        #expect(session.snapshot == original && session.inputs[0] == originalInput)
        let unchanged = try session.commitValueEdit(draft)
        #expect(!unchanged && session.snapshot == original)
        draft.text = "42.10"
        #expect(session.snapshot == original, "A draft change is not a saved edit")
        // Discard the draft, just as Cancel/swipe-to-dismiss does.
        draft = try session.beginValueEdit(at: 0)
        #expect(draft.text == originalInput && session.snapshot == original)
        #expect(session.chart.categories[0].state.valueCandidate?.origin == .geometricEstimate)
        #expect(session.evidence.values[0].uncertainty == 0.25)
    }

    @Test func reviewNumberExamplesHaveAtMostTwoDecimals() {
        for (raw, display) in [("42.101983298687145", "42.10"), ("34.2200683339697406", "34.22"), ("26.180515081527872", "26.18"), ("15.145834138942242", "15.15")] {
            let value = Decimal(string: raw)!
            #expect(ChartNumberFormat.number(value, locale: english) == display)
            #expect(value == Decimal(string: raw))
        }
    }

    @Test func nextConfirmationIsOnlyOneValidUnconfirmedCandidate() throws {
        var session = try ReviewSession(output: review().evidence, locale: english)
        let revision = session.chart.revision
        #expect(session.nextConfirmationIndex == 0 && session.confirmedCount == 0)
        #expect(session.chart.revision == revision, "Suggesting an action never confirms data")
        try session.confirm(at: 0)
        #expect(session.nextConfirmationIndex == 1 && session.confirmedCount == 1)
        #expect(session.snapshot == nil)
        try session.confirm(at: 1)
        #expect(session.nextConfirmationIndex == nil && session.snapshot != nil)
    }

    @Test func uncertainRejectedAndInvalidCandidatesRequireTheirOwnResolution() throws {
        var session = try ReviewSession(output: review().evidence, locale: english)
        try session.value(at: 0, text: "invalid")
        #expect(session.nextConfirmationIndex == 1)
        try session.reject(at: 1)
        #expect(session.nextConfirmationIndex == nil && session.snapshot == nil)
        try session.value(at: 0, text: "42.123456")
        #expect(session.nextConfirmationIndex == 0)
        try session.label(at: 0, text: session.chart.categories[1].label)
        #expect(session.nextConfirmationIndex == nil, "A duplicate label cannot be suggested for confirmation")
        #expect(session.evidence.values[0].uncertainty == 0.25)
    }

    @Test func ambiguousEstimatesAreNeverSuggestedBeforeExplicitResolution() throws {
        let source = try review().evidence
        let uncertain = ExtractionOutput(sourceID: source.sourceID, source: source.source, kind: source.kind, title: source.title,
            xAxisTitle: source.xAxisTitle, yAxisTitle: source.yAxisTitle, unit: source.unit, values: source.values,
            calibration: source.calibration, geometryEvidence: source.geometryEvidence, ocr: source.ocr,
            diagnostics: ["Synthetic uncertainty", "Needs explicit resolution"])
        var session = try ReviewSession(output: uncertain, locale: english)
        #expect(session.nextConfirmationIndex == nil && session.confirmedCount == 0)
        try session.resolve(at: 0)
        #expect(session.nextConfirmationIndex == 0 && session.confirmedCount == 0)
        #expect(session.snapshot == nil)
    }

    @Test func deliberateSavedEditRevokesTrustWithoutChangingOriginalEvidence() throws {
        var session = try review()
        let old = try #require(session.snapshot)
        var draft = try session.beginValueEdit(at: 0)
        draft.text = "43.123456789"
        let changed = try session.commitValueEdit(draft)
        #expect(changed && session.snapshot == nil)
        #expect(session.inputs[0] == "43.123456789")
        #expect(session.evidence.values[0].value == 42.101983298687145 && session.evidence.values[0].uncertainty == 0.25)
        #expect(session.chart.categories[0].state.valueCandidate?.origin == .userCorrection)
        try session.confirm(at: 0)
        let new = try #require(session.snapshot)
        #expect(new.values[0].value == Decimal(string: "43.123456789"))
        #expect(new.revision != old.revision)
    }

    @Test func localizedDraftsInvalidAndStaleEdits() throws {
        var session = try review(locale: Locale(identifier: "de_DE"))
        let original = try #require(session.snapshot)
        #expect(session.displayedValue(at: 0) == "approximately 42,10")
        var invalid = try session.beginValueEdit(at: 0)
        #expect(invalid.text.contains(",") && !invalid.text.contains("."))
        invalid.text = "42,1garbage"
        #expect(throws: ChartValidationError.invalidNumber) { try session.commitValueEdit(invalid) }
        #expect(session.snapshot == original)
        var stale = try session.beginValueEdit(at: 0)
        stale.text = "44,1234"
        session.unit("people")
        #expect(throws: ChartValidationError.unconfirmed) { try session.commitValueEdit(stale) }
        #expect(session.inputs[0] == invalid.originalText)
        var valid = try session.beginValueEdit(at: 0)
        valid.text = "44,1234"
        let changed = try session.commitValueEdit(valid)
        #expect(changed)
        #expect(session.chart.categories[0].state.valueCandidate?.value == Decimal(string: "44.1234"))
    }

    @Test(arguments: [ChartKind.verticalBar, .horizontalBar])
    func naturalBarsAndNoBoilerplate(_ kind: ChartKind) throws {
        let trusted = try snapshot(["42.101983298687145", "34.2200683339697406", "26.180515081527872", "15.145834138942242"],
            kind: kind, labels: ["Art", "Coding", "Music", "Reading"], unit: "Not specified")
        let narration = ChartNarration(trusted, locale: english)
        #expect(narration.summary == "Art has the highest value at about 42, followed by Coding at about 34 and Music at about 26. Reading has the lowest value at about 15. The gap between the highest and lowest values is about 27.")
        for forbidden in ["bar chart", "Verified chart", "Number of categories", "units not specified", "Arithmetic mean", "confidence", "Confirmed by you", "42.101983298687145", "Next", "physical accuracy"] {
            #expect(!narration.summary.localizedCaseInsensitiveContains(forbidden))
        }
        #expect(narration.summary.components(separatedBy: ". ").count == 3)
        #expect(trusted.values[0].value == Decimal(string: "42.101983298687145"))
        let unitSummary = ChartNarration(try snapshot(["10", "20"], kind: kind, labels: ["Art", "Reading"], unit: "participants"), locale: english).summary
        #expect(unitSummary.contains("20 participants") && !unitSummary.contains("USD"))
        print("NARRATION EXAMPLE|\(kind.rawValue)|\(narration.summary)")
    }

    @Test func lineEndpointsAndPieSharesUseAppropriateLanguage() throws {
        let line = ChartNarration(try snapshot(["10", "18", "15"], kind: .line, labels: ["January", "February", "March"], unit: "participants"), locale: english).summary
        #expect(line == "Values go from 10 participants at January to 15 participants at March. They finish 5 participants higher than they started. The observed values rise and fall along the way.")
        #expect(!line.contains("per day") && !line.contains("predict") && !line.contains("Line graph"))
        let pie = ChartNarration(try snapshot(["60", "25", "15"], kind: .pie, labels: ["Art", "Music", "Reading"]), locale: english).summary
        #expect(pie == "Art has the largest share at 60 percent. Reading has the smallest share at 15 percent. The gap between the largest and smallest shares is 45 percentage points.")
        #expect(!pie.contains("45 percent.") && !pie.contains("participants"))
        print("NARRATION EXAMPLE|Line|\(line)")
        print("NARRATION EXAMPLE|Pie|\(pie)")
    }

    @Test func tiesSingleValuesZeroNegativeAndSmallDecimals() throws {
        let tied = ChartNarration(try snapshot(["-2", "-2", "-10"], labels: ["Art", "Coding", "Reading"], unit: "Not specified"), locale: english).summary
        #expect(tied.contains("Art and Coding are tied") && tied.contains("gap between the highest and lowest values is 8"))
        let allEqual = ChartNarration(try snapshot(["0", "0"]), locale: english).summary
        #expect(allEqual.contains("All values are equal at 0 USD"))
        let single = ChartNarration(try snapshot(["0.001"], unit: "Not specified"), locale: english).summary
        #expect(single.contains("between 0 and 0.01") && single.contains("only value shown"))
        let pieTie = ChartNarration(try snapshot(["50", "50"], kind: .pie), locale: english).summary
        #expect(pieTie.contains("equal shares of 50 percent"))
        let zeroStart = ChartNarration(try snapshot(["0", "5"], kind: .line, unit: "Not specified"), locale: english).summary
        #expect(zeroStart.contains("5 higher") && !zeroStart.contains("percent"))
        let negativeStart = ChartNarration(try snapshot(["-5", "-8"], kind: .line), locale: english).summary
        #expect(negativeStart.contains("3 USD lower") && !negativeStart.contains("percent"))
        let fractionalShare = ChartNarration(try snapshot(["60.12", "39.88"], kind: .pie), locale: english).summary
        #expect(fractionalShare.contains("60.12 percent") && fractionalShare.contains("20.24 percentage points"))
    }

    @Test func estimatedValuesAreStillApproximateAndSpokenFormattingIsBounded() throws {
        let session = try review()
        let trusted = try #require(session.snapshot)
        let summary = ChartNarration(trusted, locale: english).summary
        #expect(summary.contains("about 42 participants") && summary.contains("about 15 participants"))
        #expect(ChartNumberFormat.spoken(Decimal(string: "10.49")!, locale: english) == "10.49")
        #expect(ChartNumberFormat.spoken(Decimal(string: "-26.956149159744903")!, locale: english) == "about -27")
        #expect(ChartNumberFormat.spoken(Decimal(string: "1.2345")!, locale: english) == "about 1.23")
        #expect(ChartNumberFormat.spoken(Decimal(string: "42")!, estimated: true, locale: english) == "about 42")
        #expect(ChartNumberFormat.spoken(Decimal(string: "60.12")!, preferWhole: false, locale: english) == "60.12")
    }

    @Test func summaryAndPointSpeechUpdateOnlyAfterReverification() throws {
        var chart = try ChartInsightsTests().chart(["10", "20"], labels: ["Art", "Reading"], unit: "participants")
        let old = try chart.trustedSnapshot()
        var explorer = ChartExplorer(old)
        let oldContent = VerifiedSpeechContent.chart(explorer)
        var playback = SpeechPlayback()
        playback.synchronize(explorer.insights.snapshot)
        let started = playback.start(oldContent, requestID: UUID())
        #expect(started && oldContent.text == explorer.naturalSummary)
        explorer.next()
        #expect(VerifiedSpeechContent.point(explorer)?.text == "Art: 10 participants.")
        try chart.edit(at: 0, text: "30")
        playback.synchronize(nil)
        #expect(playback.content == nil && !explorer.isCurrent(for: try? chart.trustedSnapshot()))
        let rejected = playback.start(oldContent, requestID: UUID())
        #expect(!rejected)
        try chart.confirm(at: 0)
        let changed = try chart.trustedSnapshot()
        let newContent = VerifiedSpeechContent.chart(ChartExplorer(changed))
        playback.synchronize(changed)
        let staleRejected = playback.start(oldContent, requestID: UUID())
        #expect(!staleRejected && newContent.text != oldContent.text)
        let accepted = playback.start(newContent, requestID: UUID())
        #expect(accepted && newContent.text.contains("Art has the highest value at 30 participants"))
    }

    @Test(arguments: ChartKind.allCases)
    func explanationPlaybackContainsOnlyValidatedTakeaways(_ kind: ChartKind) async throws {
        let trusted = try snapshot(kind == .pie ? ["40", "60"] : ["10", "20"], kind: kind,
            labels: ["Art", "Reading"], unit: kind == .pie ? "%" : "Not specified")
        let payload = ExplanationPayload.meaning(ChartCalculations.calculate(trusted))
        for available in [true, false] {
            let provider = ListeningExplanationProvider(available: available)
            let explanation = try await ChartExplanationService().explain(trusted, provider: provider)
            let spoken = try #require(VerifiedSpeechContent.explanation(explanation, snapshot: trusted))
            #expect(spoken.text == payload.renderSpokenMeaning(payload.facts))
            #expect(!spoken.text.localizedCaseInsensitiveContains("units") && !spoken.text.contains("confirmed"))
            #expect(!spoken.text.contains(kind.rawValue) && !spoken.text.contains(explanation.attribution))
            #expect(spoken.text.components(separatedBy: ". ").count == 2)
            #expect(explanation.text.contains("Use it to") && !explanation.attribution.isEmpty)
        }
    }
}

private struct ListeningExplanationProvider: ExplanationModelProvider {
    let available: Bool
    func availability() async -> ExplanationModelAvailability { available ? .available : .unavailable(.deviceUnsupported) }
    func selectFacts(_ payload: ExplanationPayload) async throws -> [String] { payload.facts.map(\.id) }
}
