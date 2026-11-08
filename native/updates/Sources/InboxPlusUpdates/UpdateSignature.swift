import CryptoKit
import Foundation

public enum UpdateSignature {
    public static func verify(data: Data, publicKey: String, signature: String) -> Bool {
        guard let keyData = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData),
              let signature = Data(base64Encoded: signature) else { return false }
        return key.isValidSignature(signature, for: data)
    }
}
