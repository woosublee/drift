import XCTest

final class AppBundleTests: XCTestCase {
    func testInfoPlistDeclaresProductionMenuBarIdentity() throws {
        let plist = try sourceInfoPlist()

        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "com.woosublee.drift")
        XCTAssertEqual(plist["CFBundleName"] as? String, "Drift")
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "Drift")
        XCTAssertEqual(plist["LSUIElement"] as? Bool, true)
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "13.0")
        XCTAssertEqual(
            plist["NSAccessibilityAccessDescription"] as? String,
            "Drift needs Accessibility access to move the pointer."
        )
    }

    func testProductionInfoPlistContainsValidSparklePublicKeyWithoutFeed() throws {
        let plist = try sourceInfoPlist()
        let publicKey = try XCTUnwrap(plist["SUPublicEDKey"] as? String)

        XCTAssertEqual(publicKey.count, 44)
        XCTAssertEqual(Data(base64Encoded: publicKey)?.count, 32)
        XCTAssertNil(plist["SUFeedURL"])
    }

    func testSourceInfoPlistContainsNoSparkleFeed() throws {
        let plist = try sourceInfoPlist()

        XCTAssertNil(plist["SUFeedURL"])
    }

    func testSourceInfoPlistDoesNotRequestUnneededPrivacyPermissions() throws {
        let plist = try sourceInfoPlist()

        [
            "NSAppleEventsUsageDescription",
            "NSCameraUsageDescription",
            "NSMicrophoneUsageDescription",
            "NSScreenCaptureUsageDescription"
        ].forEach { key in
            XCTAssertNil(plist[key], "\(key) must not be declared")
        }
    }

    func testPackageDoesNotLinkStoreKit() throws {
        let package = try String(contentsOf: sourceRoot().appendingPathComponent("Package.swift"))

        XCTAssertFalse(package.contains("StoreKit"))
    }

    private func sourceInfoPlist() throws -> [String: Any] {
        let data = try Data(contentsOf: sourceRoot().appendingPathComponent("Info.plist"))
        return try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )
    }

    private func sourceRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
