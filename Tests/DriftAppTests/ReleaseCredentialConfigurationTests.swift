import Foundation
import XCTest

final class ReleaseCredentialConfigurationTests: XCTestCase {
    func testMakefileReportsCanonicalLocalCredentialMetadataExactlyOnceInOrder() throws {
        let root = ProcessTestSupport.sourceRoot(filePath: #filePath)
        let result = try ProcessTestSupport.run(
            executable: "/usr/bin/make",
            arguments: ["-s", "print-release-credential-config"],
            currentDirectory: root
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertEqual(
            result.output.split(separator: "\n").map(String.init),
            [
                "DEVELOPER_ID_IDENTITY=Developer ID Application: Woosub Lee (2L6ZW98RCP)",
                "SPARKLE_KEYCHAIN_SERVICE=https://sparkle-project.org",
                "SPARKLE_ACCOUNT=com.woosublee.drift.sparkle.ed25519"
            ]
        )
        XCTAssertFalse(result.output.contains("PRIVATE"))
    }

    // Break caught: a self-signed or wrong-team identity would sign releases that notarization rejects.
    func testSigningIdentityCheckProbesHardenedTimestampedDeveloperIDSignature() throws {
        let fixture = try makeFixture()
        let tools = try fakeSigningTools(identities: [developerIDIdentity, "Drift"])
        let result = try runSigningIdentityCheck(in: fixture, tools: tools)

        XCTAssertEqual(result.status, 0, result.output)
        let invocations = try String(contentsOf: tools.codesignLog).split(separator: "\n").map(String.init)
        XCTAssertEqual(invocations.count, 2)
        XCTAssertTrue(
            invocations[0].contains("--options runtime --timestamp --sign \(developerIDIdentity)"),
            invocations[0]
        )
    }

    func testSigningIdentityCheckRejectsMissingDeveloperIDIdentity() throws {
        let fixture = try makeFixture()
        let tools = try fakeSigningTools(identities: ["Drift"])
        let result = try runSigningIdentityCheck(in: fixture, tools: tools)

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("found 0"), result.output)
        XCTAssertEqual((try? String(contentsOf: tools.codesignLog)) ?? "", "")
    }

    func testSigningIdentityCheckRejectsNonDeveloperIDOverride() throws {
        let fixture = try makeFixture()
        let tools = try fakeSigningTools(identities: ["Drift"])
        let result = try runSigningIdentityCheck(
            in: fixture,
            tools: tools,
            arguments: ["DEVELOPER_ID_IDENTITY=Drift"]
        )

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("must be a Developer ID Application identity"), result.output)
        XCTAssertEqual((try? String(contentsOf: tools.codesignLog)) ?? "", "")
    }

    func testGenerateEdDSAKeyLeavesFixturePlistUntouchedWhenGenerationFails() throws {
        let fixture = try makeFixture()
        let plistURL = fixture.appendingPathComponent("Info.plist")
        let originalPlist = try Data(contentsOf: plistURL)
        let account = testAccount(suffix: "failure")
        let tools = try fakeTools(
            account: account,
            generatorContents: "#!/bin/sh\nexit 23\n"
        )

        let result = try runGenerateEdDSAKey(
            in: fixture,
            account: account,
            tools: tools
        )

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertFalse(result.output.contains("Created Sparkle EdDSA key"), result.output)
        XCTAssertEqual(try Data(contentsOf: plistURL), originalPlist)
    }

    func testOptimizedPythonLeavesFixturePlistUntouchedWhenGeneratorPublicKeyIsInvalid() throws {
        let fixture = try makeFixture()
        let plistURL = fixture.appendingPathComponent("Info.plist")
        let originalPlist = try Data(contentsOf: plistURL)
        let account = testAccount(suffix: "invalid")
        let tools = try fakeTools(
            account: account,
            generatorContents: "#!/bin/sh\nif [ \"$3\" = \"-p\" ]; then\n  printf '%s\\n' 'invalid-public-key'\nelse\n  : > \"$FAKE_SPARKLE_STATE\"\nfi\n"
        )

        let result = try runGenerateEdDSAKey(
            in: fixture,
            account: account,
            tools: tools,
            environment: ["PYTHONOPTIMIZE": "1"]
        )

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertFalse(result.output.contains("Created Sparkle EdDSA key"), result.output)
        XCTAssertFalse(result.output.contains("Reusing existing Sparkle EdDSA key"), result.output)
        XCTAssertEqual(try Data(contentsOf: plistURL), originalPlist)
    }

    func testOptimizedPythonRejectsMatchingInvalidGeneratorAndPlistKey() throws {
        let fixture = try makeFixture()
        let plistURL = fixture.appendingPathComponent("Info.plist")
        let account = testAccount(suffix: "invalid-check")
        let invalidKey = "invalid-public-key"
        let tools = try fakeTools(
            account: account,
            generatorContents: "#!/bin/sh\nprintf '%s\\n' '\(invalidKey)'\n"
        )
        try Data().write(to: tools.state)
        let plistMutation = try ProcessTestSupport.run(
            executable: "/usr/bin/plutil",
            arguments: ["-replace", "SUPublicEDKey", "-string", invalidKey, plistURL.path],
            currentDirectory: fixture
        )
        XCTAssertEqual(plistMutation.status, 0, plistMutation.output)

        let result = try runCheckEdDSAKey(
            in: fixture,
            account: account,
            tools: tools,
            environment: ["PYTHONOPTIMIZE": "1"]
        )

        XCTAssertNotEqual(result.status, 0, result.output)
    }

    func testGenerateEdDSAKeyAtomicallyUpdatesFixturePlistAfterValidatingPublicKey() throws {
        let fixture = try makeFixture()
        let plistURL = fixture.appendingPathComponent("Info.plist")
        let originalPlist = try Data(contentsOf: plistURL)
        let account = testAccount(suffix: "valid")
        let publicKey = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
        let tools = try fakeTools(
            account: account,
            generatorContents: "#!/bin/sh\nif [ \"$3\" = \"-p\" ]; then\n  printf '%s\\n' '\(publicKey)'\nelse\n  : > \"$FAKE_SPARKLE_STATE\"\nfi\n"
        )

        let result = try runGenerateEdDSAKey(
            in: fixture,
            account: account,
            tools: tools
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertTrue(result.output.contains("Created Sparkle EdDSA key"), result.output)
        XCTAssertNotEqual(try Data(contentsOf: plistURL), originalPlist)
        let plistData = try Data(contentsOf: plistURL)
        let plist = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: plistData, format: nil) as? [String: Any]
        )
        XCTAssertEqual(plist["SUPublicEDKey"] as? String, publicKey)
    }

    private func runGenerateEdDSAKey(
        in fixture: URL,
        account: String,
        tools: FakeTools,
        environment: [String: String] = [:]
    ) throws -> TestProcessResult {
        try runEdDSAKeyTarget(
            "generate-eddsa-key",
            in: fixture,
            account: account,
            tools: tools,
            environment: environment
        )
    }

    private func runCheckEdDSAKey(
        in fixture: URL,
        account: String,
        tools: FakeTools,
        environment: [String: String] = [:]
    ) throws -> TestProcessResult {
        try runEdDSAKeyTarget(
            "check-eddsa-key",
            in: fixture,
            account: account,
            tools: tools,
            environment: environment
        )
    }

    private func runEdDSAKeyTarget(
        _ target: String,
        in fixture: URL,
        account: String,
        tools: FakeTools,
        environment: [String: String]
    ) throws -> TestProcessResult {
        try ProcessTestSupport.run(
            executable: "/usr/bin/make",
            arguments: [
                "-s",
                target,
                "SPARKLE_ACCOUNT=\(account)",
                "SPARKLE_GENERATE_KEYS=\(tools.generator.path)",
                "SWIFT=\(tools.swift.path)",
                "SECURITY=\(tools.security.path)"
            ],
            environment: [
                "FAKE_SPARKLE_ACCOUNT": account,
                "FAKE_SPARKLE_STATE": tools.state.path
            ].merging(environment) { _, new in new },
            currentDirectory: fixture
        )
    }

    private func makeFixture() throws -> URL {
        let root = ProcessTestSupport.sourceRoot(filePath: #filePath)
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("DriftReleaseCredentialTests-\(UUID().uuidString)", isDirectory: true)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: fixture, withIntermediateDirectories: true)
        addTeardownBlock {
            try? fileManager.removeItem(at: fixture)
        }

        for path in ["Makefile", "Info.plist"] {
            try fileManager.copyItem(at: root.appendingPathComponent(path), to: fixture.appendingPathComponent(path))
        }
        return fixture
    }

    private func runSigningIdentityCheck(
        in fixture: URL,
        tools: FakeSigningTools,
        arguments: [String] = []
    ) throws -> TestProcessResult {
        try ProcessTestSupport.run(
            executable: "/usr/bin/make",
            arguments: [
                "-s",
                "check-signing-identity",
                "SECURITY=\(tools.security.path)",
                "CODESIGN=\(tools.codesign.path)"
            ] + arguments,
            environment: ["FAKE_CODESIGN_LOG": tools.codesignLog.path],
            currentDirectory: fixture
        )
    }

    private func fakeSigningTools(identities: [String]) throws -> FakeSigningTools {
        let listing = identities.enumerated()
            .map { index, name in "  \(index + 1)) \(String(repeating: "A", count: 40)) \"\(name)\"" }
            .joined(separator: "\n")
        let codesignLog = FileManager.default.temporaryDirectory
            .appendingPathComponent("DriftReleaseCredentialTests-\(UUID().uuidString)-codesign.log")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: codesignLog)
        }
        let security = try executable(
            named: "signing-security",
            contents: "#!/bin/sh\n[ \"$1\" = find-identity ] || exit 1\ncat <<'EOF'\n\(listing)\n     \(identities.count) valid identities found\nEOF\n"
        )
        let codesign = try executable(
            named: "codesign",
            contents: "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$FAKE_CODESIGN_LOG\"\n"
        )
        return FakeSigningTools(security: security, codesign: codesign, codesignLog: codesignLog)
    }

    private func fakeTools(account: String, generatorContents: String) throws -> FakeTools {
        let state = FileManager.default.temporaryDirectory
            .appendingPathComponent("DriftReleaseCredentialTests-\(UUID().uuidString)-sparkle-state")
        let swift = try executable(named: "swift", contents: "#!/bin/sh\nexit 0\n")
        let security = try executable(
            named: "security",
            contents: "#!/bin/sh\naccount=''\nwhile [ \"$#\" -gt 0 ]; do\n  case \"$1\" in\n    -a) account=\"$2\"; shift 2 ;;\n    *) shift ;;\n  esac\ndone\nif [ \"$account\" = \"$FAKE_SPARKLE_ACCOUNT\" ] && [ -f \"$FAKE_SPARKLE_STATE\" ]; then\n  exit 0\nfi\nexit 1\n"
        )
        let generator = try executable(named: "generate-keys", contents: generatorContents)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: state)
        }
        return FakeTools(swift: swift, security: security, generator: generator, state: state)
    }

    private func executable(named name: String, contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DriftReleaseCredentialTests-\(UUID().uuidString)-\(name)")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func testAccount(suffix: String) -> String {
        "com.woosublee.drift.sparkle.test.\(suffix).\(UUID().uuidString)"
    }

    private let developerIDIdentity = "Developer ID Application: Woosub Lee (2L6ZW98RCP)"
}

private struct FakeTools {
    let swift: URL
    let security: URL
    let generator: URL
    let state: URL
}

private struct FakeSigningTools {
    let security: URL
    let codesign: URL
    let codesignLog: URL
}
