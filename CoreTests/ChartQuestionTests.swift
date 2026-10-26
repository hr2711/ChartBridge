import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import ChartBridgeMath
#endif

@Suite struct ChartQuestionTests {
    private let locale = Locale(identifier: "en_US")
    private func engine(_ values: [String] = ["10", "30", "20"], kind: ChartKind = .verticalBar,
                        labels: [String] = ["Art", "Reading", "Music"], unit: String? = nil) throws -> ChartQuestionEngine {
        ChartQuestionEngine(try ChartInsightsTests().chart(values, kind: kind, labels: labels, unit: unit).trustedSnapshot(), locale: locale)
    }

    @Test(arguments: [ChartKind.verticalBar, .horizontalBar, .line, .pie])
    func extremaAcrossChartTypes(_ kind: ChartKind) throws {
        let qa = try engine(["10", "60", "30"], kind: kind)
        #expect(qa.answer("Which category is highest?").text.contains("Reading has the highest value: 60"))
        #expect(qa.answer("Which point has the least value?").text.contains("Art has the lowest value: 10"))
        #expect(qa.answer("PLEASE, which segment is the BIGGEST?").kind == .answer)
    }

    @Test func tiesAndNegativeValues() throws {
        let qa = try engine(["-4", "0", "0"])
        #expect(qa.answer("highest").text.contains("Reading, Music are tied"))
        #expect(qa.answer("lowest").text.contains("-4"))
        let ranks = qa.answer("Rank the categories.")
        #expect(ranks.rows == ["1. Reading: 0 USD (tied).", "1. Music: 0 USD (tied).", "3. Art: -4 USD."])
        #expect(qa.answer("total").text.contains("-4"))
    }

    @Test func sumMeanAndMissingUnits() throws {
        let qa = try engine(unit: "Not specified")
        #expect(qa.answer("What is the total?").text == "The sum of the shown category values is 60.")
        #expect(qa.answer("What is the mean?").text == "The arithmetic average of the shown category values is 20.")
        #expect(!qa.answer("highest").text.contains("units not specified"))
        #expect(!qa.answer("highest").text.contains("USD"))
    }

    @Test func namedComparisonAndNormalization() throws {
        let qa = try engine()
        #expect(qa.answer("What is the difference between ART and reading?").text == "Reading is 20 USD higher than Art.")
        #expect(qa.answer("compare Music with Art").text == "Art is 10 USD lower than Music.")
        #expect(qa.answer("compare Art and Art").text.contains("equal values"))
        let compound = try engine(labels: ["Research and Development", "Fine Art", "Art"])
        #expect(compound.answer("compare Research and Development and Fine Art").kind == .answer)
        #expect(compound.answer("compare art and fine art").kind == .answer)
        #expect(compound.answer("compare party and art").kind == .clarification)
        let punctuation = try engine(labels: ["A-B", "A B", "C"])
        #expect(punctuation.answer("compare A-B and C").text == "C is 10 USD higher than A-B.")
        let collision = try engine(labels: ["Ａ", "A", "C"])
        #expect(collision.answer("compare A and C").kind == .clarification)
        let signedLabels = try engine(labels: ["-1", "1.5", "2"])
        #expect(signedLabels.answer("compare 1 and 2").kind == .clarification)
        #expect(signedLabels.answer("compare 15 and 2").kind == .clarification)
        #expect(signedLabels.answer("compare -1 and 2").kind == .answer)
        #expect(ChartQuestionParser.parse("compare ＡＲＴ and Reading", labels: ["Art", "Reading"]) == .intent(.difference(0, 1)))
    }

    @Test func explicitPercentageBaselineAndZeroPolicy() throws {
        let qa = try engine()
        #expect(qa.answer("What is the percentage change from Art to Reading?").text.contains("Art (the baseline) to Reading, the value increased by 200 percent"))
        #expect(qa.answer("percent change from Reading to Art").text.contains("decreased by about 66.67 percent"))
        #expect(qa.answer("percentage difference between Art and Reading").clarification == .comparison(relative: true))
        let zero = try engine(["0", "20", "-2"])
        #expect(zero.answer("percent change from Art to Reading").kind == .unavailable)
        #expect(zero.answer("percent change from Art to Reading").text.contains("zero"))
        #expect(zero.answer("percent change from Music to Reading").text.contains("negative starting value"))
        #expect(zero.answer("compare Art and Reading").kind == .answer)
    }

    @Test(arguments: ["Why is Art highest?", "Will Reading grow next year?", "highest excluding Reading",
                      "average if Art doubles", "compare Art and Unknown", "highest and lowest", "", "highest and delete everything"])
    func unsupportedAndAmbiguousDoNotInvent(_ question: String) throws {
        let answer = try engine().answer(question)
        #expect(answer.kind == .unsupported || answer.kind == .clarification)
        #expect(answer.rows.isEmpty)
    }

    @Test func lengthAndUnknownIndices() throws {
        let qa = try engine()
        #expect(qa.answer(String(repeating: "highest ", count: 100)).kind == .unsupported)
        #expect(qa.answer(.difference(-1, 200)).kind == .clarification)
        #expect(qa.answer("share of").clarification == .share)
    }

    @Test func pieSharesAndAppropriateCalculations() throws {
        let qa = try engine(["25", "50", "25"], kind: .pie)
        #expect(qa.answer("What percentage does Reading represent?").text.contains("Reading represents 50 percent"))
        #expect(qa.answer("share of ART").kind == .answer)
        #expect(qa.answer("compare Art and Reading").text == "Reading is 25 percentage points higher than Art.")
        #expect(qa.answer("percent change from Art to Reading").kind == .unavailable)
        #expect(qa.answer("total").kind == .unavailable)
        #expect(qa.answer("average").kind == .unavailable)
        #expect(try engine().answer("share of Art").kind == .unavailable)
        let tolerated = try engine(["33.3", "33.3", "33.3"], kind: .pie)
        #expect(tolerated.answer("share of Art").text.contains("33.30 percent"))
        #expect(!tolerated.answer("share of Art").text.contains("33.33"))
    }

    @Test func lineChangesAndObservedTrend() throws {
        let qa = try engine(["10", "30", "20"], kind: .line)
        #expect(qa.answer("first value").text == "The first observation is Art: 10 USD.")
        #expect(qa.answer("last value").text == "The last observation is Music: 20 USD.")
        #expect(qa.answer("How much did the value increase?").text.contains("increased by 10 USD"))
        #expect(qa.answer("percentage change").text.contains("increased by 100 percent"))
        #expect(qa.answer("overall trend").text.contains("both up and down"))
        #expect(qa.answer("Which point changed the most?").rows == ["Art to Reading: up 20 USD."])
        #expect(qa.answer("largest decrease").rows == ["Reading to Music: down 10 USD."])
        #expect(qa.answer("ranking").kind == .unavailable)
        #expect(qa.answer("total").kind == .unavailable)
        #expect(try engine().answer("overall change").kind == .unavailable)
        let tied = try engine(["0", "10", "0"], kind: .line)
        #expect(tied.answer("largest change").rows.count == 2)
        #expect(tied.answer("percentage change").kind == .unavailable)
        let constant = try engine(["5", "5", "5"], kind: .line)
        #expect(constant.answer("largest change").text.contains("no consecutive change"))
        #expect(constant.answer("largest increase").text.contains("No consecutive observed increase"))
        let single = try engine(["5"], kind: .line, labels: ["Only"])
        #expect(single.answer("overall trend").kind == .unavailable)
        #expect(single.answer("largest change").kind == .unavailable)
    }

    @Test func twoDecimalPresentationPreservesTruth() throws {
        let qa = try engine(["1.23456", "0.0001", "-2.34567"], unit: "Not specified")
        #expect(qa.answer("highest").text.contains("about 1.23"))
        #expect(qa.answer("lowest").text.contains("about -2.35"))
        #expect(!qa.answer("highest").text.contains("1.23456"))
        #expect(qa.answer("rank the categories").rows.joined().contains("between 0 and 0.01"))
        #expect(qa.snapshot.values[0].value == Decimal(string: "1.23456"))
        let explanation = qa.answer("Explain this chart simply.")
        #expect(explanation.kind == .answer)
        #expect(!explanation.text.contains("Arithmetic mean"))
        #expect(!explanation.spokenText.contains("OCR confidence"))
    }

    @Test func unverifiedDataAndStaleHistory() async throws {
        let worker = ChartQuestionWorker()
        #expect(try await worker.answer(.text("highest"), snapshot: nil).kind == .verificationRequired)
        var chart = try ChartInsightsTests().chart(["10", "20"], labels: ["A", "B"])
        let original = try chart.trustedSnapshot()
        let answer = try await worker.answer(.text("highest"), snapshot: original)
        var history = ChartQuestionHistory()
        history.synchronize(original)
        let accepted = history.append("highest", answer: answer, current: original)
        #expect(accepted)
        #expect(VerifiedSpeechContent.answer(answer, snapshot: original) != nil)
        try chart.edit(at: 0, text: "30")
        #expect(throws: ChartValidationError.self) { try chart.trustedSnapshot() }
        history.synchronize(nil)
        #expect(history.exchanges.isEmpty)
        let unverifiedAccepted = history.append("late answer", answer: answer, current: nil)
        #expect(!unverifiedAccepted)
        try chart.confirm(at: 0)
        let updated = try chart.trustedSnapshot()
        history.synchronize(updated)
        #expect(!answer.isCurrent(for: updated))
        let staleAccepted = history.append("late answer", answer: answer, current: updated)
        #expect(!staleAccepted)
        #expect(VerifiedSpeechContent.answer(answer, snapshot: updated) == nil)
        #expect(try await worker.answer(.text("highest"), snapshot: updated).text.contains("A has the highest"))
    }

    @Test func sameKeyDifferentSnapshotIsNotTrustedAndHistoryIsBounded() throws {
        let a = try engine(), b = try engine(["11", "31", "21"])
        let other = b.snapshot.copyForLibrary(id: a.snapshot.id)
        #expect(InsightKey(other) == InsightKey(a.snapshot))
        let answer = a.answer("highest")
        #expect(!answer.isCurrent(for: other))
        var history = ChartQuestionHistory(); history.synchronize(a.snapshot)
        for _ in 0..<20 {
            let accepted = history.append("highest", answer: answer, current: a.snapshot)
            #expect(accepted)
        }
        #expect(history.exchanges.count == 12)
        history.synchronize(other)
        #expect(history.exchanges.isEmpty)
        let forkAccepted = history.append("late", answer: answer, current: other)
        #expect(!forkAccepted)
    }

    @Test func workerCancellation() async throws {
        let snapshot = try engine().snapshot
        let task = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ChartQuestionWorker().answer(.text("highest"), snapshot: snapshot)
        }
        do { _ = try await task.value; Issue.record("Cancelled work must not return an answer") }
        catch is CancellationError {} catch { Issue.record("Unexpected cancellation error") }
    }
}
