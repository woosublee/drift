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
                "LOCAL_CERTIFICATE_IDENTITY=Drift",
                "SPARKLE_KEYCHAIN_SERVICE=https://sparkle-project.org",
                "SPARKLE_ACCOUNT=com.woosublee.drift.sparkle.ed25519"
            ]
        )
        XCTAssertFalse(result.output.contains("PRIVATE"))
    }

    func testCertificateProvisioningAvoidsGlobalKeychainMutationAndChecksFullProfile() throws {
        let makefile = try sourceMakefile()
        let createTarget = try makeTarget(named: "create-local-certificate", in: makefile)
        let checkTarget = try makeTarget(named: "check-local-certificate", in: makefile)

        XCTAssertFalse(createTarget.contains("set-key-partition-list"))
        XCTAssertFalse(createTarget.contains("|| true"))
        XCTAssertTrue(createTarget.contains("-T /usr/bin/codesign"))
        XCTAssertTrue(checkTarget.contains("datetime.timedelta(days=3650)"))
        XCTAssertTrue(checkTarget.contains("extension_value(\"Basic Constraints\") == \"CA:FALSE\""))
        XCTAssertTrue(checkTarget.contains("extension_value(\"Key Usage\") == \"Digital Signature\""))
        XCTAssertTrue(checkTarget.contains("extension_value(\"Extended Key Usage\") == \"Code Signing\""))
    }

    func testCertificateVerificationBindsProfileToUsableIdentityFingerprintOverSameCNDecoy() throws {
        let fixture = try makeFixture()
        let tools = try fakeCertificateTools()
        let result = try ProcessTestSupport.run(
            executable: "/usr/bin/make",
            arguments: [
                "-s",
                "check-local-certificate",
                "SECURITY=\(tools.security.path)",
                "CODESIGN=\(tools.codesign.path)"
            ],
            environment: [
                "FAKE_VALID_FINGERPRINT": validCertificateFingerprint,
                "FAKE_VALID_CERTIFICATE": tools.validCertificate.path,
                "FAKE_DECOY_CERTIFICATE": tools.decoyCertificate.path,
                "FAKE_CODESIGN_LOG": tools.codesignLog.path
            ],
            currentDirectory: fixture
        )

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertEqual(
            try String(contentsOf: tools.codesignLog)
                .split(separator: "\n")
                .map(String.init)
                .count,
            2
        )
    }

    func testOptimizedPythonRejectsInvalidCertificateProfileBeforeSigningProbe() throws {
        let fixture = try makeFixture()
        let tools = try fakeCertificateTools()
        let result = try ProcessTestSupport.run(
            executable: "/usr/bin/make",
            arguments: [
                "-s",
                "check-local-certificate",
                "SECURITY=\(tools.security.path)",
                "CODESIGN=\(tools.codesign.path)"
            ],
            environment: [
                "PYTHONOPTIMIZE": "1",
                "FAKE_VALID_FINGERPRINT": try certificateFingerprint(for: tools.decoyCertificate),
                "FAKE_VALID_CERTIFICATE": tools.decoyCertificate.path,
                "FAKE_DECOY_CERTIFICATE": tools.validCertificate.path,
                "FAKE_CODESIGN_LOG": tools.codesignLog.path
            ],
            currentDirectory: fixture
        )

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertFalse(result.output.contains("Code signing identity works"), result.output)
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

    private func sourceMakefile() throws -> String {
        try String(contentsOf: ProcessTestSupport.sourceRoot(filePath: #filePath).appendingPathComponent("Makefile"))
    }

    private func makeTarget(named name: String, in makefile: String) throws -> String {
        let marker = "\(name):"
        let start = try XCTUnwrap(makefile.range(of: marker))
        let remainder = makefile[start.lowerBound...]
        let end = remainder.range(of: "\n\n")?.lowerBound ?? remainder.endIndex
        return String(remainder[..<end])
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

    private func certificateFingerprint(for certificate: URL) throws -> String {
        let result = try ProcessTestSupport.run(
            executable: "/usr/bin/openssl",
            arguments: ["x509", "-in", certificate.path, "-noout", "-fingerprint", "-sha1"]
        )
        XCTAssertEqual(result.status, 0, result.output)
        let fingerprint = try XCTUnwrap(result.output.split(separator: "=").last)
        return fingerprint.replacingOccurrences(of: ":", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func fakeCertificateTools() throws -> FakeCertificateTools {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DriftReleaseCredentialTests-\(UUID().uuidString)-certificates", isDirectory: true)
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        addTeardownBlock {
            try? fileManager.removeItem(at: directory)
        }

        let validCertificate = directory.appendingPathComponent("valid.pem")
        let decoyCertificate = directory.appendingPathComponent("decoy.pem")
        let codesignLog = directory.appendingPathComponent("codesign.log")
        try validCertificatePEM.write(to: validCertificate, atomically: true, encoding: .utf8)
        try decoyCertificatePEM.write(to: decoyCertificate, atomically: true, encoding: .utf8)

        let security = try executable(
            named: "certificate-security",
            contents: "#!/bin/sh\ncase \"$1\" in\n  find-identity)\n    printf '  1) %s \"Drift\"\\n' \"$FAKE_VALID_FINGERPRINT\"\n    printf '     1 valid identities found\\n'\n    ;;\n  find-certificate)\n    cat \"$FAKE_DECOY_CERTIFICATE\" \"$FAKE_VALID_CERTIFICATE\"\n    ;;\n  *) exit 1 ;;\nesac\n"
        )
        let codesign = try executable(
            named: "codesign",
            contents: "#!/bin/sh\nprintf '%s\\n' \"$*\" >> \"$FAKE_CODESIGN_LOG\"\n"
        )
        return FakeCertificateTools(
            security: security,
            codesign: codesign,
            validCertificate: validCertificate,
            decoyCertificate: decoyCertificate,
            codesignLog: codesignLog
        )
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

    private let validCertificateFingerprint = "8504C2D9FBCA57F5D1A407A3C17F29BC1DB94051"

    private let validCertificatePEM = """
    -----BEGIN CERTIFICATE-----
    MIIDBTCCAe2gAwIBAgIUbt2NgOxLTQFif4dSeGCnmrVhbq8wDQYJKoZIhvcNAQEL
    BQAwEDEOMAwGA1UEAwwFRHJpZnQwHhcNMjYwODA4MTU1MzE5WhcNMzYwODA1MTU1
    MzE5WjAQMQ4wDAYDVQQDDAVEcmlmdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCC
    AQoCggEBAK7glTbbPd8/oVHBhQVdkGv+WzwzvshVwgGen3Tp6S4k21kx+3hY/QKV
    An0s6j/mZEnCpT0m6YdLS2bZz+fLRSLAcmrmOvAf7PpKcTSoEiio6F9zjbslr7sL
    YzqhmFr6C1oziyG3c7p3e4UZzzwKfZ7d1WgAy8qPSpCSm0H6msU3GgVO/5S3HrDL
    Ny++p6CvF5VKgVuxyvGA+694W3hKV2pvV1+rkymGIcbz6+2JnRTIyXAZoAfduv3d
    1I+4IYVQcZCdQw3gr0x+/bRVO488VhB6rrR8JraxILyZNQWYDu5nLHJfinEiQ637
    jzvdaaXEITYyskgRO72/LUsfRMBfj3ECAwEAAaNXMFUwDAYDVR0TAQH/BAIwADAO
    BgNVHQ8BAf8EBAMCB4AwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwMwHQYDVR0OBBYE
    FHJm31Q57J2xmNvg+2kfcN3xL8NBMA0GCSqGSIb3DQEBCwUAA4IBAQB4/tjrfoHU
    AYke9fEb4dwMFXcDswYV7S0UeH8Goi695aw79tcEYdsCOs77EMSmwS2auEnMhlbi
    xFUzmmP7PGJnGWQ4dAFS5chAr3g21LnDbCL5Z24iJErhqFEuCWu0Dpk7G+qczsxP
    DGoAsTZmN3ESVu+wPNl43n1EYHRFMcm5aYjAjL6nTjngRVV8/68zCZQYF8YldIwn
    Ri0eISQwuBOo9x/2SXkbUAe/qaBmA8GKTC9Cv3rt8/IzkPiTBMCjAGcPXb3Xy2BX
    a5AATeagaAF/XI5B8yvFZV4aRy1cXnbxZgDU4d6/qwa4yX33vN7YI/o4crbGgwYC
    qSdTprEjl3zJ
    -----END CERTIFICATE-----
    """

    private let decoyCertificatePEM = """
    -----BEGIN CERTIFICATE-----
    MIIDCDCCAfCgAwIBAgIUYI3DISNjJUm7LOd5yATvLts09bkwDQYJKoZIhvcNAQEL
    BQAwEDEOMAwGA1UEAwwFRHJpZnQwHhcNMjYwODA4MTU1MzE5WhcNMzYwODA1MTU1
    MzE5WjAQMQ4wDAYDVQQDDAVEcmlmdDCCASIwDQYJKoZIhvcNAQEBBQADggEPADCC
    AQoCggEBAJZPJ7XewgjAnPPGmxfVY+Ehy2TOx2VGKM0m/MxUHr6UbVEiSMc2efTP
    AAPaGZ9Dy2ckEnBcaQqN+PYT0YRF+hRNpMy8VdVy8N4BnfhVsu+wN0Vuaxh5AM12
    PdRsWvNM1fPOUgc8lwD+8Qc4zgZrsqnGNCBk5w08agg9ejmQlJ6skmf1QdYkSBvg
    TVngZ4itvobb4X4Aczb1PzkjgTTH7J95g0zFC1aNYjR9NITm1IH7he/5ZCl7FlHN
    ANFfOUwAdrtYEJxytKvqPbq51nA1BoQbhbLqTVLmvNYBN5iCZk+1XC0gwJb0BF2i
    TD/7l8y177xij6Ens39mhjHDh8BqODcCAwEAAaNaMFgwDwYDVR0TAQH/BAUwAwEB
    /zAOBgNVHQ8BAf8EBAMCAgQwFgYDVR0lAQH/BAwwCgYIKwYBBQUHAwMwHQYDVR0O
    BBYEFK1yguCX6HGkoYuaQry3XzEIyjRbMA0GCSqGSIb3DQEBCwUAA4IBAQCVPnfM
    6aErlDjnQP5+f5j0litijYxcuHBt9dxvx2zxDZ79PWQ0Y+mCIvk8/JytryhiIEgl
    FyLJlPaqvySUo4sG3UP3JUXRCwJwl9u8MxfPbPiRtpgnYVkqef5dkJbdXX23XLWF
    9An09HkaPvS2rlxMyH9uGujHqJ6wsb58tG/kQ9H0+UjrjvNT8dvKap1YM8fpiPAg
    vFUVhTLnkcKKEHUhV8RPFHHk6vq6b5mh+2M7coXxWwsMunmJyuV58fdQtxMo7PI3
    QZE45d0KGvKQ/5R0rR436Rd9FZz8GCvaS2WQUT6hkRHtO0rYdHpW4OCWC7hoaOq0
    AYeKnY2F+suKwzp7
    -----END CERTIFICATE-----
    """
}

private struct FakeTools {
    let swift: URL
    let security: URL
    let generator: URL
    let state: URL
}

private struct FakeCertificateTools {
    let security: URL
    let codesign: URL
    let validCertificate: URL
    let decoyCertificate: URL
    let codesignLog: URL
}
