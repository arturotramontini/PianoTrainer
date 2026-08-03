import Foundation
import Network
import Darwin

/// Client TCP da riga di comando per AudioTCPExperiment.
final class AudioTCPClient {
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "AudioTCPClient.queue")
    private var pendingData = Data()
    private let lock = NSLock()
    private var responseHandler: ((String) -> Void)?
    private var isConnected = false
    private var currentOctaveOffset: Int = 0

    init(host: String = "127.0.0.1", port: UInt16 = 9876) {
        let endpoint = NWEndpoint.hostPort(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(rawValue: port)!
        )
        self.connection = NWConnection(to: endpoint, using: .tcp)
    }

    func start() {
        let semaphore = DispatchSemaphore(value: 0)

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                self?.lock.withLock { self?.isConnected = true }
                print("[\u{001B}[32m✓\u{001B}[0m] Connesso al server AudioTCP!")
                semaphore.signal()
            case .failed(let error):
                print("[\u{001B}[31m✗\u{001B}[0m] Errore di connessione: \(error)")
                semaphore.signal()
            case .cancelled:
                self?.lock.withLock { self?.isConnected = false }
            default:
                break
            }
        }

        connection.start(queue: queue)
        receiveLoop()

        _ = semaphore.wait(timeout: .now() + 5.0)
    }

    func stop() {
        connection.cancel()
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 4096) { [weak self] data, _, complete, error in
            guard let self = self else { return }
            if let data = data {
                self.consume(data)
            }
            if error == nil && !complete {
                self.receiveLoop()
            }
        }
    }

    private func consume(_ data: Data) {
        pendingData.append(data)
        while let end = pendingData.firstIndex(of: 10) { // ASCII LF '\n'
            let lineData = pendingData.prefix(upTo: end)
            pendingData.removeSubrange(...end)
            let response = String(decoding: lineData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !response.isEmpty else { continue }
            
            lock.withLock {
                if let handler = responseHandler {
                    handler(response)
                    responseHandler = nil
                } else {
                    print("\n\u{001B}[36mServer:\u{001B}[0m \(response)")
                }
            }
        }
    }

    @discardableResult
    func sendSync(_ command: String, timeout: TimeInterval = 2.0) -> String? {
        let sema = DispatchSemaphore(value: 0)
        var result: String? = nil

        lock.withLock {
            responseHandler = { resp in
                result = resp
                sema.signal()
            }
        }

        let line = command.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        guard let data = line.data(using: .utf8) else { return nil }

        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("[\u{001B}[31mErr\u{001B}[0m] Invio fallito: \(error)")
                sema.signal()
            }
        })

        _ = sema.wait(timeout: .now() + timeout)
        return result
    }

    func sendAsync(_ command: String) {
        let line = command.trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
        guard let data = line.data(using: .utf8) else { return }
        connection.send(content: data, completion: .contentProcessed { _ in })
    }

    // MARK: - Interactive Terminal & Piano Mode

    func runREPL() {
        printBanner()

        // Primo ping / help
        if let welcome = sendSync("status") {
            print("\u{001B}[33mStato iniziale:\u{001B}[0m \(welcome)")
        }

        var running = true
        while running {
            print("\u{001B}[1;34mAudioClient>\u{001B}[0m ", terminator: "")
            fflush(stdout)

            guard let line = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else {
                continue
            }

            let parts = line.split(separator: " ").map(String.init)
            let cmd = parts.first?.lowercased() ?? ""

            switch cmd {
            case "exit", "quit":
                _ = sendSync("quit")
                running = false
                print("Chiusura client TCP...")

            case "piano":
                startPianoMode()

            case "play":
                let notes = parts.dropFirst().compactMap { UInt8($0) }
                if notes.isEmpty {
                    print("Uso: play <midi_1> <midi_2> ... (es: play 60 62 64 65 67 69 71 72)")
                } else {
                    playSequence(notes)
                }

            case "arpeggio":
                playArpeggio()

            case "sweep":
                sweepModulation()

            default:
                if let response = sendSync(line) {
                    print("\u{001B}[36mServer:\u{001B}[0m \(response)")
                }
            }
        }
    }

    private func printBanner() {
        print("""
        \u{001B}[1;35m
        ====================================================
           AudioTCPClient - Client Interattivo Synthesizer
        ====================================================
        \u{001B}[0m
        Comandi disponibili:
          - \u{001B}[33mstart\u{001B}[0m / \u{001B}[33mstop\u{001B}[0m       : Avvia o arresta l'audio del synth
          - \u{001B}[33mnote_on\u{001B}[0m <midi> <vel> : Suona nota MIDI (es. note_on 60 100)
          - \u{001B}[33mnote_off\u{001B}[0m <midi>      : Spegne nota MIDI (es. note_off 60)
          - \u{001B}[33mset\u{001B}[0m <idx> <val>    : Modifica parametro synth (1=release, 2=mod_freq, 3=mod_depth, 4=vol)
          - \u{001B}[33mget\u{001B}[0m <idx>          : Legge parametro synth
          - \u{001B}[33mstatus\u{001B}[0m, \u{001B}[33mtiming\u{001B}[0m     : Diagnostica in tempo reale
          - \u{001B}[32mpiano\u{001B}[0m              : Avvia la tastiera MIDI dal vivo da tastiera PC!
          - \u{001B}[32mplay\u{001B}[0m <note...>     : Suona una sequenza di note MIDI
          - \u{001B}[32marpeggio\u{001B}[0m           : Esegue un arpeggio di prova
          - \u{001B}[32msweep\u{001B}[0m              : Effettua uno sweep dinamico della modulazione
          - \u{001B}[31mexit\u{001B}[0m / \u{001B}[31mquit\u{001B}[0m       : Chiude la connessione
        """)
    }

    private func playSequence(_ notes: [UInt8]) {
        _ = sendSync("start")
        print("Suono la sequenza: \(notes)...")
        for n in notes {
            _ = sendSync("note_on \(n) 100")
            Thread.sleep(forTimeInterval: 0.25)
            _ = sendSync("note_off \(n)")
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    private func playArpeggio() {
        _ = sendSync("start")
        print("Riproduzione arpeggio Do Maggiore...")
        let chord: [UInt8] = [60, 64, 67, 72, 76, 79, 84]
        for note in chord {
            _ = sendSync("note_on \(note) 90")
            Thread.sleep(forTimeInterval: 0.15)
        }
        Thread.sleep(forTimeInterval: 0.6)
        for note in chord.reversed() {
            _ = sendSync("note_off \(note)")
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    private func sweepModulation() {
        _ = sendSync("start")
        _ = sendSync("note_on 60 100")
        print("Sweep frequenza e profondità di modulazione...")
        for freq in stride(from: 2.0, through: 30.0, by: 1.5) {
            _ = sendSync("set 2 \(freq)")
            _ = sendSync("set 3 \(freq / 300.0)")
            Thread.sleep(forTimeInterval: 0.1)
        }
        _ = sendSync("set 2 7.83")
        _ = sendSync("set 3 0.02")
        _ = sendSync("note_off 60")
        print("Sweep completato.")
    }

    // MARK: - Keyboard Live Piano

    private func startPianoMode() {
        _ = sendSync("start")
        print("""
        \u{001B}[1;32m
        ====================================================
              MODALITÀ PIANOFORTE DA TASTIERA PC
        ====================================================
        \u{001B}[0m
        Mappa Tasti:
          Fila Infeiorie:  [z]=C3 [s]=C#3 [x]=D3 [d]=D#3 [c]=E3 [v]=F3 [g]=F#3 [b]=G3 [h]=G#3 [n]=A3 [j]=A#3 [m]=B3
          Fila Superiore: [q]=C4 [2]=C#4 [w]=D4 [3]=D#4 [e]=E4 [r]=F4 [5]=F#4 [t]=G4 [6]=G#4 [y]=A4 [7]=A#4 [u]=B4 [i]=C5

          [+] / [-] : Cambia ottava (\u{001B}[33mAttuale: \(currentOctaveOffset)\u{001B}[0m)
          [ESC] o [x / Ctrl+C] : Esci dalla modalità piano
        """)

        let keyMap: [Character: UInt8] = [
            "z": 48, "s": 49, "x": 50, "d": 51, "c": 52, "v": 53, "g": 54, "b": 55, "h": 56, "n": 57, "j": 58, "m": 59,
            "q": 60, "2": 61, "w": 62, "3": 63, "e": 64, "r": 65, "5": 66, "t": 67, "6": 68, "y": 69, "7": 70, "u": 71, "i": 72
        ]

        var originalTermios = termios()
        tcgetattr(STDIN_FILENO, &originalTermios)
        var rawTermios = originalTermios
        cfmakeraw(&rawTermios)
        tcsetattr(STDIN_FILENO, TCSANOW, &rawTermios)

        defer {
            tcsetattr(STDIN_FILENO, TCSANOW, &originalTermios)
        }

        var activeNotes = Set<UInt8>()

        while true {
            var charByte: UInt8 = 0
            let bytesRead = read(STDIN_FILENO, &charByte, 1)
            guard bytesRead == 1 else { break }

            if charByte == 27 || charByte == 3 { // ESC or Ctrl+C
                break
            }

            let char = Character(UnicodeScalar(charByte))
            if char == "+" {
                currentOctaveOffset = min(2, currentOctaveOffset + 1)
                print("\r\u{001B}[K\u{001B}[33mOttava offset: \(currentOctaveOffset)\u{001B}[0m", terminator: "")
                fflush(stdout)
                continue
            } else if char == "-" {
                currentOctaveOffset = max(-2, currentOctaveOffset - 1)
                print("\r\u{001B}[K\u{001B}[33mOttava offset: \(currentOctaveOffset)\u{001B}[0m", terminator: "")
                fflush(stdout)
                continue
            } else if char == " " {
                // All notes off
                for n in activeNotes {
                    sendAsync("note_off \(n)")
                }
                activeNotes.removeAll()
                print("\r\u{001B}[K\u{001B}[31m[Mute All]\u{001B}[0m", terminator: "")
                fflush(stdout)
                continue
            }

            if let baseMidi = keyMap[char] {
                let midi = UInt8(clamping: Int(baseMidi) + (currentOctaveOffset * 12))
                sendAsync("note_on \(midi) 100")
                activeNotes.insert(midi)
                print("\r\u{001B}[K\u{001B}[32m♪ Note On: \(midi)\u{001B}[0m", terminator: "")
                fflush(stdout)

                // Spegne la nota dopo breve intervallo se il tasto non viene tenuto
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.sendAsync("note_off \(midi)")
                    activeNotes.remove(midi)
                }
            }
        }

        for n in activeNotes {
            sendAsync("note_off \(n)")
        }

        tcsetattr(STDIN_FILENO, TCSANOW, &originalTermios)
        print("\nUscita dalla modalità piano.\n")
    }
}

// Entry point
let args = CommandLine.arguments
var host = "127.0.0.1"
var port: UInt16 = 9876

if args.count > 1 { host = args[1] }
if args.count > 2, let p = UInt16(args[2]) { port = p }

print("Avvio AudioTCPClient -> \(host):\(port)")
let client = AudioTCPClient(host: host, port: port)
client.start()
client.runREPL()
client.stop()
