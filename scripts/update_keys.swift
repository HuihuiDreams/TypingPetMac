import CryptoKit
import Foundation

// Ed25519 keys for update archives. Private keys stay outside the repository.
//   swift scripts/update_keys.swift generate <development|production>
//   swift scripts/update_keys.swift check <development|production>
//   swift scripts/update_keys.swift sign <development|production> <file>
//   swift scripts/update_keys.swift verify <development|production> <file> <signature>
let environment = ProcessInfo.processInfo.environment
let keyDirectory = URL(fileURLWithPath: environment["TYPINGPET_UPDATE_KEY_DIR"]
    ?? NSHomeDirectory() + "/.config/typingpet/update-keys")

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard arguments.count >= 2, ["development", "production"].contains(arguments[1]) else {
    fail("Usage: update_keys.swift generate <channel> | sign <channel> <file>")
}
let channel = arguments[1]
let privateURL = keyDirectory.appendingPathComponent("\(channel).key")
let publicURL = keyDirectory.appendingPathComponent("\(channel).pub")

func verifiedKey() -> Curve25519.Signing.PrivateKey {
    guard let encoded = try? String(contentsOf: privateURL, encoding: .utf8),
          let raw = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
    else { fail("Cannot read \(privateURL.path). Recover the original private key before publishing updates.") }
    guard let encodedPublic = try? String(contentsOf: publicURL, encoding: .utf8),
          let publicRaw = Data(base64Encoded: encodedPublic.trimmingCharacters(in: .whitespacesAndNewlines)),
          key.publicKey.rawRepresentation == publicRaw
    else { fail("\(privateURL.path) does not match \(publicURL.path).") }
    return key
}

switch arguments[0] {
case "generate":
    if FileManager.default.fileExists(atPath: privateURL.path)
        || FileManager.default.fileExists(atPath: publicURL.path) {
        fail("A \(channel) update key already exists. Recover its private key if a released build trusts the public key.")
    }
    try FileManager.default.createDirectory(at: keyDirectory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    let key = Curve25519.Signing.PrivateKey()
    FileManager.default.createFile(
        atPath: privateURL.path,
        contents: Data(key.rawRepresentation.base64EncodedString().utf8),
        attributes: [.posixPermissions: 0o600]
    )
    try key.publicKey.rawRepresentation.base64EncodedString().write(to: publicURL, atomically: true, encoding: .utf8)
    print(publicURL.path)
case "sign":
    guard arguments.count == 3 else { fail("Usage: update_keys.swift sign <channel> <file>") }
    let key = verifiedKey()
    let data = try Data(contentsOf: URL(fileURLWithPath: arguments[2]), options: .mappedIfSafe)
    print(try key.signature(for: data).base64EncodedString())
case "check":
    guard arguments.count == 2 else { fail("Usage: update_keys.swift check <channel>") }
    _ = verifiedKey()
    print("\(channel) update key pair matches")
case "verify":
    guard arguments.count == 4,
          let encoded = try? String(contentsOf: publicURL, encoding: .utf8),
          let raw = Data(base64Encoded: encoded.trimmingCharacters(in: .whitespacesAndNewlines)),
          let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
          let signature = Data(base64Encoded: arguments[3])
    else { fail("Usage: update_keys.swift verify <channel> <file> <signature>") }
    let data = try Data(contentsOf: URL(fileURLWithPath: arguments[2]), options: .mappedIfSafe)
    guard publicKey.isValidSignature(signature, for: data) else { fail("Invalid \(channel) update signature") }
    print("\(channel) update signature verified")
default:
    fail("Unknown command \(arguments[0])")
}
