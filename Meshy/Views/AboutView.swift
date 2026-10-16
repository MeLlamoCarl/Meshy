//
//  AboutView.swift
//  Meshy
//
//  Created by Ethan Lipnik on 8/2/22.
//

import SwiftUI

struct AboutView: View {
    static let repositoryURL = URL(string: "https://github.com/MeLlamoCarl/Meshy")!
    static let originalProjectURL = URL(string: "https://github.com/EthanLipnik/Acrylic")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        return "Version \(info?["CFBundleShortVersionString"] ?? "?") (\(info?["CFBundleVersion"] ?? "?"))"
    }

    var body: some View {
        VStack {
            Image("Icon")
                .resizable()
                .aspectRatio(1 / 1, contentMode: .fit)
                .frame(maxWidth: 100)
            Text("Meshy")
                .font(.largeTitle)
                .bold()
            Text(version)
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("by MeLlamoCarl")
                .font(.callout)
                .foregroundStyle(.secondary)
            Text("Based on Acrylic by Ethan Lipnik")
                .font(.callout)
                .foregroundStyle(.secondary)
            LinksView()
            CreditsView()
            Spacer()
        }
        .padding()
        .background(
            VisualEffectView(material: .popover, blendingMode: .behindWindow)
                .edgesIgnoringSafeArea(.all)
        )
    }

    struct LinksView: View {
        var body: some View {
            GroupBox {
                VStack(alignment: .leading) {
                    link("Meshy on GitHub", systemImage: "chevron.left.forwardslash.chevron.right", AboutView.repositoryURL)
                    link("Original Acrylic project", systemImage: "arrow.triangle.branch", AboutView.originalProjectURL)
                    link("MeshKit", systemImage: "circle.grid.cross", URL(string: "https://github.com/MeLlamoCarl/MeshKit")!)
                    link("MeshGradient", systemImage: "square.stack.3d.forward.dottedline",
                         URL(string: "https://github.com/MeLlamoCarl/MeshGradient")!)

                    Link(destination: URL(string: "https://pixabay.com/")!) {
                        HStack {
                            Image(systemName: "photo")
                            Image("Pixabay")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        }
                        .frame(height: 15)
                    }
                }
            } label: {
                Label("Links", systemImage: "link")
            }
        }

        func link(_ title: String, systemImage: String, _ url: URL) -> some View {
            Link(destination: url) {
                Label(title, systemImage: systemImage)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    struct CreditsView: View {
        @Environment(\.openURL)
        var openUrl

        var body: some View {
            GroupBox {
                userView("MeLlamoCarl", username: "MeLlamoCarl", body: "Meshy app")
                Divider()
                userView("Ethan Lipnik", username: "EthanLipnik", body: "Original Acrylic app")
                Divider()
                userView("Nikita Patskov", username: "patskovn", body: "MeshGradient library")
            } label: {
                Label("Credits", systemImage: "person.crop.square.filled.and.at.rectangle")
            }
        }

        /// GitHub profile with its public avatar.
        @ViewBuilder
        func userView(_ name: String, username: String, body: String) -> some View {
            Button {
                if let url = URL(string: "https://github.com/" + username) {
                    openUrl(url)
                }
            } label: {
                HStack {
                    AsyncImage(url: URL(string: "https://github.com/\(username).png?size=90")) { phase in
                        switch phase {
                        case let .success(image):
                            image
                                .resizable()
                        default:
                            Color.secondary
                        }
                    }
                    .aspectRatio(1 / 1, contentMode: .fit)
                    .frame(height: 45)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    VStack(alignment: .leading) {
                        HStack {
                            Text(name)
                                .font(.headline)
                            Text("@" + username)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                        Text(body)
                    }
                }
            }.buttonStyle(.plain)
        }
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
            .frame(width: 500, height: 400)
    }
}
