// SPDX-License-Identifier: GPL-3.0-only
// A local stand-in provider for the smoke (ios/prd.json IOS-005): it
// answers Test connection inside the app, through the real URLSession,
// once for each verdict, without a network or a server.
import Foundation
import MurmurCore

final class StubProtocol: URLProtocol {
    /// One stand-in host for each answer Test connection can give.
    enum Answer: String, CaseIterable {
        case works, rejected, offline, message

        var baseUrl: String { "https://\(rawValue).stub.invalid/v1" }

        var expected: ConnectionVerdict {
            switch self {
            case .works: .works
            case .rejected: .keyRejected(status: 401)
            case .offline: .noConnection
            case .message: .providerMessage("Model overloaded")
            }
        }
    }

    /// The only key the works host accepts, so a missing header fails.
    static let key = "smoke-not-a-real-key-1234"

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host?.hasSuffix(".stub.invalid") == true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url,
              let answer = url.host?.split(separator: ".").first.flatMap({ Answer(rawValue: String($0)) })
        else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let authorized = request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.key)"
        let (status, body): (Int, String)
        switch answer {
        case .offline:
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        case .works:
            (status, body) = authorized ? (200, #"{"data":[]}"#) : (401, "{}")
        case .rejected:
            (status, body) = (401, #"{"error":{"message":"Invalid API Key"}}"#)
        case .message:
            (status, body) = (503, #"{"error":{"message":"Model overloaded"}}"#)
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])
        if let response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
