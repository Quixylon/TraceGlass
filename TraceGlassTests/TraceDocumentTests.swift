import XCTest
@testable import TraceGlass

final class TraceDocumentTests:XCTestCase {
    private func document()->TraceDocument {
        var project=TraceProject()
        let layer=ReferenceLayer(assetName:"test.image",pixelSize:Point2(x:1000,y:1000))
        project.layers=[layer];project.selectedLayerID=layer.id
        return TraceDocument(project:project)
    }
    func testLockRejectsAllEditRoutesIncludingLateGestures(){
        var d=document();d.begin();d.edit{$0.layers[0].transform.offset.x=123};d.commit();d.lock()
        let frozen=d.project
        for fingerCount in 1...3 {
            for _ in 0..<100 {
                d.begin()
                XCTAssertFalse(d.edit { p in
                    p.layers[0].transform.offset.x+=Double(fingerCount)
                    p.layers[0].transform.scale*=1.01;p.layers[0].transform.rotation+=0.2
                    p.layers[0].filters.invert.toggle();p.layers[0].opacity=0.1
                    p.canvas.background = .black;p.ar.opacity=0.1;p.mode = .paper
                })
                d.commit();d.undo();d.redo()
            }
        }
        XCTAssertEqual(d.project,frozen)
        d.unlock();d.begin();XCTAssertTrue(d.edit{$0.layers[0].transform.offset.y=55});d.commit()
        XCTAssertEqual(d.project.layers[0].transform.offset.y,55)
    }
    func testOneHistoryEntryPerGesture(){
        var d=document();d.begin()
        for n in 0..<120{d.edit{$0.layers[0].transform.offset.x=Double(n)}}
        d.commit();XCTAssertEqual(d.undoStack.count,1)
        d.undo();XCTAssertEqual(d.project.layers[0].transform.offset.x,0)
        d.redo();XCTAssertEqual(d.project.layers[0].transform.offset.x,119)
    }
    func testNewEditClearsRedo(){var d=document();d.begin();d.edit{$0.name="One"};d.commit();d.undo();d.begin();d.edit{$0.name="Two"};d.commit();XCTAssertTrue(d.redoStack.isEmpty)}
    func testNonFiniteTransformRejected(){var d=document();d.edit{$0.layers[0].transform.scale = .nan;$0.layers[0].transform.offset.x = .infinity};XCTAssertEqual(d.project.layers[0].transform.scale,1);XCTAssertEqual(d.project.layers[0].transform.offset,.zero)}
    func testGeometryUndo(){var d=document();let old=d.project.layers[0].geometry;d.begin();d.edit{$0.layers[0].geometry.crop=[0.1,0.1,0.8,0.8]};d.commit();d.undo();XCTAssertEqual(d.project.layers[0].geometry,old)}
    func testProjectRoundTrip()throws {
        var d=document();d.edit{p in p.canvas.grid.density = .custom;p.canvas.grid.divisions=17;p.canvas.calibratedPointsPerMM=6.12;p.ar.placement.rotation=0.8;p.layers[0].filters.thresholdEnabled=true;p.layers[0].transform.mirrorX=true}
        let data=try JSONEncoder().encode(d.project)
        XCTAssertEqual(try JSONDecoder().decode(TraceProject.self,from:data),d.project)
    }
}
