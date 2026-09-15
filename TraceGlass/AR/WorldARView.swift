import SwiftUI
import ARKit
import RealityKit
import AVFoundation

@MainActor final class WorldTrackingService: NSObject, ObservableObject, ARSessionDelegate {
    @Published var stability: TrackingQuality = .low
    @Published var placed = false
    @Published var message: String?
    private(set) lazy var view: ARView = {
        let view = ARView(frame: .zero, cameraMode: .ar, automaticallyConfigureSession: false)
        view.session.delegate = self
        view.renderOptions.insert(.disableMotionBlur)
        view.renderOptions.insert(.disableDepthOfField)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(place(_:))))
        view.addGestureRecognizer(UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:))))
        view.addGestureRecognizer(UIRotationGestureRecognizer(target: self, action: #selector(rotate(_:))))
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(hide(_:)))
        hold.numberOfTouchesRequired = 2; hold.minimumPressDuration = 0.25; view.addGestureRecognizer(hold)
        return view
    }()
    private var anchor: AnchorEntity?
    private var reference: ModelEntity?
    private var lastImage: UIImage?
    private var texture: TextureResource?
    private var lastAR: ARSettings?
    private var running = false
    private var requested = false
    private var lastOcclusion = false
    weak var store: TraceStore?
    var occlusionSupported: Bool { ARWorldTrackingConfiguration.supportsFrameSemantics(.personSegmentationWithDepth) }
    var projectedReferenceCorners: [CGPoint] {
        guard let entity = reference, let image = lastImage, let settings = store?.project.ar else { return [] }
        let w = Float(settings.worldWidth) / 2, h = w * Float(image.size.height / image.size.width)
        let points: [SIMD3<Float>] = [SIMD3(-w,0,-h),SIMD3(w,0,-h),SIMD3(w,0,h),SIMD3(-w,0,h)]
        let screen = points.compactMap { view.project(entity.convert(position: $0, to: nil)) }
        return screen.count == 4 ? screen : []
    }
    func start() {
        requested = true
        guard ARWorldTrackingConfiguration.isSupported else { message = "World Anchor is unavailable on this iPhone. Use Paper Track or Lightbox."; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: run()
        case .notDetermined: AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            Task { @MainActor in if granted { self?.run() } else { self?.message = TraceError.cameraDenied.localizedDescription } }
        }
        default: message = TraceError.cameraDenied.localizedDescription
        }
    }
    private func run() {
        guard requested else { return }
        let config = ARWorldTrackingConfiguration()
        config.planeDetection = [.horizontal, .vertical]
        config.environmentTexturing = .none
        if store?.project.ar.occlusion == true, occlusionSupported { config.frameSemantics.insert(.personSegmentationWithDepth) }
        lastOcclusion = store?.project.ar.occlusion ?? false
        view.session.run(config); running = true
    }
    func stop() { requested = false; guard running else { return }; view.session.pause(); running = false }
    func reset() {
        guard store?.locked == false else { return }
        if let anchor { view.scene.removeAnchor(anchor) }; anchor = nil; reference = nil; placed = false
    }
    func update() {
        guard let store else { return }
        if running, lastOcclusion != store.project.ar.occlusion { run() }
        let image = store.originalVisible ? store.unfilteredReference : store.reference
        if image !== lastImage, let cg = image?.cgImage {
            do { texture = try TextureResource.generate(from: cg, options: .init(semantic: .color)); lastImage = image }
            catch { message = "This reference could not be placed. Try a smaller image." }
        }
        guard let reference, let texture, let image else { return }
        let s = store.project.ar
        let opacity = s.ghost ? min(0.25, s.opacity) : s.opacity
        var material = UnlitMaterial()
        material.color = .init(tint: .white, texture: .init(texture))
        material.blending = .transparent(opacity: .init(floatLiteral: Float(opacity)))
        if #available(iOS 18.0, *) { material.faceCulling = .none }
        reference.model?.materials = [material]
        let width = Float(s.worldWidth)
        let height = width * Float(image.size.height / image.size.width)
        if lastAR?.worldWidth != s.worldWidth || lastAR == nil {
            reference.model?.mesh = .generatePlane(width: width, depth: height)
        }
        reference.scale = SIMD3(Float(s.placement.scale) * (s.placement.mirrorX ? -1 : 1), 1,
                                Float(s.placement.scale) * (s.placement.mirrorY ? -1 : 1))
        reference.orientation = simd_quatf(angle: -Float(s.placement.rotation), axis: [0,1,0])
        reference.position = SIMD3(Float(s.placement.offset.x / 1000) * width, 0.001, Float(s.placement.offset.y / 1000) * width)
        reference.isEnabled = s.referenceVisible && !store.temporaryHidden && !store.transitionHidesReference
        lastAR = s
    }
    @objc private func place(_ g: UITapGestureRecognizer) {
        guard let store, !store.locked, running else { return }
        let point = g.location(in: view)
        guard let hit = view.raycast(from: point, allowing: .existingPlaneGeometry, alignment: .any).first
                ?? view.raycast(from: point, allowing: .estimatedPlane, alignment: .any).first else {
            message = "Move the iPhone slowly to find a surface, then tap it."; return
        }
        if let anchor { view.scene.removeAnchor(anchor) }
        let newAnchor = AnchorEntity(world: hit.worldTransform)
        let entity = ModelEntity(mesh: .generatePlane(width: 0.21, depth: 0.297), materials: [UnlitMaterial(color: .white)])
        newAnchor.addChild(entity); view.scene.addAnchor(newAnchor)
        anchor = newAnchor; reference = entity; lastAR = nil; placed = true; update()
        Feedback.impact(store.settings.value.haptics, sound: store.settings.value.sounds)
    }
    @objc private func pinch(_ g: UIPinchGestureRecognizer) {
        guard let store, !store.locked else { return }
        if g.state == .began { store.beginEdit() }
        store.update { $0.ar.placement.scale = min(10,max(0.05,$0.ar.placement.scale*g.scale)) }; g.scale = 1
        if [.ended,.cancelled,.failed].contains(g.state) { store.commitEdit() }; update()
    }
    @objc private func rotate(_ g: UIRotationGestureRecognizer) {
        guard let store, !store.locked else { return }
        if g.state == .began { store.beginEdit() }
        store.update { $0.ar.placement.rotation += g.rotation }; g.rotation = 0
        if [.ended,.cancelled,.failed].contains(g.state) { store.commitEdit() }; update()
    }
    @objc private func hide(_ g: UILongPressGestureRecognizer) {
        let holding = g.state == .began || g.state == .changed
        if store?.settings.value.twoFingerHold == .original, store?.locked == false { store?.originalVisible = holding }
        else { store?.temporaryHidden = holding }
        update()
    }
    nonisolated func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
        let quality: TrackingQuality
        switch camera.trackingState { case .normal: quality = .excellent; case .limited: quality = .low; case .notAvailable: quality = .low }
        Task { @MainActor in self.stability = quality }
    }
    nonisolated func session(_ session: ARSession, didFailWithError error: Error) {
        Task { @MainActor in self.stability = .low; self.message = "Tracking stopped. Return to Lightbox, then open AR again." }
    }
    nonisolated func sessionWasInterrupted(_ session: ARSession) {
        Task { @MainActor in self.stability = .low; self.message = "Tracking paused. Keep the surface in view when you return." }
    }
    nonisolated func sessionInterruptionEnded(_ session: ARSession) { Task { @MainActor in if self.requested { self.run() } } }
}

struct WorldARView: UIViewRepresentable {
    @ObservedObject var store: TraceStore
    @ObservedObject var service: WorldTrackingService
    func makeUIView(context: Context) -> ARView { service.store = store; return service.view }
    func updateUIView(_ view: ARView, context: Context) { service.update() }
    static func dismantleUIView(_ uiView: ARView, coordinator: ()) { uiView.session.pause() }
}
