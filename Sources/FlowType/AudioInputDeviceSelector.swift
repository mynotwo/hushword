import AVFoundation
import AudioToolbox
import CoreAudio

package struct AudioInputDeviceCandidate: Equatable, Sendable {
    package let identifier: AudioObjectID
    package let hasInput: Bool
    package let isBuiltIn: Bool

    package init(
        identifier: AudioObjectID,
        hasInput: Bool,
        isBuiltIn: Bool
    ) {
        self.identifier = identifier
        self.hasInput = hasInput
        self.isBuiltIn = isBuiltIn
    }
}

package enum AudioInputDevicePolicy {
    package static func preferredDeviceIdentifier(
        devices: [AudioInputDeviceCandidate],
        defaultDeviceIdentifier: AudioObjectID
    ) -> AudioObjectID? {
        if let defaultDevice = devices.first(where: {
            $0.identifier == defaultDeviceIdentifier && $0.hasInput
        }) {
            return defaultDevice.identifier
        }
        if let builtIn = devices.first(where: {
            $0.hasInput && $0.isBuiltIn
        }) {
            return builtIn.identifier
        }
        return devices.first(where: \.hasInput)?.identifier
    }
}

package enum AudioInputDeviceSelector {
    package static func configure(_ inputNode: AVAudioInputNode) {
        guard let audioUnit = inputNode.audioUnit,
              let preferredDeviceIdentifier else {
            return
        }
        var deviceIdentifier = preferredDeviceIdentifier
        AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceIdentifier,
            UInt32(MemoryLayout<AudioObjectID>.size)
        )
    }

    private static var preferredDeviceIdentifier: AudioObjectID? {
        guard let devices = inputDevices,
              let defaultDeviceIdentifier else {
            return nil
        }
        return AudioInputDevicePolicy.preferredDeviceIdentifier(
            devices: devices,
            defaultDeviceIdentifier: defaultDeviceIdentifier
        )
    }

    private static var inputDevices: [AudioInputDeviceCandidate]? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(
            systemObject,
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return nil
        }

        var identifiers = Array(
            repeating: AudioObjectID(0),
            count: Int(dataSize) / MemoryLayout<AudioObjectID>.size
        )
        guard AudioObjectGetPropertyData(
            systemObject,
            &address,
            0,
            nil,
            &dataSize,
            &identifiers
        ) == noErr else {
            return nil
        }
        return identifiers.map {
            AudioInputDeviceCandidate(
                identifier: $0,
                hasInput: hasInput(deviceIdentifier: $0),
                isBuiltIn: transportType(deviceIdentifier: $0)
                    == kAudioDeviceTransportTypeBuiltIn
            )
        }
    }

    private static var defaultDeviceIdentifier: AudioObjectID? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var identifier = AudioObjectID(0)
        var dataSize = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &dataSize,
            &identifier
        ) == noErr else {
            return nil
        }
        return identifier
    }

    private static func hasInput(deviceIdentifier: AudioObjectID) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreamConfiguration,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(
            deviceIdentifier,
            &address,
            0,
            nil,
            &dataSize
        ) == noErr else {
            return false
        }
        let bufferList = AudioBufferList.allocate(
            maximumBuffers: max(
                1,
                Int(dataSize) / MemoryLayout<AudioBuffer>.size
            )
        )
        defer { bufferList.unsafeMutablePointer.deallocate() }

        guard AudioObjectGetPropertyData(
            deviceIdentifier,
            &address,
            0,
            nil,
            &dataSize,
            bufferList.unsafeMutablePointer
        ) == noErr else {
            return false
        }
        return bufferList.contains { $0.mNumberChannels > 0 }
    }

    private static func transportType(
        deviceIdentifier: AudioObjectID
    ) -> UInt32? {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyTransportType,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(
            deviceIdentifier,
            &address,
            0,
            nil,
            &dataSize,
            &value
        ) == noErr else {
            return nil
        }
        return value
    }
}
