import SwiftUI

/// Componente grafico SwiftUI per la visualizzazione delle note sul Pentagramma Musicale (Grand Staff View).
/// Visualizza Chiave di Violino (Treble Clef su Sol4) e Chiave di Basso (Bass Clef su Fa3 con puntini a cavallo della 4ª riga)
/// con tagli addizionali automatici per l'intera estensione del pianoforte (A0 ... C8).
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
                // Sfondo rettangolare scuro
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.14))

                // Canvas di disegno vettoriale del pentagramma ingrandito in verticale
                StaffCanvasView(notesInfo: notesInfo)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 10)
            }
            .frame(width: 155, height: 250)
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
/// tagli addizionali, chiavi musicali posizionate con precisione teorica e pallini neri delle note.
struct StaffCanvasView: View {
    let notesInfo: [GrandStaffView.StaffNoteInfo]

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height

            // Centro del pentagramma corrisponde al Do4 (diatonicStep 0)
            let centerY = height * 0.50
            let lineSpacing: CGFloat = 11.5 // Distanza tra 2 righe adiacenti (ingrandita per massima leggibilità)
            let stepHeight: CGFloat = lineSpacing / 2.0 // Distanza tra riga e spazio adiacente (5.75pt)

            // 1. Disegna le 5 righe del Pentagramma Superiore (Chiave di Violino)
            // Righe a diatonicStep: 2 (Mi4), 4 (Sol4), 6 (Si4), 8 (Re5), 10 (Fa5)
            let trebleSteps = [2, 4, 6, 8, 10]
            for step in trebleSteps {
                let y = centerY - (CGFloat(step) * stepHeight)
                var path = Path()
                path.move(to: CGPoint(x: 10, y: y))
                path.addLine(to: CGPoint(x: width - 10, y: y))
                context.stroke(path, with: .color(.white.opacity(0.45)), lineWidth: 1.1)
            }

            // 2. Disegna le 5 righe del Pentagramma Inferiore (Chiave di Basso)
            // Righe a diatonicStep: -10 (Sol2), -8 (Si2), -6 (Re3), -4 (Fa3), -2 (La3)
            let bassSteps = [-10, -8, -6, -4, -2]
            for step in bassSteps {
                let y = centerY - (CGFloat(step) * stepHeight)
                var path = Path()
                path.move(to: CGPoint(x: 10, y: y))
                path.addLine(to: CGPoint(x: width - 10, y: y))
                context.stroke(path, with: .color(.white.opacity(0.45)), lineWidth: 1.1)
            }

            // -------------------------------------------------------------
            // SIMBOLI DELLE CHIAVI CON POSIZIONAMENTO TEORICO RIGOROSO
            // -------------------------------------------------------------

            // CHIAVE DI VIOLINO (Chiave di SOL): Il ricciolo centrale avvolge la 2ª riga dal basso (Sol4 = step 4)!
            let sol4Y = centerY - (CGFloat(4) * stepHeight)
            context.draw(
                Text("🎼").font(.system(size: 27)),
                at: CGPoint(x: 22, y: sol4Y - 2), // Allinea il centro del ricciolo su Sol4
                anchor: .center
            )

            // CHIAVE DI BASSO (Chiave di FA): Il ricciolo parte sulla 4ª riga (Fa3 = step -4)
            // ed i 2 puntini si posizionano precisamente A CAVALLO della 4ª riga (nello spazio 3 e nello spazio 4)!
            let fa3Y = centerY - (CGFloat(-4) * stepHeight)
            context.draw(
                Text("𝄢").font(.system(size: 21)),
                at: CGPoint(x: 20, y: fa3Y + 1), // Posiziona il ricciolo della chiave di basso sulla 4ª riga
                anchor: .center
            )

            // Disegno vettoriale dei 2 puntini della Chiave di Basso a cavallo della 4ª riga (Fa3)
            let upperDotY = centerY - (CGFloat(-3) * stepHeight) // Spazio sopra la 4ª riga (tra Fa3 e La3)
            let lowerDotY = centerY - (CGFloat(-5) * stepHeight) // Spazio sotto la 4ª riga (tra Re3 e Fa3)
            let dotX: CGFloat = 29.5

            var dotPathUpper = Path()
            dotPathUpper.addEllipse(in: CGRect(x: dotX - 1.2, y: upperDotY - 1.2, width: 2.4, height: 2.4))
            context.fill(dotPathUpper, with: .color(.white))

            var dotPathLower = Path()
            dotPathLower.addEllipse(in: CGRect(x: dotX - 1.2, y: lowerDotY - 1.2, width: 2.4, height: 2.4))
            context.fill(dotPathLower, with: .color(.white))

            // -------------------------------------------------------------
            // 3. DISEGNO DELLE NOTE ED I RELATIVI TAGLI ADDIZIONALI
            // -------------------------------------------------------------
            let noteX = width * 0.68
            let noteRadius: CGFloat = 4.2 // Diametro ~8.4pt (< lineSpacing 11.5pt per distinguere perfettamente riga e spazio)

            for note in notesInfo {
                let noteY = centerY - (CGFloat(note.diatonicStep) * stepHeight)
                let noteColor: Color = note.isMatched ? .green : .primary

                // 3a. Disegna i Tagli Addizionali (Ledger Lines)
                // Do4 (step 0): Taglio addizionale centrale
                if note.diatonicStep == 0 {
                    var path = Path()
                    path.move(to: CGPoint(x: noteX - 10, y: noteY))
                    path.addLine(to: CGPoint(x: noteX + 10, y: noteY))
                    context.stroke(path, with: .color(.white.opacity(0.75)), lineWidth: 1.3)
                }
                // Tagli superiori (sopra Fa5 / step > 10): righe a step pari 12, 14, 16, 18, 20, 22...
                else if note.diatonicStep > 10 {
                    let maxLedgerStep = (note.diatonicStep % 2 == 0) ? note.diatonicStep : (note.diatonicStep - 1)
                    for s in stride(from: 12, through: maxLedgerStep, by: 2) {
                        let ly = centerY - (CGFloat(s) * stepHeight)
                        var path = Path()
                        path.move(to: CGPoint(x: noteX - 10, y: ly))
                        path.addLine(to: CGPoint(x: noteX + 10, y: ly))
                        context.stroke(path, with: .color(.white.opacity(0.75)), lineWidth: 1.3)
                    }
                }
                // Tagli inferiori (sotto Sol2 / step < -10): righe a step pari -12, -14, -16, -18, -20, -22...
                else if note.diatonicStep < -10 {
                    let minLedgerStep = (note.diatonicStep % 2 == 0) ? note.diatonicStep : (note.diatonicStep + 1)
                    for s in stride(from: -12, through: minLedgerStep, by: -2) {
                        let ly = centerY - (CGFloat(s) * stepHeight)
                        var path = Path()
                        path.move(to: CGPoint(x: noteX - 10, y: ly))
                        path.addLine(to: CGPoint(x: noteX + 10, y: ly))
                        context.stroke(path, with: .color(.white.opacity(0.75)), lineWidth: 1.3)
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
                context.stroke(notePath, with: .color(.white.opacity(0.85)), lineWidth: 1.0)

                // 3c. Disegna l'Alterazione (♯ o ♭) a sinistra della nota se presente
                if let acc = note.accidental {
                    context.draw(
                        Text(acc).font(.system(size: 13, weight: .bold)).foregroundColor(noteColor),
                        at: CGPoint(x: noteX - 15, y: noteY),
                        anchor: .center
                    )
                }
            }
        }
    }
}
