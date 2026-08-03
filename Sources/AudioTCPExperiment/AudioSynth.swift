import Foundation
import AVFAudio

/// Wrapper Swift per il campionatore SoundFont SF2 (A320U.sf2).
public final class AudioSynth: @unchecked Sendable {
    public let sf2Engine: SF2SamplerEngine

    public init(sf2Path: String = "A320U.sf2") {
        self.sf2Engine = SF2SamplerEngine(sf2Path: sf2Path)
    }

    public func setSF2Program(_ program: UInt8) {
        sf2Engine.loadInstrument(program: program)
    }

    public func enqueueNoteOn(frequency: Double = 440.0, note: UInt8, velocity: Double, channel: UInt8 = 0) {
        sf2Engine.noteOn(note: note, velocity: UInt8(max(0, min(127, velocity))), channel: channel)
    }

    public func enqueueNoteOff(note: UInt8, channel: UInt8 = 0) {
        sf2Engine.noteOff(note: note, channel: channel)
    }

    public func startAudio() throws {
        sf2Engine.start()
    }

    public func stopAudio() {
        sf2Engine.stop()
    }

    public var isRunning: Bool {
        sf2Engine.isRunning
    }

    public var currentProgram: UInt8 {
        sf2Engine.currentProgram
    }
}

/// Frequenza della nota MIDI
public func midiNoteToFrequency(_ note: UInt8) -> Double {
    440.0 * pow(2.0, (Double(note) - 69.0) / 12.0)
}
