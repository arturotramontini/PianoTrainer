import Foundation
import CoreMIDI
import Combine

/// Monitor per il rilevamento delle tastiere MIDI hardware fisiche nella GUI.
@MainActor
final class GUIMIDIManager: ObservableObject {
    @Published var connectedDevices: [String] = []

    private var client: MIDIClientRef = 0

    init() {
        startMonitoring()
    }

    deinit {
        if client != 0 {
            MIDIClientDispose(client)
        }
    }

    func startMonitoring() {
        let status = MIDIClientCreateWithBlock("AudioTCPGUIClientMIDIClient" as CFString, &client) { [weak self] notificationPtr in
            if notificationPtr.pointee.messageID == .msgSetupChanged {
                Task { @MainActor [weak self] in
                    self?.refreshDevices()
                }
            }
        }

        if status == noErr {
            refreshDevices()
        }
    }

    func refreshDevices() {
        var names: [String] = []
        let sourceCount = MIDIGetNumberOfSources()

        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            var nameRef: Unmanaged<CFString>?
            let nameStatus = MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &nameRef)
            
            if nameStatus == noErr, let cfName = nameRef?.takeRetainedValue() {
                names.append(cfName as String)
            } else {
                names.append("MIDI Device #\(i + 1)")
            }
        }

        self.connectedDevices = names
    }
}
