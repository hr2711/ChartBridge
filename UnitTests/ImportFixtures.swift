#if DEBUG
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

enum ImportFixtures {
    static func image(type: UTType = .png, width: Int = 240, height: Int = 160) -> Data {
        let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.setFillColor(CGColor(red: 0, green: 0.3, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 40, y: 20, width: 40, height: 100))
        context.fill(CGRect(x: 100, y: 20, width: 40, height: 60))
        let data = NSMutableData()
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, context.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(destination))
        return data as Data
    }

    static func pdf(pages: Int = 1, encrypted: Bool = false) -> Data {
        let data = NSMutableData()
        var rect = CGRect(x: 0, y: 0, width: 240, height: 160)
        let consumer = CGDataConsumer(data: data)!
        let info: CFDictionary? = encrypted
            ? [kCGPDFContextUserPassword: "test-password", kCGPDFContextOwnerPassword: "owner-password"] as CFDictionary : nil
        let context = CGContext(consumer: consumer, mediaBox: &rect, info)!
        for _ in 0..<pages {
            context.beginPDFPage(nil)
            context.setFillColor(CGColor(gray: 0.2, alpha: 1))
            context.fill(CGRect(x: 40, y: 20, width: 40, height: 100))
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }
}
#endif
