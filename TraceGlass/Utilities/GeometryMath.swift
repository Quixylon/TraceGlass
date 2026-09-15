import Foundation
import CoreGraphics

extension Point2 {
    init(_ point: CGPoint) { x = point.x; y = point.y }
    var cg: CGPoint { CGPoint(x: x, y: y) }
}
enum GeometryMath {
    static func fitScale(image: CGSize, canvas: CGSize, fill: Bool = false) -> Double {
        guard image.width > 0, image.height > 0 else { return 1 }
        let a = canvas.width / image.width, b = canvas.height / image.height
        return fill ? max(a, b) : min(a, b)
    }
    static func aroundPivot(_ transform: ImageTransform, pivot: Point2, scale: Double = 1, angle: Double = 0) -> ImageTransform {
        var result = transform
        let x = transform.offset.x - pivot.x, y = transform.offset.y - pivot.y
        result.offset = Point2(x: pivot.x + scale * (x * cos(angle) - y * sin(angle)),
                              y: pivot.y + scale * (x * sin(angle) + y * cos(angle)))
        result.scale *= scale; result.rotation += angle
        return result.sanitized()
    }
    static func snap(_ t: ImageTransform, canvas: CGSize, image: CGSize) -> (ImageTransform, Bool, Bool, Bool) {
        var r = t
        var gx = false, gy = false, ga = false
        let angle = (t.rotation / (.pi / 4)).rounded() * (.pi / 4)
        if abs(t.rotation - angle) < .pi / 90 { r.rotation = angle; ga = true }
        let width = (abs(cos(r.rotation)) * image.width + abs(sin(r.rotation)) * image.height) * r.scale
        let height = (abs(sin(r.rotation)) * image.width + abs(cos(r.rotation)) * image.height) * r.scale
        for target in [0, (canvas.width - width) / 2, -(canvas.width - width) / 2] {
            if abs(r.offset.x - target) < 6 { r.offset.x = target; gx = true; break }
        }
        for target in [0, (canvas.height - height) / 2, -(canvas.height - height) / 2] {
            if abs(r.offset.y - target) < 6 { r.offset.y = target; gy = true; break }
        }
        return (r, gx, gy, ga)
    }
    // Solves the eight-unknown homography. Reject degenerate or self-crossing quads.
    static func homography(to p: [CGPoint]) -> [Double]? {
        guard p.count == 4, p.allSatisfy({ $0.x.isFinite && $0.y.isFinite }) else { return nil }
        let turns = (0..<4).map { i -> CGFloat in
            let a = p[i], b = p[(i+1)%4], c = p[(i+2)%4]
            return (b.x-a.x)*(c.y-b.y)-(b.y-a.y)*(c.x-b.x)
        }
        guard turns.allSatisfy({ $0 > 1e-8 }) || turns.allSatisfy({ $0 < -1e-8 }) else { return nil }
        let source: [(Double, Double)] = [(0,0),(1,0),(1,1),(0,1)]
        var a = Array(repeating: Array(repeating: 0.0, count: 9), count: 8)
        for i in 0..<4 {
            let (x,y) = source[i], u = Double(p[i].x), v = Double(p[i].y)
            a[i*2] = [x,y,1,0,0,0,-u*x,-u*y,u]
            a[i*2+1] = [0,0,0,x,y,1,-v*x,-v*y,v]
        }
        for i in 0..<8 {
            let row = (i..<8).max { abs(a[$0][i]) < abs(a[$1][i]) }!
            guard abs(a[row][i]) > 1e-10 else { return nil }
            a.swapAt(i, row)
            let divisor = a[i][i]
            for j in i..<9 { a[i][j] /= divisor }
            for k in 0..<8 where k != i {
                let factor = a[k][i]
                for j in i..<9 { a[k][j] -= factor * a[i][j] }
            }
        }
        return (0..<8).map { a[$0][8] } + [1]
    }
    static func tiles(width: Double, height: Double, viewport: CGSize, overlap: Double) -> [Point2] {
        let stepX = max(1, viewport.width - overlap), stepY = max(1, viewport.height - overlap)
        let columns = min(40, max(1, Int(ceil(max(0, width - viewport.width) / stepX)) + 1))
        let rows = min(40, max(1, Int(ceil(max(0, height - viewport.height) / stepY)) + 1))
        return (0..<rows).flatMap { row in (0..<columns).map { col in
            Point2(x: width / 2 - min(Double(col) * stepX, max(0, width - viewport.width)) - viewport.width / 2,
                   y: height / 2 - min(Double(row) * stepY, max(0, height - viewport.height)) - viewport.height / 2)
        }}
    }
}
