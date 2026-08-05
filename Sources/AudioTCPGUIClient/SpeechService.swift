import Foundation
import AVFoundation

/// Servizio vocale nativo macOS basato su AVSpeechSynthesizer.
/// Pronuncia le note, gli accordi ed i suggerimenti d'allenamento senza lag o ritardi.
@MainActor
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()
    var isMuted: Bool = false

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Pronuncia il nome di una nota appena premuta (es: "C sharp 4", "Re bemolle 4").
    func speakNote(_ midi: UInt8, preferFlat: Bool = false, isItalian: Bool = false) {
        let phoneticText = NoteNameUtility.speechPhoneticName(for: midi, preferFlat: preferFlat, languageIsItalian: isItalian)
        speakText(phoneticText, languageCode: isItalian ? "it-IT" : "en-US", interruptPrevious: true)
    }

    /// Propone a voce una nuova nota da suonare (es: "Prossima nota: Re bemolle 4" o "Next note: D flat 4").
    func speakProposedNote(_ midi: UInt8, preferFlat: Bool = false, isItalian: Bool = false) {
        let phoneticText = NoteNameUtility.speechPhoneticName(for: midi, preferFlat: preferFlat, languageIsItalian: isItalian)
        let promptText = isItalian ? "Prossima nota: \(phoneticText)" : "Next note: \(phoneticText)"
        speakText(promptText, languageCode: isItalian ? "it-IT" : "en-US", interruptPrevious: true)
    }

    /// Propone a voce un nuovo accordo da suonare (es: "Prossimo accordo: Do Maggiore in 1° Rivolto").
    func speakProposedChord(_ chord: ChordDefinition, isItalian: Bool = false) {
        let phoneticText = chord.speechPhoneticName(isItalian: isItalian)
        let promptText = isItalian ? "Prossimo accordo: \(phoneticText)" : "Next chord: \(phoneticText)"
        speakText(promptText, languageCode: isItalian ? "it-IT" : "en-US", interruptPrevious: true)
    }

    /// Pronuncia la conferma di accordo indovinato (es: "Accordo di Do Maggiore eseguito correttamente!").
    func speakChordSuccess(_ chord: ChordDefinition, isItalian: Bool = false) {
        let phoneticText = chord.speechPhoneticName(isItalian: isItalian)
        let promptText = isItalian ? "\(phoneticText), corretto!" : "\(phoneticText), correct!"
        speakText(promptText, languageCode: isItalian ? "it-IT" : "en-US", interruptPrevious: true)
    }

    /// Pronuncia un testo generico a voce (es: per incoraggiamento o spartito)
    func speak(text: String, isItalian: Bool = true) {
        speakText(text, languageCode: isItalian ? "it-IT" : "en-US", interruptPrevious: true)
    }

    private func speakText(_ text: String, languageCode: String = "en-US", interruptPrevious: Bool = true) {
        guard !isMuted else {
            if synthesizer.isSpeaking {
                synthesizer.stopSpeaking(at: .immediate)
            }
            return
        }

        if interruptPrevious && synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: languageCode) ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.volume = 0.95
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.05

        synthesizer.speak(utterance)
    }
}
