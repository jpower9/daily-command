import CommonCrypto
import CryptoKit
import Foundation
import Security

/// Journal encryption, identical to the web app so one notebook opens on every surface
/// (execclone-apps `contract/parity-spec.md` §22):
///
/// - key: PBKDF2-HMAC-SHA256, 310,000 iterations, 16-byte random salt → 256-bit AES key
/// - entry: AES-256-GCM, 12-byte random nonce, stored as `enc:v1:<nonce b64>:<ciphertext+tag b64>`
/// - verifier: `kdf.check` is the string `dd-notebook-ok` encrypted with the key; a wrong
///   passphrase fails to decrypt it, so no plaintext is ever guessed at.
///
/// Keys live in memory only. The server stores ciphertext and the KDF parameters; it never sees
/// the passphrase or the key, so a forgotten passphrase cannot be recovered by anyone.
public enum JournalCrypto {
    public static let prefix = "enc:v1:"
    public static let iterations = 310_000
    public static let verifier = "dd-notebook-ok"
    public static let relockAfter: TimeInterval = 15 * 60

    public struct Kdf: Sendable, Equatable {
        public var salt: String      // base64, 16 bytes
        public var iterations: Int
        public var check: String     // `enc:v1:…` of `verifier`

        public init(salt: String, iterations: Int, check: String) {
            self.salt = salt; self.iterations = iterations; self.check = check
        }

        public init?(_ j: JSON) {
            guard let salt = j["salt"].nonEmptyString, let check = j["check"].nonEmptyString else { return nil }
            self.init(salt: salt, iterations: j["iterations"].int ?? JournalCrypto.iterations, check: check)
        }

        public var json: [String: Any] { ["salt": salt, "iterations": iterations, "check": check] }
    }

    public enum Error: Swift.Error, Equatable { case notEncrypted, malformed, wrongPassphrase, kdfFailed }

    public static func isEncrypted(_ s: String) -> Bool { s.hasPrefix(prefix) }

    public static func newSalt() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64EncodedString()
    }

    public static func deriveKey(passphrase: String, salt saltB64: String, iterations: Int = iterations) throws -> SymmetricKey {
        guard let salt = Data(base64Encoded: saltB64) else { throw Error.malformed }
        let pass = Array(passphrase.utf8)
        var out = [UInt8](repeating: 0, count: 32)
        let status = salt.withUnsafeBytes { saltPtr in
            CCKeyDerivationPBKDF(CCPBKDFAlgorithm(kCCPBKDF2), passphrase, pass.count,
                                 saltPtr.bindMemory(to: UInt8.self).baseAddress, salt.count,
                                 CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256), UInt32(iterations), &out, out.count)
        }
        guard status == kCCSuccess else { throw Error.kdfFailed }
        return SymmetricKey(data: out)
    }

    public static func encrypt(_ text: String, key: SymmetricKey) throws -> String {
        let nonce = AES.GCM.Nonce()
        let sealed = try AES.GCM.seal(Data(text.utf8), using: key, nonce: nonce)
        // WebCrypto's AES-GCM output is ciphertext followed by the 16-byte tag.
        let ct = sealed.ciphertext + sealed.tag
        return prefix + Data(nonce).base64EncodedString() + ":" + ct.base64EncodedString()
    }

    public static func decrypt(_ stored: String, key: SymmetricKey) throws -> String {
        guard stored.hasPrefix(prefix) else { throw Error.notEncrypted }
        let parts = stored.dropFirst(prefix.count).split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let iv = Data(base64Encoded: parts[0]), let ct = Data(base64Encoded: parts[1]),
              iv.count == 12, ct.count >= 16 else { throw Error.malformed }
        do {
            let nonce = try AES.GCM.Nonce(data: iv)
            let box = try AES.GCM.SealedBox(nonce: nonce, ciphertext: ct.dropLast(16), tag: ct.suffix(16))
            let pt = try AES.GCM.open(box, using: key)
            guard let s = String(data: pt, encoding: .utf8) else { throw Error.malformed }
            return s
        } catch let e as Error { throw e } catch { throw Error.wrongPassphrase }
    }

    /// A new notebook lock: salt, iterations and the verifier the unlock checks, plus the key.
    public static func makeKdf(passphrase: String) throws -> (kdf: Kdf, key: SymmetricKey) {
        let salt = newSalt()
        let key = try deriveKey(passphrase: passphrase, salt: salt)
        return (Kdf(salt: salt, iterations: iterations, check: try encrypt(verifier, key: key)), key)
    }

    /// The key for an existing lock, or nil when the passphrase is wrong.
    public static func unlock(passphrase: String, kdf: Kdf) -> SymmetricKey? {
        guard let key = try? deriveKey(passphrase: passphrase, salt: kdf.salt, iterations: kdf.iterations),
              (try? decrypt(kdf.check, key: key)) == verifier else { return nil }
        return key
    }
}
