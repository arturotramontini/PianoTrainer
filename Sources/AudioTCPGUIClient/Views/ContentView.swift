import SwiftUI

struct ContentView: View {
    @StateObject private var clientService = TCPClientService()
    @StateObject private var guiMidiManager = GUIMIDIManager()
    @State private var customCommand: String = ""
    @State private var isShowingScoreEditor: Bool = false
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
        .sheet(isPresented: $isShowingScoreEditor) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Image(systemName: "doc.text.fill")
                        .foregroundColor(.blue)
                    Text("Editor Testo Spartito (BUILDMIDI)")
                        .font(.headline)
                    Spacer()
                    Button("Chiudi & Applica") {
                        let service = clientService
                        service.loadScoreFromText(service.scoreText, fileName: service.scoreFileName.isEmpty ? "Spartito Modificato" : service.scoreFileName)
                        isShowingScoreEditor = false
                    }
                    .buttonStyle(.borderedProminent)
                }

                TextEditor(text: $clientService.scoreText)
                    .font(.system(.body, design: .monospaced))
                    .frame(minWidth: 500, minHeight: 400)
                    .border(Color.secondary.opacity(0.3))
            }
            .padding(16)
        }
    }

    private func openScoreFilePicker() {
        let service = clientService
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.text, .plainText]

        if panel.runModal() == .OK, let url = panel.url {
            do {
                let content = try String(contentsOf: url, encoding: .utf8)
                service.loadScoreFromText(content, fileName: url.lastPathComponent)
            } catch {
                service.addLog("Errore lettura file: \(error.localizedDescription)", isError: true)
            }
        }
    }

    // MARK: - Piano Trainer Control Panel

    // MARK: - Piano Trainer Control Panel

    private var pianoTrainerBannerView: some View {
        VStack(spacing: 10) {
            trainerModeHeaderView
            trainerBadgesView
            trainerActionButtonsView
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .cornerRadius(10)
    }

    private var trainerModeHeaderView: some View {
        HStack(spacing: 16) {
            Picker("Modalità Didattica", selection: $clientService.trainerMode) {
                ForEach(TCPClientService.TrainerMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            if clientService.trainerMode == .chords {
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Text("Rivolto:")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)
                        
                        Picker("Rivolto", selection: $clientService.selectedInversionFilter) {
                            ForEach(InversionFilter.allCases) { inv in
                                Text(inv.rawValue).tag(inv)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .font(.caption)
                    }

                    Divider()
                        .frame(height: 16)

                    HStack(spacing: 4) {
                        Text("Modalità Musicale:")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundColor(.secondary)

                        Picker("Modalità Musicale", selection: $clientService.selectedScaleMode) {
                            ForEach(MusicalScaleMode.allCases) { scale in
                                Text(scale.rawValue).tag(scale)
                            }
                        }
                        .pickerStyle(.radioGroup)
                        .font(.caption)
                    }
                }
            } else if clientService.trainerMode == .score {
                HStack(spacing: 8) {
                    Button(action: {
                        openScoreFilePicker()
                    }) {
                        Label("Apri File Spartito", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)

                    Button(action: {
                        isShowingScoreEditor = true
                    }) {
                        Label("Editor Testo", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)

                    if let result = clientService.scoreParseResult {
                        Text("File: \(clientService.scoreFileName) (\(result.steps.count) passi)")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()
        }
    }

    private var trainerBadgesView: some View {
        HStack(spacing: 12) {
            targetDisplayBadgeView
            Spacer()
            lastPlayedBadgeSubView
            velocityBadgeSubView
            durationBadgeSubView
            Spacer()
        }
    }

    private var lastPlayedBadgeSubView: some View {
        let isMatched: Bool = {
            switch clientService.trainerMode {
            case .singleNotes: return clientService.lastPlayedIsTargetMatched
            case .chords: return clientService.isChordMatched
            case .score: return clientService.isScoreMatched
            }
        }()

        let titleText: String = {
            if isMatched {
                switch clientService.trainerMode {
                case .singleNotes: return "NOTA GIUSTA!"
                case .chords: return "ACCORDO GIUSTO!"
                case .score: return "PASSO GIUSTO!"
                }
            } else {
                return "ULTIMA NOTA:"
            }
        }()

        let textColor: Color = isMatched ? .green : (clientService.lastPlayedNoteMIDI != nil ? .cyan : .gray)

        return VStack(alignment: .center, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: isMatched ? "checkmark.circle.fill" : "music.note")
                    .foregroundColor(isMatched ? .green : .cyan)
                Text(titleText)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(isMatched ? .green : .secondary)
            }

            Text(clientService.lastPlayedNoteText)
                .font(.system(size: 24, weight: .black, design: .rounded))
                .foregroundColor(textColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(isMatched ? Color.green.opacity(0.12) : Color.black.opacity(0.06))
        .cornerRadius(8)
    }

    private var velocityBadgeSubView: some View {
        let hasVel = clientService.lastVelocity > 0
        return VStack(alignment: .center, spacing: 2) {
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
                .foregroundColor(hasVel ? .yellow : .gray)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.06))
        .cornerRadius(8)
    }

    private var durationBadgeSubView: some View {
        let hasDur = clientService.lastDurationSeconds > 0
        return VStack(alignment: .center, spacing: 2) {
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
                .foregroundColor(hasDur ? .green : .gray)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.06))
        .cornerRadius(8)
    }

    private var trainerActionButtonsView: some View {
        let service = clientService
        return HStack(spacing: 8) {
            if service.trainerMode == .chords {
                HStack(spacing: 4) {
                    TextField("Es. Do d 4 3 o C#4", text: $clientService.manualChordInputText)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 140)
                        .onSubmit {
                            service.applyManualChordInput()
                        }
                        .help("Imposta accordo a mano: Nota (Do/C) Alterazione (d/#/b) Ottava (0..8) Modalità (1..8)")

                    Button(action: {
                        service.applyManualChordInput()
                    }) {
                        Image(systemName: "square.and.pencil")
                    }
                    .buttonStyle(.bordered)
                    .help("Applica l'accordo scritto nel campo di testo")
                }

                Button(action: {
                    service.generateNewTargetChord()
                }) {
                    Label("Nuovo Accordo", systemImage: "music.quaver.manifest")
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .help("Estrai e pronuncia un nuovo accordo con il suo rivolto")
            } else if service.trainerMode == .score {
                HStack(spacing: 6) {
                    Button(action: {
                        service.previousScoreStep()
                    }) {
                        Image(systemName: "backward.fill")
                    }
                    .buttonStyle(.bordered)
                    .help("Passo Precedente")

                    Button(action: {
                        service.toggleScoreAutoPlay()
                    }) {
                        Label(service.isScoreAutoPlaying ? "Pausa" : "Play Brano", systemImage: service.isScoreAutoPlaying ? "pause.fill" : "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(service.isScoreAutoPlaying ? .orange : .green)
                    .help("Riproduci o Metti in Pausa l'esecuzione del brano")

                    Button(action: {
                        service.nextScoreStep()
                    }) {
                        Image(systemName: "forward.fill")
                    }
                    .buttonStyle(.bordered)
                    .help("Passo Successivo")
                }
            } else {
                Button(action: {
                    service.generateNewTargetNote()
                }) {
                    Label("Nuova Nota", systemImage: "dice.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .help("Estrai e pronuncia una nuova nota tra gli 88 tasti")
            }
        }
    }

    private var trainerOptionsBarView: some View {
        HStack(spacing: 12) {
            Toggle(isOn: $clientService.showOctaveGeometryHints) {
                HStack(spacing: 4) {
                    Image(systemName: "sparkles")
                        .foregroundColor(.cyan)
                    Text("Geometria su tutte le ottave (cerchiolini ciano)")
                        .font(.caption)
                        .fontWeight(.semibold)
                }
            }
            .toggleStyle(.checkbox)
            .help("Visualizza cerchiolini ciano su tutte le ottave per osservarne il pattern geometrico")

            if clientService.showOctaveGeometryHints && clientService.trainerMode == .chords {
                Picker("Modalità Ciano", selection: $clientService.cyanDotMode) {
                    ForEach(TCPClientService.CyanDotMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
            }

            Spacer()

            Toggle(isOn: $clientService.useItalianNotation) {
                Text("Notazione Italiana (Do, Re, Mi)")
                    .font(.caption)
            }
            .toggleStyle(.checkbox)
            .help("Seleziona Notazione Italiana o Inglese (A..G)")
        }
    }

    private var targetDisplayBadgeView: some View {
        let mode = clientService.trainerMode
        let isScore = mode == .score
        let isChords = mode == .chords

        let iconName = isScore ? "doc.text.fill" : (isChords ? "music.quaver.manifest" : "target")
        let iconColor: Color = isScore ? .blue : .orange
        let headerTitle = isScore ? "PASSO SPARTITO:" : (isChords ? "ACCORDO PROPOSTO DAL MAC:" : "NOTA PROPOSTA DAL MAC:")
        let targetText = isChords ? clientService.targetChordText : clientService.targetNoteText

        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Image(systemName: iconName)
                    .foregroundColor(iconColor)
                Text(headerTitle)
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
            }

            if isScore {
                if let result = clientService.scoreParseResult, clientService.currentScoreIndex < result.steps.count {
                    let step = result.steps[clientService.currentScoreIndex]
                    Text(step.displayText)
                        .font(.system(size: 20, weight: .black, design: .rounded))
                        .foregroundColor(.blue)
                } else {
                    Text("Nessun brano caricato - Clicca 'Apri File Spartito'")
                        .font(.system(size: 16, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                }
            } else {
                Text(targetText)
                    .font(.system(size: isChords ? 20 : 24, weight: .black, design: .rounded))
                    .foregroundColor((clientService.targetNoteMIDI != nil || clientService.targetChord != nil) ? .orange : .primary)
            }

            if isChords, let keyInfo = clientService.currentKeySignature {
                let isIt = clientService.useItalianNotation
                let keyName = keyInfo.displayName(isItalian: isIt)
                let scaleNotes = keyInfo.displayScaleNotes(isItalian: isIt)
                let accidentals = keyInfo.displayAccidentals(isItalian: isIt)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Modalità / Tonalità: \(keyName)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.9))
                    Text("Note della Scala: \(scaleNotes)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.cyan)
                    Text("Alterazioni in chiave: \(accidentals)")
                        .font(.system(size: 10, weight: .regular))
                        .foregroundColor(.white.opacity(0.75))
                }
                .padding(.top, 2)
            }
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
                    Spacer()
                    Text("💡 Suggerimenti tasti hardware: A0 (nuovo accordo/nota) | Bb0 (trasponi -1 semitono) | B0 (trasponi +1 semitono)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                PianoView(clientService: clientService)
            }
        }
    }

    private var consoleLogView: some View {
        let service = clientService
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "terminal")
                    .foregroundColor(.green)
                Text("Console TCP & Log Piano Trainer")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                Spacer()
                Button(action: { service.refreshStatus() }) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Aggiorna diagnostica")
            }

            // Log Box
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(service.logEntries) { entry in
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
                .onChange(of: service.logEntries.count) { _ in
                    if let last = service.logEntries.last {
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
                .disabled(!service.isConnected || customCommand.isEmpty)
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
        let service = clientService
        return HStack(spacing: 16) {
            // Audio Engine Start/Stop
            Button(action: { service.toggleAudio() }) {
                HStack {
                    Image(systemName: service.audioRunning ? "pause.fill" : "play.fill")
                    Text(service.audioRunning ? "Arresta Audio Player" : "Avvia Audio Player")
                }
                .fontWeight(.bold)
            }
            .buttonStyle(.borderedProminent)
            .tint(service.audioRunning ? .orange : .purple)
            .disabled(!service.isConnected)

            Spacer()

            // Selettore Strumento SoundFont SF2
            HStack(spacing: 6) {
                Image(systemName: "guitars.fill")
                    .foregroundColor(.purple)
                Text("Strumento General MIDI:")
                    .font(.caption)
                    .fontWeight(.bold)
                
                Picker("Strumento SF2", selection: Binding(
                    get: { service.sf2Program },
                    set: { service.setSF2Program($0) }
                )) {
                    ForEach(TCPClientService.SF2Instrument.popularInstruments) { inst in
                        Text(inst.name).tag(inst.id)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 220)
                .disabled(!service.isConnected)
            }
        }
        .padding(10)
        .background(Color.purple.opacity(0.06))
        .cornerRadius(8)
    }
}
