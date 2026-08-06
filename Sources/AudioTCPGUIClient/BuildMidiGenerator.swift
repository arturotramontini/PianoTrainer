import Foundation

/// Extension helper per l'accesso sicuro agli elementi di una collezione tramite indice
extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

/// Generator for Standard MIDI Files (.mid) from BUILDMIDI text score format.
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
            if handleGlobalStateCommand(fields, startF: &startF) { return true }
            if handleMetaCommand(fields) { return true }
            return false
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
            var note: [Int] = []
            var nota = 0

            for token in fields.dropFirst(2) {
                if token.first == "#" { break }
                let (pitchName, oct) = parseNoteToken(token)
                nota = midiNote(pitchName, oct)
                note.append(nota)
            }

            if fields.count <= 3 || note.isEmpty {
                events.append(Event(tick: absStart, track: traccia, kind: 1, pitch: nota, vel: Int(velocity), canale: canale, text: "", data: []))
                events.append(Event(tick: absEnd, track: traccia, kind: 0, pitch: nota, vel: Int(velocity), canale: canale, text: "", data: []))
            } else {
                let delay = delayArpeggio
                let orderedNotes = (delay < 0) ? note.reversed() : note
                let q = abs(delay) * Double(ticksPerBar)

                for (index, currentNote) in orderedNotes.enumerated() {
                    if currentNote == 0 { continue }
                    let noteStart = Int(Double(absStart) + Double(index) * q)
                    let noteEnd = noteStart + durTicks

                    events.append(Event(tick: noteStart, track: traccia, kind: 1, pitch: currentNote, vel: Int(velocity), canale: canale, text: "", data: []))
                    events.append(Event(tick: noteEnd, track: traccia, kind: 0, pitch: currentNote, vel: Int(velocity), canale: canale, text: "", data: []))
                }
            }
        }

        private func parseNoteToken(_ token: String) -> (name: String, oct: Int) {
            var name = ""
            var octStr = ""

            for ch in token {
                if ch.isNumber || (ch == "-" && name.isEmpty) {
                    octStr.append(ch)
                } else {
                    name.append(ch)
                }
            }

            let oct = Int(octStr) ?? 4
            return (name.isEmpty ? "c" : name, oct)
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
