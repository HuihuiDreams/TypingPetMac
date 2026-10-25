import CryptoKit
import Foundation
import Security

// The feed is a static JSON file. `build` (CFBundleVersion) orders releases.
struct UpdateManifest: Codable, Equatable {
    let version: String
    let build: Int
    let minimumSystemVersion: String
    let url: URL
    let size: Int
    let sha256: String
    let signature: String
    let notes: String?

    func isNewer(than currentBuild: Int) -> Bool { build > currentBuild }

    func supports(_ system: OperatingSystemVersion) -> Bool {
        let parts = minimumSystemVersion.split(separator: ".").map { Int($0) ?? 0 }
        let required = OperatingSystemVersion(
            majorVersion: parts.first ?? 0,
            minorVersion: parts.count > 1 ? parts[1] : 0,
            patchVersion: parts.count > 2 ? parts[2] : 0
        )
        return (system.majorVersion, system.minorVersion, system.patchVersion)
            >= (required.majorVersion, required.minorVersion, required.patchVersion)
    }
}

// Values the running bundle carries. Info.plist is covered by the code signature.
struct UpdateConfiguration {
    static let productionFeedURL = URL(string: "https://pet.miel.ing/update/production/latest.json")!
    static let feedOverrideKey = AppPreferencesKey.updateFeedURL

    let profile: AppProfile
    let bundleIdentifier: String
    let version: String
    let build: Int
    let feedURL: URL
    let publicKey: Curve25519.Signing.PublicKey
    let teamIdentifier: String?

    static func resolve(profile: AppProfile, info: [String: Any]?, feedOverride: String?) -> Result<UpdateConfiguration, UpdateError> {
        guard let info,
              let bundleIdentifier = info["CFBundleIdentifier"] as? String,
              let version = info["CFBundleShortVersionString"] as? String,
              let build = (info["CFBundleVersion"] as? String).flatMap(Int.init)
        else { return .failure(.unavailable(L("Updates are only available when running an app bundle."))) }
        guard let encodedKey = info["TypingPetUpdatePublicKey"] as? String,
              let keyData = Data(base64Encoded: encodedKey),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else { return .failure(.unavailable(L("This build has no update signing key."))) }
        let teamIdentifier = (info["TypingPetTeamIdentifier"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let feedURL: URL
        switch profile {
        case .production:
            feedURL = productionFeedURL
        case .development:
            guard let override = feedOverride.flatMap(URL.init(string:)) else {
                return .failure(.unavailable(L("Dev builds only check for updates when %1$@ is configured.", feedOverrideKey)))
            }
            feedURL = override
        }
        guard isAllowed(feedURL, profile: profile) else { return .failure(.unavailable(L("The update URL is not secure."))) }
        return .success(UpdateConfiguration(
            profile: profile,
            bundleIdentifier: bundleIdentifier,
            version: version,
            build: build,
            feedURL: feedURL,
            publicKey: publicKey,
            teamIdentifier: teamIdentifier
        ))
    }

    // Production accepts HTTPS only. Dev may also use a loopback http server.
    static func isAllowed(_ url: URL, profile: AppProfile) -> Bool {
        if url.scheme == "https" { return url.host != nil }
        guard profile == .development, url.scheme == "http" else { return false }
        return ["localhost", "127.0.0.1", "::1"].contains(url.host ?? "")
    }

    // An ad-hoc build has no Team ID, so it relies on the Ed25519 signature alone.
    // Once a Developer ID build is installed, every later update must come from the same team.
    var codeRequirement: String? {
        guard let teamIdentifier else { return nil }
        return "anchor apple generic and identifier \"\(bundleIdentifier)\""
            + " and certificate 1[field.1.2.840.113635.100.6.2.6] exists"
            + " and certificate leaf[field.1.2.840.113635.100.6.1.13] exists"
            + " and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    }
}

enum UpdateError: LocalizedError, Equatable {
    case unavailable(String)
    case invalidFeed(String)
    case rejected(String)
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .unavailable(let message), .invalidFeed(let message), .rejected(let message), .installFailed(let message):
            return message
        }
    }
}

enum UpdateVerifier {
    static func validate(_ manifest: UpdateManifest, configuration: UpdateConfiguration) throws {
        guard UpdateConfiguration.isAllowed(manifest.url, profile: configuration.profile) else {
            throw UpdateError.invalidFeed(L("The update file URL is not secure."))
        }
        guard manifest.size > 0, manifest.sha256.count == 64, Data(base64Encoded: manifest.signature)?.count == 64 else {
            throw UpdateError.invalidFeed(L("The update information is invalid."))
        }
    }

    static func verifyArchive(_ data: Data, manifest: UpdateManifest, publicKey: Curve25519.Signing.PublicKey) throws {
        guard data.count == manifest.size else { throw UpdateError.rejected(L("The downloaded file size does not match.")) }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == manifest.sha256.lowercased() else { throw UpdateError.rejected(L("The downloaded file hash does not match.")) }
        guard let signature = Data(base64Encoded: manifest.signature),
              publicKey.isValidSignature(signature, for: data)
        else { throw UpdateError.rejected(L("The update signature is invalid.")) }
    }

    // The staged app must be this app, newer than this build, and signed like this app.
    static func verifyApp(at url: URL, manifest: UpdateManifest, configuration: UpdateConfiguration) throws {
        guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any] else {
            throw UpdateError.rejected(L("Could not read the update app's information."))
        }
        guard info["CFBundleIdentifier"] as? String == configuration.bundleIdentifier,
              info["TypingPetBuildChannel"] as? String == configuration.profile.rawValue
        else { throw UpdateError.rejected(L("This update belongs to a different app.")) }
        guard let build = (info["CFBundleVersion"] as? String).flatMap(Int.init), build == manifest.build,
              build > configuration.build
        else { throw UpdateError.rejected(L("The update build number does not match.")) }
        try verifyCodeSignature(at: url, requirement: configuration.codeRequirement)
    }

    static func verifyCodeSignature(at url: URL, requirement: String?) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
            throw UpdateError.rejected(L("Could not read the update app's signature."))
        }
        var secRequirement: SecRequirement?
        if let requirement {
            guard SecRequirementCreateWithString(requirement as CFString, [], &secRequirement) == errSecSuccess else {
                throw UpdateError.rejected(L("Could not create the signature requirement."))
            }
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(code, flags, secRequirement) == errSecSuccess else {
            throw UpdateError.rejected(requirement == nil ? L("The update app's signature is damaged.") : L("The update app is not signed by the same developer."))
        }
    }
}
