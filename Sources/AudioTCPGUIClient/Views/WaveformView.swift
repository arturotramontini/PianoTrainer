import SwiftUI

struct WaveformView: View {
    let samples: [Float]
    var lineColor: Color = .cyan

    var body: some View {
        Canvas { context, size in
            guard samples.count > 1 else { return }

            let width = size.width
            let height = size.height
            let midY = height / 2.0
            let stepX = width / CGFloat(samples.count - 1)

            // Disegna griglia di sfondo oscilloscopio
            var gridPath = Path()
            // Linea centrale
            gridPath.move(to: CGPoint(x: 0, y: midY))
            gridPath.addLine(to: CGPoint(x: width, y: midY))
            // Griglie orizzontali
            gridPath.move(to: CGPoint(x: 0, y: height * 0.25))
            gridPath.addLine(to: CGPoint(x: width, y: height * 0.25))
            gridPath.move(to: CGPoint(x: 0, y: height * 0.75))
            gridPath.addLine(to: CGPoint(x: width, y: height * 0.75))
            
            context.stroke(gridPath, with: .color(Color.gray.opacity(0.2)), lineWidth: 1)

            // Disegna forma d'onda
            var wavePath = Path()
            for (index, sample) in samples.enumerated() {
                let x = CGFloat(index) * stepX
                // Normalizza campioni (supposti tra -1.0 e +1.0 o scalati dal volume)
                let clampedSample = CGFloat(max(-1.0, min(1.0, sample * 0.1)))
                let y = midY - (clampedSample * (height / 2.2))

                if index == 0 {
                    wavePath.move(to: CGPoint(x: x, y: y))
                } else {
                    wavePath.addLine(to: CGPoint(x: x, y: y))
                }
            }

            // Glow / Ombra azzurra
            context.stroke(wavePath, with: .color(lineColor.opacity(0.4)), lineWidth: 4)
            context.stroke(wavePath, with: .color(lineColor), lineWidth: 2)
        }
        .background(Color.black.opacity(0.85))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.cyan.opacity(0.3), lineWidth: 1)
        )
    }
}
