import Foundation
import XCTest

final class AppStartupVerificationTests: XCTestCase {
    // Break caught: static codesign checks pass even when dyld terminates the app
    // immediately because Sparkle cannot be loaded under Library Validation.
    func testVerifierRejectsAppThatExitsDuringStartupAndReportsItsDiagnostics() throws {
        let fixture = try makeFixture(executable: """
        #!/bin/zsh
        print -u2 -r -- 'dyld: Library not loaded: @rpath/Sparkle.framework/Versions/B/Sparkle'
        exit 134
        """)

        let result = try runVerifier(for: fixture)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("exited during startup"), result.output)
        XCTAssertTrue(result.output.contains("Library not loaded"), result.output)
    }

    func testVerifierAcceptsAppThatRemainsAliveThroughGracePeriod() throws {
        let fixture = try makeFixture(executable: """
        #!/bin/zsh
        trap 'exit 0' TERM INT
        while true; do sleep 1; done
        """)

        let result = try runVerifier(for: fixture)

        XCTAssertEqual(result.status, 0, result.output)
    }

    func testVerifierRejectsInvalidGracePeriodsWithUsageError() throws {
        let fixture = try makeFixture(executable: """
        #!/bin/zsh
        exit 0
        """)

        for gracePeriod in ["not-a-number", "0", "-1", "nan", "inf"] {
            let result = try runVerifier(for: fixture, graceSeconds: gracePeriod)

            XCTAssertEqual(result.status, 2, "grace period: \(gracePeriod)\n\(result.output)")
            XCTAssertTrue(
                result.output.contains("STARTUP_GRACE_SECONDS must be a finite positive number"),
                "grace period: \(gracePeriod)\n\(result.output)"
            )
        }
    }

    private var sourceRoot: URL {
        ProcessTestSupport.sourceRoot(filePath: #filePath)
    }

    private func makeFixture(executable: String) throws -> URL {
        let app = FileManager.default.temporaryDirectory
            .appendingPathComponent("AppStartupVerificationTests-\(UUID().uuidString)/Drift.app")
        let executableURL = app.appendingPathComponent("Contents/MacOS/Drift")
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try executable.write(to: executableURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: executableURL.path
        )
        addTeardownBlock {
            try? FileManager.default.removeItem(at: app.deletingLastPathComponent())
        }
        return app
    }

    private func runVerifier(
        for app: URL,
        graceSeconds: String = "1"
    ) throws -> TestProcessResult {
        try ProcessTestSupport.run(
            executable: "/bin/zsh",
            arguments: [
                sourceRoot.appendingPathComponent("scripts/verify-app-startup.sh").path,
                app.path
            ],
            environment: ["STARTUP_GRACE_SECONDS": graceSeconds],
            currentDirectory: sourceRoot
        )
    }
}
