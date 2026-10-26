import Testing
import Foundation

/// Tolerances fixed before evaluating the corpus: 2 absolute axis units, 2 percentage points.
/// Report failures without changing tolerances. Unsupported fixtures must not yield clean candidates.
@Suite(.serialized)
struct ExtractionTests {
    static let tolerance = 2.0
    static let barVariants = ["basic","colors","unequal","grid","decimal","negative","nonzero","printed","monochrome","conflict","missingTicks","grouped","stacked","3D","ocrError","rotated","lowResolution"]
    static let horizontalVariants = ["basic","longLabels","colors","negative","grid","printed","conflict","missingTicks","grouped","stacked"]
    static let lineVariants = ["basic","decreasing","decimal","grid","printed","missingMarker","intersecting","missingTicks","log"]
    static let pieVariants = ["basic","four","printed","similar","missingLabels","donut","exploded","3D","conflict"]

    @MainActor
    func evaluate(kind: ChartKind, variants: [String], realOCR: Bool) async throws {
        for variant in variants {
            let f = ExtractionFixtures.make(kind:kind,variant:variant)
            let source = try SourceProvenance(fileName:"synthetic.png",mediaType:"image/png")
            let started = ContinuousClock.now
            let result: ExtractionResult
            if realOCR {
                let imported = try await ChartImporter().decode(data:f.data,fileName:"synthetic.png")
                result = try await ChartAnalyzer().analyze(imported)
            } else {
                result = try await ChartAnalyzer().extract(data:f.data,ocr:f.idealOCR,source:source)
            }
            var correctCategories = 0, correctValues = 0
            var errors: [Double] = []
            if let output = result.output {
                for v in output.values {
                    if let index = f.categories.firstIndex(of:v.category) {
                        correctCategories += 1
                        let error = abs(v.value-f.values[index]); errors.append(error)
                        if error <= Self.tolerance { correctValues += 1 }
                    }
                }
                #expect(output.values.allSatisfy { !$0.isVerified })
                let review = try output.reviewChart(title:"Test",horizontalAxis:"Category",verticalAxis:"Value",unit:"units")
                #expect(review.status == .needsReview)
                #expect(review.kind == kind)
                #expect(throws: ChartValidationError.self) { try review.trustedSnapshot() }
            }
            let clean: Bool
            if case .candidates = result { clean = true } else { clean = false }
            let success = result.output?.kind == kind && correctCategories == f.categories.count && correctValues == f.values.count
            let mae = errors.isEmpty ? "n/a" : String(format:"%.4f",errors.reduce(0,+)/Double(errors.count))
            print("ACCURACY|\(realOCR ? "E2E" : "Geometry")|\(f.name)|\(result.output?.kind.rawValue ?? result.summary)|\(correctCategories)/\(f.categories.count)|\(correctValues)/\(f.values.count)|MAE=\(mae)|clean=\(clean)|elapsed=\(started.duration(to:.now))|\(result.diagnostics.joined(separator:"; "))")
            if !f.shouldReject {
                #expect(success, Comment(rawValue:f.name+" — "+result.diagnostics.joined(separator:"; ")))
                if variant == "conflict" { #expect(!clean) }
            } else {
                #expect(!clean, Comment(rawValue:"False confident extraction: "+f.name))
            }
        }
    }

    @MainActor @Test func verticalGeometry() async throws { try await evaluate(kind:.verticalBar,variants:Self.barVariants,realOCR:false) }
    @MainActor @Test func verticalEndToEnd() async throws { try await evaluate(kind:.verticalBar,variants:Self.barVariants,realOCR:true) }
    @MainActor @Test func horizontalGeometry() async throws { try await evaluate(kind:.horizontalBar,variants:Self.horizontalVariants,realOCR:false) }
    @MainActor @Test func horizontalEndToEnd() async throws { try await evaluate(kind:.horizontalBar,variants:Self.horizontalVariants,realOCR:true) }
    @MainActor @Test func lineGeometry() async throws { try await evaluate(kind:.line,variants:Self.lineVariants,realOCR:false) }
    @MainActor @Test func lineEndToEnd() async throws { try await evaluate(kind:.line,variants:Self.lineVariants,realOCR:true) }
    @MainActor @Test func pieGeometry() async throws { try await evaluate(kind:.pie,variants:Self.pieVariants,realOCR:false) }
    @MainActor @Test func pieEndToEnd() async throws { try await evaluate(kind:.pie,variants:Self.pieVariants,realOCR:true) }
}
