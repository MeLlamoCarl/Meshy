// Generates Meshy's menu bar icon and wallpaper-type thumbnails into the asset catalog.
// Run: swiftc -o /tmp/make-app-art Design/make-app-art.swift && /tmp/make-app-art Acrylic/Assets.xcassets
import AppKit
import SwiftUI

let assets = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)

let navy   = Color(red: 0.05, green: 0.07, blue: 0.27)
let blue   = Color(red: 0.13, green: 0.25, blue: 0.78)
let azure  = Color(red: 0.20, green: 0.45, blue: 0.98)
let indigo = Color(red: 0.24, green: 0.13, blue: 0.62)
let purple = Color(red: 0.42, green: 0.14, blue: 0.70)
let violet = Color(red: 0.62, green: 0.30, blue: 0.95)
let night  = Color(red: 0.03, green: 0.03, blue: 0.12)

func mesh(_ colors: [Color]) -> MeshGradient {
    MeshGradient(width: 3, height: 3, points: [
        [0, 0], [0.5, 0], [1, 0],
        [0, 0.5], [0.4, 0.55], [1, 0.45],
        [0, 1], [0.55, 1], [1, 1],
    ], colors: colors)
}

/// Same superellipse as the app icon (n ≈ 5), optionally offset outward along its normal.
struct Squircle: Shape {
    var offset: CGFloat = 0
    func path(in rect: CGRect) -> Path {
        let n = 5.0, steps = 720
        let r = Double(min(rect.width, rect.height)) / 2 - Double(offset), c = (Double(rect.midX), Double(rect.midY))
        func point(_ t: Double) -> (Double, Double) {
            (c.0 + r * copysign(pow(abs(cos(t)), 2 / n), cos(t)), c.1 + r * copysign(pow(abs(sin(t)), 2 / n), sin(t)))
        }
        var path = Path()
        for i in 0..<steps {
            let t = 2 * Double.pi * Double(i) / Double(steps), h = Double.pi / Double(steps)
            let p = point(t), a = point(t - h), b = point(t + h)
            let dx = b.0 - a.0, dy = b.1 - a.1, l = max(hypot(dx, dy), 1e-9)
            let q = CGPoint(x: p.0 + Double(offset) * dy / l, y: p.1 - Double(offset) * dx / l)
            i == 0 ? path.move(to: q) : path.addLine(to: q)
        }
        path.closeSubpath()
        return path
    }
}

@MainActor func write<V: View>(_ view: V, size: CGSize, scale: CGFloat = 1, to url: URL) {
    let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
    renderer.scale = scale
    renderer.isOpaque = false
    let rep = NSBitmapImageRep(cgImage: renderer.cgImage!)
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
    print("wrote", url.lastPathComponent)
}

func writeContents(_ json: String, in folder: URL) {
    try! json.write(to: folder.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

@MainActor func run() {
    let fm = FileManager.default

    // Menu bar icon (template): bezel ring + translucent screen, like the app icon.
    let menubar = assets.appendingPathComponent("Menubar.imageset")
    try? fm.removeItem(at: menubar)
    try! fm.createDirectory(at: menubar, withIntermediateDirectories: true)
    let bezel: CGFloat = 1.8, screen: CGFloat = 12.4
    let glyph = ZStack {
        Squircle().fill(Color.black.opacity(0.35)).frame(width: screen, height: screen)
        Squircle(offset: -bezel).fill(Color.black, style: FillStyle(eoFill: true))
            .overlay(Squircle().fill(Color.black).frame(width: screen, height: screen).blendMode(.destinationOut))
            .compositingGroup()
            .frame(width: screen + 2 * bezel, height: screen + 2 * bezel)
    }
    for scale in [1, 2, 3] {
        write(glyph, size: CGSize(width: 18, height: 18), scale: CGFloat(scale),
              to: menubar.appendingPathComponent("Menubar@\(scale)x.png"))
    }
    writeContents("""
    {
      "images" : [
        { "filename" : "Menubar@1x.png", "idiom" : "universal", "scale" : "1x" },
        { "filename" : "Menubar@2x.png", "idiom" : "universal", "scale" : "2x" },
        { "filename" : "Menubar@3x.png", "idiom" : "universal", "scale" : "3x" }
      ],
      "info" : { "author" : "xcode", "version" : 1 },
      "properties" : { "template-rendering-intent" : "template" }
    }
    """, in: menubar)

    // Wallpaper type thumbnails (16:10). The Video thumbnail is a Pixabay preview (video 67358 by
    // Engin_Akyurt, Pixabay Content License), not generated here.
    let size = CGSize(width: 1024, height: 640)
    let thumbnails: [(String, String, AnyView)] = [
        ("FluidThumbnail", "Fluid", AnyView(mesh([violet, purple, azure, indigo, azure, blue, navy, violet, purple]))),
        ("NowplayingThumbnail", "Music", AnyView(ZStack {
            mesh([purple, violet, indigo, blue, azure, purple, navy, indigo, violet])
            Image(systemName: "music.note").font(.system(size: 150, weight: .bold)).foregroundStyle(.white.opacity(0.9))
        })),
    ]
    for (set, name, view) in thumbnails {
        let folder = assets.appendingPathComponent("Thumbnails/\(set).imageset")
        try? fm.removeItem(at: folder)
        try! fm.createDirectory(at: folder, withIntermediateDirectories: true)
        write(view, size: size, to: folder.appendingPathComponent("\(name).png"))
        writeContents("""
        {
          "images" : [ { "filename" : "\(name).png", "idiom" : "universal" } ],
          "info" : { "author" : "xcode", "version" : 1 }
        }
        """, in: folder)
    }
}

MainActor.assumeIsolated { run() }
