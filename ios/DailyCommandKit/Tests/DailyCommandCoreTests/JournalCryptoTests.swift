import CryptoKit
import Testing
@testable import DailyCommandCore

// Vectors produced independently (Python: hashlib.pbkdf2_hmac + cryptography AESGCM) with the
// web app's parameters, so a notebook locked in Executive OS opens here and vice versa.
struct JournalCryptoTests {
    let salt = "AAECAwQFBgcICQoLDA0ODw=="
    let passphrase = "correct horse"
    let check = "enc:v1:AAECAwQFBgcICQoL:8290AbG2XY+6iSBPBU4BEYwIHw4SCwjmL9vE0wEP"
    let entry = "enc:v1:CQkJCQkJCQkJCQkJ:kpKqS4iFYeMh7O2ECi/rWW6pWMpA2xIiE2EfT4LQ8agc4XXuoPlF0ZouezE="

    @Test func derivesTheSameKeyAsTheWebApp() throws {
        let key = try JournalCrypto.deriveKey(passphrase: passphrase, salt: salt)
        let raw = key.withUnsafeBytes { Data($0) }
        #expect(raw.base64EncodedString() == "cU605G1Sa4IphWDxr5nzK1kyPPB9Ohl4v0W6NdfDmGE=")
    }

    @Test func opensAWebLockedNotebookAndEntry() throws {
        let kdf = JournalCrypto.Kdf(salt: salt, iterations: 310_000, check: check)
        let key = try #require(JournalCrypto.unlock(passphrase: passphrase, kdf: kdf))
        #expect(try JournalCrypto.decrypt(entry, key: key) == "Dear diary — ünïcode ✓")
    }

    @Test func wrongPassphraseIsNil() {
        let kdf = JournalCrypto.Kdf(salt: salt, iterations: 310_000, check: check)
        #expect(JournalCrypto.unlock(passphrase: "correct horse ", kdf: kdf) == nil)
    }

    @Test func roundTripsAndNeverRepeatsANonce() throws {
        let (kdf, key) = try JournalCrypto.makeKdf(passphrase: "pw")
        #expect(kdf.iterations == 310_000)
        #expect(JournalCrypto.unlock(passphrase: "pw", kdf: kdf) != nil)
        let a = try JournalCrypto.encrypt("hello", key: key), b = try JournalCrypto.encrypt("hello", key: key)
        #expect(a != b)
        #expect(a.hasPrefix("enc:v1:"))
        #expect(try JournalCrypto.decrypt(a, key: key) == "hello")
        #expect(try JournalCrypto.decrypt(b, key: key) == "hello")
    }

    @Test func rejectsPlaintextAndGarbage() throws {
        let key = SymmetricKey(size: .bits256)
        #expect(throws: JournalCrypto.Error.notEncrypted) { try JournalCrypto.decrypt("plain", key: key) }
        #expect(throws: JournalCrypto.Error.malformed) { try JournalCrypto.decrypt("enc:v1:short:AAAA", key: key) }
        #expect(throws: JournalCrypto.Error.wrongPassphrase) { try JournalCrypto.decrypt(entry, key: key) }
    }

    @Test func kdfParsesFromJSON() throws {
        let j = try JSON(data: Data(#"{"salt":"\#(salt)","iterations":310000,"check":"\#(check)"}"#.utf8))
        let kdf = try #require(JournalCrypto.Kdf(j))
        #expect(kdf.salt == salt && kdf.check == check)
        #expect(JournalCrypto.Kdf(.null) == nil)
    }
}
