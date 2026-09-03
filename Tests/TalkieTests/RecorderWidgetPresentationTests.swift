import XCTest
@testable import TalkieCore

final class RecorderWidgetPresentationTests: XCTestCase {
    func testDoesNotShowTextUntilStreamedTextArrives() {
        let presentation = RecorderWidgetPresentation(
            transcript: "",
            recordingPhase: .recording,
            isLiveTranscriptEnabled: true
        )

        XCTAssertNil(presentation.streamedText)
        XCTAssertFalse(presentation.showsStreamedText)
    }

    func testShowsTrimmedStreamedTextWhileRecording() {
        let presentation = RecorderWidgetPresentation(
            transcript: "  This is live  ",
            recordingPhase: .recording,
            isLiveTranscriptEnabled: true
        )

        XCTAssertEqual(presentation.streamedText, "This is live")
        XCTAssertTrue(presentation.showsStreamedText)
    }

    func testFinalizingHidesStaleStreamedText() {
        let presentation = RecorderWidgetPresentation(
            transcript: "Old streamed text",
            recordingPhase: .finalizing,
            isLiveTranscriptEnabled: true
        )

        XCTAssertNil(presentation.streamedText)
        XCTAssertFalse(presentation.showsStreamedText)
    }

    func testMeterStaysStillForQuietAudio() {
        XCTAssertEqual(RecorderWidgetMeter.visibleLevel(for: 0.08), 0)
        XCTAssertEqual(RecorderWidgetMeter.visibleLevel(for: 0.12), 0)
        XCTAssertGreaterThan(RecorderWidgetMeter.visibleLevel(for: 0.2), 0)
    }

    func testMeterSmoothingApproachesChangesWithoutOvershooting() {
        let risingLevel = RecorderWidgetMeter.smoothedLevel(current: 0, target: 1)
        let fallingLevel = RecorderWidgetMeter.smoothedLevel(current: 1, target: 0)

        XCTAssertGreaterThan(risingLevel, 0)
        XCTAssertLessThan(risingLevel, 1)
        XCTAssertGreaterThan(fallingLevel, 0)
        XCTAssertLessThan(fallingLevel, 1)
        XCTAssertEqual(RecorderWidgetMeter.smoothedLevel(current: 0.998, target: 1), 1)
    }

    func testTranscriptWordPositionsStayStableAcrossCorrectionsAndAppends() {
        let initial = RecorderWidgetTranscriptWords.project("hello world")
        let corrected = RecorderWidgetTranscriptWords.project("hello there")
        let appended = RecorderWidgetTranscriptWords.project("hello there again")

        XCTAssertEqual(corrected.map(\.id), initial.map(\.id))
        XCTAssertEqual(corrected.map(\.text), ["hello", "there"])
        XCTAssertEqual(appended.map(\.id), [0, 1, 2])
    }

    func testTranscriptWordProjectionKeepsOnlyTheNewestWordWindow() {
        let transcript = (0...RecorderWidgetTranscriptWords.visibleLimit)
            .map { "word\($0)" }
            .joined(separator: " ")
        let words = RecorderWidgetTranscriptWords.project(transcript)

        XCTAssertEqual(words.count, RecorderWidgetTranscriptWords.visibleLimit)
        XCTAssertEqual(words.first?.id, 1)
        XCTAssertEqual(words.first?.text, "word1")
        XCTAssertEqual(words.last?.text, "word24")
    }

    func testTranscriptWidthStartsCompactThenGrowsWithoutShrinking() {
        let compactWidth: CGFloat = 112
        let initialWidth = RecorderWidgetLayout.nextWidth(
            compactWidth: compactWidth,
            measuredTextWidth: 40,
            previousWidth: nil
        )
        let expandedWidth = RecorderWidgetLayout.nextWidth(
            compactWidth: compactWidth,
            measuredTextWidth: 150,
            previousWidth: initialWidth
        )
        let correctedWidth = RecorderWidgetLayout.nextWidth(
            compactWidth: compactWidth,
            measuredTextWidth: 80,
            previousWidth: expandedWidth
        )

        XCTAssertEqual(initialWidth, compactWidth)
        XCTAssertGreaterThan(expandedWidth, initialWidth)
        XCTAssertEqual(correctedWidth, expandedWidth)
    }

    func testTranscriptWidthCapsAndResetsToCompact() {
        let expandedWidth = RecorderWidgetLayout.nextWidth(
            compactWidth: 112,
            measuredTextWidth: 1_000,
            previousWidth: nil
        )
        let resetWidth = RecorderWidgetLayout.nextWidth(
            compactWidth: 112,
            measuredTextWidth: nil,
            previousWidth: expandedWidth
        )

        XCTAssertEqual(expandedWidth, RecorderWidgetLayout.maximumWidth)
        XCTAssertEqual(resetWidth, 112)
    }

    func testTranscriptStylesUseDifferentContextAndWidth() {
        XCTAssertEqual(RecorderWidgetLayout.visibleWordLimit(for: .flow), 24)
        XCTAssertEqual(RecorderWidgetLayout.visibleWordLimit(for: .focus), 7)
        XCTAssertEqual(RecorderWidgetLayout.visibleWordLimit(for: .captions), 20)

        let focusedWidth = RecorderWidgetLayout.nextWidth(
            compactWidth: 112,
            measuredTextWidth: 1_000,
            previousWidth: nil,
            style: .focus
        )
        let captionWidth = RecorderWidgetLayout.nextWidth(
            compactWidth: 112,
            measuredTextWidth: 40,
            previousWidth: nil,
            style: .captions
        )

        XCTAssertEqual(focusedWidth, 220)
        XCTAssertEqual(captionWidth, 230)
    }

    func testTranscriptLeadingFadeOnlyAppearsForOverflow() {
        XCTAssertFalse(
            RecorderWidgetLayout.shouldFadeLeadingEdge(
                measuredTextWidth: 236,
                availableWidth: 236
            )
        )
        XCTAssertTrue(
            RecorderWidgetLayout.shouldFadeLeadingEdge(
                measuredTextWidth: 237,
                availableWidth: 236
            )
        )
        XCTAssertFalse(
            RecorderWidgetLayout.shouldFadeLeadingEdge(
                measuredTextWidth: nil,
                availableWidth: 236
            )
        )
    }
}
