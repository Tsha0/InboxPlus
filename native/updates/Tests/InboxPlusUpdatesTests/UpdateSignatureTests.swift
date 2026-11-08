import CryptoKit
import Foundation
import XCTest
@testable import InboxPlusUpdates

final class UpdateSignatureTests: XCTestCase {
    func testArchiveMustMatchBothSigningKeyAndExactBytes() throws {
        let key = Curve25519.Signing.PrivateKey()
        let data = Data("release archive".utf8)
        let signature = try key.signature(for: data).base64EncodedString()
        let publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        XCTAssertTrue(UpdateSignature.verify(data: data, publicKey: publicKey, signature: signature))
        XCTAssertFalse(UpdateSignature.verify(data: Data("modified archive".utf8), publicKey: publicKey, signature: signature))
        XCTAssertFalse(UpdateSignature.verify(data: data, publicKey: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString(), signature: signature))
        XCTAssertFalse(UpdateSignature.verify(data: data, publicKey: "invalid", signature: signature))
        XCTAssertFalse(UpdateSignature.verify(data: data, publicKey: publicKey, signature: "invalid"))
    }
}
