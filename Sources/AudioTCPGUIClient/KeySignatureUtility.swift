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
}
