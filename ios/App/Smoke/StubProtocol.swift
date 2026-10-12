// SPDX-License-Identifier: GPL-3.0-only
// A local stand-in provider for the smoke (ios/prd.json IOS-005, IOS-006,
// IOS-007): it answers Test connection, transcriptions, and polish inside
// the app, through the real URLSession, without a network or a server.
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

    /// The transcription stand-ins: one that hears words, one that is down.
    static let wordsBaseUrl = "https://words.stub.invalid/v1"
    static let downBaseUrl = "https://down.stub.invalid/v1"

    /// What the words host hears when a whole take reaches it.
    static let words = "smoke words from the stand-in"

    /// The cleanup stand-ins (IOS-007): one that errors, one that chats.
    static let chatErrorBaseUrl = "https://chaterror.stub.invalid/v1"
    static let chattyBaseUrl = "https://chatty.stub.invalid/v1"

    /// The only key the stand-ins accept, so a missing header fails.
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
        guard let url = request.url, let name = url.host?.split(separator: ".").first.map(String.init) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let authorized = request.value(forHTTPHeaderField: "Authorization") == "Bearer \(Self.key)"
        let (status, body): (Int, String)
        switch (name, Answer(rawValue: name)) {
        case ("words", _):
            (status, body) = !authorized ? (401, "{}") : Self.isWholeTake(request) ? (200, #"{"text":"\#(Self.words)"}"#) : (400, "{}")
        case ("down", _):
            (status, body) = (503, #"{"error":{"message":"Service unavailable"}}"#)
        case ("chaterror", _):
            (status, body) = (500, #"{"error":{"message":"Internal error"}}"#)
        case ("chatty", _):
            (status, body) = (200, #"{"choices":[{"message":{"content":"Sure! Here is the cleaned text: send the report."}}]}"#)
        case (_, .offline?):
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        case (_, .works?):
            (status, body) = authorized ? (200, #"{"data":[]}"#) : (401, "{}")
        case (_, .rejected?):
            (status, body) = (401, #"{"error":{"message":"Invalid API Key"}}"#)
        case (_, .message?):
            (status, body) = (503, #"{"error":{"message":"Model overloaded"}}"#)
        case (_, nil):
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"])
        if let response { client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed) }
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    /// A take reached us whole: a form with a WAV file and a model in it.
    /// URLSession hands a protocol the body as a stream.
    private static func isWholeTake(_ request: URLRequest) -> Bool {
        guard let body = request.httpBody ?? request.httpBodyStream.map(read) else { return false }
        let text = String(decoding: body, as: UTF8.self)
        return body.range(of: Data("RIFF".utf8)) != nil && body.range(of: Data("WAVE".utf8)) != nil
            && text.contains(#"filename="audio.wav""#) && text.contains(#"name="model""#)
    }

    private static func read(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }
}
