#if DEBUG
import UIKit
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ExtractionFixture: Sendable {
    let name: String
    let kind: ChartKind
    let values: [Double]
    let categories: [String]
    let data: Data
    let idealOCR: OCRDocument
    let shouldReject: Bool
}

@MainActor
enum ExtractionFixtures {
    static func make(kind: ChartKind, variant: String = "basic") -> ExtractionFixture {
        let names = kind == .line ? ["Alpha","Beta","Gamma","Delta"] : ["Alpha","Beta","Gamma"]
        var values: [Double] = kind == .line ? [20,60,40,80] : kind == .pie ? [20,30,50] : [20,60,80]
        var categories = names
        if variant == "negative" { values = [-20,40,80] }
        if variant == "decimal" { values = kind == .line ? [22.5,65.5,42.5,82.5] : [22.5,65.5,82.5] }
        if variant == "nonzero" { values = [45,65,85] }
        if variant == "decreasing" { values = [80,60,40,20] }
        if variant == "four" { values = [10,20,30,40]; categories = ["Alpha","Beta","Gamma","Delta"] }
        if variant == "longLabels" { categories = ["North region","South region","West region"] }
        let unsupported = ["missingTicks","missingMarker","intersecting","missingLabels","donut","exploded","3D","grouped","stacked","log","similar","rotated","lowResolution","ocrError"].contains(variant)
        let format = UIGraphicsImageRendererFormat(); format.scale = 1
        var text: [OCRText] = []
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 800), format: format).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0,y: 0,width: 1000,height: 800))
            func label(_ string: String, _ x: Double, _ y: Double, size: Double = 26, centered: Bool = true) {
                let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.systemFont(ofSize: size), .foregroundColor: UIColor.black]
                let measured = (string as NSString).size(withAttributes: attributes)
                let origin = CGPoint(x: centered ? x-measured.width/2 : x-measured.width, y: y-measured.height/2)
                (string as NSString).draw(at: origin, withAttributes: attributes)
                text.append(OCRText(id: text.count, raw: string, alternatives: [], confidence: 1,
                    box: ImageBox(x: origin.x/1000,y: origin.y/800,width: measured.width/1000,height: measured.height/800), sourceID: "synthetic"))
            }
            label("Regional Results",500,65,size:36)
            let colors: [UIColor] = variant == "colors"
                ? [.systemRed,.systemGreen,.systemPurple,.systemOrange] : [.systemBlue,.systemOrange,.systemGreen,.systemPurple]
            let cg = context.cgContext
            if kind == .pie {
                let cx = 500.0, cy = 420.0, radius = 190.0
                cg.saveGState()
                if variant == "3D" {
                    cg.translateBy(x: 0, y: cy * 0.3)
                    cg.scaleBy(x: 1, y: 0.7)
                    cg.setShadow(offset: CGSize(width: 0, height: 22), blur: 0, color: UIColor.gray.cgColor)
                }
                var start = 0.0
                for i in values.indices {
                    let end = start+values[i]/100*2 * .pi
                    let color: UIColor = variant == "similar" ? UIColor(red: 0.1,green: 0.45+Double(i)*0.01,blue: 0.75,alpha:1) : colors[i]
                    color.setFill()
                    cg.move(to: CGPoint(x:cx,y:cy))
                    cg.addArc(center:CGPoint(x:cx,y:cy),radius:radius,startAngle:start,endAngle:end,clockwise:false)
                    cg.closePath(); cg.fillPath()
                    let middle = (start+end)/2
                    if variant != "missingLabels" {
                        label(categories[i],cx+cos(middle)*280,cy+sin(middle)*280)
                    }
                    if variant == "printed" || variant == "conflict" {
                        let number = variant == "conflict" && i == 0 ? values[i]+10 : values[i]
                        label("\(Int(number))%",cx+cos(middle)*110,cy+sin(middle)*110,size:24)
                    }
                    start = end
                }
                if variant == "donut" {
                    UIColor.white.setFill(); cg.fillEllipse(in:CGRect(x:430,y:350,width:140,height:140))
                }
                if variant == "exploded" {
                    UIColor.white.setFill(); cg.fill(CGRect(x:495,y:220,width:16,height:400))
                }
                cg.restoreGState()
                return
            }
            let minimum = variant == "negative" ? -50.0 : variant == "nonzero" ? 40.0 : 0.0
            let maximum = 100.0
            func yy(_ value: Double) -> Double { 620-(value-minimum)/(maximum-minimum)*440 }
            func xx(_ value: Double) -> Double { 220+(value-minimum)/(maximum-minimum)*680 }
            let ticks = variant == "log" ? [1.0,10.0,100.0] : [minimum,(minimum+maximum)/2,maximum]
            let horizontal = kind == .horizontalBar
            for (i,value) in ticks.enumerated() {
                let y = 620-Double(i)*220, x = 220+Double(i)*340
                if variant != "missingTicks" {
                    let number = variant == "ocrError" && i == 1 ? "5O" : String(format:"%g",value)
                    label(number,horizontal ? x : 190,horizontal ? 660 : y,centered: horizontal)
                }
                if variant == "grid" {
                    UIColor(white:0.85,alpha:1).setStroke(); cg.setLineWidth(1)
                    cg.move(to:CGPoint(x:horizontal ? x : 220,y:horizontal ? 180 : y))
                    cg.addLine(to:CGPoint(x:horizontal ? x : 900,y:horizontal ? 620 : y));cg.strokePath()
                }
            }
            UIColor.black.setStroke();cg.setLineWidth(2)
            cg.move(to:CGPoint(x:220,y:180));cg.addLine(to:CGPoint(x:220,y:620));cg.addLine(to:CGPoint(x:900,y:620));cg.strokePath()
            if kind == .line {
                UIColor.systemBlue.setStroke(); cg.setLineWidth(4)
                let xs = [300.0,480,660,840]
                cg.move(to:CGPoint(x:xs[0],y:yy(values[0])))
                for i in 1..<values.count { cg.addLine(to:CGPoint(x:xs[i],y:yy(values[i]))) }
                cg.strokePath()
                for i in values.indices {
                    if !(variant == "missingMarker" && i == 1) {
                        UIColor.systemBlue.setFill();cg.fillEllipse(in:CGRect(x:xs[i]-11,y:yy(values[i])-11,width:22,height:22))
                    }
                    label(categories[i],xs[i],660)
                    if variant == "printed" { label(String(format:"%g",values[i]),xs[i],yy(values[i])-36,size:24) }
                }
                if variant == "intersecting" {
                    UIColor.systemRed.setStroke();cg.setLineWidth(4)
                    cg.move(to:CGPoint(x:300,y:200));cg.addLine(to:CGPoint(x:840,y:600));cg.strokePath()
                }
            } else {
                let baseline = minimum > 0 ? minimum : 0
                for i in values.indices {
                    let center = horizontal ? 260+Double(i)*140 : 340+Double(i)*220
                    let thickness = variant == "unequal" ? 40+Double(i)*20 : 64.0
                    let rect = horizontal
                        ? CGRect(x:min(xx(baseline),xx(values[i])),y:center-thickness/2,width:abs(xx(values[i])-xx(baseline)),height:thickness)
                        : CGRect(x:center-thickness/2,y:min(yy(baseline),yy(values[i])),width:thickness,height:abs(yy(values[i])-yy(baseline)))
                    (variant == "monochrome" ? UIColor.black : colors[i % colors.count]).setFill()
                    cg.fill(rect)
                    if horizontal { label(categories[i],190,center,centered:false) } else { label(categories[i],center,660) }
                    if variant == "printed" || variant == "conflict" {
                        let number = variant == "conflict" && i == 0 ? values[i]+20 : values[i]
                        label(String(format:"%g",number), horizontal ? xx(values[i])+45 : center,
                              horizontal ? center : yy(values[i])-30, size:24)
                    }
                    if variant == "grouped" {
                        UIColor.systemPurple.setFill()
                        cg.fill(horizontal ? rect.offsetBy(dx:0,dy:thickness+6) : rect.offsetBy(dx:thickness+6,dy:0))
                    }
                    if variant == "stacked" {
                        UIColor.systemPurple.setFill()
                        cg.fill(horizontal ? CGRect(x:rect.maxX,y:rect.minY,width:50,height:rect.height)
                            : CGRect(x:rect.minX,y:rect.minY-50,width:rect.width,height:50))
                    }
                    if variant == "3D" {
                        UIColor.gray.setFill()
                        cg.move(to:CGPoint(x:rect.maxX,y:rect.minY));cg.addLine(to:CGPoint(x:rect.maxX+22,y:rect.minY-22))
                        cg.addLine(to:CGPoint(x:rect.maxX+22,y:rect.maxY-22));cg.addLine(to:CGPoint(x:rect.maxX,y:rect.maxY))
                        cg.closePath();cg.fillPath()
                    }
                }
            }
            label("Category",560,750)
        }
        var data = image.pngData()!
        if variant == "lowResolution" {
            data = UIGraphicsImageRenderer(size:CGSize(width:250,height:200),format:format).image { _ in
                image.draw(in:CGRect(x:0,y:0,width:250,height:200))
            }.pngData()!
        }
        if variant == "rotated" {
            data = UIGraphicsImageRenderer(size:CGSize(width:800,height:1000),format:format).image { c in
                c.cgContext.translateBy(x:800,y:0);c.cgContext.rotate(by:.pi/2)
                image.draw(in:CGRect(x:0,y:0,width:1000,height:800))
            }.pngData()!
        }
        let ocr = OCRDocument(sourceID:"synthetic",observations:text,width:variant == "lowResolution" ? 250 : 1000,
                              height:variant == "lowResolution" ? 200 : 800,orientation:1)
        return ExtractionFixture(name:kind.rawValue+" / "+variant,kind:kind,values:values,categories:categories,
                                 data:data,idealOCR:ocr,shouldReject:unsupported)
    }
}
#endif
