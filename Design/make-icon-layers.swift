import SwiftUI
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
let canvas: CGFloat = 1024

// Usage: make-icon-layers <output folder> [installer]
// "installer" renders the DMG volume icon: green and yellow gradients plus a download arrow.
let isInstaller = CommandLine.arguments.dropFirst(2).first == "installer"

// App icon: close to MeshKit's Blue + Purple with dark luminosity.
// Installer: the same roles in greens and yellows.
let navy   = isInstaller ? Color(red: 0.03, green: 0.20, blue: 0.10) : Color(red: 0.05, green: 0.07, blue: 0.27)
let blue   = isInstaller ? Color(red: 0.10, green: 0.55, blue: 0.25) : Color(red: 0.13, green: 0.25, blue: 0.78)
let azure  = isInstaller ? Color(red: 0.55, green: 0.85, blue: 0.20) : Color(red: 0.20, green: 0.45, blue: 0.98)
let indigo = isInstaller ? Color(red: 0.20, green: 0.40, blue: 0.08) : Color(red: 0.24, green: 0.13, blue: 0.62)
let purple = isInstaller ? Color(red: 0.75, green: 0.62, blue: 0.05) : Color(red: 0.42, green: 0.14, blue: 0.70)
let violet = isInstaller ? Color(red: 0.98, green: 0.85, blue: 0.25) : Color(red: 0.62, green: 0.30, blue: 0.95)
let night  = isInstaller ? Color(red: 0.01, green: 0.08, blue: 0.04) : Color(red: 0.03, green: 0.03, blue: 0.12)

func mesh(_ colors: [Color], points: [SIMD2<Float>]? = nil) -> MeshGradient {
    MeshGradient(width: 3, height: 3, points: points ?? [
        [0, 0], [0.5, 0], [1, 0],
        [0, 0.5], [0.42, 0.56], [1, 0.45],
        [0, 1], [0.55, 1], [1, 1],
    ], colors: colors)
}

@MainActor func save<V: View>(_ view: V, _ name: String) {
    let renderer = ImageRenderer(content: view.frame(width: canvas, height: canvas))
    renderer.scale = 1
    renderer.isOpaque = false
    guard let cg = renderer.cgImage else { print("render failed", name); return }
    let rep = NSBitmapImageRep(cgImage: cg)
    try! rep.representation(using: .png, properties: [:])!.write(to: out.appendingPathComponent(name))
    print("wrote", name)
}

@MainActor func run() {
    // 1. Background
    let background = mesh([night, navy, indigo,
                           navy, blue, purple,
                           indigo, navy, night])
    save(background, "1 Background.png")

    // 2. Rays: soft beams fanning down from the top centre
    let rays = ZStack {
        ForEach(0..<7) { i in
            let angle = Double(i - 3) * 9
            let tint: Color = [violet, azure, .white, violet, azure, .white, violet][i]
            LinearGradient(colors: [tint.opacity(i == 3 ? 0.85 : 0.55), tint.opacity(0)],
                           startPoint: .top, endPoint: .bottom)
                .frame(width: i == 3 ? 150 : 90, height: 760)
                .blur(radius: 28)
                .rotationEffect(.degrees(angle), anchor: .top)
                .position(x: canvas / 2, y: 380)
        }
    }
    .frame(width: canvas, height: canvas)
    save(rays, "2 Rays.png")
}
MainActor.assumeIsolated { run() }

// 3. Glass square: a flat, opaque shape (Icon Composer adds the Liquid Glass effect per group).
// Apple's icon shape is close to a superellipse (n ≈ 5); the square is the same curve scaled down.
/// Points on the icon-like superellipse (n ≈ 5), optionally offset outward by `offset` along the
/// curve's normal. An offset curve has radius of curvature r + offset at every point, so a bezel
/// built this way satisfies outer radius = inner radius + bezel width (concentric corners).
func squirclePoints(_ size: Double, offset: Double = 0, n: Double = 5, c: Double = 512, steps: Int = 2880) -> [(Double, Double)] {
    let r = size / 2
    func point(_ t: Double) -> (Double, Double) {
        (c + r * copysign(pow(abs(cos(t)), 2 / n), cos(t)), c + r * copysign(pow(abs(sin(t)), 2 / n), sin(t)))
    }
    return (0..<steps).map { i in
        let t = 2 * Double.pi * Double(i) / Double(steps), h = Double.pi / Double(steps)
        let p = point(t), a = point(t - h), b = point(t + h)
        let dx = b.0 - a.0, dy = b.1 - a.1, length = max(hypot(dx, dy), 1e-9)
        // Counter-clockwise curve: the outward normal is (dy, -dx).
        return (p.0 + offset * dy / length, p.1 - offset * dx / length)
    }
}
func squircle(_ size: Double, offset: Double = 0) -> String {
    "M" + squirclePoints(size, offset: offset).map { String(format: "%.2f,%.2f", $0.0, $0.1) }.joined(separator: " L") + " Z"
}
func writeSVG(_ body: String, _ name: String) {
    let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
      \(body)
    </svg>

    """
    try! svg.write(to: out.appendingPathComponent(name), atomically: true, encoding: .utf8)
    print("wrote", name)
}
let glassSize = 620.0, bezelWidth = 48.0
// Icon Composer recolours SVG layers with its automatic gradient; the installer's green glass is
// set with a solid "fill" on the layer in its icon.json instead.
writeSVG("<path d=\"\(squircle(glassSize))\" fill=\"#FFFFFF\"/>", "3 Glass Square.svg")
// 4. Screen bezel: black ring outside the glass square (its own group, opaque).
writeSVG("<path fill-rule=\"evenodd\" d=\"\(squircle(glassSize, offset: bezelWidth)) \(squircle(glassSize))\" fill=\"#000000\"/>",
         "4 Screen Bezel.svg")

// 5. Installer only: download arrow (its own group, above the bezel).
if isInstaller {
    writeSVG("""
    <g fill="none" stroke="#FFFFFF" stroke-width="72" stroke-linecap="round" stroke-linejoin="round">
        <path d="M512 300 L512 640"/>
        <path d="M382 520 L512 650 L642 520"/>
        <path d="M352 740 L672 740"/>
      </g>
    """, "5 Download Arrow.svg")
}
