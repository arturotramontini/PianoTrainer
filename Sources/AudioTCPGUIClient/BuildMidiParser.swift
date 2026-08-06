import Foundation

public struct ScoreStep: Identifiable, Equatable {
    public let id = UUID()
    public let bar: Int
    public let stepIndex: Int
    public let track: Int
    public let startPosToken: String
    public let durationToken: String
    public let targetNotes: Set<UInt8>
    public let durationTicks: Int
    public let displayText: String
    public let phoneticText: String

    public init(bar: Int, stepIndex: Int, track: Int, startPosToken: String, durationToken: String, targetNotes: Set<UInt8>, durationTicks: Int, displayText: String, phoneticText: String) {
        self.bar = bar
        self.stepIndex = stepIndex
        self.track = track
        self.startPosToken = startPosToken
        self.durationToken = durationToken
        self.targetNotes = targetNotes
        self.durationTicks = durationTicks
        self.displayText = displayText
        self.phoneticText = phoneticText
    }
}

public struct ScoreParseResult {
    public let title: String
    public let steps: [ScoreStep]
    public let bpm: Int
    public let totalBars: Int
}

public struct BuildMidiParser {
    private static let noteIndexMap: [String: Int] = [
        "do": 0, "do#": 1, "dod": 1,
        "re": 2, "re#": 3, "red": 3, "reb": 1,
        "mi": 4, "mib": 3,
        "fa": 5, "fa#": 6, "fad": 6,
        "sol": 7, "sol#": 8, "sold": 8, "solb": 6,
        "so": 7, "so#": 8,
        "la": 9, "la#": 10, "lad": 10, "lab": 8,
        "si": 11, "sib": 10,

        "c": 0, "c#": 1, "cd": 1,
        "d": 2, "d#": 3, "dd": 3, "db": 1,
        "e": 4, "eb": 3,
        "f": 5, "f#": 6, "fd": 6,
        "g": 7, "g#": 8, "gd": 8, "gb": 6,
        "a": 9, "a#": 10, "ad": 10, "ab": 8,
        "b": 11, "bb": 10
    ]

    private static let durationSymbolMap: [String: Double] = [
        "w": 1.0,       // Intero (Semibreve)
        "h": 0.5,       // Metà (Minima)
        "q": 0.25,      // Quarto (Semiminima)
        "o": 0.125,     // Ottavo (Croma)
        "s": 0.0625,    // Sedicesimo (Semicroma)
        "t": 0.03125,   // Trentaduesimo (Biscroma)
        "x": 0.015625,  // Sessantaquattresimo
        "y": 0.0078125
    ]

    /// Analizza il codice sorgente testuale BUILDMIDI e genera la sequenza di passaggi interattivi ScoreStep
    public static func parse(text: String, title: String = "Spartito BUILDMIDI") -> ScoreParseResult {
        let lines = text.components(separatedBy: .newlines)

        var steps: [ScoreStep] = []
        var currentBar = 1
        var currentTrack = 1
        var currentBPM = 120
        var stepCount = 0
        var prevDurationTicks = 480 // 1/4 quarter note default

        let ticksPerQuarter = 480
        let ticksPerBar = ticksPerQuarter * 4

        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix("//") {
                continue
            }

            let tokens = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            if tokens.isEmpty { continue }

            let cmd = tokens[0].lowercased()

            // Gestione comandi di controllo
            if cmd == "battuta" || cmd == "bar" {
                if tokens.count > 1 {
                    if tokens[1] == "+" {
                        currentBar += 1
                    } else if let b = Int(tokens[1]) {
                        currentBar = b
                    }
                }
                continue
            }

            if cmd == "traccia" || cmd == "track" {
                if tokens.count > 1, let t = Int(tokens[1]) {
                    currentTrack = t
                }
                continue
            }

            if cmd == "bpm" {
                if tokens.count > 1, let b = Int(tokens[1]) {
                    currentBPM = b
                }
                continue
            }

            if cmd == "comment" || cmd == "com" || cmd == "commento" || cmd == "direct" || cmd == "canale" || cmd == "channel" || cmd == "vel" || cmd == "velocity" || cmd == "delayarp" {
                continue
            }

            // Parsing righe note: <start> <duration> <note> <octave> [<note> <octave> ...]
            if tokens.count >= 3 {
                let startPosToken = tokens[0]
                let durToken = tokens[1].lowercased()

                // Calcola durTicks
                var durTicks = prevDurationTicks
                if let symbolValue = durationSymbolMap[durToken] {
                    durTicks = Int(symbolValue * Double(ticksPerBar))
                } else if let doubleValue = Double(durToken) {
                    durTicks = Int(doubleValue * Double(ticksPerBar))
                }

                if durTicks > 0 {
                    prevDurationTicks = durTicks
                }

                // Estrai le note target (coppie nota + ottava)
                var targetMIDI = Set<UInt8>()
                var noteNames: [String] = []

                var i = 2
                while i < tokens.count {
                    let noteStr = tokens[i].lowercased()
                    if noteStr == "=" || noteStr == "-" {
                        i += 1
                        continue
                    }

                    if noteStr.hasPrefix("n") {
                        // Notazione NOI (es. n40 -> 60)
                        let sub = String(noteStr.dropFirst())
                        if let midiVal = UInt8(sub) {
                            if midiVal >= 21 && midiVal <= 108 {
                                targetMIDI.insert(midiVal)
                                noteNames.append(NoteNameUtility.italianName(for: midiVal))
                            }
                        } else if sub.count >= 2, let octDigit = Int(String(sub.prefix(1))), let pcDigit = Int(String(sub.suffix(1))) {
                            let midiVal = UInt8((octDigit + 1) * 12 + pcDigit)
                            if midiVal >= 21 && midiVal <= 108 {
                                targetMIDI.insert(midiVal)
                                noteNames.append(NoteNameUtility.italianName(for: midiVal))
                            }
                        }
                        i += 1
                        continue
                    }

                    if let pc = noteIndexMap[noteStr] {
                        var octave = 4
                        if i + 1 < tokens.count, let octVal = Int(tokens[i + 1]) {
                            octave = octVal
                            i += 1
                        }
                        let midiVal = UInt8((octave + 1) * 12 + pc)
                        if midiVal >= 21 && midiVal <= 108 {
                            targetMIDI.insert(midiVal)
                            noteNames.append(NoteNameUtility.italianName(for: midiVal))
                        }
                    }
                    i += 1
                }

                if !targetMIDI.isEmpty {
                    stepCount += 1
                    let displayText = "Traccia \(currentTrack) - Battuta \(currentBar) [Pos: \(startPosToken)] - " + noteNames.joined(separator: ", ")
                    let phoneticText = noteNames.joined(separator: ", ")
                    
                    let step = ScoreStep(
                        bar: currentBar,
                        stepIndex: stepCount,
                        track: currentTrack,
                        startPosToken: startPosToken,
                        durationToken: durToken,
                        targetNotes: targetMIDI,
                        durationTicks: durTicks,
                        displayText: displayText,
                        phoneticText: phoneticText
                    )
                    steps.append(step)
                }
            }
        }

        let totalBars = steps.map { $0.bar }.max() ?? currentBar
        return ScoreParseResult(title: title, steps: steps, bpm: currentBPM, totalBars: totalBars)
    }
}
