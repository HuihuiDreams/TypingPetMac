import CryptoKit
import Foundation
import Testing
@testable import TypingPet

@Suite struct UpdateTests {
    private let key = Curve25519.Signing.PrivateKey()

    private func withFolder<T>(_ body: (URL) throws -> T) throws -> T {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("UpdateTests-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        return try body(folder)
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

    @Test func manifestDecodesFeedJSON() throws {
        let json = """
        {"version":"0.13.0","build":19,"minimumSystemVersion":"13.0","url":"https://pet.miel.ing/update/production/a.zip",
         "size":10,"sha256":"\(String(repeating: "a", count: 64))","signature":"sig","notes":"- New"}
        """
        let manifest = try JSONDecoder().decode(UpdateManifest.self, from: Data(json.utf8))
        #expect(manifest.build == 19)
        #expect(manifest.notes == "- New")
        #expect(manifest.isNewer(than: 18))
        #expect(!manifest.isNewer(than: 19))
        #expect(!manifest.isNewer(than: 20))
    }

    @Test func minimumSystemVersionComparesEachComponent() throws {
        let base = try manifest(for: Data("x".utf8))
        let manifest = UpdateManifest(
            version: base.version, build: base.build, minimumSystemVersion: "14.2", url: base.url,
            size: base.size, sha256: base.sha256, signature: base.signature, notes: nil
        )
        #expect(!manifest.supports(OperatingSystemVersion(majorVersion: 13, minorVersion: 9, patchVersion: 0)))
        #expect(!manifest.supports(OperatingSystemVersion(majorVersion: 14, minorVersion: 1, patchVersion: 9)))
        #expect(manifest.supports(OperatingSystemVersion(majorVersion: 14, minorVersion: 2, patchVersion: 0)))
        #expect(manifest.supports(OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)))
    }

    @Test func productionUsesFixedHTTPSFeedAndTeamOnlyWhenSigned() throws {
        let production = try configuration(.production, team: "ABCDE12345")
        #expect(production.feedURL == UpdateConfiguration.productionFeedURL)
        #expect(production.feedURL.absoluteString == "https://pet.miel.ing/update/production/latest.json")
        #expect(production.codeRequirement != nil)
        let adHoc = try UpdateConfiguration.resolve(
            profile: .production,
            info: info(channel: "production", bundle: "ing.miel.typingpet"),
            feedOverride: "http://localhost:8787/x"
        ).get()
        #expect(adHoc.feedURL == UpdateConfiguration.productionFeedURL)
        #expect(adHoc.codeRequirement == nil)
    }

    @Test func developmentNeedsFeedOverrideAndPublicKey() {
        #expect(throws: (any Error).self) {
            try UpdateConfiguration.resolve(profile: .development, info: info(), feedOverride: nil).get()
        }
        var noKey = info()
        noKey["TypingPetUpdatePublicKey"] = nil
        #expect(throws: (any Error).self) {
            try UpdateConfiguration.resolve(profile: .development, info: noKey, feedOverride: "http://localhost/x").get()
        }
        #expect(throws: (any Error).self) {
            try UpdateConfiguration.resolve(profile: .development, info: nil, feedOverride: "http://localhost/x").get()
        }
    }

    @Test func onlyDevelopmentMayUseLoopbackHTTP() {
        #expect(UpdateConfiguration.isAllowed(URL(string: "https://pet.miel.ing/update")!, profile: .production))
        #expect(!UpdateConfiguration.isAllowed(URL(string: "http://localhost:8787/x")!, profile: .production))
        #expect(UpdateConfiguration.isAllowed(URL(string: "http://localhost:8787/x")!, profile: .development))
        #expect(UpdateConfiguration.isAllowed(URL(string: "http://127.0.0.1:8787/x")!, profile: .development))
        #expect(!UpdateConfiguration.isAllowed(URL(string: "http://example.com/x")!, profile: .development))
        #expect(!UpdateConfiguration.isAllowed(URL(string: "file:///tmp/x.zip")!, profile: .development))
    }

    @Test func signedArchiveVerifies() throws {
        let data = Data("archive".utf8)
        try UpdateVerifier.verifyArchive(data, manifest: try manifest(for: data), publicKey: key.publicKey)
    }

    @Test func tamperedArchiveOrSignatureIsRejected() throws {
        let data = Data("archive".utf8)
        let signed = try manifest(for: data)
        #expect(error { try UpdateVerifier.verifyArchive(Data("archivE".utf8), manifest: signed, publicKey: self.key.publicKey) } != nil)
        #expect(error { try UpdateVerifier.verifyArchive(data + Data([0]), manifest: signed, publicKey: self.key.publicKey) } != nil)
        let otherKey = Curve25519.Signing.PrivateKey().publicKey
        #expect(
            error { try UpdateVerifier.verifyArchive(data, manifest: signed, publicKey: otherKey) }
            == .rejected(L("The update signature is invalid."))
        )
    }

    @Test func manifestValidationRejectsUnsafeURLAndMalformedFields() throws {
        let configuration = try configuration()
        let data = Data("archive".utf8)
        try UpdateVerifier.validate(try manifest(for: data), configuration: configuration)
        let remote = try manifest(for: data, url: "http://example.com/a.zip")
        #expect(error { try UpdateVerifier.validate(remote, configuration: configuration) } != nil)
        let good = try manifest(for: data)
        let malformed = UpdateManifest(
            version: good.version, build: good.build, minimumSystemVersion: good.minimumSystemVersion, url: good.url,
            size: good.size, sha256: "abc", signature: good.signature, notes: nil
        )
        #expect(error { try UpdateVerifier.validate(malformed, configuration: configuration) } != nil)
    }

    @Test func developerIDRequirementNamesBundleAndTeam() throws {
        let requirement = try #require(try configuration(.production, team: "ABCDE12345").codeRequirement)
        #expect(requirement.contains("anchor apple generic"))
        #expect(requirement.contains("identifier \"ing.miel.typingpet\""))
        #expect(requirement.contains("certificate leaf[subject.OU] = \"ABCDE12345\""))
        var compiled: SecRequirement?
        #expect(SecRequirementCreateWithString(requirement as CFString, [], &compiled) == errSecSuccess)
        #expect(try configuration().codeRequirement == nil)
    }

    private func makeApp(in folder: URL, bundle: String = "ing.miel.typingpet.dev", build: String = "19", channel: String = "development") throws -> URL {
        let app = folder.appendingPathComponent("\(UUID()).app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        try FileManager.default.copyItem(atPath: "/usr/bin/true", toPath: macOS.appendingPathComponent("TypingPetDev").path)
        var plist = info(channel: channel, bundle: bundle, build: build)
        plist["CFBundleExecutable"] = "TypingPetDev"
        plist["CFBundlePackageType"] = "APPL"
        #expect((plist as NSDictionary).write(to: app.appendingPathComponent("Contents/Info.plist"), atomically: true))
        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--force", "--sign", "-", app.path]
        codesign.standardError = FileHandle.nullDevice
        try codesign.run()
        codesign.waitUntilExit()
        #expect(codesign.terminationStatus == 0)
        return app
    }

    @Test func stagedAppMustMatchBundleChannelAndBuild() throws {
        try withFolder { folder in
            let configuration = try configuration()
            let data = Data("archive".utf8)
            try UpdateVerifier.verifyApp(at: try makeApp(in: folder), manifest: try manifest(for: data), configuration: configuration)
            #expect(
                error { try UpdateVerifier.verifyApp(at: try self.makeApp(in: folder, bundle: "com.example.other"), manifest: try self.manifest(for: data), configuration: configuration) }
                == .rejected(L("This update belongs to a different app."))
            )
            #expect(error { try UpdateVerifier.verifyApp(at: try self.makeApp(in: folder, channel: "production"), manifest: try self.manifest(for: data), configuration: configuration) } != nil)
            #expect(error { try UpdateVerifier.verifyApp(at: try self.makeApp(in: folder, build: "20"), manifest: try self.manifest(for: data), configuration: configuration) } != nil)
            #expect(error { try UpdateVerifier.verifyApp(at: try self.makeApp(in: folder, build: "18"), manifest: try self.manifest(for: data, build: 18), configuration: configuration) } != nil)
        }
    }

    @Test func modifiedOrUnsignedAppIsRejected() throws {
        try withFolder { folder in
            let app = try makeApp(in: folder)
            try Data("changed".utf8).write(to: app.appendingPathComponent("Contents/MacOS/TypingPetDev"))
            #expect(error { try UpdateVerifier.verifyCodeSignature(at: app, requirement: nil) } != nil)
        }
    }

    @Test func adHocAppFailsDeveloperIDRequirement() throws {
        try withFolder { folder in
            let app = try makeApp(in: folder)
            try UpdateVerifier.verifyCodeSignature(at: app, requirement: nil)
            let requirement = try #require(try configuration(.production, team: "ABCDE12345").codeRequirement)
            #expect(
                error { try UpdateVerifier.verifyCodeSignature(at: app, requirement: requirement) }
                == .rejected(L("The update app is not signed by the same developer."))
            )
        }
    }

    @Test func translocatedAppCannotSelfUpdate() {
        let translocated = URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/TypingPet.app")
        #expect(throws: (any Error).self) {
            try UpdateInstaller.installTarget(for: translocated)
        }
        let readOnly = URL(fileURLWithPath: "/System/Applications/Calculator.app")
        #expect(throws: (any Error).self) {
            try UpdateInstaller.installTarget(for: readOnly)
        }
    }

    @Test func helperScriptParses() throws {
        try withFolder { folder in
            let script = folder.appendingPathComponent("install.sh")
            try UpdateInstaller.helperScript.write(to: script, atomically: true, encoding: .utf8)
            let zsh = Process()
            zsh.executableURL = URL(fileURLWithPath: "/bin/zsh")
            zsh.arguments = ["-n", script.path]
            try zsh.run()
            zsh.waitUntilExit()
            #expect(zsh.terminationStatus == 0)
        }
    }

    @Test func helperSwapsBundleAfterProcessExitsAndRestoresOnFailure() throws {
        try withFolder { folder in
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
            #expect(try String(contentsOf: target.appendingPathComponent("marker"), encoding: .utf8) == "new")
            #expect(!FileManager.default.fileExists(atPath: folder.appendingPathComponent("previous.app").path))

            try runHelper(staged: folder.appendingPathComponent("Missing.app"))
            #expect(try String(contentsOf: target.appendingPathComponent("marker"), encoding: .utf8) == "new")
            let log = try String(contentsOf: UpdateInstaller.logURL(in: folder), encoding: .utf8)
            #expect(log.contains("INSTALLED"))
            #expect(log.contains("FAILED: cannot install the update, restoring"))
        }
    }
}
