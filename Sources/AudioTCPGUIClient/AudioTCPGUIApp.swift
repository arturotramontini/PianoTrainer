import SwiftUI
import AppKit
import AudioTCPEngine

@main
struct AudioTCPGUIApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .navigationTitle("AudioTCP GUI Client")
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var audioSynth: AudioSynth?
    private var midiManager: MIDIManager?
    private var tcpServer: AudioTCPServer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // Avvio automatico del motore audio SoundFont & Server TCP 9876 integrato in background
        do {
            let synth = AudioSynth()
            self.audioSynth = synth
            try synth.startAudio()

            let midi = MIDIManager(audio: synth)
            self.midiManager = midi
            midi.start()

            let server = try AudioTCPServer(audio: synth, port: 9876)
            self.tcpServer = server
            server.start()

            print("[\u{001B}[32m✓\u{001B}[0m] PianoTrainer App: Motore Audio SoundFont SF2 e Server TCP 9876 avviati automaticamente!")
        } catch {
            print("[\u{001B}[33m!\u{001B}[0m] Avviso avvio server integrato: \(error)")
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
