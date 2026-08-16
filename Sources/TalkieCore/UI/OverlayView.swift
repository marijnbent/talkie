import AppKit
import SwiftUI

struct RecorderWidgetPresentation: Equatable {
    let streamedText: String?

    var showsStreamedText: Bool {
        streamedText != nil
    }

    init(
        transcript: String,
        recordingPhase: RecordingPhase,
        isLiveTranscriptEnabled: Bool
    ) {
        let streamedText = transcript.trimmed
        guard isLiveTranscriptEnabled,
              recordingPhase == .recording,
              !streamedText.isEmpty else {
            self.streamedText = nil
            return
        }
        self.streamedText = streamedText
    }
}

enum RecorderWidgetMeter {
    static let quietThreshold: CGFloat = 0.12

    static func visibleLevel(for level: CGFloat) -> CGFloat {
        let normalizedLevel = min(max(level, 0), 1)
        guard normalizedLevel > quietThreshold else { return 0 }
        return (normalizedLevel - quietThreshold) / (1 - quietThreshold)
    }
}

struct RecorderWidgetTranscriptWord: Identifiable, Equatable {
    let id: Int
    let text: String
}

enum RecorderWidgetTranscriptWords {
    static let visibleLimit = 24

    static func project(_ transcript: String) -> [RecorderWidgetTranscriptWord] {
        let words = transcript
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        let firstVisibleIndex = max(0, words.count - visibleLimit)
        return words.enumerated().dropFirst(firstVisibleIndex).map {
            RecorderWidgetTranscriptWord(id: $0.offset, text: $0.element)
        }
    }
}

enum RecorderWidgetLayout {
    static let maximumWidth: CGFloat = 260
    static let horizontalTextPadding: CGFloat = 28
    static let leadingFadeWidth: CGFloat = 12
    static let transcriptFontSize: CGFloat = 11
    static let wordSpacing: CGFloat = 3

    static func measuredTextWidth(for transcript: String) -> CGFloat? {
        let words = RecorderWidgetTranscriptWords.project(transcript)
        guard !words.isEmpty else { return nil }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: transcriptFontSize, weight: .regular),
        ]
        let wordsWidth = words.reduce(CGFloat.zero) { width, word in
            width + (word.text as NSString).size(withAttributes: attributes).width
        }
        return wordsWidth + CGFloat(words.count - 1) * wordSpacing
    }

    static func nextWidth(
        compactWidth: CGFloat,
        measuredTextWidth: CGFloat?,
        previousWidth: CGFloat?
    ) -> CGFloat {
        guard let measuredTextWidth else { return compactWidth }
        let desiredWidth = min(
            maximumWidth,
            max(compactWidth, ceil(measuredTextWidth) + horizontalTextPadding)
        )
        return max(previousWidth ?? compactWidth, desiredWidth)
    }

    static func shouldFadeLeadingEdge(
        measuredTextWidth: CGFloat?,
        availableWidth: CGFloat
    ) -> Bool {
        guard let measuredTextWidth else { return false }
        return measuredTextWidth > availableWidth + 0.5
    }
}

struct OverlayView: View {
    @ObservedObject var sessionState: SessionState
    @ObservedObject var settingsStore: SettingsStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let onCycleLanguage: () -> Void
    @State private var appear = false

    private var isEnhancing: Bool { sessionState.overlayLabel == "Enhancing" }

    private var presentation: RecorderWidgetPresentation {
        RecorderWidgetPresentation(
            transcript: sessionState.lastTranscript,
            recordingPhase: sessionState.recordingPhase,
            isLiveTranscriptEnabled: settingsStore.showLiveTranscriptInRecorderWidget
        )
    }

    private var cardCornerRadius: CGFloat {
        presentation.showsStreamedText ? 18 : 17
    }

    private var contentAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.16)
    }

    private var transcriptRowTransition: AnyTransition {
        guard !reduceMotion else { return .identity }
        return .asymmetric(
            insertion: .identity,
            removal: .opacity
        )
    }

    var body: some View {
        VStack(alignment: .center, spacing: presentation.showsStreamedText ? 4 : 0) {
            if let streamedText = presentation.streamedText {
                StreamingTranscriptText(text: streamedText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(transcriptRowTransition)
            }

            HStack(spacing: 8) {
                if settingsStore.showLanguageInRecorderWidget {
                    LanguageCycleButton(
                        language: settingsStore.transcriptionProvider.normalizedLanguage(
                            settingsStore.deepgramLanguage
                        ),
                        action: onCycleLanguage
                    )
                }

                PulseOrb(enhancing: isEnhancing)

                if let appIcon = sessionState.overlayAppIcon {
                    OverlayAppIcon(icon: appIcon)
                }

                if isEnhancing {
                    SparkleStars()
                        .transition(.opacity.combined(with: .scale(scale: 0.82)))
                } else {
                    MiniWaveform(level: sessionState.audioLevel)
                        .transition(.opacity.combined(with: .scale(scale: 0.82)))
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .animation(contentAnimation, value: isEnhancing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(.horizontal, 12)
        .padding(.vertical, presentation.showsStreamedText ? 8 : 5)
        .modifier(OverlayCardSurface(cornerRadius: cardCornerRadius))
        // Existing word positions update immediately. Newly appended words animate inside the row.
        .animation(contentAnimation, value: presentation.showsStreamedText)
        .scaleEffect(appear ? 1.0 : 0.96)
        .opacity(appear ? 1.0 : 0.0)
        .offset(y: appear ? 0 : -8)
        .id(sessionState.overlayPulseID)
        .onAppear {
            withAnimation(.spring(response: 0.42, dampingFraction: 0.72, blendDuration: 0.2)) {
                appear = sessionState.overlayVisible
            }
        }
        .onDisappear {
            appear = false
        }
        .onChange(of: sessionState.overlayVisible) { visible in
            if visible {
                withAnimation(.spring(response: 0.42, dampingFraction: 0.72, blendDuration: 0.2)) {
                    appear = true
                }
            } else {
                withAnimation(.easeInOut(duration: 0.18)) {
                    appear = false
                }
            }
        }
    }

}

private struct StreamingTranscriptText: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let text: String
    @State private var words: [RecorderWidgetTranscriptWord] = []
    @State private var entranceDelays: [Int: Double] = [:]

    private var layoutAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.12)
    }

    var body: some View {
        TranscriptWordLayout(spacing: RecorderWidgetLayout.wordSpacing) {
            ForEach(words) { word in
                AnimatedTranscriptWord(
                    text: word.text,
                    delay: entranceDelays[word.id] ?? 0
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 14, maxHeight: 14, alignment: .leading)
        .clipped()
        .mask {
            GeometryReader { geometry in
                if RecorderWidgetLayout.shouldFadeLeadingEdge(
                    measuredTextWidth: RecorderWidgetLayout.measuredTextWidth(for: text),
                    availableWidth: geometry.size.width
                ) {
                    HStack(spacing: 0) {
                        LinearGradient(
                            colors: [.clear, .white],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: min(RecorderWidgetLayout.leadingFadeWidth, geometry.size.width))

                        Color.white
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                } else {
                    Color.white
                }
            }
        }
        .animation(layoutAnimation, value: words.last?.id)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
        .onAppear {
            updateWords(from: text)
        }
        .onChange(of: text) { updatedText in
            updateWords(from: updatedText)
        }
    }

    private func updateWords(from transcript: String) {
        let updatedWords = RecorderWidgetTranscriptWords.project(transcript)
        let existingIDs = Set(words.map(\.id))
        let newIDs = updatedWords.lazy.filter { !existingIDs.contains($0.id) }.map(\.id)
        entranceDelays = Dictionary(uniqueKeysWithValues: newIDs.enumerated().map { index, id in
            (id, min(Double(index) * 0.025, 0.075))
        })
        words = updatedWords
    }
}

private struct AnimatedTranscriptWord: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let text: String
    let delay: Double
    @State private var isVisible = false

    var body: some View {
        Text(text)
            .font(.system(size: RecorderWidgetLayout.transcriptFontSize, weight: .regular))
            .foregroundStyle(Color.primary.opacity(0.76))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .opacity(isVisible || reduceMotion ? 1 : 0.6)
            .offset(y: isVisible || reduceMotion ? 0 : 3)
            .onAppear {
                guard !reduceMotion else {
                    isVisible = true
                    return
                }
                withAnimation(
                    .spring(response: 0.22, dampingFraction: 0.86)
                        .delay(delay)
                ) {
                    isVisible = true
                }
            }
            .onChange(of: reduceMotion) { shouldReduceMotion in
                if shouldReduceMotion {
                    isVisible = true
                }
            }
    }
}

/// Centers text while it fits, then clips from the start to keep the newest words visible.
private struct TranscriptWordLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let contentWidth = sizes.reduce(0) { $0 + $1.width }
            + CGFloat(max(0, sizes.count - 1)) * spacing
        let contentHeight = sizes.map(\.height).max() ?? 0
        return CGSize(
            width: proposal.width ?? contentWidth,
            height: proposal.height ?? contentHeight
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let contentWidth = sizes.reduce(0) { $0 + $1.width }
            + CGFloat(max(0, sizes.count - 1)) * spacing
        var x = contentWidth > bounds.width
            ? bounds.maxX - contentWidth
            : bounds.midX - contentWidth / 2

        for (subview, size) in zip(subviews, sizes) {
            subview.place(
                at: CGPoint(x: x, y: bounds.midY),
                anchor: .leading,
                proposal: ProposedViewSize(width: size.width, height: size.height)
            )
            x += size.width + spacing
        }
    }
}

private struct OverlayCardSurface: ViewModifier {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            content.glassEffect(
                .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            content
                .background(OverlayGlassBackground(cornerRadius: cornerRadius))
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
                .overlay(fallbackBorder)
        }
    }

    private var fallbackBorder: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(colorScheme == .dark ? 0.34 : 0.58),
                        Color.white.opacity(colorScheme == .dark ? 0.08 : 0.16),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                lineWidth: 1
            )
    }
}

private struct LanguageCycleButton: View {
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false
    let language: DeepgramLanguage
    let action: () -> Void

    private var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    @ViewBuilder
    var body: some View {
        if #available(macOS 26.0, *), !reduceTransparency {
            button
                .glassEffect(
                    .clear.interactive(),
                    in: RoundedRectangle(cornerRadius: 7, style: .continuous)
                )
        } else {
            button
                .background(fallbackBackground)
                .animation(.easeOut(duration: 0.12), value: isHovered)
                .onHover { isHovered = $0 }
        }
    }

    private var button: some View {
        Button(action: action) {
            Group {
                if language == .automatic {
                    Image(systemName: "globe")
                        .font(.system(size: 13, weight: .medium))
                } else {
                    Text(language.menuBarAbbreviation)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            .frame(width: 24, height: 24)
            .contentShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary.opacity(colorScheme == .dark ? 0.88 : 0.66))
        .help("Language: \(language.displayName)")
        .accessibilityLabel("Transcription language")
        .accessibilityValue(language.displayName)
    }

    private var fallbackBackground: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(
                Color.primary.opacity(
                    isHovered
                        ? (colorScheme == .dark ? 0.14 : 0.08)
                        : (colorScheme == .dark ? 0.07 : 0.035)
                )
            )
    }
}

private struct VisualEffectBackdropView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
            ? .windowBackground
            : material
        nsView.blendingMode = blendingMode
        nsView.state = .active
    }
}

private struct OverlayGlassBackground: View {
    let cornerRadius: CGFloat
    @Environment(\.colorScheme) private var colorScheme

    private var reduceTransparency: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    private var highlightOpacity: Double {
        if reduceTransparency {
            return 0.04
        }

        return colorScheme == .dark ? 0.14 : 0.16
    }

    private var glowOpacity: Double {
        guard !reduceTransparency else { return 0 }
        return colorScheme == .dark ? 0.08 : 0.07
    }

    var body: some View {
        ZStack {
            VisualEffectBackdropView(material: .hudWindow)

            if reduceTransparency {
                Color(NSColor.windowBackgroundColor)
                    .opacity(0.95)
            }

            LinearGradient(
                colors: [
                    Color.white.opacity(highlightOpacity),
                    Color.white.opacity(0.03),
                    Color.white.opacity(0)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            RadialGradient(
                colors: [
                    Color.white.opacity(glowOpacity),
                    Color.white.opacity(0)
                ],
                center: .topLeading,
                startRadius: 4,
                endRadius: 56
            )
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

private struct OverlayAppIcon: View {
    let icon: NSImage

    var body: some View {
        Image(nsImage: icon)
            .resizable()
            .interpolation(.high)
            .frame(width: 18, height: 18)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

private struct MiniWaveform: View {
    @Environment(\.colorScheme) private var colorScheme
    let level: CGFloat

    private let barCount = 5
    private let barWidth: CGFloat = 2.5
    private let spacing: CGFloat = 2
    private let maxHeight: CGFloat = 16
    private let minHeight: CGFloat = 3
    private let weights: [CGFloat] = [0.5, 0.8, 1.0, 0.75, 0.45]

    private var visibleLevel: CGFloat {
        RecorderWidgetMeter.visibleLevel(for: level)
    }

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { i in
                RoundedRectangle(cornerRadius: barWidth / 2)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.82 : 0.48))
                    .frame(width: barWidth, height: barHeight(for: i))
            }
        }
        .animation(.easeOut(duration: 0.12), value: visibleLevel)
    }

    private func barHeight(for index: Int) -> CGFloat {
        minHeight + (maxHeight - minHeight) * visibleLevel * weights[index]
    }
}

private struct SparkleStars: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var animate = false

    var body: some View {
        ZStack {
            star(size: 10, opacity: 1.0, dx: 2.5, dy: -2, duration: 1.2)
            star(size: 7, opacity: 0.7, dx: -3, dy: 2.5, duration: 1.5)
            star(size: 6, opacity: 0.5, dx: 2, dy: 1.5, duration: 1.0)
        }
        .frame(width: 23, height: 20)
        .onAppear { animate = !reduceMotion }
        .onChange(of: reduceMotion) { animate = !$0 }
    }

    private func star(size: CGFloat, opacity: Double, dx: CGFloat, dy: CGFloat, duration: Double) -> some View {
        StarShape()
            .fill(Color.primary.opacity(opacity * (colorScheme == .dark ? 1 : 0.55)))
            .frame(width: size, height: size)
            .offset(x: animate ? dx : -dx, y: animate ? dy : -dy)
            .animation(
                .easeInOut(duration: duration).repeatForever(autoreverses: true),
                value: animate
            )
    }
}

private struct StarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outer = min(rect.width, rect.height) / 2
        let inner = outer * 0.38
        var path = Path()
        for i in 0..<8 {
            let angle = Double(i) * .pi / 4 - .pi / 2
            let r = i.isMultiple(of: 2) ? outer : inner
            let pt = CGPoint(x: center.x + CGFloat(cos(angle)) * r,
                             y: center.y + CGFloat(sin(angle)) * r)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        return path
    }
}

private struct PulseOrb: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var enhancing: Bool = false

    var body: some View {
        ZStack {
            if enhancing {
                Circle()
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.48 : 0.28))
                    .frame(width: 8, height: 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
            } else {
                Circle()
                    .fill(Color.red.opacity(0.18))
                    .frame(width: 20, height: 20)
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [Color.red, Color.red.opacity(0.7)],
                            center: .center,
                            startRadius: 2,
                            endRadius: 12
                        )
                    )
                    .frame(width: 8, height: 8)
                    .shadow(color: Color.red.opacity(0.48), radius: 5, x: 0, y: 0)
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
            }
        }
        .frame(width: 22, height: 22)
        .animation(
            reduceMotion ? nil : .spring(response: 0.3, dampingFraction: 0.78),
            value: enhancing
        )
    }
}
