import CryptoKit
import Foundation
import XCTest
@testable import TypingPet

final class UpdateTests: XCTestCase {
    private let key = Curve25519.Signing.PrivateKey()
    private var folder: URL!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("UpdateTests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
    }

    private func info(
        channel: String = "development",
        bundle: String = "ing.miel.typingpet.dev",
        build: String = "18",
        team: String? = nil
    ) -> [String: Any] {
        var info: [String: Any] = [
            "CFBundleIdentifier": bundle,
            "CFBundleShortVersionString": "0.12.0",
            "CFBundleVersion": build,
            "TypingPetBuildChannel": channel,
            "TypingPetUpdatePublicKey": key.publicKey.rawRepresentation.base64EncodedString(),
        ]
        info["TypingPetTeamIdentifier"] = team
        return info
    }

    private func configuration(_ profile: AppProfile = .development, team: String? = nil) throws -> UpdateConfiguration {
        try UpdateConfiguration.resolve(
            profile: profile,
            info: info(
                channel: profile.rawValue,
                bundle: profile.bundleIdentifier,
                team: team
            ),
            feedOverride: "http://localhost:8787/development/latest.json"
        ).get()
    }

    private func manifest(for data: Data, build: Int = 19, url: String = "http://127.0.0.1:8787/a.zip") throws -> UpdateManifest {
        UpdateManifest(
            version: "0.13.0",
            build: build,
            minimumSystemVersion: "13.0",
            url: URL(string: url)!,
            size: data.count,
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            signature: try key.signature(for: data).base64EncodedString(),
            notes: nil
        )
    }

    private func error(_ operation: () throws -> Void) -> UpdateError? {
        do { try operation(); return nil } catch { return error as? UpdateError }
    }

    func testManifestDecodesFeedJSON() throws {
        let json = """
        {"version":"0.13.0","build":19,"minimumSystemVersion":"13.0","url":"https://pet.miel.ing/update/production/a.zip",
         "size":10,"sha256":"\(String(repeating: "a", count: 64))","signature":"sig","notes":"- New"}
        """
        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: Data(json.utf8))
        XCTAssertEqual(manifest.build, 19)
        XCTAssertEqual(manifest.notes, "- New")
        XCTAssertTrue(manifest.isNewer(than: 18))
        XCTAssertFalse(manifest.isNewer(than: 19))
        XCTAssertFalse(manifest.isNewer(than: 20))
    }

    func testMinimumSystemVersionComparesEachComponent() throws {
        let base = try manifest(for: Data("x".utf8))
        let manifest = UpdateManifest(
            version: base.version, build: base.build, minimumSystemVersion: "14.2", url: base.url,
            size: base.size, sha256: base.sha256, signature: base.signature, notes: nil
        )
        XCTAssertFalse(manifest.supports(OperatingSystemVersion(majorVersion: 13, minorVersion: 9, patchVersion: 0)))
        XCTAssertFalse(manifest.supports(OperatingSystemVersion(majorVersion: 14, minorVersion: 1, patchVersion: 9)))
        XCTAssertTrue(manifest.supports(OperatingSystemVersion(majorVersion: 14, minorVersion: 2, patchVersion: 0)))
        XCTAssertTrue(manifest.supports(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)))
    }

    func testProductionUsesFixedHTTPSFeedAndRequiresTeam() throws {
        let production = try configuration(.production, team: "ABCDE12345")
        XCTAssertEqual(production.feedURL, UpdateConfiguration.productionFeedURL)
        XCTAssertEqual(production.feedURL.absoluteString, "https://pet.miel.ing/update/production/latest.json")
        let missingTeam = UpdateConfiguration.resolve(profile: .production, info: info(channel: "production", bundle: "ing.miel.typingpet"), feedOverride: nil)
        XCTAssertThrowsError(try missingTeam.get())
    }

    func testDevelopmentNeedsFeedOverrideAndPublicKey() {
        XCTAssertThrowsError(try UpdateConfiguration.resolve(profile: .development, info: info(), feedOverride: nil).get())
        var noKey = info()
        noKey["TypingPetUpdatePublicKey"] = nil
        XCTAssertThrowsError(try UpdateConfiguration.resolve(profile: .development, info: noKey, feedOverride: "http://localhost/x").get())
        XCTAssertThrowsError(try UpdateConfiguration.resolve(profile: .development, info: nil, feedOverride: "http://localhost/x").get())
    }

    func testOnlyDevelopmentMayUseLoopbackHTTP() {
        XCTAssertTrue(UpdateConfiguration.isAllowed(URL(string: "https://pet.miel.ing/update")!, profile: .production))
        XCTAssertFalse(UpdateConfiguration.isAllowed(URL(string: "http://localhost:8787/x")!, profile: .production))
        XCTAssertTrue(UpdateConfiguration.isAllowed(URL(string: "http://localhost:8787/x")!, profile: .development))
        XCTAssertTrue(UpdateConfiguration.isAllowed(URL(string: "http://127.0.0.1:8787/x")!, profile: .development))
        XCTAssertFalse(UpdateConfiguration.isAllowed(URL(string: "http://example.com/x")!, profile: .development))
        XCTAssertFalse(UpdateConfiguration.isAllowed(URL(string: "file:///tmp/x.zip")!, profile: .development))
    }

    func testSignedArchiveVerifies() throws {
        let data = Data("archive".utf8)
        XCTAssertNoThrow(try UpdateVerifier.verifyArchive(data, manifest: try manifest(for: data), publicKey: key.publicKey))
    }

    func testTamperedArchiveOrSignatureIsRejected() throws {
        let data = Data("archive".utf8)
        let signed = try manifest(for: data)
        XCTAssertNotNil(error { try UpdateVerifier.verifyArchive(Data("archivE".utf8), manifest: signed, publicKey: self.key.publicKey) })
        XCTAssertNotNil(error { try UpdateVerifier.verifyArchive(data + Data([0]), manifest: signed, publicKey: self.key.publicKey) })
        let otherKey = Curve25519.Signing.PrivateKey().publicKey
        XCTAssertEqual(
            error { try UpdateVerifier.verifyArchive(data, manifest: signed, publicKey: otherKey) },
            .rejected("업데이트 서명이 올바르지 않아요.")
        )
    }

    func testManifestValidationRejectsUnsafeURLAndMalformedFields() throws {
        let configuration = try configuration()
        let data = Data("archive".utf8)
        XCTAssertNoThrow(try UpdateVerifier.validate(try manifest(for: data), configuration: configuration))
        let remote = try manifest(for: data, url: "http://example.com/a.zip")
        XCTAssertNotNil(error { try UpdateVerifier.validate(remote, configuration: configuration) })
        let good = try manifest(for: data)
        let malformed = UpdateManifest(
            version: good.version, build: good.build, minimumSystemVersion: good.minimumSystemVersion, url: good.url,
            size: good.size, sha256: "abc", signature: good.signature, notes: nil
        )
        XCTAssertNotNil(error { try UpdateVerifier.validate(malformed, configuration: configuration) })
    }

    func testDeveloperIDRequirementNamesBundleAndTeam() throws {
        let requirement = try XCTUnwrap(try configuration(.production, team: "ABCDE12345").codeRequirement)
        XCTAssertTrue(requirement.contains("anchor apple generic"))
        XCTAssertTrue(requirement.contains("identifier \"ing.miel.typingpet\""))
        XCTAssertTrue(requirement.contains("certificate leaf[subject.OU] = \"ABCDE12345\""))
        var compiled: SecRequirement?
        XCTAssertEqual(SecRequirementCreateWithString(requirement as CFString, [], &compiled), errSecSuccess)
        XCTAssertNil(try configuration().codeRequirement)
    }

    // A fake bundle with an ad-hoc signed copy of /usr/bin/true.
    private func makeApp(bundle: String = "ing.miel.typingpet.dev", build: String = "19", channel: String = "development") throws -> URL {
        let app = folder.appendingPathComponent("\(UUID()).app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: macOS.appendingPathComponent("TypingPetDev").path)
        var plist = info(channel: channel, bundle: bundle, build: build)
        plist["CFBundleExecutable"] = "TypingPetDev"
        plist["CFBundlePackageType"] = "APPL"
        XCTAssertTrue((plist as NSDictionary).write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true))
        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--force", "--sign", "-", app.path]
        codesign.standardError = FileHandle.nullDevice
        try codesign.run()
        codesign.waitUntilExit()
        XCTAssertEqual(codesign.terminationStatus, 0)
        return app
    }

    func testStagedAppMustMatchBundleChannelAndBuild() throws {
        let configuration = try configuration()
        let data = Data("archive".utf8)
        XCTAssertNoThrow(try UpdateVerifier.verifyApp(at: try makeApp(), manifest: try manifest(for: data), configuration: configuration))
        XCTAssertEqual(
            error { try UpdateVerifier.verifyApp(at: try self.makeApp(bundle: "com.example.other"), manifest: try self.manifest(for: data), configuration: configuration) },
            .rejected("다른 앱의 업데이트예요.")
        )
        XCTAssertNotNil(error { try UpdateVerifier.verifyApp(at: try self.makeApp(channel: "production"), manifest: try self.manifest(for: data), configuration: configuration) })
        XCTAssertNotNil(error { try UpdateVerifier.verifyApp(at: try self.makeApp(build: "20"), manifest: try self.manifest(for: data), configuration: configuration) })
        XCTAssertNotNil(error { try UpdateVerifier.verifyApp(at: try self.makeApp(build: "18"), manifest: try self.manifest(for: data, build: 18), configuration: configuration) })
    }

    func testModifiedOrUnsignedAppIsRejected() throws {
        let app = try makeApp()
        try Data("changed".utf8).write(to: app.appendingPathComponent("Contents/MacOS/TypingPetDev"))
        XCTAssertNotNil(error { try UpdateVerifier.verifyCodeSignature(at: app, requirement: nil) })
    }

    func testAdHocAppFailsDeveloperIDRequirement() throws {
        let app = try makeApp()
        XCTAssertNoThrow(try UpdateVerifier.verifyCodeSignature(at: app, requirement: nil))
        let requirement = try XCTUnwrap(try configuration(.production, team: "ABCDE12345").codeRequirement)
        XCTAssertEqual(
            error { try UpdateVerifier.verifyCodeSignature(at: app, requirement: requirement) },
            .rejected("업데이트 앱이 같은 개발자 서명이 아니에요.")
        )
    }

    func testTranslocatedAppCannotSelfUpdate() {
        let translocated = URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/TypingPet.app")
        XCTAssertThrowsError(try UpdateInstaller.installTarget(for: translocated))
        let readOnly = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        XCTAssertThrowsError(try UpdateInstaller.installTarget(for: readOnly))
    }

    func testHelperScriptParses() throws {
        let script = folder.appendingPathComponent("install.sh")
        try UpdateInstaller.helperScript.write(to: script, atomically: true, encoding: .utf8)
        let zsh = Process()
        zsh.executableURL = URL(fileURLWithPath: "/bin/zsh")
        zsh.arguments = ["-n", script.path]
        try zsh.run()
        zsh.waitUntilExit()
        XCTAssertEqual(zsh.terminationStatus, 0)
    }

    func testHelperSwapsBundleAfterProcessExitsAndRestoresOnFailure() throws {
        let target = folder.appendingPathComponent("Installed.app")
        let staged = folder.appendingPathComponent("Staged.app")
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staged, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: target.appendingPathComponent("marker"))
        try Data("new".utf8).write(to: staged.appendingPathComponent("marker"))
        let script = folder.appendingPathComponent("install.sh")
        try UpdateInstaller.helperScript.write(to: script, atomically: true, encoding: .utf8)

        func runHelper(staged: URL) throws {
            let helper = Process()
            helper.executableURL = URL(fileURLWithPath: "/bin/zsh")
            // PID 999999 is not running, so the helper starts at once.
            helper.arguments = [script.path, "999999", target.path, staged.path, "0", folder.path]
            try helper.run()
            helper.waitUntilExit()
        }

        try runHelper(staged: staged)
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("marker"), encoding: .utf8), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("previous.app").path))

        try runHelper(staged: folder.appendingPathComponent("Missing.app"))
        XCTAssertEqual(try String(contentsOf: target.appendingPathComponent("marker"), encoding: .utf8), "new")
        let log = try String(contentsOf: UpdateInstaller.logURL(in: folder), encoding: .utf8)
        XCTAssertTrue(log.contains("INSTALLED"))
        XCTAssertTrue(log.contains("FAILED: cannot install the update, restoring"))
    }
}
