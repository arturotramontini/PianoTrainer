import SwiftUI

struct PianoKey: Identifiable {
    let id: UInt8 // MIDI note number
    let noteName: String
    let isBlack: Bool
    let whiteIndex: Int // Per il calcolo del posizionamento
}

struct PianoView: View {
    @ObservedObject var clientService: TCPClientService
    var startMidi: UInt8 = 21 // A0 (Pianoforte completo 88 tasti: A0 ... C8)
    var noteCount: Int = 88   // 88 tasti (52 bianchi + 36 neri)

    private var keys: [PianoKey] {
        let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        var result: [PianoKey] = []
        var currentWhiteIndex = 0

        for midi in startMidi..<(startMidi + UInt8(noteCount)) {
            let noteInOctave = Int(midi % 12)
            let isBlack = [1, 3, 6, 8, 10].contains(noteInOctave)
            let octaveNumber = Int(midi / 12) - 1
            let name = "\(noteNames[noteInOctave])\(octaveNumber)"
            
            result.append(PianoKey(
                id: midi,
                noteName: name,
                isBlack: isBlack,
                whiteIndex: isBlack ? currentWhiteIndex - 1 : currentWhiteIndex
            ))

            if !isBlack {
                currentWhiteIndex += 1
            }
        }
        return result
    }

    private var totalWhiteKeys: Int {
        keys.filter { !$0.isBlack }.count
    }

    var body: some View {
        GeometryReader { geometry in
            let availableWidth = geometry.size.width
            // Calcola la larghezza minima del tasto bianco per garantire la leggibilità di 49 tasti
            let whiteKeyWidth = max(20.0, availableWidth / CGFloat(totalWhiteKeys))
            let totalKeyboardWidth = whiteKeyWidth * CGFloat(totalWhiteKeys)
            let height = geometry.size.height
            let blackKeyWidth = whiteKeyWidth * 0.62
            let blackKeyHeight = height * 0.58

            let fixedIndicatorWidth = max(6.0, whiteKeyWidth * 0.35)

            // Calcola le note target correnti in base alla modalità (Note Singole, Accordi, Spartito)
            let targetMIDINotes: Set<UInt8> = {
                if clientService.trainerMode == .singleNotes, let midi = clientService.targetNoteMIDI {
                    return Set([midi])
                } else if clientService.trainerMode == .chords, let chord = clientService.targetChord {
                    return chord.notesMIDI
                } else if clientService.trainerMode == .score, let result = clientService.scoreParseResult, clientService.currentScoreIndex < result.steps.count {
                    return result.steps[clientService.currentScoreIndex].targetNotes
                }
                return Set<UInt8>()
            }()

            let isCurrentStepMatched: Bool = {
                if clientService.trainerMode == .singleNotes {
                    return clientService.lastPlayedIsTargetMatched
                } else if clientService.trainerMode == .chords {
                    return clientService.isChordMatched
                } else if clientService.trainerMode == .score {
                    return clientService.isScoreMatched
                }
                return false
            }()

            // Calcola le classi di altezza (Pitch Classes 0..11) per la geometria dell'accordo o della tonalità su tutte le ottave
            let octavePitchClasses: Set<UInt8> = {
                if clientService.trainerMode == .chords, let chord = clientService.targetChord {
                    if clientService.cyanDotMode == .keyScaleNotes, let keyInfo = clientService.currentKeySignature {
                        return keyInfo.scalePitchClasses
                    } else {
                        return Set(chord.notesMIDI.map { $0 % 12 })
                    }
                } else if clientService.trainerMode == .singleNotes, let midi = clientService.targetNoteMIDI {
                    return Set([midi % 12])
                } else if clientService.trainerMode == .score {
                    return Set(targetMIDINotes.map { $0 % 12 })
                }
                return Set<UInt8>()
            }()

            ScrollView(.horizontal, showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    // Tasti Bianchi
                    HStack(spacing: 1) {
                        ForEach(keys.filter { !$0.isBlack }) { key in
                            let isActive = clientService.isNoteActive(key.id)
                            let isTargetKey = targetMIDINotes.contains(key.id)
                            let isMatched = isActive && isTargetKey && isCurrentStepMatched
                            let isOctaveMatch = octavePitchClasses.contains(key.id % 12)
                            let label = NoteNameUtility.dualName(for: key.id, isItalian: clientService.useItalianNotation)
                            
                            VStack {
                                Spacer()
                                Text(label)
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(isActive ? .white : .black.opacity(0.75))
                                    .padding(.bottom, 6)
                            }
                            .frame(width: whiteKeyWidth - 1, height: height - 14)
                            .background(
                                LinearGradient(
                                    colors: isMatched ? [.green, Color.green.opacity(0.8)] : (isActive ? [.cyan, .blue] : [.white, Color(white: 0.92)]),
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .cornerRadius(5, corners: [.bottomLeft, .bottomRight])
                            .shadow(color: .black.opacity(0.15), radius: 1.5, x: 0, y: 1.5)
                            .overlay(alignment: .top) {
                                ZStack {
                                    // 1. Indicatori Rettangolari Arancione Scuro a larghezza FISSA uniformata FUORI sopra il tasto esatto
                                    if clientService.showKeyHints && isTargetKey {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(Color(red: 0.88, green: 0.40, blue: 0.0))
                                            .frame(width: fixedIndicatorWidth, height: 5)
                                            .shadow(color: Color(red: 0.88, green: 0.40, blue: 0.0).opacity(0.9), radius: 3, x: 0, y: -1)
                                            .offset(y: -9)
                                    }

                                    // 2. Cerchiolini Ciano per la Geometria dell'accordo su TUTTE le ottave (più in alto a y = -17)
                                    if clientService.showOctaveGeometryHints && isOctaveMatch {
                                        Circle()
                                            .fill(Color.cyan.opacity(0.9))
                                            .frame(width: 4.5, height: 4.5)
                                            .shadow(color: Color.cyan.opacity(0.7), radius: 2, x: 0, y: -1)
                                            .offset(y: -17)
                                    }
                                }
                            }
                            .padding(.top, 14)
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { _ in
                                        if !clientService.isNoteActive(key.id) {
                                            clientService.sendNoteOn(midi: key.id)
                                        }
                                    }
                                    .onEnded { _ in
                                        clientService.sendNoteOff(midi: key.id)
                                    }
                            )
                        }
                    }

                    // Tasti Neri posizionati accuratamente sulle giunzioni con doppia dicitura Diesis / Bemolle
                    ForEach(keys.filter { $0.isBlack }) { key in
                        let xOffset = (CGFloat(key.whiteIndex + 1) * whiteKeyWidth) - (blackKeyWidth / 2.0)
                        let isActive = clientService.isNoteActive(key.id)
                        let isTargetKey = targetMIDINotes.contains(key.id)
                        let isMatched = isActive && isTargetKey && isCurrentStepMatched
                        let isOctaveMatch = octavePitchClasses.contains(key.id % 12)
                        let label = NoteNameUtility.dualName(for: key.id, isItalian: clientService.useItalianNotation)

                        VStack {
                            Spacer()
                            Text(label)
                                .font(.system(size: 6.5, weight: .bold))
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 1)
                                .padding(.bottom, 3)
                        }
                        .frame(width: blackKeyWidth, height: blackKeyHeight)
                        .background(
                            LinearGradient(
                                colors: isMatched ? [.green, Color.green.opacity(0.7)] : (isActive ? [.purple, .indigo] : [Color(white: 0.22), .black]),
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .cornerRadius(4, corners: [.bottomLeft, .bottomRight])
                        .shadow(color: .black.opacity(0.4), radius: 2, x: 1, y: 2)
                        .overlay(alignment: .top) {
                            ZStack {
                                // 1. Indicatori Rettangolari Arancione Scuro a larghezza FISSA uniformata FUORI sopra il tasto nero
                                if clientService.showKeyHints && isTargetKey {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(red: 0.88, green: 0.40, blue: 0.0))
                                        .frame(width: fixedIndicatorWidth, height: 5)
                                        .shadow(color: Color(red: 0.88, green: 0.40, blue: 0.0).opacity(0.9), radius: 3, x: 0, y: -1)
                                        .offset(y: -9)
                                }

                                // 2. Cerchiolini Ciano per la Geometria dell'accordo su TUTTE le ottave (più in alto a y = -17)
                                if clientService.showOctaveGeometryHints && isOctaveMatch {
                                    Circle()
                                        .fill(Color.cyan.opacity(0.9))
                                        .frame(width: 4.5, height: 4.5)
                                        .shadow(color: Color.cyan.opacity(0.7), radius: 2, x: 0, y: -1)
                                        .offset(y: -17)
                                }
                            }
                        }
                        .offset(x: xOffset, y: 14)
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { _ in
                                    if !clientService.isNoteActive(key.id) {
                                        clientService.sendNoteOn(midi: key.id)
                                    }
                                }
                                .onEnded { _ in
                                    clientService.sendNoteOff(midi: key.id)
                                }
                        )
                    }
                }
                .frame(width: totalKeyboardWidth, height: height)
            }
        }
        .frame(height: 145)
        .padding(8)
        .background(Color.black.opacity(0.4))
        .cornerRadius(12)
    }
}

// Estensione helper per angoli arrotondati specifici
extension View {
    func cornerRadius(_ radius: CGFloat, corners: RectCorner) -> some View {
        clipShape(RoundedCornerShape(radius: radius, corners: corners))
    }
}

struct RectCorner: OptionSet {
    let rawValue: Int
    static let topLeft = RectCorner(rawValue: 1 << 0)
    static let topRight = RectCorner(rawValue: 1 << 1)
    static let bottomLeft = RectCorner(rawValue: 1 << 2)
    static let bottomRight = RectCorner(rawValue: 1 << 3)
    static let allCorners: RectCorner = [.topLeft, .topRight, .bottomLeft, .bottomRight]
}

struct RoundedCornerShape: Shape {
    var radius: CGFloat = .infinity
    var corners: RectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let p1 = CGPoint(x: rect.minX, y: rect.minY)
        let p2 = CGPoint(x: rect.maxX, y: rect.minY)
        let p3 = CGPoint(x: rect.maxX, y: rect.maxY)
        let p4 = CGPoint(x: rect.minX, y: rect.maxY)

        path.move(to: p1)
        path.addLine(to: p2)
        if corners.contains(.bottomRight) {
            path.addArc(center: CGPoint(x: p3.x - radius, y: p3.y - radius), radius: radius, startAngle: Angle(degrees: 0), endAngle: Angle(degrees: 90), clockwise: false)
        } else {
            path.addLine(to: p3)
        }
        if corners.contains(.bottomLeft) {
            path.addArc(center: CGPoint(x: p4.x + radius, y: p4.y - radius), radius: radius, startAngle: Angle(degrees: 90), endAngle: Angle(degrees: 180), clockwise: false)
        } else {
            path.addLine(to: p4)
        }
        path.addLine(to: p1)

        return path
    }
}
