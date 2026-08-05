import Foundation

public enum MusicalScaleMode: String, CaseIterable, Identifiable {
    case major = "Maggiore"
    case minorNatural = "Minore Naturale"
    case minorHarmonic = "Minore Armonica"
    case minorMelodic = "Minore Melodica"
    case pentatonicMajor = "Pentatonica Magg."
    case pentatonicMinor = "Pentatonica Min."
    case blues = "Scala Blues"
    case dorianJazz = "Jazz (Dorica)"

    public var id: String { rawValue }

    public var englishName: String {
        switch self {
        case .major: return "Major"
        case .minorNatural: return "Natural Minor"
        case .minorHarmonic: return "Harmonic Minor"
        case .minorMelodic: return "Melodic Minor"
        case .pentatonicMajor: return "Major Pentatonic"
        case .pentatonicMinor: return "Minor Pentatonic"
        case .blues: return "Blues Scale"
        case .dorianJazz: return "Jazz (Dorian)"
        }
    }

    public var semitoneIntervals: [UInt8] {
        switch self {
        case .major:            return [0, 2, 4, 5, 7, 9, 11]
        case .minorNatural:     return [0, 2, 3, 5, 7, 8, 10]
        case .minorHarmonic:    return [0, 2, 3, 5, 7, 8, 11]
        case .minorMelodic:     return [0, 2, 3, 5, 7, 9, 11]
        case .pentatonicMajor:  return [0, 2, 4, 7, 9]
        case .pentatonicMinor:  return [0, 3, 5, 7, 10]
        case .blues:            return [0, 3, 5, 6, 7, 10]
        case .dorianJazz:       return [0, 2, 3, 5, 7, 9, 10]
        }
    }

    public var defaultChordQuality: ChordQuality {
        switch self {
        case .major, .pentatonicMajor:
            return .major
        case .minorNatural, .minorHarmonic, .minorMelodic, .pentatonicMinor, .blues, .dorianJazz:
            return .minor
        }
    }
}

public struct KeySignatureInfo: Equatable {
    public let keyNameItalian: String
    public let keyNameEnglish: String
    public let accidentalsTextItalian: String
    public let accidentalsTextEnglish: String
    public let scalePitchClasses: Set<UInt8> // I toni (modulo 12) della scala/modalità
    public let scaleNotesTextItalian: String
    public let scaleNotesTextEnglish: String

    public func displayName(isItalian: Bool) -> String {
        isItalian ? keyNameItalian : keyNameEnglish
    }

    public func displayAccidentals(isItalian: Bool) -> String {
        isItalian ? accidentalsTextItalian : accidentalsTextEnglish
    }

    public func displayScaleNotes(isItalian: Bool) -> String {
        isItalian ? scaleNotesTextItalian : scaleNotesTextEnglish
    }
}

public struct ManualChordParseResult {
    public let midiNote: UInt8
    public let scaleMode: MusicalScaleMode
    public let chordQuality: ChordQuality
    public let preferFlat: Bool
}

public struct KeySignatureUtility {
    /// Ricava le informazioni sulla Tonalità/Modalità e sulle alterazioni in chiave relative ad un accordo e scala scelta
    public static func forChord(_ chord: ChordDefinition, scaleMode: MusicalScaleMode = .major) -> KeySignatureInfo {
        let rootPC = chord.rootMIDI % 12
        let intervals = scaleMode.semitoneIntervals
        
        let scalePitchClasses = Set(intervals.map { (rootPC + $0) % 12 })

        // Genera i nomi delle note della scala
        let noteNamesIt = intervals.map { NoteNameUtility.italianName(for: chord.rootMIDI + $0, preferFlat: chord.preferFlat) }
        let noteNamesEn = intervals.map { NoteNameUtility.englishName(for: chord.rootMIDI + $0, preferFlat: chord.preferFlat) }

        let scaleTextIt = noteNamesIt.joined(separator: ", ")
        let scaleTextEn = noteNamesEn.joined(separator: ", ")

        let rootNameIt = NoteNameUtility.italianName(for: chord.rootMIDI, preferFlat: chord.preferFlat)
        let rootNameEn = NoteNameUtility.englishName(for: chord.rootMIDI, preferFlat: chord.preferFlat)

        let keyNameIt = "\(rootNameIt) \(scaleMode.rawValue)"
        let keyNameEn = "\(rootNameEn) \(scaleMode.englishName)"

        // Alterazioni in chiave ufficiali del circolo delle quinte (basate sulla tonalità maggiore relativa)
        let isMinor = (scaleMode != .major && scaleMode != .pentatonicMajor)
        let relativeMajorRoot = isMinor ? (rootPC + 3) % 12 : rootPC

        let keyData: [UInt8: (accIt: String, accEn: String)] = [
            0:  ("Nessuna alterazione", "No accidentals"),
            7:  ("1 Diesis: Fa♯", "1 Sharp: F♯"),
            2:  ("2 Diesis: Fa♯, Do♯", "2 Sharps: F♯, C♯"),
            9:  ("3 Diesis: Fa♯, Do♯, Sol♯", "3 Sharps: F♯, C♯, G♯"),
            4:  ("4 Diesis: Fa♯, Do♯, Sol♯, Re♯", "4 Sharps: F♯, C♯, G♯, D♯"),
            11: ("5 Diesis: Fa♯, Do♯, Sol♯, Re♯, La♯", "5 Sharps: F♯, C♯, G♯, D♯, A♯"),
            6:  chord.preferFlat ?
                    ("6 Bemolli: Si♭, Mi♭, La♭, Re♭, Sol♭, Do♭", "6 Flats: B♭, E♭, A♭, D♭, G♭, C♭") :
                    ("6 Diesis: Fa♯, Do♯, Sol♯, Re♯, La♯, Mi♯", "6 Sharps: F♯, C♯, G♯, D♯, A♯, E♯"),
            5:  ("1 Bemolle: Si♭", "1 Flat: B♭"),
            10: ("2 Bemolli: Si♭, Mi♭", "2 Flats: B♭, E♭"),
            3:  ("3 Bemolli: Si♭, Mi♭, La♭", "3 Flats: B♭, E♭, A♭"),
            8:  ("4 Bemolli: Si♭, Mi♭, La♭, Re♭", "4 Flats: B♭, E♭, A♭, D♭"),
            1:  ("5 Bemolli: Si♭, Mi♭, La♭, Re♭, Sol♭", "5 Flats: B♭, E♭, A♭, D♭, G♭")
        ]

        let accData = keyData[relativeMajorRoot] ?? ("Nessuna alterazione", "No accidentals")

        return KeySignatureInfo(
            keyNameItalian: keyNameIt,
            keyNameEnglish: keyNameEn,
            accidentalsTextItalian: accData.accIt,
            accidentalsTextEnglish: accData.accEn,
            scalePitchClasses: scalePitchClasses,
            scaleNotesTextItalian: scaleTextIt,
            scaleNotesTextEnglish: scaleTextEn
        )
    }

    /// Analizza e converte una stringa di testo libera (es: "Do d 4 3", "C#4", "Mi b 3 7") in un accordo e modalità esatta
    public static func parseManualInput(_ rawInput: String) -> ManualChordParseResult? {
        let cleaned = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .lowercased()

        if cleaned.isEmpty { return nil }

        let tokens = cleaned.components(separatedBy: .whitespaces).filter { !$0.isEmpty }

        var basePC: Int? = nil
        var accidental: Int = 0
        var octave: Int = 4
        var modeIndex: Int = 1
        var preferFlat: Bool = false

        // Tabella note
        let noteMap: [String: Int] = [
            "c": 0, "do": 0,
            "d": 2, "re": 2,
            "e": 4, "mi": 4,
            "f": 5, "fa": 5,
            "g": 7, "sol": 7,
            "a": 9, "la": 9,
            "b": 11, "si": 11
        ]

        let remainingStr = cleaned

        // Cerca prima il nome della nota nel testo
        for (name, pc) in noteMap {
            if remainingStr.hasPrefix(name) || tokens.contains(name) {
                basePC = pc
                break
            }
        }

        // Se non troviamo una nota con prefisso semplice, cerchiamo di separare cifre e lettere
        if basePC == nil {
            for token in tokens {
                for (name, pc) in noteMap {
                    if token.starts(with: name) {
                        basePC = pc
                        break
                    }
                }
                if basePC != nil { break }
            }
        }

        guard let foundPC = basePC else { return nil }

        // Cerca alterazioni: 'd', '#', 'diesis' vs 'b', '♭', 'bemolle'
        if cleaned.contains("#") || cleaned.contains("d") || cleaned.contains("diesis") || cleaned.contains("sharp") {
            // Attenzione: 'd' come nota Re vs 'd' come diesis
            if cleaned.contains("#") || cleaned.contains("diesis") || cleaned.contains("sharp") || (cleaned.contains(" d ") || cleaned.hasSuffix(" d")) {
                accidental = 1
                preferFlat = false
            }
        }
        if cleaned.contains("b") || cleaned.contains("♭") || cleaned.contains("bemolle") || cleaned.contains("flat") {
            // Attenzione: 'b' come nota Si (inglese) vs 'b' come bemolle
            if cleaned.contains("♭") || cleaned.contains("bemolle") || cleaned.contains("flat") || cleaned.contains(" b ") || cleaned.hasSuffix(" b") || tokens.contains("b") {
                accidental = -1
                preferFlat = true
            }
        }

        // Estrai numeri (ottava 0..8 ed indice modalità 1..8)
        let numbers = tokens.compactMap { Int($0) }
        if numbers.count >= 1 {
            // Il primo numero se in 0..8 è l'ottava
            if numbers[0] >= 0 && numbers[0] <= 8 {
                octave = numbers[0]
            }
        }
        if numbers.count >= 2 {
            // Il secondo numero se in 1..8 è la modalità
            if numbers[1] >= 1 && numbers[1] <= 8 {
                modeIndex = numbers[1]
            }
        }

        // O estrai numeri da stringhe composte come "c4" o "do4"
        let digitMatches = cleaned.compactMap { $0.wholeNumberValue }
        if numbers.isEmpty && !digitMatches.isEmpty {
            if digitMatches[0] >= 0 && digitMatches[0] <= 8 {
                octave = digitMatches[0]
            }
            if digitMatches.count >= 2 && digitMatches[1] >= 1 && digitMatches[1] <= 8 {
                modeIndex = digitMatches[1]
            }
        }

        let totalMIDI = (octave + 1) * 12 + foundPC + accidental
        let clampedMIDI = UInt8(max(21, min(108, totalMIDI)))

        let modes = MusicalScaleMode.allCases
        let selectedMode = (modeIndex >= 1 && modeIndex <= modes.count) ? modes[modeIndex - 1] : .major

        return ManualChordParseResult(
            midiNote: clampedMIDI,
            scaleMode: selectedMode,
            chordQuality: selectedMode.defaultChordQuality,
            preferFlat: preferFlat
        )
    }
}
