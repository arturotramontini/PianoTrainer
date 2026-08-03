import SwiftUI
import AppKit

/// Gestore degli eventi di tastiera PC per suonare le note del pianoforte.
final class KeyboardMonitor {
    private var monitor: Any?
    private var pressedKeys = Set<UInt8>()

    // Mappatura tasti: 1..8 -> C4, D4, E4, F4, G4, A4, B4, C5
    // Supporto aggiuntivo fila alfa (A-S-D-F-G-H-J-K per ottava 3 e Q-W-E-R-T-Y-U-I per ottava 4)
    private let keyMap: [Character: UInt8] = [
        // Tasti 1..8 (Richiesti)
        "1": 60, // C4
        "2": 62, // D4
        "3": 64, // E4
        "4": 65, // F4
        "5": 67, // G4
        "6": 69, // A4
        "7": 71, // B4
        "8": 72, // C5

        // Fila Tastiera 'A-S-D-F-G-H-J-K' (C3 .. C4)
        "a": 48, "s": 50, "d": 52, "f": 53, "g": 55, "h": 57, "j": 59, "k": 60,
        "A": 48, "S": 50, "D": 52, "F": 53, "G": 55, "H": 57, "J": 59, "K": 60,

        // Fila Tastiera 'Q-W-E-R-T-Y-U-I' (C4 .. C5)
        "q": 60, "w": 62, "e": 64, "r": 65, "t": 67, "y": 69, "u": 71, "i": 72,
        "Q": 60, "W": 62, "E": 64, "R": 65, "T": 67, "Y": 69, "U": 71, "I": 72
    ]

    func startMonitoring(clientService: TCPClientService) {
        stopMonitoring()

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self = self else { return event }

            // Non intercettare se l'utente sta scrivendo in un campo di testo
            if let responder = event.window?.firstResponder, responder is NSTextView {
                return event
            }

            guard let chars = event.charactersIgnoringModifiers, let firstChar = chars.first,
                  let midi = self.keyMap[firstChar] else {
                return event
            }

            if event.type == .keyDown {
                if !event.isARepeat && !self.pressedKeys.contains(midi) {
                    self.pressedKeys.insert(midi)
                    Task { @MainActor in
                        clientService.sendNoteOn(midi: midi, velocity: 100.0)
                    }
                }
                return nil // Evento consumato (evita bip di sistema)
            } else if event.type == .keyUp {
                if self.pressedKeys.contains(midi) {
                    self.pressedKeys.remove(midi)
                    Task { @MainActor in
                        clientService.sendNoteOff(midi: midi)
                    }
                }
                return nil // Evento consumato
            }

            return event
        }
    }

    func stopMonitoring() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
        pressedKeys.removeAll()
    }

    deinit {
        stopMonitoring()
    }
}
