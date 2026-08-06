import Foundation

/// Extension helper per l'accesso sicuro agli elementi di una collezione tramite indice
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Generator for Standard MIDI Files (.mid) from BUILDMIDI text score format.
/// 100% compatibile con la sintassi ed i risultati del progetto BUILDMIDI_2.
public enum BuildMidiGenerator {

    public struct Event {
        public var tick: Int
        public var track: Int
        public var kind: Int
        public var pitch: Int
        public var vel: Int
        public var canale: Int
        public var text: String
        public var data: [UInt8]
    }

    public final class MidiBuilder {
        let ticksPerQuarter = 480
        var ticksPerBar: Int { ticksPerQuarter * 4 }

        let noteIndex: [String: Int] = [
            "do": 0, "do#": 1,
            "re": 2, "re#": 3,
            "mi": 4,
            "fa": 5, "fa#": 6,
            "sol": 7, "sol#": 8,
            "so": 7, "so#": 8,
            "la": 9, "la#": 10,
            "si": 11,

            "c": 0, "c#": 1,
            "d": 2, "d#": 3,
            "e": 4,
            "f": 5, "f#": 6,
            "g": 7, "g#": 8,
            "a": 9, "a#": 10,
            "b": 11, "bb": 10
        ]

        let drumName: [Int: String] = [
            45: "BD 45 (A1): Low Tom",
            43: "BD 43 (G1): High Floor Tom",
            41: "BD 41 (F1): Low Floor Tom",
            36: "BD 36 (C1): Bass Drum 1",
            35: "BD 35 (B0): Acoustic Bass Drum",
            37: "SH 37 (C#1): Side Stick",
            39: "SH 39 (Eb1): Hand Clap",
            40: "SH 40 (E1): Electric Snare",
            38: "SH 38 (D1): Acoustic Snare",
            59: "HH 59 (B2): Ride Cymbal 2",
            51: "HH 51 (Eb2): Ride Cymbal 1",
            57: "HH 57 (A2): Crash Cymbal 2",
            49: "HH 49 (C#2): Crash Cymbal 1",
            46: "HH 46 (Bb1): Open Hi-Hat",
            44: "HH 44 (Ab1): Pedal Hi-Hat",
            42: "HH 42 (F#1): Closed Hi-Hat",
            66: "LP 66 (F#3): Low Timbale",
            65: "LP 65 (F3): High Timbale",
            64: "LP 64 (E3): Low Conga",
            63: "LP 63 (Eb3): Open Hi Conga",
            62: "LP 62 (D3): Mute Hi Conga",
            61: "LP 61 (C#3): Low Bongo",
            60: "LP 60 (C3): Hi Bongo",
            80: "OE 80 (Ab4): Mute Triangle",
            79: "OE 79 (G4): Open Cuica",
            78: "OE 78 (F#4): Mute Cuica",
            77: "OE 77 (F4): Low Wood Block",
            76: "OE 76 (E4): Hi Wood Block",
            75: "OE 75 (Eb4): Claves",
            74: "OE 74 (D4): Long Guiro",
            73: "OE 73 (C#4): Short Guiro",
            72: "OE 72 (C4): Long Whistle",
            71: "OE 71 (B3): Short Whistle",
            70: "OE 70 (Bb3): Maracas",
            58: "OE 58 (Bb2): Vibraslap",
            56: "OE 56 (Ab2): Cowbell",
            55: "OE 55 (G2): Splash Cymbal"
        ]

        let velMap: [Character: Int] = [
            "0": 0, "1": 1, "2": 2, "3": 3, "4": 4,
            "5": 5, "6": 6, "7": 7, "8": 8, "9": 9
        ]

        var startTick = 0
        var durTicks = 0
        var absStart = 0
        var absEnd = 0

        var delayArpeggio = 1.0
        var revert = 0

        var canale = 0
        var events: [Event] = []

        var bar = 1
        var traccia = 1
        var battuta = 0

        var prevStart = 0.0
        var prevDur = 0.0

        var velocity: UInt8 = 127

        var drum_ticks = 2
        var drum_type = 60

        var drumStart = 0
        var drumBarRepeats = 1
        var divisions = 0.0

        var mappa: [String: [String]] = [
            "60": ["60"],
            "m0": ["36", "48"],
            "m1": ["46", "63"],
            "75": ["75"]
        ]
        var instruments: [Int] = [60]

        public init() {}

        public func generateMIDI(from rawText: String, midURL: URL) throws {
            events.removeAll()
            bar = 1
            traccia = 1
            battuta = 0
            prevStart = 0.0
            prevDur = 0.0
            velocity = 127
            delayArpeggio = 1.0

            parseScore(rawText)
            try writeOutputs(midURL: midURL)
        }

        private func getByteValue(_ h: String) -> UInt8 {
            if h.first == "<" {
                let body = String(h.dropFirst())
                guard let value = UInt8(body, radix: 10) else { return 0 }
                return value
            }
            guard let value = UInt8(h, radix: 16) else { return 0 }
            return value
        }

        private func hex(_ c: Character) -> Int {
            Int(String(c), radix: 16) ?? -1
        }

        private func midiNote(_ name: String, _ oct: Int) -> Int {
            let idx = noteIndex[name.lowercased()] ?? 0
            return (oct + 1) * 12 + idx
        }

        private func writeVLQ(_ data: inout Data, _ value: Int) {
            var v = value
            var stack: [UInt8] = [UInt8(v & 0x7F)]
            v >>= 7
            while v > 0 {
                stack.append(UInt8((v & 0x7F) | 0x80))
                v >>= 7
            }
            for byte in stack.reversed() {
                data.append(byte)
            }
        }

        private func writeEvent(_ track: inout Data, _ payload: [UInt8]) {
            track.append(contentsOf: payload)
        }

        private func writeNoteOn(_ track: inout Data, delta: Int, pitch: Int, velocity: Int, channel: Int) {
            var tmp = Data()
            writeVLQ(&tmp, delta)
            tmp.append(UInt8(0x90 | (channel & 0x0F)))
            tmp.append(UInt8(pitch & 0x7F))
            tmp.append(UInt8(velocity & 0x7F))
            writeEvent(&track, Array(tmp))
        }

        private func writeNoteOff(_ track: inout Data, delta: Int, pitch: Int, channel: Int) {
            var tmp = Data()
            writeVLQ(&tmp, delta)
            tmp.append(UInt8(0x80 | (channel & 0x0F)))
            tmp.append(UInt8(pitch & 0x7F))
            tmp.append(0)
            writeEvent(&track, Array(tmp))
        }

        private func writeDirect(_ track: inout Data, delta: Int, data: [UInt8]) {
            var tmp = Data()
            writeVLQ(&tmp, delta)
            tmp.append(contentsOf: data)
            writeEvent(&track, Array(tmp))
        }

        private func writeMarker(_ track: inout Data, delta: Int, text: String) {
            var tmp = Data()
            writeVLQ(&tmp, delta)
            tmp.append(contentsOf: [0xFF, 0x06, UInt8(text.count)])
            tmp.append(contentsOf: Array(text.utf8))
            writeEvent(&track, Array(tmp))
        }

        private func writeTrack(_ output: FileHandle, events: [Event]) throws {
            var track = Data()
            var currentTick = 0

            for event in events {
                let delta = max(0, event.tick - currentTick)
                currentTick = event.tick

                switch event.kind {
                case 1:
                    writeNoteOn(&track, delta: delta, pitch: event.pitch, velocity: event.vel, channel: event.canale)
                case 0:
                    writeNoteOff(&track, delta: delta, pitch: event.pitch, channel: event.canale)
                case 6:
                    writeMarker(&track, delta: delta, text: event.text)
                case 3:
                    writeDirect(&track, delta: delta, data: event.data)
                default:
                    break
                }
            }

            writeVLQ(&track, 0)
            track.append(contentsOf: [0xFF, 0x2F, 0x00])

            try output.write(contentsOf: Data("MTrk".utf8))
            try output.write(contentsOf: be32(UInt32(track.count)))
            try output.write(contentsOf: track)
        }

        private func parseScore(_ rawText: String) {
            var startF = 0.0
            var durF = 0.0
            var skipAllFlag = false
            var linea = 0

            for rawLine in rawText.components(separatedBy: .newlines) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                linea += 1

                if line.isEmpty || line.first == "#" || skipAllFlag { continue }

                let fields = line.split(whereSeparator: \.isWhitespace).map(String.init)
                if fields.isEmpty { continue }

                if handleScoreCommand(fields, lineNumber: linea, skipAllFlag: &skipAllFlag, startF: &startF) {
                    continue
                }

                guard let timing = parseTiming(fields) else { continue }
                startF = timing.start
                durF = timing.duration
                applyTiming(startF: startF, durF: durF)

                if fields.count > 2 {
                    handlePitchedNotes(fields, durF: durF)
                }
            }
        }

        private func handleScoreCommand(_ fields: [String], lineNumber: Int, skipAllFlag: inout Bool, startF: inout Double) -> Bool {
            if ["comment", "com", "commento"].contains(fields[0]) { return true }
            if ["exit", "end", "stop"].contains(fields[0]) {
                skipAllFlag = true
                return true
            }
            if handleDrumCommand(fields) { return true }
            if handleGlobalStateCommand(fields, startF: &startF) { return true }
            if handleMetaCommand(fields) { return true }
            return false
        }

        private func handleDrumCommand(_ fields: [String]) -> Bool {
            if ["d_division", "d_div", "ddiv"].contains(fields[0]) {
                divisions = Double(fields[safe: 1] ?? "") ?? 4.0
                drum_ticks = Int(divisions)
                return true
            }

            if fields[0] == "offset" {
                divisions = Double(fields[safe: 1] ?? "") ?? 0.0
                return true
            }

            if fields[0] == "drum" {
                drum_type = Int(fields[safe: 1] ?? "") ?? 60
                return true
            }

            if fields[0] == "dmsetadd" {
                if let name = fields[safe: 1] {
                    for value in fields.dropFirst(2) {
                        mappa[name, default: []].append(value)
                    }
                }
                return true
            }

            if ["d_map_set", "dmset", "d_def_index_instruments"].contains(fields[0]) {
                if let name = fields[safe: 1] {
                    mappa[name] = []
                    for value in fields.dropFirst(2) {
                        mappa[name, default: []].append(value)
                    }
                }
                return true
            }

            if ["dmap", "dm", "d_get_index_instruments"].contains(fields[0]) {
                instruments = []
                let index = fields.count >= 2 ? fields[1] : "60"
                let values = mappa[index] ?? []
                for value in values {
                    if let parsed = Int(value) {
                        instruments.append(parsed)
                    }
                }
                return true
            }

            if ["dstart", "ds", "d_beat_start"].contains(fields[0]), let mask = fields[safe: 1] {
                var pos = 0
                var value = ticksPerBar / 2
                for ch in mask {
                    if ch == "1" { pos += value }
                    value /= 2
                }
                drumStart = battuta * ticksPerBar + pos
                return true
            }

            if ["dbr", "dbrepeats"].contains(fields[0]) {
                drumBarRepeats = Int(fields[safe: 1] ?? "") ?? 1
                return true
            }

            if fields[0] == "d" {
                handleDrum(fields)
                return true
            }

            return false
        }

        private func handleDrum(_ fields: [String]) {
            var ps = ""
            var drum = drum_type
            var dmode = 0

            for (index, value) in fields.enumerated() {
                if index == 1, value.first == "p" {
                    dmode = 1
                    drum = Int(value.dropFirst()) ?? 61
                    drum_type = drum
                    instruments = [drum]
                    continue
                }
                if index > dmode {
                    ps.append(contentsOf: value)
                }
            }

            let start = drumStart

            for (idx, val) in ps.enumerated() {
                let s1 = start + idx * ticksPerBar / max(drum_ticks, 1)
                drumStart = s1
                let velo = Int(velocity)
                let start1 = s1
                let end1 = start1 + 24

                for n in 0..<max(drumBarRepeats, 0) {
                    let sr = start1 + n * ticksPerBar
                    let er = end1 + n * ticksPerBar

                    if val == "-" {
                        for instrument in instruments {
                            events.append(Event(tick: sr, track: 10, kind: 1, pitch: instrument, vel: velo, canale: 9, text: "aa", data: []))
                            events.append(Event(tick: er, track: 10, kind: 0, pitch: instrument, vel: 0, canale: 9, text: "bb", data: []))
                        }
                    }

                    if val == "." {
                        for instrument in instruments {
                            events.append(Event(tick: sr, track: 10, kind: 1, pitch: instrument, vel: 0, canale: 9, text: "aa", data: []))
                            events.append(Event(tick: er, track: 10, kind: 0, pitch: instrument, vel: 0, canale: 9, text: "bb", data: []))
                        }
                    }
                }

                if let mapValue = velMap[val] {
                    let scaled = Double(Int(velocity)) * (Double(mapValue) / 9.0)
                    for n in 0..<max(drumBarRepeats, 0) {
                        let sr = start1 + n * ticksPerBar
                        let er = end1 + n * ticksPerBar
                        for instrument in instruments {
                            events.append(Event(tick: sr, track: 10, kind: 1, pitch: instrument, vel: Int(scaled), canale: 9, text: "aa", data: []))
                            events.append(Event(tick: er, track: 10, kind: 0, pitch: instrument, vel: 0, canale: 9, text: "bb", data: []))
                        }
                    }
                }
            }

            drumStart += ticksPerBar / max(drum_ticks, 1)
        }

        private func handleGlobalStateCommand(_ fields: [String], startF: inout Double) -> Bool {
            if ["canale", "channel"].contains(fields[0]) {
                var t = Int(fields[safe: 1] ?? "") ?? 1
                t = max(1, min(16, t))
                canale = (t - 1) & 0xF
                return true
            }

            if ["traccia", "track"].contains(fields[0]) {
                traccia = (Int(fields[safe: 1] ?? "") ?? 1) & 0xFF
                return true
            }

            if fields[0] == "revert" {
                revert = (Int(fields[safe: 1] ?? "") ?? 0) == 0 ? 0 : 1
                return true
            }

            if fields[0] == "delayarp" {
                guard let token = fields[safe: 1] else { return true }
                var n = 0.0
                if token.first == ".", token.count >= 3 {
                    let chars = Array(token)
                    let v = (hex(chars[1]) << 4) | hex(chars[2])
                    n = Double(v) / 256.0
                } else {
                    n = Double(token) ?? 0.0
                    n = Double(n) / 256.0
                }
                n = n.truncatingRemainder(dividingBy: 2)
                n = max(-2, min(2, n))
                delayArpeggio = n
                return true
            }

            if ["battuta", "bar"].contains(fields[0]) {
                if let token = fields[safe: 1], token.first == "+" {
                    battuta += 1
                } else {
                    bar = max(1, Int(fields[safe: 1] ?? "") ?? 1)
                    battuta = bar - 1
                }
                drumStart = battuta * ticksPerBar
                startF = 0
                absStart = battuta * ticksPerBar
                return true
            }

            if ["velocity", "vel"].contains(fields[0]) {
                velocity = getByteValue(fields[safe: 1] ?? "7F")
                return true
            }

            return false
        }

        private func handleMetaCommand(_ fields: [String]) -> Bool {
            if ["direct", "midi_direct"].contains(fields[0]) {
                var data: [UInt8] = []
                for token in fields.dropFirst() {
                    if token.first == "#" { break }
                    let value = getByteValue(token)
                    data.append(value)
                }
                events.append(Event(tick: absStart, track: traccia, kind: 3, pitch: 0, vel: 0, canale: 0, text: "", data: data))
                return true
            }

            if fields[0] == "bpm" {
                guard let bpmValue = Double(fields[safe: 1] ?? "") else { return true }
                let microsecondsPerQuarter = Int(60000000.0 / bpmValue)
                let v1 = UInt8(microsecondsPerQuarter & 0xFF)
                let v2 = UInt8((microsecondsPerQuarter >> 8) & 0xFF)
                let v3 = UInt8((microsecondsPerQuarter >> 16) & 0xFF)
                let data: [UInt8] = [0xff, 0x51, 0x03, v3, v2, v1]
                events.append(Event(tick: absStart, track: traccia, kind: 3, pitch: 0, vel: 0, canale: 0, text: "", data: data))
                return true
            }

            return false
        }

        private func parseTiming(_ fields: [String]) -> (start: Double, duration: Double)? {
            guard fields.count >= 2 else { return nil }

            let startF: Double
            switch fields[0].first! {
            case "=": startF = prevStart
            case "+": startF = prevStart + prevDur
            case ".":
                let chars = Array(fields[0])
                let v = (hex(chars[1]) << 4) | hex(chars[2])
                startF = Double(v) / 256.0
            default:
                startF = Double(fields[0]) ?? 0.0
            }

            let durationToken = normalizeDurationToken(fields[1])
            var durF = Double(durationToken) ?? 0.0
            if fields[1].first == ".", fields[1].count >= 3 {
                let chars = Array(fields[1])
                let v = (hex(chars[1]) << 4) | hex(chars[2])
                durF = Double(v) / 256.0
            }

            return (startF, durF)
        }

        private func normalizeDurationToken(_ token: String) -> String {
            switch token {
            case "=": return "\(prevDur)"
            case "w": return "1.0"
            case "h": return "0.5"
            case "h.": return "0.75"
            case "h..": return "0.875"
            case "q": return "0.25"
            case "q.": return "0.375"
            case "q..": return "0.4375"
            case "o": return "0.125"
            case "o.": return "0.1875"
            case "o..": return "0.21875"
            case "s": return "0.0625"
            case "s.": return "\(1.0 / 16.0 + 1.0 / 32.0)"
            case "t": return "\(1.0 / 32.0)"
            case "x": return "\(1.0 / 64.0)"
            case "y": return "\(1.0 / 128.0)"
            default: return token
            }
        }

        private func applyTiming(startF: Double, durF: Double) {
            let offset = Int(startF * Double(ticksPerBar))
            absStart = battuta * ticksPerBar + offset
            durTicks = Int(durF * Double(ticksPerBar))
            absEnd = absStart + durTicks
            prevStart = startF
            prevDur = durF
        }

        private func handlePitchedNotes(_ fields: [String], durF: Double) {
            var s = fields[2]
            if let first = s.first, first == "#" || first == "p" || first == "-" {
                return
            }

            if s.first != "n" {
                var i = 2
                while i + 1 < fields.count {
                    let name = fields[i]
                    guard let oct = Int(fields[i + 1]) else { return }
                    let pitch = midiNote(name, oct)
                    events.append(Event(tick: absStart, track: traccia, kind: 1, pitch: pitch, vel: Int(velocity), canale: canale, text: "", data: []))
                    events.append(Event(tick: absEnd, track: traccia, kind: 0, pitch: pitch, vel: Int(velocity), canale: canale, text: "", data: []))
                    prevDur = durF
                    i += 2
                }
            }

            s = fields[2]
            if s.first != "n" { return }

            if fields.count > 3 {
                for extra in fields.dropFirst(3) {
                    s += extra
                }
            }

            var note: [Int] = []
            if Array(s)[safe: 1] == "<" {
                let chars = Array(s)
                var sn = "\(chars[safe: 2] ?? "0")\(chars[safe: 3] ?? "0")"
                var s0 = String(chars.dropFirst(4))
                if chars[safe: 2] == "1" {
                    sn += String(chars[safe: 4] ?? "0")
                    s0 = String(chars.dropFirst(5))
                }
                s = s0
                let v = Int(sn) ?? 0
                let ottava = (v / 12) - 1
                let nota = v % 12
                s = "n\(ottava)\(String(nota, radix: 16).uppercased())\(s)"
            }

            let chars = Array(s)
            guard chars.count >= 3 else { return }
            let o = hex(chars[1])
            var i = hex(chars[2])
            if i > 15 { i = 15 }

            var nota = (o + 1) * 12 + i
            note.append(nota)

            if s.count <= 3 {
                events.append(Event(tick: absStart, track: traccia, kind: 1, pitch: nota, vel: Int(velocity), canale: canale, text: "", data: []))
                events.append(Event(tick: absEnd, track: traccia, kind: 0, pitch: nota, vel: Int(velocity), canale: canale, text: "", data: []))
                prevDur = durF
            } else {
                if revert == 0 {
                    for n in 3..<chars.count {
                        let delta = hex(chars[n])
                        let index = n - 3
                        nota = note[index] + delta
                        note.append(nota)
                    }
                } else {
                    for n in 3..<chars.count {
                        let delta = hex(chars[n])
                        let index = n - 3
                        nota = note[index] - delta
                        note.append(nota)
                    }
                }

                var delay = delayArpeggio
                let orderedNotes: [Int]
                if delay < 0 {
                    delay *= -1
                    orderedNotes = note.reversed()
                } else {
                    orderedNotes = note
                }

                let q = delay * Double(ticksPerQuarter * 4)

                for (index, currentNote) in orderedNotes.enumerated() {
                    if currentNote == 0 { continue }
                    let noteStart = Int(Double(absStart) + Double(index) * q)
                    let noteEnd = noteStart + durTicks

                    events.append(Event(tick: noteStart, track: traccia, kind: 1, pitch: currentNote, vel: Int(velocity), canale: canale, text: "", data: []))
                    events.append(Event(tick: noteEnd, track: traccia, kind: 0, pitch: currentNote, vel: Int(velocity), canale: canale, text: "", data: []))
                }

                prevDur = durF + Double(max(orderedNotes.count - 1, 0)) * delay
            }
        }

        private func writeOutputs(midURL: URL) throws {
            var tracks: [Int: [Event]] = [:]
            for event in events {
                tracks[event.track, default: []].append(event)
            }

            FileManager.default.createFile(atPath: midURL.path, contents: nil)
            guard let output = FileHandle(forWritingAtPath: midURL.path) else {
                throw NSError(domain: "BuildMidiGenerator", code: 1, userInfo: [NSLocalizedDescriptionKey: "Impossibile creare file MIDI a \(midURL.path)"])
            }
            defer { try? output.close() }

            try output.write(contentsOf: Data("MThd".utf8))
            try output.write(contentsOf: be32(6))
            try output.write(contentsOf: be16(1))
            try output.write(contentsOf: be16(UInt16(tracks.count)))
            try output.write(contentsOf: be16(UInt16(ticksPerQuarter)))

            for key in tracks.keys.sorted() {
                try writeTrack(output, events: tracks[key] ?? [])
            }
        }

        private func be16(_ value: UInt16) -> Data {
            var big = value.bigEndian
            return Data(bytes: &big, count: MemoryLayout<UInt16>.size)
        }

        private func be32(_ value: UInt32) -> Data {
            var big = value.bigEndian
            return Data(bytes: &big, count: MemoryLayout<UInt32>.size)
        }
    }

    public static func generateMIDI(from text: String, midURL: URL) throws {
        let builder = MidiBuilder()
        try builder.generateMIDI(from: text, midURL: midURL)
    }
}
