import Foundation
import UIKit
import ImageIO

enum TraceError: LocalizedError {
    case invalidImage, tooLarge, storage, damagedProject, cameraUnavailable, cameraDenied, rendering
    var errorDescription: String? {
        switch self {
        case .invalidImage: return "This file could not be opened. Choose a PNG, JPEG, HEIC or PDF."
        case .tooLarge: return "This file is too large. Try a smaller copy."
        case .storage: return "Your changes could not be saved. Check the free space on your iPhone."
        case .damagedProject: return "This project could not be opened. Your other projects are safe."
        case .cameraUnavailable: return "The camera is unavailable. You can continue in Lightbox."
        case .cameraDenied: return "Allow Camera in Settings to use AR or take a photo."
        case .rendering: return "This edit could not be displayed. Try resetting the image tools."
        }
    }
}

actor ProjectStorage {
    let root: URL
    init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TraceGlass", isDirectory: true)
    }
    private func directory(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString, isDirectory: true) }
    func save(_ project: TraceProject) throws {
        let dir = directory(project.id)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(project)
            try data.write(to: dir.appendingPathComponent("project.json"), options: [.atomic, .completeFileProtectionUnlessOpen])
        } catch { throw TraceError.storage }
    }
    func importAsset(_ data: Data, projectID: UUID) throws -> String {
        let dir = directory(projectID)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = UUID().uuidString + ".image"
        try data.write(to: dir.appendingPathComponent(name), options: [.atomic, .completeFileProtectionUnlessOpen])
        return name
    }
    func assetURL(project: UUID, name: String) throws -> URL {
        guard name == URL(fileURLWithPath: name).lastPathComponent, !name.hasPrefix(".") else { throw TraceError.damagedProject }
        return directory(project).appendingPathComponent(name)
    }
    func recent() throws -> [TraceProject] {
        guard FileManager.default.fileExists(atPath: root.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .compactMap { url -> TraceProject? in
                guard let data = try? Data(contentsOf: url.appendingPathComponent("project.json")),
                      let p = try? JSONDecoder().decode(TraceProject.self, from: data), p.schemaVersion == 1 else { return nil }
                return p
            }.sorted { $0.modifiedAt > $1.modifiedAt }
    }
    func remove(_ project: TraceProject) throws { try FileManager.default.removeItem(at: directory(project.id)) }
    func saveThumbnail(_ data: Data, id: UUID) throws {
        try data.write(to: directory(id).appendingPathComponent("preview.jpg"), options: .atomic)
    }
    func thumbnail(id: UUID) -> Data? { try? Data(contentsOf: directory(id).appendingPathComponent("preview.jpg")) }
}

enum ImageImporter {
    static let maxFileBytes = 180 * 1024 * 1024
    static func downsample(_ data: Data, maxDimension: Int = 2560) throws -> CGImage {
        guard data.count <= maxFileBytes else { throw TraceError.tooLarge }
        guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension
              ] as CFDictionary) else { throw TraceError.invalidImage }
        return image
    }
    static func sourceSize(_ data: Data) throws -> Point2 {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = properties[kCGImagePropertyPixelHeight] as? NSNumber else { throw TraceError.invalidImage }
        let orientation = (properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        return [5,6,7,8].contains(orientation) ? Point2(x: height.doubleValue, y: width.doubleValue)
            : Point2(x: width.doubleValue, y: height.doubleValue)
    }
}
