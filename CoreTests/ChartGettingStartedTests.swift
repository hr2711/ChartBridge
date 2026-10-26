import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import ChartBridgeMath
#endif

@Suite struct ChartGettingStartedTests {
    @Test func onboardingAdvancesSkipsAndPersistsOnlyCompletion() throws {
        let suite = "ChartBridge-Onboarding-Test-" + UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(!OnboardingPreferences.isComplete(in: defaults))
        var progress = OnboardingProgress()
        #expect(progress.step == .importChart && !progress.completed)
        progress.advance(); #expect(progress.step == .verify && !progress.completed)
        progress.advance(); #expect(progress.step == .explore && !progress.completed)
        progress.advance(); #expect(progress.completed)
        OnboardingPreferences.complete(in: defaults)
        let reopened = try #require(UserDefaults(suiteName: suite))
        #expect(OnboardingPreferences.isComplete(in: reopened))
        var skipped = OnboardingProgress(); skipped.skip()
        #expect(skipped.completed && skipped.step == .importChart)
        // Help can always start a fresh presentation without deleting completion.
        #expect(OnboardingProgress().step == .importChart)
        #expect(OnboardingPreferences.isComplete(in: reopened))
    }

    @Test func recoveryExplainsTrustAndFallback() {
        #expect(RecoveryTopic.analysis.guidance.contains("one upright"))
        #expect(RecoveryTopic.verification.guidance.contains("explicitly confirmed"))
        #expect(RecoveryTopic.intelligence.guidance.contains("deterministically"))
        #expect(RecoveryTopic.storage.guidance.contains("keep this preview open"))
    }

    @Test(arguments: ChartSample.allCases)
    func samplesUseRealRecognitionAndRemainUnverified(_ sample: ChartSample) async throws {
        let expected: [ChartSample: [Int]] = [.vertical: [20,60,80], .horizontal: [20,60,80],
            .line: [20,60,40,80], .pie: [20,30,50]]
        #expect(sample.referenceValues == expected[sample])
        #expect(!sample.title.isEmpty && !sample.scenario.isEmpty && sample.labels.count == sample.referenceValues.count)
        let renderer = SampleChartRenderer()
        let bytes = try await renderer.render(sample)
        let second = try await renderer.render(sample)
        #expect(bytes == second)
        let imported = try await ChartImporter().decode(data: bytes, fileName: sample.title + ".png")
        #expect(imported.pixelWidth == 1000 && imported.pixelHeight == 800)
        let result = try await ChartAnalyzer().analyze(imported)
        let output = try #require(result.output, "Real OCR/geometry must return a reviewable sample, not a shortcut: \(result.summary), \(result.diagnostics)")
        #expect(output.kind == sample.kind)
        #expect(output.values.map(\.category) == sample.labels)
        for (value, expected) in zip(output.values, sample.referenceValues) {
            #expect(!value.isVerified && abs(value.value - Double(expected)) <= 2)
        }
        var review = try ReviewSession(output: output, locale: Locale(identifier: "en_US"))
        #expect(review.snapshot == nil && review.confirmedCount == 0)
        #expect(throws: ChartValidationError.self) { try review.chart.trustedSnapshot() }
        // Reference corrections are explicit simulated user edits in this test,
        // never inputs to ChartAnalyzer or automatically confirmed by the app.
        review.title(sample.title); review.unit(sample == .pie ? "%" : "count")
        for i in sample.labels.indices {
            try review.label(at: i, text: sample.labels[i])
            try review.value(at: i, text: String(sample.referenceValues[i]))
            try review.resolve(at: i)
            #expect(review.snapshot == nil)
            try review.confirm(at: i)
        }
        let trusted = try #require(review.snapshot)
        #expect(trusted.values.map(\.value) == sample.referenceValues.map { Decimal($0) })
        try review.value(at: 0, text: "1")
        #expect(review.snapshot == nil)
    }
}
