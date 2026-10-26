import Foundation

enum AxisEvidence {
    static func firstLabelRow(_ labels: [OCRText]) -> [OCRText] {
        guard let first = labels.min(by: { $0.box.midY < $1.box.midY }) else { return [] }
        return labels.filter { abs($0.box.midY-first.box.midY) < 0.03 }
    }
    static func calibration(text: [OCRText], vertical: Bool, region: ImageBox) throws -> AxisCalibration {
        let numeric = text.compactMap { t -> AxisCalibration.Tick? in
            guard let number = OCRNumber.parse(t.raw), !number.isPercent, t.confidence >= 0.4 else { return nil }
            let nearAxis = vertical
                ? t.box.maxX < region.x + 0.015
                : t.box.y >= region.maxY - 0.015
            guard nearAxis else { return nil }
            return AxisCalibration.Tick(position: vertical ? t.box.midY : t.box.midX, value: number.value, observation: t)
        }
        // Separate axis ticks from titles/printed values by a common label alignment.
        var groups: [[AxisCalibration.Tick]] = []
        for tick in numeric {
            let alignment = vertical ? tick.observation.box.maxX : tick.observation.box.midY
            if let i = groups.firstIndex(where: {
                abs((vertical ? $0[0].observation.box.maxX : $0[0].observation.box.midY) - alignment) < 0.025
            }) { groups[i].append(tick) } else { groups.append([tick]) }
        }
        let candidates = groups.compactMap { try? AxisCalibration(ticks: $0) }
        guard candidates.count == 1, let calibration = candidates.first else {
            throw ExtractionIssue("Missing, conflicting, or nonlinear axis ticks.")
        }
        return calibration
    }

    static func output(kind: ChartKind, values: [ExtractedValue], region: ImageBox,
                       calibration: AxisCalibration?, ocr: OCRDocument, source: SourceProvenance,
                       geometry: String, warnings: [String] = []) -> ExtractionOutput {
        let title = ocr.observations.filter { $0.box.maxY < region.y - 0.02 && OCRNumber.parse($0.raw) == nil }
            .sorted { $0.box.y < $1.box.y }.first?.raw
        let xTitle = ocr.observations.filter { text in text.box.y > region.maxY + 0.08 && OCRNumber.parse(text.raw) == nil
            && !values.contains(where: { v in v.category == text.raw }) }.sorted { $0.box.y > $1.box.y }.first?.raw
        let issues = values.flatMap(\.diagnostics) + warnings
            + ((calibration?.ticks.count ?? 3) < 3 ? ["Only two ticks were recognized. Linearity is unconfirmed; the estimates require review."] : [])
        let leftTick = calibration?.ticks.map { $0.observation.box.x }.min()
        let yTitles = ocr.observations.filter { text in
            guard let leftTick else { return false }
            return text.box.maxX < leftTick - 0.02 && text.box.midY > region.y && text.box.midY < region.maxY
                && OCRNumber.parse(text.raw) == nil
        }
        return ExtractionOutput(sourceID: ocr.sourceID, source: source, kind: kind, title: title,
            xAxisTitle: xTitle, yAxisTitle: yTitles.count == 1 ? yTitles[0].raw : nil, unit: kind == .pie ? "%" : nil,
            values: values, calibration: calibration, geometryEvidence: geometry, ocr: ocr,
            diagnostics: ["All results are unverified. Geometry-derived values are estimates."] + issues)
    }
}

enum BarExtractor {
    static func extract(vertical: Bool, raster: Raster, components: [Raster.Component],
                        ocr: OCRDocument, source: SourceProvenance) throws -> ExtractionOutput {
        let bars = components.filter {
            $0.fill > 0.90 && $0.box.width > 0.015 && $0.box.height > 0.015
        }
        guard (2...20).contains(bars.count) else { throw ExtractionIssue("No reliable set of solid bars was found.") }
        let minimumArea = bars.map(\.area).min()!
        let extras = components.filter { component in
            !bars.contains(where: { $0.box == component.box }) && component.area > minimumArea / 12
            && component.fill > 0.15
            && component.box.width * Double(raster.width) > 3 && component.box.height * Double(raster.height) > 3
            && bars.contains(where: { bar in
                component.box.x < bar.box.maxX+0.03 && component.box.maxX > bar.box.x-0.03
                && component.box.y < bar.box.maxY+0.03 && component.box.maxY > bar.box.y-0.03
            })
        }
        guard extras.isEmpty else { throw ExtractionIssue("Additional adjacent shapes suggest stacked bars, shadows, or 3D decoration.") }
        let x0 = bars.map { $0.box.x }.min()!, y0 = bars.map { $0.box.y }.min()!
        let x1 = bars.map { $0.box.maxX }.max()!, y1 = bars.map { $0.box.maxY }.max()!
        let region = ImageBox(x: x0, y: y0, width: x1-x0, height: y1-y0)
        let calibration = try AxisEvidence.calibration(text: ocr.observations, vertical: vertical, region: region)
        let possibleLabels = ocr.observations.filter {
            OCRNumber.parse($0.raw) == nil && $0.confidence >= 0.4
            && (vertical ? $0.box.y > region.maxY && $0.box.y < region.maxY + 0.16
                : $0.box.maxX < region.x && $0.box.maxX > region.x - 0.35)
        }
        let labels = vertical ? AxisEvidence.firstLabelRow(possibleLabels) : possibleLabels
        guard labels.count == bars.count else {
            throw ExtractionIssue("Category and bar counts disagree; missing or fragmented bars cannot be inferred.")
        }
        let sorted = bars.sorted { vertical ? $0.box.midX < $1.box.midX : $0.box.midY < $1.box.midY }
        var used = Set<Int>(), values: [ExtractedValue] = []
        // A shared physical baseline must be an endpoint of every bar. Zero is not assumed.
        let endpoints = sorted.flatMap { vertical ? [$0.box.y,$0.box.maxY] : [$0.box.x,$0.box.maxX] }
        let baselines = endpoints.filter { candidate in sorted.allSatisfy { bar in
            let ends = vertical ? [bar.box.y,bar.box.maxY] : [bar.box.x,bar.box.maxX]
            return ends.contains { abs($0-candidate) < 0.008 }
        }}
        guard let baseline = baselines.first else { throw ExtractionIssue("Bars do not share a baseline; stacked, grouped, or 3D layout may be present.") }
        // Multiple distinct common endpoints means equal-length ambiguity, not an inferred baseline.
        guard baselines.allSatisfy({ abs($0-baseline) < 0.008 }) else {
            throw ExtractionIssue("Two baselines are plausible.")
        }
        for (i,bar) in sorted.enumerated() {
            let center = vertical ? bar.box.midX : bar.box.midY
            let matches = labels.filter { abs((vertical ? $0.box.midX : $0.box.midY) - center) < (vertical ? max(bar.box.width / 2,0.04) : max(bar.box.height / 2,0.025)) }
            guard matches.count == 1, let label = matches.first, used.insert(label.id).inserted else {
                throw ExtractionIssue("Category association is missing or ambiguous; grouped/stacked bars are unsupported.")
            }
            let ends = vertical ? [bar.box.y,bar.box.maxY] : [bar.box.x,bar.box.maxX]
            let end = abs(ends[0]-baseline) > abs(ends[1]-baseline) ? ends[0] : ends[1]
            let estimate = calibration.value(at: end)
            let axisMin = calibration.ticks.map(\.value).min()!, axisMax = calibration.ticks.map(\.value).max()!
            let extensionLimit = calibration.ticks.count == 2 ? calibration.span : calibration.span * 0.02
            guard estimate >= axisMin-extensionLimit, estimate <= axisMax+extensionLimit else {
                throw ExtractionIssue("Bar endpoint lies outside the calibrated axis.")
            }
            let outsideRecognizedTicks = estimate < axisMin-calibration.span*0.02 || estimate > axisMax+calibration.span*0.02
            let printed = ocr.observations.filter { t in
                OCRNumber.parse(t.raw) != nil && !calibration.ticks.contains { $0.observation.id == t.id }
                && (vertical ? abs(t.box.midX-bar.box.midX) < max(bar.box.width/2,0.04)
                    && abs(t.box.midY-end) < 0.065 : abs(t.box.midY-bar.box.midY) < max(bar.box.height/2,0.025)
                    && abs(t.box.midX-end) < 0.09)
            }
            let printedValue = printed.count == 1 ? OCRNumber.parse(printed[0].raw)?.value : nil
            let uncertainty = abs(calibration.slope) * 2 / Double(vertical ? raster.height : raster.width) + calibration.residual
            let disagreement = printedValue.map { abs($0-estimate) > max(uncertainty,calibration.span*0.02) } ?? false
            values.append(ExtractedValue(order: i, category: label.raw, value: estimate, printedValue: printedValue,
                method: "Estimated from calibrated bar endpoint", region: bar.box,
                observations: [label] + printed + calibration.ticks.map(\.observation),
                uncertainty: uncertainty,
                diagnostics: (disagreement ? ["Printed value disagrees with bar geometry for \(label.raw)."] : [])
                    + (outsideRecognizedTicks ? ["Endpoint lies beyond the recognized tick span; linear scale extension is unconfirmed."] : [])))
        }
        return AxisEvidence.output(kind: vertical ? .verticalBar : .horizontalBar, values: values, region: region,
            calibration: calibration, ocr: ocr, source: source,
            geometry: "Solid rectangles; common baseline at \(baseline); value = \(calibration.slope) × coordinate + \(calibration.intercept).")
    }
}
