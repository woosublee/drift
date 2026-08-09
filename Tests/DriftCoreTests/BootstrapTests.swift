import XCTest
@testable import DriftCore

final class BootstrapTests: XCTestCase {
    func testModuleIdentifierIsStable() {
        XCTAssertEqual(DriftCore.moduleIdentifier, "com.woosublee.Drift.core")
    }
}
