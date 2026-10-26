import Foundation
import CoreGraphics
import ImageIO

struct Raster: Sendable {
    let width: Int
    let height: Int
    let pixels: [UInt8]
    struct Color: Sendable {
        let r: Double; let g: Double; let b: Double
        var chroma: Double { max(r, g, b) - min(r, g, b) }
        var darkness: Double { 1 - (r + g + b) / 3 }
        func distance(_ other: Color) -> Double {
            sqrt(pow(r - other.r, 2) + pow(g - other.g, 2) + pow(b - other.b, 2))
        }
    }
    func color(_ x: Int, _ y: Int) -> Color {
        guard x >= 0, y >= 0, x < width, y < height else { return Color(r: 1, g: 1, b: 1) }
        let i = (y * width + x) * 4
        return Color(r: Double(pixels[i]) / 255, g: Double(pixels[i+1]) / 255, b: Double(pixels[i+2]) / 255)
    }
    func color(normalX: Double, normalY: Double) -> Color {
        color(Int(normalX * Double(width)), Int(normalY * Double(height)))
    }
    init(data: Data) throws {
        try Task.checkCancellation()
        guard let src = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(src, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 800,
                kCGImageSourceCreateThumbnailWithTransform: true
              ] as CFDictionary) else { throw AnalysisFailure.invalidImage }
        let width = image.width, height = image.height
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        let success = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)
            else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard success else { throw AnalysisFailure.invalidImage }
        self.width = width; self.height = height; pixels = bytes
    }

    struct Component: Sendable {
        let box: ImageBox
        let area: Int
        let fill: Double
        let color: Color
    }

    func foregroundMask(excluding text: [OCRText]) throws -> [Bool] {
        var mask = [Bool](repeating: false, count: width * height)
        for y in 0..<height {
            if y % 32 == 0 { try Task.checkCancellation() }
            for x in 0..<width {
                let c = color(x, y)
                // Chroma-independent dark fills and any sufficiently chromatic fill;
                // light gray grid lines are deliberately excluded.
                mask[y * width + x] = c.chroma > 0.15 || c.darkness > 0.40
            }
        }
        for observation in text {
            try Task.checkCancellation()
            let b = observation.box
            let x0 = max(0, Int((b.x - 0.004) * Double(width)))
            let x1 = min(width, Int(ceil((b.maxX + 0.004) * Double(width))))
            let y0 = max(0, Int((b.y - 0.004) * Double(height)))
            let y1 = min(height, Int(ceil((b.maxY + 0.004) * Double(height))))
            guard x0 < x1, y0 < y1 else { continue }
            for y in y0..<y1 {
                for x in x0..<x1 where color(x,y).chroma < 0.12 {
                    mask[y * width + x] = false
                }
            }
        }
        // Remove thin, long neutral axes without deleting broad filled bars.
        let longRows = try (0..<height).map { y in
            if y % 32 == 0 { try Task.checkCancellation() }
            return (0..<width).filter { mask[y * width + $0] && color($0, y).chroma < 0.1 }.count > width / 3
        }
        let longCols = try (0..<width).map { x in
            if x % 32 == 0 { try Task.checkCancellation() }
            return (0..<height).filter { mask[$0 * width + x] && color(x, $0).chroma < 0.1 }.count > height / 3
        }
        for y in 0..<height where longRows[y] {
            let neighbors = (max(0,y-4)...min(height-1,y+4)).filter { longRows[$0] }.count
            if neighbors <= 4 { for x in 0..<width where color(x,y).chroma < 0.1 { mask[y*width+x] = false } }
        }
        for x in 0..<width where longCols[x] {
            let neighbors = (max(0,x-4)...min(width-1,x+4)).filter { longCols[$0] }.count
            if neighbors <= 4 { for y in 0..<height where color(x,y).chroma < 0.1 { mask[y*width+x] = false } }
        }
        return mask
    }

    func components(mask: [Bool], separateColors: Bool = true) throws -> [Component] {
        var visited = [Bool](repeating: false, count: mask.count)
        var result: [Component] = []
        for index in mask.indices {
            if index % 2048 == 0 { try Task.checkCancellation() }
            guard mask[index] && !visited[index] else { continue }
            let first = color(index % width, index / width)
            var stack = [index], count = 0
            var minX = width, minY = height, maxX = 0, maxY = 0
            visited[index] = true
            while let next = stack.popLast() {
                count += 1
                let x = next % width, y = next / width
                minX = min(minX,x); maxX = max(maxX,x); minY = min(minY,y); maxY = max(maxY,y)
                for (nx,ny) in [(x-1,y),(x+1,y),(x,y-1),(x,y+1)] where nx >= 0 && ny >= 0 && nx < width && ny < height {
                    let j = ny*width+nx
                    if mask[j] && !visited[j] && (!separateColors || color(nx,ny).distance(first) < 0.2) {
                        visited[j] = true; stack.append(j)
                    }
                }
                if count % 8192 == 0 { try Task.checkCancellation() }
            }
            if count >= 12 {
                let w = maxX-minX+1, h = maxY-minY+1
                result.append(Component(box: ImageBox(x: Double(minX)/Double(width), y: Double(minY)/Double(height),
                    width: Double(w)/Double(width), height: Double(h)/Double(height)),
                    area: count, fill: Double(count)/Double(w*h), color: first))
            }
        }
        return result
    }
}
