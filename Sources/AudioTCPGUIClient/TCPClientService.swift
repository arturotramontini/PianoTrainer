import Foundation
import Network
import SwiftUI
import Combine

/// Servizio di rete TCP per il client SwiftUI SoundFont A320U.sf2 Standalone.
@MainActor
final class TCPClientService: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var isConnecting: Bool = false
    @Published var host: String = "127.0.0.1"
    @Published var port: String = "9876"
    @Published var audioRunning: Bool = false
    @Published var clientCount: Int = 0

    // Strumento SoundFont SF2
    @Published var sf2Program: UInt8 = 0
    @Published var logEntries: [LogEntry] = []

    struct LogEntry: Identifiable {
        let id = UUID()
        let timestamp = Date()
        let message: String
        let isError: Bool
        let isOutgoing: Bool
    }

    private var connection: NWConnection?
    private let networkQueue = DispatchQueue(label: "AudioTCPGUIClient.network")
    private var pendingData = Data()
    @Published var activeNotes = Set<UInt8>()

    init() {
    }

    func connect() {
        guard let portNum = UInt16(port), !isConnected else { return }
        isConnecting = true
        addLog("Connessione a \(host):\(port)...", isOutgoing: true)

        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: portNum)!
        )
        let conn = NWConnection(to: endpoint, using: .tcp)
        self.connection = conn

        conn.stateUpdateHandler = { [weak self] state in
            DispatchQueue.main.async {
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.isConnected = true
                    self.isConnecting = false
                    self.addLog("Connesso al server SoundFont SF2!", isError: false)
                    self.refreshStatus()
                case .failed(let error):
                    self.isConnected = false
                    self.isConnecting = false
                    self.addLog("Errore connessione: \(error.localizedDescription)", isError: true)
                case .cancelled:
                    self.isConnected = false
                    self.isConnecting = false
                    self.addLog("Disconnesso dal server.", isError: false)
                default:
                    break
                }
            }
        }

        conn.start(queue: networkQueue)
        receiveLoop(conn: conn)
    }

    func disconnect() {
        connection?.cancel()
        connection = nil
        isConnected = false
        isConnecting = false
    }

    nonisolated private func receiveLoop(conn: NWConnection) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self, weak conn] data, _, complete, error in
            guard let self = self, let conn = conn else { return }
            if let data = data {
                Task { @MainActor in
                    self.consumeData(data)
                }
            }
            if error == nil && !complete {
                self.receiveLoop(conn: conn)
            }
        }
    }

    private func consumeData(_ data: Data) {
        pendingData.append(data)
        while let end = pendingData.firstIndex(of: 10) { // ASCII LF '\n'
            let lineData = pendingData.prefix(upTo: end)
            pendingData.removeSubrange(...end)
            let line = String(decoding: lineData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            processServerResponse(line)
        }
    }

    private func processServerResponse(_ line: String) {
        let isErr = line.hasPrefix("ERR")
        addLog("Server: \(line)", isError: isErr, isOutgoing: false)

        if line.hasPrefix("OK audio_running") || line.hasPrefix("OK status") {
            if line.contains("audio_running=true") {
                self.audioRunning = true
            } else if line.contains("audio_running=false") {
                self.audioRunning = false
            }
        }
    }

    func sendRawCommand(_ cmd: String) {
        let trimmed = cmd.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isConnected else { return }
        addLog(trimmed, isOutgoing: true)
        
        let line = trimmed + "\n"
        guard let data = line.data(using: .utf8) else { return }
        connection?.send(content: data, completion: .contentProcessed { _ in })
    }

    // MARK: - Audio Controls

    func toggleAudio() {
        if audioRunning {
            sendRawCommand("stop")
            audioRunning = false
        } else {
            sendRawCommand("start")
            audioRunning = true
        }
    }

    func sendNoteOn(midi: UInt8, velocity: Double = 100.0) {
        activeNotes.insert(midi)
        sendRawCommand("note_on \(midi) \(Int(velocity))")
    }

    func sendNoteOff(midi: UInt8) {
        activeNotes.remove(midi)
        sendRawCommand("note_off \(midi)")
    }

    func isNoteActive(_ midi: UInt8) -> Bool {
        activeNotes.contains(midi)
    }

    func setNoteActive(midi: UInt8, active: Bool) {
        if active {
            activeNotes.insert(midi)
        } else {
            activeNotes.remove(midi)
        }
    }

    func setSF2Program(_ program: UInt8) {
        sf2Program = program
        sendRawCommand("program \(program)")
    }

    func refreshStatus() {
        sendRawCommand("status")
    }

    private func addLog(_ message: String, isError: Bool = false, isOutgoing: Bool = false) {
        let entry = LogEntry(message: message, isError: isError, isOutgoing: isOutgoing)
        logEntries.append(entry)
        if logEntries.count > 100 {
            logEntries.removeFirst(logEntries.count - 100)
        }
    }

    struct SF2Instrument: Identifiable, Hashable {
        let id: UInt8
        let name: String

        static let popularInstruments: [SF2Instrument] = [
            SF2Instrument(id: 0, name: "Piano (Grand Piano)"),
            SF2Instrument(id: 4, name: "Piano Elettrico (Rhodes)"),
            SF2Instrument(id: 16, name: "Organo Hammond (Drawbar)"),
            SF2Instrument(id: 19, name: "Organo di Chiesa"),
            SF2Instrument(id: 24, name: "Chitarra Acustica"),
            SF2Instrument(id: 30, name: "Chitarra Elettrica Distortion"),
            SF2Instrument(id: 33, name: "Basso Elettrico"),
            SF2Instrument(id: 40, name: "Violino Solo"),
            SF2Instrument(id: 48, name: "Archi (String Ensemble)"),
            SF2Instrument(id: 56, name: "Tromba (Trumpet)"),
            SF2Instrument(id: 65, name: "Sassofono (Alto Sax)"),
            SF2Instrument(id: 73, name: "Flauto Traverso"),
            SF2Instrument(id: 80, name: "Synth Lead (Square)"),
            SF2Instrument(id: 88, name: "Synth Pad (New Age)")
        ]
    }
}
