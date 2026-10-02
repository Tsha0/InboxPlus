import Foundation
import Testing
@testable import InboxPlusBridgeService

private final class ArtifactURLProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let url = request.url!
        let length = url.path == "/exact" ? 16 : 17
        var headers: [String: String] = ["Content-Type": "application/octet-stream"]
        if url.path == "/advertised" { headers["Content-Length"] = "17" }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(repeating: 0x61, count: length))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@Test(arguments: ["/unknown-length", "/advertised"])
func streamedArtifactsEnforceSizeLimitAndRemovePartialFiles(_ path: String) async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ArtifactURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent("InboxPlusStreamingTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: destination) }
    let fetcher = URLSessionBridgeArtifactFetcher(maximumBytes: 16, session: session)
    await #expect(throws: (any Error).self) {
        try await fetcher.fetch(URL(string: "https://artifact.test\(path)")!, to: destination)
    }
    #expect(!FileManager.default.fileExists(atPath: destination.path))
}

@Test func streamedArtifactAtTheExactLimitIsWrittenNonExecutable() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ArtifactURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let destination = FileManager.default.temporaryDirectory
        .appendingPathComponent("InboxPlusStreamingTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: destination) }
    let fetcher = URLSessionBridgeArtifactFetcher(maximumBytes: 16, session: session)
    #expect(try await fetcher.fetch(URL(string: "https://artifact.test/exact")!, to: destination) == 200)
    #expect(try Data(contentsOf: destination) == Data(repeating: 0x61, count: 16))
    #expect(try FileManager.default.attributesOfItem(atPath: destination.path)[.posixPermissions] as? Int == 0o600)
}
