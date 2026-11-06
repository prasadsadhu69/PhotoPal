import Photos
import PhotosUI
import SwiftUI
import UIKit

/// Your pal's profile (tap their name in the yard): level, other pals, milestones, stats
struct ProfileSheet: View {
    var body: some View {
        ClosetView(mode: .profile)
    }
}

/// Closet tab (colors, Photo Match, outfits) and the profile sheet share this screen
struct ClosetView: View {
    enum Mode { case closet, profile }
    var mode: Mode = .closet

    @EnvironmentObject var game: GameState
    @EnvironmentObject var library: PhotoLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var renaming = false
    @State private var draftName = ""
    @State private var pendingPalette: PetPalette?
    @State private var photoItem: PhotosPickerItem?
    @State private var matching = false
    @State private var matchFailed = false
    @State private var confirmReset = false
    @State private var confirmUnlock = false
    @State private var showAdopt = false

    private let outfitColumns = [GridItem(.adaptive(minimum: 96), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if mode == .closet {
                        closetHeader
                        colorsSection
                        photoMatchSection
                        outfitSection("Hats", category: .hat)
                        outfitSection("Neckwear", category: .neck)
                        outfitShop
                    } else {
                        profileCard
                        familySection
                        milestonesSection
                        statsSection
                        Button("Start over with a new pal", role: .destructive) { confirmReset = true }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 8)
                    }
                }
                .padding()
            }
            .paperBackground()
            .navigationTitle(mode == .closet ? "Closet" : game.petName)
            .navigationBarTitleDisplayMode(mode == .closet ? .large : .inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { CoinBadge() }
                if mode == .profile {
                    ToolbarItem(placement: .topBarLeading) { Button("Done") { dismiss() } }
                }
            }
            .alert("Rename your pal", isPresented: $renaming) {
                TextField("Name", text: $draftName)
                Button("Save") {
                    let trimmed = draftName.trimmingCharacters(in: .whitespaces)
                    if !trimmed.isEmpty { game.petName = trimmed }
                }
                Button("Cancel", role: .cancel) {}
            }
            .alert(pendingPalette.map { "Unlock \($0.name) for \($0.price) coins?" } ?? "",
                   isPresented: Binding(get: { pendingPalette != nil }, set: { if !$0 { pendingPalette = nil } })) {
                Button("Unlock") {
                    if let p = pendingPalette { game.choosePalette(p) }
                    pendingPalette = nil
                }
                Button("Cancel", role: .cancel) { pendingPalette = nil }
            }
            .alert("Unlock Photo Match for \(GameState.photoMatchPrice) coins?", isPresented: $confirmUnlock) {
                Button("Unlock") { game.unlockPhotoMatch() }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Couldn't read that photo", isPresented: $matchFailed) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Try a clear, well-lit photo where your pet fills most of the picture.")
            }
            .confirmationDialog("Start over?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Erase \(game.petName) and start over", role: .destructive) { game.resetGame() }
            } message: {
                Text("Your coins, items and progress will be erased. Your photos are not affected.")
            }
            .sheet(isPresented: $showAdopt) { AdoptSheet() }
            .onChange(of: photoItem) { _, item in
                guard let item else { return }
                Task { await match(item) }
            }
        }
    }

    // MARK: Closet

    private var closetHeader: some View {
        ZStack {
            Ellipse()
                .fill(Theme.plum.opacity(0.2))
                .overlay(Ellipse().inset(by: 6).stroke(Theme.plum.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                .frame(width: 220, height: 56)
                .offset(y: 84)
            PalView(mood: .happy, size: 160)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 240)
        .paperCard(padding: 8, radius: 28)
    }

    @ViewBuilder
    private var outfitShop: some View {
        let forSale = ShopItem.all.filter { ($0.category == .hat || $0.category == .neck) && !game.owns($0) }
        if !forSale.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Shop: Outfits").font(Theme.title3)
                ForEach(forSale) { item in ShopRow(item: item) }
            }
        }
    }

    // MARK: Profile

    private var profileCard: some View {
        VStack(spacing: 10) {
            PalView(size: 170)
                .frame(maxWidth: .infinity)
                .frame(height: 240)
                .paperCard(padding: 8, radius: 28)
            HStack {
                Text(game.petName).font(Theme.title2)
                Button {
                    draftName = game.petName
                    renaming = true
                } label: {
                    Image(systemName: "pencil")
                }
            }
            Text("\(game.stage.name(for: game.species)) · Lv. \(game.level) · \(game.ageDays) day\(game.ageDays == 1 ? "" : "s") old")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if game.stage.next != nil {
                StageTrack(stage: game.stage, progress: game.growthProgress, species: game.species)
            }
            Text(game.nextStageHint)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Family

    private var familySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Your pals").font(Theme.headline)
                Spacer()
                Text("\(1 + game.otherPals.count) of \(Species.allCases.count) animals")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    palCard(name: game.petName, look: game.look, stage: game.stage, active: true) {}
                    ForEach(game.otherPals) { pal in
                        palCard(name: pal.name, look: pal.look, stage: pal.stage, active: false) {
                            withAnimation(.snappy) { game.switchTo(pal.id) }
                        }
                    }
                    if !game.speciesToAdopt.isEmpty {
                        Button {
                            showAdopt = true
                        } label: {
                            VStack(spacing: 6) {
                                Image(systemName: game.tickets > 0 ? "plus.circle.fill" : "lock.fill")
                                    .font(.title)
                                    .foregroundStyle(game.tickets > 0 ? Theme.terracotta : Color.secondary)
                                    .frame(height: 70)
                                Text(game.tickets > 0 ? "Adopt (\(game.tickets))" : "Locked")
                                    .font(.caption.bold())
                            }
                            .frame(width: 96, height: 120)
                            .background(Theme.terracotta.opacity(0.08), in: RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(.plain)
                        .disabled(game.tickets == 0)
                    }
                }
            }
            Text(game.tickets > 0
                 ? "You have \(game.tickets) adoption ticket\(game.tickets == 1 ? "" : "s")! Tap Adopt to bring home a new baby."
                 : "Earn adoption tickets when your pal grows into a Teen, then Grown, then Legendary. Tap a pal to care for them; the others relax in the yard.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func palCard(name: String, look: PetLook, stage: LifeStage, active: Bool, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            VStack(spacing: 4) {
                PetFigure(look: look, stage: stage, mood: .happy, size: 56, animated: false)
                    .frame(width: 62, height: 72)
                Text(name).font(.caption.bold()).lineLimit(1)
                Text(active ? "Caring now" : stage.name(for: look.species))
                    .font(.caption2)
                    .foregroundStyle(active ? Theme.terracotta : Color.secondary)
                    .lineLimit(1)
            }
            .frame(width: 96, height: 120)
            .background(active ? Theme.terracotta.opacity(0.15) : Color.secondary.opacity(0.08),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(active ? Theme.terracotta : Color.clear, lineWidth: 2))
        }
        .buttonStyle(.plain)
        .disabled(active)
    }

    // MARK: Colors

    private var colorsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Colors").font(Theme.headline)
            HStack(spacing: 14) {
                ForEach(game.species.palettes) { p in
                    let owned = game.ownsPalette(p)
                    let using = game.isUsingPalette(p)
                    Button {
                        if owned {
                            withAnimation(.snappy) { _ = game.choosePalette(p) }
                        } else {
                            pendingPalette = p
                        }
                    } label: {
                        VStack(spacing: 4) {
                            Circle()
                                .fill(p.main.color)
                                .overlay(Circle().fill(p.accent.color).frame(width: 14, height: 14).offset(x: 12, y: -12))
                                .frame(width: 46, height: 46)
                                .overlay(Circle().stroke(using ? Theme.terracotta : Color.secondary.opacity(0.3), lineWidth: using ? 3 : 1))
                                .overlay {
                                    if !owned {
                                        Image(systemName: "lock.fill")
                                            .font(.caption)
                                            .padding(5)
                                            .background(.ultraThinMaterial, in: Circle())
                                    }
                                }
                            Text(owned ? p.name : "\(p.price)")
                                .font(.caption2)
                                .lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Photo Match

    private var photoMatchSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Photo Match").font(Theme.headline)
            Text("Pick a photo of your real pet and \(game.petName) copies their colors. It all happens on your phone.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if game.photoMatchUnlocked {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    HStack {
                        if matching { ProgressView() } else { Image(systemName: "camera.fill") }
                        Text(matching ? "Matching..." : "Choose a pet photo")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.plum)
                .disabled(matching)
                if game.look.custom != nil {
                    Label("Using your pet's colors", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            } else {
                Button {
                    confirmUnlock = true
                } label: {
                    Label("Unlock for \(GameState.photoMatchPrice) coins", systemImage: "lock.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(Theme.plum)
                .disabled(game.coins < GameState.photoMatchPrice)
            }
        }
        .padding()
        .background(Theme.plum.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    private func match(_ item: PhotosPickerItem) async {
        matching = true
        defer {
            matching = false
            photoItem = nil
        }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let palette = await PhotoMatch.palette(from: data, name: "My pet") else {
            matchFailed = true
            return
        }
        withAnimation(.spring) { game.applyCustomPalette(palette) }
    }

    // MARK: Outfits

    private func outfitSection(_ title: String, category: ItemCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(Theme.headline)
            if !ShopItem.all.contains(where: { $0.category == category && game.owns($0) }) {
                Text("Nothing here yet. Find \(title.lowercased()) in the shop below.")
                    .font(.caption)
                    .opacity(0.7)
            }
            LazyVGrid(columns: outfitColumns, spacing: 10) {
                ForEach(ShopItem.all.filter { $0.category == category && game.owns($0) }) { item in
                    let owned = game.owns(item)
                    let wearing = game.isWearing(item)
                    Button {
                        guard owned else { return }
                        withAnimation(.snappy) { game.toggleWear(item) }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    } label: {
                        VStack(spacing: 4) {
                            ItemIcon(item: item).frame(height: 56)
                            Text(item.name).font(.caption).lineLimit(1)
                            if !owned {
                                Label("\(item.price)", systemImage: "lock.fill").font(.caption2)
                            } else if wearing {
                                Text("Wearing").font(.caption2.bold()).foregroundStyle(Theme.terracotta)
                            }
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity)
                        .background(wearing ? Theme.terracotta.opacity(0.15) : Color.secondary.opacity(0.1),
                                    in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14)
                            .stroke(wearing ? Theme.terracotta : Color.clear, lineWidth: 2))
                        .opacity(owned ? 1 : 0.45)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Milestones and stats

    private var milestonesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Milestones").font(Theme.headline)
            ForEach(Milestone.all) { m in
                let done = game.milestonesReached.contains(m.id)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: done ? "checkmark.seal.fill" : "seal")
                            .foregroundStyle(done ? Color.green : Color.secondary)
                        Text(m.title).font(.subheadline)
                        Spacer()
                        Text("+\(m.coins)").font(.caption.bold()).foregroundStyle(Theme.mustard)
                    }
                    if !done {
                        ProgressView(value: min(1, Double(game.bytesFreed) / Double(m.bytes)))
                            .tint(Theme.sageDeep)
                    }
                }
            }
        }
    }

    private var statsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stats").font(Theme.headline)
            LabeledContent("Space freed", value: ByteCountFormatter.string(fromByteCount: game.bytesFreed, countStyle: .file))
            LabeledContent("Poops scooped", value: "\(game.itemsTossed)")
            LabeledContent("Scooping sessions", value: "\(game.cleanups)")
            LabeledContent("Daily streak", value: "\(game.streak)")
            LabeledContent("Care mistakes", value: "\(game.careMistakes)")
            LabeledContent("Cozy score", value: "\(game.cozy)")
        }
        .font(.subheadline)
    }
}

// MARK: - Growing up track (Baby > Little > Teen > Grown > Legendary)

struct StageTrack: View {
    let stage: LifeStage
    let progress: Double
    let species: Species

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 4) {
                ForEach(LifeStage.allCases, id: \.self) { s in
                    let reached = s.xpNeeded <= stage.xpNeeded
                    VStack(spacing: 3) {
                        Circle()
                            .fill(reached ? Theme.plum : Color.secondary.opacity(0.25))
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Theme.plum, lineWidth: s == stage ? 3 : 0).padding(-3))
                        Text(s == .baby ? species.babyName : s.title)
                            .font(.system(size: 9, weight: s == stage ? .bold : .regular))
                            .foregroundStyle(reached ? Color.primary : Color.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            ProgressView(value: progress).tint(Theme.plum)
        }
    }
}

// MARK: - Adopt another pal with a ticket

struct AdoptSheet: View {
    @EnvironmentObject var game: GameState
    @Environment(\.dismiss) private var dismiss

    @State private var species: Species?
    @State private var name = ""
    @State private var paletteID = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    if let species {
                        PetFigure(look: PetLook(species: species, paletteID: paletteID, custom: nil),
                                  stage: .baby, mood: .thriving, size: 170)
                        TextField("Name", text: $name)
                            .font(Theme.title2)
                            .multilineTextAlignment(.center)
                            .padding(10)
                            .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal, 40)
                        HStack(spacing: 14) {
                            ForEach(species.palettes.filter { $0.price == 0 }) { p in
                                Button {
                                    paletteID = p.id
                                } label: {
                                    Circle().fill(p.main.color)
                                        .frame(width: 44, height: 44)
                                        .overlay(Circle().stroke(paletteID == p.id ? Theme.terracotta : Color.secondary.opacity(0.3),
                                                                 lineWidth: paletteID == p.id ? 3 : 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        Button {
                            let trimmed = name.trimmingCharacters(in: .whitespaces)
                            if game.adoptNewPal(species: species, name: trimmed.isEmpty ? species.defaultName : trimmed,
                                                paletteID: paletteID) {
                                UINotificationFeedbackGenerator().notificationOccurred(.success)
                                dismiss()
                            }
                        } label: {
                            Text("Adopt \(name.isEmpty ? species.defaultName : name)")
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.terracotta)
                        Button("Pick a different animal") { self.species = nil }
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Who's joining the family?")
                            .font(Theme.title2)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                            ForEach(game.speciesToAdopt) { sp in
                                Button {
                                    species = sp
                                    name = sp.defaultName
                                    paletteID = sp.palettes[0].id
                                } label: {
                                    VStack(spacing: 6) {
                                        PetFigure(look: PetLook(species: sp, paletteID: sp.palettes[0].id, custom: nil),
                                                  stage: .baby, mood: .happy, size: 90)
                                            .frame(height: 120)
                                        Text(sp.babyName).font(Theme.headline)
                                        Text(sp.personality)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .multilineTextAlignment(.center)
                                            .lineLimit(3)
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity)
                                    .background(Theme.terracotta.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Adopt a pal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
        }
    }
}
