import Foundation
import XCTest

final class BundleSigningMetadataTests: XCTestCase {
    func testSigningMetadataGuardRejectsForbiddenFinderAndFileProviderAttributes() throws {
        let fixture = FileManager.default.temporaryDirectory
            .appendingPathComponent("BundleSigningMetadataTests-\(UUID().uuidString).app")
        try FileManager.default.createDirectory(at: fixture, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: fixture) }

        _ = try run("/usr/bin/xattr", arguments: [
            "-w", "com.apple.FinderInfo", "fixture", fixture.path
        ])
        _ = try run("/usr/bin/xattr", arguments: [
            "-w", "com.apple.fileprovider.fpfs#P", "fixture", fixture.path
        ])

        let result = try run(metadataGuard.path, arguments: [fixture.path])

        XCTAssertEqual(result.status, 1)
        XCTAssertTrue(result.standardError.contains("Forbidden signing metadata"))
    }

    func testMakefileRunsMetadataGuardAfterFrameworkSigningBeforeAppSigning() throws {
        let makefile = try String(contentsOf: sourceRoot.appendingPathComponent("Makefile"))
        let frameworkSigning = "codesign --force --options runtime --sign \"$(CODESIGN_IDENTITY)\" \"$(FRAMEWORKS_DIR)/Sparkle.framework\""
        let cleanup = "find \"$(APP_DIR)\" -depth -exec xattr -d com.apple.FinderInfo"
        let guardDefinition = "VERIFY_SIGNING_XATTRS := scripts/verify-bundle-signing-xattrs.sh"
        let guardInvocation = "$(SHELL) $(VERIFY_SIGNING_XATTRS) \"$(APP_DIR)\""
        let appSigning = "--entitlements \"$(ENTITLEMENTS)\" \"$(APP_DIR)\""

        let frameworkIndex = try XCTUnwrap(makefile.range(of: frameworkSigning)?.lowerBound)
        let cleanupIndex = try XCTUnwrap(makefile.range(of: cleanup)?.lowerBound)
        XCTAssertNotNil(makefile.range(of: guardDefinition))
        let guardIndex = try XCTUnwrap(makefile.range(of: guardInvocation)?.lowerBound)
        let appSigningIndex = try XCTUnwrap(makefile.range(of: appSigning)?.lowerBound)

        XCTAssertLessThan(frameworkIndex, cleanupIndex)
        XCTAssertLessThan(cleanupIndex, guardIndex)
        XCTAssertLessThan(guardIndex, appSigningIndex)
    }

    func testMakefileCleansSigningMetadataAfterFinalAppSigningBeforeGuardAndVerification() throws {
        let makefile = try String(contentsOf: sourceRoot.appendingPathComponent("Makefile"))
        let appSigning = "--entitlements \"$(ENTITLEMENTS)\" \"$(APP_DIR)\""
        let finderInfoCleanup = "find \"$(APP_DIR)\" -depth -exec xattr -d com.apple.FinderInfo"
        let fileProviderCleanup = "find \"$(APP_DIR)\" -depth -exec xattr -d 'com.apple.fileprovider.fpfs#P'"
        let guardInvocation = "$(SHELL) $(VERIFY_SIGNING_XATTRS) \"$(APP_DIR)\""
        let verification = "codesign --verify --strict --verbose=2 \"$(APP_DIR)\""

        let finalSigningIndex = try XCTUnwrap(
            makefile.range(of: appSigning, options: .backwards)?.lowerBound
        )
        let finalPipeline = String(makefile[finalSigningIndex...])
        let finderInfoCleanupIndex = try XCTUnwrap(finalPipeline.range(of: finderInfoCleanup)?.lowerBound)
        let fileProviderCleanupIndex = try XCTUnwrap(finalPipeline.range(of: fileProviderCleanup)?.lowerBound)
        let guardIndex = try XCTUnwrap(finalPipeline.range(of: guardInvocation)?.lowerBound)
        let verificationIndex = try XCTUnwrap(finalPipeline.range(of: verification)?.lowerBound)

        XCTAssertLessThan(finderInfoCleanupIndex, guardIndex)
        XCTAssertLessThan(fileProviderCleanupIndex, guardIndex)
        XCTAssertLessThan(guardIndex, verificationIndex)
    }

    func testMakefileBuildsVariantAwareBundleUnderConfigurableTemporaryDirectory() throws {
        let makefile = try String(contentsOf: sourceRoot.appendingPathComponent("Makefile"))
        let defaultBuildDirectory = "/tmp/drift-bundles/default"

        XCTAssertTrue(makefile.contains("BUILD_DIR ?= \(defaultBuildDirectory)"))
        XCTAssertTrue(makefile.contains("APP_DIR = $(BUILD_DIR)/$(PRODUCT_NAME).app"))
        XCTAssertFalse(defaultBuildDirectory.hasPrefix(sourceRoot.path))
        XCTAssertFalse(defaultBuildDirectory.contains("/Documents/"))
        XCTAssertFalse(makefile.contains("APP_DIR = .build/app/Drift.app"))
    }

    private var metadataGuard: URL {
        sourceRoot.appendingPathComponent("scripts/verify-bundle-signing-xattrs.sh")
    }

    private var sourceRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    private func run(_ executablePath: String, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        try process.run()
        process.waitUntilExit()
        return ProcessResult(
            status: process.terminationStatus,
            standardError: String(
                data: standardError.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            ) ?? ""
        )
    }
}

private struct ProcessResult {
    let status: Int32
    let standardError: String
}
