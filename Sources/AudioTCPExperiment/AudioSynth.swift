//
//  AudioSynth.swift
//
//  Modulo di sintesi e acquisizione audio per macOS.
//  Può essere aggiunto sia a un programma Swift + GLFW sia a un'app SwiftUI.
//
//  Richiede macOS 13 o successivo.
//  Per usare il microfono l'app ospitante deve avere in Info.plist:
//      NSMicrophoneUsageDescription = "..."
//

import AVFAudio
import AudioToolbox
import Foundation
import os

/// Versione Swift, pensata per esperimenti, del file `audio.c` ricevuto.
///
/// I nomi principali sono deliberatamente simili al C: `startAudio`,
/// `enqueueNoteOn`, `enqueueNoteOff`, `setValue1`, `getOutputBuffer`, ecc.
/// Creare e controllare questa classe dal thread principale; la generazione
/// dei campioni avviene invece nel thread audio gestito da AVAudioEngine.
public final class AudioSynth {
	public static let maxNotes = 64
	public static let sampleRate = 44_100.0
	public static let inputBufferSize = 65_536
	public static let outputBufferSize = 65_536

	public struct AudioTiming: Sendable {
		public var tPrev: Double = 0
		public var tStart: Double = 0
		public var tEnd: Double = 0
		public var duration: Double = 0
		public var frames: UInt32 = 0
		public var frameCounter: UInt32 = 0
		public var delta: Double = 0
	}

	private struct Note {
		var frequency: Double = 0
		var phases = Array(repeating: 0.0, count: 7)
		var time: Double = 0
		var state: Int = 0  // 0 = spenta, 1 = on, 2 = release
		var releaseTime: Double = 0
		var releaseStartEnvelope: Double = 0
		var currentEnvelope: Double = 0
		var velocity: Double = 0
		var envelopeSmooth: Double = 0
		var midiNote: UInt8 = 0
		var sustainOff: UInt32 = 0
	}

	private enum EventType { case noteOn, noteOff }
	private struct Event {
		var type: EventType
		var frequency: Double = 0
		var note: UInt8
		var velocity: Double = 0
		var sustainOff: UInt32 = 0
	}

	// AVAudioEngine è la parte Apple che sostituisce i due HALOutput del C.
	private let engine = AVAudioEngine()
	private var sourceNode: AVAudioSourceNode?
	private var inputTapInstalled = false

	// Lo stato musicale appartiene esclusivamente al callback di output.
	private var notes = Array(repeating: Note(), count: AudioSynth.maxNotes)
	private var voiceIndex = 0
	private var lowPassY = 0.0
	private var lowPassAlpha = 0.0

	// Il controllo arriva dai callback GLFW / SwiftUI; questa coda è breve.
	// Per un sintetizzatore definitivo la si potrà sostituire con una SPSC
	// lock-free basata su atomiche. Per i programmi di prova è più semplice e
	// sicura da comprendere.
	private let eventLock = OSAllocatedUnfairLock(initialState: [Event]())
	private let parameterLock = OSAllocatedUnfairLock(initialState: Array(repeating: 0.0, count: 256))
	private let monitorLock = OSAllocatedUnfairLock(initialState: MonitorState())

	private struct MonitorState {
		var inputRing = Array(repeating: Float.zero, count: AudioSynth.inputBufferSize)
		var outputRing = Array(repeating: Float.zero, count: AudioSynth.outputBufferSize)
		var inputWriteIndex = 0
		var outputWriteIndex = 0
		var frames: UInt32 = 0
		var hostTime: UInt64 = 0
		var sampleTime: Double = 0
		var lastTiming = AudioTiming()
		var maximumRenderTime = 0.0
	}

	public init() {
		setDefault()
	}

	deinit { stopAudio() }

	// MARK: - Public API, intentionally close to audio.c

	public func setDefault() {
		parameterLock.withLock { p in
			p = Array(repeating: 0.0, count: 256)
			p[1] = 1.5  // sustain globale: alto = rilascio rapido
			p[2] = 7.83  // frequenza modulazione in Hz
			p[3] = 0.02  // profondità modulazione
			p[4] = 20.0  // volume finale
			p[5] = 90.0
			p[10] = 0.0  // trasposizione, lasciata al programma ospitante
		}
	}

	public func setValue1(_ index: UInt32, _ value: Double) {
		let i = min(Int(index), 255)
		parameterLock.withLock { $0[i] = value }
	}

	public func getValue1(_ index: UInt32) -> Double {
		let i = min(Int(index), 255)
		return parameterLock.withLock { $0[i] }
	}

	public func enqueueNoteOn(frequency: Double, note: UInt8, velocity: Double) {
		eventLock.withLock { events in
			// Come MAX_EVENTS=256 del C: in caso di pieno scartiamo il nuovo evento.
			guard events.count < 255 else { return }
			events.append(Event(type: .noteOn, frequency: frequency, note: note, velocity: velocity))
		}
	}

	public func enqueueNoteOff(note: UInt8, sustainOff: UInt32 = 0) {
		eventLock.withLock { events in
			guard events.count < 255 else { return }
			events.append(Event(type: .noteOff, note: note, sustainOff: sustainOff))
		}
	}

	/// Avvia sintetizzatore e tap del microfono. Può lanciare un errore, per
	/// esempio se il microfono non è autorizzato o non è disponibile.
	public func startAudio() throws {
		guard !engine.isRunning else { return }

		let synthFormat = AVAudioFormat(standardFormatWithSampleRate: Self.sampleRate, channels: 1)!
		let node = AVAudioSourceNode {
			[weak self] _, timeStamp, frameCount, audioBufferList -> OSStatus in
			guard let self else { return noErr }
			self.render(
				timeStamp: timeStamp.pointee, frameCount: Int(frameCount), audioBufferList: audioBufferList)
			return noErr
		}
		sourceNode = node
		engine.attach(node)
		engine.connect(node, to: engine.mainMixerNode, format: synthFormat)

		let input = engine.inputNode
		input.installTap(onBus: 0, bufferSize: 1_024, format: nil) { [weak self] buffer, _ in
			self?.captureInput(buffer)
		}
		inputTapInstalled = true

		try engine.start()
	}

	public func stopAudio() {
		if inputTapInstalled {
			engine.inputNode.removeTap(onBus: 0)
			inputTapInstalled = false
		}
		engine.stop()
		if let node = sourceNode {
			engine.disconnectNodeInput(node)
			engine.detach(node)
			sourceNode = nil
		}
	}

	public var isRunning: Bool { engine.isRunning }
	public func getFrames() -> UInt32 { monitorLock.withLock { $0.frames } }
	public func getHostTime() -> UInt64 { monitorLock.withLock { $0.hostTime } }
	public func getSampleTime() -> Double { monitorLock.withLock { $0.sampleTime } }

	public func getLastTiming() -> AudioTiming {
		monitorLock.withLock { state in
			var t = state.lastTiming
			t.delta = ProcessInfo.processInfo.systemUptime - t.tStart
			return t
		}
	}

	/// Restituisce gli ultimi `count` campioni, dal meno recente al più recente.
	public func getOutputBuffer(count: Int) -> [Float] {
		copyRing(count: count, input: false)
	}

	/// Restituisce gli ultimi `count` campioni del microfono.
	public func getInputBuffer(count: Int) -> [Float] {
		copyRing(count: count, input: true)
	}

	/// Come `getTmax()` nel C: restituisce e poi azzera il massimo tempo di render.
	public func getTmax() -> Double {
		monitorLock.withLock { state in
			let value = state.maximumRenderTime
			state.maximumRenderTime = 0
			return value
		}
	}

	// MARK: - Audio callback

	private func render(
		timeStamp: AudioTimeStamp, frameCount: Int,
		audioBufferList: UnsafeMutablePointer<AudioBufferList>
	) {
		let started = ProcessInfo.processInfo.systemUptime
		let parameters = parameterLock.withLock { $0 }
		processEvents()

		let bufferList = UnsafeMutableAudioBufferListPointer(audioBufferList)
		let outputBuffers = bufferList.compactMap { buffer -> UnsafeMutablePointer<Float>? in
			guard let data = buffer.mData else { return nil }
			return data.assumingMemoryBound(to: Float.self)
		}
		guard !outputBuffers.isEmpty else { return }

		let dt = 1.0 / Self.sampleRate
		let envelopeAlpha = 1.0 - exp(-dt / 0.002)
		let cutoff: Double = 400
		lowPassAlpha = 1.0 - exp(-2.0 * .pi * cutoff / Self.sampleRate)

		for i in 0..<frameCount {
			var mix = 0.0
			for n in notes.indices {
				guard notes[n].state != 0 else { continue }
				var envelope: Double

				if notes[n].state == 1 {
					let target = exp(-notes[n].time) * (1.0 - exp(-2_000.0 * notes[n].time))
					notes[n].envelopeSmooth += envelopeAlpha * (target - notes[n].envelopeSmooth)
					envelope = notes[n].envelopeSmooth
					notes[n].currentEnvelope = envelope
					notes[n].releaseStartEnvelope = envelope
				} else {
					let sustain = notes[n].sustainOff == 0 ? parameters[1] : Double(notes[n].sustainOff)
					envelope = notes[n].releaseStartEnvelope * exp(-sustain * notes[n].releaseTime)
					notes[n].releaseTime += dt
					if envelope < 0.01 {
						notes[n].state = 0
						continue
					}
				}

				envelope *= notes[n].velocity / 128.0
				notes[n].envelopeSmooth += envelopeAlpha * (envelope - notes[n].envelopeSmooth)

				let modulation = sin(2.0 * .pi * parameters[2] * notes[n].time)
				let frequency = notes[n].frequency * (1.0 + parameters[3] * modulation)
				let omega = 2.0 * .pi * frequency / Self.sampleRate
				let multipliers = [1.0, 1.5, 1.25, 1.75, 1.125, 1.375, 1.625]
				for p in notes[n].phases.indices {
					notes[n].phases[p] += omega * multipliers[p]
					if notes[n].phases[p] > 2.0 * .pi { notes[n].phases[p] -= 2.0 * .pi }
				}

				// Come nella configurazione C attuale: solo la fondamentale è attiva.
				mix += sin(notes[n].phases[0]) * envelope
				notes[n].time += dt
			}

			lowPassY += lowPassAlpha * (mix * 0.03 - lowPassY)
			let sample = Float(lowPassY * parameters[4])
			for output in outputBuffers { output[i] = sample }
			appendOutput(sample)
		}

		let ended = ProcessInfo.processInfo.systemUptime
		monitorLock.withLock { state in
			state.frames = UInt32(frameCount)
			state.hostTime = timeStamp.mHostTime
			state.sampleTime = timeStamp.mSampleTime
			state.lastTiming.tPrev = state.lastTiming.tStart
			state.lastTiming.tStart = started
			state.lastTiming.tEnd = ended
			state.lastTiming.duration = ended - started
			state.lastTiming.frames = UInt32(frameCount)
			state.lastTiming.frameCounter &+= 1
			state.maximumRenderTime = max(state.maximumRenderTime, ended - started)
		}
	}

	private func processEvents() {
		let events = eventLock.withLock { state -> [Event] in
			let result = state
			state.removeAll(keepingCapacity: true)
			return result
		}
		for event in events {
			switch event.type {
			case .noteOn: noteOn(frequency: event.frequency, note: event.note, velocity: event.velocity)
			case .noteOff: noteOff(note: event.note, sustainOff: event.sustainOff)
			}
		}
	}

	private func noteOn(frequency: Double, note: UInt8, velocity: Double) {
		let i = voiceIndex
		voiceIndex = (voiceIndex + 1) % Self.maxNotes
		notes[i] = Note(
			frequency: frequency, phases: Array(repeating: 0, count: 7), time: 0,
			state: 1, releaseTime: 0, releaseStartEnvelope: 0, currentEnvelope: 0,
			velocity: velocity, envelopeSmooth: 0, midiNote: note, sustainOff: 0)
	}

	private func noteOff(note: UInt8, sustainOff: UInt32) {
		for i in notes.indices where notes[i].state == 1 && notes[i].midiNote == note {
			notes[i].state = 2
			notes[i].releaseTime = 0
			notes[i].sustainOff = sustainOff
		}
	}

//=====================
	private func captureInput_2(_ buffer: AVAudioPCMBuffer) {
		guard let channel = buffer.floatChannelData?[0] else { return }
		let count = Int(buffer.frameLength)
		monitorLock.withLock { state in
			for i in 0..<count {
				state.inputRing[state.inputWriteIndex] = channel[i]
				state.inputWriteIndex = (state.inputWriteIndex + 1) % Self.inputBufferSize
			}
		}
	}
	
	private func captureInput(_ buffer: AVAudioPCMBuffer) {
		guard let channel = buffer.floatChannelData?[0] else { return }

		let count = Int(buffer.frameLength)
		let samples = Array(UnsafeBufferPointer(start: channel, count: count))

		monitorLock.withLock { state in
			for sample in samples {
				state.inputRing[state.inputWriteIndex] = sample
				state.inputWriteIndex =
					(state.inputWriteIndex + 1) % Self.inputBufferSize
			}
		}
	}
//======================
	private func appendOutput(_ sample: Float) {
		monitorLock.withLock { state in
			state.outputRing[state.outputWriteIndex] = sample
			state.outputWriteIndex = (state.outputWriteIndex + 1) % Self.outputBufferSize
		}
	}

	private func copyRing(count: Int, input: Bool) -> [Float] {
		monitorLock.withLock { state in
			let source = input ? state.inputRing : state.outputRing
			let write = input ? state.inputWriteIndex : state.outputWriteIndex
			let amount = max(0, min(count, source.count))
			let start = (write - amount + source.count) % source.count
			return (0..<amount).map { source[(start + $0) % source.count] }
		}
	}
}

/// Frequenza della nota MIDI, utile al chiamante GLFW o SwiftUI.
public func midiNoteToFrequency(_ note: UInt8) -> Double {
	440.0 * pow(2.0, (Double(note) - 69.0) / 12.0)
}
