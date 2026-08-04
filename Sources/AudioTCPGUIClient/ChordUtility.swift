import Foundation

public enum ChordQuality: String, CaseIterable, Identifiable {
    case major = "Maggiore"
    case minor = "Minore"
    case diminished = "Diminuito"
    case augmented = "Aumentato"
    case dominant7 = "7ª Dominante"
    case major7 = "7ª Maggiore"
    case minor7 = "7ª Minore"

    public var id: String { rawValue }

    public var englishName: String {
        switch self {
        case .major: return "Major"
        case .minor: return "Minor"
        case .diminished: return "Diminished"
        case .augmented: return "Augmented"
        case .dominant7: return "Dominant 7th"
        case .major7: return "Major 7th"
        case .minor7: return "Minor 7th"
        }
    }

    public var shortSymbol: String {
        switch self {
        case .major: return ""
        case .minor: return "m"
        case .diminished: return "dim"
        case .augmented: return "aug"
        case .dominant7: return "7"
        case .major7: return "Maj7"
        case .minor7: return "m7"
        }
    }

    /// Intervalli in semitoni dallo stato fondamentale
    public var intervals: [Int] {
        switch self {
        case .major: return [0, 4, 7]
        case .minor: return [0, 3, 7]
        case .diminished: return [0, 3, 6]
        case .augmented: return [0, 4, 8]
        case .dominant7: return [0, 4, 7, 10]
        case .major7: return [0, 4, 7, 11]
        case .minor7: return [0, 3, 7, 10]
        }
    }
}

public enum ChordInversion: String, CaseIterable, Identifiable {
    case root = "Stato Fondamentale"
    case first = "1° Rivolto"
    case second = "2° Rivolto"

    public var id: String { rawValue }

    public var englishName: String {
        switch self {
        case .root: return "Root position"
        case .first: return "1st inversion"
        case .second: return "2nd inversion"
        }
    }
}

public struct ChordDefinition: Identifiable, Equatable {
    public let id = UUID()
    public let rootMIDI: UInt8 // es. 60 = C4
    public let quality: ChordQuality
    public let inversion: ChordInversion
    public let preferFlat: Bool

    public init(rootMIDI: UInt8, quality: ChordQuality, inversion: ChordInversion, preferFlat: Bool = false) {
        self.rootMIDI = rootMIDI
        self.quality = quality
        self.inversion = inversion
        self.preferFlat = preferFlat
    }

    /// Calcola le note MIDI esatte necessarie per l'accordo ed il suo rivolto
    public var notesMIDI: Set<UInt8> {
        let baseIntervals = quality.intervals
        var shiftedMIDI: [UInt8] = []

        for (index, interval) in baseIntervals.enumerated() {
            var note = Int(rootMIDI) + interval
            // Applica il rivolto
            if inversion == .first && index == 0 {
                note += 12 // Sposta la fondamentale un'ottava sopra
            } else if inversion == .second && index < 2 {
                note += 12 // Sposta fondamentale e terza un'ottava sopra
            }
            if note <= 108 {
                shiftedMIDI.append(UInt8(note))
            }
        }
        return Set(shiftedMIDI)
    }

    /// Nome leggibile dell'accordo (es: "Do Maggiore (1° Rivolto)" o "C Major (1st inversion)")
    public func displayName(isItalian: Bool = false) -> String {
        let rootName = isItalian ?
            NoteNameUtility.italianName(for: rootMIDI, preferFlat: preferFlat) :
            NoteNameUtility.englishName(for: rootMIDI, preferFlat: preferFlat)
        
        let qualName = isItalian ? quality.rawValue : quality.englishName
        let invName  = isItalian ? inversion.rawValue : inversion.englishName

        return "\(rootName) \(qualName) (\(invName))"
    }

    /// Testo fonetico per AVSpeechSynthesizer
    public func speechPhoneticName(isItalian: Bool = false) -> String {
        let rootPhonetic = NoteNameUtility.speechPhoneticName(for: rootMIDI, preferFlat: preferFlat, languageIsItalian: isItalian)
        let qualName = isItalian ? quality.rawValue : quality.englishName
        let invName  = isItalian ? inversion.rawValue : inversion.englishName

        return isItalian ?
            "Accordo di \(rootPhonetic) \(qualName), \(invName)" :
            "\(rootPhonetic) \(qualName) chord, \(invName)"
    }

    /// Genera un accordo casuale entro la gamma centrale del pianoforte (es: C3...C5)
    public static func random(allowedQualities: [ChordQuality] = [.major, .minor], minMIDI: UInt8 = 48, maxMIDI: UInt8 = 72) -> ChordDefinition {
        let root = UInt8.random(in: minMIDI...maxMIDI)
        let quality = allowedQualities.randomElement() ?? .major
        let inversion = ChordInversion.allCases.randomElement() ?? .root
        let preferFlat = NoteNameUtility.isBlackKey(midi: root) ? Bool.random() : false

        return ChordDefinition(rootMIDI: root, quality: quality, inversion: inversion, preferFlat: preferFlat)
    }
}
