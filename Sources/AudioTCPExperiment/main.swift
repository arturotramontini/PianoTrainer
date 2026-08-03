import Dispatch
import AudioTCPEngine

let audio = AudioSynth()
let midiManager = MIDIManager(audio: audio)
midiManager.start()

do {
    let server = try AudioTCPServer(audio: audio, port: 9876)
    server.start()
    print("AudioTCPExperiment avviato. Collegati con: nc 127.0.0.1 9876")
    print("Poi invia: help")
    dispatchMain()
} catch {
    print("Impossibile avviare il server: \(error)")
}
