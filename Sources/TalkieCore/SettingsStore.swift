import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    static let apiKeyKey = "Talkie.ApiKey"
    static let transcriptionProviderKey = "Talkie.TranscriptionProvider"
    static let elevenLabsApiKeyKey = "Talkie.ElevenLabsApiKey"
    static let museApiKeyKey = "Talkie.MuseApiKey"
    static let deepgramLanguageKey = "Talkie.DeepgramLanguage"
    static let automaticLanguageCandidatesKey = "Talkie.AutomaticLanguageCandidates"
    static let starredDeepgramLanguagesKey = "Talkie.StarredDeepgramLanguages"
    static let historyLimitKey = "Talkie.HistoryLimit"
    static let shortcutsKey = "Talkie.Shortcuts"
    static let enhancementProviderKey = "Talkie.EnhancementProvider"
    static let openRouterApiKeyKey = "Talkie.OpenRouterApiKey"
    static let openRouterModelKey = "Talkie.OpenRouterModel"
    static let celerisApiKeyKey = "Talkie.CelerisApiKey"
    static let promptsKey = "Talkie.Prompts"
    static let legacyEnhancementPromptsKey = "Talkie.EnhancementPrompts"
    static let escToCancelRecordingKey = "Talkie.EscToCancelRecording"
    static let playSoundEffectsKey = "Talkie.PlaySoundEffects"
    static let muteMediaDuringRecordingKey = "Talkie.MuteMediaDuringRecording"
    static let restoreClipboardAfterPasteKey = "Talkie.RestoreClipboardAfterPaste"
    static let showSelectedLanguageInMenuBarKey = "Talkie.ShowSelectedLanguageInMenuBar"
    static let showLanguageInRecorderWidgetKey = "Talkie.ShowLanguageInRecorderWidget"
    static let showLiveTranscriptInRecorderWidgetKey = "Talkie.ShowLiveTranscriptInRecorderWidget"
    static let overlayPositionKey = "Talkie.OverlayPosition"
    static let audioInputSelectionKey = "Talkie.AudioInputSelection"
    static let appTranscriptionLanguageOverridesKey = "Talkie.AppTranscriptionLanguageOverrides"

    private let defaults: UserDefaults

    @Published var apiKey: String {
        didSet {
            defaults.set(apiKey, forKey: Self.apiKeyKey)
        }
    }

    @Published var transcriptionProvider: TranscriptionProvider {
        didSet {
            defaults.set(transcriptionProvider.rawValue, forKey: Self.transcriptionProviderKey)
        }
    }

    @Published var elevenLabsApiKey: String {
        didSet {
            defaults.set(elevenLabsApiKey, forKey: Self.elevenLabsApiKeyKey)
        }
    }

    @Published var museApiKey: String {
        didSet {
            defaults.set(museApiKey, forKey: Self.museApiKeyKey)
        }
    }

    @Published var shortcuts: [ShortcutConfig] {
        didSet {
            if let data = try? JSONEncoder().encode(shortcuts) {
                defaults.set(data, forKey: Self.shortcutsKey)
            }
        }
    }

    @Published var openRouterApiKey: String {
        didSet {
            defaults.set(openRouterApiKey, forKey: Self.openRouterApiKeyKey)
        }
    }

    @Published var celerisApiKey: String {
        didSet {
            defaults.set(celerisApiKey, forKey: Self.celerisApiKeyKey)
        }
    }

    @Published var prompts: [PromptConfig] {
        didSet {
            if let data = try? JSONEncoder().encode(prompts) {
                defaults.set(data, forKey: Self.promptsKey)
            }
        }
    }

    @Published var escToCancelRecording: Bool {
        didSet {
            defaults.set(escToCancelRecording, forKey: Self.escToCancelRecordingKey)
        }
    }

    @Published var playSoundEffects: Bool {
        didSet {
            defaults.set(playSoundEffects, forKey: Self.playSoundEffectsKey)
        }
    }

    @Published var muteMediaDuringRecording: Bool {
        didSet {
            defaults.set(muteMediaDuringRecording, forKey: Self.muteMediaDuringRecordingKey)
        }
    }

    @Published var restoreClipboardAfterPaste: Bool {
        didSet {
            defaults.set(restoreClipboardAfterPaste, forKey: Self.restoreClipboardAfterPasteKey)
        }
    }

    @Published var showSelectedLanguageInMenuBar: Bool {
        didSet {
            defaults.set(showSelectedLanguageInMenuBar, forKey: Self.showSelectedLanguageInMenuBarKey)
        }
    }

    @Published var showLanguageInRecorderWidget: Bool {
        didSet {
            defaults.set(showLanguageInRecorderWidget, forKey: Self.showLanguageInRecorderWidgetKey)
        }
    }

    @Published var showLiveTranscriptInRecorderWidget: Bool {
        didSet {
            defaults.set(showLiveTranscriptInRecorderWidget, forKey: Self.showLiveTranscriptInRecorderWidgetKey)
        }
    }

    @Published var overlayPosition: OverlayPosition {
        didSet {
            defaults.set(overlayPosition.rawValue, forKey: Self.overlayPositionKey)
        }
    }

    @Published var audioInputSelection: AudioInputSelection {
        didSet {
            defaults.set(audioInputSelection.storedValue, forKey: Self.audioInputSelectionKey)
        }
    }

    @Published var deepgramLanguage: DeepgramLanguage {
        didSet {
            defaults.set(deepgramLanguage.rawValue, forKey: Self.deepgramLanguageKey)
        }
    }

    @Published var automaticLanguageCandidates: [DeepgramLanguage] {
        didSet {
            let normalized = TranscriptionProvider.elevenLabs.normalizedAutomaticLanguageCandidates(
                automaticLanguageCandidates
            )
            if normalized != automaticLanguageCandidates {
                automaticLanguageCandidates = normalized
                return
            }

            defaults.set(normalized.map(\.rawValue), forKey: Self.automaticLanguageCandidatesKey)
        }
    }

    @Published var starredDeepgramLanguages: [DeepgramLanguage] {
        didSet {
            let normalized = DeepgramLanguage.normalizedStarredLanguages(
                starredDeepgramLanguages,
                fallback: oldValue.isEmpty ? DeepgramLanguage.defaultStarredLanguages : oldValue
            )

            if normalized != starredDeepgramLanguages {
                starredDeepgramLanguages = normalized
                return
            }

            defaults.set(normalized.map(\.rawValue), forKey: Self.starredDeepgramLanguagesKey)
        }
    }

    @Published var historyLimit: HistoryLimit {
        didSet {
            defaults.set(historyLimit.rawValue, forKey: Self.historyLimitKey)
        }
    }

    @Published var appTranscriptionLanguageOverrides: [AppTranscriptionLanguageOverride] {
        didSet {
            if let data = try? JSONEncoder().encode(appTranscriptionLanguageOverrides) {
                defaults.set(data, forKey: Self.appTranscriptionLanguageOverridesKey)
            }
        }
    }

    func enhancementProviderSettings(
        provider: EnhancementProvider,
        model: String
    ) -> EnhancementProviderSettings {
        switch provider {
        case .openRouter:
            EnhancementProviderSettings(
                provider: .openRouter,
                apiKey: openRouterApiKey.trimmed,
                model: model.trimmed
            )
        case .celeris:
            EnhancementProviderSettings(
                provider: .celeris,
                apiKey: celerisApiKey.trimmed,
                model: model.trimmed
            )
        }
    }

    func enhancementProviderSettings(for prompt: EnhancementPromptContext) -> EnhancementProviderSettings {
        enhancementProviderSettings(provider: prompt.provider, model: prompt.model)
    }

    func enhancementProviderSettings(for entry: TranscriptHistoryEntry) -> EnhancementProviderSettings {
        let provider = entry.enhancementProvider ?? legacyEnhancementProvider
        let savedModel = (entry.enhancementModel?.trimmed)
            .flatMap { $0.isEmpty ? nil : $0 }
        let model = savedModel ?? legacyModel(for: provider)
        return enhancementProviderSettings(provider: provider, model: model)
    }

    var transcriptionProviderSettings: TranscriptionProviderSettings {
        let apiKey = switch transcriptionProvider {
        case .deepgram:
            apiKey
        case .elevenLabs:
            elevenLabsApiKey
        case .muse:
            museApiKey
        }
        return TranscriptionProviderSettings(
            provider: transcriptionProvider,
            apiKey: apiKey.trimmed,
            automaticLanguageCandidates: automaticLanguageCandidates
        )
    }

    private let legacyEnhancementProvider: EnhancementProvider
    private let legacyOpenRouterModel: String

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        apiKey = defaults.string(forKey: Self.apiKeyKey) ?? ""
        transcriptionProvider = defaults.string(forKey: Self.transcriptionProviderKey)
            .flatMap(TranscriptionProvider.init(rawValue:)) ?? .deepgram
        elevenLabsApiKey = defaults.string(forKey: Self.elevenLabsApiKeyKey) ?? ""
        museApiKey = defaults.string(forKey: Self.museApiKeyKey) ?? ""
        escToCancelRecording = (defaults.object(forKey: Self.escToCancelRecordingKey) as? Bool) ?? true
        playSoundEffects = (defaults.object(forKey: Self.playSoundEffectsKey) as? Bool) ?? false
        muteMediaDuringRecording = (defaults.object(forKey: Self.muteMediaDuringRecordingKey) as? Bool) ?? false
        restoreClipboardAfterPaste = (defaults.object(forKey: Self.restoreClipboardAfterPasteKey) as? Bool) ?? false
        showSelectedLanguageInMenuBar = (defaults.object(forKey: Self.showSelectedLanguageInMenuBarKey) as? Bool) ?? false
        showLanguageInRecorderWidget = (defaults.object(forKey: Self.showLanguageInRecorderWidgetKey) as? Bool) ?? true
        showLiveTranscriptInRecorderWidget = (defaults.object(forKey: Self.showLiveTranscriptInRecorderWidgetKey) as? Bool) ?? true

        let savedPosition = defaults.string(forKey: Self.overlayPositionKey)
        overlayPosition = savedPosition.flatMap(OverlayPosition.init(rawValue:)) ?? .top

        audioInputSelection = AudioInputSelection(
            storedValue: defaults.string(forKey: Self.audioInputSelectionKey)
        )

        let savedLanguage = defaults.string(forKey: Self.deepgramLanguageKey)
        deepgramLanguage = savedLanguage.flatMap(DeepgramLanguage.init(rawValue:)) ?? .automatic
        let savedAutomaticLanguageCandidates = defaults.stringArray(forKey: Self.automaticLanguageCandidatesKey)?
            .compactMap(DeepgramLanguage.init(rawValue:))
        automaticLanguageCandidates = TranscriptionProvider.elevenLabs.normalizedAutomaticLanguageCandidates(
            savedAutomaticLanguageCandidates
                ?? TranscriptionProvider.elevenLabs.defaultAutomaticLanguageCandidates
        )
        starredDeepgramLanguages = DeepgramLanguage.starredLanguages(
            from: defaults.stringArray(forKey: Self.starredDeepgramLanguagesKey)
        )

        let savedLimit = defaults.object(forKey: Self.historyLimitKey) as? Int
        historyLimit = savedLimit.flatMap(HistoryLimit.init(rawValue:)) ?? .ten

        if let data = defaults.data(forKey: Self.appTranscriptionLanguageOverridesKey),
           let decoded = try? JSONDecoder().decode([AppTranscriptionLanguageOverride].self, from: data) {
            appTranscriptionLanguageOverrides = decoded
        } else {
            appTranscriptionLanguageOverrides = []
        }

        if let data = defaults.data(forKey: Self.shortcutsKey),
           let decoded = try? JSONDecoder().decode([ShortcutConfig].self, from: data),
           !decoded.isEmpty {
            shortcuts = decoded
        } else {
            shortcuts = [ShortcutConfig.makeDefault()]
        }

        legacyEnhancementProvider = defaults.string(forKey: Self.enhancementProviderKey)
            .flatMap(EnhancementProvider.init(rawValue:)) ?? .openRouter
        let savedOpenRouterModel = (defaults.string(forKey: Self.openRouterModelKey)?.trimmed)
            .flatMap { $0.isEmpty ? nil : $0 }
        legacyOpenRouterModel = savedOpenRouterModel ?? EnhancementProvider.openRouter.defaultModel
        openRouterApiKey = defaults.string(forKey: Self.openRouterApiKeyKey) ?? ""
        celerisApiKey = defaults.string(forKey: Self.celerisApiKeyKey) ?? ""

        if let data = defaults.data(forKey: Self.promptsKey),
           let decoded = try? JSONDecoder().decode([PromptConfig].self, from: data) {
            prompts = Self.migratedPromptConfigurations(
                decoded,
                encodedData: data,
                legacyProvider: legacyEnhancementProvider,
                legacyOpenRouterModel: legacyOpenRouterModel
            )
            if prompts != decoded,
               let migratedData = try? JSONEncoder().encode(prompts) {
                defaults.set(migratedData, forKey: Self.promptsKey)
            }
        } else {
            prompts = []
            PromptRoutingService.migrateLegacyEnhancementPromptsIfNeeded(
                defaults: defaults,
                shortcuts: &shortcuts,
                prompts: &prompts,
                provider: legacyEnhancementProvider,
                model: legacyModel(for: legacyEnhancementProvider)
            )
        }
    }

    private func legacyModel(for provider: EnhancementProvider) -> String {
        switch provider {
        case .openRouter: legacyOpenRouterModel
        case .celeris: provider.defaultModel
        }
    }

    private static func migratedPromptConfigurations(
        _ prompts: [PromptConfig],
        encodedData: Data,
        legacyProvider: EnhancementProvider,
        legacyOpenRouterModel: String
    ) -> [PromptConfig] {
        guard let objects = try? JSONSerialization.jsonObject(with: encodedData) as? [[String: Any]],
              objects.count == prompts.count else {
            return prompts
        }

        return prompts.enumerated().map { index, prompt in
            var prompt = prompt
            let object = objects[index]
            if object["provider"] == nil {
                prompt.provider = legacyProvider
            }
            if object["model"] == nil {
                prompt.model = prompt.provider == .openRouter
                    ? legacyOpenRouterModel
                    : prompt.provider.defaultModel
            }
            return prompt
        }
    }
}

enum OverlayPosition: String, CaseIterable, Identifiable {
    case top
    case bottom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .top: "Top"
        case .bottom: "Bottom"
        }
    }
}

enum HistoryLimit: Int, CaseIterable, Identifiable {
    case none = 0
    case ten = 10
    case hundred = 100

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .none: "None"
        case .ten: "10"
        case .hundred: "100"
        }
    }
}
