import SwiftUI

private struct PromptEditorRequest: Identifiable {
    let id: UUID
}

private struct OverridePickerRequest: Identifiable {
    let shortcutID: UUID

    var id: UUID { shortcutID }
}

private extension PromptConfig {
    var previewText: String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "No prompt content yet." }
        return trimmed.replacingOccurrences(of: "\n", with: " ")
    }
}

private struct PromptEditorSheet: View {
    @Binding var prompt: PromptConfig
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(prompt.displayName)
                .font(.title3.weight(.semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                TextField("Prompt name", text: $prompt.name)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Provider")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    Picker("Provider", selection: $prompt.provider) {
                        ForEach(EnhancementProvider.allCases) { provider in
                            Text(provider.displayName).tag(provider)
                        }
                    }
                    .labelsHidden()
                    .onChange(of: prompt.provider) { provider in
                        prompt.model = provider.defaultModel
                    }
                }
                .frame(width: 160, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Model")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                    TextField("Model ID", text: $prompt.model)
                        .textFieldStyle(.roundedBorder)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Instructions")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                TextEditor(text: $prompt.content)
                    .font(.body)
                    .frame(minHeight: 220)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: .textBackgroundColor))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.18))
                    )
            }

            Text("The transcript is appended automatically inside <transcription> tags before the enhancement request is sent.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 560, height: 550)
    }
}

struct EnhancementsSettingsView: View {
    @ObservedObject var viewModel: EnhancementsSettingsViewModel

    @StateObject private var pickerModel = RunningAppPickerModel()
    @State private var promptEditorRequest: PromptEditorRequest?
    @State private var overridePickerRequest: OverridePickerRequest?

    var body: some View {
        Form {
            providerSection
            promptLibrarySection
            routingSections
        }
        .formStyle(.grouped)
        .sheet(item: $promptEditorRequest) { request in
            Group {
                if let promptBinding = viewModel.bindingForPromptID(request.id) {
                    PromptEditorSheet(prompt: promptBinding)
                } else {
                    Text("Prompt not found.")
                        .padding(24)
                }
            }
        }
        .sheet(item: $overridePickerRequest) { request in
            RunningAppPickerSheet(model: pickerModel) { app in
                viewModel.upsertAppPromptOverride(
                    shortcutID: request.shortcutID,
                    appBundleIdentifier: app.bundleIdentifier,
                    appDisplayName: app.displayName
                )
            }
        }
    }

    @ViewBuilder
    private var providerSection: some View {
        Section {
            LabeledContent("OpenRouter") {
                SecureField("API Key", text: viewModel.binding(for: \.openRouterApiKey))
                    .frame(width: 320)
            }
            LabeledContent("Celeris") {
                SecureField("API Key", text: viewModel.binding(for: \.celerisApiKey))
                    .frame(width: 320)
            }
        } header: {
            Text("Providers")
        } footer: {
            Text("Add each API key once. Choose the provider and model in each prompt.")
        }
    }

    @ViewBuilder
    private var promptLibrarySection: some View {
        Section {
            if viewModel.prompts.isEmpty {
                Text("No prompts yet. Add a prompt first, then assign it as a default or app-specific override.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.prompts) { prompt in
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(prompt.displayName)
                                .font(.headline)
                            Text(prompt.previewText)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text("\(prompt.provider.displayName) · \(prompt.model.trimmed.isEmpty ? "No model" : prompt.model.trimmed)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(viewModel.promptUsageSummary(for: prompt.id))
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer(minLength: 12)

                        HStack(spacing: 8) {
                            Button("Edit") {
                                promptEditorRequest = PromptEditorRequest(id: prompt.id)
                            }
                            Button("Delete", role: .destructive) {
                                viewModel.deletePrompt(id: prompt.id)
                            }
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.vertical, 4)
                }
            }
        } header: {
            HStack {
                Text("Prompt Library")
                Spacer()
                Button("Add Prompt") {
                    let prompt = viewModel.addPrompt()
                    promptEditorRequest = PromptEditorRequest(id: prompt.id)
                }
                .font(.caption.weight(.medium))
            }
        } footer: {
            Text("Create reusable prompts, then route them per shortcut and per running application.")
        }
    }

    @ViewBuilder
    private var routingSections: some View {
        ForEach(viewModel.shortcuts) { shortcut in
            if let shortcutBinding = viewModel.bindingForShortcutID(shortcut.id) {
                Section {
                    Picker("Default Prompt", selection: shortcutBinding.promptID) {
                        Text("None").tag(UUID?.none)
                        ForEach(viewModel.prompts) { prompt in
                            Text(prompt.displayName).tag(Optional(prompt.id))
                        }
                    }

                    ForEach(Array(shortcutBinding.wrappedValue.appPromptOverrides.indices), id: \.self) { index in
                        HStack(alignment: .center, spacing: 12) {
                            BundleIconView(
                                bundleIdentifier: shortcutBinding.wrappedValue.appPromptOverrides[index].appBundleIdentifier,
                                bundleURL: nil,
                                size: 28
                            )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(shortcutBinding.wrappedValue.appPromptOverrides[index].appDisplayName)
                                    .font(.headline)
                                Text(shortcutBinding.wrappedValue.appPromptOverrides[index].appBundleIdentifier)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 8)

                            Picker(
                                "Prompt",
                                selection: Binding(
                                    get: { shortcutBinding.wrappedValue.appPromptOverrides[index].promptID },
                                    set: { newValue in
                                        var updated = shortcutBinding.wrappedValue
                                        updated.appPromptOverrides[index].promptID = newValue
                                        shortcutBinding.wrappedValue = updated
                                    }
                                )
                            ) {
                                ForEach(viewModel.prompts) { prompt in
                                    Text(prompt.displayName).tag(prompt.id)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 200)
                            .labelsHidden()

                            Button(role: .destructive) {
                                var updated = shortcutBinding.wrappedValue
                                updated.appPromptOverrides.remove(at: index)
                                shortcutBinding.wrappedValue = updated
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Remove override")
                        }
                        .padding(.vertical, 2)
                    }

                    Button("Add App Override...") {
                        overridePickerRequest = OverridePickerRequest(shortcutID: shortcut.id)
                    }
                    .disabled(viewModel.prompts.isEmpty)
                } header: {
                    Text("\(shortcut.key.displayName) · \(shortcut.mode.displayName)")
                } footer: {
                    if shortcut.appPromptOverrides.isEmpty {
                        Text(viewModel.prompts.isEmpty
                             ? "Create a prompt before adding per-app overrides."
                             : "Only running apps appear in the picker. Overrides stay saved even when the app is not running.")
                    }
                }
            }
        }
    }
}
