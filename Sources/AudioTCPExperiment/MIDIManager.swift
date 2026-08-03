import Foundation
import CoreMIDI

/// Gestore nativo CoreMIDI per rilevare e connettere tastiere MIDI hardware fisiche USB/Bluetooth.
public final class MIDIManager: @unchecked Sendable {
    private var client: MIDIClientRef = 0
    private var inputPort: MIDIPortRef = 0
    private let audio: AudioSynth
    private let lock = NSLock()

    public private(set) var connectedDevices: [String] = []
    public var onDevicesChanged: (([String]) -> Void)?

    public init(audio: AudioSynth) {
        self.audio = audio
    }

    deinit {
        stop()
    }

    public func start() {
        var status = MIDIClientCreateWithBlock("AudioTCPExperimentMIDIClient" as CFString, &client) { [weak self] notificationPtr in
            let notification = notificationPtr.pointee
            if notification.messageID == .msgSetupChanged {
                DispatchQueue.main.async {
                    self?.rescanDevices()
                }
            }
        }

        guard status == noErr else {
            print("[\u{001B}[31m✗\u{001B}[0m] Impossibile creare il MIDI Client: \(status)")
            return
        }

        status = MIDIInputPortCreateWithBlock(client, "AudioTCPExperimentInputPort" as CFString, &inputPort) { [weak self] pktlistPtr, _ in
            self?.handleIncomingMIDIPackets(pktlistPtr.pointee)
        }

        guard status == noErr else {
            print("[\u{001B}[31m✗\u{001B}[0m] Impossibile creare la porta MIDI Input: \(status)")
            return
        }

        rescanDevices()
    }

    public func stop() {
        if inputPort != 0 {
            MIDIPortDispose(inputPort)
            inputPort = 0
        }
        if client != 0 {
            MIDIClientDispose(client)
            client = 0
        }
    }

    public func rescanDevices() {
        lock.lock()
        defer { lock.unlock() }

        var deviceNames: [String] = []
        let sourceCount = MIDIGetNumberOfSources()

        for i in 0..<sourceCount {
            let source = MIDIGetSource(i)
            let status = MIDIPortConnectSource(inputPort, source, nil)
            
            var nameRef: Unmanaged<CFString>?
            let nameStatus = MIDIObjectGetStringProperty(source, kMIDIPropertyDisplayName, &nameRef)
            
            let name: String
            if nameStatus == noErr, let cfName = nameRef?.takeRetainedValue() {
                name = cfName as String
            } else {
                name = "Dispositivo MIDI #\(i + 1)"
            }

            // Ignora il driver di sistema IAC Bus per evitare interferenze di sintesi Apple DLS
            if name.contains("IAC") {
                continue
            }

            if status == noErr {
                deviceNames.append(name)
            }
        }

        self.connectedDevices = deviceNames
        
        if deviceNames.isEmpty {
            print("[\u{001B}[33m!\u{001B}[0m] Nessuna tastiera MIDI fisica trovata.")
        } else {
            print("[\u{001B}[32m✓\u{001B}[0m] Tastiere MIDI fisiche connesse (\(deviceNames.count)):")
            for dev in deviceNames {
                print("    - 🎹 \(dev)")
            }
        }

        onDevicesChanged?(deviceNames)
    }

    private func handleIncomingMIDIPackets(_ packetList: MIDIPacketList) {
        var packet = packetList.packet
        for _ in 0..<packetList.numPackets {
            parsePacketData(packet)
            packet = MIDIPacketNext(&packet).pointee
        }
    }

    private func parsePacketData(_ packet: MIDIPacket) {
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
                    if velocity > 0 {
                        print("[\u{001B}[35mMIDI Input Hardware\u{001B}[0m] NoteOn: nota=\(note) vel=\(velocity)")
                        let freq = midiNoteToFrequency(note)
                        audio.enqueueNoteOn(frequency: freq, note: note, velocity: Double(velocity))
                    } else {
                        audio.enqueueNoteOff(note: note, sustainOff: 0)
                    }
                    i += 3
                } else { break }
            } else if messageType == 0x80 { // Note Off
                if i + 1 < length {
                    let note = bytes[i + 1]
                    audio.enqueueNoteOff(note: note, sustainOff: 0)
                    i += (i + 2 < length ? 3 : 2)
                } else { break }
            } else if messageType == 0xB0 { // Control Change (CC)
                if i + 2 < length {
                    // CC events can be extended for SF2 volume / expression
                    i += 3
                } else { break }
            } else {
                i += 1
            }
        }
    }
}
