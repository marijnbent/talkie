import AVFoundation
import Foundation

struct Linear16AudioChunk: Sendable, Equatable {
    let data: Data
    let meterLevel: Float
}

enum AudioBufferConverter {
    /// Converts one capture buffer and calculates its display level in the same pass.
    static func linear16Chunk(from buffer: AVAudioPCMBuffer) -> Linear16AudioChunk? {
        guard let floatChannelData = buffer.floatChannelData else { return nil }

        let channelCount = Int(buffer.format.channelCount)
        let frameLength = Int(buffer.frameLength)
        let sampleCount = frameLength * channelCount
        guard sampleCount > 0 else {
            return Linear16AudioChunk(data: Data(), meterLevel: 0)
        }

        var int16Samples = [Int16](repeating: 0, count: sampleCount)
        var firstChannelSquareSum: Float = 0
        int16Samples.withUnsafeMutableBufferPointer { destination in
            var index = 0
            for frame in 0..<frameLength {
                for channel in 0..<channelCount {
                    let sample = floatChannelData[channel][frame]
                    if channel == 0 {
                        firstChannelSquareSum += sample * sample
                    }
                    let clamped = max(-1.0, min(1.0, sample))
                    destination[index] = Int16(clamped * Float(Int16.max))
                    index += 1
                }
            }
        }

        let data = int16Samples.withUnsafeBufferPointer { bufferPointer in
            Data(buffer: bufferPointer)
        }
        let rootMeanSquare = sqrt(firstChannelSquareSum / Float(frameLength))
        let meterLevel = min(1, sqrt(rootMeanSquare) * 3.5)
        return Linear16AudioChunk(data: data, meterLevel: meterLevel)
    }
}
