import Foundation
import AVFAudio
import AudioToolbox

/// Gestore nativo Apple AVAudioEngine & AVAudioUnitSampler per campioni SoundFont (.sf2).
public final class SF2SamplerEngine: @unchecked Sendable {
    private let audioEngine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()
    private var sf2URL: URL?

    public private(set) var currentProgram: UInt8 = 0
    public private(set) var isRunning: Bool = false

    public init(sf2Path: String = "A320U.sf2") {
        let fileManager = FileManager.default
        let currentDirURL = URL(fileURLWithPath: fileManager.currentDirectoryPath)
        let targetURL = currentDirURL.appendingPathComponent(sf2Path)

        if fileManager.fileExists(atPath: targetURL.path) {
            self.sf2URL = targetURL
        } else {
            let altURL = URL(fileURLWithPath: sf2Path)
            if fileManager.fileExists(atPath: altURL.path) {
                self.sf2URL = altURL
            } else {
                let defaultPath = "/Volumes/PortableSSD/SWIFT/AUDIOSYNTH/AudioTCPExperiment/A320U.sf2"
                if fileManager.fileExists(atPath: defaultPath) {
                    self.sf2URL = URL(fileURLWithPath: defaultPath)
                }
            }
        }

        setupEngine()
    }

    private func setupEngine() {
        audioEngine.attach(sampler)
        audioEngine.connect(sampler, to: audioEngine.mainMixerNode, format: nil)
    }

    public func start() {
        guard !isRunning else { return }
        do {
            try audioEngine.start()
            isRunning = true
            print("[\u{001B}[32m✓\u{001B}[0m] AVAudioEngine Sampler SF2 avviato correttamente.")
            
            // Carica lo strumento predefinito (Piano 0)
            if let sf2URL = sf2URL {
                loadInstrument(program: currentProgram)
                print("[\u{001B}[32m✓\u{001B}[0m] Banco SoundFont A320U.sf2 caricato (\(sf2URL.path)).")
            } else {
                print("[\u{001B}[33m!\u{001B}[0m] File A320U.sf2 non trovato.")
            }
        } catch {
            print("[\u{001B}[31m✗\u{001B}[0m] Errore avvio AVAudioEngine: \(error)")
        }
    }

    public func stop() {
        guard isRunning else { return }
        audioEngine.stop()
        isRunning = false
    }

    public func loadInstrument(program: UInt8) {
        self.currentProgram = program
        guard let url = sf2URL else { return }

        do {
            try sampler.loadSoundBankInstrument(
                at: url,
                program: program,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: 0
            )
            sampler.sendProgramChange(
                program,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: 0,
                onChannel: 0
            )
            print("[\u{001B}[32m✓\u{001B}[0m] Strumento SoundFont SF2 attivato a Program \(program).")
        } catch {
            print("[\u{001B}[31m✗\u{001B}[0m] Errore caricamento strumento SF2 Program \(program): \(error)")
        }
    }

    public func noteOn(note: UInt8, velocity: UInt8) {
        guard isRunning else { return }
        sampler.startNote(note, withVelocity: velocity, onChannel: 0)
    }

    public func noteOff(note: UInt8) {
        guard isRunning else { return }
        sampler.stopNote(note, onChannel: 0)
    }
}
