import AVFoundation
import XCTest
@testable import TalkieCore

final class AudioBufferConverterTests: XCTestCase {
    func testLinear16ChunkConvertsFloatSamplesAndCalculatesMeterLevel() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 3)!
        buffer.frameLength = 3

        let channel = buffer.floatChannelData![0]
        channel[0] = -1.0
        channel[1] = 0.0
        channel[2] = 1.0

        guard let chunk = AudioBufferConverter.linear16Chunk(from: buffer) else {
            return XCTFail("Expected a linear16 chunk for the float buffer.")
        }

        let values = chunk.data.withUnsafeBytes { bufferPointer -> [Int16] in
            Array(bufferPointer.bindMemory(to: Int16.self))
        }

        XCTAssertEqual(values, [-32767, 0, 32767])
        XCTAssertGreaterThan(chunk.meterLevel, 0)
        XCTAssertLessThanOrEqual(chunk.meterLevel, 1)
    }

    func testLinear16ChunkClampsOutOfRangeSamples() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2)!
        buffer.frameLength = 2

        let channel = buffer.floatChannelData![0]
        channel[0] = 2.0
        channel[1] = -2.0

        guard let chunk = AudioBufferConverter.linear16Chunk(from: buffer) else {
            return XCTFail("Expected a linear16 chunk for the float buffer.")
        }

        let values = chunk.data.withUnsafeBytes { bufferPointer -> [Int16] in
            Array(bufferPointer.bindMemory(to: Int16.self))
        }

        XCTAssertEqual(values, [32767, -32767])
    }
}
