import XCTest

final class BuildIdentityScriptTests: XCTestCase {
    func testDebugDefaultsToDevelopmentIdentity() throws {
        XCTAssertEqual(try value(configuration: "debug", variant: "", field: "variant"), "dev")
        XCTAssertEqual(try value(configuration: "debug", variant: "", field: "product-name"), "Drift Dev")
        XCTAssertEqual(try value(configuration: "debug", variant: "", field: "bundle-id"), "com.woosublee.drift.dev")
        XCTAssertEqual(
            try value(configuration: "debug", variant: "", field: "accessibility-description"),
            "Drift Dev needs Accessibility access to move the pointer."
        )
    }

    func testReleaseDefaultsToProductionIdentity() throws {
        XCTAssertEqual(try value(configuration: "release", variant: "", field: "variant"), "production")
        XCTAssertEqual(try value(configuration: "release", variant: "", field: "product-name"), "Drift")
        XCTAssertEqual(try value(configuration: "release", variant: "", field: "bundle-id"), "com.woosublee.drift")
    }

    func testExplicitVariantOverridesCompilerConfiguration() throws {
        XCTAssertEqual(try value(configuration: "release", variant: "dev", field: "product-name"), "Drift Dev")
        XCTAssertEqual(try value(configuration: "debug", variant: "production", field: "product-name"), "Drift")
    }

    func testUnsupportedConfigurationFailsWithBothExplicitVariants() throws {
        for variant in ["dev", "production"] {
            let result = try run(configuration: "profile", variant: variant, field: "variant")

            XCTAssertNotEqual(result.status, 0, result.output)
            XCTAssertTrue(result.output.contains("CONFIGURATION must be debug or release"), result.output)
        }
    }

    func testInvalidVariantFails() throws {
        let result = try run(configuration: "debug", variant: "preview", field: "variant")

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("APP_VARIANT must be production or dev"))
    }

    func testBundleVerifierRequiresVariantAwareIdentityArguments() throws {
        let root = ProcessTestSupport.sourceRoot(filePath: #filePath)
        let result = try ProcessTestSupport.run(
            executable: "/bin/zsh",
            arguments: [root.appendingPathComponent("scripts/verify-app-bundle.sh").path],
            currentDirectory: root
        )

        XCTAssertEqual(result.status, 2)
        XCTAssertTrue(
            result.output.contains(
                "<development|production-unconfigured|production-configured> <bundle-id> <product-name>"
            )
        )
    }

    // Break caught: bundle verification can drift from the canonical Sparkle public-key format rules.
    func testBundleVerifierUsesCanonicalSparklePublicKeyValidation() throws {
        let root = ProcessTestSupport.sourceRoot(filePath: #filePath)
        let verifier = try String(
            contentsOf: root.appendingPathComponent("scripts/verify-app-bundle.sh"),
            encoding: .utf8
        )

        XCTAssertTrue(verifier.contains("source \"$script_dir/release-version-lib.sh\""))
        XCTAssertTrue(verifier.contains("release_validate_sparkle_public_key \"$key\""))
        XCTAssertFalse(verifier.contains("import base64"))
    }

    func testOptimizedPythonRejectsInvalidConfiguredProductionKeyDuringAssembly() throws {
        let fixture = try assemblyFixture()
        let result = try makeApp(
            in: fixture,
            publicKey: invalidPublicKey,
            environment: ["PYTHONOPTIMIZE": "1"]
        )

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains(publicKeyValidationError), result.output)
    }

    func testOptimizedPythonRejectsInvalidConfiguredProductionKeyDuringVerification() throws {
        let fixture = try assemblyFixture()
        let assembly = try makeApp(in: fixture)
        XCTAssertEqual(assembly.status, 0, assembly.output)

        let app = fixture.buildDirectory.appendingPathComponent("Drift.app")
        let plist = app.appendingPathComponent("Contents/Info.plist")
        let plistMutation = try ProcessTestSupport.run(
            executable: "/usr/bin/plutil",
            arguments: ["-replace", "SUPublicEDKey", "-string", invalidPublicKey, plist.path],
            currentDirectory: fixture.root
        )
        XCTAssertEqual(plistMutation.status, 0, plistMutation.output)

        let root = ProcessTestSupport.sourceRoot(filePath: #filePath)
        let result = try ProcessTestSupport.run(
            executable: "/bin/zsh",
            arguments: [
                root.appendingPathComponent("scripts/verify-app-bundle.sh").path,
                app.path,
                "production-configured",
                "com.woosublee.drift",
                "Drift"
            ],
            environment: fixture.environment.merging(["PYTHONOPTIMIZE": "1"]) { _, new in new },
            currentDirectory: fixture.root
        )

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains(publicKeyValidationError), result.output)
    }

    private func value(configuration: String, variant: String, field: String) throws -> String {
        let result = try run(configuration: configuration, variant: variant, field: field)
        XCTAssertEqual(result.status, 0, result.output)
        return result.output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func run(configuration: String, variant: String, field: String) throws -> TestProcessResult {
        let root = ProcessTestSupport.sourceRoot(filePath: #filePath)
        return try ProcessTestSupport.run(
            executable: "/bin/zsh",
            arguments: [
                root.appendingPathComponent("scripts/resolve-build-identity.sh").path,
                configuration,
                variant,
                field
            ],
            currentDirectory: root
        )
    }

    private func makeApp(
        in fixture: AssemblyFixture,
        publicKey: String? = nil,
        environment: [String: String] = [:]
    ) throws -> TestProcessResult {
        var arguments = [
            "-s",
            "app",
            "CONFIGURATION=release",
            "BUILD_DIR=\(fixture.buildDirectory.path)",
            "CODESIGN_IDENTITY=-",
            "SWIFT=\(fixture.swift.path)",
            "SPARKLE_FEED_URL=https://example.com/appcast.xml"
        ]
        if let publicKey {
            arguments.append("SPARKLE_PUBLIC_ED_KEY=\(publicKey)")
        }
        return try ProcessTestSupport.run(
            executable: "/usr/bin/make",
            arguments: arguments,
            environment: fixture.environment.merging(environment) { _, new in new },
            currentDirectory: fixture.root
        )
    }

    private func assemblyFixture() throws -> AssemblyFixture {
        let sourceRoot = ProcessTestSupport.sourceRoot(filePath: #filePath)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("BuildIdentityScriptTests-\(UUID().uuidString)", isDirectory: true)
        let scripts = root.appendingPathComponent("scripts", isDirectory: true)
        let bin = root.appendingPathComponent("bin", isDirectory: true)
        let tools = root.appendingPathComponent("tools", isDirectory: true)
        let framework = bin.appendingPathComponent("Sparkle.framework", isDirectory: true)
        let buildDirectory = root.appendingPathComponent("build", isDirectory: true)
        let fileManager = FileManager.default

        try fileManager.createDirectory(at: scripts, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: framework, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: tools, withIntermediateDirectories: true)
        try fileManager.copyItem(at: sourceRoot.appendingPathComponent("Makefile"), to: root.appendingPathComponent("Makefile"))
        try fileManager.copyItem(at: sourceRoot.appendingPathComponent("Info.plist"), to: root.appendingPathComponent("Info.plist"))
        let release = root.appendingPathComponent("release", isDirectory: true)
        try fileManager.createDirectory(at: release, withIntermediateDirectories: true)
        try fileManager.copyItem(
            at: sourceRoot.appendingPathComponent("release/version.json"),
            to: release.appendingPathComponent("version.json")
        )
        for script in [
            "resolve-build-identity.sh",
            "release-version-lib.sh",
            "resolve-release-version.sh",
            "sync-release-version.sh",
            "verify-bundle-signing-xattrs.sh"
        ] {
            try fileManager.copyItem(
                at: sourceRoot.appendingPathComponent("scripts/\(script)"),
                to: scripts.appendingPathComponent(script)
            )
        }

        let executable = bin.appendingPathComponent("Drift")
        try "#!/bin/zsh\nexit 0\n".write(to: executable, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)

        let swift = try writeExecutable(
            named: "swift",
            contents: "#!/bin/zsh\nif [[ \"$*\" == *--show-bin-path* ]]; then\n    print -r -- \"$FAKE_BIN_DIR\"\nfi\n",
            in: tools
        )
        _ = try writeExecutable(
            named: "codesign",
            contents: "#!/bin/zsh\nif [[ \"$*\" == *\"-d -r-\"* ]]; then\n    print -r -- 'designated => identifier \"com.woosublee.drift\"' >&2\nfi\n",
            in: tools
        )
        _ = try writeExecutable(
            named: "otool",
            contents: "#!/bin/zsh\nif [[ \"$1\" == \"-l\" ]]; then\n    print -r -- 'LC_RPATH'\n    print -r -- 'path @executable_path/../Frameworks'\nfi\n",
            in: tools
        )
        _ = try writeExecutable(
            named: "ditto",
            contents: "#!/bin/zsh\nsource=\"${@: -2:1}\"\ndestination=\"${@: -1}\"\ncp -R \"$source\" \"$destination\"\n",
            in: tools
        )

        addTeardownBlock {
            try? fileManager.removeItem(at: root)
        }
        let inheritedPath = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        let path = "\(tools.path):\(inheritedPath)"
        return AssemblyFixture(
            root: root,
            buildDirectory: buildDirectory,
            swift: swift,
            environment: ["FAKE_BIN_DIR": bin.path, "PATH": path]
        )
    }

    private func writeExecutable(named name: String, contents: String, in directory: URL) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private let invalidPublicKey = "not-a-valid-key"
    private let publicKeyValidationError =
        "Sparkle public key must be a 44-character padded Base64 value decoding to 32 bytes"
}

private struct AssemblyFixture {
    let root: URL
    let buildDirectory: URL
    let swift: URL
    let environment: [String: String]
}
