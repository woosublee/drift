import Foundation
import XCTest

final class ReleaseVersionTests: XCTestCase {
    func testResolverReturnsCanonicalReleaseIdentity() throws {
        let fixture = try makeReleaseFixture()
        let result = try runScript("scripts/resolve-release-version.sh", ["json"], in: fixture)

        XCTAssertEqual(result.status, 0, result.output)
        let data = try XCTUnwrap(result.output.data(using: .utf8))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["version"] as? String, "0.1.0")
        XCTAssertEqual(json["build"] as? Int, 1)
        XCTAssertEqual(json["tag"] as? String, "v0.1.0")
        XCTAssertEqual(json["dmgName"] as? String, "Drift-0.1.0.dmg")
        XCTAssertEqual(json["dmgPath"] as? String, "build/release/Drift-0.1.0.dmg")
        XCTAssertEqual(json["appcastPath"] as? String, "build/release/appcast.xml")
        XCTAssertEqual(json["provenancePath"] as? String, "build/release/release-provenance.json")
        XCTAssertEqual(
            json["feedURL"] as? String,
            "https://github.com/woosublee/drift/releases/latest/download/appcast.xml"
        )
        XCTAssertEqual(
            json["downloadURL"] as? String,
            "https://github.com/woosublee/drift/releases/download/v0.1.0/Drift-0.1.0.dmg"
        )
    }

    func testResolverRejectsUnknownKeysAndInvalidValues() throws {
        let fixture = try makeReleaseFixture(versionJSON: """
        {"marketingVersion":"01.0.0","buildNumber":0,"extra":true}
        """)
        let result = try runScript("scripts/resolve-release-version.sh", ["validate"], in: fixture)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("exactly marketingVersion and buildNumber"))
    }

    func testMakePrintTargetResolvesOnlyRequestedValue() throws {
        let fixture = try makeReleaseFixture()
        let resolver = fixture.appendingPathComponent("scripts/resolve-release-version.sh")
        let resolverLog = fixture.appendingPathComponent("resolver.log")
        try """
        #!/bin/zsh
        print -r -- "$1" >> "$RESOLVER_LOG"
        case "$1" in
            version) print -r -- "0.1.0" ;;
            build) print -r -- "1" ;;
            tag) print -r -- "v0.1.0" ;;
            *) exit 2 ;;
        esac
        """.write(to: resolver, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: resolver.path)

        let result = try ProcessTestSupport.run(
            executable: "/usr/bin/make",
            arguments: ["-s", "print-release-version"],
            environment: ["RESOLVER_LOG": resolverLog.path],
            currentDirectory: fixture
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertEqual(result.output, "0.1.0\n")
        XCTAssertEqual(try String(contentsOf: resolverLog), "version\n")
    }

    func testReleaseLibraryProvidesComparisonAndAppcastParsingHelpers() throws {
        let fixture = try makeReleaseFixture()
        let appcast = fixture.appendingPathComponent("appcast.xml")
        try """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <item>
              <enclosure url="https://example.com/Drift-0.1.0.dmg" sparkle:version="2" />
            </item>
          </channel>
        </rss>
        """.write(to: appcast, atomically: true, encoding: .utf8)
        let library = fixture.appendingPathComponent("scripts/release-version-lib.sh")
        let result = try ProcessTestSupport.run(
            executable: "/bin/zsh",
            arguments: [
                "-c",
                "source \"$1\"; release_positive_integer_greater_than 2 1; ! release_positive_integer_greater_than 1 2; [[ \"$(release_appcast_extract_enclosure_url \"$2\")\" == \"https://example.com/Drift-0.1.0.dmg\" ]]; [[ \"$(release_appcast_extract_enclosure_version \"$2\")\" == \"2\" ]]",
                "release-library-test",
                library.path,
                appcast.path
            ],
            currentDirectory: fixture
        )

        XCTAssertEqual(result.status, 0, result.output)
    }

    func testVersionMirrorCheckSucceedsForMatchingPlist() throws {
        let fixture = try makeReleaseFixture()
        let result = try runScript("scripts/sync-release-version.sh", ["--check"], in: fixture)

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertEqual(result.output, "")
    }

    func testVersionMirrorCheckFailsWithoutMutatingPlist() throws {
        let fixture = try makeReleaseFixture(plistVersion: "9.9.9", plistBuild: "99")
        let plist = fixture.appendingPathComponent("Info.plist")
        let before = try Data(contentsOf: plist)

        let result = try runScript("scripts/sync-release-version.sh", ["--check"], in: fixture)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertEqual(try Data(contentsOf: plist), before)
        XCTAssertTrue(result.output.contains("Info.plist version mismatch"))
        XCTAssertTrue(result.output.contains("Info.plist build mismatch"))
    }

    func testVersionMirrorSyncUpdatesBothKeysAtomically() throws {
        let fixture = try makeReleaseFixture(plistVersion: "9.9.9", plistBuild: "99")
        let result = try runScript("scripts/sync-release-version.sh", [], in: fixture)

        XCTAssertEqual(result.status, 0, result.output)
        let plist = try loadPlist(fixture.appendingPathComponent("Info.plist"))
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "0.1.0")
        XCTAssertEqual(plist["CFBundleVersion"] as? String, "1")
    }

    private func makeReleaseFixture(
        versionJSON: String = #"{"marketingVersion":"0.1.0","buildNumber":1}"#,
        plistVersion: String = "0.1.0",
        plistBuild: String = "1"
    ) throws -> URL {
        let sourceRoot = ProcessTestSupport.sourceRoot(filePath: #filePath)
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReleaseVersionTests-\(UUID().uuidString)", isDirectory: true)
        let scripts = fixture.appendingPathComponent("scripts", isDirectory: true)
        let release = fixture.appendingPathComponent("release", isDirectory: true)
        let fileManager = FileManager.default

        try fileManager.createDirectory(at: scripts, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: release, withIntermediateDirectories: true)
        for path in ["Makefile", "Info.plist"] {
            try fileManager.copyItem(
                at: sourceRoot.appendingPathComponent(path),
                to: fixture.appendingPathComponent(path)
            )
        }
        try fileManager.copyItem(
            at: sourceRoot.appendingPathComponent("release/version.json"),
            to: release.appendingPathComponent("version.json")
        )
        try versionJSON.write(
            to: release.appendingPathComponent("version.json"),
            atomically: true,
            encoding: .utf8
        )
        for script in ["release-version-lib.sh", "resolve-release-version.sh", "sync-release-version.sh"] {
            try fileManager.copyItem(
                at: sourceRoot.appendingPathComponent("scripts/\(script)"),
                to: scripts.appendingPathComponent(script)
            )
        }

        let plist = fixture.appendingPathComponent("Info.plist")
        let versionUpdate = try ProcessTestSupport.run(
            executable: "/usr/bin/plutil",
            arguments: ["-replace", "CFBundleShortVersionString", "-string", plistVersion, plist.path],
            currentDirectory: fixture
        )
        XCTAssertEqual(versionUpdate.status, 0, versionUpdate.output)
        let buildUpdate = try ProcessTestSupport.run(
            executable: "/usr/bin/plutil",
            arguments: ["-replace", "CFBundleVersion", "-string", plistBuild, plist.path],
            currentDirectory: fixture
        )
        XCTAssertEqual(buildUpdate.status, 0, buildUpdate.output)

        addTeardownBlock {
            try? fileManager.removeItem(at: fixture)
        }
        return fixture
    }

    private func runScript(_ path: String, _ arguments: [String], in fixture: URL) throws -> TestProcessResult {
        try ProcessTestSupport.run(
            executable: "/bin/zsh",
            arguments: [fixture.appendingPathComponent(path).path] + arguments,
            currentDirectory: fixture
        )
    }

    private func loadPlist(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any])
    }
}
