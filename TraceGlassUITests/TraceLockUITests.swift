import XCTest

final class TraceLockUITests:XCTestCase {
    func testLockRejectsTouchesAndHoldUnlocks(){
        let app=XCUIApplication();app.launchArguments=["--uitesting"];app.launch()
        let lock=app.buttons["lockReference"]
        XCTAssertTrue(lock.waitForExistence(timeout:20))
        let canvas=app.otherElements["traceCanvas"]
        XCTAssertTrue(canvas.exists)
        let start=canvas.coordinate(withNormalizedOffset:CGVector(dx:0.5,dy:0.4))
        start.press(forDuration:0.05,thenDragTo:canvas.coordinate(withNormalizedOffset:CGVector(dx:0.65,dy:0.5)))
        lock.tap()
        let unlock=app.buttons["unlockReference"]
        XCTAssertTrue(unlock.waitForExistence(timeout:3))
        let value=canvas.value as? String
        // These gestures reach the canvas handlers after Lock and must all be rejected.
        canvas.tap();canvas.doubleTap();canvas.twoFingerTap()
        start.press(forDuration:0.1,thenDragTo:canvas.coordinate(withNormalizedOffset:CGVector(dx:0.3,dy:0.6)))
        canvas.pinch(withScale:1.3,velocity:1)
        canvas.rotate(0.3,withVelocity:1)
        XCTAssertEqual(canvas.value as? String,value)
        unlock.press(forDuration:1.4)
        XCTAssertTrue(lock.waitForExistence(timeout:4))
        let attachment=XCTAttachment(screenshot:app.screenshot());attachment.name="Lightbox-unlocked";attachment.lifetime = .keepAlways;add(attachment)
    }
    func testToolLayoutsAndReopen() {
        let app = XCUIApplication(); app.launchArguments = ["--uitesting"]; app.launch()
        XCTAssertTrue(app.buttons["lockReference"].waitForExistence(timeout:20))
        app.buttons["Filters"].tap()
        XCTAssertTrue(app.buttons["Prepare for Tracing"].waitForExistence(timeout:3))
        app.descendants(matching:.any)["Invert"].firstMatch.tap()
        capture(app,"Filters-portrait")
        app.buttons["Recent projects"].tap()
        let gone = XCTNSPredicateExpectation(predicate:NSPredicate(format:"exists == false"), object:app.buttons["lockReference"])
        XCTAssertEqual(XCTWaiter.wait(for:[gone],timeout:8),.completed)
        XCTAssertTrue(app.buttons["chooseImage"].isHittable)
        capture(app,"Home")
        let recent = app.buttons["recentProject"].firstMatch
        if !recent.isHittable { app.swipeUp() }
        XCTAssertTrue(recent.waitForExistence(timeout:5))
        recent.tap()
        XCTAssertTrue(app.buttons["lockReference"].waitForExistence(timeout:8))
        capture(app,"Reopened-project")
        app.buttons["Filters"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        let canvas = app.otherElements["traceCanvas"]
        let landscape = XCTNSPredicateExpectation(predicate:NSPredicate { _,_ in canvas.frame.width > canvas.frame.height },object:nil)
        XCTAssertEqual(XCTWaiter.wait(for:[landscape],timeout:8),.completed)
        XCTAssertTrue(app.buttons["lockReference"].isHittable)
        app.buttons["lockReference"].tap()
        let unlock = app.buttons["unlockReference"]
        XCTAssertTrue(unlock.waitForExistence(timeout:4))
        unlock.press(forDuration:1.4)
        XCTAssertTrue(app.buttons["lockReference"].waitForExistence(timeout:4))
        app.buttons["Filters"].tap()
        XCTAssertTrue(app.buttons["Prepare for Tracing"].waitForExistence(timeout:4))
        let layout = XCTAttachment(string:app.debugDescription)
        layout.name="Landscape-layout";layout.lifetime = .keepAlways;add(layout)
        capture(app,"Filters-landscape")
        XCUIDevice.shared.orientation = .portrait
    }

    private func capture(_ app:XCUIApplication,_ name:String) {
        // Device capture avoids application-frame cropping while the window rotates.
        let attachment = XCTAttachment(screenshot:XCUIScreen.main.screenshot())
        attachment.name=name;attachment.lifetime = .keepAlways;add(attachment)
    }

}
