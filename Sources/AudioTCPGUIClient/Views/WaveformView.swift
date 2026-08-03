import SwiftUI

struct WaveformView: View {
    let samples: [Float]
    var timebaseSeconds: Double = 1.0
    var verticalGain: Double = 1.0
    var lineColor: Color = .cyan

    var body: some View {
        Canvas { context, size in
            guard samples.count > 1 else { return }

            let width = size.width
            let height = size.height
            let midY = height / 2.0

            // 1. Disegna griglia di sfondo oscilloscopio
            var gridPath = Path()
            // Linea centrale orizzontale
            gridPath.move(to: CGPoint(x: 0, y: midY))
            gridPath.addLine(to: CGPoint(x: width, y: midY))
            // Griglie orizzontali (+0.5, -0.5)
            gridPath.move(to: CGPoint(x: 0, y: height * 0.25))
            gridPath.addLine(to: CGPoint(x: width, y: height * 0.25))
            gridPath.move(to: CGPoint(x: 0, y: height * 0.75))
            gridPath.addLine(to: CGPoint(x: width, y: height * 0.75))

            // Griglie verticali di tempo (divise in 10 sezioni)
            let timeDivisions = 10
            for i in 1..<timeDivisions {
                let x = (CGFloat(i) / CGFloat(timeDivisions)) * width
                gridPath.move(to: CGPoint(x: x, y: 0))
                gridPath.addLine(to: CGPoint(x: x, y: height))
            }
            
            context.stroke(gridPath, with: .color(Color.gray.opacity(0.18)), lineWidth: 1)

            // 2. Determina quanti campioni visualizzare in base al timebase (fino a 5.0s)
            let maxPointsForFiveSeconds = 10000
            let targetCount = Int(Double(maxPointsForFiveSeconds) * (min(5.0, max(0.05, timebaseSeconds)) / 5.0))
            
            let displaySamples: ArraySlice<Float>
            if samples.count > targetCount {
                displaySamples = samples.suffix(targetCount)
            } else {
                displaySamples = samples[...]
            }

            guard displaySamples.count > 1 else { return }
            let stepX = width / CGFloat(displaySamples.count - 1)

            // 3. Disegna forma d'onda a scorrimento (da sinistra verso destra)
            var wavePath = Path()
            let gainMultiplier = Float(verticalGain)
            for (index, sample) in displaySamples.enumerated() {
                let x = CGFloat(index) * stepX
                let scaledSample = sample * 0.1 * gainMultiplier
                let clampedSample = CGFloat(max(-1.0, min(1.0, scaledSample)))
                let y = midY - (clampedSample * (height / 2.2))

                if index == 0 {
                    wavePath.move(to: CGPoint(x: x, y: y))
                } else {
                    wavePath.addLine(to: CGPoint(x: x, y: y))
                }
            }

            // Bagliore neon dell'oscilloscopio
            context.stroke(wavePath, with: .color(lineColor.opacity(0.35)), lineWidth: 3.5)
            context.stroke(wavePath, with: .color(lineColor), lineWidth: 1.8)
        }
        .background(Color.black.opacity(0.88))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.cyan.opacity(0.35), lineWidth: 1)
        )
    }
}
