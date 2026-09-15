import XCTest
@testable import TraceGlass

final class GeometryTests:XCTestCase {
    func testPivotStaysFixed(){
        let t=ImageTransform(offset:Point2(x:30,y:-20),scale:1.2,rotation:0.4)
        let pivot=Point2(x:70,y:40)
        let next=GeometryMath.aroundPivot(t,pivot:pivot,scale:2,angle:.pi/2)
        XCTAssertEqual(next.offset.x,190,accuracy:0.0001)
        XCTAssertEqual(next.offset.y,-40,accuracy:0.0001)
        XCTAssertEqual(next.scale,2.4,accuracy:0.0001)
    }
    func testHomographyHitsFourCorners()throws {
        let corners=[CGPoint(x:12,y:20),CGPoint(x:320,y:45),CGPoint(x:290,y:460),CGPoint(x:40,y:440)]
        let h=try XCTUnwrap(GeometryMath.homography(to:corners))
        for (i,p) in [CGPoint.zero,CGPoint(x:1,y:0),CGPoint(x:1,y:1),CGPoint(x:0,y:1)].enumerated(){
            let w=h[6]*p.x+h[7]*p.y+1
            XCTAssertEqual((h[0]*p.x+h[1]*p.y+h[2])/w,corners[i].x,accuracy:0.000001)
            XCTAssertEqual((h[3]*p.x+h[4]*p.y+h[5])/w,corners[i].y,accuracy:0.000001)
        }
    }
    func testDegenerateHomographyRejected(){XCTAssertNil(GeometryMath.homography(to:Array(repeating:.zero,count:4)))}
    func testCrossedQuadRejected(){
        XCTAssertNil(GeometryMath.homography(to:[CGPoint(x:0,y:0),CGPoint(x:1,y:1),CGPoint(x:1,y:0),CGPoint(x:0,y:1)]))
    }
    func testTilesCoverFullImage(){
        let tiles=GeometryMath.tiles(width:800,height:1200,viewport:CGSize(width:400,height:700),overlap:50)
        XCTAssertEqual(tiles.count,6)
        XCTAssertEqual(tiles.first,Point2(x:200,y:250))
        XCTAssertEqual(tiles.last,Point2(x:-200,y:-250))
    }
    func testSmoothingRejectsSingleOutlier(){
        var s=PaperSmoother();let p=[Point2(x:0.1,y:0.1),Point2(x:0.5,y:0.1),Point2(x:0.5,y:0.5),Point2(x:0.1,y:0.5)]
        _=s.update(PaperEstimate(corners:p,confidence:0.9,timestamp:1))
        let shifted=p.map{Point2(x:$0.x+0.3,y:$0.y+0.3)}
        _=s.update(PaperEstimate(corners:shifted,confidence:0.9,timestamp:1.03))
        XCTAssertEqual(s.current?.corners,p)
    }
}
