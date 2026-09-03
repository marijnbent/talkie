import XCTest
@testable import TalkieCore

@MainActor
final class EnhancementTests: XCTestCase {
    private let enhancementProviderKey = "Talkie.EnhancementProvider"
    private let openRouterApiKeyKey = "Talkie.OpenRouterApiKey"
    private let openRouterModelKey = "Talkie.OpenRouterModel"
    private let celerisApiKeyKey = "Talkie.CelerisApiKey"
    private let enhancementPromptsKey = "Talkie.EnhancementPrompts"
    private let promptsKey = "Talkie.Prompts"
    private let shortcutsKey = "Talkie.Shortcuts"

    override func setUp() {
        super.setUp()
        UserDefaults.standard.removeObject(forKey: enhancementProviderKey)
        UserDefaults.standard.removeObject(forKey: openRouterApiKeyKey)
        UserDefaults.standard.removeObject(forKey: openRouterModelKey)
        UserDefaults.standard.removeObject(forKey: celerisApiKeyKey)
        UserDefaults.standard.removeObject(forKey: enhancementPromptsKey)
        UserDefaults.standard.removeObject(forKey: promptsKey)
        UserDefaults.standard.removeObject(forKey: shortcutsKey)
    }

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: enhancementProviderKey)
        UserDefaults.standard.removeObject(forKey: openRouterApiKeyKey)
        UserDefaults.standard.removeObject(forKey: openRouterModelKey)
        UserDefaults.standard.removeObject(forKey: celerisApiKeyKey)
        UserDefaults.standard.removeObject(forKey: enhancementPromptsKey)
        UserDefaults.standard.removeObject(forKey: promptsKey)
        UserDefaults.standard.removeObject(forKey: shortcutsKey)
        super.tearDown()
    }

    // MARK: - Provider Credentials

    func testNewPromptDefaultsToOpenRouter() {
        let prompt = PromptConfig.makeDefault()
        XCTAssertEqual(prompt.provider, .openRouter)
        XCTAssertEqual(prompt.model, EnhancementProvider.openRouter.defaultModel)
    }

    func testPromptProviderAndModelPersist() {
        let state = AppState()
        state.prompts = [
            PromptConfig(
                id: UUID(),
                name: "Fast cleanup",
                content: "Clean this",
                provider: .celeris,
                model: "celeris-next"
            )
        ]

        let restored = AppState()
        XCTAssertEqual(restored.prompts.first?.provider, .celeris)
        XCTAssertEqual(restored.prompts.first?.model, "celeris-next")
    }

    func testOldPromptMigratesCurrentProviderAndModel() throws {
        let promptID = UUID()
        let data = try JSONSerialization.data(withJSONObject: [[
            "id": promptID.uuidString,
            "name": "Existing prompt",
            "content": "Clean this"
        ]])
        UserDefaults.standard.set(data, forKey: promptsKey)
        UserDefaults.standard.set(EnhancementProvider.openRouter.rawValue, forKey: enhancementProviderKey)
        UserDefaults.standard.set("anthropic/claude-sonnet-4.5", forKey: openRouterModelKey)

        let restored = AppState()

        XCTAssertEqual(restored.prompts.first?.id, promptID)
        XCTAssertEqual(restored.prompts.first?.provider, .openRouter)
        XCTAssertEqual(restored.prompts.first?.model, "anthropic/claude-sonnet-4.5")
    }

    func testOpenRouterCredentialsRequireApiKeyAndModel() {
        let settings = SettingsStore()
        settings.openRouterApiKey = "sk-test"
        XCTAssertEqual(
            settings.enhancementProviderSettings(provider: .openRouter, model: "").missingCredential,
            "model"
        )

        XCTAssertNil(
            settings.enhancementProviderSettings(
                provider: .openRouter,
                model: "openai/gpt-4o-mini"
            ).missingCredential
        )
    }

    func testCelerisApiKeyDefaultsToEmpty() {
        let state = AppState()
        XCTAssertEqual(state.celerisApiKey, "")
    }

    func testCelerisCredentialsRequireApiKey() {
        let settings = SettingsStore()
        let prompt = PromptConfig.makeDefault(provider: .celeris)
        XCTAssertEqual(
            settings.enhancementProviderSettings(
                provider: prompt.provider,
                model: prompt.model
            ).missingCredential,
            "API key"
        )

        settings.celerisApiKey = "ck-test"
        XCTAssertNil(
            settings.enhancementProviderSettings(
                provider: prompt.provider,
                model: prompt.model
            ).missingCredential
        )
    }

    func testCelerisApiKeyPersists() {
        let state = AppState()
        state.celerisApiKey = "ck-persisted"

        let restored = AppState()
        XCTAssertEqual(restored.celerisApiKey, "ck-persisted")
    }

    // MARK: - Named Prompts

    func testPromptsDefaultToEmpty() {
        let state = AppState()
        XCTAssertTrue(state.prompts.isEmpty)
    }

    func testPromptsPersist() {
        let state = AppState()
        let prompt = PromptConfig(id: UUID(), name: "Fix grammar", content: "fix grammar")
        state.prompts.append(prompt)

        let restored = AppState()
        XCTAssertEqual(restored.prompts.count, 1)
        XCTAssertEqual(restored.prompts[0].name, "Fix grammar")
        XCTAssertEqual(restored.prompts[0].content, "fix grammar")
    }

    func testDeletePromptRemovesPrompt() {
        let state = AppState()
        let prompt = PromptConfig(id: UUID(), name: "Test", content: "test")
        state.prompts.append(prompt)
        state.deletePrompt(id: prompt.id)

        XCTAssertTrue(state.prompts.isEmpty)
    }

    func testDeletePromptClearsShortcutReferences() {
        let state = AppState()
        let prompt = PromptConfig(id: UUID(), name: "Test", content: "test")
        state.prompts.append(prompt)
        state.shortcuts[0].promptID = prompt.id

        state.deletePrompt(id: prompt.id)
        XCTAssertNil(state.shortcuts[0].promptID)
    }

    func testDeletePromptClearsShortcutOverrideReferences() {
        let state = AppState()
        let defaultPrompt = PromptConfig(id: UUID(), name: "Default", content: "default")
        let overridePrompt = PromptConfig(id: UUID(), name: "WhatsApp", content: "whatsapp")
        state.prompts = [defaultPrompt, overridePrompt]
        state.shortcuts[0].promptID = defaultPrompt.id
        state.shortcuts[0].appPromptOverrides = [
            AppPromptOverride(
                appBundleIdentifier: "net.whatsapp.WhatsApp",
                appDisplayName: "WhatsApp",
                promptID: overridePrompt.id
            )
        ]

        state.deletePrompt(id: overridePrompt.id)

        XCTAssertTrue(state.shortcuts[0].appPromptOverrides.isEmpty)
        XCTAssertEqual(state.shortcuts[0].promptID, defaultPrompt.id)
    }

    func testPromptContentForShortcutID() {
        let state = AppState()
        let prompt = PromptConfig(id: UUID(), name: "Test", content: "do the thing")
        state.prompts.append(prompt)
        state.shortcuts[0].promptID = prompt.id

        XCTAssertEqual(state.promptContent(forShortcutID: state.shortcuts[0].id), "do the thing")
    }

    func testPromptContentForShortcutIDReturnsNilWithNoPromptID() {
        let state = AppState()
        XCTAssertNil(state.promptContent(forShortcutID: state.shortcuts[0].id))
    }

    func testPromptContentForShortcutIDReturnsNilForDeletedPrompt() {
        let state = AppState()
        state.shortcuts[0].promptID = UUID() // points to nonexistent prompt
        XCTAssertNil(state.promptContent(forShortcutID: state.shortcuts[0].id))
    }

    func testPromptContentForShortcutIDUsesAppOverrideBeforeDefault() {
        let state = AppState()
        let defaultPrompt = PromptConfig(id: UUID(), name: "Default", content: "default")
        let overridePrompt = PromptConfig(id: UUID(), name: "WhatsApp", content: "override")
        state.prompts = [defaultPrompt, overridePrompt]
        state.shortcuts[0].promptID = defaultPrompt.id
        state.shortcuts[0].appPromptOverrides = [
            AppPromptOverride(
                appBundleIdentifier: "net.whatsapp.WhatsApp",
                appDisplayName: "WhatsApp",
                promptID: overridePrompt.id
            )
        ]

        let content = state.promptContent(
            forShortcutID: state.shortcuts[0].id,
            activeAppBundleIdentifier: "NET.WHATSAPP.WHATSAPP"
        )

        XCTAssertEqual(content, "override")
    }

    func testResolvedEnhancementPromptUsesDefaultPromptMetadata() {
        let state = AppState()
        let prompt = PromptConfig(
            id: UUID(),
            name: "Clean up",
            content: "clean this",
            provider: .celeris,
            model: "celeris-next"
        )
        state.prompts = [prompt]
        state.shortcuts[0].promptID = prompt.id

        let resolved = state.resolvedEnhancementPrompt(forShortcutID: state.shortcuts[0].id)

        XCTAssertEqual(resolved?.name, "Clean up")
        XCTAssertEqual(resolved?.content, "clean this")
        XCTAssertEqual(resolved?.isForActiveApp, false)
        XCTAssertEqual(resolved?.provider, .celeris)
        XCTAssertEqual(resolved?.model, "celeris-next")
    }

    func testResolvedEnhancementPromptUsesAppOverrideMetadata() {
        let state = AppState()
        let defaultPrompt = PromptConfig(id: UUID(), name: "Default", content: "default")
        let overridePrompt = PromptConfig(id: UUID(), name: "WhatsApp", content: "override")
        state.prompts = [defaultPrompt, overridePrompt]
        state.shortcuts[0].promptID = defaultPrompt.id
        state.shortcuts[0].appPromptOverrides = [
            AppPromptOverride(
                appBundleIdentifier: "net.whatsapp.WhatsApp",
                appDisplayName: "WhatsApp",
                promptID: overridePrompt.id
            )
        ]

        let resolved = state.resolvedEnhancementPrompt(
            forShortcutID: state.shortcuts[0].id,
            activeAppBundleIdentifier: "NET.WHATSAPP.WHATSAPP"
        )

        XCTAssertEqual(resolved?.name, "WhatsApp")
        XCTAssertEqual(resolved?.content, "override")
        XCTAssertEqual(resolved?.isForActiveApp, true)
    }

    func testPromptContentForShortcutIDFallsBackToDefaultWhenNoAppOverrideMatches() {
        let state = AppState()
        let defaultPrompt = PromptConfig(id: UUID(), name: "Default", content: "default")
        let overridePrompt = PromptConfig(id: UUID(), name: "WhatsApp", content: "override")
        state.prompts = [defaultPrompt, overridePrompt]
        state.shortcuts[0].promptID = defaultPrompt.id
        state.shortcuts[0].appPromptOverrides = [
            AppPromptOverride(
                appBundleIdentifier: "net.whatsapp.WhatsApp",
                appDisplayName: "WhatsApp",
                promptID: overridePrompt.id
            )
        ]

        let content = state.promptContent(
            forShortcutID: state.shortcuts[0].id,
            activeAppBundleIdentifier: "com.apple.TextEdit"
        )

        XCTAssertEqual(content, "default")
    }

    // MARK: - Migration from old enhancementPrompts

    func testMigrationFromOldEnhancementPrompts() {
        // Seed old-format data
        let state1 = AppState()
        let shortcutID = state1.shortcuts[0].id

        let oldPrompts: [String: String] = [shortcutID.uuidString: "old prompt content"]
        let data = try! JSONEncoder().encode(oldPrompts)
        UserDefaults.standard.set(data, forKey: enhancementPromptsKey)
        // Remove new-format key so migration triggers
        UserDefaults.standard.removeObject(forKey: promptsKey)

        // Re-seed shortcuts so the shortcut ID matches
        let shortcutData = try! JSONEncoder().encode(state1.shortcuts)
        UserDefaults.standard.set(shortcutData, forKey: shortcutsKey)

        let state2 = AppState()
        XCTAssertEqual(state2.prompts.count, 1)
        XCTAssertEqual(state2.prompts[0].content, "old prompt content")
        XCTAssertEqual(state2.shortcuts[0].promptID, state2.prompts[0].id)
        // Old key should be cleaned up
        XCTAssertNil(UserDefaults.standard.data(forKey: enhancementPromptsKey))
    }

    // MARK: - Default Prompt

    func testDefaultPromptIsNotEmpty() {
        let prompt = PromptConfig.makeDefault()
        XCTAssertFalse(prompt.content.isEmpty)
    }

    // MARK: - CelerisError

    func testCelerisErrorInvalidResponseDescription() {
        let error = CelerisError.invalidResponse
        XCTAssertEqual(error.errorDescription, "Invalid response from Celeris.")
    }

    func testCelerisErrorHttpErrorDescription() {
        let error = CelerisError.httpError(statusCode: 401, body: "Unauthorized")
        XCTAssertEqual(error.errorDescription, "Celeris HTTP 401: Unauthorized")
    }

    func testCelerisErrorNoContentDescription() {
        let error = CelerisError.noContent
        XCTAssertEqual(error.errorDescription, "Celeris returned no content.")
    }

    func testCelerisRequestUsesSelectedModel() throws {
        let request = try CelerisClient.makeRequest(
            transcript: "Raw text",
            prompt: "Clean it",
            apiKey: "ck-test",
            model: "celeris-next"
        )
        let body = try XCTUnwrap(request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])

        XCTAssertEqual(request.url?.absoluteString, "https://inference.celeris.ai/celeris-next/v1/chat/completions")
        XCTAssertEqual(json["model"] as? String, "celeris-next")
    }

    func testOpenRouterErrorInvalidResponseDescription() {
        let error = OpenRouterError.invalidResponse
        XCTAssertEqual(error.errorDescription, "Invalid response from OpenRouter.")
    }

    func testOpenRouterErrorHttpErrorDescription() {
        let error = OpenRouterError.httpError(statusCode: 401, body: "Unauthorized")
        XCTAssertEqual(error.errorDescription, "OpenRouter HTTP 401: Unauthorized")
    }

    // MARK: - Missing Credentials with Enhancement Enabled

    func testEnhancementEnabledButMissingApiKeyLogsWarning() {
        let state = AppState()
        let prompt = PromptConfig(id: UUID(), name: "Fix", content: "fix it")
        state.prompts.append(prompt)
        state.shortcuts[0].promptID = prompt.id
        XCTAssertNotNil(state.promptContent(forShortcutID: state.shortcuts[0].id))

        let settings = SettingsStore()
        XCTAssertEqual(
            settings.enhancementProviderSettings(
                provider: prompt.provider,
                model: prompt.model
            ).missingCredential,
            "API key"
        )
    }
}
