import Foundation
import CoreGraphics
import CoreText
import Observation

enum ChartReportError: String, Error, LocalizedError, Sendable {
    case stale = "Verification changed. Prepare a new report from a complete trusted chart."
    case tooLarge = "The report exceeds the safe export size limit."
    case rendering = "The PDF could not be prepared. Use the plain-text alternative."
    var errorDescription: String? { rawValue }
}
struct ChartReportPayload: Sendable {
    fileprivate let snapshot: BarChart.TrustedSnapshot
    var key: InsightKey { InsightKey(snapshot) }
    let text: String
    let pdf: Data
    let exportedAt: Date
    fileprivate init(snapshot: BarChart.TrustedSnapshot, text: String, pdf: Data, exportedAt: Date) {
        self.snapshot = snapshot; self.text = text; self.pdf = pdf; self.exportedAt = exportedAt
    }
}
@MainActor @Observable
final class ReportAuthorization {
    private var snapshot: BarChart.TrustedSnapshot?
    func synchronize(with snapshot: BarChart.TrustedSnapshot?) {
        self.snapshot = snapshot
    }
    func validate(_ snapshot: BarChart.TrustedSnapshot) throws {
        guard isCurrent(snapshot) else { throw ChartReportError.stale }
    }
    func isCurrent(_ snapshot: BarChart.TrustedSnapshot) -> Bool { self.snapshot == snapshot }
    func data(for payload: ChartReportPayload, pdf: Bool) throws -> Data {
        guard snapshot == payload.snapshot else { throw ChartReportError.stale }
        if pdf && payload.pdf.isEmpty { throw ChartReportError.rendering }
        return pdf ? payload.pdf : Data(payload.text.utf8)
    }
}

/// PDF and text are derived together from the same immutable trusted snapshot.
/// No original file, pixels, OCR strings or source paths are included.
actor ChartReportBuilder {
    private var cache = VerifiedInsightsCache()
    func prepare(_ snapshot: BarChart.TrustedSnapshot, explanation: ChartExplanation? = nil, exportedAt: Date = Date(), includePDF: Bool = true) throws -> ChartReportPayload {
        try Task.checkCancellation()
        if let explanation, !explanation.isCurrent(for: snapshot) { throw ChartReportError.stale }
        let insights = cache.calculate(snapshot)
        let facts = ExplanationPayload.prepare(insights)
        let explanationText = explanation.map { $0.attribution + "\n" + $0.text } ??
            ("Deterministic explanation — no generative AI used.\n" + facts.render(facts.facts))
        let formatter = ISO8601DateFormatter()
        let sections: [(String, [String])] = [
            (snapshot.title, [snapshot.kind.rawValue, "Units: " + insights.unit.label, "Report created/exported: " + formatter.string(from: exportedAt)]),
            ("Verified data", snapshot.values.map { "Item \($0.order + 1): \($0.label): \(ChartNumberFormat.readable($0.value)) \(insights.unit.label). Confirmed by you." } + [ChartNumberFormat.note]),
            ("Deterministic findings", insights.results.filter { $0.operation != .ascending && $0.operation != .descending }.map(\.summary) + [insights.scope]),
            ("Explanation", [explanationText]),
            ("Source and verification", ["These values were explicitly confirmed by the user before this report was prepared. Confirmation accepts the entered values; it does not establish the physical accuracy of an extracted estimate. Original images, PDFs, paths and OCR evidence are not included."])
        ]
        let text = sections.map { $0.0 + "\n" + $0.1.joined(separator: "\n") }.joined(separator: "\n\n") + "\n"
        guard text.utf8.count <= 2 * 1_024 * 1_024 else { throw ChartReportError.tooLarge }
        try Task.checkCancellation()
        if !includePDF { return .init(snapshot: snapshot, text: text, pdf: Data(), exportedAt: exportedAt) }
        let attributed = NSMutableAttributedString(string: "")
        let body = CTFontCreateWithName("Helvetica" as CFString, 14, nil)
        for (index, section) in sections.enumerated() {
            let heading = CTFontCreateWithName("Helvetica-Bold" as CFString, index == 0 ? 22 : 17, nil)
            attributed.append(NSAttributedString(string: section.0 + "\n\n", attributes: [.init(kCTFontAttributeName as String): heading]))
            attributed.append(NSAttributedString(string: section.1.joined(separator: "\n\n") + "\n\n", attributes: [.init(kCTFontAttributeName as String): body]))
        }
        let buffer = NSMutableData()
        guard let consumer = CGDataConsumer(data: buffer as CFMutableData) else { throw ChartReportError.rendering }
        var page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let info = [kCGPDFContextTitle: snapshot.title, kCGPDFContextCreator: "ChartBridge"] as CFDictionary
        guard let context = CGContext(consumer: consumer, mediaBox: &page, info) else { throw ChartReportError.rendering }
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        let path = CGPath(rect: CGRect(x: 44, y: 44, width: 524, height: 704), transform: nil)
        var offset = 0, pages = 0
        while offset < attributed.length {
            try Task.checkCancellation()
            guard pages < 100 else { throw ChartReportError.tooLarge }
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { throw ChartReportError.rendering }
            context.beginPDFPage(nil)
            // CoreGraphics SDK tag APIs supply logical selectable page text.
            // This is not a claim of audited PDF/UA conformance.
            let pageText = attributed.attributedSubstring(from: NSRange(location: visible.location, length: visible.length)).string
            CGPDFContextBeginTag(context, .paragraph, [CGPDFTagProperty.actualText.rawValue: pageText, CGPDFTagProperty.languageText.rawValue: "en"] as CFDictionary)
            CTFrameDraw(frame, context)
            CGPDFContextEndTag(context)
            context.endPDFPage()
            offset += visible.length; pages += 1
        }
        context.closePDF()
        guard buffer.length > 0, buffer.length <= 20 * 1_024 * 1_024 else { throw ChartReportError.tooLarge }
        return .init(snapshot: snapshot, text: text, pdf: buffer as Data, exportedAt: exportedAt)
    }
}
