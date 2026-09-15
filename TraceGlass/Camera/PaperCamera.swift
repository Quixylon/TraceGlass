import AVFoundation
import Vision
import UIKit
import Combine

final class PaperCamera: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    let session = AVCaptureSession()
    @Published private(set) var corners: [Point2] = []
    @Published private(set) var frameSize = CGSize(width: 1080, height: 1920)
    @Published private(set) var stability: TrackingQuality = .low
    @Published private(set) var finding = true
    @Published private(set) var referenceAlpha: Double = 0
    @Published var message: String?
    private let queue = DispatchQueue(label: "app.traceglass.camera", qos: .userInitiated)
    private let output = AVCaptureVideoDataOutput()
    private var configured = false
    private var sequence = VNSequenceRequestHandler()
    private var observation: VNRectangleObservation?
    private var smoother = PaperSmoother()
    private var frameNumber = 0
    private var lastReliable: Double = 0
    private var stableFrames = 0
    private var manual = false
    private var rotationAngle: CGFloat = 90
    private var detectionInterval = 12
    private var desiredRunning = false
    private var interruptionObservers: [NSObjectProtocol] = []
    override init() {
        super.init()
        interruptionObservers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionWasInterrupted, object: session, queue: .main) { [weak self] _ in
            self?.finding = true; self?.referenceAlpha = 0; self?.message = "Camera paused. It will resume when available."
        })
        interruptionObservers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionInterruptionEnded, object: session, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.queue.async { if self.desiredRunning { self.configureAndRun() } }
        })
        interruptionObservers.append(NotificationCenter.default.addObserver(forName: .AVCaptureSessionRuntimeError, object: session, queue: .main) { [weak self] _ in
            self?.message = "The camera stopped. Return to Lightbox and open AR again."
        })
    }
    deinit { interruptionObservers.forEach { NotificationCenter.default.removeObserver($0) } }
    func start() {
        queue.async { self.desiredRunning = true }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: queue.async { self.configureAndRun() }
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                guard let self else { return }
                self.queue.async {
                    guard self.desiredRunning else { return }
                    if granted { self.configureAndRun() }
                    else { DispatchQueue.main.async { self.message = TraceError.cameraDenied.localizedDescription } }
                }
            }
        default: DispatchQueue.main.async { self.message = TraceError.cameraDenied.localizedDescription }
        }
    }
    func stop() { queue.async { self.desiredRunning = false; if self.session.isRunning { self.session.stopRunning() } } }
    func setQuality(_ quality: Quality, warm: Bool) { queue.async { self.detectionInterval = warm || quality == .performance ? 18 : 10 } }
    func setOrientation(_ value: UIInterfaceOrientation) {
        let angle: CGFloat
        switch value { case .landscapeLeft: angle = 180; case .landscapeRight: angle = 0
        case .portraitUpsideDown: angle = 270; default: angle = 90 }
        queue.async {
            guard self.rotationAngle != angle else { return }
            self.rotationAngle = angle
            if let connection = self.output.connection(with: .video), connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
            self.smoother.reset(); self.observation = nil; self.sequence = VNSequenceRequestHandler()
        }
    }

    func seed(_ corners: [Point2]) {
        guard corners.count == 4, GeometryMath.homography(to: corners.map(\.cg)) != nil else {
            DispatchQueue.main.async { self.message = "Place the corners around the paper without crossing them." }; return
        }
        queue.async {
            let p = corners.map { CGPoint(x: $0.x, y: 1 - $0.y) }
            self.observation = VNRectangleObservation(requestRevision: 1, topLeft: p[0], bottomLeft: p[3], bottomRight: p[2], topRight: p[1])
            self.manual = true; self.smoother.reset(); self.sequence = VNSequenceRequestHandler()
        }
    }
    func reset() { queue.async { self.manual = false; self.observation = nil; self.smoother.reset(); self.sequence = VNSequenceRequestHandler() } }
    private func configureAndRun() {
        guard desiredRunning else { return }
        if !configured {
            session.beginConfiguration(); session.sessionPreset = .hd1920x1080
            guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
                  let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input), session.canAddOutput(output) else {
                session.commitConfiguration(); DispatchQueue.main.async { self.message = TraceError.cameraUnavailable.localizedDescription }; return
            }
            session.addInput(input)
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_420YpCbCr8BiPlanarFullRange]
            output.setSampleBufferDelegate(self, queue: queue); session.addOutput(output)
            if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(rotationAngle) { connection.videoRotationAngle = rotationAngle }
            if let connection = output.connection(with: .video), connection.isVideoStabilizationSupported { connection.preferredVideoStabilizationMode = .off }
            if (try? device.lockForConfiguration()) != nil {
                if device.isFocusModeSupported(.continuousAutoFocus) { device.focusMode = .continuousAutoFocus }
                device.unlockForConfiguration()
            }
            session.commitConfiguration(); configured = true
        }
        if !session.isRunning { session.startRunning() }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard desiredRunning, let pixel = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        autoreleasepool {
            frameNumber += 1
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sampleBuffer).seconds
            var next: VNRectangleObservation?
            if let observation {
                let tracking = VNTrackRectangleRequest(rectangleObservation: observation)
                tracking.trackingLevel = .accurate
                try? sequence.perform([tracking], on: pixel, orientation: .up)
                if let tracked = tracking.results?.first as? VNRectangleObservation, tracked.confidence > 0.45 { next = tracked }
            }
            if (next == nil || frameNumber % detectionInterval == 0), !manual || next == nil {
                let detection = VNDetectRectanglesRequest()
                detection.minimumConfidence = 0.6; detection.minimumSize = 0.12
                detection.minimumAspectRatio = 0.3; detection.maximumAspectRatio = 1
                detection.maximumObservations = 5; detection.quadratureTolerance = 35
                try? VNImageRequestHandler(cvPixelBuffer: pixel, orientation: .up).perform([detection])
                if let results = detection.results, !results.isEmpty {
                    if let old = observation {
                        let oldPoints = points(old)
                        if let match = results.min(by: { PaperSmoother.distance(points($0), oldPoints) < PaperSmoother.distance(points($1), oldPoints) }),
                           PaperSmoother.distance(points(match), oldPoints) < 0.18 { next = match }
                    } else { next = results.max { $0.boundingBox.width * $0.boundingBox.height < $1.boundingBox.width * $1.boundingBox.height } }
                }
            }
            if let next {
                observation = next; lastReliable = timestamp
                let sample = PaperEstimate(corners: points(next), confidence: Double(next.confidence), timestamp: timestamp)
                let estimate = smoother.update(sample)
                stableFrames = next.confidence > 0.7 ? min(30, stableFrames + 1) : 0
                let quality: TrackingQuality = stableFrames > 12 ? .excellent : (stableFrames > 3 ? .good : .low)
                let size = CGSize(width: CVPixelBufferGetWidth(pixel), height: CVPixelBufferGetHeight(pixel))
                DispatchQueue.main.async {
                    self.corners = estimate?.corners ?? []; self.frameSize = size
                    self.stability = quality; self.finding = quality == .low; self.referenceAlpha = 1
                }
            } else {
                stableFrames = 0
                let age = timestamp - lastReliable
                if age > 1.2 { observation = nil; manual = false }
                DispatchQueue.main.async { self.stability = .low; self.finding = true; self.referenceAlpha = age < 0.7 ? 1 : max(0, 1 - (age - 0.7) / 0.5) }
            }
        }
    }
    private func points(_ observation: VNRectangleObservation) -> [Point2] {
        [observation.topLeft, observation.topRight, observation.bottomRight, observation.bottomLeft].map { Point2(x: Double($0.x), y: 1 - Double($0.y)) }
    }
}
