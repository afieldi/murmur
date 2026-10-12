// SPDX-License-Identifier: GPL-3.0-only
// The headless smoke (npm run ios:smoke): launched with --smoke, the app
// runs every subsystem check, prints one SMOKE_RESULT line, and exits.
// The same contract as desktop's smoke: {"ok": Bool, "checks": {name: Bool}},
// and a failed check explains itself on a line starting "smoke <name>:".
import Foundation
import MurmurCore
import Synchronization

struct SmokeRequest: Equatable {
    /// How many shared rule files the build bundled; -1 when not given,
    /// which no real count matches.
    let sharedCount: Int

    /// Nil unless the app was launched with --smoke.
    init?(arguments: [String]) {
        guard arguments.contains("--smoke") else { return nil }
        let prefix = "--shared-count="
        sharedCount = arguments.lazy
            .filter { $0.hasPrefix(prefix) }
            .compactMap { Int($0.dropFirst(prefix.count)) }
            .first ?? -1
    }
}

struct SmokeFailure: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

enum SmokeRunner {
    static func runAndExit(_ request: SmokeRequest) -> Never {
        let checks: [(name: String, run: () throws -> Void)] = [
            ("appGroup", checkAppGroup),
            ("keychain", checkKeychain),
            ("keyRing", checkKeyRing),
            ("connectionTest", checkConnectionTest),
            ("sharedJson", { try checkSharedJson(expected: request.sharedCount) })
        ]
        var results: [String: Bool] = [:]
        for check in checks {
            do {
                try check.run()
                results[check.name] = true
            } catch {
                results[check.name] = false
                emit("smoke \(check.name): \(error)")
            }
        }
        let ok = results.values.allSatisfy { $0 }
        let payload: [String: Any] = ["ok": ok, "checks": results]
        let json = (try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])) ?? Data()
        emit("SMOKE_RESULT " + String(decoding: json, as: UTF8.self))
        exit(ok ? 0 : 1)
    }

    /// Unbuffered, so nothing is lost when the app exits right after.
    private static func emit(_ line: String) {
        FileHandle.standardOutput.write(Data((line + "\n").utf8))
    }

    static func checkAppGroup() throws {
        guard let container = AppGroup.containerURL else {
            throw SmokeFailure("no container for \(AppGroup.identifier)")
        }
        let probe = container.appendingPathComponent("smoke-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: probe) }
        try Data("murmur smoke".utf8).write(to: probe)
        let back = try String(contentsOf: probe, encoding: .utf8)
        guard back == "murmur smoke" else { throw SmokeFailure("read back \(back)") }
    }

    static func checkKeychain() throws {
        let store = KeychainStore(service: "com.lbwalton.murmur.ios.smoke")
        let account = "smoke"
        defer { try? store.delete(account: account) }
        try store.save("not-a-real-key", account: account)
        guard try store.read(account: account) == "not-a-real-key" else {
            throw SmokeFailure("read back a different value")
        }
        try store.delete(account: account)
        guard try store.read(account: account) == nil else {
            throw SmokeFailure("delete left the item behind")
        }
    }

    /// A dummy key through the key ring: saved, read back, filed in the
    /// app's own Keychain access group (never the app group, which the
    /// keyboard can read), kept out of the app's defaults, and deleted.
    static func checkKeyRing() throws {
        let ring = KeychainKeyRing()
        let url = "https://smoke.invalid/v1/"
        defer { try? ring.remove(for: url) }
        guard let key = APIKey(StubProtocol.key) else { throw SmokeFailure("the dummy key did not parse") }
        try ring.save(key, for: url)
        guard try ring.key(for: "https://smoke.invalid/v1") == key else {
            throw SmokeFailure("read back a different key")
        }
        let group = try ring.store.accessGroup(account: BaseURL.normalized(url)) ?? ""
        guard group != AppGroup.identifier, group.hasSuffix("." + (Bundle.main.bundleIdentifier ?? "?")) else {
            throw SmokeFailure("the key sits in access group \(group)")
        }
        guard !"\(UserDefaults.standard.dictionaryRepresentation())".contains(key.secret) else {
            throw SmokeFailure("the key reached the app's defaults")
        }
        try ring.remove(for: url)
        guard try ring.key(for: url) == nil else { throw SmokeFailure("remove left the key behind") }
    }

    /// Test connection against the local stand-in, once for each answer.
    static func checkConnectionTest() throws {
        guard let key = APIKey(StubProtocol.key) else { throw SmokeFailure("the dummy key did not parse") }
        let session = StubProtocol.session()
        for answer in StubProtocol.Answer.allCases {
            let verdict = waitFor { await ConnectionTest.run(baseUrl: answer.baseUrl, key: key, send: { try await session.data(for: $0) }) }
            guard verdict == answer.expected else {
                throw SmokeFailure("\(answer.rawValue) gave \(verdict), expected \(answer.expected)")
            }
        }
    }

    /// Runs async work to the end from the smoke's synchronous start.
    private static func waitFor<T: Sendable>(_ work: @escaping @Sendable () async -> T) -> T {
        let result = Mutex<T?>(nil)
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            let value = await work()
            result.withLock { $0 = value }
            done.signal()
        }
        done.wait()
        guard let value = result.withLock({ $0 }) else { preconditionFailure("the work signaled without a value") }
        return value
    }

    static func checkSharedJson(expected: Int) throws {
        guard let directory = Bundle.main.url(forResource: "shared", withExtension: nil) else {
            throw SmokeFailure("no shared folder in the app bundle")
        }
        let names = try SharedData(directory: directory).validateAll()
        guard names.count == expected else {
            throw SmokeFailure("bundled \(names.count) shared rules, expected \(expected)")
        }
    }
}
