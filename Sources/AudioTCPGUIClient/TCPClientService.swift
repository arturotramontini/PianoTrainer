import Foundation
import Network
import SwiftUI
import Combine

/// Servizio di rete TCP per il client SwiftUI Piano Trainer Standalone.
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

    public enum TrainerMode: String, CaseIterable, Identifiable {
        case singleNotes = "Note Singole"
        case chords = "Accordi & Rivolti"

        public var id: String { rawValue }
    }

    // Piano Trainer & Speech Assistant
    @Published var trainerMode: TrainerMode = .singleNotes {
        didSet {
            updateDisplayedNoteNames()
        }
    }
    @Published var speakPressedNotes: Bool = false // Checkbox per la lettura vocale della nota premuta
    @Published var showKeyHints: Bool = false     // Checkbox per mostrare i rettangolini di suggerimento sui tasti target
    @Published var showOctaveGeometryHints: Bool = false // Checkbox per mostrare la geometria dell'accordo su tutte le ottave
    @Published var useItalianNotation: Bool = false { // Notazione Inglese (C4) vs Italiana (Do4)
        didSet {
            updateDisplayedNoteNames()
        }
    }

    // Modalità Note Singole
    @Published var targetNoteMIDI: UInt8? = nil
    @Published var targetNoteText: String = "Premere un tasto per > 1.4s per iniziare"
    @Published var targetPreferFlat: Bool = false

    public enum CyanDotMode: String, CaseIterable, Identifiable {
        case chordNotes = "Note dell'Accordo"
        case keyScaleNotes = "Scala della Tonalità"

        public var id: String { rawValue }
    }

    // Modalità Accordi & Rivolti
    @Published var targetChord: ChordDefinition? = nil
    @Published var targetChordText: String = "Premere 'Nuovo Accordo' per iniziare"
    @Published var isChordMatched: Bool = false
    @Published var allowedChordQualities: Set<ChordQuality> = [.major, .minor]
    @Published var selectedInversionFilter: InversionFilter = .all {
        didSet {
            updateCurrentChordInversion()
        }
    }
    @Published var cyanDotMode: CyanDotMode = .chordNotes
    @Published var selectedScaleMode: MusicalScaleMode = .major

    /// Restituisce la Tonalità/Modalità e le alterazioni in chiave per l'accordo corrente
    public var currentKeySignature: KeySignatureInfo? {
        guard let chord = targetChord else { return nil }
        return KeySignatureUtility.forChord(chord, scaleMode: selectedScaleMode)
    }

    @Published var lastPlayedNoteMIDI: UInt8? = nil
    @Published var lastPlayedNoteText: String = "-"
    @Published var lastPlayedIsTargetMatched: Bool = false
    @Published var lastPlayedPreferFlat: Bool = false

    // Dinamica di Tocco (Velocity) & Articolazione (Duration)
    @Published var lastVelocity: Int = 0
    @Published var lastVelocityText: String = "-"
    @Published var lastDurationSeconds: Double = 0.0
    @Published var lastDurationText: String = "-"

    @Published var activeNotes = Set<UInt8>()

    private let speechService = SpeechService()
    private var pressStartTimes: [UInt8: Date] = [:]

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

    // MARK: - Audio & Note Controls

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
        setNoteActive(midi: midi, active: true, velocity: velocity)
        sendRawCommand("note_on \(midi) \(Int(velocity))")
    }

    func sendNoteOff(midi: UInt8) {
        setNoteActive(midi: midi, active: false)
        sendRawCommand("note_off \(midi)")
    }

    func isNoteActive(_ midi: UInt8) -> Bool {
        activeNotes.contains(midi)
    }

    func setNoteActive(midi: UInt8, active: Bool, velocity: Double = 100.0) {
        if active {
            activeNotes.insert(midi)
            pressStartTimes[midi] = Date()

            // Controlla se il tasto premuto corrisponde alla nota proposta dal Mac (MATCH 🟢)
            let isMatched = (midi == targetNoteMIDI)
            lastPlayedIsTargetMatched = isMatched
            lastPlayedNoteMIDI = midi

            // Scelta dell'alterazione (Diesis vs Bemolle)
            let preferFlat: Bool
            if isMatched {
                preferFlat = targetPreferFlat // Usa l'alterazione esatta richiesta
            } else if NoteNameUtility.isBlackKey(midi: midi) {
                preferFlat = Bool.random() // Se non corrisponde, alterna casualmente Diesis e Bemolle per i tasti neri
            } else {
                preferFlat = false
            }
            lastPlayedPreferFlat = preferFlat

            // Aggiorna l'ultima nota suonata (visualizzata in modo permanente)
            lastPlayedNoteText = useItalianNotation ? NoteNameUtility.italianName(for: midi, preferFlat: preferFlat) : NoteNameUtility.englishName(for: midi, preferFlat: preferFlat)

            // Dinamica di Tocco (Velocity)
            let vel = Int(velocity)
            lastVelocity = vel
            if vel <= 40 {
                lastVelocityText = "\(vel) / 127 (p - piano)"
            } else if vel <= 85 {
                lastVelocityText = "\(vel) / 127 (mf - mezzo forte)"
            } else {
                lastVelocityText = "\(vel) / 127 (f - forte)"
            }

            // Pronuncia la nota (se la checkbox è attiva o se ha indovinato la nota proposta)
            if (speakPressedNotes || isMatched) && trainerMode == .singleNotes {
                speechService.speakNote(midi, preferFlat: preferFlat, isItalian: useItalianNotation)
            }
        } else {
            activeNotes.remove(midi)

            // Calcola la durata di pressione (in millisecondi / secondi)
            if let startTime = pressStartTimes.removeValue(forKey: midi) {
                let duration = Date().timeIntervalSince(startTime)
                lastDurationSeconds = duration
                
                if duration < 0.2 {
                    lastDurationText = String(format: "%.2f s (Staccato ⚡️)", duration)
                } else if duration <= 1.0 {
                    lastDurationText = String(format: "%.2f s (Tenuto 🎼)", duration)
                } else {
                    lastDurationText = String(format: "%.2f s (Sostenuto 🎹)", duration)
                }

                // Requisito Tastissimi Hardware di Controllo Senza Mouse (A0, Bb0, B0):
                // - A0 (MIDI 21): Breve pressione -> Nuovo accordo / Nuova nota casuale
                // - Bb0 (MIDI 22): Breve pressione -> Trasponi l'accordo attuale di -1 semitone (1 semitono sotto)
                // - B0 (MIDI 23): Breve pressione -> Trasponi l'accordo attuale di +1 semitone (1 semitono sopra)
                if duration < 1.0 {
                    if midi == 21 {
                        if trainerMode == .chords {
                            generateNewTargetChord()
                        } else {
                            generateNewTargetNote()
                        }
                    } else if midi == 22 && trainerMode == .chords {
                        transposeTargetChord(by: -1)
                    } else if midi == 23 && trainerMode == .chords {
                        transposeTargetChord(by: 1)
                    }
                } else if duration >= 1.4 && trainerMode == .singleNotes {
                    // Requisito #1 (Modalità Note Singole): Se qualsiasi tasto è tenuto premuto per >1.4s, al rilascio propone una nuova nota
                    generateNewTargetNote()
                }
            }
        }

        // MODALITÀ ACCORDI: Considera "accordo corretto" SOLO se sono premuti SOLTANTO i tasti richiesti (uguaglianza esatta)
        if trainerMode == .chords, let chord = targetChord {
            let requiredNotes = chord.notesMIDI
            let isExactMatch = (activeNotes == requiredNotes)

            if isExactMatch {
                if !isChordMatched {
                    isChordMatched = true
                    speechService.speakChordSuccess(chord, isItalian: useItalianNotation)
                    addLog("Piano Trainer: Accordo Indovinato -> \(targetChordText)", isError: false)
                }
                // Quando i tasti premuti sono esattamente quelli dell'accordo, mostra il nome della nota FONDAMENTALE dell'accordo
                let rootName = useItalianNotation ?
                    NoteNameUtility.italianName(for: chord.rootMIDI, preferFlat: chord.preferFlat) :
                    NoteNameUtility.englishName(for: chord.rootMIDI, preferFlat: chord.preferFlat)
                lastPlayedNoteText = "\(rootName) (Fondamentale)"
            } else {
                isChordMatched = false

                // Se non è l'accordo corretto:
                // - Se c'è SOLTANTO un tasto premuto, mostra quella singola nota in modalità normale
                // - Se ce ne sono 2 o più (o 0), la dicitura dell'accordo giusto non appare e il testo mostra "-"
                if activeNotes.count == 1, let singleMIDI = activeNotes.first {
                    let preferFlat = NoteNameUtility.isBlackKey(midi: singleMIDI) ? Bool.random() : false
                    lastPlayedNoteText = useItalianNotation ?
                        NoteNameUtility.italianName(for: singleMIDI, preferFlat: preferFlat) :
                        NoteNameUtility.englishName(for: singleMIDI, preferFlat: preferFlat)
                } else if activeNotes.count > 1 {
                    lastPlayedNoteText = "-"
                }
            }
        }
    }

    /// Aggiorna i testi visualizzati quando si passa da notazione inglese ad italiana o viceversa.
    func updateDisplayedNoteNames() {
        if let target = targetNoteMIDI {
            targetNoteText = useItalianNotation ? NoteNameUtility.italianName(for: target, preferFlat: targetPreferFlat) : NoteNameUtility.englishName(for: target, preferFlat: targetPreferFlat)
        }
        if let last = lastPlayedNoteMIDI {
            lastPlayedNoteText = useItalianNotation ? NoteNameUtility.italianName(for: last, preferFlat: lastPlayedPreferFlat) : NoteNameUtility.englishName(for: last, preferFlat: lastPlayedPreferFlat)
        }
        if let chord = targetChord {
            targetChordText = chord.displayName(isItalian: useItalianNotation)
        }
    }

    /// Genera e pronuncia una nuova nota casuale tra gli 88 tasti del pianoforte (21 A0 ... 108 C8).
    /// Se la nota è un tasto nero, sceglie casualmente se proporla come Diesis (♯) o Bemolle (♭).
    func generateNewTargetNote() {
        let newTarget = NoteNameUtility.randomPianoMIDI()
        self.targetNoteMIDI = newTarget
        self.targetPreferFlat = NoteNameUtility.isBlackKey(midi: newTarget) ? Bool.random() : false
        self.targetNoteText = useItalianNotation ? NoteNameUtility.italianName(for: newTarget, preferFlat: targetPreferFlat) : NoteNameUtility.englishName(for: newTarget, preferFlat: targetPreferFlat)
        self.speechService.speakProposedNote(newTarget, preferFlat: targetPreferFlat, isItalian: useItalianNotation)
        addLog("Piano Trainer: Nuova nota proposta -> \(targetNoteText)", isError: false)
    }

    /// Genera e pronuncia un nuovo accordo casuale con il suo rivolto
    func generateNewTargetChord() {
        let qualities = allowedChordQualities.isEmpty ? [.major, .minor] : Array(allowedChordQualities)
        let newChord = ChordDefinition.random(allowedQualities: qualities, allowedInversion: selectedInversionFilter.targetInversion, minMIDI: 48, maxMIDI: 72)
        self.targetChord = newChord
        self.isChordMatched = false
        self.targetChordText = newChord.displayName(isItalian: useItalianNotation)
        self.speechService.speakProposedChord(newChord, isItalian: useItalianNotation)
        addLog("Piano Trainer: Nuovo accordo proposto -> \(targetChordText)", isError: false)
    }

    /// Traspone l'accordo proposto corrente di N semitoni in più (+1) o in meno (-1)
    func transposeTargetChord(by semitones: Int) {
        guard trainerMode == .chords, let chord = targetChord else { return }
        let newRootInt = Int(chord.rootMIDI) + semitones
        let clampedRoot = UInt8(max(36, min(84, newRootInt)))

        let preferFlat = NoteNameUtility.isBlackKey(midi: clampedRoot) ? (semitones < 0 ? true : false) : chord.preferFlat

        let newChord = ChordDefinition(
            rootMIDI: clampedRoot,
            quality: chord.quality,
            inversion: chord.inversion,
            preferFlat: preferFlat
        )
        self.targetChord = newChord
        self.isChordMatched = false
        self.targetChordText = newChord.displayName(isItalian: useItalianNotation)
        self.speechService.speakProposedChord(newChord, isItalian: useItalianNotation)
        addLog("Piano Trainer: Accordo Trasposto (\(semitones > 0 ? "+1" : "-1") semitono) -> \(targetChordText)", isError: false)
    }

    /// Aggiorna il rivolto dell'accordo proposto corrente in base al nuovo filtro selettore
    func updateCurrentChordInversion() {
        guard trainerMode == .chords, let chord = targetChord else { return }
        if let newInversion = selectedInversionFilter.targetInversion {
            let updatedChord = ChordDefinition(
                rootMIDI: chord.rootMIDI,
                quality: chord.quality,
                inversion: newInversion,
                preferFlat: chord.preferFlat
            )
            self.targetChord = updatedChord
            self.isChordMatched = false
            self.targetChordText = updatedChord.displayName(isItalian: useItalianNotation)
            self.speechService.speakProposedChord(updatedChord, isItalian: useItalianNotation)
            addLog("Piano Trainer: Rivolto aggiornato -> \(targetChordText)", isError: false)
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
