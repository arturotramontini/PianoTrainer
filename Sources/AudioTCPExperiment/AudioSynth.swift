import Foundation
import CAudioEngine

/// Wrapper Swift attorno al motore audio C nativo (audio.c / audio.h).
public final class AudioSynth {
    private var audioRunning: Bool = false

    public struct AudioTiming: Sendable {
        public var tPrev: Double = 0
        public var tStart: Double = 0
        public var tEnd: Double = 0
        public var duration: Double = 0
        public var frames: UInt32 = 0
        public var frameCounter: UInt32 = 0
        public var delta: Double = 0
    }

    public init() {
        CAudioEngine.setDefault()
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
        CAudioEngine.enqueueNoteOn(frequency, note, velocity)
    }

    public func enqueueNoteOff(note: UInt8, sustainOff: UInt32 = 0) {
        CAudioEngine.enqueueNoteOff(note, sustainOff)
    }

    public func startAudio() throws {
        CAudioEngine.startAudio()
        audioRunning = true
    }

    public func stopAudio() {
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
