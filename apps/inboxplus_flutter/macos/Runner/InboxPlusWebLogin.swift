import Foundation
import WebKit
#if os(macOS)
import Cocoa
#else
import UIKit
#endif

enum InboxPlusLoginError: String, Error {
    case unavailable = "login_unavailable"
    case cancelled = "login_cancelled"
    case failed = "login_failed"
}

struct InboxPlusLoginPolicy {
    let domain: String
    let url: URL
    let cookieNames: Set<String>
    let requiredCookieNames: Set<String>

    static func platform(_ platform: String) -> Self? {
        switch platform {
        case "instagram":
            Self(
                domain: "instagram.com", url: URL(string: "https://www.instagram.com/accounts/login/")!,
                cookieNames: ["sessionid", "csrftoken", "ds_user_id"],
                requiredCookieNames: ["sessionid", "csrftoken", "ds_user_id"]
            )
        case "messenger":
            Self(
                domain: "facebook.com", url: URL(string: "https://www.facebook.com/login/")!,
                cookieNames: ["xs", "c_user", "datr"], requiredCookieNames: ["xs", "c_user", "datr"]
            )
        default:
            nil
        }
    }

    func credentials(from cookies: [HTTPCookie]) -> [String: String]? {
        var values: [String: String] = [:]
        for cookie in cookies {
            let host = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard host == domain || host.hasSuffix("." + domain),
                  cookieNames.contains(cookie.name), cookie.isSecure, !cookie.value.isEmpty,
                  cookie.expiresDate.map({ $0 > Date() }) ?? true
            else { continue }
            values[cookie.name] = cookie.value
        }
        return requiredCookieNames.isSubset(of: Set(values.keys)) ? values : nil
    }
}

@MainActor
final class InboxPlusWebLogin: NSObject, WKNavigationDelegate, WKUIDelegate, WKHTTPCookieStoreObserver {
    private var webView: WKWebView?
    private var policy: InboxPlusLoginPolicy?
    private var completion: ((Result<[String: String], InboxPlusLoginError>) -> Void)?
    #if os(macOS)
    private var loginWindow: NSWindow?
    #else
    private var loginController: UINavigationController?
    #endif

    func start(
        platform: String,
        completion: @escaping (Result<[String: String], InboxPlusLoginError>) -> Void
    ) {
        guard self.completion == nil, let policy = InboxPlusLoginPolicy.platform(platform) else {
            completion(.failure(.unavailable))
            return
        }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.policy = policy
        self.completion = completion
        self.webView = webView
        webView.navigationDelegate = self
        webView.uiDelegate = self
        configuration.websiteDataStore.httpCookieStore.add(self)
        #if os(macOS)
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 720),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false
        )
        window.title = "Sign in to \(platform == "instagram" ? "Instagram" : "Messenger")"
        window.isReleasedWhenClosed = false
        window.contentView = webView
        window.delegate = self
        window.center()
        loginWindow = window
        window.makeKeyAndOrderFront(nil)
        #else
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              var presenter = scene.windows.first(where: \.isKeyWindow)?.rootViewController
        else {
            finish(.failure(.unavailable))
            return
        }
        while let presented = presenter.presentedViewController { presenter = presented }
        let controller = UIViewController()
        controller.view = webView
        controller.title = "Sign in to \(platform == "instagram" ? "Instagram" : "Messenger")"
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancel)
        )
        let navigation = UINavigationController(rootViewController: controller)
        loginController = navigation
        navigation.presentationController?.delegate = self
        presenter.present(navigation, animated: true)
        navigation.presentationController?.delegate = self
        #endif
        webView.load(URLRequest(url: policy.url))
    }

    func cookiesDidChange(in cookieStore: WKHTTPCookieStore) {
        captureCredentials()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        captureCredentials()
    }

    func webView(
        _ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        decisionHandler(navigationAction.request.url?.scheme?.lowercased() == "https" ? .allow : .cancel)
    }

    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil, navigationAction.request.url?.scheme?.lowercased() == "https" {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        finish(.failure(.failed))
    }

    private func captureCredentials() {
        guard let webView, let policy, completion != nil else { return }
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self, self.webView === webView,
                  let values = policy.credentials(from: cookies) else { return }
            self.finish(.success(values))
        }
    }

    private func finish(_ result: Result<[String: String], InboxPlusLoginError>) {
        guard let completion else { return }
        self.completion = nil
        webView?.configuration.websiteDataStore.httpCookieStore.remove(self)
        webView?.stopLoading()
        webView?.navigationDelegate = nil
        webView?.uiDelegate = nil
        #if os(macOS)
        loginWindow?.close()
        loginWindow = nil
        #else
        loginController?.dismiss(animated: true)
        loginController = nil
        #endif
        webView = nil
        policy = nil
        completion(result)
    }

    @objc func cancel() { finish(.failure(.cancelled)) }
}

#if os(macOS)
extension InboxPlusWebLogin: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) { finish(.failure(.cancelled)) }
}
#else
extension InboxPlusWebLogin: UIAdaptivePresentationControllerDelegate {
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        finish(.failure(.cancelled))
    }
}
#endif
