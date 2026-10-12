// SPDX-License-Identifier: GPL-3.0-only
// The Provider screen's state (ios/prd.json IOS-005): which presets are
// picked for transcription and cleanup, and one key slot for each. The
// choices save to ConnectionStore as they change; keys go to the key ring.
import Foundation
import MurmurCore
import Observation

@Observable @MainActor
final class ProviderModel {
    let catalog: ProviderCatalog
    private(set) var settings: ConnectionSettings
    let transcriptionKey: KeySlot
    let cleanupKey: KeySlot
    @ObservationIgnored private let store: ConnectionStore

    init(catalog: ProviderCatalog, store: ConnectionStore, ring: any KeyRing, send: @escaping ConnectionTest.Send) {
        self.catalog = catalog
        self.store = store
        let settings = store.load(catalog: catalog)
        self.settings = settings
        transcriptionKey = KeySlot(baseUrl: settings.transcription.baseUrl, catalog: catalog, ring: ring, send: send)
        cleanupKey = KeySlot(baseUrl: settings.cleanupBaseUrl, catalog: catalog, ring: ring, send: send)
    }

    var transcriptionPreset: ProviderCatalog.Provider? { catalog.preset(forBaseUrl: settings.transcription.baseUrl) }
    var cleanupPreset: ProviderCatalog.Provider? { catalog.preset(forBaseUrl: settings.cleanupBaseUrl) }

    /// Separate cleanup at transcription's address uses transcription's key.
    var cleanupSharesKey: Bool {
        !settings.cleanup.separate
            || BaseURL.normalized(settings.cleanup.baseUrl) == BaseURL.normalized(settings.transcription.baseUrl)
    }

    /// A preset fills the address and its first models; nil keeps the
    /// address for editing as Custom.
    func chooseTranscription(_ preset: ProviderCatalog.Provider?) {
        guard let preset else {
            if transcriptionPreset != nil { update { $0.transcription.baseUrl = "" } }
            return
        }
        update {
            $0.transcription.baseUrl = preset.url(for: .transcription)
            $0.transcription.sttModel = preset.sttModels.first?.id ?? $0.transcription.sttModel
            $0.transcription.llmModel = preset.llmModels.first?.id ?? $0.transcription.llmModel
        }
    }

    func chooseCleanup(_ preset: ProviderCatalog.Provider?) {
        guard let preset else {
            if cleanupPreset != nil { update { $0.cleanup.baseUrl = "" } }
            return
        }
        update {
            $0.cleanup.baseUrl = preset.url(for: .cleanup)
            $0.cleanup.llmModel = preset.llmModels.first?.id ?? $0.cleanup.llmModel
        }
    }

    func setSeparateCleanup(_ separate: Bool) { update { $0.cleanup.separate = separate } }
    func setTranscriptionBaseUrl(_ url: String) { update { $0.transcription.baseUrl = url } }
    func setSttModel(_ model: String) { update { $0.transcription.sttModel = model } }
    func setCleanupBaseUrl(_ url: String) { update { $0.cleanup.baseUrl = url } }

    /// The cleanup model, wherever cleanup runs.
    func setCleanupModel(_ model: String) {
        update {
            if $0.cleanup.separate { $0.cleanup.llmModel = model } else { $0.transcription.llmModel = model }
        }
    }

    private func update(_ change: (inout ConnectionSettings) -> Void) {
        var next = settings
        change(&next)
        guard next != settings else { return }
        settings = next
        store.save(next)
        transcriptionKey.point(at: next.transcription.baseUrl)
        cleanupKey.point(at: next.cleanupBaseUrl)
    }
}

enum TestState: Equatable {
    case idle
    case testing
    case done(ConnectionVerdict)
}

/// One provider's key: the field, the saved mask, and the test.
@Observable @MainActor
final class KeySlot {
    private(set) var baseUrl: String
    var draft = ""
    /// The saved key's mask; the key itself is read only to send it.
    private(set) var masked: String?
    private(set) var test: TestState = .idle
    /// A Keychain failure, said plainly.
    private(set) var failure: String?
    @ObservationIgnored private let catalog: ProviderCatalog
    @ObservationIgnored private let ring: any KeyRing
    @ObservationIgnored private let send: ConnectionTest.Send

    init(baseUrl: String, catalog: ProviderCatalog, ring: any KeyRing, send: @escaping ConnectionTest.Send) {
        self.baseUrl = baseUrl
        self.catalog = catalog
        self.ring = ring
        self.send = send
        reload()
    }

    var note: KeyNote? { catalog.keyNote(for: draft, baseUrl: baseUrl) }
    var addressProblem: String? { BaseURL.problem(baseUrl) }
    var canSave: Bool { addressProblem == nil && APIKey(draft) != nil }
    var canTest: Bool { addressProblem == nil && masked != nil && test != .testing }

    /// Follows a new address: that provider's saved key, and no verdict,
    /// since one earned against another address never vouches for this one.
    func point(at baseUrl: String) {
        guard BaseURL.normalized(baseUrl) != BaseURL.normalized(self.baseUrl) else { return }
        self.baseUrl = baseUrl
        draft = ""
        test = .idle
        reload()
    }

    func save() {
        guard canSave, let key = APIKey(draft) else { return }
        attempt { try ring.save(key, for: baseUrl) }
        if failure == nil {
            draft = ""
            test = .idle
            reload()
        }
    }

    func remove() {
        attempt { try ring.remove(for: baseUrl) }
        test = .idle
        reload()
    }

    func runTest() async {
        guard canTest else { return }
        let key: APIKey?
        do {
            key = try ring.key(for: baseUrl)
        } catch {
            failure = Self.words(for: error)
            return
        }
        guard let key else { return }
        test = .testing
        let tested = baseUrl
        let verdict = await ConnectionTest.run(baseUrl: tested, key: key, send: send)
        if BaseURL.normalized(tested) == BaseURL.normalized(baseUrl) { test = .done(verdict) }
    }

    private func reload() {
        do {
            masked = try ring.key(for: baseUrl)?.masked
            failure = nil
        } catch {
            masked = nil
            failure = Self.words(for: error)
        }
    }

    private func attempt(_ work: () throws -> Void) {
        do {
            try work()
            failure = nil
        } catch {
            failure = Self.words(for: error)
        }
    }

    private static func words(for error: Error) -> String {
        if case KeychainError.status(let status) = error {
            return "murmur could not reach the Keychain (code \(status)). Try again."
        }
        return "murmur could not reach the Keychain. Try again."
    }
}

extension KeySlot {
    /// A slot in a fixed state, for previews.
    static func preview(baseUrl: String, catalog: ProviderCatalog, saved: String? = nil, draft: String = "", test: TestState = .idle) -> KeySlot {
        let ring = MemoryKeyRing()
        if let saved, let key = APIKey(saved) { try? ring.save(key, for: baseUrl) }
        let slot = KeySlot(baseUrl: baseUrl, catalog: catalog, ring: ring, send: { _ in throw URLError(.notConnectedToInternet) })
        slot.draft = draft
        slot.test = test
        return slot
    }
}
