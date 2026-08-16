import Sparkle
import XCTest
@testable import DriftApp

@MainActor
final class SparkleUpdaterAdapterTests: XCTestCase {
    func testSparkleFactoryConformsToUpdaterFactoryProtocol() {
        let factory: UpdaterControllerMaking = SparkleUpdaterControllerFactory()

        XCTAssertNotNil(factory as AnyObject)
    }

    func testNoUpdateAbortIsNotAReportableFailure() {
        let error = NSError(
            domain: SUSparkleErrorDomain,
            code: Int(SUError.noUpdateError.rawValue)
        )

        XCTAssertFalse(SparkleUpdateAbortClassifier.shouldReport(error))
    }

    func testMatchingCodeFromAnotherDomainRemainsAReportableFailure() {
        let error = NSError(
            domain: "AnotherUpdater",
            code: Int(SUError.noUpdateError.rawValue)
        )

        XCTAssertTrue(SparkleUpdateAbortClassifier.shouldReport(error))
    }

    func testOtherSparkleAbortRemainsAReportableFailure() {
        let error = NSError(
            domain: SUSparkleErrorDomain,
            code: Int(SUError.appcastError.rawValue)
        )

        XCTAssertTrue(SparkleUpdateAbortClassifier.shouldReport(error))
    }

    func testDelegateOnlyPublishesReportableAbortErrors() {
        var reportedErrors: [NSError] = []
        let delegate = SparkleUpdaterDelegate { error in
            reportedErrors.append(error as NSError)
        }
        let noUpdate = NSError(
            domain: SUSparkleErrorDomain,
            code: Int(SUError.noUpdateError.rawValue)
        )
        let appcastFailure = NSError(
            domain: SUSparkleErrorDomain,
            code: Int(SUError.appcastError.rawValue)
        )

        delegate.handleAbort(noUpdate)
        delegate.handleAbort(appcastFailure)

        XCTAssertEqual(reportedErrors, [appcastFailure])
    }
}
