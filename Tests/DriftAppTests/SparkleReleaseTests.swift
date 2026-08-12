import Foundation
import XCTest

final class SparkleReleaseTests: XCTestCase {
    private let testPrivateSeed = "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE="
    private let testPublicKey = "iojj3XQJ8ZX9UtstPLpdcspnCb8dlBIb83SIAbQPb1w="

    func testSparkleKeyValidatorAcceptsMatchingSeedAndRejectsMismatch() throws {
        let matching = try runValidator(privateKey: testPrivateSeed, publicKey: testPublicKey)
        XCTAssertEqual(matching.status, 0, matching.output)

        let mismatch = try runValidator(
            privateKey: testPrivateSeed,
            publicKey: "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        )
        XCTAssertNotEqual(mismatch.status, 0)
        XCTAssertTrue(mismatch.output.contains("does not match SUPublicEDKey"))
    }

    func testAppcastGeneratorSignsThenVerifiesAndWritesCanonicalEnclosure() throws {
        let fixture = try makeSparkleFixture()
        let result = try runGenerator(in: fixture, privateKey: testPrivateSeed)

        XCTAssertEqual(result.status, 0, result.output)
        let appcast = try String(contentsOf: fixture.appendingPathComponent("build/release/appcast.xml"))
        XCTAssertTrue(appcast.contains("<sparkle:version>1</sparkle:version>"))
        XCTAssertTrue(appcast.contains("<sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>"))
        XCTAssertTrue(appcast.contains("https://github.com/woosublee/drift/releases/download/v0.1.0/Drift-0.1.0.dmg"))
        XCTAssertTrue(appcast.contains("sparkle:edSignature=\"TEST_SIGNATURE\""))
        let log = try String(contentsOf: fixture.appendingPathComponent("sign-update.log"))
        XCTAssertTrue(log.contains("SIGN"))
        XCTAssertTrue(log.contains("VERIFY TEST_SIGNATURE"))
    }

    private var sourceRoot: URL {
        ProcessTestSupport.sourceRoot(filePath: #filePath)
    }

    private func runValidator(privateKey: String, publicKey: String) throws -> TestProcessResult {
        let validator = sourceRoot.appendingPathComponent("scripts/validate-sparkle-key.swift")
        return try ProcessTestSupport.run(
            executable: "/bin/zsh",
            arguments: [
                "-c",
                "print -rn -- \"$PRIVATE_KEY\" | /usr/bin/xcrun swift \"$1\" \"$2\"",
                "validator-test",
                validator.path,
                publicKey
            ],
            environment: ["PRIVATE_KEY": privateKey],
            currentDirectory: sourceRoot
        )
    }

    private func makeSparkleFixture() throws -> URL {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("SparkleReleaseTests-\(UUID().uuidString)", isDirectory: true)
        let scripts = fixture.appendingPathComponent("scripts", isDirectory: true)
        let release = fixture.appendingPathComponent("release", isDirectory: true)
        let tools = fixture.appendingPathComponent("tools", isDirectory: true)
        let fileManager = FileManager.default

        try fileManager.createDirectory(at: scripts, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: release, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tools, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: fixture.appendingPathComponent("build/release", isDirectory: true),
            withIntermediateDirectories: true
        )

        for path in ["Info.plist", "release/version.json"] {
            try fileManager.copyItem(
                at: sourceRoot.appendingPathComponent(path),
                to: fixture.appendingPathComponent(path)
            )
        }
        for script in [
            "release-version-lib.sh",
            "resolve-release-version.sh",
            "release-sparkle-lib.sh",
            "validate-sparkle-key.swift",
            "generate-sparkle-appcast.sh"
        ] {
            let source = sourceRoot.appendingPathComponent("scripts/\(script)")
            let destination = scripts.appendingPathComponent(script)
            if fileManager.fileExists(atPath: source.path) {
                try fileManager.copyItem(at: source, to: destination)
                try makeExecutable(destination)
            }
        }

        let update = try ProcessTestSupport.run(
            executable: "/usr/bin/plutil",
            arguments: ["-replace", "SUPublicEDKey", "-string", testPublicKey, fixture.appendingPathComponent("Info.plist").path],
            currentDirectory: fixture
        )
        XCTAssertEqual(update.status, 0, update.output)
        try Data("test dmg".utf8).write(to: fixture.appendingPathComponent("build/release/Drift-0.1.0.dmg"))

        let signUpdate = tools.appendingPathComponent("sign_update")
        try """
        #!/bin/zsh
        set -euo pipefail
        key="$(cat)"
        [[ "$key" == "${SPARKLE_PRIVATE_KEY}" ]]
        if [[ "$1" == "--verify" ]]; then
            [[ "$2" == "--ed-key-file" && "$3" == "-" ]]
            [[ "$4" == "$PWD/build/release/Drift-0.1.0.dmg" ]]
            [[ "$5" == "TEST_SIGNATURE" ]]
            print -r -- "VERIFY $5" >> "$SIGN_UPDATE_LOG"
            exit 0
        fi
        [[ "$1" == "$PWD/build/release/Drift-0.1.0.dmg" ]]
        [[ "$2" == "--ed-key-file" && "$3" == "-" ]]
        print -r -- "SIGN" >> "$SIGN_UPDATE_LOG"
        print -r -- 'sparkle:edSignature="TEST_SIGNATURE"'
        """.write(to: signUpdate, atomically: true, encoding: .utf8)
        try makeExecutable(signUpdate)

        addTeardownBlock {
            try? fileManager.removeItem(at: fixture)
        }
        return fixture
    }

    private func runGenerator(in fixture: URL, privateKey: String) throws -> TestProcessResult {
        try ProcessTestSupport.run(
            executable: "/bin/zsh",
            arguments: [fixture.appendingPathComponent("scripts/generate-sparkle-appcast.sh").path],
            environment: [
                "SPARKLE_PRIVATE_KEY": privateKey,
                "SPARKLE_SIGN_UPDATE": fixture.appendingPathComponent("tools/sign_update").path,
                "SIGN_UPDATE_LOG": fixture.appendingPathComponent("sign-update.log").path
            ],
            currentDirectory: fixture
        )
    }

    private func makeExecutable(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
