import Foundation

struct Point2: Codable, Equatable, Sendable {
    var x: Double = 0
    var y: Double = 0
    static let zero = Point2()
    var isFinite: Bool { x.isFinite && y.isFinite }
}

struct ImageTransform: Codable, Equatable, Sendable {
    var offset = Point2.zero
    var scale: Double = 1
    var rotation: Double = 0
    var mirrorX = false
    var mirrorY = false
    func sanitized() -> Self {
        var result = self
        if !result.offset.isFinite { result.offset = .zero }
        result.scale = scale.isFinite ? min(100, max(0.01, scale)) : 1
        result.rotation = rotation.isFinite ? rotation.remainder(dividingBy: .pi * 2) : 0
        return result
    }
}

enum EdgeMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case original = "Original", edges = "Edges", clean = "Clean Lines"
    case black = "Black Lines", white = "White Lines", inverted = "Inverted Lines"
    var id: String { rawValue }
}

struct FilterSettings: Codable, Equatable, Sendable {
    var brightness: Double = 0
    var contrast: Double = 1
    var exposure: Double = 0
    var saturation: Double = 1
    var blackPoint: Double = 0
    var highlights: Double = 1
    var shadows: Double = 0
    var sharpness: Double = 0
    var grayscale = false
    var invert = false
    var thresholdEnabled = false
    var threshold: Double = 0.5
    var edgeMode: EdgeMode = .original
    var edgeStrength: Double = 2
    var cleanup: Double = 0
}

struct RGBA: Codable, Equatable, Sendable {
    var r: Double
    var g: Double
    var b: Double
    var a: Double = 1
    static let white = RGBA(r: 1, g: 1, b: 1)
    static let black = RGBA(r: 0, g: 0, b: 0)
    static let mint = RGBA(r: 0.50, g: 0.94, b: 0.83)
    static let presets: [(String, RGBA)] = [
        ("White", .white), ("Black", .black), ("Gray", RGBA(r: 0.5, g: 0.5, b: 0.5)),
        ("Warm", RGBA(r: 1, g: 0.94, b: 0.83)), ("Cold", RGBA(r: 0.86, g: 0.94, b: 1)),
        ("Red", RGBA(r: 0.90, g: 0.22, b: 0.22)), ("Green", RGBA(r: 0.25, g: 0.85, b: 0.45)),
        ("Blue", RGBA(r: 0.23, g: 0.48, b: 0.96))
    ]
}

enum GridDensity: String, Codable, CaseIterable, Identifiable, Sendable {
    case off = "Off", large = "Large", medium = "Medium", fine = "Fine", custom = "Custom"
    var id: String { rawValue }
}
enum GridSpace: String, Codable, CaseIterable, Identifiable, Sendable {
    case screen = "Screen", image = "Image"
    var id: String { rawValue }
}
struct GridSettings: Codable, Equatable, Sendable {
    var density: GridDensity = .off
    var space: GridSpace = .screen
    var divisions: Int = 8
    var opacity: Double = 0.25
    var thickness: Double = 0.5
    var color = RGBA.black
    var center = false
    var thirds = false
    var rulers = false
    var count: Int {
        switch density { case .off: return 0; case .large: return 4; case .medium: return 8
        case .fine: return 16; case .custom: return max(2, min(40, divisions)) }
    }
}

enum PaperPreset: String, Codable, CaseIterable, Identifiable, Sendable {
    case a5 = "A5", a4 = "A4", a3 = "A3", letter = "Letter", custom = "Custom"
    var id: String { rawValue }
    var size: Point2 {
        switch self { case .a5: return Point2(x: 148, y: 210); case .a4: return Point2(x: 210, y: 297)
        case .a3: return Point2(x: 297, y: 420); case .letter: return Point2(x: 215.9, y: 279.4)
        case .custom: return Point2(x: 150, y: 200) }
    }
}
struct CanvasSettings: Codable, Equatable, Sendable {
    var background = RGBA.white
    var grid = GridSettings()
    var calibratedPointsPerMM: Double? = nil
    var paper: PaperPreset = .a4
    var customPaper = Point2(x: 150, y: 200)
    var physicalWidthMM: Double = 150
    var tileIndex: Int = 0
    var tileOverlapMM: Double = 8
    var tileEnabled = false
}

// Coordinates are normalized in the upright source image, with origin at top left.
struct ImageGeometry: Codable, Equatable, Sendable {
    var corners: [Point2]? = nil
    var crop: [Double]? = nil // x, y, width, height after perspective correction
}
struct ReferenceLayer: Codable, Equatable, Identifiable, Sendable {
    var id = UUID()
    var name = "Reference"
    var assetName: String
    var pixelSize: Point2
    var transform = ImageTransform()
    var filters = FilterSettings()
    var geometry = ImageGeometry()
    var opacity: Double = 1
    var visible = true
    var locked = false
}

enum TraceMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case lightbox = "Lightbox", paper = "Paper Track", world = "World Anchor"
    var id: String { rawValue }
}
struct ARSettings: Codable, Equatable, Sendable {
    var opacity: Double = 0.5
    var ghost = false
    var projector = false
    var intensity: Double = 0.3
    var overhead = false
    var occlusion = false
    var referenceVisible = true
    var placement = ImageTransform()
    var worldWidth: Double = 0.21
}

struct TraceProject: Codable, Equatable, Identifiable, Sendable {
    var schemaVersion = 1
    var id = UUID()
    var name = "Untitled Trace"
    var createdAt = Date()
    var modifiedAt = Date()
    var layers: [ReferenceLayer] = []
    var selectedLayerID: UUID? = nil
    var canvas = CanvasSettings()
    var ar = ARSettings()
    var mode: TraceMode = .lightbox
    var selectedIndex: Int? { layers.firstIndex { $0.id == selectedLayerID } }
    var selectedLayer: ReferenceLayer? { selectedIndex.map { layers[$0] } }
}

// Every document mutation goes through this gate, including delayed UI callbacks.
// Lock is session state, deliberately never restored from disk.
struct TraceDocument {
    private(set) var project: TraceProject
    private(set) var isLocked = false
    private(set) var undoStack: [TraceProject] = []
    private(set) var redoStack: [TraceProject] = []
    private var transaction: TraceProject?
    init(project: TraceProject) { self.project = project }
    mutating func begin() { guard !isLocked, transaction == nil else { return }; transaction = project }
    @discardableResult mutating func edit(_ action: (inout TraceProject) -> Void) -> Bool {
        guard !isLocked else { return false }
        action(&project)
        func bounded(_ value: Double, _ low: Double, _ high: Double, _ fallback: Double) -> Double {
            value.isFinite ? min(high, max(low, value)) : fallback
        }
        project.canvas.physicalWidthMM = bounded(project.canvas.physicalWidthMM, 1, 3000, 150)
        project.canvas.customPaper.x = bounded(project.canvas.customPaper.x, 1, 10000, 150)
        project.canvas.customPaper.y = bounded(project.canvas.customPaper.y, 1, 10000, 200)
        project.ar.opacity = bounded(project.ar.opacity, 0.05, 1, 0.5)
        project.ar.worldWidth = bounded(project.ar.worldWidth, 0.01, 10, 0.21)
        project.ar.placement = project.ar.placement.sanitized()
        for i in project.layers.indices {
            project.layers[i].transform = project.layers[i].transform.sanitized()
            let value = project.layers[i].opacity
            project.layers[i].opacity = value.isFinite ? min(1, max(0.05, value)) : 1
        }
        return true
    }
    mutating func commit() {
        guard !isLocked, let previous = transaction else { return }
        transaction = nil
        guard previous != project else { return }
        undoStack.append(previous)
        if undoStack.count > 60 { undoStack.removeFirst() }
        redoStack.removeAll()
        project.modifiedAt = Date()
    }
    mutating func lock() { commit(); isLocked = true }
    mutating func unlock() { isLocked = false }
    mutating func undo() {
        guard !isLocked, let previous = undoStack.popLast() else { return }
        transaction = nil; redoStack.append(project); project = previous; project.modifiedAt = Date()
    }
    mutating func redo() {
        guard !isLocked, let next = redoStack.popLast() else { return }
        transaction = nil; undoStack.append(project); project = next; project.modifiedAt = Date()
    }
}
