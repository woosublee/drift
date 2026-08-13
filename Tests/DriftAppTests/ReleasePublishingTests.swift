import Foundation
import XCTest

final class ReleasePublishingTests: XCTestCase {
    // Break caught: a default release orchestration path that creates any remote GitHub state.
    func testLocalReleaseDefaultsToDryRunWithoutGitHubMutation() throws {
        let fixture = try makePublishingFixture()
        let result = try runLocalRelease(in: fixture, arguments: [])

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Dry-run complete; no tag or GitHub Release was created"))
        let mutations = (try? String(contentsOf: fixture.appendingPathComponent("mutations.log"))) ?? ""
        XCTAssertEqual(mutations, "")
    }

    // Break caught: publication from a lightweight tag rather than the required existing annotated tag.
    func testPublishRequiresExistingAnnotatedTagOnCurrentCommitAndOrigin() throws {
        let fixture = try makePublishingFixture(localTagType: "commit")
        let result = try runLocalRelease(in: fixture, arguments: ["--publish"])

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("release tag must be annotated"), result.output)
    }

    // Break caught: concatenating tag and notes lets either required publication argument be omitted.
    func testPublisherRequiresTagAndNotesIndividually() throws {
        let fixture = try makePublishingFixture()
        let missingTag = try runScript(
            "publish-github-release.sh",
            in: fixture,
            arguments: ["--repository", "woosublee/drift", "--notes", "notes.md"]
        )
        let missingNotes = try runScript(
            "publish-github-release.sh",
            in: fixture,
            arguments: ["--repository", "woosublee/drift", "--tag", "v0.1.0"]
        )

        XCTAssertEqual(missingTag.status, 2, missingTag.output)
        XCTAssertEqual(missingNotes.status, 2, missingNotes.output)
    }

    // Break caught: overwriting a mismatched release asset instead of safely resuming only exact assets.
    func testPublisherResumesOnlyMatchingAssetsAndRejectsDifferentChecksums() throws {
        let matching = try makePublishingFixture(existingAssets: [.dmgMatching])
        let matchingResult = try runPublisher(in: matching)
        XCTAssertEqual(matchingResult.status, 0, matchingResult.output)
        XCTAssertEqual(try uploadedAssetNames(in: matching), ["create", "appcast.xml", "release-provenance.json"])

        let conflicting = try makePublishingFixture(existingAssets: [.dmgConflicting])
        let result = try runPublisher(in: conflicting)
        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("existing asset checksum mismatch"))
    }

    private enum ExistingAsset {
        case dmgMatching
        case dmgConflicting
    }

    private var sourceRoot: URL {
        ProcessTestSupport.sourceRoot(filePath: #filePath)
    }

    private func makePublishingFixture(
        localTagType: String = "tag",
        existingAssets: [ExistingAsset] = []
    ) throws -> URL {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReleasePublishingTests-\(UUID().uuidString)", isDirectory: true)
        let fileManager = FileManager.default
        let scripts = fixture.appendingPathComponent("scripts", isDirectory: true)
        let tools = fixture.appendingPathComponent("tools", isDirectory: true)
        let release = fixture.appendingPathComponent("release", isDirectory: true)
        let assets = fixture.appendingPathComponent("remote-assets", isDirectory: true)
        try fileManager.createDirectory(at: scripts, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tools, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: release, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: assets, withIntermediateDirectories: true)

        for path in ["Info.plist", "release/version.json"] {
            try fileManager.copyItem(at: sourceRoot.appendingPathComponent(path), to: fixture.appendingPathComponent(path))
        }
        for script in [
            "release-version-lib.sh",
            "resolve-release-version.sh",
            "release-local.sh",
            "publish-github-release.sh"
        ] {
            let source = sourceRoot.appendingPathComponent("scripts/\(script)")
            let destination = scripts.appendingPathComponent(script)
            if fileManager.fileExists(atPath: source.path) {
                try fileManager.copyItem(at: source, to: destination)
                try makeExecutable(destination)
            }
        }

        let buildRelease = fixture.appendingPathComponent("build/release", isDirectory: true)
        try fileManager.createDirectory(at: buildRelease, withIntermediateDirectories: true)
        try Data("canonical dmg".utf8).write(to: buildRelease.appendingPathComponent("Drift-0.1.0.dmg"))
        try Data("canonical appcast".utf8).write(to: buildRelease.appendingPathComponent("appcast.xml"))
        try Data("canonical provenance".utf8).write(to: buildRelease.appendingPathComponent("release-provenance.json"))
        try "release notes\n".write(to: fixture.appendingPathComponent("notes.md"), atomically: true, encoding: .utf8)
        try "\(localTagType)\n".write(
            to: fixture.appendingPathComponent("local-tag-type"),
            atomically: true,
            encoding: .utf8
        )

        for asset in existingAssets {
            switch asset {
            case .dmgMatching:
                try fileManager.copyItem(
                    at: buildRelease.appendingPathComponent("Drift-0.1.0.dmg"),
                    to: assets.appendingPathComponent("Drift-0.1.0.dmg")
                )
            case .dmgConflicting:
                try Data("different remote dmg".utf8).write(to: assets.appendingPathComponent("Drift-0.1.0.dmg"))
            }
        }

        try makeTool(named: "git", in: tools, content: """
        case "$1 $2" in
            "status --porcelain") ;;
            "rev-parse HEAD") print -r -- "0123456789abcdef0123456789abcdef01234567" ;;
            "cat-file -t") cat "$LOCAL_TAG_TYPE_FILE" ;;
            "rev-list -n") print -r -- "0123456789abcdef0123456789abcdef01234567" ;;
            "ls-remote --get-url") print -r -- "git@github.com:woosublee/drift.git" ;;
            "ls-remote --tags") print -r -- "0123456789abcdef0123456789abcdef01234567\trefs/tags/v0.1.0^{}" ;;
            *) print -u2 -r -- "unexpected git: $*"; exit 2 ;;
        esac
        """)
        try makeTool(named: "gh", in: tools, content: """
        case "$1 $2" in
            "auth status") exit 0 ;;
            "release list") print -r -- "[]" ;;
            "release view")
                if [[ ! -f "$RELEASE_EXISTS" ]]; then
                    print -u2 -r -- "release not found"
                    exit 1
                fi
                print -r -- '{"isDraft":false,"isPrerelease":false,"name":"Drift 0.1.0"}'
                ;;
            "release create")
                print -r -- "create" >> "$MUTATIONS_LOG"
                : > "$RELEASE_EXISTS"
                ;;
            "release download")
                pattern=""
                directory=""
                while (( $# > 0 )); do
                    case "$1" in
                        --pattern) pattern="$2"; shift 2 ;;
                        --dir) directory="$2"; shift 2 ;;
                        *) shift ;;
                    esac
                done
                [[ -f "$REMOTE_ASSETS/$pattern" ]] || exit 1
                cp "$REMOTE_ASSETS/$pattern" "$directory/$pattern"
                ;;
            "release upload")
                asset="${@: -1}"
                print -r -- "${asset:t}" >> "$MUTATIONS_LOG"
                cp "$asset" "$REMOTE_ASSETS/${asset:t}"
                ;;
            *) print -u2 -r -- "unexpected gh: $*"; exit 2 ;;
        esac
        """)
        try makeTool(named: "make", in: tools, content: """
        case "$*" in
            *"release-metadata-check"*|*"check-local-certificate"*|*"check-eddsa-key"*|*"verify-release-artifacts"*) exit 0 ;;
            *"test"*) exit 0 ;;
            *) print -u2 -r -- "unexpected make: $*"; exit 2 ;;
        esac
        """)
        try makeTool(named: "check-release-monotonic.sh", in: tools, content: """
        output=""
        while (( $# > 0 )); do
            case "$1" in
                --output) output="$2"; shift 2 ;;
                *) shift ;;
            esac
        done
        mkdir -p "${output:h}"
        print -r -- '{"source":"no-previous-release","previous":null}' > "$output"
        """)

        addTeardownBlock {
            try? fileManager.removeItem(at: fixture)
        }
        return fixture
    }

    private func runLocalRelease(in fixture: URL, arguments: [String]) throws -> TestProcessResult {
        try runScript("release-local.sh", in: fixture, arguments: arguments)
    }

    private func runPublisher(in fixture: URL) throws -> TestProcessResult {
        try runScript(
            "publish-github-release.sh",
            in: fixture,
            arguments: ["--repository", "woosublee/drift", "--tag", "v0.1.0", "--notes", "notes.md"]
        )
    }

    private func runScript(_ script: String, in fixture: URL, arguments: [String]) throws -> TestProcessResult {
        let tools = fixture.appendingPathComponent("tools", isDirectory: true)
        return try ProcessTestSupport.run(
            executable: "/bin/zsh",
            arguments: [fixture.appendingPathComponent("scripts/\(script)").path] + arguments,
            environment: [
                "GIT": tools.appendingPathComponent("git").path,
                "GH": tools.appendingPathComponent("gh").path,
                "MAKE": tools.appendingPathComponent("make").path,
                "MONOTONICITY_CHECKER": tools.appendingPathComponent("check-release-monotonic.sh").path,
                "LOCAL_TAG_TYPE_FILE": fixture.appendingPathComponent("local-tag-type").path,
                "MUTATIONS_LOG": fixture.appendingPathComponent("mutations.log").path,
                "RELEASE_EXISTS": fixture.appendingPathComponent("release-exists").path,
                "REMOTE_ASSETS": fixture.appendingPathComponent("remote-assets").path,
                "RELEASE_NOTES_FILE": fixture.appendingPathComponent("notes.md").path
            ],
            currentDirectory: fixture
        )
    }

    private func uploadedAssetNames(in fixture: URL) throws -> [String] {
        let log = try String(contentsOf: fixture.appendingPathComponent("mutations.log"))
        return log.split(separator: "\n").map(String.init)
    }

    private func makeTool(named name: String, in directory: URL, content: String) throws {
        let tool = directory.appendingPathComponent(name)
        try "#!/bin/zsh\nset -euo pipefail\n\(content)".write(to: tool, atomically: true, encoding: .utf8)
        try makeExecutable(tool)
    }

    private func makeExecutable(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
