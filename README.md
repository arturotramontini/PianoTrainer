# AudioTCPExperiment

Piccolo programma console per macOS: avvia un sintetizzatore `AudioSynth` e lo
controlla via TCP, senza GLFW né SwiftUI.

## Avvio

```bash
cd AudioTCPExperiment
swift run
```

In un secondo Terminale:

```bash
nc 127.0.0.1 9876
```

Poi scrivi, una riga per comando:

```text
help
start
note_on 60 100
note_off 60
stop
```

È possibile aprire due o tre Terminali con `nc`: sono tutti client del
medesimo sintetizzatore.

## Comandi

| Comando | Effetto |
|---|---|
| `start` / `stop` | Avvia / ferma audio e microfono. |
| `note_on 60 100` | Nota MIDI 60, velocity 100. |
| `note_off 60` | Spegne la nota MIDI 60. |
| `note_off 60 20` | Spegne con rilascio personalizzato. |
| `set 1 1.5` | Scrive un parametro di `AudioSynth`. |
| `get 1` | Legge un parametro. |
| `frames`, `timing`, `tmax` | Dati diagnostici. |
| `input 32`, `output 32` | Ultimi campioni del microfono o del synth (massimo 256). |
| `status` | Stato audio e numero client. |

I parametri principali attuali sono: `1` sustain/release, `2` frequenza di
modulazione, `3` profondità di modulazione, `4` volume finale.

## Nota sul microfono

Al primo `start`, macOS può chiedere il permesso di usare il microfono. Se non
serve per il primo test, si può comunque usare l'uscita sintetizzata: l'input
è solo una funzione aggiuntiva del modulo.
