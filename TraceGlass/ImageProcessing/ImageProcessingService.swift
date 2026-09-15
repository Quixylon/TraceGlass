import Foundation
import CoreImage
import CoreImage.CIFilterBuiltins
import Metal
import UIKit
import Vision

actor ImageProcessingService {
    private let context: CIContext
    init() {
        if let device = MTLCreateSystemDefaultDevice() {
            context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false, .workingColorSpace: CGColorSpace(name: CGColorSpace.extendedLinearSRGB)!])
        } else { context = CIContext(options: [.cacheIntermediates: false]) }
    }
    func clearCaches() { context.clearCaches() }
    func render(_ source: CGImage, settings s: FilterSettings, geometry: ImageGeometry = ImageGeometry()) throws -> CGImage {
        var input = CIImage(cgImage: source)
        if let corners = geometry.corners, corners.count == 4 {
            let w = input.extent.width, h = input.extent.height
            let points = corners.map { CIVector(x: $0.x * w, y: (1 - $0.y) * h) }
            input = input.applyingFilter("CIPerspectiveCorrection", parameters: [
                "inputTopLeft": points[0], "inputTopRight": points[1],
                "inputBottomRight": points[2], "inputBottomLeft": points[3]])
            input = input.transformed(by: CGAffineTransform(translationX: -input.extent.minX, y: -input.extent.minY))
        }
        if let crop = geometry.crop, crop.count == 4 {
            let e = input.extent
            let r = CGRect(x: crop[0] * e.width, y: (1 - crop[1] - crop[3]) * e.height,
                           width: crop[2] * e.width, height: crop[3] * e.height).intersection(e)
            if r.width > 1, r.height > 1 { input = input.cropped(to: r).transformed(by: CGAffineTransform(translationX: -r.minX, y: -r.minY)) }
        }
        let extent = input.extent
        let alphaSource = input
        if s.cleanup > 0 {
            input = input.applyingFilter("CINoiseReduction", parameters: ["inputNoiseLevel": 0.005 + s.cleanup * 0.06, "inputSharpness": 0.4 + s.cleanup * 0.5])
            if s.cleanup > 0.65 { input = input.applyingFilter("CIMedianFilter") }
        }
        input = input.applyingFilter("CIColorControls", parameters: [
            kCIInputBrightnessKey: s.brightness, kCIInputContrastKey: s.contrast,
            kCIInputSaturationKey: s.grayscale ? 0 : s.saturation])
        if s.exposure != 0 { input = input.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: s.exposure]) }
        if s.highlights != 1 || s.shadows != 0 {
            input = input.applyingFilter("CIHighlightShadowAdjust", parameters: ["inputHighlightAmount": s.highlights, "inputShadowAmount": s.shadows])
        }
        if s.blackPoint > 0 {
            let gain = 1 / max(0.1, 1 - s.blackPoint)
            input = input.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: gain, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: gain, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: gain, w: 0),
                "inputBiasVector": CIVector(x: -s.blackPoint * gain, y: -s.blackPoint * gain, z: -s.blackPoint * gain, w: 0)])
        }
        if s.sharpness > 0 { input = input.applyingFilter("CISharpenLuminance", parameters: [kCIInputSharpnessKey: s.sharpness]) }
        if s.edgeMode != .original {
            input = input.applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 0])
                .applyingFilter("CIEdges", parameters: [kCIInputIntensityKey: s.edgeStrength])
            if s.edgeMode == .clean {
                input = input.applyingFilter("CIColorThreshold", parameters: ["inputThreshold": 0.12 + s.threshold * 0.35])
            }
            if [.black, .clean, .inverted].contains(s.edgeMode) { input = input.applyingFilter("CIColorInvert") }
        }
        if s.thresholdEnabled { input = input.applyingFilter("CIColorThreshold", parameters: ["inputThreshold": s.threshold]) }
        if s.invert { input = input.applyingFilter("CIColorInvert") }
        // Filters must never fill the transparent region of a PNG.
        let clear = CIImage(color: .clear).cropped(to: extent)
        input = input.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 1)])
        input = input.applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: clear, kCIInputMaskImageKey: alphaSource]).cropped(to: extent)
        guard let cg = context.createCGImage(input, from: extent, format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) else { throw TraceError.rendering }
        return cg
    }
    func prepare(_ source: CGImage) -> FilterSettings {
        let small = CIImage(cgImage: source).transformed(by: CGAffineTransform(scaleX: 128 / Double(source.width), y: 128 / Double(source.height)))
        var pixels = [UInt8](repeating: 0, count: 128 * 128 * 4)
        pixels.withUnsafeMutableBytes { context.render(small, toBitmap: $0.baseAddress!, rowBytes: 512,
                                                       bounds: CGRect(x: 0, y: 0, width: 128, height: 128), format: .RGBA8, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)) }
        var histogram = [Int](repeating: 0, count: 256)
        for i in stride(from: 0, to: pixels.count, by: 4) where pixels[i+3] > 32 {
            let luma = Int(0.2126 * Double(pixels[i]) + 0.7152 * Double(pixels[i+1]) + 0.0722 * Double(pixels[i+2]))
            histogram[min(255, luma)] += 1
        }
        let total = histogram.reduce(0, +)
        guard total > 0 else { return FilterSettings() }
        let sum = histogram.enumerated().reduce(0.0) { $0 + Double($1.offset * $1.element) }
        var w0 = 0, sum0 = 0.0, best = 0.0, threshold = 128
        for t in 0..<255 {
            w0 += histogram[t]; sum0 += Double(t * histogram[t])
            let w1 = total - w0
            guard w0 > 0, w1 > 0 else { continue }
            let delta = sum0 / Double(w0) - (sum - sum0) / Double(w1)
            let variance = Double(w0 * w1) * delta * delta
            if variance > best { best = variance; threshold = t }
        }
        let whiteFraction = Double(histogram[220...255].reduce(0,+)) / Double(total)
        var result = FilterSettings()
        result.grayscale = true; result.contrast = 1.15; result.cleanup = 0.4
        result.threshold = min(0.8, max(0.18, Double(threshold) / 255))
        result.thresholdEnabled = whiteFraction > 0.25
        result.edgeMode = whiteFraction > 0.25 ? .original : .black
        result.edgeStrength = 3; result.sharpness = 0.3
        return result
    }
    func detectRectangle(_ image: CGImage) -> [Point2]? {
        let request = VNDetectRectanglesRequest()
        request.maximumObservations = 1; request.minimumConfidence = 0.6
        request.minimumAspectRatio = 0.2; request.minimumSize = 0.1
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return request.results?.first.map { observation in
            [observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft]
                .map { Point2(x: Double($0.x), y: 1 - Double($0.y)) }
        }
    }
}

enum TracePreset: String, CaseIterable, Identifiable {
    case original = "Original", sketch = "Sketch", clean = "Clean Lines", dark = "Dark Lines"
    case inverted = "Inverted", lightbox = "Lightbox", paper = "Paper Trace", ghost = "AR Ghost"
    var id: String { rawValue }
    var filters: FilterSettings {
        var s = FilterSettings()
        switch self {
        case .original, .ghost: break
        case .sketch: s.grayscale = true; s.contrast = 1.4; s.sharpness = 0.4
        case .clean: s.edgeMode = .clean; s.cleanup = 0.6; s.edgeStrength = 3
        case .dark: s.grayscale = true; s.contrast = 1.8; s.blackPoint = 0.1
        case .inverted: s.invert = true
        case .lightbox: s.grayscale = true; s.contrast = 1.4; s.brightness = 0.08
        case .paper: s.grayscale = true; s.thresholdEnabled = true; s.cleanup = 0.5
        }
        return s
    }
}
