import SwiftUI

/// Componente grafico SwiftUI per la visualizzazione delle note sul Pentagramma Musicale (Grand Staff View).
/// Visualizza Chiave di Violino (Treble Clef su Sol4) e Chiave di Basso (Bass Clef su Fa3 con puntini a cavallo della 4ª riga)
/// con tagli addizionali automatici per l'intera estensione del pianoforte (A0 ... C8).
///
/// MOSTRA 2 COLONNE CON SOTTO-COLONNE SEPARATE PER NOTE NATURALI ED ALTERATE:
/// 1. Colonna Sinistra (PROPOSTE): Note Naturali su xBaseTarget, Note Alterate traslate a sinistra di 5mm (~15pt)
/// 2. Colonna Destra (SUONATE): Note Naturali su xBasePlayed, Note Alterate traslate a sinistra di 5mm (~15pt)
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
        let activeNotes = clientService.activeNotes
        let isMatched = isCurrentStepMatched

        let targetNotesInfo = calculateNotesInfo(notes: targetNotes, isMatched: isMatched)
        let playedNotesInfo = calculateNotesInfo(notes: activeNotes, isMatched: isMatched)

        VStack(alignment: .center, spacing: 4) {
            HStack(spacing: 12) {
                Text("PENTAGRAMMA")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
            }

            ZStack {
                // Sfondo rettangolare scuro ingrandito in altezza per contenere completamente A0 e C8
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.black.opacity(0.18))

                // Canvas di disegno vettoriale del pentagramma (2 colonne con sotto-colonna alterata a sinistra di 5mm)
                StaffCanvasView(targetNotesInfo: targetNotesInfo, playedNotesInfo: playedNotesInfo)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 10)
            }
            .frame(width: 250, height: 680)
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

    /// Calcola i dati di posizionamento fonetico e diatonico per ogni insieme di note
    private func calculateNotesInfo(notes: Set<UInt8>, isMatched: Bool) -> [StaffNoteInfo] {
        notes.map { midi in
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

/// Canvas di disegno vettoriale a 2 COLONNE con sotto-colonne separate per note naturali ed alterate (traslate di 5mm a sinistra):
/// - Colonna 1 (xBaseTarget): Note Proposte dal Mac
/// - Colonna 2 (xBasePlayed): Note Suonate in Tempo Reale sulla Tastiera MIDI
struct StaffCanvasView: View {
    let targetNotesInfo: [GrandStaffView.StaffNoteInfo]
    let playedNotesInfo: [GrandStaffView.StaffNoteInfo]

    var body: some View {
        Canvas { context, size in
            let width = size.width
            let height = size.height

            // Centro del pentagramma corrisponde al Do4 (diatonicStep 0)
            let centerY = height * 0.51
            let lineSpacing: CGFloat = 22.0 // Distanza tra 2 righe adiacenti
            let stepHeight: CGFloat = lineSpacing / 2.0 // Distanza tra riga e spazio adiacente (11.0pt)

            // Posizionamento orizzontale delle due colonne base
            let xClef: CGFloat = 24.0
            let xBaseTarget: CGFloat = width * 0.46 // Base Colonna Note Proposte
            let xBasePlayed: CGFloat = width * 0.82 // Base Colonna Note Suonate (distanza ~1.5 cm)

            // Header delle Colonne
            context.draw(
                Text("PROPOSTE").font(.system(size: 8, weight: .bold)).foregroundColor(.orange),
                at: CGPoint(x: xBaseTarget - 7, y: 14),
                anchor: .center
            )
            context.draw(
                Text("SUONATE").font(.system(size: 8, weight: .bold)).foregroundColor(.cyan),
                at: CGPoint(x: xBasePlayed - 7, y: 14),
                anchor: .center
            )

            // 1. Disegna le 5 righe del Pentagramma Superiore (Chiave di Violino)
            // Righe a diatonicStep: 2 (Mi4), 4 (Sol4), 6 (Si4), 8 (Re5), 10 (Fa5)
            let trebleSteps = [2, 4, 6, 8, 10]
            for step in trebleSteps {
                let y = centerY - (CGFloat(step) * stepHeight)
                var path = Path()
                path.move(to: CGPoint(x: 10, y: y))
                path.addLine(to: CGPoint(x: width - 10, y: y))
                context.stroke(path, with: .color(.white.opacity(0.45)), lineWidth: 1.2)
            }

            // 2. Disegna le 5 righe del Pentagramma Inferiore (Chiave di Basso)
            // Righe a diatonicStep: -10 (Sol2), -8 (Si2), -6 (Re3), -4 (Fa3), -2 (La3)
            let bassSteps = [-10, -8, -6, -4, -2]
            for step in bassSteps {
                let y = centerY - (CGFloat(step) * stepHeight)
                var path = Path()
                path.move(to: CGPoint(x: 10, y: y))
                path.addLine(to: CGPoint(x: width - 10, y: y))
                context.stroke(path, with: .color(.white.opacity(0.45)), lineWidth: 1.2)
            }

            // -------------------------------------------------------------
            // SIMBOLI DELLE CHIAVI CON POSIZIONAMENTO TEORICO RIGOROSO
            // -------------------------------------------------------------

            // CHIAVE DI VIOLINO (Chiave di SOL): Il ricciolo centrale avvolge la 2ª riga dal basso (Sol4 = step 4)!
            let sol4Y = centerY - (CGFloat(4) * stepHeight)
            context.draw(
                Text("🎼").font(.system(size: 44)),
                at: CGPoint(x: xClef, y: sol4Y - 3),
                anchor: .center
            )

            // CHIAVE DI BASSO (Chiave di FA): Il ricciolo parte sulla 4ª riga (Fa3 = step -4)
            // ed i 2 puntini si posizionano precisamente A CAVALLO della 4ª riga (nello spazio 3 e nello spazio 4)!
            let fa3Y = centerY - (CGFloat(-4) * stepHeight)
            context.draw(
                Text("𝄢").font(.system(size: 36)),
                at: CGPoint(x: xClef - 2, y: fa3Y + 1),
                anchor: .center
            )

            // Disegno vettoriale dei 2 puntini della Chiave di Basso a cavallo della 4ª riga (Fa3)
            let upperDotY = centerY - (CGFloat(-3) * stepHeight)
            let lowerDotY = centerY - (CGFloat(-5) * stepHeight)
            let dotX: CGFloat = xClef + 15.0

            var dotPathUpper = Path()
            dotPathUpper.addEllipse(in: CGRect(x: dotX - 2.0, y: upperDotY - 2.0, width: 4.0, height: 4.0))
            context.fill(dotPathUpper, with: .color(.white))

            var dotPathLower = Path()
            dotPathLower.addEllipse(in: CGRect(x: dotX - 2.0, y: lowerDotY - 2.0, width: 4.0, height: 4.0))
            context.fill(dotPathLower, with: .color(.white))

            // -------------------------------------------------------------
            // 3. FUNZIONE HELPER PER DISEGNARE LE NOTE CON SOTTO-COLONNA ALTERATA (5mm a sinistra)
            // -------------------------------------------------------------
            let noteHeight: CGFloat = lineSpacing / 3.0 // Exact 1/3 line spacing (7.33pt)
            let noteWidth: CGFloat = lineSpacing * 0.58 // 12.7pt
            let subColumnOffset: CGFloat = 15.0 // Distanza ~5 mm a sinistra per le note alterate!

            func drawNotes(_ notes: [GrandStaffView.StaffNoteInfo], xBase: CGFloat, defaultColor: Color) {
                for note in notes {
                    let isAltered = (note.accidental != nil)
                    // Note naturali su xBase, note alterate traslate a sinistra di ~5mm (15pt)
                    let noteX = isAltered ? (xBase - subColumnOffset) : xBase
                    let noteY = centerY - (CGFloat(note.diatonicStep) * stepHeight)
                    let noteColor: Color = note.isMatched ? .green : defaultColor

                    // 3a. Disegna i Tagli Addizionali (Ledger Lines)
                    if note.diatonicStep == 0 {
                        var path = Path()
                        path.move(to: CGPoint(x: noteX - 12, y: noteY))
                        path.addLine(to: CGPoint(x: noteX + 12, y: noteY))
                        context.stroke(path, with: .color(.white.opacity(0.85)), lineWidth: 1.4)
                    }
                    else if note.diatonicStep > 10 {
                        let maxLedgerStep = (note.diatonicStep % 2 == 0) ? note.diatonicStep : (note.diatonicStep - 1)
                        for s in stride(from: 12, through: maxLedgerStep, by: 2) {
                            let ly = centerY - (CGFloat(s) * stepHeight)
                            var path = Path()
                            path.move(to: CGPoint(x: noteX - 12, y: ly))
                            path.addLine(to: CGPoint(x: noteX + 12, y: ly))
                            context.stroke(path, with: .color(.white.opacity(0.85)), lineWidth: 1.4)
                        }
                    }
                    else if note.diatonicStep < -10 {
                        let minLedgerStep = (note.diatonicStep % 2 == 0) ? note.diatonicStep : (note.diatonicStep + 1)
                        for s in stride(from: -12, through: minLedgerStep, by: -2) {
                            let ly = centerY - (CGFloat(s) * stepHeight)
                            var path = Path()
                            path.move(to: CGPoint(x: noteX - 11, y: ly))
                            path.addLine(to: CGPoint(x: noteX + 11, y: ly))
                            context.stroke(path, with: .color(.white.opacity(0.85)), lineWidth: 1.4)
                        }
                    }

                    // 3b. Disegna la Nota (Pallino)
                    let noteRect = CGRect(
                        x: noteX - (noteWidth / 2.0),
                        y: noteY - (noteHeight / 2.0),
                        width: noteWidth,
                        height: noteHeight
                    )
                    let notePath = Path(ellipseIn: noteRect)
                    context.fill(notePath, with: .color(noteColor))
                    context.stroke(notePath, with: .color(.white.opacity(0.9)), lineWidth: 1.1)

                    // 3c. Disegna l'Alterazione (♯ o ♭) a sinistra della nota alterata
                    if let acc = note.accidental {
                        context.draw(
                            Text(acc).font(.system(size: 15, weight: .bold)).foregroundColor(noteColor),
                            at: CGPoint(x: noteX - 14, y: noteY),
                            anchor: .center
                        )
                    }
                }
            }

            // Disegna la Colonna 1: Note Proposte dal Mac (Orange / Black / Green)
            drawNotes(targetNotesInfo, xBase: xBaseTarget, defaultColor: .orange)

            // Disegna la Colonna 2: Note Suonate in Tempo Reale dall'Utente (Cyan / Green)
            drawNotes(playedNotesInfo, xBase: xBasePlayed, defaultColor: .cyan)
        }
    }
}
