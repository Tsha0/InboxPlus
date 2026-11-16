import Foundation
import XCTest
@testable import Runner

final class RunnerTests: XCTestCase {
    func testInstagramCapturesOnlyDeclaredSecureCookiesOnOwnedDomains() throws {
        let policy = try XCTUnwrap(InboxPlusLoginPolicy.platform("instagram"))
        let cookies = [
            cookie("sessionid", domain: ".instagram.com"),
            cookie("csrftoken", domain: "www.instagram.com"),
            cookie("ds_user_id", domain: ".instagram.com"),
            cookie("unrelated", domain: ".instagram.com"),
            cookie("sessionid", domain: "instagram.com.example.org", value: "foreign"),
        ]

        XCTAssertEqual(policy.credentials(from: cookies), ["sessionid": "fixture", "csrftoken": "fixture", "ds_user_id": "fixture"])
    }

    func testMissingExpiredAndInsecureCredentialsCannotCompleteLogin() throws {
        let policy = try XCTUnwrap(InboxPlusLoginPolicy.platform("instagram"))
        let supporting = [cookie("csrftoken", domain: ".instagram.com"), cookie("ds_user_id", domain: ".instagram.com")]

        XCTAssertNil(policy.credentials(from: supporting))
        XCTAssertNil(policy.credentials(from: supporting + [cookie("sessionid", domain: ".instagram.com", secure: false)]))
        XCTAssertNil(policy.credentials(from: supporting + [cookie("sessionid", domain: ".instagram.com", expires: Date(timeIntervalSince1970: 0))]))
        XCTAssertNil(InboxPlusLoginPolicy.platform("unsupported"))
    }

    func testMessengerCapturesItsOwnCredentials() throws {
        let policy = try XCTUnwrap(InboxPlusLoginPolicy.platform("messenger"))
        let cookies = [cookie("xs", domain: ".facebook.com"), cookie("c_user", domain: ".facebook.com"), cookie("datr", domain: ".facebook.com")]

        XCTAssertEqual(policy.credentials(from: cookies), ["xs": "fixture", "c_user": "fixture", "datr": "fixture"])
        XCTAssertNil(policy.credentials(from: [cookie("xs", domain: ".facebook.com"), cookie("c_user", domain: ".facebook.com")]))
        XCTAssertNil(policy.credentials(from: [cookie("xs", domain: ".instagram.com"), cookie("c_user", domain: ".facebook.com")]))
    }

    private func cookie(
        _ name: String, domain: String, value: String = "fixture", secure: Bool = true,
        expires: Date = Date().addingTimeInterval(3_600)
    ) -> HTTPCookie {
        var properties: [HTTPCookiePropertyKey: Any] = [.name: name, .value: value, .domain: domain, .path: "/", .expires: expires]
        if secure { properties[.secure] = "TRUE" }
        return HTTPCookie(properties: properties)!
    }
}
