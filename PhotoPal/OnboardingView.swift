import Photos
import SwiftUI
import UIKit

/// First launch: pick a pal, customize it, let it sniff your camera roll, then scoop your first pile.
struct AdoptFlow: View {
    @EnvironmentObject var game: GameState
    @EnvironmentObject var library: PhotoLibrary

    private enum Step { case lineup, customize, access, scan }

    @State private var step: Step = .lineup
    @State private var species: Species = .dog
    @State private var name = ""
    @State private var paletteID = ""
    @State private var firstClean: JunkKind?
    @State private var scanned = false

    private var previewLook: PetLook {
        PetLook(species: species, paletteID: paletteID.isEmpty ? species.palettes[0].id : paletteID, custom: nil)
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: [Theme.terracotta.opacity(0.18), Color.mint.opacity(0.18)],
                           startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            switch step {
            case .lineup: lineup
            case .customize: customize
            case .access: access
            case .scan: scanStep
            }
        }
        .animation(.snappy, value: step)
        .sheet(item: $firstClean, onDismiss: { game.finishOnboarding() }) { kind in
            CleanupView(kind: kind)
        }
    }

    // MARK: 1. Pick an animal

    private var lineup: some View {
        VStack(spacing: 16) {
            Text("Adopt a pal")
                .font(Theme.largeTitle)
                .padding(.top, 30)
            Text("Your pal lives in your camera roll. Junk photos show up as poop, and your pal needs you to scoop it.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)

            TabView(selection: $species) {
                ForEach(Species.allCases) { sp in
                    VStack(spacing: 10) {
                        PetFigure(look: PetLook(species: sp, paletteID: sp.palettes[0].id, custom: nil),
                                  stage: .baby, mood: .happy, size: 190)
                        Text(sp.title).font(Theme.title2)
                        Text(sp.personality)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 30)
                    }
                    .tag(sp)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
            .frame(height: 400)

            Spacer()
            Button {
                paletteID = species.palettes[0].id
                name = species.defaultName
                step = .customize
            } label: {
                Text("Adopt the \(species.title.lowercased())")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.terracotta)
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
    }

    // MARK: 2. Name and colors

    private var customize: some View {
        ScrollView {
            VStack(spacing: 18) {
                PetFigure(look: previewLook, stage: .baby, mood: .thriving, size: 190)
                    .padding(.top, 24)

                TextField("Name", text: $name)
                    .font(Theme.title2)
                    .multilineTextAlignment(.center)
                    .padding(10)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 40)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Colors").font(Theme.headline)
                    HStack(spacing: 14) {
                        ForEach(species.palettes) { p in
                            let locked = p.price > 0
                            Button {
                                if !locked { paletteID = p.id }
                            } label: {
                                VStack(spacing: 4) {
                                    Circle()
                                        .fill(p.main.color)
                                        .overlay(Circle().fill(p.accent.color).frame(width: 14, height: 14).offset(x: 12, y: -12))
                                        .frame(width: 46, height: 46)
                                        .overlay(Circle().stroke(paletteID == p.id ? Theme.terracotta : Color.secondary.opacity(0.3),
                                                                 lineWidth: paletteID == p.id ? 3 : 1))
                                        .overlay {
                                            if locked {
                                                Image(systemName: "lock.fill")
                                                    .font(.caption)
                                                    .padding(5)
                                                    .background(.ultraThinMaterial, in: Circle())
                                            }
                                        }
                                    Text(p.name).font(.caption2).lineLimit(1)
                                }
                            }
                            .buttonStyle(.plain)
                            .opacity(locked ? 0.6 : 1)
                        }
                    }
                    Text("Locked colors unlock with coins later, in the Me tab.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                HStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.title2)
                        .foregroundStyle(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Have a real pet?").font(Theme.headline)
                        Text("Later you can unlock Photo Match: pick a photo of your pet and your pal copies their colors.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
                .background(Theme.plum.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                .padding(.horizontal)

                HStack(spacing: 12) {
                    Button("Back") { step = .lineup }
                        .buttonStyle(.bordered)
                    Button {
                        let trimmed = name.trimmingCharacters(in: .whitespaces)
                        game.adopt(species: species,
                                   name: trimmed.isEmpty ? species.defaultName : trimmed,
                                   paletteID: previewLook.paletteID)
                        step = library.hasAccess ? .scan : .access
                    } label: {
                        Text("Meet \(name.isEmpty ? species.defaultName : name)")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.terracotta)
                }
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    // MARK: 3. Photo access

    private var access: some View {
        VStack(spacing: 20) {
            Spacer()
            PalView(mood: .content, size: 170)
            Text("\(game.petName) needs to peek at your camera roll")
                .font(Theme.title2)
                .multilineTextAlignment(.center)
            Text("That's how \(game.petName) sniffs out the poop: old screenshots, duplicate shots and giant videos. Your photos never leave your phone, and nothing is deleted unless you say so.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal)
            Spacer()
            if library.status == .denied || library.status == .restricted {
                Text("Photo access is off. Turn it on in Settings to play.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button {
                    Task {
                        await library.requestAccess()
                        if library.hasAccess { step = .scan }
                    }
                } label: {
                    Text("Let \(game.petName) in").frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.terracotta)
            }
        }
        .padding(24)
    }

    // MARK: 4. The junk report

    private var scanStep: some View {
        ScrollView {
            VStack(spacing: 18) {
                if !scanned {
                    PalView(mood: .happy, size: 160)
                        .padding(.top, 60)
                    ProgressView("\(game.petName) is sniffing around...")
                } else if let report = library.report {
                    PalView(mood: report.junkCount > 0 ? .content : .thriving, size: 150)
                        .padding(.top, 24)
                    Text(report.junkCount > 0 ? "Uh oh! \(game.petName) found poop!" : "Wow, spotless!")
                        .font(Theme.title)
                    HealthCard(report: report)
                    ForEach(JunkKind.allCases) { kind in
                        if report.count(kind) > 0 {
                            HStack {
                                Image(systemName: kind.symbol).frame(width: 24)
                                Text(kind.title)
                                Spacer()
                                Text("\(report.count(kind))").bold()
                                Text(ByteCountFormatter.string(fromByteCount: report.bytesFor(kind), countStyle: .file))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.subheadline)
                            .padding(.horizontal, 8)
                        }
                    }
                    if let first = report.biggest {
                        Button {
                            firstClean = first
                        } label: {
                            Text("Scoop the \(first.title.lowercased()) first")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.sageDeep)
                        Button("Maybe later") { game.finishOnboarding() }
                            .foregroundStyle(.secondary)
                    } else {
                        Button {
                            game.finishOnboarding()
                        } label: {
                            Text("Go to \(game.petName)'s yard").frame(maxWidth: .infinity).padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.terracotta)
                    }
                }
            }
            .padding()
        }
        .task {
            guard !scanned else { return }
            await library.refresh(game, force: true)
            withAnimation(.spring) { scanned = true }
        }
    }
}

/// Shown if photo access gets turned off after setup
struct AccessView: View {
    @EnvironmentObject var game: GameState
    @EnvironmentObject var library: PhotoLibrary

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            PalView(mood: .grumpy, size: 170)
            Text("\(game.petName) can't see the camera roll")
                .font(Theme.title2)
                .multilineTextAlignment(.center)
            Text("Photo access is needed to find poop. Your photos never leave your phone.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
            if library.status == .notDetermined {
                Button("Allow photo access") {
                    Task { await library.requestAccess() }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.terracotta)
            } else {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.terracotta)
            }
        }
        .padding(24)
    }
}
