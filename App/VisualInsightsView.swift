import SwiftUI
import Charts

private enum InsightDestination: String, CaseIterable, Identifiable {
    case extremes = "Highest & Lowest", compare = "Compare Two Points", ranking = "Ranking", trend = "Observed Trend"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .extremes: "arrow.up.arrow.down"; case .compare: "chart.bar.xaxis"; case .ranking: "list.number"; case .trend: "chart.xyaxis.line" }
    }
}

struct VisualInsightsOverview: View {
    let data: VisualInsightData
    let authorization: ReportAuthorization
    private var destinations: [InsightDestination] {
        data.snapshot.kind == .line ? [.trend, .extremes, .compare] : [.extremes, .compare, .ranking]
    }
    var body: some View {
        InformationCard {
            ChartSectionHeading(title: "Insights", subtitle: "Explore the values you confirmed.")
            if authorization.isCurrent(data.snapshot) {
                VerifiedDatasetChart(data: data, points: data.points)
                ForEach(destinations) { destination in
                    NavigationLink {
                        VisualInsightDetail(data: data, authorization: authorization, destination: destination)
                    } label: {
                        ChartActionRow(title: destination.rawValue, subtitle: summary(destination), symbol: destination.symbol)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens an interactive chart and verified findings.")
                    Divider().accessibilityHidden(true)
                }
                DisclosureGroup("More calculated findings") {
                    ForEach(data.insights.results.filter { [.count, .total, .mean, .pieTotal, .pieConsistency, .physicalTotal].contains($0.operation) }) { result in
                        ChartCalculationView(result: result).accessibilityIdentifier("insight-" + result.operation.rawValue)
                    }
                }
                DisclosureGroup("About these insights") {
                    Text(ChartNumberFormat.note)
                    Text(data.insights.scope)
                    if data.insights.unit == .unspecified { Text("No units were recognized. Do not assume the values count people, money or time.") }
                    Text("Plot positions use drawing precision; comparisons and ties use full-precision verified decimals. Bars start at zero. Line labels follow source order, not measured x-spacing.")
                }.font(.subheadline)
            } else { staleNotice }
        }
    }
    private func summary(_ destination: InsightDestination) -> String {
        switch destination {
        case .extremes:
            let highest = data.extrema(.largest), lowest = data.extrema(.smallest)
            return "Highest: \(highest.first.map { ChartNumberFormat.readable($0.value) } ?? "Unavailable"). Lowest: \(lowest.first.map { ChartNumberFormat.readable($0.value) } ?? "Unavailable"). All ties included."
        case .compare: return "Choose two values to see their difference and comparison baseline."
        case .ranking: return "All \(data.points.count) categories, highest first. Equal values share a rank."
        case .trend: return "Start, end and changes across the observed points, in source order."
        }
    }
}

private var staleNotice: some View {
    ContentUnavailableView("Verification Changed", systemImage: "checkmark.shield", description: Text("Return to the chart and verify the current values before viewing insights."))
}

private struct VisualInsightDetail: View {
    let data: VisualInsightData
    let authorization: ReportAuthorization
    let destination: InsightDestination
    @State private var selection = VisualComparisonSelection()
    @State private var comparison: VisualComparison?
    @State private var worker = ChartInsightsWorker()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ChartBridgeDesign.Spacing.section) {
                if authorization.isCurrent(data.snapshot) {
                    Text(data.insights.title).font(.headline).accessibilityAddTraits(.isHeader)
                    ChartStatus(title: "Verified values", symbol: "checkmark.seal")
                    switch destination {
                    case .extremes: extremes
                    case .compare: compare
                    case .ranking: ranking
                    case .trend: trend
                    }
                    DisclosureGroup("Accuracy and scope") {
                        Text(ChartNumberFormat.note)
                        Text(data.insights.scope)
                    }.font(.subheadline)
                } else { staleNotice }
            }
            .padding(ChartBridgeDesign.Spacing.page)
            .frame(maxWidth: 600).frame(maxWidth: .infinity)
        }
        .background(ChartBridgeDesign.Colors.canvas)
        .navigationTitle(destination.rawValue).navigationBarTitleDisplayMode(.inline)
        .task(id: selection) {
            guard destination == .compare, authorization.isCurrent(data.snapshot) else { return }
            comparison = nil
            let result = await worker.visualComparison(data, selection: selection)
            guard !Task.isCancelled, authorization.isCurrent(data.snapshot) else { return }
            comparison = result
        }
        .onAppear {
            if data.points.count == 1 { selection.second = selection.first }
        }
    }

    private var extremes: some View {
        VStack(alignment: .leading, spacing: 20) {
            VerifiedDatasetChart(data: data, points: data.points, highlightExtremes: true)
            extremaCard("Highest", operation: .largest)
            extremaCard("Lowest", operation: .smallest)
            if data.points.count == 1 { Text("This is the only value, so it is both highest and lowest.") }
            Text("Highest and lowest are determined before display rounding.").font(.subheadline).foregroundStyle(.secondary)
        }
    }
    private func extremaCard(_ title: String, operation: CalculationOperation) -> some View {
        let points = data.extrema(operation)
        return InformationCard {
            Text(title).font(.headline).accessibilityAddTraits(.isHeader)
            if points.isEmpty { Text("No verified values available.") }
            if points.count > 1 { Text("\(points.count) values tied") }
            ForEach(points) { point in pointRow(point) }
        }
    }
    private var compare: some View {
        VStack(alignment: .leading, spacing: 20) {
            InformationCard {
                pointPicker("First value (baseline)", selection: $selection.first)
                pointPicker("Second value", selection: $selection.second)
            }
            let selected = data.points.filter { $0.id.order == selection.first || $0.id.order == selection.second }
            VerifiedDatasetChart(data: data, points: selected, horizontal: true)
            if let comparison, comparison.selection == selection {
                InformationCard {
                    Text(comparison.relationship).font(.headline)
                    Text("Baseline: the first selected value, \(data.points.first { $0.id.order == selection.first }?.label ?? "unavailable").")
                    ForEach(comparison.results) { result in finding(result) }
                }
            } else { ProgressView("Comparing verified values…") }
        }
    }
    private func pointPicker(_ title: String, selection: Binding<Int>) -> some View {
        Picker(title, selection: selection) {
            ForEach(data.points) { Text($0.label).tag($0.id.order) }
        }.pickerStyle(.menu).frame(minHeight: 44)
    }
    private var ranking: some View {
        VStack(alignment: .leading, spacing: 20) {
            VerifiedDatasetChart(data: data, points: data.ranking.map(\.point), horizontal: true)
            Text("Highest first. Equal full-precision values share a rank; the next rank skips tied places.")
            InformationCard {
                ForEach(data.ranking) { entry in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Rank \(entry.rank)" + (entry.tied ? " · Tied" : "")).font(.headline)
                        pointRow(entry.point)
                    }.accessibilityElement(children: .combine)
                    Divider().accessibilityHidden(true)
                }
            }
        }
    }
    private var trend: some View {
        VStack(alignment: .leading, spacing: 20) {
            VerifiedDatasetChart(data: data, points: data.points)
            InformationCard {
                ForEach([CalculationOperation.first, .last, .netChange, .relativeChange, .trend], id: \.rawValue) { operation in
                    if let result = data.insights.result(operation) { finding(result) }
                }
                Text("Observed points only. Lines connect observations without establishing what happened between them. X positions are categorical source order, not elapsed time.")
            }
        }
    }
    private func pointRow(_ point: CalculationPoint) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(point.label).font(.headline)
            Text(ChartNumberFormat.readable(point.value) + data.insights.unit.displaySuffix)
        }.fixedSize(horizontal: false, vertical: true).accessibilityElement(children: .combine)
    }
    private func finding(_ result: ChartCalculation) -> some View {
        ChartCalculationView(result: result)
    }
}

private struct ChartCalculationView: View {
    let result: ChartCalculation
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.label.replacingOccurrences(of: "Arithmetic mean", with: "Average")).font(.subheadline).foregroundStyle(.secondary)
            switch result.availability {
            case .available(.number(let value)):
                Text(value.text + result.unit.displaySuffix).font(.headline).monospacedDigit()
            case .available(.trend(let trend)):
                Text(trend.rawValue).font(.headline)
            case .unavailable(let reason):
                Text(reason.rawValue).font(.subheadline)
            default: Text(result.summary).font(.subheadline)
            }
            DisclosureGroup("Calculation details") { Text(result.explanation) }.font(.subheadline)
        }.fixedSize(horizontal: false, vertical: true).padding(.vertical, 6)
    }
}

private extension CalculationUnit {
    var displaySuffix: String {
        switch self { case .unspecified, .none: ""; default: " " + label }
    }
}

/// Native chart selection is paired with an explicit picker and text alternative.
/// At most 30 marks are drawn; every verified value remains selectable/readable.
private struct VerifiedDatasetChart: View {
    let data: VisualInsightData
    let points: [CalculationPoint]
    var horizontal = false
    var highlightExtremes = false
    @State private var selectedLabel: String?
    @State private var selectedAngle: Double?
    @ScaledMetric(relativeTo: .body) private var chartHeight = 240.0
    private var plotted: [CalculationPoint] { Array(points.prefix(30)) }
    private var domain: ClosedRange<Double> { VisualInsightData.axisDomain(points) }
    private var isHorizontal: Bool { horizontal || data.snapshot.kind == .horizontalBar || (data.snapshot.kind == .pie && !isPie) }
    private var isPie: Bool {
        !horizontal && data.snapshot.kind == .pie && points.count <= 30 &&
            data.insights.result(.pieTotal)?.number?.exactValue == 100 && points.count == data.points.count
    }
    private var selected: CalculationPoint? { points.first { $0.label == selectedLabel } ?? points.first }
    private func drawingValue(_ point: CalculationPoint) -> Double { NSDecimalNumber(decimal: point.value).doubleValue }
    private func isExtreme(_ point: CalculationPoint) -> Bool {
        data.extrema(.largest).contains { $0.id == point.id } || data.extrema(.smallest).contains { $0.id == point.id }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if points.isEmpty { Text("No verified values available.") }
            else {
                drawing.frame(height: min(chartHeight, 480))
                    .accessibilityLabel(data.insights.title + ", verified chart")
                    .accessibilityHint("Select a value using the picker below for its label and value. A complete text alternative follows.")
                if points.count > plotted.count {
                    Text("The plot shows the first \(plotted.count) of \(points.count) values in this view's order. Every value is available below.").font(.subheadline)
                }
                if data.snapshot.kind == .pie {
                    Text(isPie ? "Verified shares of the whole. No physical total is inferred." : "Shares shown as bars against zero, without normalizing the verified percentages.").font(.subheadline)
                }
                Picker("Selected value", selection: $selectedLabel) {
                    ForEach(points) { Text($0.label).tag(Optional($0.label)) }
                }.pickerStyle(.menu).frame(minHeight: 44)
                if let selected {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selected.label).font(.headline)
                        Text(ChartNumberFormat.readable(selected.value) + data.insights.unit.displaySuffix)
                        if highlightExtremes {
                            if data.extrema(.largest).contains(where: { $0.id == selected.id }) { Text("Highest value") }
                            if data.extrema(.smallest).contains(where: { $0.id == selected.id }) { Text("Lowest value") }
                        }
                    }.accessibilityElement(children: .combine)
                }
                DisclosureGroup("All verified values (text alternative)") {
                    ForEach(points) { point in
                        Text(point.label + ": " + ChartNumberFormat.readable(point.value) + data.insights.unit.displaySuffix)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.font(.subheadline)
            }
        }
        .onAppear { selectedLabel = points.first?.label }
        .onChange(of: points) { _, value in selectedLabel = value.first?.label; selectedAngle = nil }
        .onChange(of: selectedAngle) { _, angle in
            guard let angle, let order = data.pieSelection(angle) else { return }
            selectedLabel = points.first { $0.id.order == order }?.label
        }
    }

    @ViewBuilder private var drawing: some View {
        if isPie {
            Chart(plotted) { point in
                SectorMark(angle: .value("Share", drawingValue(point)), innerRadius: .ratio(0.45), angularInset: 1)
                    .foregroundStyle(by: .value("Category", point.label))
                    .opacity(highlightExtremes ? (isExtreme(point) ? 1 : 0.45) : (selectedLabel == nil || selectedLabel == point.label ? 1 : 0.6))
                    .accessibilityLabel(point.label)
                    .accessibilityValue(ChartNumberFormat.readable(point.value) + " percent")
            }
            .chartAngleSelection(value: $selectedAngle).chartLegend(.hidden)
        } else if isHorizontal {
            Chart(plotted) { point in
                BarMark(x: .value("Value", drawingValue(point)), y: .value("Category", point.label))
                    .foregroundStyle(ChartBridgeDesign.Colors.accent)
                    .opacity(highlightExtremes ? (isExtreme(point) ? 1 : 0.45) : (selectedLabel == nil || selectedLabel == point.label ? 1 : 0.6))
                    .accessibilityLabel(point.label)
                    .accessibilityValue(ChartNumberFormat.readable(point.value) + data.insights.unit.displaySuffix)
            }
            .chartXScale(domain: domain).chartYScale(domain: plotted.map(\.label))
            .chartYSelection(value: $selectedLabel)
            .chartXAxis { AxisMarks { value in AxisGridLine(); AxisValueLabel { if let v = value.as(Double.self) { Text(ChartNumberFormat.number(v)) } } } }
        } else {
            Chart(plotted) { point in
                if data.snapshot.kind == .line {
                    LineMark(x: .value("Observation", point.label), y: .value("Value", drawingValue(point)))
                        .foregroundStyle(ChartBridgeDesign.Colors.accent)
                        .interpolationMethod(.linear)
                    PointMark(x: .value("Observation", point.label), y: .value("Value", drawingValue(point)))
                        .symbolSize((highlightExtremes && isExtreme(point)) || selectedLabel == point.label ? 90 : 40)
                        .foregroundStyle(ChartBridgeDesign.Colors.accent)
                        .accessibilityLabel(point.label)
                        .accessibilityValue(ChartNumberFormat.readable(point.value) + data.insights.unit.displaySuffix)
                } else {
                    BarMark(x: .value("Category", point.label), y: .value("Value", drawingValue(point)))
                        .foregroundStyle(ChartBridgeDesign.Colors.accent)
                        .opacity(highlightExtremes ? (isExtreme(point) ? 1 : 0.45) : (selectedLabel == nil || selectedLabel == point.label ? 1 : 0.6))
                        .accessibilityLabel(point.label)
                        .accessibilityValue(ChartNumberFormat.readable(point.value) + data.insights.unit.displaySuffix)
                }
            }
            .chartYScale(domain: domain).chartXScale(domain: plotted.map(\.label))
            .chartXSelection(value: $selectedLabel)
            .chartYAxis { AxisMarks { value in AxisGridLine(); AxisValueLabel { if let v = value.as(Double.self) { Text(ChartNumberFormat.number(v)) } } } }
        }
    }
}
