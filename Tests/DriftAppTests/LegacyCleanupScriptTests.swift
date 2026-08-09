import Foundation
import XCTest

final class LegacyCleanupScriptTests: XCTestCase {
    func testRemovesOnlyVerifiedLegacyBundlesAndResetsAccessibility() throws {
        let fixture = try Fixture(bundleID: "com.woosublee.Drift")

        let result = try fixture.run()

        XCTAssertEqual(result.status, 0, result.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.installedApp.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.temporaryApp.path))
        let log = try String(contentsOf: fixture.logURL)
        XCTAssertTrue(log.contains("tccutil reset Accessibility com.woosublee.Drift"))
        XCTAssertTrue(log.contains("lsregister -u"))
    }

    func testUnregisterFailureBlocksDeletionOfAllValidatedLegacyBundles() throws {
        let fixture = try Fixture(bundleID: "com.woosublee.Drift", unregisterFails: true)

        let result = try fixture.run()

        XCTAssertNotEqual(result.status, 0, result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.installedApp.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.temporaryApp.path))
        XCTAssertFalse(result.output.contains("Removed legacy bundle:"), result.output)
        let log = try String(contentsOf: fixture.logURL)
        XCTAssertTrue(log.contains("lsregister -f"), log)
        XCTAssertTrue(log.contains("tccutil reset Accessibility com.woosublee.Drift"), log)
        XCTAssertTrue(log.contains("lsregister -u"), log)
    }

    func testRefusesBundleWithUnexpectedIdentifierBeforeAnyDeletion() throws {
        let fixture = try Fixture(bundleID: "com.example.unrelated")

        let result = try fixture.run()

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.installedApp.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.temporaryApp.path))
        XCTAssertEqual((try? String(contentsOf: fixture.logURL)) ?? "", "")
    }

    func testRefusesDiscoveryFailureBeforeAnyMutation() throws {
        let fixture = try Fixture(bundleID: "com.woosublee.Drift", discoveryFails: true)

        let result = try fixture.run()

        XCTAssertNotEqual(result.status, 0)
        XCTAssertTrue(result.output.contains("BLOCKED: discovery failed"), result.output)
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.installedApp.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.temporaryApp.path))
        XCTAssertEqual((try? String(contentsOf: fixture.logURL)) ?? "", "")
    }
}

private final class Fixture {
    let root: URL
    let installedApp: URL
    let temporaryApp: URL
    let logURL: URL
    var findPath: URL?

    init(
        bundleID: String,
        discoveryFails: Bool = false,
        unregisterFails: Bool = false
    ) throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DriftLegacyCleanupTests-\(UUID().uuidString)")
        self.root = root
        installedApp = root.appendingPathComponent("Applications/Drift.app")
        temporaryApp = root.appendingPathComponent("bundles/dev/Drift.app")
        logURL = root.appendingPathComponent("calls.log")
        try makeBundle(installedApp, bundleID: bundleID)
        try makeBundle(temporaryApp, bundleID: "com.woosublee.Drift")
        try makeTool(named: "tccutil")
        try makeTool(named: "lsregister", unregisterFails: unregisterFails)
        findPath = discoveryFails ? try makeFailingFindTool() : nil
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func run() throws -> TestProcessResult {
        let sourceRoot = ProcessTestSupport.sourceRoot(filePath: #filePath)
        var environment = [
            "LEGACY_INSTALLED_APP": installedApp.path,
            "LEGACY_TEMP_ROOT": root.appendingPathComponent("bundles").path,
            "TCCUTIL_BIN": root.appendingPathComponent("tccutil").path,
            "LSREGISTER_BIN": root.appendingPathComponent("lsregister").path,
            "TEST_LOG": logURL.path
        ]
        if let findPath {
            environment["FIND_BIN"] = findPath.path
        }
        return try ProcessTestSupport.run(
            executable: "/bin/zsh",
            arguments: [sourceRoot.appendingPathComponent("scripts/remove-legacy-drift.sh").path],
            environment: environment,
            currentDirectory: sourceRoot
        )
    }

    private func makeBundle(_ url: URL, bundleID: String) throws {
        let contents = url.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": bundleID]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: contents.appendingPathComponent("Info.plist"))
    }

    private func makeTool(named name: String, unregisterFails: Bool = false) throws {
        let url = root.appendingPathComponent(name)
        let unregisterFailure = unregisterFails
            ? "if [[ \"$1\" == \"-u\" ]]; then\n    exit 23\nfi\n"
            : ""
        let script = "#!/bin/zsh\nprint -r -- '\(name) '$* >> \"$TEST_LOG\"\n\(unregisterFailure)"
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    private func makeFailingFindTool() throws -> URL {
        let url = root.appendingPathComponent("find")
        try "#!/bin/zsh\nexit 1\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}
