import Foundation
import AVFoundation

/// Servizio vocale nativo macOS basato su AVSpeechSynthesizer.
/// Pronuncia le note ed i suggerimenti d'allenamento senza lag o ritardi.
@MainActor
final class SpeechService: NSObject, AVSpeechSynthesizerDelegate {
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    /// Pronuncia il nome di una nota appena premuta (es: "C4", "F sharp 3").
    func speakNote(_ midi: UInt8, isItalian: Bool = false) {
        let phoneticText = NoteNameUtility.speechPhoneticName(for: midi, languageIsItalian: isItalian)
        speakText(phoneticText, languageCode: isItalian ? "it-IT" : "en-US", interruptPrevious: true)
    }

    /// Propone a voce una nuova nota da suonare (es: "Prossima nota: E4" o "Next note: E4").
    func speakProposedNote(_ midi: UInt8, isItalian: Bool = false) {
        let phoneticText = NoteNameUtility.speechPhoneticName(for: midi, languageIsItalian: isItalian)
        let promptText = isItalian ? "Prossima nota: \(phoneticText)" : "Next note: \(phoneticText)"
        speakText(promptText, languageCode: isItalian ? "it-IT" : "en-US", interruptPrevious: true)
    }

    private func speakText(_ text: String, languageCode: String = "en-US", interruptPrevious: Bool = true) {
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
