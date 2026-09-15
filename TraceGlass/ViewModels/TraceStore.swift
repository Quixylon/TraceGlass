import SwiftUI
import Combine

@MainActor final class TraceStore: ObservableObject, Identifiable {
    let id = UUID()
    @Published private(set) var document: TraceDocument
    @Published private(set) var images: [UUID: UIImage] = [:]
    @Published private(set) var originals: [UUID: UIImage] = [:]
    @Published private(set) var geometryPreviews: [UUID: UIImage] = [:]
    @Published var message: String?
    @Published var processing = false
    @Published var originalVisible = false
    @Published var temporaryHidden = false
    @Published var transitionHidesReference = false
    @Published var comparison = false
    @Published var comparisonPosition: Double = 0.5
    @Published var gestureLabel: String?
    @Published var guides = Point2.zero
    @Published var freezeFrame: UIImage?
    @Published var frozenSize = CGSize.zero
    @Published var viewport = CGSize(width: 390, height: 844)
    var captureCanvas: (() -> UIImage?)?
    let storage: ProjectStorage
    let processor = ImageProcessingService()
    let display = DisplaySession()
    let settings: AppSettings
    private var rendering: Task<Void, Never>?
    private var saving: Task<Void, Never>?
    private var generation = 0
    private var renderKeys: [UUID: ReferenceLayer] = [:]
    private var observers: [AnyCancellable] = []
    var project: TraceProject { document.project }
    var locked: Bool { document.isLocked }
    var selected: ReferenceLayer? { project.selectedLayer }
    var reference: UIImage? { selected.flatMap { images[$0.id] } }
    var original: UIImage? { selected.flatMap { originals[$0.id] } }
    var unfilteredReference: UIImage? { selected.flatMap { geometryPreviews[$0.id] ?? originals[$0.id] } }
    var baseImageSize: CGSize {
        guard let image = reference else { return CGSize(width: 1000, height: 1000) }
        return CGSize(width: 1000, height: 1000 * image.size.height / max(1, image.size.width))
    }
    init(project: TraceProject, storage: ProjectStorage, settings: AppSettings) {
        document = TraceDocument(project: project); self.storage = storage; self.settings = settings
        observers.append(NotificationCenter.default.publisher(for: UIApplication.didReceiveMemoryWarningNotification)
            .receive(on: DispatchQueue.main).sink { [weak self] _ in
                guard let self else { return }
                self.releaseUnusedImages()
                Task { await self.processor.clearCaches(); await self.flush() }
            })
    }
    func load() async {
        display.begin()
        for layer in project.layers {
            do {
                let url = try await storage.assetURL(project: project.id, name: layer.assetName)
                let cg = try await Task.detached(priority: .userInitiated) {
                    try ImageImporter.downsample(Data(contentsOf: url, options: .mappedIfSafe))
                }.value
                originals[layer.id] = UIImage(cgImage: cg)
            } catch { message = TraceError.damagedProject.localizedDescription }
        }
        await renderNow()
    }
    func addImage(_ data: Data, name: String = "Reference") async {
        guard !locked, project.layers.count < 5 else { message = "A project can contain up to five references."; return }
        do {
            let cg = try await Task.detached(priority: .userInitiated) { try ImageImporter.downsample(data) }.value
            let size = try ImageImporter.sourceSize(data)
            guard !locked else { return }
            let asset = try await storage.importAsset(data, projectID: project.id)
            guard !locked else { return }
            var layer = ReferenceLayer(name: name, assetName: asset, pixelSize: size)
            let base = CGSize(width: 1000, height: 1000 * Double(cg.height) / Double(cg.width))
            layer.transform.scale = GeometryMath.fitScale(image: base, canvas: viewport) * 0.85
            originals[layer.id] = UIImage(cgImage: cg); images[layer.id] = UIImage(cgImage: cg)
            edit { p in
                p.layers.append(layer); p.selectedLayerID = layer.id
                if p.layers.count == 1 { p.name = name == "Reference" ? "New Trace" : name }
            }
            await flush()
        } catch { message = (error as? TraceError)?.localizedDescription ?? TraceError.invalidImage.localizedDescription }
    }
    func beginEdit() { guard !locked else { return }; document.begin() }
    func commitEdit() { guard !locked else { return }; document.commit(); scheduleSave() }
    func edit(_ action: (inout TraceProject) -> Void) {
        guard !locked else { return }
        let previous = project.layers
        document.begin(); document.edit(action); document.commit(); scheduleSave()
        if previous != project.layers { releaseUnusedImages(); scheduleRender() }
    }
    func update(_ action: (inout TraceProject) -> Void) {
        guard !locked else { return }; document.edit(action)
    }
    func updateLayer(_ action: (inout ReferenceLayer) -> Void, continuous: Bool = false) {
        guard !locked, let i = project.selectedIndex, !project.layers[i].locked else { return }
        let old = project.layers[i]
        if !continuous { document.begin() }
        document.edit { action(&$0.layers[i]) }
        if !continuous { document.commit(); scheduleSave() }
        let new = project.layers[i]
        if old.filters != new.filters || old.geometry != new.geometry { scheduleRender() }
    }
    func setTransform(_ value: ImageTransform) { updateLayer({ $0.transform = value }, continuous: true) }
    func lock() {
        guard !locked else { return }
        originalVisible = false; temporaryHidden = false; comparison = false
        if project.mode == .lightbox {
            guard let frame = captureCanvas?() else { message = "Wait for the image to finish opening, then lock again."; return }
            freezeFrame = frame; frozenSize = viewport
        }
        generation += 1; rendering?.cancel(); processing = false
        document.lock(); guides = .zero; gestureLabel = nil
        AppDelegate.freezeOrientation(true)
        if settings.value.maxBrightnessOnLock && project.mode == .lightbox { display.setBrightness(1) }
        Feedback.impact(settings.value.haptics, sound: settings.value.sounds)
        scheduleSave()
    }
    func unlock() {
        guard locked else { return }
        document.unlock(); freezeFrame = nil; AppDelegate.freezeOrientation(false)
        Feedback.impact(settings.value.haptics, sound: settings.value.sounds)
        scheduleRender()
    }
    func transformCommand(_ command: String) {
        guard let layer = selected, !locked else { return }
        var t = layer.transform
        switch command {
        case "Fit", "Fill": t.offset = .zero; t.rotation = 0; t.scale = GeometryMath.fitScale(image: baseImageSize, canvas: viewport, fill: command == "Fill")
        case "Center": t.offset = .zero
        case "1:1":
            let cropRatio = Double((reference?.size.width ?? 1) / max(1, original?.size.width ?? 1))
            t.scale = layer.pixelSize.x * cropRatio / Double(UIScreen.main.scale) / 1000
        case "Reset": t = ImageTransform(); t.scale = GeometryMath.fitScale(image: baseImageSize, canvas: viewport) * 0.85
        case "Reset Rotation": t.rotation = 0
        case "Mirror H": t.mirrorX.toggle()
        case "Mirror V": t.mirrorY.toggle()
        default: return
        }
        updateLayer { $0.transform = t }
        Feedback.tick(settings.value.haptics)
    }
    func physicalSize() {
        guard let calibration = project.canvas.calibratedPointsPerMM ?? settings.value.calibratedPointsPerMM else {
            message = "Calibrate with a real ruler first."; return
        }
        let scale = project.canvas.physicalWidthMM * calibration / 1000
        updateLayer { $0.transform.scale = scale; $0.transform.rotation = 0 }
        if project.canvas.physicalWidthMM * calibration > viewport.width { message = "The reference is wider than this screen. Use Tiles to trace it in sections." }
    }
    func nextTile(_ direction: Int) {
        guard let layer = selected, let ppm = project.canvas.calibratedPointsPerMM ?? settings.value.calibratedPointsPerMM else { message = "Calibrate physical size before using Tiles."; return }
        let tiles = GeometryMath.tiles(width: baseImageSize.width * layer.transform.scale,
            height: baseImageSize.height * layer.transform.scale, viewport: viewport, overlap: project.canvas.tileOverlapMM * ppm)
        let index = max(0, min(tiles.count - 1, project.canvas.tileIndex + direction))
        edit { p in p.canvas.tileIndex = index; p.canvas.tileEnabled = true; if let i = p.selectedIndex { p.layers[i].transform.offset = tiles[index] } }
        gestureLabel = "Tile \(index + 1) / \(tiles.count)"
    }
    func preset(_ preset: TracePreset) {
        updateLayer { $0.filters = preset.filters }
        if preset == .ghost { edit { $0.ar.ghost = true; $0.ar.opacity = 0.25 } }
    }
    func prepare() {
        guard !locked, let cg = original?.cgImage, let id = selected?.id else { return }
        Task {
            let filters = await processor.prepare(cg)
            guard !locked, selected?.id == id else { return }
            updateLayer { $0.filters = filters }
        }
    }
    func undo() { guard !locked else { return }; document.undo(); scheduleRender(); scheduleSave() }
    func redo() { guard !locked else { return }; document.redo(); scheduleRender(); scheduleSave() }
    func scheduleRender() {
        guard !locked else { return }
        rendering?.cancel(); generation += 1
        rendering = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(35))
            guard !Task.isCancelled, let self else { return }; await self.renderNow()
        }
    }
    private func renderNow() async {
        let ticket = generation
        let snapshot = project
        processing = true
        defer { if ticket == generation { processing = false } }
        for layer in snapshot.layers {
            guard !Task.isCancelled, !locked, layer.visible || layer.id == snapshot.selectedLayerID else { continue }
            if let cached = renderKeys[layer.id], cached.filters == layer.filters, cached.geometry == layer.geometry, images[layer.id] != nil { continue }
            do {
                if originals[layer.id] == nil {
                    let url = try await storage.assetURL(project: snapshot.id, name: layer.assetName)
                    let cg = try await Task.detached(priority: .userInitiated) { try ImageImporter.downsample(Data(contentsOf: url, options: .mappedIfSafe)) }.value
                    guard !Task.isCancelled, !locked, ticket == generation else { return }
                    originals[layer.id] = UIImage(cgImage: cg)
                }
                guard let source = originals[layer.id]?.cgImage else { continue }
                if layer.geometry != ImageGeometry(), renderKeys[layer.id]?.geometry != layer.geometry {
                    let base = try await processor.render(source, settings: FilterSettings(), geometry: layer.geometry)
                    guard !Task.isCancelled, !locked, ticket == generation else { return }
                    geometryPreviews[layer.id] = UIImage(cgImage: base)
                } else if layer.geometry == ImageGeometry() { geometryPreviews.removeValue(forKey: layer.id) }
                let result = try await processor.render(source, settings: layer.filters, geometry: layer.geometry)
                guard !Task.isCancelled, !locked, ticket == generation else { return }
                images[layer.id] = UIImage(cgImage: result)
                renderKeys[layer.id] = layer
            } catch { if !Task.isCancelled { message = TraceError.rendering.localizedDescription } }
        }
    }
    private func releaseUnusedImages() {
        // Undo keeps asset identifiers on disk, never dozens of decoded photo textures.
        let retained = Set(project.layers.filter { $0.visible || $0.id == project.selectedLayerID }.map(\.id))
        for id in Array(images.keys) where !retained.contains(id) { images.removeValue(forKey: id); renderKeys.removeValue(forKey: id) }
        for id in Array(originals.keys) where !retained.contains(id) { originals.removeValue(forKey: id) }
        for id in Array(geometryPreviews.keys) where !retained.contains(id) { geometryPreviews.removeValue(forKey: id) }
    }
    private func scheduleSave() {
        saving?.cancel()
        saving = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, let self else { return }; await self.flush()
        }
    }
    func flush() async {
        let snapshot = project
        do {
            try await storage.save(snapshot)
            if let image = reference {
                let f = UIGraphicsImageRendererFormat(); f.scale = 1
                let size = CGSize(width: 360, height: 360 * image.size.height / max(image.size.width, 1))
                let thumbnail = UIGraphicsImageRenderer(size: size, format: f).image { _ in image.draw(in: CGRect(origin: .zero, size: size)) }
                if let data = thumbnail.jpegData(compressionQuality: 0.75) { try await storage.saveThumbnail(data, id: snapshot.id) }
            }
        } catch { message = TraceError.storage.localizedDescription }
    }
    func close() async {
        saving?.cancel(); rendering?.cancel()
        await flush(); display.end(); AppDelegate.freezeOrientation(false)
    }
}
