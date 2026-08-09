import XCTest
@testable import DriftApp

@MainActor
final class SparkleUpdaterAdapterTests: XCTestCase {
    func testSparkleFactoryConformsToUpdaterFactoryProtocol() {
        let factory: UpdaterControllerMaking = SparkleUpdaterControllerFactory()

        XCTAssertNotNil(factory as AnyObject)
    }
}
