// SPDX-License-Identifier: GPL-3.0-only
// The Provider screen (ios/prd.json IOS-005): pick who turns your voice
// into text and who cleans it up, paste each key once, and test it. The
// presets come from shared/provider-catalog.json, Groq first; Custom
// takes any OpenAI-compatible https address.
import MurmurCore
import SwiftUI

struct ProviderScreen: View {
    @State var model: ProviderModel

    var body: some View {
        Form {
            Section {
                presetPicker(role: .transcription)
                if model.transcriptionPreset == nil {
                    AddressField(url: model.settings.transcription.baseUrl, set: model.setTranscriptionBaseUrl)
                }
                ModelField(
                    label: "Transcription model",
                    value: model.settings.transcription.sttModel,
                    options: model.transcriptionPreset?.sttModels.map(\.id) ?? [],
                    set: model.setSttModel
                )
                KeySlotView(
                    slot: model.transcriptionKey,
                    provider: ProviderName.of(model.transcriptionPreset, baseUrl: model.settings.transcription.baseUrl),
                    keyPage: model.transcriptionPreset?.keyUrl.flatMap(URL.init(string:))
                )
            } header: {
                SectionTitle("Transcription")
            } footer: {
                Text("Turns what you say into text.").foregroundStyle(Tokens.textDim)
            }
            .listRowBackground(Tokens.panel)

            Section {
                Picker("Cleanup runs on", selection: Binding(get: { model.settings.cleanup.separate }, set: model.setSeparateCleanup)) {
                    Text("Same as transcription").tag(false)
                    Text("Separate").tag(true)
                }
                .pickerStyle(.segmented)
                if model.settings.cleanup.separate {
                    presetPicker(role: .cleanup)
                    if model.cleanupPreset == nil {
                        AddressField(url: model.settings.cleanup.baseUrl, set: model.setCleanupBaseUrl)
                    }
                }
                ModelField(
                    label: "Cleanup model",
                    value: model.settings.cleanupModel,
                    options: model.cleanupPreset?.llmModels.map(\.id) ?? [],
                    set: model.setCleanupModel
                )
                if model.cleanupSharesKey {
                    Text("Uses your transcription key.")
                        .foregroundStyle(Tokens.textDim)
                } else {
                    KeySlotView(
                        slot: model.cleanupKey,
                        provider: ProviderName.of(model.cleanupPreset, baseUrl: model.settings.cleanup.baseUrl),
                        keyPage: model.cleanupPreset?.keyUrl.flatMap(URL.init(string:))
                    )
                }
            } header: {
                SectionTitle("Cleanup")
            } footer: {
                Text("Fixes punctuation and filler words after each take.").foregroundStyle(Tokens.textDim)
            }
            .listRowBackground(Tokens.panel)

            Section {
                Text("Your keys stay on this iPhone, in its Keychain. Only the murmur app can read them; the keyboard never can, and they never sync to another device.")
                    .font(.footnote)
                    .foregroundStyle(Tokens.textDim)
            }
            .listRowBackground(Tokens.panel)
        }
        .scrollContentBackground(.hidden)
        .background(Tokens.ink)
        .foregroundStyle(Tokens.text)
        .tint(Tokens.brand)
        .navigationTitle("Provider and key")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func presetPicker(role: ProviderRole) -> some View {
        let presets = model.catalog.presets(for: role)
        let current = role == .transcription ? model.transcriptionPreset : model.cleanupPreset
        return Picker("Provider", selection: Binding<String>(
            get: { current?.id ?? "custom" },
            set: { id in
                let preset = presets.first { $0.id == id }
                if role == .transcription { model.chooseTranscription(preset) } else { model.chooseCleanup(preset) }
            }
        )) {
            ForEach(presets, id: \.id) { Text($0.name).tag($0.id) }
            Text("Custom").tag("custom")
        }
    }
}

/// A section title in brand gold, sentence case.
struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Tokens.brand)
            .textCase(nil)
    }
}

/// A custom provider's base URL, with what to fix said under it.
struct AddressField: View {
    let url: String
    let set: @MainActor (String) -> Void

    var body: some View {
        TextField("Base URL", text: Binding(get: { url }, set: set), prompt: Text("https://api.example.com/v1"))
            .keyboardType(.URL)
            .textContentType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
        if let problem = BaseURL.problem(url) {
            Note(text: problem, color: Tokens.red, symbol: "exclamationmark.triangle")
        }
    }
}

/// A model: the preset's suggestions as a picker, or a field for any id,
/// as desktop's ModelPicker offers. The section title says which model,
/// so the row says Model and VoiceOver hears the full name.
struct ModelField: View {
    let label: String
    let value: String
    let options: [String]
    let set: @MainActor (String) -> Void

    var body: some View {
        if options.isEmpty {
            TextField("Model", text: Binding(get: { value }, set: set), prompt: Text("Model id"))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityLabel(label)
        } else {
            Picker("Model", selection: Binding(get: { value }, set: set)) {
                ForEach(options, id: \.self) { id in
                    Text(id).tag(id)
                }
                if !options.contains(value) {
                    Text(value).tag(value)
                }
            }
            .pickerStyle(.navigationLink)
            .accessibilityLabel(label)
        }
    }
}

extension ProviderModel {
    /// The real screen: the bundled catalog, saved choices, the Keychain,
    /// and a session that keeps no cookies or cache.
    static func live() -> ProviderModel? {
        guard let catalog = try? BundledRules.catalog() else { return nil }
        let session = URLSession(configuration: .ephemeral)
        return ProviderModel(catalog: catalog, store: ConnectionStore(), ring: KeychainKeyRing(), send: { try await session.data(for: $0) })
    }
}

/// Opens the Provider screen, built once the catalog is read.
struct ProviderRoute: View {
    @State private var model: ProviderModel?
    @State private var failed = false

    var body: some View {
        Group {
            if let model {
                ProviderScreen(model: model)
            } else if failed {
                Note(text: "murmur could not read its provider list. Reinstall murmur to fix it.", color: Tokens.red, symbol: "exclamationmark.triangle")
                    .padding()
            }
        }
        .task {
            guard model == nil else { return }
            model = ProviderModel.live()
            failed = model == nil
        }
    }
}

#if DEBUG
let previewCatalog: ProviderCatalog = {
    do {
        return try BundledRules.catalog()
    } catch {
        preconditionFailure("the bundled catalog does not load: \(error)")
    }
}()

@MainActor private func previewModel(_ keys: [String: String] = [:]) -> ProviderModel {
    let ring = MemoryKeyRing(Dictionary(uniqueKeysWithValues: keys.compactMap { url, key in APIKey(key).map { (url, $0) } }))
    let defaults = UserDefaults(suiteName: "murmur.previews.\(UUID().uuidString)") ?? .standard
    return ProviderModel(catalog: previewCatalog, store: ConnectionStore(defaults: defaults), ring: ring, send: { _ in throw URLError(.notConnectedToInternet) })
}

#Preview("No key") {
    NavigationStack { ProviderScreen(model: previewModel()) }.preferredColorScheme(.dark)
}

#Preview("Saved key") {
    NavigationStack { ProviderScreen(model: previewModel(["https://api.groq.com/openai/v1": "gsk_abcdefgh1234"])) }.preferredColorScheme(.dark)
}
#endif
