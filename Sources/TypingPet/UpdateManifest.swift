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
    static let feedOverrideKey = "UpdateFeedURL"

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
        else { return .failure(.unavailable("앱 번들로 실행할 때만 업데이트할 수 있어요.")) }
        guard let encodedKey = info["TypingPetUpdatePublicKey"] as? String,
              let keyData = Data(base64Encoded: encodedKey),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData)
        else { return .failure(.unavailable("이 빌드에는 업데이트 서명 키가 없어요.")) }
        let teamIdentifier = (info["TypingPetTeamIdentifier"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let feedURL: URL
        switch profile {
        case .production:
            guard teamIdentifier != nil else { return .failure(.unavailable("이 빌드에는 Developer ID 팀 정보가 없어요.")) }
            feedURL = productionFeedURL
        case .development:
            guard let override = feedOverride.flatMap(URL.init(string:)) else {
                return .failure(.unavailable("Dev 빌드는 \(feedOverrideKey) 설정이 있을 때만 업데이트를 확인해요."))
            }
            feedURL = override
        }
        guard isAllowed(feedURL, profile: profile) else { return .failure(.unavailable("업데이트 주소가 안전하지 않아요.")) }
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
            throw UpdateError.invalidFeed("업데이트 파일 주소가 안전하지 않아요.")
        }
        guard manifest.size > 0, manifest.sha256.count == 64, Data(base64Encoded: manifest.signature)?.count == 64 else {
            throw UpdateError.invalidFeed("업데이트 정보가 올바르지 않아요.")
        }
    }

    static func verifyArchive(_ data: Data, manifest: UpdateManifest, publicKey: Curve25519.Signing.PublicKey) throws {
        guard data.count == manifest.size else { throw UpdateError.rejected("내려받은 파일 크기가 달라요.") }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard digest == manifest.sha256.lowercased() else { throw UpdateError.rejected("내려받은 파일의 해시가 달라요.") }
        guard let signature = Data(base64Encoded: manifest.signature),
              publicKey.isValidSignature(signature, for: data)
        else { throw UpdateError.rejected("업데이트 서명이 올바르지 않아요.") }
    }

    // The staged app must be this app, newer than this build, and signed like this app.
    static func verifyApp(at url: URL, manifest: UpdateManifest, configuration: UpdateConfiguration) throws {
        guard let info = NSDictionary(contentsOf: url.appendingPathComponent("Contents/Info.plist")) as? [String: Any] else {
            throw UpdateError.rejected("업데이트 앱 정보를 읽지 못했어요.")
        }
        guard info["CFBundleIdentifier"] as? String == configuration.bundleIdentifier,
              info["TypingPetBuildChannel"] as? String == configuration.profile.rawValue
        else { throw UpdateError.rejected("다른 앱의 업데이트예요.") }
        guard let build = (info["CFBundleVersion"] as? String).flatMap(Int.init), build == manifest.build,
              build > configuration.build
        else { throw UpdateError.rejected("업데이트 빌드 번호가 맞지 않아요.") }
        try verifyCodeSignature(at: url, requirement: configuration.codeRequirement)
    }

    static func verifyCodeSignature(at url: URL, requirement: String?) throws {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code else {
            throw UpdateError.rejected("업데이트 앱의 서명을 읽지 못했어요.")
        }
        var secRequirement: SecRequirement?
        if let requirement {
            guard SecRequirementCreateWithString(requirement as CFString, [], &secRequirement) == errSecSuccess else {
                throw UpdateError.rejected("서명 요구 사항을 만들지 못했어요.")
            }
        }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSStrictValidate | kSecCSCheckNestedCode)
        guard SecStaticCodeCheckValidity(code, flags, secRequirement) == errSecSuccess else {
            throw UpdateError.rejected(requirement == nil ? "업데이트 앱의 서명이 손상됐어요." : "업데이트 앱이 같은 개발자 서명이 아니에요.")
        }
    }
}
