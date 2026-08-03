import Foundation
import CoreMIDI
import Combine

/// Gestore nativo CoreMIDI per tastiere MIDI fisiche USB/Bluetooth client-side.
/// Invia le note via TCP al server affinché usino lo strumento SF2 selezionato e illumina i tasti a schermo.
@MainActor
final class GUIMIDIManager: ObservableObject {
    @Published var connectedDevices: [String] = []

    nonisolated(unsafe) private var client: MIDIClientRef = 0
    nonisolated(unsafe) private var inputPort: MIDIPortRef = 0
    private weak var clientService: TCPClientService?

    init() {
    }

    deinit {
        stop()
    }

    func startMonitoring(clientService: TCPClientService) {
        self.clientService = clientService
        stop()

        var status = MIDIClientCreateWithBlock("AudioTCPGUIClientMIDIClient" as CFString, &client) { [weak self] notificationPtr in
            if notificationPtr.pointee.messageID == .msgSetupChanged {
                Task { @MainActor [weak self] in
                    self?.refreshDevices()
                }
            }
        }

        guard status == noErr else { return }

        status = MIDIInputPortCreateWithBlock(client, "AudioTCPGUIClientInputPort" as CFString, &inputPort) { [weak self] pktlistPtr, _ in
            self?.handleMIDIPackets(pktlistPtr.pointee)
        }

        guard status == noErr else { return }

        refreshDevices()
    }

    nonisolated func stop() {
        if inputPort != 0 {
            MIDIPortDispose(inputPort)
            inputPort = 0
        }
        if client != 0 {
            MIDIClientDispose(client)
            client = 0
        }
    }

    func refreshDevices() {
        var names: [String] = []
        let sourceCount = MIDIGetNumberOfSources()

        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            _ = MIDIPortConnectSource(inputPort, source, nil)

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

    nonisolated private func handleMIDIPackets(_ packetList: MIDIPacketList) {
        var packet = packetList.packet
        for _ in 0..<packetList.numPackets {
            parsePacketData(packet)
            packet = MIDIPacketNext(&packet).pointee
        }
    }

    nonisolated private func parsePacketData(_ packet: MIDIPacket) {
        let length = Int(packet.length)
        guard length >= 2 else { return }

        var bytes = [UInt8]()
        bytes.reserveCapacity(length)
        
        var tempPacket = packet
        withUnsafePointer(to: &tempPacket.data) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: length) { bytePtr in
                for k in 0..<length {
                    bytes.append(bytePtr[k])
                }
            }
        }

        var i = 0
        while i < length {
            let statusByte = bytes[i]
            let messageType = statusByte & 0xF0

            if messageType == 0x90 { // Note On
                if i + 2 < length {
                    let note = bytes[i + 1]
                    let velocity = bytes[i + 2]
                    let isNoteOn = velocity > 0
                    Task { @MainActor in
                        self.clientService?.setNoteActive(midi: note, active: isNoteOn, velocity: Double(velocity))
                    }
                    i += 3
                } else { break }
            } else if messageType == 0x80 { // Note Off
                if i + 1 < length {
                    let note = bytes[i + 1]
                    Task { @MainActor in
                        self.clientService?.setNoteActive(midi: note, active: false)
                    }
                    i += (i + 2 < length ? 3 : 2)
                } else { break }
            } else if messageType == 0xC0 { // Program Change da tastiera fisica
                if i + 1 < length {
                    let prog = bytes[i + 1]
                    Task { @MainActor in
                        self.clientService?.setSF2Program(prog)
                    }
                    i += 2
                } else { break }
            } else {
                i += 1
            }
        }
    }
}
