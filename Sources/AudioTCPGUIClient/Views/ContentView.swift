import SwiftUI

struct ContentView: View {
    @StateObject private var clientService = TCPClientService()
    @StateObject private var guiMidiManager = GUIMIDIManager()
    @State private var customCommand: String = ""
    @State private var selectedPreset: TCPClientService.Preset = TCPClientService.Preset.defaultPresets[0]
    @AppStorage("showConsole") private var showConsole: Bool = true

    @State private var keyboardMonitor = KeyboardMonitor()

    var body: some View {
        VStack(spacing: 12) {
            // Header & Connection Bar
            connectionHeaderView

            Divider().background(Color.white.opacity(0.15))

            // Main Content Area
            if showConsole {
                HSplitView {
                    mainSynthControlsView
                        .padding(.trailing, 8)
                        .frame(minWidth: 480)

                    consoleLogView
                        .padding(.leading, 8)
                        .frame(minWidth: 260, idealWidth: 320)
                }
            } else {
                mainSynthControlsView
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(16)
        .frame(
            minWidth: showConsole ? 800 : 560,
            idealWidth: showConsole ? 920 : 640,
            maxWidth: .infinity,
            minHeight: 600,
            idealHeight: 720,
            maxHeight: .infinity
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            keyboardMonitor.startMonitoring(clientService: clientService)
        }
        .onDisappear {
            keyboardMonitor.stopMonitoring()
        }
    }

    private var mainSynthControlsView: some View {
        VStack(spacing: 16) {
            // Transport & Presets Bar
            transportAndPresetsView

            // Synth Parameters Sliders
            synthParametersView

            // Waveform Oscilloscope (Rolling 1-Second View)
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: "waveform.path.ecg")
                        .foregroundColor(.cyan)
                    Text("Oscilloscopio Uscita Synth")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundColor(.secondary)
                    
                    Spacer()

                    // Selettore Timebase per lo scorrimento continuo
                    HStack(spacing: 4) {
                        Text("Timebase:")
                            .font(.caption2)
                            .foregroundColor(.gray)

                        ForEach([0.05, 0.2, 0.5, 1.0, 2.0, 5.0], id: \.self) { seconds in
                            Button(action: { clientService.timebaseSeconds = seconds }) {
                                Text(seconds >= 1.0 ? String(format: "%.1f s", seconds) : "\(Int(seconds * 1000)) ms")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .buttonStyle(.bordered)
                            .tint(clientService.timebaseSeconds == seconds ? .cyan : .gray)
                        }
                    }

                    Spacer()

                    // Selettore Scala Verticale (Gain / Volts-per-div)
                    HStack(spacing: 4) {
                        Text("Gain V:")
                            .font(.caption2)
                            .foregroundColor(.gray)

                        ForEach([0.5, 1.0, 2.0, 4.0, 8.0], id: \.self) { gain in
                            Button(action: { clientService.verticalGain = gain }) {
                                Text(gain < 1.0 ? "0.5x" : "\(Int(gain))x")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .buttonStyle(.bordered)
                            .tint(clientService.verticalGain == gain ? .blue : .gray)
                        }
                    }

                    Spacer()

                    Text("Latenza: \(clientService.tmaxInfo)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                WaveformView(
                    samples: clientService.rollingBuffer,
                    timebaseSeconds: clientService.timebaseSeconds,
                    verticalGain: clientService.verticalGain
                )
                .frame(minHeight: 110, maxHeight: .infinity)
            }

            // Interactive Piano Keyboard
            VStack(alignment: .leading, spacing: 4) {
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
                Text("Console TCP & Diagnostica")
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
                                    .font(.system(size: 9, design: .monospaced))
                                    .foregroundColor(.gray)
                                Text(entry.isOutgoing ? "➔" : "⬅")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundColor(entry.isOutgoing ? .blue : .green)
                                Text(entry.message)
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundColor(entry.isError ? .red : (entry.isOutgoing ? .cyan : .white))
                            }
                            .id(entry.id)
                        }
                    }
                    .padding(8)
                }
                .background(Color.black.opacity(0.8))
                .cornerRadius(6)
                .onChange(of: clientService.logEntries.count) { _ in
                    if let last = clientService.logEntries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            // Raw TCP Command Sender
            HStack {
                TextField("Comando TCP (es: get 1, timing)...", text: $customCommand)
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
            Image(systemName: "waveform.circle.fill")
                .resizable()
                .frame(width: 28, height: 28)
                .foregroundColor(.cyan)

            VStack(alignment: .leading, spacing: 2) {
                Text("AudioTCP Synthesizer Client")
                    .font(.headline)
                Text("Controllo Remoto TCP per AudioSynth macOS")
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
        HStack {
            // Audio Engine Start/Stop
            Button(action: { clientService.toggleAudio() }) {
                HStack {
                    Image(systemName: clientService.audioRunning ? "pause.fill" : "play.fill")
                    Text(clientService.audioRunning ? "Arresta Audio Synth" : "Avvia Audio Synth")
                }
                .fontWeight(.bold)
            }
            .buttonStyle(.borderedProminent)
            .tint(clientService.audioRunning ? .orange : .green)
            .disabled(!clientService.isConnected)

            Spacer()

            // Presets Dropdown
            Text("Presets:")
                .font(.caption)
                .fontWeight(.medium)

            Picker("Preset", selection: $selectedPreset) {
                ForEach(TCPClientService.Preset.defaultPresets) { preset in
                    Text(preset.name).tag(preset)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 200)
            .disabled(!clientService.isConnected)
            .onChange(of: selectedPreset) { newPreset in
                clientService.applyPreset(newPreset)
            }
        }
        .padding(8)
        .background(Color.black.opacity(0.05))
        .cornerRadius(8)
    }

    private var synthParametersView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Parametri di Sintesi Audio")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.secondary)

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 10) {
                // Parametro 1: Sustain / Release
                GridRow {
                    Text("Sustain / Release (p1)")
                        .font(.caption)
                    Slider(value: $clientService.paramSustainRelease, in: 0.1...10.0, step: 0.1) {
                        Text("Sustain")
                    } onEditingChanged: { _ in
                        clientService.setParam(1, value: clientService.paramSustainRelease)
                    }
                    Text(String(format: "%.1f", clientService.paramSustainRelease))
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 40)
                }

                // Parametro 2: Frequenza Modulazione
                GridRow {
                    Text("Mod Freq Hz (p2)")
                        .font(.caption)
                    Slider(value: $clientService.paramModFreq, in: 0.5...40.0, step: 0.25) {
                        Text("Mod Freq")
                    } onEditingChanged: { _ in
                        clientService.setParam(2, value: clientService.paramModFreq)
                    }
                    Text(String(format: "%.2f Hz", clientService.paramModFreq))
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 60)
                }

                // Parametro 3: Profondità Modulazione
                GridRow {
                    Text("Mod Depth (p3)")
                        .font(.caption)
                    Slider(value: $clientService.paramModDepth, in: 0.0...0.2, step: 0.005) {
                        Text("Mod Depth")
                    } onEditingChanged: { _ in
                        clientService.setParam(3, value: clientService.paramModDepth)
                    }
                    Text(String(format: "%.3f", clientService.paramModDepth))
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 40)
                }

                // Parametro 4: Volume
                GridRow {
                    Text("Volume Finale (p4)")
                        .font(.caption)
                    Slider(value: $clientService.paramVolume, in: 0.0...50.0, step: 1.0) {
                        Text("Volume")
                    } onEditingChanged: { _ in
                        clientService.setParam(4, value: clientService.paramVolume)
                    }
                    Text(String(format: "%.0f", clientService.paramVolume))
                        .font(.caption)
                        .monospacedDigit()
                        .frame(width: 40)
                }
            }
            .disabled(!clientService.isConnected)
        }
        .padding(12)
        .background(Color.black.opacity(0.04))
        .cornerRadius(10)
    }
}
