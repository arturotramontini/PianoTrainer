import SwiftUI

/// Componente grafico SwiftUI per la visualizzazione delle note sul Pentagramma Musicale (Grand Staff View).
/// Visualizza Chiave di Violino (Treble Clef) e Chiave di Basso (Bass Clef) con tagli addizionali automatici
/// per l'intera estensione del pianoforte (A0 ... C8).
struct GrandStaffView: View {
    @ObservedObject var clientService: TCPClientService

    /// Struttura dati interna per una nota nel pentagramma
    struct StaffNoteInfo: Hashable {
        let midi: UInt8
        let diatonicStep: Int // Step relativo al Do4 (Do4 = 0, Re4 = 1, Mi4 = 2, Si3 = -1, ecc.)
        let accidental: String? // "♯", "♭" o nil
        let isMatched: Bool
    }

    var body: some View {
        let targetNotes = currentTargetNotes
        let isMatched = isCurrentStepMatched
        let notesInfo = calculateNotesInfo(targetNotes: targetNotes, isMatched: isMatched)

        VStack(alignment: .center, spacing: 4) {
            Text("PENTAGRAMMA")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.secondary)

            ZStack {
                // Sfondo rettangolare scuro sottile
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.12))

                // Canvas di disegno vettoriale del pentagramma
                StaffCanvasView(notesInfo: notesInfo)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 8)
            }
            .frame(width: 140, height: 180)
        }
    }

    /// Ottiene le note target correnti in base alla modalità (Note Singole, Accordi, Spartito)
    private var currentTargetNotes: Set<UInt8> {
        switch clientService.trainerMode {
        case .singleNotes:
            if let midi = clientService.targetNoteMIDI {
                return Set([midi])
            }
        case .chords:
            if let chord = clientService.targetChord {
                return chord.notesMIDI
            }
        case .score:
            if let result = clientService.scoreParseResult, clientService.currentScoreIndex < result.steps.count {
                return result.steps[clientService.currentScoreIndex].targetNotes
            }
        }
        return Set<UInt8>()
    }

    /// Verifica se il passo/nota/accordo corrente è stato indovinato dall'utente
    private var isCurrentStepMatched: Bool {
        switch clientService.trainerMode {
        case .singleNotes: return clientService.lastPlayedIsTargetMatched
        case .chords: return clientService.isChordMatched
        case .score: return clientService.isScoreMatched
        }
    }

    /// Calcola i dati di posizionamento fonetico e diatonico per ogni nota target
    private func calculateNotesInfo(targetNotes: Set<UInt8>, isMatched: Bool) -> [StaffNoteInfo] {
        targetNotes.map { midi in
            let pitchClass = Int(midi % 12)
            let octave = Int(midi / 12) - 1

            let preferFlat: Bool = {
                if clientService.trainerMode == .singleNotes {
                    return clientService.targetPreferFlat
                } else if clientService.trainerMode == .chords, let chord = clientService.targetChord {
                    return chord.preferFlat
                }
                return false
            }()

            let diatonicPitchClass: Int
            let accidental: String?

            switch pitchClass {
            case 0: // C
                diatonicPitchClass = 0; accidental = nil
            case 1: // C# / Db
                if preferFlat { diatonicPitchClass = 1; accidental = "♭" }
                else { diatonicPitchClass = 0; accidental = "♯" }
            case 2: // D
                diatonicPitchClass = 1; accidental = nil
            case 3: // D# / Eb
                if preferFlat { diatonicPitchClass = 2; accidental = "♭" }
                else { diatonicPitchClass = 1; accidental = "♯" }
            case 4: // E
                diatonicPitchClass = 2; accidental = nil
            case 5: // F
                diatonicPitchClass = 3; accidental = nil
            case 6: // F# / Gb
                if preferFlat { diatonicPitchClass = 4; accidental = "♭" }
                else { diatonicPitchClass = 3; accidental = "♯" }
            case 7: // G
                diatonicPitchClass = 4; accidental = nil
            case 8: // G# / Ab
                if preferFlat { diatonicPitchClass = 5; accidental = "♭" }
                else { diatonicPitchClass = 4; accidental = "♯" }
            case 9: // A
                diatonicPitchClass = 5; accidental = nil
            case 10: // A# / Bb
                if preferFlat { diatonicPitchClass = 6; accidental = "♭" }
                else { diatonicPitchClass = 5; accidental = "♯" }
            case 11: // B
                diatonicPitchClass = 6; accidental = nil
            default:
                diatonicPitchClass = 0; accidental = nil
            }

            // Step diatonico totale dove C4 (MIDI 60) = 0
            // C4: octave=4, diatonicPitchClass=0 -> 4*7 + 0 = 28 -> 28 - 28 = 0
            let diatonicStep = (octave * 7 + diatonicPitchClass) - 28

            return StaffNoteInfo(midi: midi, diatonicStep: diatonicStep, accidental: accidental, isMatched: isMatched)
        }
    }
}

/// Canvas di disegno vettoriale per le 5 righe della Chiave di Violino, 5 righe della Chiave di Basso,
/// tagli addizionali, chiavi musicali e pallini neri delle note.
struct StaffCanvasView: View {
    let notesInfo: [GrandStaffView.StaffNoteInfo]

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height

            // Centro del pentagramma corrisponde al Do4 (diatonicStep 0)
            let centerY = height * 0.50
            let lineSpacing: CGFloat = 8.0 // Distanza tra 2 righe adiacenti
            let stepHeight: CGFloat = lineSpacing / 2.0 // Distanza tra riga e spazio adiacente (4.0pt)

            // 1. Disegna le 5 righe del Pentagramma Superiore (Chiave di Violino)
            // Righe a diatonicStep: 2 (Mi4), 4 (Sol4), 6 (Si4), 8 (Re5), 10 (Fa5)
            let trebleSteps = [2, 4, 6, 8, 10]
            for step in trebleSteps {
                let y = centerY - (CGFloat(step) * stepHeight)
                var path = Path()
                path.move(to: CGPoint(x: 10, y: y))
                path.addLine(to: CGPoint(x: width - 10, y: y))
                context.stroke(path, with: .color(.white.opacity(0.4)), lineWidth: 1.0)
            }

            // 2. Disegna le 5 righe del Pentagramma Inferiore (Chiave di Basso)
            // Righe a diatonicStep: -10 (Sol2), -8 (Si2), -6 (Re3), -4 (Fa3), -2 (La3)
            let bassSteps = [-10, -8, -6, -4, -2]
            for step in bassSteps {
                let y = centerY - (CGFloat(step) * stepHeight)
                var path = Path()
                path.move(to: CGPoint(x: 10, y: y))
                path.addLine(to: CGPoint(x: width - 10, y: y))
                context.stroke(path, with: .color(.white.opacity(0.4)), lineWidth: 1.0)
            }

            // Simboli delle Chiavi Musicali (G = Treble, F = Bass)
            let trebleGlyphY = centerY - (CGFloat(6) * stepHeight)
            let bassGlyphY = centerY - (CGFloat(-6) * stepHeight)

            context.draw(
                Text("🎼").font(.system(size: 20)),
                at: CGPoint(x: 20, y: trebleGlyphY),
                anchor: .center
            )
            context.draw(
                Text("𝄢").font(.system(size: 16)),
                at: CGPoint(x: 20, y: bassGlyphY),
                anchor: .center
            )

            // 3. Disegna le Note ed i relativi Tagli Addizionali
            let noteX = width * 0.65
            let noteRadius: CGFloat = 3.2 // Diametro ~6.4pt (< lineSpacing 8.0pt per distinguere riga e spazio)

            for note in notesInfo {
                let noteY = centerY - (CGFloat(note.diatonicStep) * stepHeight)
                let noteColor: Color = note.isMatched ? .green : .primary

                // 3a. Disegna i Tagli Addizionali (Ledger Lines)
                // Do4 (step 0): Taglio addizionale centrale
                if note.diatonicStep == 0 {
                    var path = Path()
                    path.move(to: CGPoint(x: noteX - 8, y: noteY))
                    path.addLine(to: CGPoint(x: noteX + 8, y: noteY))
                    context.stroke(path, with: .color(.white.opacity(0.7)), lineWidth: 1.2)
                }
                // Tagli superiori (sopra Fa5 / step > 10): righe a step pari 12, 14, 16, 18, 20, 22...
                else if note.diatonicStep > 10 {
                    let maxLedgerStep = (note.diatonicStep % 2 == 0) ? note.diatonicStep : (note.diatonicStep - 1)
                    for s in stride(from: 12, through: maxLedgerStep, by: 2) {
                        let ly = centerY - (CGFloat(s) * stepHeight)
                        var path = Path()
                        path.move(to: CGPoint(x: noteX - 8, y: ly))
                        path.addLine(to: CGPoint(x: noteX + 8, y: ly))
                        context.stroke(path, with: .color(.white.opacity(0.7)), lineWidth: 1.2)
                    }
                }
                // Tagli inferiori (sotto Sol2 / step < -10): righe a step pari -12, -14, -16, -18, -20, -22...
                else if note.diatonicStep < -10 {
                    let minLedgerStep = (note.diatonicStep % 2 == 0) ? note.diatonicStep : (note.diatonicStep + 1)
                    for s in stride(from: -12, through: minLedgerStep, by: -2) {
                        let ly = centerY - (CGFloat(s) * stepHeight)
                        var path = Path()
                        path.move(to: CGPoint(x: noteX - 8, y: ly))
                        path.addLine(to: CGPoint(x: noteX + 8, y: ly))
                        context.stroke(path, with: .color(.white.opacity(0.7)), lineWidth: 1.2)
                    }
                }

                // 3b. Disegna la Nota (Pallino nero pieno / verde se indovinato)
                let noteRect = CGRect(
                    x: noteX - noteRadius,
                    y: noteY - (noteRadius * 0.85),
                    width: noteRadius * 2.2,
                    height: noteRadius * 1.7
                )
                let notePath = Path(ellipseIn: noteRect)
                context.fill(notePath, with: .color(noteColor))
                context.stroke(notePath, with: .color(.white.opacity(0.8)), lineWidth: 0.8)

                // 3c. Disegna l'Alterazione (♯ o ♭) a sinistra della nota se presente
                if let acc = note.accidental {
                    context.draw(
                        Text(acc).font(.system(size: 11, weight: .bold)).foregroundColor(noteColor),
                        at: CGPoint(x: noteX - 12, y: noteY),
                        anchor: .center
                    )
                }
            }
        }
    }
}
