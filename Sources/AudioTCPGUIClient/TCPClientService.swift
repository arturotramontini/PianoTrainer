import Foundation
import Network
import SwiftUI
import Combine

/// Servizio di rete TCP per il client SwiftUI AudioTCP.
@MainActor
final class TCPClientService: ObservableObject {
    @Published var isConnected: Bool = false
    @Published var isConnecting: Bool = false
    @Published var host: String = "127.0.0.1"
    @Published var port: String = "9876"
    @Published var audioRunning: Bool = false
    @Published var clientCount: Int = 0

    // Parametri synth (indici 1..5)
    @Published var paramSustainRelease: Double = 1.5   // Param 1
    @Published var paramModFreq: Double = 7.83         // Param 2
    @Published var paramModDepth: Double = 0.02        // Param 3
    @Published var paramVolume: Double = 20.0          // Param 4

    // Diagnostics & Buffers
    @Published var outputSamples: [Float] = Array(repeating: 0.0, count: 128)
    @Published var inputSamples: [Float] = Array(repeating: 0.0, count: 128)
    @Published var timingInfo: String = "N/A"
    @Published var tmaxInfo: String = "0.0 ms"
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
    private var timer: Timer?
    private var activeNotes = Set<UInt8>()

    init() {
        // Auto-connect su avvio se desiderato
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
                    self.addLog("Connesso al server AudioTCP!", isError: false)
                    self.startPolling()
                    self.refreshStatus()
                case .failed(let error):
                    self.isConnected = false
                    self.isConnecting = false
                    self.addLog("Errore connessione: \(error.localizedDescription)", isError: true)
                    self.stopPolling()
                case .cancelled:
                    self.isConnected = false
                    self.isConnecting = false
                    self.addLog("Disconnesso dal server.", isError: false)
                    self.stopPolling()
                default:
                    break
                }
            }
        }

        conn.start(queue: networkQueue)
        receiveLoop(conn: conn)
    }

    func disconnect() {
        stopPolling()
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

        if line.hasPrefix("OK status") || line.hasPrefix("OK audio_running") {
            // OK audio_running=true clients=1
            if line.contains("audio_running=true") {
                self.audioRunning = true
            } else if line.contains("audio_running=false") {
                self.audioRunning = false
            }
        } else if line.hasPrefix("OK output=") {
            let sampleStr = line.replacingOccurrences(of: "OK output=", with: "")
            let vals = sampleStr.split(separator: ",").compactMap { Float($0) }
            if !vals.isEmpty {
                self.outputSamples = vals
            }
        } else if line.hasPrefix("OK timing") {
            self.timingInfo = line.replacingOccurrences(of: "OK ", with: "")
        } else if line.hasPrefix("OK tmax_seconds=") {
            if let sec = Double(line.replacingOccurrences(of: "OK tmax_seconds=", with: "")) {
                self.tmaxInfo = String(format: "%.2f ms", sec * 1000.0)
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

    // MARK: - Core Audio Controls

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

    func setParam(_ index: Int, value: Double) {
        sendRawCommand("set \(index) \(String(format: "%.4f", value))")
    }

    func applyPreset(_ preset: Preset) {
        paramSustainRelease = preset.sustain
        paramModFreq = preset.modFreq
        paramModDepth = preset.modDepth
        paramVolume = preset.volume

        setParam(1, value: preset.sustain)
        setParam(2, value: preset.modFreq)
        setParam(3, value: preset.modDepth)
        setParam(4, value: preset.volume)
    }

    func refreshStatus() {
        sendRawCommand("status")
        sendRawCommand("timing")
        sendRawCommand("tmax")
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, self.isConnected else { return }
                self.sendRawCommand("output 128")
            }
        }
    }

    private func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    private func addLog(_ message: String, isError: Bool = false, isOutgoing: Bool = false) {
        let entry = LogEntry(message: message, isError: isError, isOutgoing: isOutgoing)
        logEntries.append(entry)
        if logEntries.count > 100 {
            logEntries.removeFirst(logEntries.count - 100)
        }
    }

    struct Preset: Identifiable, Hashable {
        let id = UUID()
        let name: String
        let sustain: Double
        let modFreq: Double
        let modDepth: Double
        let volume: Double

        static let defaultPresets: [Preset] = [
            Preset(name: "Default (Standard)", sustain: 1.5, modFreq: 7.83, modDepth: 0.02, volume: 20.0),
            Preset(name: "Long Release (Ambient)", sustain: 0.3, modFreq: 4.0, modDepth: 0.04, volume: 22.0),
            Preset(name: "Fast Pluck (Short)", sustain: 5.0, modFreq: 12.0, modDepth: 0.01, volume: 25.0),
            Preset(name: "Vibrato Warm", sustain: 1.2, modFreq: 6.0, modDepth: 0.08, volume: 18.0),
            Preset(name: "Tremolo Extreme", sustain: 1.0, modFreq: 18.0, modDepth: 0.15, volume: 16.0)
        ]
    }
}
