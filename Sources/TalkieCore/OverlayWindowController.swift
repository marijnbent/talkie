import AppKit
import SwiftUI

@MainActor
final class OverlayWindowController {
    private let sessionState: SessionState
    private let settingsStore: SettingsStore
    private var panel: NSPanel?
    private var isShowing = false
    private var animationID = UUID()
    var onCycleLanguage: (() -> Void)?

    init(sessionState: SessionState, settingsStore: SettingsStore) {
        self.sessionState = sessionState
        self.settingsStore = settingsStore
    }

    func show() {
        if panel == nil {
            panel = makePanel()
        }
        guard let panel else { return }
        ensureOverlayContent(on: panel)
        guard let screen = NSScreen.main else {
            sessionState.overlayPulseID = UUID()
            isShowing = true
            animationID = UUID()
            panel.orderFrontRegardless()
            return
        }

        let target = targetFrame(screen: screen)

        if isShowing {
            panel.alphaValue = 1
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.12
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(target, display: true)
            }
            return
        }

        sessionState.overlayPulseID = UUID()
        isShowing = true
        animationID = UUID()

        let offscreen = offscreenFrame(screen: screen, width: target.width, height: target.height)

        panel.alphaValue = 0
        panel.setFrame(offscreen, display: false)
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
            panel.animator().setFrame(target, display: true)
        }
    }

    func hide() {
        guard let panel else { return }
        guard isShowing else { return }
        isShowing = false
        let hideID = animationID

        guard let screen = NSScreen.main else {
            releasePanelIfHidden(for: hideID)
            return
        }

        let target = targetFrame(screen: screen)
        let offscreen = offscreenFrame(screen: screen, width: target.width, height: target.height)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            panel.animator().alphaValue = 0
            panel.animator().setFrame(offscreen, display: true)
        } completionHandler: {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.releasePanelIfHidden(for: hideID)
            }
        }

        // AppKit's animation completion callback is not always reliable for
        // non-activating panels, so also schedule a fallback cleanup.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            Task { @MainActor in
                self?.releasePanelIfHidden(for: hideID)
            }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 90, height: 32),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]

        if let screen = NSScreen.main {
            let target = targetFrame(screen: screen)
            panel.setFrame(target, display: false)
        }

        return panel
    }

    private func ensureOverlayContent(on panel: NSPanel) {
        guard panel.contentViewController == nil else { return }

        let overlayView = OverlayView(
            sessionState: sessionState,
            settingsStore: settingsStore,
            onCycleLanguage: { [weak self] in
                self?.onCycleLanguage?()
            }
        )
        let hosting = NSHostingController(rootView: overlayView)
        panel.contentViewController = hosting

        if let contentView = panel.contentView {
            hosting.view.frame = contentView.bounds
            hosting.view.autoresizingMask = [.width, .height]
        }
    }

    private func releasePanelIfHidden(for hideID: UUID) {
        guard animationID == hideID, !isShowing else { return }
        guard let panel else { return }

        panel.orderOut(nil)
        // Release the hosted SwiftUI tree so repeatForever animations cannot
        // keep driving layout after the overlay is hidden.
        panel.contentViewController = nil
        self.panel = nil
    }

    private func targetFrame(screen: NSScreen) -> CGRect {
        let fullFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let width = min(overlayWidth, fullFrame.width - 80)
        let height: CGFloat = 32
        let x = fullFrame.midX - width / 2
        let y: CGFloat
        switch settingsStore.overlayPosition {
        case .top:
            y = visibleFrame.maxY - height - 28
        case .bottom:
            y = visibleFrame.minY + 28
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }

    private var overlayWidth: CGFloat {
        let baseWidth: CGFloat = sessionState.overlayAppIcon == nil ? 90 : 116
        return settingsStore.showLanguageInRecorderWidget ? baseWidth + 56 : baseWidth
    }

    private func offscreenFrame(screen: NSScreen, width: CGFloat, height: CGFloat) -> CGRect {
        let fullFrame = screen.frame
        let visibleFrame = screen.visibleFrame
        let x = fullFrame.midX - width / 2
        let y: CGFloat
        switch settingsStore.overlayPosition {
        case .top:
            y = visibleFrame.maxY + 8
        case .bottom:
            y = visibleFrame.minY - height - 8
        }
        return CGRect(x: x, y: y, width: width, height: height)
    }
}
