import Foundation

actor ChartAnalyzer {
    private let textEngine = VisionTextEngine()
    func analyze(_ chart: ImportedChart) async throws -> ExtractionResult {
        let ocr = try await textEngine.recognize(chart.previewPNG)
        try Task.checkCancellation()
        return try extract(data: chart.previewPNG, ocr: ocr, source: chart.source)
    }

    /// Geometry-only tests may supply known OCR observations. Production always uses Vision.
    func extract(data: Data, ocr: OCRDocument, source: SourceProvenance) throws -> ExtractionResult {
        try Task.checkCancellation()
        guard ocr.width >= 320, ocr.height >= 240, ocr.orientation == 1 else {
            return .unsupported(["Input is too small or not upright after normalization. Provide a clear upright image."], ocr)
        }
        let raster = try Raster(data: data)
        let mask = try raster.foregroundMask(excluding: ocr.observations)
        let components = try raster.components(mask: mask)
        var outputs: [ExtractionOutput] = [], reasons: [String] = []
        for kind in ChartKind.allCases {
            try Task.checkCancellation()
            do {
                let output: ExtractionOutput
                switch kind {
                case .verticalBar: output = try BarExtractor.extract(vertical: true, raster: raster, components: components, ocr: ocr, source: source)
                case .horizontalBar: output = try BarExtractor.extract(vertical: false, raster: raster, components: components, ocr: ocr, source: source)
                case .line: output = try LineExtractor.extract(raster: raster, mask: mask, ocr: ocr, source: source)
                case .pie: output = try PieExtractor.extract(raster: raster, mask: raster.foregroundMask(excluding: []), ocr: ocr, source: source)
                }
                guard Set(output.values.map { $0.category.lowercased() }).count == output.values.count else {
                    throw ExtractionIssue("Duplicate category names require review.")
                }
                outputs.append(output)
            } catch let issue as ExtractionIssue { reasons.append("\(kind.rawValue): \(issue.message)") }
        }
        if outputs.count > 1 { return .ambiguous(outputs.map(\.kind), reasons+["More than one geometric interpretation is plausible."], ocr) }
        guard let output = outputs.first else { return .unsupported(reasons,ocr) }
        return output.diagnostics.count > 1 ? .needsReview(output) : .candidates(output)
    }
}
