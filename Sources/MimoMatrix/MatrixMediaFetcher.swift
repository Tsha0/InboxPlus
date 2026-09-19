import Foundation
import MatrixRustSDK
import MimoCore
import MimoGateway

/// Fetches media bytes through the Matrix SDK.
///
/// The rest of Mimo only ever holds a `MediaHandle`, so this is the single place that knows an
/// `mxc://` URI is what it contains. The SDK handles authenticated media and decryption for
/// encrypted rooms, which is why the bytes are asked of it rather than of a plain HTTP client.
public struct MatrixMediaFetcher: RemoteMediaFetching {
    private let client: MimoMatrixClient

    public init(client: MimoMatrixClient) {
        self.client = client
    }

    public func fetch(_ handle: MediaHandle) async throws -> Data {
        let source = try MediaSource.fromUrl(url: handle.source)
        return try await client.requireClient().getMediaContent(mediaSource: source)
    }
}
