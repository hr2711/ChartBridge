import Testing
import Foundation

struct ReviewVerificationTests {
    @Test func geometricProposalKeepsUnsupportedPrecisionUnverified() throws {
        var c = try chart()
        try c.proposeEstimate(at: 0, text: "0.0000001")
        #expect(c.categories[0].state.valueCandidate?.value == Decimal(string: "0.0000001")!)
        try c.proposeEstimate(at: 1, text: "1e-100")
        #expect(c.categories[1].state.valueCandidate?.origin == .geometricEstimate)
        #expect(c.categories[1].state.valueCandidate?.rawText == "1e-100")
        #expect(throws: ChartValidationError.self) { try c.confirm(at: 1) }
        #expect(throws: ChartValidationError.self) { try c.trustedSnapshot() }
    }
    @Test func pieUnitCannotCreateMislabeledTrustedSnapshot() throws {
        var c = try chart(.pie)
        try c.edit(at: 0, text: "40"); try c.edit(at: 1, text: "60")
        try c.confirm(at: 0); try c.confirm(at: 1)
        c.updateUnit("USD")
        #expect(c.status == .needsReview)
        #expect(c.validationMessages.contains { $0.contains("percent (%)") })
        #expect(throws: ChartValidationError.self) { try c.confirm(at: 0) }
        #expect(throws: ChartValidationError.self) { try c.trustedSnapshot() }
        c.updateUnit("%")
        try c.confirm(at: 0); try c.confirm(at: 1)
        #expect(try c.trustedSnapshot().unit == "%")
    }

    @MainActor @Test func correctionProgressPartitionsEveryState() async throws {
        let fixture = ExtractionFixtures.make(kind: .pie)
        let source = try SourceProvenance(fileName: "synthetic.png", mediaType: "image/png")
        let output = try #require(try await ChartAnalyzer().extract(data: fixture.data, ocr: fixture.idealOCR, source: source).output)
        var r = try ReviewSession(output: output, locale: Locale(identifier: "en_US"))
        for i in r.chart.categories.indices { try r.resolve(at: i); try r.confirm(at: i) }
        #expect(r.snapshot != nil)
        try r.label(at: 0, text: r.chart.categories[1].label)
        #expect(r.confirmedCount == 1)
        #expect(r.correctionCount == 2)
        #expect(r.awaitingCount == 0)
        try r.label(at: 0, text: "")
        #expect(r.correctionCount == 1)
        try r.label(at: 0, text: "New slice")
        try r.value(at: 0, text: "101")
        #expect(r.correctionCount == 1)
        try r.reject(at: 0)
        #expect(r.rejectedCount == 1)
        #expect(r.correctionCount == 0)
        try r.value(at: 1, text: "")
        #expect(r.correctionCount == 1)
        #expect(r.confirmedCount + r.rejectedCount + r.correctionCount + r.awaitingCount == r.chart.categories.count)
        #expect(r.snapshot == nil)
    }

    @Test func localizedInputBoundsAndSigns() throws {
        #expect(throws: ChartValidationError.self) { try LocalizedChartNumber.parse(String(repeating: "1", count: 100_000), locale: .init(identifier: "en_US")) }
        let formatter = NumberFormatter(); formatter.locale = Locale(identifier: "ar_EG")
        #expect(try LocalizedChartNumber.parse(formatter.minusSign + "١٢٫٥", locale: formatter.locale) == Decimal(string: "-12.5")!)
        #expect(try LocalizedChartNumber.parse("-0", locale: .init(identifier: "en_US")) == 0)
    }

    @Test func printedGeometryAgreementUsesDocumentedTolerance() throws {
        let source = try SourceProvenance(fileName: "synthetic.png", mediaType: "image/png")
        let box = ImageBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        let ocr = OCRDocument(sourceID: "test", observations: [], width: 800, height: 800, orientation: 1)
        let output = ExtractionOutput(sourceID: "test", source: source, kind: .pie, title: nil, xAxisTitle: nil, yAxisTitle: nil, unit: "%", values: [], calibration: nil, geometryEvidence: "Measured circle", ocr: ocr, diagnostics: [])
        func value(_ printed: Double?, uncertainty: Double = 1) -> ExtractedValue {
            .init(order: 0, category: "A", value: 50, printedValue: printed, method: "Measured angle", region: box, observations: [], uncertainty: uncertainty, diagnostics: [])
        }
        #expect(EvidenceSupport.agreement(output: output, value: value(52)) == .agrees)
        #expect(EvidenceSupport.agreement(output: output, value: value(52.01)) == .conflicts)
        #expect(EvidenceSupport.agreement(output: output, value: value(nil)) == .unavailable)
        #expect(EvidenceSupport.agreement(output: output, value: value(.nan)) == .unreliable)
        #expect(EvidenceSupport.label(output: output, value: value(60)) == "Conflicting evidence")
        #expect(EvidenceSupport.label(output: output, value: value(50, uncertainty: -.infinity)) == "Unable to estimate reliably")
    }

    @MainActor @Test func extractedReviewSessionsPreserveEvidence() async throws {
        for kind in ChartKind.allCases {
            let fixture = ExtractionFixtures.make(kind: kind)
            let source = try SourceProvenance(fileName: "synthetic-review.png", mediaType: "image/png")
            let result = try await ChartAnalyzer().extract(data: fixture.data, ocr: fixture.idealOCR, source: source)
            let output = try #require(result.output)
            var review = try ReviewSession(output: output, locale: Locale(identifier: "fr_FR"))
            #expect(review.snapshot == nil)
            for index in output.values.indices {
                let candidate = try #require(review.chart.categories[index].state.valueCandidate?.value)
                #expect(candidate == Decimal(string: String(output.values[index].value), locale: Locale(identifier: "en_US_POSIX")))
            }
            for index in review.chart.categories.indices {
                try review.resolve(at: index)
                try review.confirm(at: index)
            }
            #expect(review.snapshot?.kind == kind)
            #expect(review.confirmedCount == output.values.count)
            try review.value(at: 0, text: "")
            #expect(review.snapshot == nil)
            #expect(review.correctionCount == 1)
            #expect(review.evidence.sourceID == output.sourceID)
            #expect(review.evidence.values[0].value == output.values[0].value)
            #expect(throws: ChartValidationError.self) { try review.resolve(at: 99) }
        }
    }
    @Test func evidenceLabelsAreSeparateFromVerification() throws {
        let box = ImageBox(x: 0.1, y: 0.1, width: 0.2, height: 0.2)
        let source = try SourceProvenance(fileName: "synthetic.png", mediaType: "image/png")
        func label(confidence: Float = 0.9, printed: Double? = 50, warnings: [String] = []) -> String {
            let text = OCRText(id: 0, raw: "50%", alternatives: [], confidence: confidence, box: box, sourceID: "synthetic")
            let value = ExtractedValue(order: 0, category: "A", value: 50, printedValue: printed, method: "Measured slice", region: box, observations: [text], uncertainty: 0.5, diagnostics: warnings)
            let output = ExtractionOutput(sourceID: "synthetic", source: source, kind: .pie, title: nil, xAxisTitle: nil, yAxisTitle: nil, unit: "%", values: [value], calibration: nil, geometryEvidence: "Synthetic complete pie", ocr: OCRDocument(sourceID: "synthetic", observations: [text], width: 800, height: 800, orientation: 1), diagnostics: ["All values are unverified."])
            #expect(!value.isVerified)
            return EvidenceSupport.label(output: output, value: value)
        }
        #expect(label() == "Strong supporting evidence")
        #expect(label(confidence: 0.3) == "Limited supporting evidence")
        #expect(label(confidence: .nan) == "Limited supporting evidence")
        #expect(label(confidence: 1.1) == "Limited supporting evidence")
        #expect(label(printed: nil) == "Limited supporting evidence")
        #expect(label(warnings: ["Printed value disagrees with geometry."]) == "Conflicting evidence")
    }
    func chart(_ kind: ChartKind = .verticalBar) throws -> BarChart {
        try BarChart(kind: kind, title: "Review example", horizontalAxis: "Category", verticalAxis: "Value", unit: kind == .pie ? "%" : "Count",
            source: SourceProvenance(fileName: "synthetic.png", mediaType: "image/png"), categories: [("A", 0), ("B", 1)])
    }
    @Test(arguments: ChartKind.allCases)
    func allKindsUseExistingEngine(_ kind: ChartKind) throws {
        var c = try chart(kind)
        try c.proposeEstimate(at: 0, text: "40", ambiguous: true)
        try c.proposeEstimate(at: 1, text: "60")
        #expect(throws: ChartValidationError.self) { try c.confirm(at: 0) }
        try c.editLocalized(at: 0, text: "40", locale: Locale(identifier: "en_US"))
        try c.confirm(at: 0)
        #expect(throws: ChartValidationError.self) { try c.trustedSnapshot() }
        try c.confirm(at: 1)
        #expect(c.status == .userVerified)
        #expect(try c.trustedSnapshot().kind == kind)
        #expect(try c.trustedSnapshot().values.map(\.order) == [0, 1])
        try c.editLocalized(at: 0, text: "bad", locale: Locale(identifier: "en_US"))
        #expect(c.status == .partiallyVerified)
        #expect(throws: ChartValidationError.self) { try c.confirm(at: 0) }
        #expect(throws: ChartValidationError.self) { try c.trustedSnapshot() }
        try c.editLocalized(at: 0, text: "", locale: Locale(identifier: "en_US"))
        #expect(c.categories[0].state == .missing)
        try c.editLocalized(at: 0, text: "40", locale: Locale(identifier: "en_US"))
        try c.confirm(at: 0); try c.reject(at: 0)
        #expect(throws: ChartValidationError.self) { try c.trustedSnapshot() }
        #expect(throws: ChartValidationError.self) { try c.confirm(at: 0) }
    }
    @Test func localeParsingAndExactDrafts() throws {
        #expect(try LocalizedChartNumber.parse("-12,50", locale: Locale(identifier: "fr_FR")) == Decimal(string: "-12.5")!)
        #expect(try LocalizedChartNumber.parse("٠٫٥", locale: Locale(identifier: "ar_EG")) == Decimal(string: "0.5")!)
        for text in ["1,200", "1.5x", "NaN", "1e3", " 2", "1."] {
            #expect(throws: ChartValidationError.self) { try LocalizedChartNumber.parse(text, locale: Locale(identifier: "en_US")) }
        }
        var c = try chart()
        try c.editLocalized(at: 0, text: "-12,50", locale: Locale(identifier: "fr_FR"))
        #expect(c.categories[0].state.valueCandidate?.rawText == "-12,50")
    }
    @Test func metadataAndLabelEditsRevoke() throws {
        var c = try chart()
        for i in 0..<2 { try c.edit(at: i, text: "0"); try c.confirm(at: i) }
        try c.updateLabel(at: 0, label: "B")
        #expect(c.status != .userVerified)
        #expect(throws: ChartValidationError.self) { try c.confirm(at: 0) }
        try c.updateLabel(at: 0, label: "Renamed")
        try c.confirm(at: 0)
        c.updateTitle("New title")
        #expect(c.status == .needsReview)
        #expect(throws: ChartValidationError.self) { try c.trustedSnapshot() }
        for i in 0..<2 { try c.confirm(at: i) }
        c.updateUnit("")
        #expect(!c.validationMessages.isEmpty)
        #expect(throws: ChartValidationError.self) { try c.confirm(at: 0) }
        #expect(throws: ChartValidationError.self) { try c.trustedSnapshot() }
    }
    @Test func pieRangeAndTotalNeverNormalize() throws {
        var c = try chart(.pie)
        try c.edit(at: 0, text: "-1")
        #expect(throws: ChartValidationError.self) { try c.confirm(at: 0) }
        try c.edit(at: 0, text: "40"); try c.edit(at: 1, text: "50")
        try c.confirm(at: 0); try c.confirm(at: 1)
        #expect(c.status == .partiallyVerified)
        #expect(throws: ChartValidationError.self) { try c.trustedSnapshot() }
        #expect(c.categories[1].state.valueCandidate?.value == 50)
        try c.edit(at: 1, text: "59.6"); try c.confirm(at: 1)
        #expect(try c.trustedSnapshot().values[1].value == Decimal(string: "59.6")!)
        try c.edit(at: 1, text: "60.6"); try c.confirm(at: 1)
        #expect(throws: ChartValidationError.self) { try c.trustedSnapshot() }
        try c.edit(at: 1, text: "101")
        #expect(throws: ChartValidationError.self) { try c.confirm(at: 1) }
    }
}

struct ChartDomainTests {
    func chart(_ categories: [(String, Int)] = [("A", 0), ("B", 1)]) throws -> BarChart {
        try BarChart(title: "Sales", horizontalAxis: "Category", verticalAxis: "Amount", unit: "USD",
                     source: SourceProvenance(fileName: "chart.png", mediaType: "image/png"), categories: categories)
    }

    @Test func verificationAndSnapshot() throws {
        var c = try chart()
        #expect(c.status == .needsReview)
        #expect(throws: ChartValidationError.self) { try c.trustedSnapshot() }
        try c.propose(at: 0, text: "0", confidence: 0.9)
        #expect(c.status == .needsReview)
        try c.confirm(at: 0)
        #expect(c.status == .partiallyVerified)
        try c.edit(at: 1, text: "-12.50")
        try c.confirm(at: 1)
        #expect(c.status == .userVerified)
        let snapshot = try c.trustedSnapshot()
        #expect(snapshot.values.map(\.value) == [0, Decimal(string: "-12.50")!])
        #expect(snapshot.values.map(\.order) == [0, 1])
        try c.edit(at: 0, text: "0")
        #expect(c.status == .partiallyVerified)
        #expect(throws: ChartValidationError.self) { try c.trustedSnapshot() }
        #expect(snapshot.values[0].value == 0)
        #expect(c.categories[0].history.count == 3)
        try c.confirm(at: 0)
        try c.reject(at: 0)
        #expect(c.status == .partiallyVerified)
        #expect(throws: ChartValidationError.self) { try c.trustedSnapshot() }
    }

    @Test func ambiguityRejectionAndInvalidConfidence() throws {
        var c = try chart()
        try c.propose(at: 0, text: "1O", confidence: 0.2)
        #expect(throws: ChartValidationError.self) { try c.confirm(at: 0) }
        try c.reject(at: 0)
        #expect(throws: ChartValidationError.self) { try c.confirm(at: 0) }
        try c.edit(at: 0, text: "10")
        try c.confirm(at: 0)
        #expect(c.status == .partiallyVerified)
        for confidence in [-0.1, 1.1, Double.nan, Double.infinity] {
            #expect(throws: ChartValidationError.self) { try c.propose(at: 1, text: "1", confidence: confidence) }
        }
        try c.propose(at: 1, text: "5", ambiguous: true)
        #expect(throws: ChartValidationError.self) { try c.confirm(at: 1) }
        #expect(throws: ChartValidationError.self) { try c.edit(at: 99, text: "1") }
    }

    @Test(arguments: ["", " ", "1,200", "12x", "NaN", "1e9", ".5", "1.", "1\n", "99999999999999999999999999999"])
    func invalidNumbers(_ text: String) {
        #expect(throws: ChartValidationError.self) { try BarChart.parse(text) }
    }

    @Test func labelsAndOrder() {
        #expect(throws: ChartValidationError.self) { try chart([]) }
        #expect(throws: ChartValidationError.self) { try chart([(" ", 0)]) }
        #expect(throws: ChartValidationError.self) { try chart([("A", 0), (" a ", 1)]) }
        #expect(throws: ChartValidationError.self) { try chart([("A", 1)]) }
        #expect(throws: ChartValidationError.self) { try chart([("A", 0), ("B", 0)]) }
        #expect(throws: ChartValidationError.self) { try SourceProvenance(fileName: "", mediaType: "image/png") }
        #expect(throws: ChartValidationError.self) {
            try BarChart(title: " ", horizontalAxis: "X", verticalAxis: "Y", unit: "count",
                         source: SourceProvenance(fileName: "chart.png", mediaType: "image/png"),
                         categories: [("A", 0)])
        }
    }
}
