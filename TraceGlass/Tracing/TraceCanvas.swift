import SwiftUI
import UIKit

struct TraceCanvas: UIViewRepresentable {
    @ObservedObject var store: TraceStore
    func makeUIView(context: Context) -> TraceCanvasView { TraceCanvasView(store: store) }
    func updateUIView(_ view: TraceCanvasView, context: Context) { view.refresh() }
    static func dismantleUIView(_ view: TraceCanvasView, coordinator: ()) { view.store?.captureCanvas = nil }
}

final class TraceCanvasView: UIView, UIGestureRecognizerDelegate {
    weak var store: TraceStore?
    private let content = UIView()
    private var layerViews: [UUID: UIImageView] = [:]
    private let frozen = UIImageView()
    private let grid = CAShapeLayer()
    private let imageGrid = CAShapeLayer()
    private let hints = CAShapeLayer()
    private let rulerTicks = CAShapeLayer()
    private let tileGuides = CAShapeLayer()
    private var rulerLabels: [CATextLayer] = []
    private var gestures = Set<ObjectIdentifier>()
    private var lastGrid = GridSettings()
    private var lastBounds = CGRect.zero
    private var lastGridLayer: UUID?
    private var lastCalibration: Double?
    private var lastImageGridSize = CGSize.zero
    private var lastFilters: [UUID: FilterSettings] = [:]
    private var panOffset = Point2.zero
    private let comparisonOriginal = UIImageView()
    private let comparisonMask = CAShapeLayer()
    private let comparisonLine = CAShapeLayer()
    private var comparisonPan: UIPanGestureRecognizer!
    init(store: TraceStore) {
        self.store = store
        super.init(frame: .zero)
        isMultipleTouchEnabled = true; clipsToBounds = true
        addSubview(content); addSubview(comparisonOriginal); addSubview(frozen)
        layer.addSublayer(grid); layer.addSublayer(hints); layer.addSublayer(comparisonLine)
        layer.addSublayer(rulerTicks); layer.addSublayer(tileGuides)
        comparisonOriginal.layer.mask = comparisonMask
        frozen.contentMode = .topLeft; frozen.isHidden = true
        let pan = UIPanGestureRecognizer(target: self, action: #selector(pan(_:)))
        pan.maximumNumberOfTouches = 3
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch(_:)))
        let rotation = UIRotationGestureRecognizer(target: self, action: #selector(rotate(_:)))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        let original = UILongPressGestureRecognizer(target: self, action: #selector(original(_:)))
        original.minimumPressDuration = 0.35; original.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.direct.rawValue)]
        let two = UILongPressGestureRecognizer(target: self, action: #selector(twoFinger(_:)))
        two.numberOfTouchesRequired = 2; two.minimumPressDuration = 0.3
        comparisonPan = UIPanGestureRecognizer(target: self, action: #selector(compare(_:)))
        for recognizer in [pan, pinch, rotation, doubleTap, original, two, comparisonPan!] {
            recognizer.delegate = self; addGestureRecognizer(recognizer)
        }
        isAccessibilityElement = true
        accessibilityIdentifier = "traceCanvas"
        accessibilityLabel = "Reference canvas"
        accessibilityHint = "Use Transform tools to position the image, then Lock to trace."
        store.captureCanvas = { [weak self] in self?.snapshot() }
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard let store else { return }
        if !store.locked {
            content.frame = bounds
            if bounds.size != store.viewport, bounds.width > 0 {
                let size = bounds.size
                DispatchQueue.main.async { [weak store] in if store?.locked == false { store?.viewport = size } }
            }
        }
        refresh()
    }
    func refresh() {
        guard let store else { return }
        if let t = store.selected?.transform { accessibilityValue = String(format: "%.6f,%.6f,%.6f,%.6f", t.offset.x,t.offset.y,t.scale,t.rotation) }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        if store.locked, let frame = store.freezeFrame {
            frozen.image = frame; frozen.frame = CGRect(origin: .zero, size: store.frozenSize)
            frozen.isHidden = false; content.isHidden = true; grid.isHidden = true
            hints.isHidden = true; comparisonOriginal.isHidden = true; comparisonLine.isHidden = true
            rulerLabels.forEach { $0.isHidden = true }
            rulerTicks.isHidden = true; tileGuides.isHidden = true
            return
        }
        frozen.isHidden = true; frozen.image = nil; content.isHidden = false; grid.isHidden = false; hints.isHidden = false
        rulerLabels.forEach { $0.isHidden = false }
        rulerTicks.isHidden = false; tileGuides.isHidden = false
        backgroundColor = store.project.canvas.background.uiColor
        let ids = Set(store.project.layers.map(\.id))
        for id in Array(layerViews.keys) where !ids.contains(id) { layerViews.removeValue(forKey: id)?.removeFromSuperview() }
        for layer in store.project.layers {
            let v = layerViews[layer.id] ?? UIImageView()
            if layerViews[layer.id] == nil { content.addSubview(v); layerViews[layer.id] = v }
            let nextImage = store.originalVisible && layer.id == store.selected?.id ? store.unfilteredReference : store.images[layer.id]
            if nextImage !== v.image, !store.originalVisible, !UIAccessibility.isReduceMotionEnabled {
                let old = lastFilters[layer.id]
                let shouldReveal = v.image == nil || old?.invert != layer.filters.invert || old?.edgeMode != layer.filters.edgeMode || old?.thresholdEnabled != layer.filters.thresholdEnabled
                if shouldReveal {
                    let reveal = CATransition(); reveal.type = .reveal; reveal.subtype = .fromLeft; reveal.duration = v.image == nil ? 0.28 : 0.18
                    v.layer.add(reveal, forKey: "referenceReveal")
                }
                lastFilters[layer.id] = layer.filters
            }
            v.image = nextImage
            let size = v.image?.size ?? CGSize(width: 1, height: 1)
            v.bounds = CGRect(x: 0, y: 0, width: 1000, height: 1000 * size.height / max(size.width, 1))
            v.center = CGPoint(x: bounds.midX + layer.transform.offset.x, y: bounds.midY + layer.transform.offset.y)
            v.transform = affine(layer.transform)
            v.alpha = layer.opacity; v.isHidden = !layer.visible || store.temporaryHidden || store.transitionHidesReference
            v.layer.minificationFilter = .trilinear; v.layer.magnificationFilter = .linear
        }
        content.subviews.forEach { if let v = $0 as? UIImageView, let id = layerViews.first(where: { $0.value === v })?.key,
            let index = store.project.layers.firstIndex(where: { $0.id == id }) { v.layer.zPosition = CGFloat(index) } }
        drawGrid(store.project.canvas.grid)
        if store.project.canvas.tileEnabled, let ppm = store.project.canvas.calibratedPointsPerMM ?? store.settings.value.calibratedPointsPerMM {
            let overlap = min(min(bounds.width,bounds.height)/3, store.project.canvas.tileOverlapMM * ppm)
            tileGuides.path = UIBezierPath(rect: bounds.insetBy(dx: overlap, dy: overlap)).cgPath
            tileGuides.fillColor = nil; tileGuides.strokeColor = RGBA.mint.uiColor.cgColor
            tileGuides.lineWidth = 0.7; tileGuides.lineDashPattern = [5,4]
        } else { tileGuides.path = nil }
        drawComparison()
        let hp = UIBezierPath()
        if store.guides.x != 0 { hp.move(to: CGPoint(x: bounds.midX, y: 0)); hp.addLine(to: CGPoint(x: bounds.midX, y: bounds.height)) }
        if store.guides.y != 0 { hp.move(to: CGPoint(x: 0, y: bounds.midY)); hp.addLine(to: CGPoint(x: bounds.width, y: bounds.midY)) }
        hints.path = hp.cgPath; hints.strokeColor = RGBA.mint.uiColor.cgColor; hints.lineWidth = 0.5
    }
    private func affine(_ t: ImageTransform) -> CGAffineTransform {
        CGAffineTransform(rotationAngle: t.rotation).scaledBy(x: t.scale * (t.mirrorX ? -1 : 1), y: t.scale * (t.mirrorY ? -1 : 1))
    }
    private func drawGrid(_ settings: GridSettings) {
        let ppm = store?.project.canvas.calibratedPointsPerMM ?? store?.settings.value.calibratedPointsPerMM
        let selectedSize = store?.selected.flatMap { layerViews[$0.id]?.bounds.size } ?? .zero
        let changed = lastGrid != settings || bounds != lastBounds || lastGridLayer != store?.selected?.id || lastCalibration != ppm || lastImageGridSize != selectedSize
        guard changed else { return }
        lastGrid = settings; lastBounds = bounds; lastGridLayer = store?.selected?.id
        lastCalibration = ppm; lastImageGridSize = selectedSize
        let p = UIBezierPath(), target = settings.space == .image ? imageGrid : grid
        imageGrid.removeFromSuperlayer(); grid.path = nil
        var rect = bounds
        if settings.space == .image, let id = store?.selected?.id, let v = layerViews[id] { v.layer.addSublayer(imageGrid); rect = v.bounds }
        let count = settings.count
        if count > 0 {
            for i in 1..<count {
                let x = rect.width * Double(i) / Double(count), y = rect.height * Double(i) / Double(count)
                p.move(to: CGPoint(x: x, y: 0)); p.addLine(to: CGPoint(x: x, y: rect.height))
                p.move(to: CGPoint(x: 0, y: y)); p.addLine(to: CGPoint(x: rect.width, y: y))
            }
        }
        if settings.center {
            p.move(to: CGPoint(x: rect.midX, y: 0)); p.addLine(to: CGPoint(x: rect.midX, y: rect.height))
            p.move(to: CGPoint(x: 0, y: rect.midY)); p.addLine(to: CGPoint(x: rect.width, y: rect.midY))
        }
        if settings.thirds {
            for fraction in [1.0/3, 2.0/3] {
                p.move(to: CGPoint(x: rect.width * fraction, y: 0)); p.addLine(to: CGPoint(x: rect.width * fraction, y: rect.height))
                p.move(to: CGPoint(x: 0, y: rect.height * fraction)); p.addLine(to: CGPoint(x: rect.width, y: rect.height * fraction))
            }
        }
        target.path = p.cgPath; target.strokeColor = settings.color.uiColor.withAlphaComponent(settings.opacity).cgColor
        target.fillColor = nil; target.lineWidth = settings.thickness
        if !UIAccessibility.isReduceMotionEnabled {
            let animation = CABasicAnimation(keyPath: "strokeEnd"); animation.fromValue = 0; animation.toValue = 1; animation.duration = 0.25
            target.add(animation, forKey: "gridReveal")
        }
        rulerLabels.forEach { $0.removeFromSuperlayer() }; rulerLabels.removeAll()
        rulerTicks.path = nil
        if settings.rulers, let ppm = store?.project.canvas.calibratedPointsPerMM ?? store?.settings.value.calibratedPointsPerMM {
            let ticks = UIBezierPath()
            for vertical in [false, true] {
                let length = vertical ? bounds.height : bounds.width
                for mm in 0...Int(length / ppm) {
                    let position = Double(mm) * ppm, height: Double = mm % 10 == 0 ? 10 : mm % 5 == 0 ? 7 : 4
                    ticks.move(to: vertical ? CGPoint(x:0,y:position) : CGPoint(x:position,y:0))
                    ticks.addLine(to: vertical ? CGPoint(x:height,y:position) : CGPoint(x:position,y:height))
                }
                for mm in stride(from: 0, through: Int(length / ppm), by: 10) {
                    let text = CATextLayer(); text.string = "\(mm)"; text.fontSize = 9; text.contentsScale = UIScreen.main.scale
                    text.foregroundColor = settings.color.uiColor.cgColor
                    text.frame = vertical ? CGRect(x: 3, y: Double(mm) * ppm, width: 25, height: 12) : CGRect(x: Double(mm) * ppm, y: 3, width: 25, height: 12)
                    layer.addSublayer(text); rulerLabels.append(text)
                }
            }
            rulerTicks.path = ticks.cgPath; rulerTicks.strokeColor = settings.color.uiColor.cgColor; rulerTicks.lineWidth = 0.5
        }
    }
    private func drawComparison() {
        guard let store else { return }
        comparisonOriginal.isHidden = !store.comparison
        comparisonLine.isHidden = !store.comparison
        guard store.comparison, let selected = store.selected, let v = layerViews[selected.id] else { return }
        comparisonOriginal.image = store.unfilteredReference; comparisonOriginal.bounds = v.bounds
        comparisonOriginal.center = v.center; comparisonOriginal.transform = v.transform; comparisonOriginal.alpha = v.alpha
        // Convert the screen-space split mask into image-local coordinates.
        let screenRect = CGRect(x: 0, y: 0, width: bounds.width * store.comparisonPosition, height: bounds.height)
        let points = [CGPoint(x: screenRect.minX, y: 0), CGPoint(x: screenRect.maxX, y: 0),
                      CGPoint(x: screenRect.maxX, y: bounds.height), CGPoint(x: 0, y: bounds.height)]
        let p = UIBezierPath(); for (i, point) in points.enumerated() {
            let local = comparisonOriginal.convert(point, from: self)
            if i == 0 { p.move(to: local) } else { p.addLine(to: local) }
        }; p.close(); comparisonMask.path = p.cgPath
        let line = UIBezierPath(); line.move(to: CGPoint(x: screenRect.maxX, y: 0)); line.addLine(to: CGPoint(x: screenRect.maxX, y: bounds.height))
        comparisonLine.path = line.cgPath; comparisonLine.strokeColor = UIColor.white.cgColor; comparisonLine.lineWidth = 2
    }
    func snapshot() -> UIImage? {
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        refresh(); grid.removeAllAnimations(); imageGrid.removeAllAnimations()
        layerViews.values.forEach { $0.layer.removeAllAnimations() }
        hints.isHidden = true; comparisonOriginal.isHidden = true; comparisonLine.isHidden = true
        let format = UIGraphicsImageRendererFormat(); format.scale = window?.screen.scale ?? UIScreen.main.scale
        return UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in layer.render(in: context.cgContext) }
    }
    override func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
        guard let store, !store.locked else { return false }
        if g === comparisonPan { return store.comparison }
        return !store.comparison && store.selected?.locked == false
    }
    func gestureRecognizer(_ g: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        let transforms = { (r: UIGestureRecognizer) in r is UIPanGestureRecognizer || r is UIPinchGestureRecognizer || r is UIRotationGestureRecognizer }
        return transforms(g) && transforms(other) && g !== comparisonPan && other !== comparisonPan
    }
    private func track(_ g: UIGestureRecognizer) -> Bool {
        guard let store, !store.locked, store.selected?.locked == false else { gestures.removeAll(); return false }
        if g.state == .began { if gestures.isEmpty { store.beginEdit() }; gestures.insert(ObjectIdentifier(g)) }
        return true
    }
    private func finish(_ g: UIGestureRecognizer) {
        guard [.ended, .cancelled, .failed].contains(g.state), let store, !store.locked else { return }
        gestures.remove(ObjectIdentifier(g))
        if gestures.isEmpty {
            if store.settings.value.snap, let t = store.selected?.transform {
                let (snapped, x, y, angle) = GeometryMath.snap(t, canvas: bounds.size, image: store.baseImageSize)
                store.setTransform(snapped); store.guides = Point2(x: x ? 1 : 0, y: y ? 1 : 0)
                if x || y || angle { Feedback.tick(store.settings.value.haptics) }
            }
            store.commitEdit()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { [weak store] in
                guard store?.locked == false else { return }; store?.gestureLabel = nil; store?.guides = .zero
            }
        }
    }
    @objc private func pan(_ g: UIPanGestureRecognizer) {
        guard track(g), let store, var t = store.selected?.transform else { return }
        if g.state == .began || gestures.count > 1 { panOffset = t.offset }
        let delta = g.translation(in: self); g.setTranslation(.zero, in: self)
        panOffset.x += delta.x; panOffset.y += delta.y; t.offset = panOffset
        if store.settings.value.snap, gestures.count == 1 {
            let (snapped, x, y, _) = GeometryMath.snap(t, canvas: bounds.size, image: store.baseImageSize)
            let previous = store.guides
            t.offset = snapped.offset; store.guides = Point2(x: x ? 1 : 0, y: y ? 1 : 0)
            if (x && previous.x == 0) || (y && previous.y == 0) { Feedback.tick(store.settings.value.haptics) }
        }
        store.setTransform(t); finish(g)
    }
    @objc private func pinch(_ g: UIPinchGestureRecognizer) {
        guard track(g), let store, let t = store.selected?.transform else { return }
        let p = g.location(in: self)
        let new = GeometryMath.aroundPivot(t, pivot: Point2(x: p.x - bounds.midX, y: p.y - bounds.midY), scale: g.scale)
        g.scale = 1; store.setTransform(new); store.gestureLabel = "\(Int(new.scale * 100))%"; finish(g)
    }
    @objc private func rotate(_ g: UIRotationGestureRecognizer) {
        guard track(g), let store, let t = store.selected?.transform else { return }
        let p = g.location(in: self)
        let new = GeometryMath.aroundPivot(t, pivot: Point2(x: p.x - bounds.midX, y: p.y - bounds.midY), angle: g.rotation)
        g.rotation = 0; store.setTransform(new); store.gestureLabel = String(format: "%.1f°", new.rotation * 180 / .pi); finish(g)
    }
    @objc private func doubleTap(_ g: UITapGestureRecognizer) {
        guard let store, !store.locked else { return }
        switch store.settings.value.doubleTap {
        case .fit: store.transformCommand("Fit")
        case .center: store.transformCommand("Center")
        case .actual: store.transformCommand("1:1")
        case .original: store.originalVisible.toggle()
        }
    }
    @objc private func original(_ g: UILongPressGestureRecognizer) {
        guard let store, !store.locked else { return }; store.originalVisible = g.state == .began || g.state == .changed
    }
    @objc private func twoFinger(_ g: UILongPressGestureRecognizer) {
        guard let store, !store.locked else { return }
        let holding = g.state == .began || g.state == .changed
        if store.settings.value.twoFingerHold == .original { store.originalVisible = holding } else { store.temporaryHidden = holding }
    }
    @objc private func compare(_ g: UIPanGestureRecognizer) {
        guard let store, !store.locked, store.comparison else { return }
        store.comparisonPosition = max(0.02, min(0.98, g.location(in: self).x / max(1, bounds.width)))
    }
}
