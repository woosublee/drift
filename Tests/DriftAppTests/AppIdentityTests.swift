import XCTest
@testable import DriftApp

final class AppIdentityTests: XCTestCase {
    func testLoadsDevelopmentDisplayNameFromBundleMetadata() {
        let identity = AppIdentity.load(from: ["CFBundleDisplayName": "Drift Dev"])

        XCTAssertEqual(identity.displayName, "Drift Dev")
        XCTAssertEqual(identity.quitTitle, "Quit Drift Dev")
    }

    func testLoadsProductionDisplayNameFromBundleMetadata() {
        let identity = AppIdentity.load(from: ["CFBundleDisplayName": "Drift"])

        XCTAssertEqual(identity.displayName, "Drift")
        XCTAssertEqual(identity.quitTitle, "Quit Drift")
    }

    func testFallsBackToDriftWhenDisplayNameIsMissingOrBlank() {
        XCTAssertEqual(AppIdentity.load(from: [:]).displayName, "Drift")
        XCTAssertEqual(AppIdentity.load(from: ["CFBundleDisplayName": "   "]).displayName, "Drift")
    }
}
