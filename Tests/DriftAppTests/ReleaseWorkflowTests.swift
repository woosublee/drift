import Foundation
import XCTest

final class ReleaseWorkflowTests: XCTestCase {
    // Break caught: automatic tag publication or manual publication can be enabled without an explicit false-by-default input.
    func testWorkflowSupportsTagPublishAndManualDryRun() throws {
        let workflow = try sourceWorkflow()

        XCTAssertTrue(workflow.contains("push:"))
        XCTAssertTrue(workflow.contains("tags:"))
        XCTAssertTrue(workflow.contains("- 'v*'"))
        XCTAssertTrue(workflow.contains("workflow_dispatch:"))
        XCTAssertTrue(workflow.contains("publish:"))
        XCTAssertTrue(workflow.contains("default: false"))
        XCTAssertTrue(workflow.contains("cancel-in-progress: false"))
    }

    // Break caught: a branch-dispatched run can publish or use bespoke release behavior instead of the existing verified scripts.
    func testWorkflowUsesCanonicalSecretsSharedScriptsAndImmutableManualPublishGate() throws {
        let workflow = try sourceWorkflow()

        for secret in ["DRIFT_CERTIFICATE_BASE64", "DRIFT_CERTIFICATE_PASSWORD", "SPARKLE_PRIVATE_KEY"] {
            XCTAssertTrue(workflow.contains("secrets.\(secret)"))
        }
        XCTAssertTrue(workflow.contains("scripts/check-release-monotonic.sh"))
        XCTAssertTrue(workflow.contains("make verify-release-artifacts"))
        XCTAssertTrue(workflow.contains("scripts/publish-github-release.sh"))
        XCTAssertTrue(workflow.contains("scripts/verify-published-release.sh"))
        XCTAssertTrue(workflow.contains("[[ \"$GITHUB_REF\" == \"refs/tags/$RELEASE_TAG\" ]]"))
        XCTAssertTrue(workflow.contains("[[ \"$(git rev-list -n 1 \"$RELEASE_TAG\")\" == \"$GITHUB_SHA\" ]]"))
        XCTAssertTrue(workflow.contains("if: steps.release.outputs.publish_requested == 'true'"))
        XCTAssertFalse(workflow.contains("set -x"))
        XCTAssertFalse(workflow.contains("--clobber"))
    }

    // Break caught: a temporary signing identity persists after a failed release job or the runner's keychain defaults are left modified.
    func testWorkflowAlwaysCleansTemporaryCertificateAndKeychain() throws {
        let workflow = try sourceWorkflow()

        XCTAssertTrue(workflow.contains("if: always()"))
        XCTAssertTrue(workflow.contains("security default-keychain -d user -s \"$ORIGINAL_DEFAULT_KEYCHAIN\""))
        XCTAssertTrue(workflow.contains("security list-keychains -d user -s $ORIGINAL_KEYCHAINS"))
        XCTAssertTrue(workflow.contains("KEYCHAIN_PASSWORD=\"$(openssl rand -base64 32)\""))
        XCTAssertTrue(workflow.contains("::add-mask::$KEYCHAIN_PASSWORD"))
        XCTAssertTrue(workflow.contains("security delete-keychain"))
        XCTAssertTrue(workflow.contains("rm -f \"$RUNNER_TEMP/drift-certificate.p12\""))
    }

    private func sourceWorkflow() throws -> String {
        let root = ProcessTestSupport.sourceRoot(filePath: #filePath)
        return try String(contentsOf: root.appendingPathComponent(".github/workflows/release.yml"))
    }
}
