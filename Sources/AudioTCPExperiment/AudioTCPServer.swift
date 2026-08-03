import Foundation
import Network

/// Server TCP testuale, pensato per controllare una singola istanza AudioSynth.
/// Ogni comando e ogni risposta terminano con un carattere newline (`\n`).
final class AudioTCPServer {
    private final class Client {
        let connection: NWConnection
        var pendingData = Data()

        init(_ connection: NWConnection) { self.connection = connection }
    }

    private let audio: AudioSynth
    private let listener: NWListener
    private let queue = DispatchQueue(label: "AudioTCPExperiment.server")
    private var clients: [ObjectIdentifier: Client] = [:]

    init(audio: AudioSynth, port: UInt16 = 9876) throws {
        guard let port = NWEndpoint.Port(rawValue: port) else {
            throw ServerError.invalidPort
        }
        self.audio = audio
        self.listener = try NWListener(using: .tcp, on: port)
    }

    func start() {
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.stateUpdateHandler = { state in
            switch state {
            case .failed(let error): print("TCP server error: \(error)")
            case .ready: print("TCP server pronto sulla porta 9876")
            default: break
            }
        }
        listener.start(queue: queue)
    }

    func stop() {
        listener.cancel()
        for client in clients.values { client.connection.cancel() }
        clients.removeAll()
    }

    private func accept(_ connection: NWConnection) {
        let client = Client(connection)
        let id = ObjectIdentifier(client)
        clients[id] = client

        connection.stateUpdateHandler = { [weak self, weak client] state in
            guard let self, let client else { return }
            switch state {
            case .ready:
                self.reply("OK connected; type help", to: client)
                self.receiveNext(from: client)
            case .failed, .cancelled:
                self.clients.removeValue(forKey: ObjectIdentifier(client))
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func receiveNext(from client: Client) {
        client.connection.receive(minimumIncompleteLength: 1, maximumLength: 4_096) { [weak self, weak client] data, _, complete, error in
            guard let self, let client else { return }
            if let data { self.consume(data, from: client) }
            if error == nil && !complete { self.receiveNext(from: client) }
            else if complete || error != nil { client.connection.cancel() }
        }
    }

    private func consume(_ data: Data, from client: Client) {
        client.pendingData.append(data)
        while let end = client.pendingData.firstIndex(of: 10) { // ASCII LF
            let lineData = client.pendingData.prefix(upTo: end)
            client.pendingData.removeSubrange(...end)
            let line = String(decoding: lineData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            reply(execute(line), to: client)
        }
    }

    private func reply(_ text: String, to client: Client) {
        let data = Data((text + "\n").utf8)
        client.connection.send(content: data, completion: .contentProcessed { _ in })
    }

    private func execute(_ line: String) -> String {
        let words = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
        guard let first = words.first else { return "ERR empty command" }
        let command = first.lowercased()

        switch command {
        case "help":
            return "OK commands: start stop note_on <midi> <velocity> note_off <midi> [release] set <index> <value> get <index> frames host_time sample_time timing tmax input <count> output <count> status quit"

        case "start":
            do {
                try audio.startAudio()
                return "OK audio started"
            } catch { return "ERR cannot start audio: \(error)" }

        case "stop":
            audio.stopAudio()
            return "OK audio stopped"

        case "note_on":
            guard words.count == 3, let midi = UInt8(words[1]), let velocity = Double(words[2]) else {
                return "ERR usage: note_on <midi 0...127> <velocity 0...127>"
            }
            audio.enqueueNoteOn(frequency: midiNoteToFrequency(midi), note: midi, velocity: velocity)
            return String(format: "OK note_on midi=%d frequency=%.3f velocity=%.1f", midi, midiNoteToFrequency(midi), velocity)

        case "note_off":
            guard words.count == 2 || words.count == 3, let midi = UInt8(words[1]) else {
                return "ERR usage: note_off <midi 0...127> [release]"
            }
            let release: UInt32
            if words.count == 3 {
                guard let parsedRelease = UInt32(words[2]) else {
                    return "ERR release must be an unsigned integer"
                }
                release = parsedRelease
            } else {
                release = 0
            }
            audio.enqueueNoteOff(note: midi, sustainOff: release)
            return "OK note_off midi=\(midi)"

        case "set":
            guard words.count == 3, let index = UInt32(words[1]), let value = Double(words[2]) else {
                return "ERR usage: set <index 0...255> <value>"
            }
            audio.setValue1(index, value)
            return "OK parameter[\(min(index, 255))]=\(value)"

        case "get":
            guard words.count == 2, let index = UInt32(words[1]) else { return "ERR usage: get <index>" }
            return "OK parameter[\(min(index, 255))]=\(audio.getValue1(index))"

        case "frames": return "OK frames=\(audio.getFrames())"
        case "host_time": return "OK host_time=\(audio.getHostTime())"
        case "sample_time": return "OK sample_time=\(audio.getSampleTime())"
        case "tmax": return "OK tmax_seconds=\(audio.getTmax())"
        case "status": return "OK audio_running=\(audio.isRunning) clients=\(clients.count)"

        case "timing":
            let t = audio.getLastTiming()
            return "OK frames=\(t.frames) counter=\(t.frameCounter) duration=\(t.duration) delta=\(t.delta)"

        case "input", "output":
            guard words.count == 2, let count = Int(words[1]), count >= 0, count <= 256 else {
                return "ERR usage: \(command) <count 0...256>"
            }
            let values = command == "input" ? audio.getInputBuffer(count: count) : audio.getOutputBuffer(count: count)
            return "OK \(command)=" + values.map { String(format: "%.5f", $0) }.joined(separator: ",")

        case "quit", "exit":
            return "OK bye"
        default:
            return "ERR unknown command '\(first)'; type help"
        }
    }

    private enum ServerError: Error { case invalidPort }
}
