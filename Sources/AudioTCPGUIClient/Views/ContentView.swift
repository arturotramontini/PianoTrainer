import SwiftUI

struct ContentView: View {
    @StateObject private var clientService = TCPClientService()
    @StateObject private var guiMidiManager = GUIMIDIManager()
    @State private var customCommand: String = ""
    @AppStorage("showConsole") private var showConsole: Bool = true

    @State private var keyboardMonitor = KeyboardMonitor()

    var body: some View {
        VStack(spacing: 16) {
            // Header & Connection Bar
            connectionHeaderView

            // Main Controls and Piano Keyboard
            mainSynthControlsView

            // Console TCP Panel (Drawer)
            if showConsole {
                Divider()
                consoleLogView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(16)
        .frame(
            minWidth: showConsole ? 750 : 540,
            idealWidth: showConsole ? 850 : 600,
            maxWidth: .infinity,
            minHeight: 480,
            idealHeight: 560,
            maxHeight: .infinity
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            keyboardMonitor.startMonitoring(clientService: clientService)
            guiMidiManager.startMonitoring(clientService: clientService)
        }
        .onDisappear {
            keyboardMonitor.stopMonitoring()
            guiMidiManager.stop()
        }
    }

    private var mainSynthControlsView: some View {
        VStack(spacing: 16) {
            // Transport & Instrument Bar
            transportAndPresetsView

            // Interactive Piano Keyboard
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "pianokeys")
                        .foregroundColor(.indigo)
                    Text("Tastiera Pianoforte (C2 - C6)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                }
                PianoView(clientService: clientService)
            }
        }
    }

    private var consoleLogView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "terminal")
                    .foregroundColor(.green)
                Text("Console TCP & Diagnostica SoundFont SF2")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { clientService.refreshStatus() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Aggiorna diagnostica")
            }

            // Log Box
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(clientService.logEntries) { entry in
                            HStack(alignment: .top, spacing: 6) {
                                Text(entry.timestamp, style: .time)
                                    .font(.caption2)
                                    .foregroundColor(.gray)

                                Text(entry.message)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(entry.isError ? .red : (entry.isOutgoing ? .cyan : .primary))
                            }
                            .id(entry.id)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                }
                .background(Color.black.opacity(0.85))
                .cornerRadius(6)
                .onChange(of: clientService.logEntries.count) { _ in
                    if let last = clientService.logEntries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
            .frame(height: 120)

            // Custom TCP Command Line Input
            HStack {
                TextField("Invia comando TCP (es: note_on 60 100, program 19...)", text: $customCommand)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        sendCustomCommand()
                    }
                Button("Invia") {
                    sendCustomCommand()
                }
                .disabled(!clientService.isConnected || customCommand.isEmpty)
            }
        }
    }

    private func sendCustomCommand() {
        guard !customCommand.isEmpty else { return }
        clientService.sendRawCommand(customCommand)
        customCommand = ""
    }

    // MARK: - Subviews

    private var connectionHeaderView: some View {
        HStack(spacing: 12) {
            Image(systemName: "music.note.house.fill")
                .resizable()
                .frame(width: 28, height: 28)
                .foregroundColor(.purple)

            VStack(alignment: .leading, spacing: 2) {
                Text("SoundFont A320U.sf2 Player Client")
                    .font(.headline)
                Text("Campionatore Musicale Standalone macOS")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Fields Host & Port
            HStack(spacing: 6) {
                Text("Host:")
                    .font(.caption)
                TextField("Host", text: $clientService.host)
                    .frame(width: 90)
                    .textFieldStyle(.roundedBorder)

                Text("Porta:")
                    .font(.caption)
                TextField("Porta", text: $clientService.port)
                    .frame(width: 50)
                    .textFieldStyle(.roundedBorder)
            }
            .disabled(clientService.isConnected)

            // Connect Button
            if clientService.isConnected {
                Button(action: { clientService.disconnect() }) {
                    Label("Disconnetti", systemImage: "bolt.slash.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red.opacity(0.2))
            } else {
                Button(action: { clientService.connect() }) {
                    if clientService.isConnecting {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Connetti", systemImage: "bolt.fill")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(clientService.isConnecting)
            }

            // Connection Badge Indicator
            HStack(spacing: 4) {
                Circle()
                    .fill(clientService.isConnected ? Color.green : Color.red)
                    .frame(width: 8, height: 8)
                Text(clientService.isConnected ? "Connesso" : "Disconnesso")
                    .font(.caption2)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.1))
            .cornerRadius(12)

            // Hardware MIDI Devices Badge
            HStack(spacing: 4) {
                Image(systemName: "pianokeys")
                    .foregroundColor(guiMidiManager.connectedDevices.isEmpty ? .gray : .purple)
                if guiMidiManager.connectedDevices.isEmpty {
                    Text("Nessun MIDI USB")
                        .font(.caption2)
                        .foregroundColor(.gray)
                } else {
                    Text("MIDI: \(guiMidiManager.connectedDevices.joined(separator: ", "))")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundColor(.purple)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.black.opacity(0.1))
            .cornerRadius(12)

            // Console TCP Toggle Button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showConsole.toggle()
                }
            }) {
                Label("Console TCP", systemImage: showConsole ? "terminal.fill" : "terminal")
            }
            .buttonStyle(.bordered)
            .tint(showConsole ? .green : .gray)
            .help("Mostra o nascondi la console TCP & log")
        }
    }

    private var transportAndPresetsView: some View {
        HStack(spacing: 16) {
            // Audio Engine Start/Stop
            Button(action: { clientService.toggleAudio() }) {
                HStack {
                    Image(systemName: clientService.audioRunning ? "pause.fill" : "play.fill")
                    Text(clientService.audioRunning ? "Arresta Audio Player" : "Avvia Audio Player")
                }
                .fontWeight(.bold)
            }
            .buttonStyle(.borderedProminent)
            .tint(clientService.audioRunning ? .orange : .purple)
            .disabled(!clientService.isConnected)

            Spacer()

            // Selettore Strumento SoundFont SF2
            HStack(spacing: 6) {
                Image(systemName: "guitars.fill")
                    .foregroundColor(.purple)
                Text("Strumento General MIDI:")
                    .font(.caption)
                    .fontWeight(.bold)
                
                Picker("Strumento SF2", selection: Binding(
                    get: { clientService.sf2Program },
                    set: { clientService.setSF2Program($0) }
                )) {
                    ForEach(TCPClientService.SF2Instrument.popularInstruments) { inst in
                        Text(inst.name).tag(inst.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220)
                .disabled(!clientService.isConnected)
            }
        }
        .padding(10)
        .background(Color.purple.opacity(0.06))
        .cornerRadius(8)
    }
}
