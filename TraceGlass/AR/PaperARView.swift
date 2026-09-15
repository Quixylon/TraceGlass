import SwiftUI
import AVFoundation

struct PaperARView: UIViewRepresentable {
    @ObservedObject var store: TraceStore
    @ObservedObject var camera: PaperCamera
    var manual: Bool
    var onManualChange: ([Point2]) -> Void
    func makeUIView(context: Context) -> PaperPreview { PaperPreview(store: store, camera: camera) }
    func updateUIView(_ view: PaperPreview, context: Context) {
        view.manual = manual; view.onManualChange = onManualChange; view.refresh()
    }
    static func dismantleUIView(_ view: PaperPreview, coordinator: ()) { view.camera?.stop() }
}

final class PaperPreview: UIView, UIGestureRecognizerDelegate {
    weak var store: TraceStore?
    weak var camera: PaperCamera?
    let preview = AVCaptureVideoPreviewLayer()
    let paperLayer = CALayer()
    let reference = CALayer()
    let cornersLayer = CAShapeLayer()
    var manual = false
    var onManualChange: (([Point2]) -> Void)?
    private var manualPoints: [Point2] = [Point2(x: 0.2,y: 0.25), Point2(x: 0.8,y: 0.25), Point2(x: 0.8,y: 0.75), Point2(x: 0.2,y: 0.75)]
    private var draggedCorner: Int?
    private var activeGestures = Set<ObjectIdentifier>()
    init(store: TraceStore, camera: PaperCamera) {
        self.store = store; self.camera = camera
        super.init(frame: .zero); isMultipleTouchEnabled = true
        preview.session = camera.session; preview.videoGravity = .resizeAspectFill
        layer.addSublayer(preview); layer.addSublayer(paperLayer); paperLayer.addSublayer(reference); layer.addSublayer(cornersLayer)
        paperLayer.anchorPoint = .zero; paperLayer.position = .zero; paperLayer.bounds = CGRect(x: 0, y: 0, width: 1000, height: 1414)
        paperLayer.masksToBounds = true
        cornersLayer.fillColor = UIColor.clear.cgColor; cornersLayer.strokeColor = RGBA.mint.uiColor.cgColor; cornersLayer.lineWidth = 1
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(rotate(_:)))
        let hide = UILongPressGestureRecognizer(target: self, action: #selector(hide(_:)))
        hide.numberOfTouchesRequired = 2; hide.minimumPressDuration = 0.25
        for g in [pan, pinch, rotation, hide] { g.delegate = self; addGestureRecognizer(g) }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews(); preview.frame = bounds
        if let orientation = window?.windowScene?.interfaceOrientation {
            let angle: CGFloat = orientation == .landscapeLeft ? 180 : orientation == .landscapeRight ? 0 : 90
            if let connection = preview.connection, connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }; camera?.setOrientation(orientation)
        }
        refresh()
    }
    private func screen(_ p: Point2) -> CGPoint {
        guard let camera else { return .zero }
        let s = max(bounds.width / camera.frameSize.width, bounds.height / camera.frameSize.height)
        return CGPoint(x: p.x * camera.frameSize.width * s + (bounds.width - camera.frameSize.width * s)/2,
                       y: p.y * camera.frameSize.height * s + (bounds.height - camera.frameSize.height * s)/2)
    }
    private func normalized(_ p: CGPoint) -> Point2 {
        guard let camera else { return .zero }
        let s = max(bounds.width / camera.frameSize.width, bounds.height / camera.frameSize.height)
        return Point2(x: min(1,max(0,(p.x - (bounds.width-camera.frameSize.width*s)/2)/(camera.frameSize.width*s))),
                      y: min(1,max(0,(p.y - (bounds.height-camera.frameSize.height*s)/2)/(camera.frameSize.height*s))))
    }
    func refresh() {
        guard let store, let camera else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true); defer { CATransaction.commit() }
        let points = (manual ? manualPoints : camera.corners).map(screen)
        guard points.count == 4, let h = GeometryMath.homography(to: points) else { paperLayer.isHidden = true; return }
        paperLayer.isHidden = store.temporaryHidden || store.transitionHidesReference || !store.project.ar.referenceVisible
        let aspect = store.project.canvas.paper == .custom ? store.project.canvas.customPaper : store.project.canvas.paper.size
        let ph = 1000 * aspect.y / max(1,aspect.x)
        paperLayer.bounds.size = CGSize(width: 1000, height: ph)
        var t = CATransform3DIdentity
        t.m11 = h[0]/1000; t.m21 = h[1]/ph; t.m41 = h[2]
        t.m12 = h[3]/1000; t.m22 = h[4]/ph; t.m42 = h[5]
        t.m14 = h[6]/1000; t.m24 = h[7]/ph; t.m44 = 1
        paperLayer.transform = t
        let image = store.originalVisible ? store.unfilteredReference : store.reference
        reference.contents = image?.cgImage
        let size = image?.size ?? CGSize(width: 1,height: 1)
        let fit = min(1000/size.width, ph/size.height)
        reference.bounds = CGRect(x: 0,y: 0,width: size.width*fit,height: size.height*fit)
        let placement = store.project.ar.placement
        reference.position = CGPoint(x: 500 + placement.offset.x, y: ph/2 + placement.offset.y)
        reference.setAffineTransform(CGAffineTransform(rotationAngle: placement.rotation)
            .scaledBy(x: placement.scale * (placement.mirrorX ? -1 : 1), y: placement.scale * (placement.mirrorY ? -1 : 1)))
        reference.opacity = Float((store.project.ar.ghost ? min(0.25,store.project.ar.opacity) : store.project.ar.opacity) * (manual ? 1 : camera.referenceAlpha))
        reference.shadowColor = UIColor.white.cgColor
        reference.shadowRadius = store.project.ar.projector ? 3 + store.project.ar.intensity * 7 : 0
        reference.shadowOpacity = store.project.ar.projector ? Float(store.project.ar.intensity * 0.5) : 0
        reference.shadowOffset = .zero
        let path = UIBezierPath()
        for i in 0..<4 {
            let p = points[i], before = points[(i+3)%4], after = points[(i+1)%4]
            func near(_ q: CGPoint) -> CGPoint { let length = max(1,hypot(q.x-p.x,q.y-p.y)); return CGPoint(x:p.x+(q.x-p.x)*18/length,y:p.y+(q.y-p.y)*18/length) }
            path.move(to: near(before)); path.addLine(to: p); path.addLine(to: near(after))
            if manual { path.append(UIBezierPath(ovalIn: CGRect(x:p.x-13,y:p.y-13,width:26,height:26))) }
        }
        cornersLayer.path = path.cgPath; cornersLayer.opacity = store.locked ? 0 : camera.finding || manual ? 1 : 0.4
    }
    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        if g is UILongPressGestureRecognizer { return true }
        return store?.locked == false
    }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        !(g is UILongPressGestureRecognizer) && !(other is UILongPressGestureRecognizer) && !manual
    }
    private func transaction(_ g: UIGestureRecognizer) {
        guard let store, !store.locked else { return }
        if g.state == .began { if activeGestures.isEmpty { store.beginEdit() }; activeGestures.insert(ObjectIdentifier(g)) }
        if [.ended,.cancelled,.failed].contains(g.state) { activeGestures.remove(ObjectIdentifier(g)); if activeGestures.isEmpty { store.commitEdit() } }
    }
    @objc private func pan(_ g: UIPanGestureRecognizer) {
        guard let store, !store.locked else { return }
        if manual {
            let point = g.location(in: self)
            if g.state == .began { draggedCorner = manualPoints.indices.min { hypot(screen(manualPoints[$0]).x-point.x,screen(manualPoints[$0]).y-point.y) < hypot(screen(manualPoints[$1]).x-point.x,screen(manualPoints[$1]).y-point.y) } }
            if let i = draggedCorner { manualPoints[i] = normalized(point); refresh() }
            if g.state == .ended { onManualChange?(manualPoints); draggedCorner = nil }
            return
        }
        if g.state == .began { transaction(g) }
        let d = g.translation(in:self); g.setTranslation(.zero,in:self)
        let width = camera?.corners.count == 4 ? max(30,hypot(screen(camera!.corners[1]).x-screen(camera!.corners[0]).x,screen(camera!.corners[1]).y-screen(camera!.corners[0]).y)) : bounds.width
        store.update { $0.ar.placement.offset.x += d.x * 1000/width; $0.ar.placement.offset.y += d.y * 1000/width }
        if g.state != .began { transaction(g) }
    }
    @objc private func pinch(_ g: UIPinchGestureRecognizer) {
        guard let store, !store.locked, !manual else { return }
        if g.state == .began { transaction(g) }
        store.update { $0.ar.placement.scale = max(0.05,min(10,$0.ar.placement.scale*g.scale)) }; g.scale = 1
        if g.state != .began { transaction(g) }
    }
    @objc private func rotate(_ g: UIRotationGestureRecognizer) {
        guard let store, !store.locked, !manual else { return }
        if g.state == .began { transaction(g) }
        store.update { $0.ar.placement.rotation += g.rotation }; g.rotation = 0
        if g.state != .began { transaction(g) }
    }
    @objc private func hide(_ g: UILongPressGestureRecognizer) {
        // Temporary visibility is deliberately not a document edit; AR tracking stays active.
        let hold = g.state == .began || g.state == .changed
        if store?.settings.value.twoFingerHold == .original, store?.locked == false { store?.originalVisible = hold }
        else { store?.temporaryHidden = hold }
    }
}
