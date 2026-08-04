import Foundation

public struct KeySignatureInfo: Equatable {
    public let keyNameItalian: String
    public let keyNameEnglish: String
    public let accidentalsTextItalian: String
    public let accidentalsTextEnglish: String
    public let scalePitchClasses: Set<UInt8> // I 7 toni (modulo 12) della tonalità

    public func displayName(isItalian: Bool) -> String {
        isItalian ? keyNameItalian : keyNameEnglish
    }

    public func displayAccidentals(isItalian: Bool) -> String {
        isItalian ? accidentalsTextItalian : accidentalsTextEnglish
    }
}

public struct KeySignatureUtility {
    /// Ricava le informazioni sulla Tonalità e sulle alterazioni in chiave relative ad un accordo
    public static func forChord(_ chord: ChordDefinition) -> KeySignatureInfo {
        let root = chord.rootMIDI % 12
        let isMinor = (chord.quality == .minor || chord.quality == .minor7)

        // Se l'accordo è minore, la sua tonalità relativa maggiore si trova 3 semitoni sopra (es: La minore -> Do Maggiore)
        let relativeMajorRoot = isMinor ? (root + 3) % 12 : root

        return forMajorKey(rootMIDI: relativeMajorRoot, isOriginallyMinor: isMinor, originalRootMIDI: chord.rootMIDI, preferFlat: chord.preferFlat)
    }

    /// Genera la KeySignatureInfo per una tonalità Maggiore o Minore
    public static func forMajorKey(rootMIDI: UInt8, isOriginallyMinor: Bool = false, originalRootMIDI: UInt8 = 60, preferFlat: Bool = false) -> KeySignatureInfo {
        let rootPC = rootMIDI % 12
        let origRootPC = originalRootMIDI % 12

        // Calcola i 7 pitch classes della scala
        let majorIntervals: [UInt8] = [0, 2, 4, 5, 7, 9, 11]
        let minorIntervals: [UInt8] = [0, 2, 3, 5, 7, 8, 10]
        
        let activeIntervals = isOriginallyMinor ? minorIntervals : majorIntervals
        let scalePitchClasses = Set(activeIntervals.map { (origRootPC + $0) % 12 })

        // Alterazioni in chiave ufficiali del circolo delle quinte (per tonalità maggiori)
        let keyData: [UInt8: (nameIt: String, nameEn: String, accIt: String, accEn: String)] = [
            0:  ("Do Magg.", "C Major", "Nessuna alterazione", "No accidentals"),
            7:  ("Sol Magg.", "G Major", "1 Diesis: Fa♯", "1 Sharp: F♯"),
            2:  ("Re Magg.", "D Major", "2 Diesis: Fa♯, Do♯", "2 Sharps: F♯, C♯"),
            9:  ("La Magg.", "A Major", "3 Diesis: Fa♯, Do♯, Sol♯", "3 Sharps: F♯, C♯, G♯"),
            4:  ("Mi Magg.", "E Major", "4 Diesis: Fa♯, Do♯, Sol♯, Re♯", "4 Sharps: F♯, C♯, G♯, D♯"),
            11: ("Si Magg.", "B Major", "5 Diesis: Fa♯, Do♯, Sol♯, Re♯, La♯", "5 Sharps: F♯, C♯, G♯, D♯, A♯"),
            6:  preferFlat ?
                    ("Sol♭ Magg.", "G♭ Major", "6 Bemolli: Si♭, Mi♭, La♭, Re♭, Sol♭, Do♭", "6 Flats: B♭, E♭, A♭, D♭, G♭, C♭") :
                    ("Fa♯ Magg.", "F♯ Major", "6 Diesis: Fa♯, Do♯, Sol♯, Re♯, La♯, Mi♯", "6 Sharps: F♯, C♯, G♯, D♯, A♯, E♯"),
            5:  ("Fa Magg.", "F Major", "1 Bemolle: Si♭", "1 Flat: B♭"),
            10: ("Si♭ Magg.", "B♭ Major", "2 Bemolli: Si♭, Mi♭", "2 Flats: B♭, E♭"),
            3:  ("Mi♭ Magg.", "E♭ Major", "3 Bemolli: Si♭, Mi♭, La♭", "3 Flats: B♭, E♭, A♭"),
            8:  ("La♭ Magg.", "A♭ Major", "4 Bemolli: Si♭, Mi♭, La♭, Re♭", "4 Flats: B♭, E♭, A♭, D♭"),
            1:  ("Re♭ Magg.", "D♭ Major", "5 Bemolli: Si♭, Mi♭, La♭, Re♭, Sol♭", "5 Flats: B♭, E♭, A♭, D♭, G♭")
        ]

        let data = keyData[rootPC] ?? ("Do Magg.", "C Major", "Nessuna alterazione", "No accidentals")

        if isOriginallyMinor {
            let origNameIt = NoteNameUtility.italianName(for: originalRootMIDI, preferFlat: preferFlat)
            let origNameEn = NoteNameUtility.englishName(for: originalRootMIDI, preferFlat: preferFlat)
            let minNameIt = "\(origNameIt) Minore (rel. \(data.nameIt))"
            let minNameEn = "\(origNameEn) Minor (rel. \(data.nameEn))"
            return KeySignatureInfo(
                keyNameItalian: minNameIt,
                keyNameEnglish: minNameEn,
                accidentalsTextItalian: data.accIt,
                accidentalsTextEnglish: data.accEn,
                scalePitchClasses: scalePitchClasses
            )
        } else {
            return KeySignatureInfo(
                keyNameItalian: data.nameIt,
                keyNameEnglish: data.nameEn,
                accidentalsTextItalian: data.accIt,
                accidentalsTextEnglish: data.accEn,
                scalePitchClasses: scalePitchClasses
            )
        }
    }
}
