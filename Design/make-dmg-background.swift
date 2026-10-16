// Renders the DMG window background (560×360 pt, @1x and @2x) in Meshy's mesh style, in the
// installer's green and yellow. Run: swiftc -o /tmp/bg Design/make-dmg-background.swift && /tmp/bg out-folder,
// then: tiffutil -cathidpicheck out-folder/background.png out-folder/background@2x.png -out Design/DMG/background.tiff
import AppKit
import SwiftUI

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

let night  = Color(red: 0.01, green: 0.08, blue: 0.04)
let navy   = Color(red: 0.03, green: 0.20, blue: 0.10)
let green  = Color(red: 0.10, green: 0.45, blue: 0.22)
let olive  = Color(red: 0.20, green: 0.38, blue: 0.08)
let gold   = Color(red: 0.62, green: 0.52, blue: 0.05)
let yellow = Color(red: 0.85, green: 0.74, blue: 0.20)

struct Background: View {
    var body: some View {
        ZStack {
            MeshGradient(width: 3, height: 3, points: [
                [0, 0], [0.5, 0], [1, 0],
                [0, 0.5], [0.45, 0.55], [1, 0.4],
                [0, 1], [0.55, 1], [1, 1],
            ], colors: [night, navy, olive,
                        navy, green, gold,
                        olive, navy, night])

            VStack(spacing: 0) {
                Text("Drag Meshy to Applications")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 34)
                Spacer()
                // Kept above the bottom edge: Finder's path bar, if shown, covers the last ~28 pt.
                Text("First launch: System Settings › Privacy & Security › Open Anyway")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.8))
                    .padding(.bottom, 48)
            }

            // Arrow between the app (x 140) and Applications (x 420), at the icons' height.
            Path { path in
                path.move(to: CGPoint(x: 232, y: 170))
                path.addLine(to: CGPoint(x: 322, y: 170))
                path.move(to: CGPoint(x: 302, y: 152))
                path.addLine(to: CGPoint(x: 324, y: 170))
                path.addLine(to: CGPoint(x: 302, y: 188))
            }
            .stroke(.white.opacity(0.85), style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
        }
        .frame(width: 560, height: 360)
    }
}

@MainActor func render(scale: CGFloat, name: String) {
    let renderer = ImageRenderer(content: Background())
    renderer.scale = scale
    let rep = NSBitmapImageRep(cgImage: renderer.cgImage!)
    rep.size = NSSize(width: 560, height: 360)  // points, so @2x keeps its density
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    print("wrote", name)
}

MainActor.assumeIsolated {
    render(scale: 1, name: "background.png")
    render(scale: 2, name: "background@2x.png")
}
