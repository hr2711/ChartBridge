import Foundation

enum LineExtractor {
    static func extract(raster: Raster, mask: [Bool], ocr: OCRDocument,
                        source: SourceProvenance) throws -> ExtractionOutput {
        let components = try raster.components(mask: mask, separateColors: false)
        let lines = components.filter { $0.box.width > 0.15 && $0.fill < 0.35 && $0.box.height > 0.025 }
        guard lines.count == 1, let line = lines.first else {
            throw ExtractionIssue("A single connected line series with discrete point markers is required.")
        }
        let radius = max(2, Int(Double(min(raster.width,raster.height)) * 0.005))
        var cores = [Bool](repeating: false, count: mask.count)
        for y in radius..<(raster.height-radius) {
            if y % 32 == 0 { try Task.checkCancellation() }
            for x in radius..<(raster.width-radius) where mask[y*raster.width+x] {
                var solid = true
                for dy in [-radius,0,radius] {
                    for dx in [-radius,0,radius] where !mask[(y+dy)*raster.width+x+dx] { solid = false }
                }
                cores[y*raster.width+x] = solid
            }
        }
        let markers = try raster.components(mask: cores, separateColors: false).filter {
            $0.box.width > 0.003 && $0.box.height > 0.003 && $0.box.width < 0.06 && $0.box.height < 0.07
        }.sorted { $0.box.midX < $1.box.midX }
        guard (3...20).contains(markers.count) else { throw ExtractionIssue("At least three visible point markers are required; no points are inferred from the curve.") }
        let region = line.box
        let calibration = try AxisEvidence.calibration(text: ocr.observations, vertical: true, region: region)
        let labels = AxisEvidence.firstLabelRow(ocr.observations.filter {
            $0.box.y > region.maxY && $0.box.y < region.maxY+0.3
                && $0.box.midX >= region.x - 0.04 && $0.box.midX <= region.maxX + 0.04
        })
        // Every x category must have one marker; missing markers never become interpolated values.
        let associated = labels.filter { label in markers.contains { abs(label.box.midX-$0.box.midX) < 0.04 } }
        guard associated.count == markers.count, labels.count == markers.count else {
            throw ExtractionIssue("Category and marker counts disagree; missing markers or labels require review.")
        }
        // Detect a second stroke crossing the line by checking the vertical support at category x positions.
        var values: [ExtractedValue] = [], used = Set<Int>()
        for (i,marker) in markers.enumerated() {
            let matches = labels.filter { abs($0.box.midX-marker.box.midX) < 0.04 }
            guard matches.count == 1, let label = matches.first, used.insert(label.id).inserted else {
                throw ExtractionIssue("Point-to-category association is ambiguous.")
            }
            let x = Int(marker.box.midX * Double(raster.width))
            var runs = 0, wasSet = false
            for y in 0..<raster.height {
                let set = mask[y*raster.width+x]
                if set && !wasSet { runs += 1 }
                wasSet = set
            }
            guard runs == 1 else { throw ExtractionIssue("Multiple strokes intersect a data column; multi-series graphs are unsupported.") }
            let estimate = calibration.value(at: marker.box.midY)
            let printed = ocr.observations.filter { text in
                OCRNumber.parse(text.raw) != nil && !calibration.ticks.contains(where: { t in t.observation.id == text.id })
                && abs(text.box.midX-marker.box.midX) < 0.045 && abs(text.box.midY-marker.box.midY) < 0.08
            }
            let number = printed.count == 1 ? OCRNumber.parse(printed[0].raw)?.value : nil
            let uncertainty = abs(calibration.slope) * 3 / Double(raster.height) + calibration.residual
            let mismatch = number.map { abs($0-estimate) > max(uncertainty,calibration.span*0.02) } ?? false
            values.append(ExtractedValue(order: i, category: label.raw, value: estimate, printedValue: number,
                method: "Estimated from visible marker center", region: marker.box,
                observations: [label] + printed + calibration.ticks.map(\.observation),
                uncertainty: uncertainty, diagnostics: mismatch ? ["Printed point value conflicts with geometry."] : []))
        }
        return AxisEvidence.output(kind: .line, values: values, region: region, calibration: calibration,
            ocr: ocr, source: source, geometry: "Single connected stroke with \(markers.count) discrete markers. No interpolated points.")
    }
}
