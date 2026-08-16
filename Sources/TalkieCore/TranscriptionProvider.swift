import Foundation

enum TranscriptionProvider: String, CaseIterable, Identifiable, Sendable {
    case deepgram
    case elevenLabs

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .deepgram:
            return "Deepgram"
        case .elevenLabs:
            return "ElevenLabs"
        }
    }

    var languageOptions: [DeepgramLanguage] {
        switch self {
        case .deepgram:
            DeepgramLanguage.deepgramNova3Languages
        case .elevenLabs:
            DeepgramLanguage.elevenLabsLanguages
        }
    }

    var supportsAutomaticLanguageCandidates: Bool {
        switch self {
        case .deepgram:
            false
        case .elevenLabs:
            true
        }
    }

    var automaticLanguageCandidateOptions: [DeepgramLanguage] {
        guard supportsAutomaticLanguageCandidates else { return [] }
        return languageOptions.filter { $0 != .automatic }
    }

    var defaultAutomaticLanguageCandidates: [DeepgramLanguage] {
        switch self {
        case .deepgram:
            []
        case .elevenLabs:
            [.dutch, .english]
        }
    }

    func normalizedAutomaticLanguageCandidates(_ candidates: [DeepgramLanguage]) -> [DeepgramLanguage] {
        guard supportsAutomaticLanguageCandidates else { return [] }

        let selected = Set(candidates)
        let normalized = automaticLanguageCandidateOptions.filter(selected.contains)
        return normalized.isEmpty ? defaultAutomaticLanguageCandidates : normalized
    }

    var automaticLanguageHelpText: String {
        switch self {
        case .deepgram:
            return "Automatic uses Deepgram's multilingual streaming model; custom language limits are not available."
        case .elevenLabs:
            return "Automatic uses the selected languages only."
        }
    }

    func normalizedLanguage(_ language: DeepgramLanguage) -> DeepgramLanguage {
        switch self {
        case .deepgram:
            if languageOptions.contains(language) {
                return language
            }

            switch language {
            case .cantonese:
                return .chineseCantonese
            case .mandarinChinese:
                return .chineseMandarinSimplified
            case .filipino:
                return .tagalog
            default:
                return .automatic
            }
        case .elevenLabs:
            if languageOptions.contains(language) {
                return language
            }

            switch language {
            case .chineseCantonese:
                return .cantonese
            case .chineseMandarinSimplified,
                 .chineseMandarinSimplifiedChina,
                 .chineseMandarinSimplifiedHans,
                 .chineseMandarinTraditional,
                 .chineseMandarinTraditionalHant:
                return .mandarinChinese
            case .tagalog:
                return .filipino
            default:
                let baseCode = language.rawValue.split(separator: "-", maxSplits: 1).first.map(String.init)
                return languageOptions.first(where: { $0.rawValue == baseCode }) ?? .automatic
            }
        }
    }
}

struct TranscriptionProviderSettings: Equatable, Sendable {
    let provider: TranscriptionProvider
    let apiKey: String
    let automaticLanguageCandidates: [DeepgramLanguage]

    init(
        provider: TranscriptionProvider,
        apiKey: String,
        automaticLanguageCandidates: [DeepgramLanguage]? = nil
    ) {
        self.provider = provider
        self.apiKey = apiKey
        self.automaticLanguageCandidates = provider.normalizedAutomaticLanguageCandidates(
            automaticLanguageCandidates ?? provider.defaultAutomaticLanguageCandidates
        )
    }
}
