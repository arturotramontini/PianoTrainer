# 🎹 SoundFont Piano Trainer Assistant & SF2 Synthesizer for macOS

![macOS 13+](https://img.shields.io/badge/macOS-13.0%2B-blue?style=for-the-badge&logo=apple)
![Swift 5.10](https://img.shields.io/badge/Swift-5.10-orange?style=for-the-badge&logo=swift)
![License GPLv3](https://img.shields.io/badge/License-GPLv3-green?style=for-the-badge)

Un'applicazione macOS nativa in Swift e SwiftUI progettata per la sintesi audio SoundFont (`.sf2`) e l'allenamento vocale al pianoforte ad occhi chiusi.

---

## 🌟 Caratteristiche Principali

- 🎓 **Piano Trainer Assistant**:
  - **Proposta Nota Casuale (> 2s)**: Tenendo premuto un tasto per più di 2 secondi, la voce nativa del Mac (`AVSpeechSynthesizer`) propone a voce una nuova nota da cercare su tutta la tastiera a 88 tasti (`A0...C8`).
  - **Lettura Vocale ad Occhi Chiusi**: Opzione per attivare la lettura vocale istantanea di ogni nota premuta per esercitarsi senza guardare lo schermo.
  - **Analisi Tocco & Dinamica (Velocity)**: Misurazione in tempo reale della dinamica di tocco (`p` piano, `mf` mezzo forte, `f` forte).
  - **Analisi Articolazione (Duration)**: Calcolo della durata di pressione (`Staccato`, `Tenuto`, `Sostenuto`).
  - **Notazione Inglese ed Italiana**: Selezione dinamica tra `C4, F#3` e `Do4, Fa#3`.

- 🎹 **Campionatore SoundFont SF2 Nativo**:
  - Utilizza l'engine nativo Apple `AVAudioEngine` & `AVAudioUnitSampler` caricando il banco General MIDI `A320U.sf2`.
  - Supporta le **tastiere MIDI hardware fisiche USB/Bluetooth** (Akai, Arturia, Novation, Yamaha, Roland, Korg...) con cambio strumento General MIDI sincrono a latenza zero.
  - Tastiera grafica dinamica reattiva a 88 tasti con illuminazione in tempo reale.

- 🖥️ **Finestra Standalone Unificata (`PianoTrainer.app`)**:
  - App macOS impacchettata con la sua icona personalizzata: doppio click ed il motore audio ed il server si avviano automaticamente.

---

## 🚀 Installazione ed Avvio

### Requisiti
- macOS 13.0 Ventura o superiore
- Xcode 15+ o Swift 5.10 toolchain

### Avvio dell'App Nativamene
Puoi aprire direttamente l'app impacchettata:
```bash
open PianoTrainer.app
```

> **Nota per il download dell'App da GitHub (Gatekeeper Quarantine)**:
> Se scarichi la `.app` da browser web, macOS bloccherà l'avvio con il messaggio *"App danneggiata"*. Per sbloccarla ed avviarla subito, digita nel terminale:
> ```bash
> xattr -cr ~/Downloads/PianoTrainer.app
> ```

### Compilazione da Sorgente via Swift Package Manager
```bash
git clone https://github.com/tuousero/PianoTrainer.git
cd PianoTrainer

# Compilazione ed avvio della GUI Piano Trainer
swift run AudioTCPGUIClient
```

---

## 📄 Licenza

Rilasciato sotto licenza **GNU General Public License v3.0 (GPL-3.0)**. Consultare il file [LICENSE](LICENSE) per i dettagli.
