import AVKit
import SwiftUI
import UIKit
import Photos

// MARK: - Payout after scooping

struct RewardView: View {
    let reward: CleanReward
    let done: () -> Void
    @EnvironmentObject var game: GameState
    @State private var pop = false
    /// 0 = bag appears, 1 = bag ties up, 2 = bursts into coins, 3 = totals
    @State private var phase = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                ZStack {
                    if phase < 2 {
                        ScoopBag(tied: phase >= 1)
                            .frame(width: 120, height: 130)
                            .transition(.scale(scale: 1.4).combined(with: .opacity))
                    } else {
                        PalView(mood: .thriving, size: 140)
                            .transition(.scale.combined(with: .opacity))
                        CoinBurst()
                    }
                }
                .frame(height: 200)
                .padding(.top, 16)

                if phase >= 2 {
                    Text("+\(reward.total) coins")
                        .font(Theme.header(44, "Bold", relativeTo: .largeTitle))
                        .foregroundStyle(Theme.mustard)
                        .scaleEffect(pop ? 1 : 0.4)
                        .onAppear { withAnimation(.spring(response: 0.4, dampingFraction: 0.5)) { pop = true } }
                } else {
                    Text(phase == 0 ? "Bagging it up..." : "All tied up!")
                        .font(Theme.title3)
                }
                if phase >= 3 {
                Text("\(game.petName) is so happy the yard is cleaner!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let stage = reward.grewTo {
                    Label("\(game.petName) grew into a \(stage.name(for: game.species).lowercased())!", systemImage: "star.fill")
                        .font(Theme.headline)
                        .foregroundStyle(Theme.plum)
                }

                VStack(spacing: 10) {
                    row("Scooped \(reward.count) \(reward.kind.title.lowercased())", "+\(reward.coins)")
                    row("Space freed", ByteCountFormatter.string(fromByteCount: reward.bytes, countStyle: .file))
                    if reward.firstTodayBonus > 0 { row("First scoop of the day", "+\(reward.firstTodayBonus)") }
                    if reward.streakBonus > 0 { row("\(game.streak)-day streak bonus", "+\(reward.streakBonus)") }
                    if reward.dailyBonus > 0 { row("Today's bounty complete!", "+\(reward.dailyBonus)") }
                    ForEach(reward.milestones) { m in
                        row(m.title, "+\(m.coins)")
                        if let gift = m.gift, let item = ShopItem.byID(gift) {
                            row("Gift: \(item.name)", "In your closet")
                        }
                    }
                }
                .paperCard()

                if reward.bytes > 3_000_000 {
                    Text("That's room for about \(Int(reward.bytes / 3_000_000).formatted()) new photos.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    done()
                } label: {
                    Text("Back to the yard").font(Theme.headline).frame(maxWidth: .infinity).padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.sageDeep)
                }
            }
            .padding()
        }
        .task {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            try? await Task.sleep(for: .seconds(0.7))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.5)) { phase = 1 }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            try? await Task.sleep(for: .seconds(0.7))
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) { phase = 2 }
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            try? await Task.sleep(for: .seconds(0.6))
            withAnimation(.easeOut) { phase = 3 }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).bold().monospacedDigit()
        }
    }
}

// MARK: - Scoop bag and coin burst

/// A little paper scoop bag that ties itself up
struct ScoopBag: View {
    let tied: Bool

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            ZStack(alignment: .top) {
                // bag body
                UnevenRoundedRectangle(topLeadingRadius: w * 0.12, bottomLeadingRadius: w * 0.22,
                                       bottomTrailingRadius: w * 0.22, topTrailingRadius: w * 0.12)
                    .fill(LinearGradient(colors: [Theme.cork, Theme.woodLight], startPoint: .top, endPoint: .bottom))
                    .overlay(PaperGrain(opacity: 0.12).clipShape(RoundedRectangle(cornerRadius: w * 0.2)))
                    .frame(width: w * (tied ? 0.82 : 0.9), height: h * 0.7)
                    .offset(y: h * 0.28)
                // gathered top
                Triangle()
                    .fill(Theme.cork)
                    .frame(width: w * (tied ? 0.4 : 0.85), height: h * 0.3)
                    .rotationEffect(.degrees(180))
                    .offset(y: h * 0.06)
                // ribbon
                if tied {
                    HStack(spacing: -w * 0.04) {
                        Ellipse().fill(Theme.terracotta).frame(width: w * 0.26, height: w * 0.16).rotationEffect(.degrees(-20))
                        Circle().fill(Theme.terracotta).frame(width: w * 0.1, height: w * 0.1)
                        Ellipse().fill(Theme.terracotta).frame(width: w * 0.26, height: w * 0.16).rotationEffect(.degrees(20))
                    }
                    .offset(y: h * 0.22)
                    .transition(.scale)
                }
                Image(systemName: "pawprint.fill")
                    .font(.system(size: w * 0.18))
                    .foregroundStyle(Theme.woodDark.opacity(0.5))
                    .offset(y: h * 0.55)
            }
            .frame(width: w, height: h)
            .rotationEffect(.degrees(tied ? 0 : -4))
        }
    }
}

/// Coins and stars flying out in a happy burst
struct CoinBurst: View {
    @State private var out = false

    var body: some View {
        ZStack {
            ForEach(0..<14, id: \.self) { i in
                let angle = Double(i) / 14 * 2 * .pi
                let distance: CGFloat = i % 2 == 0 ? 120 : 90
                Image(systemName: i % 3 == 0 ? "star.fill" : "dollarsign.circle.fill")
                    .font(.system(size: i % 3 == 0 ? 16 : 22))
                    .foregroundStyle(i % 3 == 0 ? Theme.terracotta : Theme.mustard)
                    .offset(x: out ? CGFloat(cos(angle)) * distance : 0,
                            y: out ? CGFloat(sin(angle)) * distance * 0.7 : 0)
                    .opacity(out ? 0 : 1)
                    .scaleEffect(out ? 0.6 : 1.1)
            }
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.easeOut(duration: 1.1)) { out = true }
        }
    }
}

// MARK: - Watch a video before deciding

/// Lets PHAsset work with .sheet(item:)
struct PreviewItem: Identifiable {
    let asset: PHAsset
    var id: String { asset.localIdentifier }
}

struct VideoPreview: View {
    let asset: PHAsset
    let isKept: Bool
    let onDecide: (Bool) -> Void      // true = keep, false = scoop
    @Environment(\.dismiss) private var dismiss
    @State private var player: AVPlayer?
    @State private var failed = false

    private var ratio: CGFloat {
        guard asset.pixelHeight > 0 else { return 9.0 / 16.0 }
        return CGFloat(asset.pixelWidth) / CGFloat(asset.pixelHeight)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ZStack {
                    Color.black
                    if let player {
                        VideoPlayer(player: player)
                    } else if failed {
                        Text("Couldn't load this video.")
                            .foregroundStyle(.white)
                    } else {
                        ProgressView("Loading...").tint(.white).foregroundStyle(.white)
                    }
                }
                .aspectRatio(ratio, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxHeight: .infinity)

                Text(details)
                    .font(.subheadline)
                    .opacity(0.7)

                HStack(spacing: 12) {
                    Button {
                        onDecide(true)
                        dismiss()
                    } label: {
                        Label("Keep it", systemImage: "heart.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.leaf)

                    Button {
                        onDecide(false)
                        dismiss()
                    } label: {
                        Label("Scoop it", systemImage: "trash.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }
                .controlSize(.large)
            }
            .padding()
            .paperBackground()
            .foregroundStyle(Theme.cocoa)
            .navigationTitle(isKept ? "Keeping this one" : "Set to scoop")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task { await load() }
            .onDisappear { player?.pause() }
        }
    }

    private var details: String {
        let length = Duration.seconds(asset.duration).formatted(.time(pattern: .minuteSecond))
        let size = ByteCountFormatter.string(fromByteCount: PhotoLibrary.fileSize(of: asset), countStyle: .file)
        let date = asset.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? ""
        return "\(length) long, \(size), \(date)"
    }

    private func load() async {
        guard player == nil else { return }
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true    // downloads from iCloud if needed
        options.deliveryMode = .automatic
        let item: AVPlayerItem? = await withCheckedContinuation { continuation in
            PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { item, _ in
                continuation.resume(returning: item)
            }
        }
        if let item {
            let newPlayer = AVPlayer(playerItem: item)
            player = newPlayer
            newPlayer.play()
        } else {
            failed = true
        }
    }
}

// MARK: - Photo thumbnail

struct Thumbnail: View {
    let asset: PHAsset
    var side: CGFloat = 120
    @EnvironmentObject var library: PhotoLibrary
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        Color.gray.opacity(0.2)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if asset.mediaType == .video {
                    Image(systemName: "video.fill")
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(5)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .task(id: asset.localIdentifier) {
                let pixels = side * displayScale
                image = await library.image(for: asset, size: CGSize(width: pixels, height: pixels))
            }
    }
}
