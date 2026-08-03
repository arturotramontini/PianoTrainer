import Foundation

/// Utility per la conversione di numeri di nota MIDI (21...108 per pianoforte a 88 tasti)
/// in notazione internazionale/inglese (C4, F#3) o italiana (Do4, Fa#3) e testo fonetico per la sintesi vocale.
public struct NoteNameUtility {
    private static let englishNoteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    private static let italianNoteNames = ["Do", "Do#", "Re", "Re#", "Mi", "Fa", "Fa#", "Sol", "Sol#", "La", "La#", "Si"]

    /// Restituisce la notazione inglese (es: "C4", "F#3") per una nota MIDI (21..108).
    public static func englishName(for midi: UInt8) -> String {
        let noteInOctave = Int(midi % 12)
        let octaveNumber = Int(midi / 12) - 1
        return "\(englishNoteNames[noteInOctave])\(octaveNumber)"
    }

    /// Restituisce la notazione italiana (es: "Do4", "Fa#3") per una nota MIDI.
    public static func italianName(for midi: UInt8) -> String {
        let noteInOctave = Int(midi % 12)
        let octaveNumber = Int(midi / 12) - 1
        return "\(italianNoteNames[noteInOctave])\(octaveNumber)"
    }

    /// Converte il nome della nota in testo fonetico comprensibile per AVSpeechSynthesizer.
    /// Esempio: "F#4" -> "F sharp 4", "C4" -> "C 4"
    public static func speechPhoneticName(for midi: UInt8, languageIsItalian: Bool = false) -> String {
        let noteInOctave = Int(midi % 12)
        let octaveNumber = Int(midi / 12) - 1

        if languageIsItalian {
            let names = ["Do", "Do diesis", "Re", "Re diesis", "Mi", "Fa", "Fa diesis", "Sol", "Sol diesis", "La", "La diesis", "Si"]
            return "\(names[noteInOctave]) \(octaveNumber)"
        } else {
            let names = ["C", "C sharp", "D", "D sharp", "E", "F", "F sharp", "G", "G sharp", "A", "A sharp", "B"]
            return "\(names[noteInOctave]) \(octaveNumber)"
        }
    }

    /// Estrae una nota MIDI casuale da una gamma specificata (predefinito 88 tasti del pianoforte: 21 A0 ... 108 C8).
    public static func randomPianoMIDI(minMIDI: UInt8 = 21, maxMIDI: UInt8 = 108) -> UInt8 {
        UInt8.random(in: minMIDI...maxMIDI)
    }
}
