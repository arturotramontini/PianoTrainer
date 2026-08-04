import SwiftUI

struct ContentView: View {
    @StateObject private var clientService = TCPClientService()
    @StateObject private var guiMidiManager = GUIMIDIManager()
    @State private var customCommand: String = ""
    @AppStorage("showConsole") private var showConsole: Bool = true

    var body: some View {
        VStack(spacing: 16) {
            // Header & Connection Bar
            connectionHeaderView

            // Piano Trainer Training Control Panel
            pianoTrainerBannerView

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
            minWidth: showConsole ? 780 : 580,
            idealWidth: showConsole ? 880 : 640,
            maxWidth: .infinity,
            minHeight: 560,
            idealHeight: 640,
            maxHeight: .infinity
        )
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            guiMidiManager.startMonitoring(clientService: clientService)
            // Auto-connessione automatica al server integrato
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                clientService.connect()
            }
        }
        .onDisappear {
            guiMidiManager.stop()
        }
    }

    // MARK: - Piano Trainer Control Panel

    private var pianoTrainerBannerView: some View {
        VStack(spacing: 10) {
            // Mode Selector Bar (Note Singole vs Accordi & Rivolti)
            HStack {
                Picker("Modalità Didattica", selection: $clientService.trainerMode) {
                    ForEach(TCPClientService.TrainerMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                Spacer()
            }

            HStack(spacing: 12) {
                // Target Display Badge (Note or Chord)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: clientService.trainerMode == .chords ? "music.quaver.manifest" : "target")
                            .foregroundColor(.orange)
                        Text(clientService.trainerMode == .chords ? "ACCORDO PROPOSTO DAL MAC:" : "NOTA PROPOSTA DAL MAC:")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                    }

                    Text(clientService.trainerMode == .chords ? clientService.targetChordText : clientService.targetNoteText)
                        .font(.system(size: clientService.trainerMode == .chords ? 20 : 24, weight: .black, design: .rounded))
                        .foregroundColor((clientService.targetNoteMIDI != nil || clientService.targetChord != nil) ? .orange : .primary)
                }

                Spacer()

                // Last Played / Matched Status Badge
                VStack(alignment: .center, spacing: 2) {
                    let isMatched = (clientService.trainerMode == .chords) ? clientService.isChordMatched : clientService.lastPlayedIsTargetMatched
                    HStack(spacing: 4) {
                        Image(systemName: isMatched ? "checkmark.circle.fill" : "music.note")
                            .foregroundColor(isMatched ? .green : .cyan)
                        Text(isMatched ? (clientService.trainerMode == .chords ? "ACCORDO GIUSTO!" : "NOTA GIUSTA!") : "ULTIMA NOTA:")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(isMatched ? .green : .secondary)
                    }

                    Text(clientService.lastPlayedNoteText)
                        .font(.system(size: 24, weight: .black, design: .rounded))
                        .foregroundColor(isMatched ? .green : (clientService.lastPlayedNoteMIDI != nil ? .cyan : .gray))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background((clientService.trainerMode == .chords ? clientService.isChordMatched : clientService.lastPlayedIsTargetMatched) ? Color.green.opacity(0.12) : Color.black.opacity(0.06))
                .cornerRadius(8)

                // Dynamic Velocity (Tocco / Dinamica) Display Badge
                VStack(alignment: .center, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .foregroundColor(.yellow)
                        Text("VELOCITÀ (DINAMICA):")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                    }

                    Text(clientService.lastVelocityText)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(clientService.lastVelocity > 0 ? .yellow : .gray)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.06))
                .cornerRadius(8)

                // Duration (Tempo di pressione) Display Badge
                VStack(alignment: .center, spacing: 2) {
                    HStack(spacing: 4) {
                        Image(systemName: "timer")
                            .foregroundColor(.green)
                        Text("DURATA PRESSIONE:")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                    }

                    Text(clientService.lastDurationText)
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundColor(clientService.lastDurationSeconds > 0 ? .green : .gray)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.06))
                .cornerRadius(8)

                Spacer()

                // Action Buttons: Generate New Note or Chord
                HStack(spacing: 8) {
                    if clientService.trainerMode == .chords {
                        Button(action: {
                            clientService.generateNewTargetChord()
                        }) {
                            Label("Nuovo Accordo", systemImage: "music.quaver.manifest")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .help("Estrai e pronuncia un nuovo accordo con il suo rivolto")
                    } else {
                        Button(action: {
                            clientService.generateNewTargetNote()
                        }) {
                            Label("Nuova Nota", systemImage: "dice.fill")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .help("Estrai e pronuncia una nuova nota tra gli 88 tasti")
                    }
                }
            }

            Divider()

            // Options: Eyes-Closed Speech, Key Hint Dots & Notation Toggle
            HStack(spacing: 20) {
                Toggle(isOn: $clientService.speakPressedNotes) {
                    HStack(spacing: 4) {
                        Image(systemName: "ear.and.waveform")
                            .foregroundColor(.purple)
                        Text("Pronuncia nota premuta (ad occhi chiusi)")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
                .toggleStyle(.checkbox)
                .help("Attiva/disattiva la sintesi vocale ad ogni tasto premuto")

                Toggle(isOn: $clientService.showKeyHints) {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.circle.fill")
                            .foregroundColor(.red)
                        Text("Mostra suggerimento tasti (indicatori)")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                }
                .toggleStyle(.checkbox)
                .help("Mostra piccoli cerchiolini luminosi sui tasti da premere per suggerire la nota o l'accordo")

                Spacer()

                Toggle(isOn: $clientService.useItalianNotation) {
                    Text("Notazione Italiana (Do, Re, Mi)")
                        .font(.caption)
                }
                .toggleStyle(.checkbox)
                .help("Seleziona Notazione Italiana o Inglese (A..G)")
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.25), lineWidth: 1)
        )
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
                    Spacer()
                    Text("💡 Suggerimento: tieni premuto un tasto per > 1.4s per ricevere una nuova nota proposta")
                        .font(.caption2)
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
                Text("Console TCP & Log Piano Trainer")
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
            .frame(height: 110)

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
            Image(systemName: "graduationcap.fill")
                .resizable()
                .frame(width: 28, height: 28)
                .foregroundColor(.orange)

            VStack(alignment: .leading, spacing: 2) {
                Text("SoundFont Piano Trainer Assistant")
                    .font(.headline)
                Text("Allenatore Vocale Pianoforte ad Occhi Chiusi")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Fields Host & Port
            HStack(spacing: 6) {
                Text("Host:")
                    .font(.caption)
                TextField("Host", text: $clientService.host)
                    .frame(width: 85)
                    .textFieldStyle(.roundedBorder)

                Text("Porta:")
                    .font(.caption)
                TextField("Porta", text: $clientService.port)
                    .frame(width: 45)
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
