import CoreAudio
import XCTest
@testable import TalkieCore

@MainActor
final class SystemMuteControllerTests: XCTestCase {
    private struct WriteCall: Equatable {
        let deviceID: AudioDeviceID
        let isMuted: Bool
    }

    func testDoesNotMuteWhenCurrentStateCannotBeRead() {
        var writes: [WriteCall] = []
        let controller = makeController(
            defaultDevice: { .success(41) },
            readMute: { _ in .failure(.coreAudio(-1)) },
            writeMute: { deviceID, isMuted in
                writes.append(WriteCall(deviceID: deviceID, isMuted: isMuted))
                return .success(())
            }
        )

        controller.muteForRecording()
        controller.restoreMute()

        XCTAssertTrue(writes.isEmpty)
    }

    func testRestoresTheDeviceThatWasMutedEvenWhenTheDefaultChanges() {
        var defaultDevice = AudioDeviceID(41)
        var writes: [WriteCall] = []
        let controller = makeController(
            defaultDevice: { .success(defaultDevice) },
            readMute: { _ in .success(false) },
            writeMute: { deviceID, isMuted in
                writes.append(WriteCall(deviceID: deviceID, isMuted: isMuted))
                return .success(())
            }
        )

        controller.muteForRecording()
        defaultDevice = 99
        controller.restoreMute()

        XCTAssertEqual(
            writes,
            [
                WriteCall(deviceID: 41, isMuted: true),
                WriteCall(deviceID: 41, isMuted: false),
            ]
        )
    }

    func testFailedMuteWriteDoesNotCreateRestorationState() {
        var writes: [WriteCall] = []
        let controller = makeController(
            defaultDevice: { .success(41) },
            readMute: { _ in .success(false) },
            writeMute: { deviceID, isMuted in
                writes.append(WriteCall(deviceID: deviceID, isMuted: isMuted))
                return .failure(.coreAudio(-2))
            }
        )

        controller.muteForRecording()
        controller.restoreMute()

        XCTAssertEqual(writes, [WriteCall(deviceID: 41, isMuted: true)])
    }

    func testFailedRestoreCanBeRetried() {
        var writes: [WriteCall] = []
        var restoreAttempts = 0
        let controller = makeController(
            defaultDevice: { .success(41) },
            readMute: { _ in .success(false) },
            writeMute: { deviceID, isMuted in
                writes.append(WriteCall(deviceID: deviceID, isMuted: isMuted))
                guard !isMuted else { return .success(()) }

                restoreAttempts += 1
                return restoreAttempts == 1 ? .failure(.coreAudio(-3)) : .success(())
            }
        )

        controller.muteForRecording()
        controller.restoreMute()
        controller.restoreMute()
        controller.restoreMute()

        XCTAssertEqual(
            writes,
            [
                WriteCall(deviceID: 41, isMuted: true),
                WriteCall(deviceID: 41, isMuted: false),
                WriteCall(deviceID: 41, isMuted: false),
            ]
        )
    }

    private func makeController(
        defaultDevice: @escaping () -> Result<AudioDeviceID, SystemMuteAudioError>,
        readMute: @escaping (AudioDeviceID) -> Result<Bool, SystemMuteAudioError>,
        writeMute: @escaping (AudioDeviceID, Bool) -> Result<Void, SystemMuteAudioError>
    ) -> SystemMuteController {
        SystemMuteController(
            audio: SystemMuteAudioOperations(
                defaultOutputDevice: defaultDevice,
                readMute: readMute,
                writeMute: writeMute
            ),
            onLog: { _, _ in }
        )
    }
}
