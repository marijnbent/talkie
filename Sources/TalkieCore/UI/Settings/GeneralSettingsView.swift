import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var viewModel: GeneralSettingsViewModel
    @State private var languageSearchText = ""
    @StateObject private var pickerModel = RunningAppPickerModel()
    @State private var isPresentingAppLanguageOverridePicker = false
    @State private var isPresentingAutomaticLanguagePicker = false

    var body: some View {
        Form {
            Section("Permissions") {
                LabeledContent {
                    Button(viewModel.microphonePermissionButtonTitle()) {
                        viewModel.requestMicrophonePermission()
                    }
                    .disabled(viewModel.microphonePermission.isGranted)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Recording")
                            Text(viewModel.microphonePermission.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Circle()
                            .fill(viewModel.microphonePermission.color)
                            .frame(width: 8, height: 8)
                    }
                }

                LabeledContent {
                    Button(viewModel.accessibilityPermissionButtonTitle()) {
                        viewModel.requestAccessibilityPermission()
                    }
                    .disabled(viewModel.accessibilityPermission.isGranted)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Pasting")
                            Text(viewModel.accessibilityPermission.rawValue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Circle()
                            .fill(viewModel.accessibilityPermission.color)
                            .frame(width: 8, height: 8)
                    }
                }
            }

            Section {
                Picker("Microphone", selection: viewModel.binding(for: \.audioInputSelection)) {
                    Text(viewModel.resolvedAudioInputSelection.systemDefaultDevice.map {
                        "System Default (\($0.name))"
                    } ?? "System Default")
                        .tag(AudioInputSelection.systemDefault)

                    ForEach(viewModel.availableAudioInputs) { input in
                        Text(input.name).tag(AudioInputSelection.device(input.id))
                    }
                }
            } header: {
                Text("Recording")
            } footer: {
                Text(viewModel.audioInputHelpText)
            }

            Section {
                Picker("Provider", selection: viewModel.binding(for: \.transcriptionProvider)) {
                    ForEach(TranscriptionProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)

                switch viewModel.transcriptionProvider {
                case .deepgram:
                    SecureField("Deepgram API Key", text: viewModel.binding(for: \.apiKey))
                case .elevenLabs:
                    SecureField("ElevenLabs API Key", text: viewModel.binding(for: \.elevenLabsApiKey))
                case .muse:
                    SecureField("Muse API Key", text: viewModel.binding(for: \.museApiKey))
                }

                Picker("Current language", selection: viewModel.languageBinding()) {
                    ForEach(viewModel.availableLanguages) { language in
                        Text(language.displayName).tag(language)
                    }
                }

                if viewModel.supportsAutomaticLanguageCandidates {
                    LabeledContent("Automatic languages") {
                        HStack(spacing: 10) {
                            Text(viewModel.automaticLanguageCandidatesSummary)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Button("Edit…") {
                                isPresentingAutomaticLanguagePicker = true
                            }
                        }
                    }
                }
            } header: {
                Text("Speech to text")
            } footer: {
                Text(viewModel.transcriptionLanguageHelpText)
            }

            Section {
                Toggle("Show selected language in menu bar", isOn: viewModel.binding(for: \.showSelectedLanguageInMenuBar))
                Text("When Automatic is selected, no language text is shown.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("Show language button in recorder widget", isOn: viewModel.binding(for: \.showLanguageInRecorderWidget))

                TextField("Search languages", text: $languageSearchText)
                    .textFieldStyle(.roundedBorder)

                if viewModel.menuBarLanguages(matching: languageSearchText).isEmpty {
                    Text("No languages found")
                        .foregroundStyle(.secondary)
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(viewModel.menuBarLanguages(matching: languageSearchText)) { language in
                                MenuBarLanguageSettingsRow(
                                    language: language,
                                    isCurrent: viewModel.selectedLanguage == language,
                                    isStarred: viewModel.isLanguageStarred(language),
                                    canToggleStarRemoval: viewModel.canToggleStarRemoval(for: language),
                                    onToggleStar: { viewModel.toggleStar(for: language) }
                                )
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.trailing, 12)
                    }
                    .frame(minHeight: 160, maxHeight: 220)
                }
            } header: {
                Text("Menu bar languages")
            } footer: {
                Text("Only starred languages appear in the menu bar language submenu.")
            }

            appLanguageOverridesSection

            Section("Behavior") {
                Toggle("Cancel recording with Escape", isOn: viewModel.binding(for: \.escToCancelRecording))
                Toggle("Play sound effects", isOn: viewModel.binding(for: \.playSoundEffects))
                Toggle("Mute during recording", isOn: viewModel.binding(for: \.muteMediaDuringRecording))
                Toggle("Restore clipboard after confirmed auto-paste", isOn: viewModel.binding(for: \.restoreClipboardAfterPaste))
                Toggle("Show live transcript in recorder widget", isOn: viewModel.binding(for: \.showLiveTranscriptInRecorderWidget))
                Picker("Live transcript style", selection: viewModel.binding(for: \.liveTranscriptStyle)) {
                    ForEach(LiveTranscriptStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .disabled(!viewModel.showLiveTranscriptInRecorderWidget)
                Picker("Widget position", selection: viewModel.binding(for: \.overlayPosition)) {
                    ForEach(OverlayPosition.allCases) { position in
                        Text(position.displayName).tag(position)
                    }
                }
            }

            Section("History") {
                Picker("Keep history", selection: viewModel.binding(for: \.historyLimit)) {
                    ForEach(HistoryLimit.allCases) { limit in
                        Text(limit.displayName).tag(limit)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $isPresentingAppLanguageOverridePicker) {
            RunningAppPickerSheet(model: pickerModel) { app in
                viewModel.upsertAppTranscriptionLanguageOverride(
                    appBundleIdentifier: app.bundleIdentifier,
                    appDisplayName: app.displayName
                )
            }
        }
        .sheet(isPresented: $isPresentingAutomaticLanguagePicker) {
            AutomaticLanguagePickerSheet(viewModel: viewModel)
        }
        .onAppear {
            viewModel.refreshPermissions()
        }
    }

    @ViewBuilder
    private var appLanguageOverridesSection: some View {
        Section {
            if viewModel.appTranscriptionLanguageOverrides.isEmpty {
                Text("No app-specific languages yet.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.appTranscriptionLanguageOverrides) { override in
                    if let overrideBinding = viewModel.bindingForAppTranscriptionLanguageOverrideID(override.id) {
                        AppLanguageOverrideRow(
                            overrideBinding: overrideBinding,
                            availableLanguages: viewModel.appOverrideLanguages(for: override.language),
                            onRemove: {
                                viewModel.removeAppTranscriptionLanguageOverride(id: override.id)
                            }
                        )
                    }
                }
            }

            Button("Add App Override...") {
                isPresentingAppLanguageOverridePicker = true
            }
        } header: {
            Text("App language overrides")
        } footer: {
            Text("Apps without an override use Talkie default: \(viewModel.selectedLanguage.displayName).")
        }
    }
}

private struct AutomaticLanguagePickerSheet: View {
    @ObservedObject var viewModel: GeneralSettingsViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""

    private var filteredLanguages: [DeepgramLanguage] {
        viewModel.automaticLanguageCandidateOptions.filter { $0.matchesSearch(searchText) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Automatic languages")
                    .font(.title3.weight(.semibold))
                Text("Select at least two languages. Automatic detection will ignore other languages.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            TextField("Search languages", text: $searchText)
                .textFieldStyle(.roundedBorder)

            if filteredLanguages.isEmpty {
                Text("No languages found")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredLanguages) { language in
                    let isSelected = viewModel.isAutomaticLanguageCandidate(language)
                    Button {
                        viewModel.toggleAutomaticLanguageCandidate(language)
                    } label: {
                        HStack(spacing: 10) {
                            Text(language.displayName)
                                .foregroundStyle(.primary)
                            Spacer()
                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(Color.accentColor)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(isSelected && !viewModel.canRemoveAutomaticLanguageCandidate(language))
                }
                .listStyle(.inset)
            }

            HStack {
                Text("\(viewModel.automaticLanguageCandidates.count) selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500, height: 580)
    }
}

private struct MenuBarLanguageSettingsRow: View {
    let language: DeepgramLanguage
    let isCurrent: Bool
    let isStarred: Bool
    let canToggleStarRemoval: Bool
    let onToggleStar: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(language.displayName)

                if isCurrent {
                    Text("Current selection")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: onToggleStar) {
                Image(systemName: isStarred ? "star.fill" : "star")
                    .foregroundStyle(isStarred ? Color.yellow : Color.secondary)
            }
            .buttonStyle(.plain)
            .disabled(isStarred && !canToggleStarRemoval)
            .accessibilityLabel(isStarred ? "Remove star" : "Add star")
            .help(isStarred ? "Remove from menu bar languages" : "Add to menu bar languages")
        }
    }
}

private struct AppLanguageOverrideRow: View {
    @Binding var overrideBinding: AppTranscriptionLanguageOverride
    let availableLanguages: [DeepgramLanguage]
    let onRemove: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            BundleIconView(
                bundleIdentifier: overrideBinding.appBundleIdentifier,
                bundleURL: nil,
                size: 28
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(overrideBinding.appDisplayName)
                    .font(.headline)
                Text(overrideBinding.appBundleIdentifier)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Picker("Language", selection: $overrideBinding.language) {
                ForEach(availableLanguages) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 220)
            .labelsHidden()

            Button(role: .destructive, action: onRemove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove override")
        }
        .padding(.vertical, 2)
    }
}
