import XCTest
import UIKit
@testable import TraceGlass

final class StorageAndFilterTests:XCTestCase {
    func testDiskRoundTripAndAssets()async throws {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer{try? FileManager.default.removeItem(at:root)}
        let storage=ProjectStorage(root:root);var project=TraceProject()
        project.canvas.calibratedPointsPerMM=6.5;project.canvas.grid.thickness=1.25
        let data=Data([1,2,3,4]);let name=try await storage.importAsset(data,projectID:project.id)
        project.layers=[ReferenceLayer(assetName:name,pixelSize:Point2(x:1,y:1))]
        try await storage.save(project)
        let restored=try await ProjectStorage(root:root).recent()
        XCTAssertEqual(restored,[project])
        let url=try await storage.assetURL(project:project.id,name:name)
        XCTAssertEqual(try Data(contentsOf:url),data)
        do{_ = try await storage.assetURL(project:project.id,name:"../other");XCTFail("Traversal accepted")}catch{}
    }
    func testInvalidImage(){XCTAssertThrowsError(try ImageImporter.downsample(Data("not an image".utf8)))}
    @MainActor func testFilterChainAndAlpha()async throws {
        let format=UIGraphicsImageRendererFormat();format.opaque=false;format.scale=1
        let source=UIGraphicsImageRenderer(size:CGSize(width:32,height:32),format:format).image{ctx in
            UIColor.black.setFill();ctx.fill(CGRect(x:8,y:8,width:16,height:16))
            UIColor.black.withAlphaComponent(0.5).setFill();ctx.fill(CGRect(x:2,y:2,width:4,height:4))
        }
        let processor=ImageProcessingService();let cg=try XCTUnwrap(source.cgImage)
        for preset in TracePreset.allCases {
            let result=try await processor.render(cg,settings:preset.filters)
            XCTAssertEqual(result.width,32);XCTAssertEqual(result.height,32)
            var bytes=[UInt8](repeating:0,count:32*32*4)
            let context=CGContext(data:&bytes,width:32,height:32,bitsPerComponent:8,bytesPerRow:128,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(result,in:CGRect(x:0,y:0,width:32,height:32))
            XCTAssertEqual(bytes[3],0,"Transparency lost for \(preset.rawValue)")
            // UIImage/Core Graphics uses top-left image coordinates here; test either flipped row.
            let a = bytes[(3 * 32 + 3) * 4 + 3]
            let b = bytes[(28 * 32 + 3) * 4 + 3]
            XCTAssertTrue(abs(Int(max(a,b))-128) <= 2,"Partial alpha changed for \(preset.rawValue)")
        }
    }
}
