import Foundation
import XCTest

final class ReleaseArtifactVerificationTests: XCTestCase {
    private let testPrivateKey = "AQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQE="
    private let testPublicKey = "iojj3XQJ8ZX9UtstPLpdcspnCb8dlBIb83SIAbQPb1w="

    // Break caught: removing any aggregate verification step would let an inconsistent
    // source, app, DMG, appcast, or provenance bundle ship as one release.
    func testVerifierAcceptsACompleteCanonicalRelease() throws {
        let fixture = try makeArtifactVerificationFixture()
        let result = try runVerifier(in: fixture)

        XCTAssertEqual(result.status, 0, result.output)
    }

    // Break caught: accepting a release executable that lacks an Intel slice.
    func testVerifierRejectsNonUniversalExecutable() throws {
        let fixture = try makeArtifactVerificationFixture(architectures: ["arm64"])
        let result = try runVerifier(in: fixture)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("architectures mismatch: expected arm64 x86_64"))
    }

    // Break caught: trusting appcast metadata that does not describe the signed DMG.
    func testVerifierRejectsAppcastLengthOrSignatureMismatch() throws {
        let fixture = try makeArtifactVerificationFixture(appcastLengthDelta: 1, verifySignature: false)
        let result = try runVerifier(in: fixture)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(
            result.output.contains("appcast enclosure length mismatch") ||
                result.output.contains("Sparkle signature verification failed")
        )
    }

    // Break caught: accepting provenance that names a different DMG than the appcast and file.
    func testVerifierRejectsProvenanceHashMismatch() throws {
        let fixture = try makeArtifactVerificationFixture(
            provenanceDMGSHA256: String(repeating: "0", count: 64)
        )
        let result = try runVerifier(in: fixture)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("provenance DMG SHA-256 mismatch"))
    }

    // Break caught: allowing provenance to smuggle an unverified field into a public release record.
    func testVerifierRejectsUnknownProvenanceTopLevelKey() throws {
        let fixture = try makeArtifactVerificationFixture(extraProvenanceKey: true)
        let result = try runVerifier(in: fixture)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("provenance has unknown or missing top-level keys"))
    }

    // Break caught: failing to remove a mounted DMG after a post-mount validation failure.
    func testVerifierDetachesMountedDMGAfterMountedAppFailure() throws {
        let fixture = try makeArtifactVerificationFixture(mountedArchitectures: ["arm64"])
        let result = try runVerifier(in: fixture, mountedArchitectures: ["arm64"])

        XCTAssertNotEqual(result.status, 0)
        let hdiutilLog = try String(contentsOf: fixture.appendingPathComponent("hdiutil.log"))
        XCTAssertTrue(hdiutilLog.contains("attach"))
        XCTAssertTrue(hdiutilLog.contains("detach"))
    }

    // Break caught: reporting tool stderr that could contain secret-adjacent Sparkle key material.
    func testVerifierRedactsSparkleSignatureToolFailure() throws {
        let fixture = try makeArtifactVerificationFixture(verifySignature: false)
        let result = try runVerifier(in: fixture, verifySignature: false)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("Sparkle signature verification failed"))
        XCTAssertFalse(result.output.contains("test-only-sensitive-signer-output"))
    }

    private var sourceRoot: URL {
        ProcessTestSupport.sourceRoot(filePath: #filePath)
    }

    private func makeArtifactVerificationFixture(
        architectures: [String] = ["x86_64", "arm64"],
        appcastLengthDelta: Int = 0,
        verifySignature: Bool = true,
        provenanceDMGSHA256: String? = nil,
        extraProvenanceKey: Bool = false,
        mountedArchitectures: [String]? = nil
    ) throws -> URL {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReleaseArtifactVerificationTests-\(UUID().uuidString)", isDirectory: true)
        let fileManager = FileManager.default
        let scripts = fixture.appendingPathComponent("scripts", isDirectory: true)
        let release = fixture.appendingPathComponent("release", isDirectory: true)
        let tools = fixture.appendingPathComponent("tools", isDirectory: true)
        let app = fixture.appendingPathComponent("build/release/Drift.app", isDirectory: true)
        let mountedApp = fixture.appendingPathComponent("mounted-app/Drift.app", isDirectory: true)
        let dmg = fixture.appendingPathComponent("build/release/Drift-0.1.0.dmg")
        let appcast = fixture.appendingPathComponent("build/release/appcast.xml")
        let provenance = fixture.appendingPathComponent("build/release/release-provenance.json")

        try fileManager.createDirectory(at: scripts, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: release, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tools, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: app.appendingPathComponent("Contents/MacOS", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: mountedApp.appendingPathComponent("Contents/MacOS", isDirectory: true),
            withIntermediateDirectories: true
        )

        for path in ["release/version.json"] {
            try fileManager.copyItem(
                at: sourceRoot.appendingPathComponent(path),
                to: fixture.appendingPathComponent(path)
            )
        }
        for script in [
            "release-version-lib.sh",
            "resolve-release-version.sh",
            "release-sparkle-lib.sh",
            "verify-release-artifacts.sh"
        ] {
            let source = sourceRoot.appendingPathComponent("scripts/\(script)")
            let destination = scripts.appendingPathComponent(script)
            if fileManager.fileExists(atPath: source.path) {
                try fileManager.copyItem(at: source, to: destination)
                try makeExecutable(destination)
            }
        }

        try fileManager.copyItem(at: sourceRoot.appendingPathComponent("Info.plist"), to: fixture.appendingPathComponent("Info.plist"))
        try replacePlistString("SUPublicEDKey", with: testPublicKey, at: fixture.appendingPathComponent("Info.plist"))

        for artifactApp in [app, mountedApp] {
            let info = artifactApp.appendingPathComponent("Contents/Info.plist")
            try fileManager.copyItem(at: fixture.appendingPathComponent("Info.plist"), to: info)
            try insertPlistString(
                "SUFeedURL",
                value: "https://github.com/woosublee/drift/releases/latest/download/appcast.xml",
                at: info
            )
            let executable = artifactApp.appendingPathComponent("Contents/MacOS/Drift")
            try "#!/bin/zsh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
            try makeExecutable(executable)
        }

        try Data("test-only dmg payload".utf8).write(to: dmg)
        let expectedDMGSHA256 = sha256(of: dmg)
        let appcastLength = try Data(contentsOf: dmg).count + appcastLengthDelta
        try makeAppcast(length: appcastLength).write(to: appcast, atomically: true, encoding: .utf8)
        let expectedAppcastSHA256 = sha256(of: appcast)

        let previousMetadata = "{\"source\":\"no-previous-release\",\"previous\":null}\n"
        try previousMetadata.write(
            to: fixture.appendingPathComponent("build/release/previous-release.json"),
            atomically: true,
            encoding: .utf8
        )
        let provenanceValue: [String: Any] = [
            "schemaVersion": 1,
            "release": [
                "version": "0.1.0",
                "build": 1,
                "tag": "v0.1.0",
                "commit": "0123456789abcdef0123456789abcdef01234567",
                "repository": "woosublee/drift",
                "bundleIdentifier": "com.woosublee.drift",
                "architectures": ["arm64", "x86_64"],
                "feedURL": "https://github.com/woosublee/drift/releases/latest/download/appcast.xml",
                "downloadURL": "https://github.com/woosublee/drift/releases/download/v0.1.0/Drift-0.1.0.dmg"
            ],
            "signing": [
                "certificateCommonName": "Drift",
                "certificateSHA256": String(repeating: "A", count: 64),
                "sparklePublicKey": testPublicKey
            ],
            "artifacts": [
                "dmg": [
                    "name": "Drift-0.1.0.dmg",
                    "bytes": try Data(contentsOf: dmg).count,
                    "sha256": provenanceDMGSHA256 ?? expectedDMGSHA256
                ],
                "appcast": [
                    "name": "appcast.xml",
                    "bytes": try Data(contentsOf: appcast).count,
                    "sha256": expectedAppcastSHA256
                ]
            ],
            "build": ["timestamp": "2026-08-12T00:00:00Z", "workflowRunID": NSNull()],
            "previous": NSNull()
        ]
        var completeProvenanceValue = provenanceValue
        if extraProvenanceKey {
            completeProvenanceValue["unverified"] = "must be rejected"
        }
        let provenanceData = try JSONSerialization.data(withJSONObject: completeProvenanceValue, options: [.sortedKeys])
        try provenanceData.write(to: provenance)

        try makeTool(
            named: "lipo",
            in: tools,
            content: """
            [[ "$1" == "-archs" ]]
            if [[ "$MOUNTED_ARCHITECTURES" != "" && "$2" == */drift-release-verification-mount.*/Drift.app/Contents/MacOS/Drift ]]; then
                print -r -- "$MOUNTED_ARCHITECTURES"
            else
                print -r -- "\(architectures.joined(separator: " "))"
            fi
            """
        )
        try makeTool(
            named: "codesign",
            in: tools,
            content: """
            if [[ "$1" == "-d" ]]; then
                [[ "$2" == --extract-certificates=* ]]
                prefix="${2#--extract-certificates=}"
                print -rn -- certificate > "${prefix}0"
            fi
            """
        )
        try makeTool(
            named: "openssl",
            in: tools,
            content: """
            [[ "$1" == "x509" ]]
            if [[ "$*" == *"-subject"* ]]; then
                print -r -- "subject=CN=Drift"
            else
                print -r -- "sha256 Fingerprint=AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA"
            fi
            """
        )
        try makeTool(
            named: "hdiutil",
            in: tools,
            content: """
            case "$1" in
                attach)
                    [[ "$2" == "-readonly" && "$3" == "-nobrowse" && "$4" == "-mountpoint" ]]
                    mountpoint="$5"
                    dmg="$6"
                    mkdir -p "$mountpoint"
                    print -r -- "attach $mountpoint" >> "$HDIUTIL_LOG"
                    cp -R "$MOUNTED_APP" "$mountpoint/Drift.app"
                    chmod +x "$mountpoint/Drift.app/Contents/MacOS/Drift"
                    ;;
                detach)
                    print -r -- "detach $*" >> "$HDIUTIL_LOG"
                    if [[ "$2" == "-force" ]]; then
                        rm -rf "$3"
                    else
                        rm -rf "$2"
                    fi
                    ;;
                *) exit 2 ;;
            esac
            """
        )
        try makeTool(
            named: "sign_update",
            in: tools,
            content: """
            [[ "$(cat)" == "$SPARKLE_PRIVATE_KEY" ]]
            [[ "$1" == "--verify" && "$2" == "--ed-key-file" && "$3" == "-" ]]
            [[ "$4" == "$PWD/build/release/Drift-0.1.0.dmg" && "$5" == "TEST_SIGNATURE" ]]
            if [[ "$VERIFY_SIGNATURE" != "1" ]]; then
                print -u2 -r -- "test-only-sensitive-signer-output"
                exit 1
            fi
            """
        )
        try makeTool(
            named: "git",
            in: tools,
            content: """
            [[ "$1" == "rev-parse" && "$2" == "HEAD" ]]
            print -r -- "0123456789abcdef0123456789abcdef01234567"
            """
        )

        addTeardownBlock {
            try? fileManager.removeItem(at: fixture)
        }
        return fixture
    }

    private func runVerifier(
        in fixture: URL,
        verifySignature: Bool = true,
        mountedArchitectures: [String]? = nil
    ) throws -> TestProcessResult {
        try ProcessTestSupport.run(
            executable: "/bin/zsh",
            arguments: [
                fixture.appendingPathComponent("scripts/verify-release-artifacts.sh").path,
                "--source-plist", "Info.plist",
                "--app", "build/release/Drift.app",
                "--dmg", "build/release/Drift-0.1.0.dmg",
                "--appcast", "build/release/appcast.xml",
                "--provenance", "build/release/release-provenance.json"
            ],
            environment: [
                "CODESIGN": fixture.appendingPathComponent("tools/codesign").path,
                "GIT": fixture.appendingPathComponent("tools/git").path,
                "HDIUTIL": fixture.appendingPathComponent("tools/hdiutil").path,
                "HDIUTIL_LOG": fixture.appendingPathComponent("hdiutil.log").path,
                "LIPO": fixture.appendingPathComponent("tools/lipo").path,
                "MOUNTED_APP": fixture.appendingPathComponent("mounted-app/Drift.app").path,
                "MOUNTED_EXECUTABLE": fixture.appendingPathComponent("mounted-app/Drift.app/Contents/MacOS/Drift").path,
                "OPENSSL": fixture.appendingPathComponent("tools/openssl").path,
                "SPARKLE_PRIVATE_KEY": testPrivateKey,
                "SPARKLE_SIGN_UPDATE": fixture.appendingPathComponent("tools/sign_update").path,
                "VERIFY_SIGNATURE": verifySignature ? "1" : "0",
                "MOUNTED_ARCHITECTURES": mountedArchitectures?.joined(separator: " ") ?? ""
            ],
            currentDirectory: fixture
        )
    }

    private func makeAppcast(length: Int) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <item>
              <sparkle:version>1</sparkle:version>
              <sparkle:shortVersionString>0.1.0</sparkle:shortVersionString>
              <enclosure url="https://github.com/woosublee/drift/releases/download/v0.1.0/Drift-0.1.0.dmg" length="\(length)" type="application/octet-stream" sparkle:edSignature="TEST_SIGNATURE" sparkle:version="1" sparkle:shortVersionString="0.1.0" />
            </item>
          </channel>
        </rss>
        """
    }

    private func replacePlistString(_ key: String, with value: String, at url: URL) throws {
        let result = try ProcessTestSupport.run(
            executable: "/usr/bin/plutil",
            arguments: ["-replace", key, "-string", value, url.path]
        )
        XCTAssertEqual(result.status, 0, result.output)
    }

    private func insertPlistString(_ key: String, value: String, at url: URL) throws {
        let result = try ProcessTestSupport.run(
            executable: "/usr/bin/plutil",
            arguments: ["-insert", key, "-string", value, url.path]
        )
        XCTAssertEqual(result.status, 0, result.output)
    }

    private func makeTool(named name: String, in directory: URL, content: String) throws {
        let tool = directory.appendingPathComponent(name)
        try "#!/bin/zsh\nset -euo pipefail\n\(content)".write(to: tool, atomically: true, encoding: .utf8)
        try makeExecutable(tool)
    }

    private func makeExecutable(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func sha256(of url: URL) -> String {
        let task = Process()
        let output = Pipe()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/shasum")
        task.arguments = ["-a", "256", url.path]
        task.standardOutput = output
        try! task.run()
        task.waitUntilExit()
        return String(
            data: output.fileHandleForReading.readDataToEndOfFile(),
            encoding: .utf8
        )!.split(separator: " ", maxSplits: 1)[0].lowercased()
    }
}
