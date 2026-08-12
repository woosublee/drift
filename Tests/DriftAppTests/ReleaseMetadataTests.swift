import Foundation
import XCTest

final class ReleaseMetadataTests: XCTestCase {
    private let privateMaterialSentinel = "test-private-material-must-not-appear"
    private let publicKey = "iojj3XQJ8ZX9UtstPLpdcspnCb8dlBIb83SIAbQPb1w="

    func testFirstReleaseWritesNullPreviousMetadata() throws {
        let fixture = try makeMetadataFixture(fakeGitHubReleases: [])
        let result = try runMonotonicCheck(in: fixture)

        XCTAssertEqual(result.status, 0, result.output)
        let metadata = try loadJSON(fixture.appendingPathComponent("build/release/previous-release.json"))
        XCTAssertTrue(metadata["previous"] is NSNull)
        XCTAssertEqual(metadata["source"] as? String, "no-previous-release")
    }

    func testCandidateBuildMustBeGreaterThanPreviousAppcastBuild() throws {
        let fixture = try makeMetadataFixture(candidateBuild: 1, previousBuild: 1)
        let result = try runMonotonicCheck(in: fixture, explicitPreviousAppcast: true)

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("current build 1 must be greater than previous build 1"))
    }

    func testGitHubPreviousReleaseWritesCanonicalPreviousMetadata() throws {
        let fixture = try makeGitHubPreviousFixture()
        let result = try runMonotonicCheck(in: fixture)

        XCTAssertEqual(result.status, 0, result.output)
        let metadata = try loadJSON(fixture.appendingPathComponent("build/release/previous-release.json"))
        XCTAssertEqual(metadata["source"] as? String, "github-release-appcast")
        let previous = try XCTUnwrap(metadata["previous"] as? [String: Any])
        XCTAssertEqual(previous["version"] as? String, "0.0.9")
        XCTAssertEqual(previous["build"] as? Int, 9)
        XCTAssertEqual(previous["tag"] as? String, "v0.0.9")
        XCTAssertEqual(previous["dmgName"] as? String, "Drift-0.0.9.dmg")
    }

    func testProvenanceContainsOnlyPublicCanonicalMetadata() throws {
        let fixture = try makeCompleteArtifactFixture()
        let result = try runProvenanceGenerator(in: fixture)

        XCTAssertEqual(result.status, 0, result.output)
        let value = try loadJSON(fixture.appendingPathComponent("build/release/release-provenance.json"))
        let release = try XCTUnwrap(value["release"] as? [String: Any])
        XCTAssertEqual(release["version"] as? String, "0.1.0")
        XCTAssertEqual(release["build"] as? Int, 1)
        XCTAssertEqual(release["tag"] as? String, "v0.1.0")
        XCTAssertEqual(release["architectures"] as? [String], ["arm64", "x86_64"])
        XCTAssertNil(value["privateMaterial"])
        XCTAssertFalse(
            String(
                data: try Data(contentsOf: fixture.appendingPathComponent("build/release/release-provenance.json")),
                encoding: .utf8
            )!.contains(privateMaterialSentinel)
        )
    }

    private var sourceRoot: URL {
        ProcessTestSupport.sourceRoot(filePath: #filePath)
    }

    private func makeMetadataFixture(
        candidateBuild: Int = 1,
        previousBuild: Int? = nil,
        fakeGitHubReleases: [[String: String]] = []
    ) throws -> URL {
        let fixture = try makeReleaseFixture(candidateBuild: candidateBuild)
        let tools = fixture.appendingPathComponent("tools", isDirectory: true)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: tools, withIntermediateDirectories: true)

        let gh = tools.appendingPathComponent("gh")
        let releases = try JSONSerialization.data(withJSONObject: fakeGitHubReleases)
        try """
        #!/bin/zsh
        set -euo pipefail
        [[ "$1" == "release" && "$2" == "list" ]]
        print -r -- '\(String(decoding: releases, as: UTF8.self))'
        """.write(to: gh, atomically: true, encoding: .utf8)
        try makeExecutable(gh)

        if let previousBuild {
            let previousAppcast = fixture.appendingPathComponent("previous-appcast.xml")
            try appcast(build: previousBuild, version: "0.0.9").write(
                to: previousAppcast,
                atomically: true,
                encoding: .utf8
            )
        }
        return fixture
    }

    private func makeGitHubPreviousFixture() throws -> URL {
        let fixture = try makeMetadataFixture(
            candidateBuild: 10,
            fakeGitHubReleases: [
                ["tagName": "v0.0.9", "publishedAt": "2026-08-11T00:00:00Z"],
                ["tagName": "v0.0.8", "publishedAt": "2026-08-10T00:00:00Z"]
            ]
        )
        let gh = fixture.appendingPathComponent("tools/gh")
        let downloadedAppcast = appcast(build: 9, version: "0.0.9")
        try """
        #!/bin/zsh
        set -euo pipefail
        if [[ "$1" == "release" && "$2" == "list" ]]; then
            print -r -- '[{"tagName":"v0.0.9","publishedAt":"2026-08-11T00:00:00Z"},{"tagName":"v0.0.8","publishedAt":"2026-08-10T00:00:00Z"}]'
        elif [[ "$1" == "release" && "$2" == "download" ]]; then
            [[ "$3" == "v0.0.9" && "$4" == "--repo" && "$5" == "woosublee/drift" && "$6" == "--pattern" && "$7" == "appcast.xml" && "$8" == "--dir" ]]
            cat > "$9/appcast.xml" <<'EOF'
        \(downloadedAppcast)
        EOF
        else
            exit 2
        fi
        """.write(to: gh, atomically: true, encoding: .utf8)
        try makeExecutable(gh)
        return fixture
    }

    private func makeCompleteArtifactFixture() throws -> URL {
        let fixture = try makeReleaseFixture(candidateBuild: 1)
        let fileManager = FileManager.default
        let scripts = fixture.appendingPathComponent("scripts", isDirectory: true)
        let tools = fixture.appendingPathComponent("tools", isDirectory: true)
        let app = fixture.appendingPathComponent("build/release/Drift.app", isDirectory: true)

        for script in ["generate-release-provenance.sh"] {
            let source = sourceRoot.appendingPathComponent("scripts/\(script)")
            let destination = scripts.appendingPathComponent(script)
            if fileManager.fileExists(atPath: source.path) {
                try fileManager.copyItem(at: source, to: destination)
                try makeExecutable(destination)
            }
        }
        try fileManager.createDirectory(at: tools, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: app.appendingPathComponent("Contents/MacOS", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.copyItem(
            at: sourceRoot.appendingPathComponent("Info.plist"),
            to: app.appendingPathComponent("Contents/Info.plist")
        )
        let appInfo = app.appendingPathComponent("Contents/Info.plist")
        try replacePlistString("SUPublicEDKey", with: publicKey, at: appInfo)
        try insertPlistString(
            "SUFeedURL",
            value: "https://github.com/woosublee/drift/releases/latest/download/appcast.xml",
            at: appInfo
        )
        try insertPlistString("PrivateMaterial", value: privateMaterialSentinel, at: appInfo)
        try "release executable".write(
            to: app.appendingPathComponent("Contents/MacOS/Drift"),
            atomically: true,
            encoding: .utf8
        )
        try "release dmg".write(
            to: fixture.appendingPathComponent("build/release/Drift-0.1.0.dmg"),
            atomically: true,
            encoding: .utf8
        )
        try appcast(build: 1, version: "0.1.0").write(
            to: fixture.appendingPathComponent("build/release/appcast.xml"),
            atomically: true,
            encoding: .utf8
        )
        try """
        {"source":"no-previous-release","previous":null}
        """.write(
            to: fixture.appendingPathComponent("build/release/previous-release.json"),
            atomically: true,
            encoding: .utf8
        )

        let lipo = tools.appendingPathComponent("lipo")
        try """
        #!/bin/zsh
        set -euo pipefail
        [[ "$1" == "-archs" ]]
        print -r -- "x86_64 arm64"
        """.write(to: lipo, atomically: true, encoding: .utf8)
        try makeExecutable(lipo)

        let git = tools.appendingPathComponent("git")
        try """
        #!/bin/zsh
        set -euo pipefail
        if [[ "$1" == "rev-parse" && "$2" == "HEAD" ]]; then
            print -r -- "0123456789abcdef0123456789abcdef01234567"
        elif [[ "$1" == "show" ]]; then
            print -r -- "1786492800"
        else
            exit 2
        fi
        """.write(to: git, atomically: true, encoding: .utf8)
        try makeExecutable(git)

        let codesign = tools.appendingPathComponent("codesign")
        try """
        #!/bin/zsh
        set -euo pipefail
        [[ "$1" == "--extract-certificates" ]]
        prefix="$2"
        app="$3"
        [[ -d "$app" ]]
        print -rn -- "certificate" > "${prefix}0"
        """.write(to: codesign, atomically: true, encoding: .utf8)
        try makeExecutable(codesign)

        let openssl = tools.appendingPathComponent("openssl")
        try """
        #!/bin/zsh
        set -euo pipefail
        [[ "$1" == "x509" ]]
        if [[ "$*" == *"-subject"* ]]; then
            print -r -- "subject=CN=Drift"
        else
            print -r -- "sha256 Fingerprint=AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA:AA"
        fi
        """.write(to: openssl, atomically: true, encoding: .utf8)
        try makeExecutable(openssl)

        return fixture
    }

    private func makeReleaseFixture(candidateBuild: Int) throws -> URL {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReleaseMetadataTests-\(UUID().uuidString)", isDirectory: true)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: fixture.appendingPathComponent("scripts"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: fixture.appendingPathComponent("release"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: fixture.appendingPathComponent("build/release"), withIntermediateDirectories: true)
        try fileManager.copyItem(
            at: sourceRoot.appendingPathComponent("release/version.json"),
            to: fixture.appendingPathComponent("release/version.json")
        )
        try "{\"marketingVersion\":\"0.1.0\",\"buildNumber\":\(candidateBuild)}".write(
            to: fixture.appendingPathComponent("release/version.json"),
            atomically: true,
            encoding: .utf8
        )
        for script in ["release-version-lib.sh", "resolve-release-version.sh", "check-release-monotonic.sh"] {
            let source = sourceRoot.appendingPathComponent("scripts/\(script)")
            let destination = fixture.appendingPathComponent("scripts/\(script)")
            if fileManager.fileExists(atPath: source.path) {
                try fileManager.copyItem(at: source, to: destination)
                try makeExecutable(destination)
            }
        }
        addTeardownBlock {
            try? fileManager.removeItem(at: fixture)
        }
        return fixture
    }

    private func runMonotonicCheck(in fixture: URL, explicitPreviousAppcast: Bool = false) throws -> TestProcessResult {
        var arguments = [
            fixture.appendingPathComponent("scripts/check-release-monotonic.sh").path,
            "--repository", "woosublee/drift",
            "--output", "build/release/previous-release.json"
        ]
        if explicitPreviousAppcast {
            arguments += ["--previous-appcast", "previous-appcast.xml"]
        }
        return try ProcessTestSupport.run(
            executable: "/bin/zsh",
            arguments: arguments,
            environment: ["GH": fixture.appendingPathComponent("tools/gh").path],
            currentDirectory: fixture
        )
    }

    private func runProvenanceGenerator(in fixture: URL) throws -> TestProcessResult {
        try ProcessTestSupport.run(
            executable: "/bin/zsh",
            arguments: [
                fixture.appendingPathComponent("scripts/generate-release-provenance.sh").path,
                "--previous", "build/release/previous-release.json"
            ],
            environment: [
                "CODESIGN": fixture.appendingPathComponent("tools/codesign").path,
                "GIT": fixture.appendingPathComponent("tools/git").path,
                "LIPO": fixture.appendingPathComponent("tools/lipo").path,
                "OPENSSL": fixture.appendingPathComponent("tools/openssl").path,
                "SOURCE_DATE_EPOCH": "1786492800",
                "GITHUB_RUN_ID": "42"
            ],
            currentDirectory: fixture
        )
    }

    private func appcast(build: Int, version: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
          <channel>
            <item>
              <sparkle:shortVersionString>\(version)</sparkle:shortVersionString>
              <enclosure url="https://github.com/woosublee/drift/releases/download/v\(version)/Drift-\(version).dmg" sparkle:version="\(build)" />
            </item>
          </channel>
        </rss>
        """
    }

    private func loadJSON(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
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

    private func makeExecutable(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
