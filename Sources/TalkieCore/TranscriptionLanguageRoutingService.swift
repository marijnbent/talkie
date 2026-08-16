import Foundation

@MainActor
enum TranscriptionLanguageRoutingService {
    static func resolvedLanguage(
        settings: SettingsStore,
        activeAppBundleIdentifier: String? = nil
    ) -> DeepgramLanguage {
        if let normalizedBundleIdentifier = AppOverrideSupport.normalizeBundleIdentifier(activeAppBundleIdentifier),
           let language = settings.appTranscriptionLanguageOverrides.first(where: {
               $0.normalizedAppBundleIdentifier == normalizedBundleIdentifier
           })?.language {
            return language
        }

        return settings.transcriptionProvider.normalizedLanguage(settings.deepgramLanguage)
    }

    static func upsertAppOverride(
        appBundleIdentifier: String,
        appDisplayName: String,
        language: DeepgramLanguage? = nil,
        settings: SettingsStore
    ) {
        guard let normalizedBundleIdentifier = AppOverrideSupport.normalizeBundleIdentifier(appBundleIdentifier) else {
            return
        }

        let displayName = AppOverrideSupport.cleanedDisplayName(
            appDisplayName,
            fallback: normalizedBundleIdentifier
        )
        let resolvedLanguage = settings.transcriptionProvider.normalizedLanguage(
            language ?? settings.deepgramLanguage
        )

        if let overrideIndex = settings.appTranscriptionLanguageOverrides.firstIndex(where: {
            $0.normalizedAppBundleIdentifier == normalizedBundleIdentifier
        }) {
            settings.appTranscriptionLanguageOverrides[overrideIndex].appBundleIdentifier = normalizedBundleIdentifier
            settings.appTranscriptionLanguageOverrides[overrideIndex].appDisplayName = displayName
            settings.appTranscriptionLanguageOverrides[overrideIndex].language = resolvedLanguage
        } else {
            settings.appTranscriptionLanguageOverrides.append(
                AppTranscriptionLanguageOverride(
                    appBundleIdentifier: normalizedBundleIdentifier,
                    appDisplayName: displayName,
                    language: resolvedLanguage
                )
            )
        }

        AppOverrideSupport.sortByDisplayNameAndBundleIdentifier(
            &settings.appTranscriptionLanguageOverrides,
            displayName: \.appDisplayName,
            bundleIdentifier: \.appBundleIdentifier
        )
    }
}
