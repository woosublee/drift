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

    // Break caught: publication refers to release notes that do not exist, making a tagged publish fail after artifact verification.
    func testWorkflowNotesFileExistsAndIsNonEmpty() throws {
        let workflow = try sourceWorkflow()
        let pattern = #"--notes\s+([^\s]+)"#
        let range = NSRange(workflow.startIndex..., in: workflow)
        let expression = try NSRegularExpression(pattern: pattern)
        let match = try XCTUnwrap(expression.firstMatch(in: workflow, range: range))
        let notesPathRange = try XCTUnwrap(Range(match.range(at: 1), in: workflow))
        let notesURL = sourceRoot().appendingPathComponent(String(workflow[notesPathRange]))

        XCTAssertTrue(FileManager.default.fileExists(atPath: notesURL.path))
        let notes = try String(contentsOf: notesURL, encoding: .utf8)
        XCTAssertFalse(notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    // Break caught: monotonicity and publication scripts invoke gh, which exits unauthenticated in Actions without GH_TOKEN.
    func testWorkflowAuthenticatesGitHubCLIWithWorkflowToken() throws {
        let workflow = try sourceWorkflow()

        XCTAssertTrue(workflow.contains("GH_TOKEN: ${{ github.token }}"))
    }

    // Break caught: GitHub accepts zsh only as a custom shell format string containing the script placeholder.
    func testWorkflowUsesRunnableZshFormatString() throws {
        let workflow = try sourceWorkflow()
        let invalidPattern = #"(?m)^\s*shell:\s*zsh\s*$"#
        let invalidExpression = try NSRegularExpression(pattern: invalidPattern)
        let range = NSRange(workflow.startIndex..., in: workflow)

        XCTAssertNil(invalidExpression.firstMatch(in: workflow, range: range))
        XCTAssertTrue(workflow.contains("shell: zsh {0}"))
    }

    // Break caught: job-level env cannot resolve the runner context, so GitHub rejects the workflow before any step starts.
    func testWorkflowInitializesTemporaryKeychainPathAtRuntime() throws {
        let workflow = try sourceWorkflow()

        XCTAssertFalse(workflow.contains("KEYCHAIN_PATH: ${{ runner.temp }}"))
        XCTAssertTrue(
            workflow.contains("printf 'KEYCHAIN_PATH=%s\\n' \"$KEYCHAIN_PATH\" >> \"$GITHUB_ENV\"")
        )
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
        return try String(contentsOf: sourceRoot().appendingPathComponent(".github/workflows/release.yml"))
    }

    private func sourceRoot() -> URL {
        ProcessTestSupport.sourceRoot(filePath: #filePath)
    }
}
