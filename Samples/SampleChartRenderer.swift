import Foundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

/// Offline sample pixels only. The real importer/Vision/geometry pipeline sees
/// no expected values or fabricated OCR observations.
actor SampleChartRenderer {
    func render(_ sample: ChartSample) throws -> Data {
        try Task.checkCancellation()
        guard let cg = CGContext(data: nil, width: 1000, height: 800, bitsPerComponent: 8,
            bytesPerRow: 4000, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw ImportFailure.malformed }
        cg.setFillColor(CGColor(gray: 1, alpha: 1)); cg.fill(CGRect(x: 0, y: 0, width: 1000, height: 800))
        cg.translateBy(x: 0, y: 800); cg.scaleBy(x: 1, y: -1)
        func label(_ text: String, _ x: Double, _ y: Double, size: Double = 26, right: Bool = false) {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: [
                .init(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, size, nil),
                .init(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
            ]))
            let width = CTLineGetTypographicBounds(line, nil, nil, nil)
            cg.saveGState(); cg.translateBy(x: x, y: y); cg.scaleBy(x: 1, y: -1)
            cg.textMatrix = .identity; cg.textPosition = CGPoint(x: right ? -width : -width / 2, y: -size * 0.35)
            CTLineDraw(line, cg); cg.restoreGState()
        }
        let colors = [(0.05, 0.35, 0.75), (0.85, 0.35, 0.05), (0.05, 0.55, 0.25), (0.55, 0.2, 0.7)]
        func fill(_ index: Int) {
            let c = colors[index]; cg.setFillColor(CGColor(red: c.0, green: c.1, blue: c.2, alpha: 1))
        }
        label(sample.title, 500, 65, size: 36)
        if sample == .pie {
            var start = 0.0
            for i in sample.labels.indices {
                let end = start + Double(sample.referenceValues[i]) / 100 * 2 * .pi
                fill(i); cg.move(to: CGPoint(x: 500, y: 420))
                cg.addArc(center: CGPoint(x: 500, y: 420), radius: 190, startAngle: start, endAngle: end, clockwise: false)
                cg.closePath(); cg.fillPath()
                let mid = (start + end) / 2
                label(sample.labels[i], 500 + cos(mid) * 280, 420 + sin(mid) * 280)
                start = end
            }
        } else {
            let horizontal = sample == .horizontal
            for (i, tick) in [0, 50, 100].enumerated() {
                label(String(tick), horizontal ? 220 + Double(i) * 340 : 190,
                      horizontal ? 660 : 620 - Double(i) * 220, right: !horizontal)
            }
            cg.setStrokeColor(CGColor(gray: 0, alpha: 1)); cg.setLineWidth(2)
            cg.move(to: CGPoint(x: 220, y: 180)); cg.addLine(to: CGPoint(x: 220, y: 620))
            cg.addLine(to: CGPoint(x: 900, y: 620)); cg.strokePath()
            if sample == .line {
                let points = sample.referenceValues.enumerated().map {
                    CGPoint(x: 280 + Double($0.offset) * 180, y: 620 - Double($0.element) * 4.4)
                }
                cg.setStrokeColor(CGColor(red: 0.05, green: 0.35, blue: 0.75, alpha: 1)); cg.setLineWidth(5)
                cg.addLines(between: points); cg.strokePath()
                for (i, p) in points.enumerated() {
                    fill(0); cg.fillEllipse(in: CGRect(x: p.x - 12, y: p.y - 12, width: 24, height: 24))
                    label(sample.labels[i], p.x, 660)
                }
            } else {
                for i in sample.labels.indices {
                    fill(i)
                    if horizontal {
                        let y = 230 + Double(i) * 145
                        cg.fill(CGRect(x: 220, y: y, width: Double(sample.referenceValues[i]) * 6.8, height: 70))
                        label(sample.labels[i], 190, y + 35, right: true)
                    } else {
                        let x = 300 + Double(i) * 230
                        let height = Double(sample.referenceValues[i]) * 4.4
                        cg.fill(CGRect(x: x - 42, y: 620 - height, width: 84, height: height))
                        label(sample.labels[i], x, 660)
                    }
                }
            }
            label(horizontal ? "Hours" : "Category", 550, 735)
        }
        try Task.checkCancellation()
        guard let image = cg.makeImage() else { throw ImportFailure.malformed }
        let bytes = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(bytes, UTType.png.identifier as CFString, 1, nil)
        else { throw ImportFailure.malformed }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw ImportFailure.malformed }
        return bytes as Data
    }
}
