import XCTest

final class FlexTrackSampleUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testPrimaryWorkflowIsDiscoverable() throws {
    let app = XCUIApplication()
    app.launch()

    XCTAssertTrue(app.navigationBars["Signal board"].waitForExistence(timeout: 5))
    for tab in ["Events", "Queue", "Logs", "Settings"] {
      let button = app.tabBars.buttons[tab]
      XCTAssertTrue(button.exists)
      button.tap()
      XCTAssertTrue(app.navigationBars[tab].waitForExistence(timeout: 2))
    }
  }
}
