import Foundation
import XCTest

final class ReleaseBuildTests: XCTestCase {
    func testUniversalBuilderUsesBothMacOSTriplesAndLiposTheirExecutables() throws {
        let fixture = try makeUniversalBuildFixture()
        let builder = fixture.appendingPathComponent("scripts/build-universal-app.sh")
        guard FileManager.default.fileExists(atPath: builder.path) else {
            XCTFail("Universal release builder is missing")
            return
        }

        let result = try runUniversalBuilder(in: fixture)

        XCTAssertEqual(result.status, 0, result.output)
        let log = try String(contentsOf: fixture.appendingPathComponent("tool.log"))
        XCTAssertTrue(log.contains("--triple arm64-apple-macosx13.0"))
        XCTAssertTrue(log.contains("--triple x86_64-apple-macosx13.0"))
        XCTAssertTrue(log.contains("lipo -create"))
        XCTAssertTrue(log.contains("bundle-prebuilt"))
        XCTAssertTrue(log.contains("PREBUILT_EXECUTABLE="))
        XCTAssertTrue(log.contains("SPARKLE_FEED_URL=https://github.com/woosublee/drift/releases/latest/download/appcast.xml"))
    }

    func testReleaseSigningAppliesHardenedRuntimeToNestedCodeAndApp() throws {
        let makefile = try String(contentsOf: sourceRoot.appendingPathComponent("Makefile"))
        let helperStart = try XCTUnwrap(makefile.range(of: "function sign_if_present()")?.lowerBound)
        let frameworkStart = try XCTUnwrap(
            makefile.range(of: "framework=\"$(FRAMEWORKS_DIR)/Sparkle.framework/Versions/B\"")?.lowerBound
        )
        let helper = String(makefile[helperStart..<frameworkStart])

        XCTAssertTrue(
            helper.contains("codesign --force --options runtime --sign \"$(CODESIGN_IDENTITY)\" \"$$1\"")
        )
        for path in [
            "$$framework/XPCServices/Installer.xpc",
            "$$framework/XPCServices/Downloader.xpc",
            "$$framework/Autoupdate",
            "$$framework/Updater.app"
        ] {
            XCTAssertTrue(
                makefile.contains("sign_if_present \"\(path)\""),
                "Missing nested hardened-runtime signing path: \(path)"
            )
        }
        XCTAssertTrue(
            makefile.contains(
                "codesign --force --options runtime --sign \"$(CODESIGN_IDENTITY)\" \"$(FRAMEWORKS_DIR)/Sparkle.framework\""
            )
        )
        XCTAssertTrue(
            makefile.contains(
                "codesign --force --options runtime --sign \"$(CODESIGN_IDENTITY)\" \\\n\t\t\t--entitlements \"$(ENTITLEMENTS)\" \"$(APP_DIR)\""
            )
        )
    }

    // Break caught: self-signed app and Sparkle signatures have no Apple Team ID,
    // so Hardened Runtime rejects Sparkle unless the host carries this entitlement.
    func testReleaseEntitlementsAllowBundledSparkleToLoad() throws {
        let entitlementsURL = sourceRoot.appendingPathComponent("Drift.entitlements")
        let data = try Data(contentsOf: entitlementsURL)
        let value = try PropertyListSerialization.propertyList(from: data, format: nil)
        let entitlements = try XCTUnwrap(value as? [String: Any])

        XCTAssertEqual(
            entitlements["com.apple.security.cs.disable-library-validation"] as? Bool,
            true
        )
    }

    func testGitignoreExcludesReleaseBuildArtifacts() throws {
        let gitignore = try String(contentsOf: sourceRoot.appendingPathComponent(".gitignore"))

        XCTAssertTrue(gitignore.split(separator: "\n").contains("build/"))
    }

    private var sourceRoot: URL {
        ProcessTestSupport.sourceRoot(filePath: #filePath)
    }

    private func makeUniversalBuildFixture() throws -> URL {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReleaseBuildTests-\(UUID().uuidString)", isDirectory: true)
        let scripts = fixture.appendingPathComponent("scripts", isDirectory: true)
        let release = fixture.appendingPathComponent("release", isDirectory: true)
        let tools = fixture.appendingPathComponent("tools", isDirectory: true)
        let fileManager = FileManager.default

        try fileManager.createDirectory(at: scripts, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: release, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tools, withIntermediateDirectories: true)

        try fileManager.copyItem(
            at: sourceRoot.appendingPathComponent("Info.plist"),
            to: fixture.appendingPathComponent("Info.plist")
        )
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

        let builder = sourceRoot.appendingPathComponent("scripts/build-universal-app.sh")
        if fileManager.fileExists(atPath: builder.path) {
            let destination = scripts.appendingPathComponent("build-universal-app.sh")
            try fileManager.copyItem(at: builder, to: destination)
            try makeExecutable(destination)
        }

        let verifier = scripts.appendingPathComponent("verify-app-bundle.sh")
        try """
        #!/bin/zsh
        print -r -- "verify $*" >> "$TOOL_LOG"
        """.write(to: verifier, atomically: true, encoding: .utf8)
        try makeExecutable(verifier)

        try """
        #!/bin/zsh
        print -r -- "swift $*" >> "$TOOL_LOG"
        scratch=""
        args=("$@")
        for (( index = 1; index <= $#; index++ )); do
            if [[ "${args[$index]}" == "--scratch-path" ]]; then
                scratch="${args[$((index + 1))]}"
            fi
        done
        [[ -n "$scratch" ]]
        mkdir -p "$scratch/bin/Sparkle.framework"
        print -r -- '#!/bin/zsh' > "$scratch/bin/Drift"
        chmod +x "$scratch/bin/Drift"
        if [[ " $* " == *" --show-bin-path "* ]]; then
            print -r -- "$scratch/bin"
        fi
        """.write(
            to: tools.appendingPathComponent("swift"),
            atomically: true,
            encoding: .utf8
        )
        try makeExecutable(tools.appendingPathComponent("swift"))

        try """
        #!/bin/zsh
        print -r -- "lipo $*" >> "$TOOL_LOG"
        if [[ "$1" == "-archs" ]]; then
            print -r -- "x86_64 arm64"
            exit 0
        fi
        output=""
        args=("$@")
        for (( index = 1; index <= $#; index++ )); do
            if [[ "${args[$index]}" == "-output" ]]; then
                output="${args[$((index + 1))]}"
            fi
        done
        mkdir -p "${output:h}"
        cp "$2" "$output"
        """.write(
            to: tools.appendingPathComponent("lipo"),
            atomically: true,
            encoding: .utf8
        )
        try makeExecutable(tools.appendingPathComponent("lipo"))

        try """
        #!/bin/zsh
        print -r -- "make $*" >> "$TOOL_LOG"
        build_dir=""
        executable=""
        framework=""
        for argument in "$@"; do
            case "$argument" in
                BUILD_DIR=*) build_dir="${argument#BUILD_DIR=}" ;;
                PREBUILT_EXECUTABLE=*) executable="${argument#PREBUILT_EXECUTABLE=}" ;;
                PREBUILT_SPARKLE_FRAMEWORK=*) framework="${argument#PREBUILT_SPARKLE_FRAMEWORK=}" ;;
            esac
        done
        [[ -n "$build_dir" && -n "$executable" && -n "$framework" ]]
        app="$build_dir/Drift.app"
        mkdir -p "$app/Contents/MacOS" "$app/Contents/Frameworks"
        cp "$executable" "$app/Contents/MacOS/Drift"
        cp -R "$framework" "$app/Contents/Frameworks/Sparkle.framework"
        """.write(
            to: tools.appendingPathComponent("make"),
            atomically: true,
            encoding: .utf8
        )
        try makeExecutable(tools.appendingPathComponent("make"))

        addTeardownBlock {
            try? fileManager.removeItem(at: fixture)
        }
        return fixture
    }

    private func runUniversalBuilder(in fixture: URL) throws -> TestProcessResult {
        try ProcessTestSupport.run(
            executable: "/bin/zsh",
            arguments: [fixture.appendingPathComponent("scripts/build-universal-app.sh").path],
            environment: [
                "SWIFT": fixture.appendingPathComponent("tools/swift").path,
                "LIPO": fixture.appendingPathComponent("tools/lipo").path,
                "MAKE": fixture.appendingPathComponent("tools/make").path,
                "TOOL_LOG": fixture.appendingPathComponent("tool.log").path
            ],
            currentDirectory: fixture
        )
    }

    private func makeExecutable(_ url: URL) throws {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }
}
