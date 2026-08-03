import Foundation

/// Utility per la conversione di numeri di nota MIDI (21...108 per pianoforte a 88 tasti)
/// in notazione internazionale/inglese (C4, F#3, Db4) o italiana (Do4, Fa#3, Reb4) e fonetica vocale.
public struct NoteNameUtility {
    private static let englishNoteNamesSharp = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let englishNoteNamesFlat  = ["C", "Db", "D", "Eb", "E", "F", "Gb", "G", "Ab", "A", "Bb", "B"]

    private static let italianNoteNamesSharp = ["Do", "Do#", "Re", "Re#", "Mi", "Fa", "Fa#", "Sol", "Sol#", "La", "La#", "Si"]
    private static let italianNoteNamesFlat  = ["Do", "Reb", "Re", "Mib", "Mi", "Fa", "Solb", "Sol", "Lab", "La", "Sib", "Si"]

    /// Determina se una nota MIDI corrisponde a un tasto nero (nota alterata).
    public static func isBlackKey(midi: UInt8) -> Bool {
        let noteInOctave = Int(midi % 12)
        return [1, 3, 6, 8, 10].contains(noteInOctave)
    }

    /// Restituisce la notazione inglese (es: "C#4" oppure "Db4") per una nota MIDI.
    public static func englishName(for midi: UInt8, preferFlat: Bool = false) -> String {
        let noteInOctave = Int(midi % 12)
        let octaveNumber = Int(midi / 12) - 1
        let names = preferFlat ? englishNoteNamesFlat : englishNoteNamesSharp
        return "\(names[noteInOctave])\(octaveNumber)"
    }

    /// Restituisce la notazione italiana (es: "Do#4" oppure "Reb4") per una nota MIDI.
    public static func italianName(for midi: UInt8, preferFlat: Bool = false) -> String {
        let noteInOctave = Int(midi % 12)
        let octaveNumber = Int(midi / 12) - 1
        let names = preferFlat ? italianNoteNamesFlat : italianNoteNamesSharp
        return "\(names[noteInOctave])\(octaveNumber)"
    }

    /// Restituisce il testo da visualizzare (es: "C4" per tasto bianco, "C#4 / Db4" per tasto nero).
    public static func dualName(for midi: UInt8, isItalian: Bool = false) -> String {
        if !isBlackKey(midi: midi) {
            return isItalian ? italianName(for: midi) : englishName(for: midi)
        }
        let sharp = isItalian ? italianName(for: midi, preferFlat: false) : englishName(for: midi, preferFlat: false)
        let flat  = isItalian ? italianName(for: midi, preferFlat: true)  : englishName(for: midi, preferFlat: true)
        return "\(sharp) / \(flat)"
    }

    /// Converte la nota in testo fonetico comprensibile per AVSpeechSynthesizer.
    /// Esempio: "Do diesis 4" vs "Re bemolle 4", "C sharp 4" vs "D flat 4"
    public static func speechPhoneticName(for midi: UInt8, preferFlat: Bool = false, languageIsItalian: Bool = false) -> String {
        let noteInOctave = Int(midi % 12)
        let octaveNumber = Int(midi / 12) - 1

        if languageIsItalian {
            let namesSharp = ["Do", "Do diesis", "Re", "Re diesis", "Mi", "Fa", "Fa diesis", "Sol", "Sol diesis", "La", "La diesis", "Si"]
            let namesFlat  = ["Do", "Re bemolle", "Re", "Mi bemolle", "Mi", "Fa", "Sol bemolle", "Sol", "La bemolle", "La", "Si bemolle", "Si"]
            let names = preferFlat ? namesFlat : namesSharp
            return "\(names[noteInOctave]) \(octaveNumber)"
        } else {
            let namesSharp = ["C", "C sharp", "D", "D sharp", "E", "F", "F sharp", "G", "G sharp", "A", "A sharp", "B"]
            let namesFlat  = ["C", "D flat", "D", "E flat", "E", "F", "G flat", "G", "A flat", "A", "B flat", "B"]
            let names = preferFlat ? namesFlat : namesSharp
            return "\(names[noteInOctave]) \(octaveNumber)"
        }
    }

    /// Estrae una nota MIDI casuale da una gamma specificata (predefinito 88 tasti del pianoforte: 21 A0 ... 108 C8).
    public static func randomPianoMIDI(minMIDI: UInt8 = 21, maxMIDI: UInt8 = 108) -> UInt8 {
        UInt8.random(in: minMIDI...maxMIDI)
    }
}
