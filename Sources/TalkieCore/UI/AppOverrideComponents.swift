import AppKit
import SwiftUI

struct BundleIconView: View {
    let bundleIdentifier: String?
    let bundleURL: URL?
    let size: CGFloat

    @State private var icon: NSImage?

    var body: some View {
        Group {
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
            } else {
                Image(systemName: "app.fill")
                    .resizable()
                    .scaledToFit()
                    .padding(size * 0.2)
                    .foregroundStyle(.secondary)
                    .background(
                        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                            .fill(Color.secondary.opacity(0.10))
                    )
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
        .task(id: cacheKey) {
            icon = loadIcon()
        }
    }

    private var cacheKey: String {
        if let bundleURL {
            return bundleURL.path
        }
        return bundleIdentifier ?? "unknown"
    }

    private func loadIcon() -> NSImage? {
        if let bundleURL {
            return NSWorkspace.shared.icon(forFile: bundleURL.path)
        }

        guard let bundleIdentifier,
              let bundleURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            return nil
        }
        return NSWorkspace.shared.icon(forFile: bundleURL.path)
    }
}

private struct PickerEmptyState: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

struct RunningAppPickerSheet: View {
    @ObservedObject var model: RunningAppPickerModel
    let onPick: (RunningApplicationOption) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Pick Running Application")
                        .font(.title3.weight(.semibold))
                    Text("Only applications that are running right now can be selected.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Reload") {
                    model.reload()
                }
                .buttonStyle(.bordered)
            }

            TextField("Search running apps", text: $model.searchText)
                .textFieldStyle(.roundedBorder)

            Group {
                if !model.hasLoadedSnapshot {
                    PickerEmptyState(
                        title: "Loading Running Apps",
                        systemImage: "bolt.horizontal.circle",
                        message: "The picker opens immediately and refreshes from the current running-app snapshot."
                    )
                } else if model.apps.isEmpty {
                    PickerEmptyState(
                        title: "No Running Apps Found",
                        systemImage: "app.slash",
                        message: "Launch the app you want to target, then click Reload."
                    )
                } else if model.filteredApps.isEmpty {
                    PickerEmptyState(
                        title: "No Matches",
                        systemImage: "magnifyingglass",
                        message: "Try a different search term or reload the running-app list."
                    )
                } else {
                    List(model.filteredApps) { app in
                        Button {
                            onPick(app)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                BundleIconView(
                                    bundleIdentifier: app.bundleIdentifier,
                                    bundleURL: app.bundleURL,
                                    size: 28
                                )

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.displayName)
                                        .foregroundStyle(.primary)
                                    Text(app.bundleIdentifier)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(minHeight: 320)

            HStack {
                Text("Search is local to the current running-app snapshot.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
            }
        }
        .padding(24)
        .frame(width: 560, height: 520)
        .onAppear {
            model.prepareForPresentation()
        }
    }
}
