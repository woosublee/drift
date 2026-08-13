import Foundation
import XCTest

final class ReleasePackagingTests: XCTestCase {
    func testPackagerStagesAppAndApplicationsLinkUnderCanonicalName() throws {
        let fixture = try makePackagingFixture()
        let result = try runPackager(in: fixture)

        XCTAssertEqual(result.status, 0, result.output)
        let log = try String(contentsOf: fixture.appendingPathComponent("tool.log"))
        XCTAssertTrue(log.contains("Drift.app"))
        XCTAssertTrue(log.contains("Applications -> /Applications"))
        XCTAssertTrue(log.contains("-volname Drift"))
        XCTAssertTrue(log.contains("Drift-0.1.0.dmg"))
        XCTAssertTrue(log.contains("verify-xattrs"))
        XCTAssertTrue(log.contains("codesign --verify --deep --strict --verbose=2"))

        let stagedAppVerification = try XCTUnwrap(log.range(of: "codesign --verify --deep --strict --verbose=2"))
        let dmgCreation = try XCTUnwrap(log.range(of: "hdiutil create"))
        XCTAssertLessThan(stagedAppVerification.lowerBound, dmgCreation.lowerBound)
        XCTAssertTrue(
            FileManager.default.fileExists(
                atPath: fixture.appendingPathComponent("build/release/Drift-0.1.0.dmg").path
            )
        )
    }

    func testPackagerSignsAndStrictlyVerifiesTheDMG() throws {
        let fixture = try makePackagingFixture()
        let result = try runPackager(in: fixture)

        XCTAssertEqual(result.status, 0, result.output)
        let log = try String(contentsOf: fixture.appendingPathComponent("tool.log"))
        let sign = try XCTUnwrap(log.range(of: "codesign --force --sign Drift"))
        let verify = try XCTUnwrap(log.range(of: "codesign --verify --strict"))
        XCTAssertLessThan(sign.lowerBound, verify.lowerBound)
    }

    private var sourceRoot: URL {
        ProcessTestSupport.sourceRoot(filePath: #filePath)
    }

    private func makePackagingFixture() throws -> URL {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReleasePackagingTests-\(UUID().uuidString)", isDirectory: true)
        let scripts = fixture.appendingPathComponent("scripts", isDirectory: true)
        let release = fixture.appendingPathComponent("release", isDirectory: true)
        let app = fixture.appendingPathComponent("build/release/Drift.app", isDirectory: true)
        let tools = fixture.appendingPathComponent("tools", isDirectory: true)
        let fileManager = FileManager.default

        try fileManager.createDirectory(at: scripts, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: release, withIntermediateDirectories: true)
        try fileManager.createDirectory(
            at: app.appendingPathComponent("Contents/MacOS", isDirectory: true),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(at: tools, withIntermediateDirectories: true)

        try fileManager.copyItem(
            at: sourceRoot.appendingPathComponent("release/version.json"),
            to: release.appendingPathComponent("version.json")
        )
        for script in ["release-version-lib.sh", "resolve-release-version.sh"] {
            let destination = scripts.appendingPathComponent(script)
            try fileManager.copyItem(
                at: sourceRoot.appendingPathComponent("scripts/\(script)"),
                to: destination
            )
            try makeExecutable(destination)
        }
        let packager = sourceRoot.appendingPathComponent("scripts/package-release-dmg.sh")
        if fileManager.fileExists(atPath: packager.path) {
            let destination = scripts.appendingPathComponent("package-release-dmg.sh")
            try fileManager.copyItem(at: packager, to: destination)
            try makeExecutable(destination)
        }

        let executable = app.appendingPathComponent("Contents/MacOS/Drift")
        try "#!/bin/zsh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try makeExecutable(executable)

        try """
        #!/bin/zsh
        set -euo pipefail
        print -r -- "verify-xattrs $*" >> "$TOOL_LOG"
        [[ -d "$1" ]]
        """.write(
            to: scripts.appendingPathComponent("verify-bundle-signing-xattrs.sh"),
            atomically: true,
            encoding: .utf8
        )
        try makeExecutable(scripts.appendingPathComponent("verify-bundle-signing-xattrs.sh"))

        try """
        #!/bin/zsh
        set -euo pipefail
        print -r -- "ditto $*" >> "$TOOL_LOG"
        [[ "$1" == "--norsrc" && "$2" == "--noextattr" ]]
        [[ "$3" == "$PWD/build/release/Drift.app" ]]
        cp -R "$3" "$4"
        """.write(to: tools.appendingPathComponent("ditto"), atomically: true, encoding: .utf8)
        try makeExecutable(tools.appendingPathComponent("ditto"))

        try """
        #!/bin/zsh
        set -euo pipefail
        print -r -- "hdiutil $*" >> "$TOOL_LOG"
        volume=""
        source_folder=""
        for (( index = 1; index <= $#; index++ )); do
            case "${argv[index]}" in
                -volname) volume="${argv[index + 1]}" ;;
                -srcfolder) source_folder="${argv[index + 1]}" ;;
            esac
        done
        [[ "$1" == "create" && "$volume" == "Drift" ]]
        [[ -d "$source_folder/Drift.app" ]]
        [[ "$(readlink "$source_folder/Applications")" == "/Applications" ]]
        print -r -- "Applications -> $(readlink "$source_folder/Applications")" >> "$TOOL_LOG"
        dmg="${argv[-1]}"
        mkdir -p "${dmg:h}"
        touch "$dmg"
        """.write(to: tools.appendingPathComponent("hdiutil"), atomically: true, encoding: .utf8)
        try makeExecutable(tools.appendingPathComponent("hdiutil"))

        try """
        #!/bin/zsh
        set -euo pipefail
        print -r -- "codesign $*" >> "$TOOL_LOG"
        target="${argv[-1]}"
        [[ -e "$target" ]]
        """.write(to: tools.appendingPathComponent("codesign"), atomically: true, encoding: .utf8)
        try makeExecutable(tools.appendingPathComponent("codesign"))

        addTeardownBlock {
            try? fileManager.removeItem(at: fixture)
        }
        return fixture
    }

    private func runPackager(in fixture: URL) throws -> TestProcessResult {
        try ProcessTestSupport.run(
            executable: "/bin/zsh",
            arguments: [fixture.appendingPathComponent("scripts/package-release-dmg.sh").path],
            environment: [
                "HDIUTIL": fixture.appendingPathComponent("tools/hdiutil").path,
                "CODESIGN": fixture.appendingPathComponent("tools/codesign").path,
                "DITTO": fixture.appendingPathComponent("tools/ditto").path,
                "CODESIGN_IDENTITY": "Drift",
                "TOOL_LOG": fixture.appendingPathComponent("tool.log").path
            ],
            currentDirectory: fixture
        )
    }

    private func makeExecutable(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
