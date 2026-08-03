import Foundation
import CAudioEngine

/// Wrapper Swift attorno al motore audio C nativo ed al campionatore SoundFont SF2.
public final class AudioSynth: @unchecked Sendable {
    private var audioRunning: Bool = false
    public let sf2Engine: SF2SamplerEngine

    /// Modalità Suono: 0 = Motore C, 1 = Sampler SF2, 2 = Entrambi (Layer)
    public private(set) var soundMode: Int = 0

    public struct AudioTiming: Sendable {
        public var tPrev: Double = 0
        public var tStart: Double = 0
        public var tEnd: Double = 0
        public var duration: Double = 0
        public var frames: UInt32 = 0
        public var frameCounter: UInt32 = 0
        public var delta: Double = 0
    }

    public init(sf2Path: String = "A320U.sf2") {
        self.sf2Engine = SF2SamplerEngine(sf2Path: sf2Path)
        CAudioEngine.setDefault()
    }

    public func setSoundMode(_ mode: Int) {
        let clamped = max(0, min(2, mode))
        self.soundMode = clamped
        print("[\u{001B}[36mi\u{001B}[0m] Modalità Suono impostata a: \(soundModeName(clamped))")
    }

    public func soundModeName(_ mode: Int) -> String {
        switch mode {
        case 0: return "Motore C Custom"
        case 1: return "Sampler SoundFont SF2"
        case 2: return "Entrambi / Layer"
        default: return "Sconosciuto"
        }
    }

    public func setSF2Program(_ program: UInt8) {
        sf2Engine.loadInstrument(program: program)
    }

    public func setDefault() {
        CAudioEngine.setDefault()
    }

    public func setValue1(_ index: UInt32, _ value: Double) {
        CAudioEngine.setValue1(index, value)
    }

    public func getValue1(_ index: UInt32) -> Double {
        return CAudioEngine.getValue1(index)
    }

    public func enqueueNoteOn(frequency: Double, note: UInt8, velocity: Double) {
        if soundMode == 0 || soundMode == 2 {
            CAudioEngine.enqueueNoteOn(frequency, note, velocity)
        }
        if soundMode == 1 || soundMode == 2 {
            sf2Engine.noteOn(note: note, velocity: UInt8(max(0, min(127, velocity))))
        }
    }

    public func enqueueNoteOff(note: UInt8, sustainOff: UInt32 = 0) {
        if soundMode == 0 || soundMode == 2 {
            CAudioEngine.enqueueNoteOff(note, sustainOff)
        }
        if soundMode == 1 || soundMode == 2 {
            sf2Engine.noteOff(note: note)
        }
    }

    public func startAudio() throws {
        CAudioEngine.startAudio()
        sf2Engine.start()
        audioRunning = true
    }

    public func stopAudio() {
        sf2Engine.stop()
        audioRunning = false
    }

    public var isRunning: Bool { audioRunning }

    public func getFrames() -> UInt32 {
        return CAudioEngine.getFrames()
    }

    public func getHostTime() -> UInt64 {
        return CAudioEngine.getHostTime()
    }

    public func getSampleTime() -> Double {
        return CAudioEngine.getSampleTime()
    }

    public func getOutputBuffer(count: Int) -> [Float] {
        let size = max(0, min(count, 256))
        var buffer = [Float](repeating: 0, count: size)
        CAudioEngine.getOutputBuffer(&buffer, Int32(size))
        return buffer
    }

    public func getInputBuffer(count: Int) -> [Float] {
        let size = max(0, min(count, 256))
        var buffer = [Float](repeating: 0, count: size)
        CAudioEngine.getInputBuffer(&buffer, Int32(size))
        return buffer
    }

    public func getTmax() -> Double {
        return CAudioEngine.getTmax()
    }

    public func getLastTiming() -> AudioTiming {
        let t = CAudioEngine.getLastTiming()
        return AudioTiming(
            tPrev: t.t_prev,
            tStart: t.t_start,
            tEnd: t.t_end,
            duration: t.duration,
            frames: t.frames,
            frameCounter: t.frameCounter,
            delta: t.delta
        )
    }
}

/// Frequenza della nota MIDI
public func midiNoteToFrequency(_ note: UInt8) -> Double {
    440.0 * pow(2.0, (Double(note) - 69.0) / 12.0)
}
