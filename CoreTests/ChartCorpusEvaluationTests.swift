import Foundation
import Testing
#if SWIFT_PACKAGE
@testable import ChartBridgeMath
#endif

/// Opt-in, local-only diagnostic corpus. Never downloads data during a test or
/// substitutes expected values into production OCR. See Docs/PublicCorpus.md.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["CHARTBRIDGE_EVALUATE_CORPUS"] == "1"))
struct ChartCorpusEvaluationTests {
    private struct Fixture {
        let file: String
        let kind: ChartKind?
        let labels: [String]
        let values: [Double]
        let tolerance: Double
        var external = false
        var multipage = false
    }

    @Test func localCorpusMetricsAndTrustBoundary() async throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let fixtures: [Fixture] = [
            .init(file: "01_vertical_basic.png", kind: .verticalBar, labels: ["Beans", "Carrots", "Peas"], values: [20,35,28], tolerance: 2),
            .init(file: "02_vertical_negative.png", kind: .verticalBar, labels: ["North", "Central", "South"], values: [-20,30,10], tolerance: 2),
            .init(file: "03_vertical_gridlines.png", kind: .verticalBar, labels: ["Reading", "Art", "Music", "Coding"], values: [15,42,26,34], tolerance: 2),
            .init(file: "04_horizontal_basic.png", kind: .horizontalBar, labels: ["Garden", "Library", "Shelter"], values: [15,30,22], tolerance: 2),
            .init(file: "05_horizontal_long_labels.png", kind: .horizontalBar, labels: ["Neighborhood cleanup", "After-school tutoring", "Public library workshops"], values: [24,38,17], tolerance: 2),
            .init(file: "06_horizontal_negative.png", kind: .horizontalBar, labels: ["January", "February", "March"], values: [-20,30,10], tolerance: 2),
            .init(file: "07_line_basic.png", kind: .line, labels: ["Week A", "Week B", "Week C", "Week D"], values: [10,25,18,40], tolerance: 2),
            .init(file: "08_line_declining.png", kind: .line, labels: ["Week A", "Week B", "Week C", "Week D"], values: [45,33,24,12], tolerance: 2),
            .init(file: "09_line_gridlines.png", kind: .line, labels: ["Week A", "Week B", "Week C", "Week D"], values: [15,32,22,44], tolerance: 2),
            .init(file: "10_pie_basic.png", kind: .pie, labels: ["Walking", "Bus", "Cycling"], values: [45,30,25], tolerance: 2),
            .init(file: "11_pie_four_slices.png", kind: .pie, labels: ["Parks", "Library", "Roads", "Arts"], values: [40,27,21,12], tolerance: 2),
            .init(file: "12_pie_printed_percentages.png", kind: .pie, labels: ["Science", "Art", "Music"], values: [50,30,20], tolerance: 2),
            .init(file: "13_multipage_test.pdf", kind: nil, labels: [], values: [], tolerance: 0, multipage: true),
            .init(file: "14_chart_single_page.pdf", kind: .verticalBar, labels: ["Beans", "Carrots", "Peas"], values: [20,35,28], tolerance: 2),
            .init(file: "15_unsupported_chart.png", kind: nil, labels: [], values: [], tolerance: 0),
            // Independent visual estimates from a photographed, fictional chart;
            // these are not exact census observations. Do not label as real data.
            .init(file: "commons-bar.jpg", kind: .verticalBar, labels: ["Park City", "Hillside", "Elmdale", "River Valley", "Cedar Grove"], values: [4000,3500,2500,4500,2000], tolerance: 100, external: true),
            // Published, rounded table percentages. Do not renormalize their sum.
            .init(file: "canada-ghg-2024.png", kind: .pie, labels: ["Oil and Gas", "Transport", "Buildings", "Heavy Industry", "Agriculture", "Electricity", "Waste and Others"], values: [30,22,12,11,10,7.2,6.9], tolerance: 2, external: true)
        ]
        for fixture in fixtures {
            let directory = fixture.external ? "work/PublicChartCorpus" : "TestCharts"
            let url = root.appendingPathComponent(directory).appendingPathComponent(fixture.file)
            #expect(FileManager.default.fileExists(atPath: url.path), "Regenerate or download only the documented public corpus first")
            let started = ContinuousClock.now
            do {
                let chart = try await ChartImporter().load(url: url)
                let result = try await ChartAnalyzer().analyze(chart)
                let elapsed = started.duration(to: .now)
                var row: [String: Any] = ["file": fixture.file, "expectedType": fixture.kind?.rawValue ?? "unsupported", "result": result.summary,
                    "external": fixture.external, "expectedLabels": fixture.labels.count, "seconds": Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18]
                if let output = result.output {
                    let matched = output.values.compactMap { value -> (Double, Double, Bool)? in
                        guard let index = fixture.labels.firstIndex(of: value.category) else { return nil }
                        let error = abs(value.value - fixture.values[index])
                        return (error, fixture.values[index] == 0 ? .nan : error / abs(fixture.values[index]), error > value.uncertainty)
                    }
                    row["correctType"] = output.kind == fixture.kind
                    row["returnedType"] = output.kind.rawValue
                    row["returnedLabels"] = output.values.map(\.category)
                    row["returnedValues"] = output.values.map(\.value)
                    row["matchedLabels"] = matched.count
                    row["absoluteErrors"] = matched.map(\.0)
                    row["relativeErrors"] = matched.map(\.1).filter(\.isFinite)
                    row["outsideRasterUncertainty"] = matched.filter(\.2).count
                    row["withinTolerance"] = matched.filter { $0.0 <= fixture.tolerance }.count
                    if case .candidates = result {
                        row["falseClean"] = output.kind != fixture.kind || matched.count != fixture.labels.count || matched.contains { $0.0 > fixture.tolerance }
                    } else { row["falseClean"] = false }
                    #expect(output.values.allSatisfy { !$0.isVerified })
                    let session = try? ReviewSession(output: output, locale: Locale(identifier: "en_US"))
                    #expect(session?.snapshot == nil, "No recognition outcome may confirm data")
                } else { row["correctType"] = false; row["matchedLabels"] = 0; row["falseClean"] = false }
                row["diagnostics"] = result.diagnostics
                print("CORPUS|" + String(decoding: try JSONSerialization.data(withJSONObject: row, options: [.sortedKeys]), as: UTF8.self))
            } catch let error as ImportFailure {
                #expect(fixture.multipage && error == .multiplePages, "Unexpected import failure for documented fixture")
                print("CORPUS|{\"file\":\"\(fixture.file)\",\"result\":\"import rejected: \(error)\"}")
            }
        }
    }
}
