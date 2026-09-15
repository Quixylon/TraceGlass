import Foundation
import CoreGraphics

struct PaperEstimate {
    var corners: [Point2]
    var confidence: Double
    var timestamp: Double
}
struct PaperSmoother {
    private(set) var current: PaperEstimate?
    private var candidate: PaperEstimate?
    private var candidateFrames = 0
    mutating func reset() { current = nil; candidate = nil; candidateFrames = 0 }
    mutating func update(_ sample: PaperEstimate) -> PaperEstimate? {
        guard sample.corners.count == 4, sample.corners.allSatisfy(\.isFinite), sample.confidence >= 0.35 else { return current }
        guard let old = current else { current = sample; return sample }
        let delta = Self.distance(old.corners, sample.corners)
        if delta > 0.18 {
            if let candidate, Self.distance(candidate.corners, sample.corners) < 0.03 { candidateFrames += 1 }
            else { candidateFrames = 1 }
            candidate = sample
            guard candidateFrames >= 4 else { return old }
        }
        candidate = nil; candidateFrames = 0
        let dt = max(1.0/120, min(0.2, sample.timestamp - old.timestamp))
        let tau = delta < 0.008 ? 0.075 : 0.018
        let alpha = 1 - exp(-dt / tau)
        let corners = zip(old.corners, sample.corners).map { a, b in
            Point2(x: a.x + (b.x - a.x) * alpha, y: a.y + (b.y - a.y) * alpha)
        }
        let result = PaperEstimate(corners: corners, confidence: old.confidence * 0.3 + sample.confidence * 0.7, timestamp: sample.timestamp)
        current = result; return result
    }
    static func distance(_ a: [Point2], _ b: [Point2]) -> Double {
        guard a.count == 4, b.count == 4 else { return .infinity }
        return zip(a,b).map { hypot($0.x - $1.x, $0.y - $1.y) }.reduce(0,+) / 4
    }
}

enum TrackingQuality: String {
    case low = "Low", good = "Good", excellent = "Excellent"
}
