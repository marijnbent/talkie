import CoreAudio
import Foundation

enum SystemMuteAudioError: Error, Equatable {
    case noDefaultOutputDevice
    case coreAudio(OSStatus)
}

struct SystemMuteAudioOperations {
    let defaultOutputDevice: () -> Result<AudioDeviceID, SystemMuteAudioError>
    let readMute: (AudioDeviceID) -> Result<Bool, SystemMuteAudioError>
    let writeMute: (AudioDeviceID, Bool) -> Result<Void, SystemMuteAudioError>

    @MainActor static let live = SystemMuteAudioOperations(
        defaultOutputDevice: {
            var deviceID = AudioDeviceID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout<AudioDeviceID>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            let status = AudioObjectGetPropertyData(
                AudioObjectID(kAudioObjectSystemObject),
                &address,
                0,
                nil,
                &size,
                &deviceID
            )
            guard status == noErr else { return .failure(.coreAudio(status)) }
            guard deviceID != kAudioObjectUnknown else { return .failure(.noDefaultOutputDevice) }
            return .success(deviceID)
        },
        readMute: { deviceID in
            var value: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            let status = AudioObjectGetPropertyData(deviceID, &address, 0, nil, &size, &value)
            guard status == noErr else { return .failure(.coreAudio(status)) }
            return .success(value != 0)
        },
        writeMute: { deviceID, isMuted in
            var value: UInt32 = isMuted ? 1 : 0
            let size = UInt32(MemoryLayout<UInt32>.size)
            var address = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyMute,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: kAudioObjectPropertyElementMain
            )
            let status = AudioObjectSetPropertyData(deviceID, &address, 0, nil, size, &value)
            guard status == noErr else { return .failure(.coreAudio(status)) }
            return .success(())
        }
    )
}

@MainActor
final class SystemMuteController {
    private struct SavedMuteState {
        let deviceID: AudioDeviceID
        let wasMuted: Bool
    }

    private var savedMuteState: SavedMuteState?
    private let audio: SystemMuteAudioOperations
    private let onLog: (String, LogLevel) -> Void

    init(
        audio: SystemMuteAudioOperations = .live,
        onLog: @escaping (String, LogLevel) -> Void
    ) {
        self.audio = audio
        self.onLog = onLog
    }

    func muteForRecording() {
        guard savedMuteState == nil else { return }

        let deviceID: AudioDeviceID
        switch audio.defaultOutputDevice() {
        case .success(let value):
            deviceID = value
        case .failure(let error):
            log(error, action: "find the default output device")
            return
        }

        let wasMuted: Bool
        switch audio.readMute(deviceID) {
        case .success(let value):
            wasMuted = value
        case .failure(let error):
            log(error, action: "read the system mute state")
            return
        }

        guard !wasMuted else { return }

        switch audio.writeMute(deviceID, true) {
        case .success:
            savedMuteState = SavedMuteState(deviceID: deviceID, wasMuted: wasMuted)
        case .failure(let error):
            log(error, action: "mute the system output")
        }
    }

    func restoreMute() {
        guard let savedMuteState else { return }

        switch audio.writeMute(savedMuteState.deviceID, savedMuteState.wasMuted) {
        case .success:
            self.savedMuteState = nil
        case .failure(let error):
            // Keep the saved state so shutdown or a later cleanup call can retry safely.
            log(error, action: "restore the system mute state")
        }
    }

    private func log(_ error: SystemMuteAudioError, action: String) {
        switch error {
        case .noDefaultOutputDevice:
            onLog("Unable to \(action): no default output device.", .warning)
        case .coreAudio(let status):
            onLog("Unable to \(action) (CoreAudio status \(status)).", .warning)
        }
    }
}
