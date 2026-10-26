import Foundation

enum PieExtractor {
    static func extract(raster: Raster, mask: [Bool], ocr: OCRDocument,
                        source: SourceProvenance) throws -> ExtractionOutput {
        let shapes = try raster.components(mask: mask, separateColors: false)
        guard let circle = shapes.filter({ $0.box.width > 0.2 && $0.box.height > 0.2
            && abs($0.box.width * Double(raster.width) / ($0.box.height * Double(raster.height)) - 1) < 0.06
            && $0.fill > 0.70 && $0.fill < 0.86 }).max(by: { $0.area < $1.area }) else {
            throw ExtractionIssue("No complete circular pie region was found; donut, exploded, and 3D pies are unsupported.")
        }
        let box = circle.box, cx = box.midX, cy = box.midY
        let rx = box.width / 2, ry = box.height / 2
        // Verify filled center and full circular coverage at multiple radii.
        for fraction in [0.1,0.35,0.7,0.9] {
            var gaps = 0
            for degree in stride(from: 0, to: 360, by: 3) {
                let angle = Double(degree) * .pi / 180
                let x = Int((cx+cos(angle)*rx*fraction)*Double(raster.width))
                let y = Int((cy+sin(angle)*ry*fraction)*Double(raster.height))
                if x < 0 || y < 0 || x >= raster.width || y >= raster.height || !mask[y*raster.width+x] { gaps += 1 }
            }
            guard gaps <= 3 else { throw ExtractionIssue("Pie has an incomplete or hollow region; no complete percentages can be measured.") }
        }
        let samples = 720
        var colors: [Raster.Color] = []
        for i in 0..<samples {
            let angle = Double(i) * 2 * .pi / Double(samples)
            colors.append(raster.color(normalX: cx+cos(angle)*rx*0.85, normalY: cy+sin(angle)*ry*0.85))
        }
        // Group contiguous colors, not a fixed palette. Similar slices below this separation
        // threshold are intentionally ambiguous rather than silently merged into a known label.
        var boundaries = (0..<samples).filter { colors[$0].distance(colors[($0+samples-1)%samples]) > 0.09 }
        boundaries = boundaries.filter { index in
            !boundaries.contains { other in other != index && (index-other+samples)%samples < 3 }
        }
        guard (2...12).contains(boundaries.count) else { throw ExtractionIssue("Slice boundaries are missing or ambiguous.") }
        let labels = ocr.observations.filter {
            OCRNumber.parse($0.raw) == nil && $0.confidence >= 0.4
            && hypot(($0.box.midX-cx)/rx,($0.box.midY-cy)/ry) > 1.02
            && hypot(($0.box.midX-cx)/rx,($0.box.midY-cy)/ry) < 1.8
        }
        guard labels.count == boundaries.count else { throw ExtractionIssue("Every pie slice needs one reliable nearby category label; no category names are invented.") }
        var used = Set<Int>(), values: [ExtractedValue] = []
        for i in boundaries.indices {
            let start = boundaries[i], count = (boundaries[(i+1)%boundaries.count]-start+samples)%samples
            guard count >= 6 else { throw ExtractionIssue("A slice is too small to measure reliably.") }
            let middle = Double(start)+Double(count)/2
            let angle = middle*2 * .pi/Double(samples)
            // Boundary consistency at another radius rejects overlapping/non-radial regions.
            let expectedColor = colors[Int(middle)%samples]
            for fraction in [0.3,0.5,0.85] {
                let px = cx+cos(angle)*rx*fraction, py = cy+sin(angle)*ry*fraction
                if ocr.observations.contains(where: { $0.box.contains(px,py,padding:0.005) }) { continue }
                let color = raster.color(normalX: px, normalY: py)
                guard color.distance(expectedColor) < 0.12 else { throw ExtractionIssue("Slice color is not radial; overlap or decoration is ambiguous.") }
            }
            func within(_ t: OCRText) -> Bool {
                var a = atan2((t.box.midY-cy)/ry,(t.box.midX-cx)/rx)
                if a < 0 { a += 2 * .pi }
                let relative = (a*Double(samples)/(2 * .pi)-Double(start)+Double(samples)).truncatingRemainder(dividingBy: Double(samples))
                return relative > 2 && relative < Double(count)-2
            }
            let matches = labels.filter(within)
            guard matches.count == 1, let label = matches.first, used.insert(label.id).inserted else {
                throw ExtractionIssue("Slice label association is ambiguous.")
            }
            let printed = ocr.observations.filter {
                OCRNumber.parse($0.raw)?.isPercent == true && within($0)
            }
            let percent = Double(count)*100/Double(samples)
            let number = printed.count == 1 ? OCRNumber.parse(printed[0].raw)?.value : nil
            let mismatch = number.map { abs($0-percent) > 2 } ?? false
            values.append(ExtractedValue(order: i, category: label.raw, value: percent, printedValue: number,
                method: "Estimated from raster slice angle", region: box, observations: [label]+printed,
                uncertainty: 1, diagnostics: mismatch ? ["Printed percentage conflicts with measured angle."] : []))
        }
        let printed = values.compactMap(\.printedValue)
        let warnings = printed.count == values.count && abs(printed.reduce(0,+)-100) > 2
            ? ["Printed percentages do not sum to 100."] : []
        return AxisEvidence.output(kind: .pie, values: values, region: box, calibration: nil, ocr: ocr,
            source: source, geometry: "Center (\(cx), \(cy)); normalized radii (\(rx), \(ry)); 720 radial samples; percentages are estimated, not exact.", warnings: warnings)
    }
}
