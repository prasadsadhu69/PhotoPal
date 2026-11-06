import SwiftUI
import UIKit
import Photos

// MARK: - Clean tab: your camera roll's health report

struct CleanView: View {
    @Environment(\.dismiss) private var closeSheet
    @EnvironmentObject var game: GameState
    @EnvironmentObject var library: PhotoLibrary
    @EnvironmentObject var router: Router

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    if let report = library.report {
                        HealthCard(report: report)
                        ForEach(JunkKind.allCases) { kind in
                            pileRow(kind, report: report)
                        }
                        freedCard
                    } else if library.scanning {
                        VStack(spacing: 16) {
                            PalView(size: 120)
                            ProgressView("\(game.petName) is sniffing your camera roll...")
                        }
                        .padding(.top, 60)
                    } else {
                        Button("Sniff for poop") {
                            Task { await rescan() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.sageDeep)
                        .padding(.top, 60)
                    }
                }
                .padding()
            }
            .paperBackground()
            .refreshable { await rescan() }
            .navigationTitle("Scoop & Sweep")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Done") { closeSheet() } }
                ToolbarItem(placement: .topBarTrailing) { CoinBadge() }
            }
        }
    }

    private func rescan() async {
        await library.refresh(game, force: true)
    }

    private func pileRow(_ kind: JunkKind, report: JunkReport) -> some View {
        let count = report.count(kind)
        let size = ByteCountFormatter.string(fromByteCount: report.bytesFor(kind), countStyle: .file)
        return HStack(spacing: 12) {
            ZStack {
                PoopView(size: 44)
                Image(systemName: kind.symbol)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(y: 12)
            }
            .frame(width: 54, height: 54)
            .opacity(count > 0 ? 1 : 0.3)
            VStack(alignment: .leading, spacing: 3) {
                Text(kind.title).font(Theme.headline)
                Text(kind.blurb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                if count > 0 {
                    Text("\(count) to scoop, \(size)")
                        .font(.caption.bold())
                        .foregroundStyle(.teal)
                }
            }
            Spacer(minLength: 4)
            if count > 0 {
                Button("Scoop") {
                    closeSheet()
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(0.4))
                        router.cleaning = kind
                    }
                }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.sageDeep)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
            }
        }
        .padding(12)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 16))
    }

    private var freedCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Your scooping record").font(Theme.headline)
            LabeledContent("Space freed", value: ByteCountFormatter.string(fromByteCount: game.bytesFreed, countStyle: .file))
            LabeledContent("Poops scooped", value: "\(game.itemsTossed)")
            LabeledContent("Daily streak", value: "\(game.streak) day\(game.streak == 1 ? "" : "s")")
        }
        .font(.subheadline)
        .padding(14)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct HealthCard: View {
    let report: JunkReport

    private var color: Color {
        switch report.score {
        case ..<40: return .red
        case ..<70: return .orange
        default: return .green
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle().stroke(color.opacity(0.2), lineWidth: 12)
                Circle()
                    .trim(from: 0, to: CGFloat(report.score) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(report.score)")
                        .font(.system(size: 34, weight: .heavy, design: .rounded))
                    Text("roll health")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 112, height: 112)

            VStack(alignment: .leading, spacing: 6) {
                Text(report.junkCount == 0 ? "Squeaky clean!" : "\(report.junkCount) poops found")
                    .font(Theme.title3)
                if report.junkBytes > 0 {
                    Text("\(ByteCountFormatter.string(fromByteCount: report.junkBytes, countStyle: .file)) you can free up")
                        .font(.subheadline)
                    Text("That's room for about \(max(1, Int(report.junkBytes / 3_000_000)).formatted()) new photos")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding()
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 20))
    }
}

// MARK: - Scooping one pile (batch review)

struct CleanupView: View {
    let kind: JunkKind
    @EnvironmentObject var game: GameState
    @EnvironmentObject var library: PhotoLibrary
    @Environment(\.dismiss) private var dismiss

    @State private var items: [PHAsset] = []        // screenshots, giant videos, oopsies
    @State private var groups: [[PHAsset]] = []     // real twin groups
    @State private var keep: Set<String> = []
    @State private var reasons: [String: String] = [:]   // why something is kept or flagged
    @State private var picks: Set<String> = []      // your pal's pick in each twin group
    @State private var sizes: [String: Int64] = [:]
    @State private var available = 0
    @State private var loaded = false
    @State private var checking = false             // still reading screenshots / comparing twins
    @State private var checked = 0
    @State private var toCheck = 0
    @State private var working = false
    @State private var reward: CleanReward?
    @State private var errorText: String?
    @State private var preview: PreviewItem?
    @State private var confirmTrash = false
    @EnvironmentObject var router: Router

    private var batchLimit: Int {
        switch kind {
        case .screenshots: return 60     // each one gets its text read, so smaller batches
        case .giants: return 60
        case .oopsies: return 150
        case .twins: return 25           // groups
        }
    }

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 6)]

    private var allAssets: [PHAsset] { kind == .twins ? groups.flatMap { $0 } : items }
    private var tossAssets: [PHAsset] { allAssets.filter { !keep.contains($0.localIdentifier) } }
    private var tossBytes: Int64 { tossAssets.reduce(Int64(0)) { $0 + (sizes[$1.localIdentifier] ?? 0) } }

    var body: some View {
        NavigationStack {
            Group {
                if let reward {
                    RewardView(reward: reward) {
                        router.celebrate += 1
                        dismiss()
                    }
                } else if !loaded || (allAssets.isEmpty && checking) {
                    VStack(spacing: 16) {
                        PalView(size: 110)
                        ProgressView(kind == .twins ? "\(game.petName) is comparing photos..." : "\(game.petName) is sniffing...")
                    }
                } else if allAssets.isEmpty {
                    ContentUnavailableView(kind == .twins ? "No real twins here" : "All scooped!",
                                           systemImage: "checkmark.seal.fill",
                                           description: Text(kind == .twins
                                                             ? "\(game.petName) checked closely and these photos are all different."
                                                             : "No \(kind.title.lowercased()) left in this pile."))
                } else {
                    content
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .paperBackground()
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if reward == nil {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { dismiss() }
                    }
                }
            }
            .task { await load() }
            .sheet(isPresented: $confirmTrash) {
                ConfirmTrashSheet(count: tossAssets.count,
                                  size: ByteCountFormatter.string(fromByteCount: tossBytes, countStyle: .file)) {
                    confirmTrash = false
                    Task {
                        try? await Task.sleep(for: .seconds(0.35))   // let the sheet close before iOS asks
                        await scoop()
                    }
                }
                .presentationDetents([.height(300)])
            }
            .sheet(item: $preview) { item in
                VideoPreview(asset: item.asset, isKept: keep.contains(item.id)) { keepIt in
                    if keepIt { keep.insert(item.id) } else { keep.remove(item.id) }
                }
            }
            .interactiveDismissDisabled(working)
            .alert("Nothing was deleted",
                   isPresented: Binding(get: { errorText != nil }, set: { if !$0 { errorText = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    // MARK: Layout

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                intro
                if checking { checkingBanner } else { selectionBar }
                switch kind {
                case .screenshots, .oopsies:
                    LazyVGrid(columns: columns, spacing: 6) {
                        ForEach(items, id: \.localIdentifier) { asset in
                            tile(asset, side: 120)
                        }
                    }
                case .giants:
                    ForEach(items, id: \.localIdentifier) { asset in
                        videoRow(asset)
                    }
                case .twins:
                    ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                        twinRow(index: index, group: group)
                    }
                }
            }
            .padding()
        }
        .safeAreaInset(edge: .bottom) { scoopBar }
    }

    private var intro: some View {
        HStack(spacing: 12) {
            PalView(mood: .happy, size: 64)
                .frame(width: 70, height: 84)
            VStack(alignment: .leading, spacing: 4) {
                Text(kind == .twins
                     ? "\(game.petName) found \(groups.count) groups of look-alikes"
                     : "\(game.petName) sniffed out \(available) \(kind.title.lowercased())")
                    .font(Theme.headline)
                Text(instructions)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if available > items.count && kind != .twins {
                    Text("Showing \(items.count) now. The rest will be waiting next time.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var instructions: String {
        switch kind {
        case .screenshots:
            return "Everything is set to scoop, except screenshots that look important (tickets, receipts, codes). Tap any photo to change it."
        case .twins:
            return "\(game.petName) compared what's in each photo and kept the best one (sharpest, or best faces). Tap to change."
        case .giants:
            return "Your biggest videos. Everything is set to scoop. Tap play to watch one first, or tap a video to keep it."
        case .oopsies:
            return "Photos that look dark, blurry or accidental. Everything is set to scoop. Tap anything you want to keep."
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 10) {
            Text("\(tossAssets.count) of \(allAssets.count) selected to scoop")
                .font(.subheadline.bold())
            Spacer()
            Button {
                withAnimation(.snappy) {
                    if allSelected { deselectAll() } else { selectAll() }
                }
            } label: {
                Label(allSelected ? "Deselect all" : "Select all",
                      systemImage: allSelected ? "circle" : "checkmark.circle.fill")
                    .font(.subheadline.bold())
            }
            .buttonStyle(.borderedProminent)
            .tint(allSelected ? Color.gray : Theme.mint)
            .controlSize(.small)
        }
        .padding(10)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 14))
    }

    private var checkingBanner: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text(kind == .twins
                 ? "Comparing photos... \(checked) of \(toCheck) groups"
                 : "Reading screenshots for important stuff... \(checked) of \(toCheck)")
                .font(.caption)
            Spacer()
        }
        .padding(10)
        .background(Color.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }

    private func tile(_ asset: PHAsset, side: CGFloat) -> some View {
        let id = asset.localIdentifier
        let kept = keep.contains(id)
        return Thumbnail(asset: asset, side: side)
            .opacity(kept ? 1 : 0.6)
            .overlay(RoundedRectangle(cornerRadius: 8)
                .stroke(kept ? Color.green : Color.red.opacity(0.7), lineWidth: 3))
            .overlay(alignment: .topTrailing) {
                Image(systemName: kept ? "heart.circle.fill" : "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, kept ? Color.green : Color.red)
                    .padding(4)
            }
            .overlay {
                if asset.mediaType == .video {
                    Button {
                        preview = PreviewItem(asset: asset)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: side * 0.18, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: side * 0.38, height: side * 0.38)
                            .background(.black.opacity(0.45), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Watch video")
                }
            }
            .overlay(alignment: .bottomLeading) {
                if let reason = reasons[id] {
                    Text(reason)
                        .font(.system(size: 9, weight: .bold))
                        .lineLimit(2)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
                        .padding(4)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { toggle(asset) }
            .contextMenu {
                Button {
                    vault(asset)
                } label: {
                    Label("Put in the \(PhotoLibrary.vaultName)", systemImage: "lock.fill")
                }
                Button {
                    keep.insert(id)
                } label: {
                    Label("Keep", systemImage: "heart")
                }
                if asset.mediaType == .video {
                    Button {
                        preview = PreviewItem(asset: asset)
                    } label: {
                        Label("Watch", systemImage: "play.fill")
                    }
                }
            }
    }

    private func videoRow(_ asset: PHAsset) -> some View {
        HStack(spacing: 12) {
            tile(asset, side: 90)
                .frame(width: 90, height: 90)
            VStack(alignment: .leading, spacing: 3) {
                Text(ByteCountFormatter.string(fromByteCount: sizes[asset.localIdentifier] ?? 0, countStyle: .file))
                    .font(Theme.headline)
                Text(Duration.seconds(asset.duration).formatted(.time(pattern: .minuteSecond)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(asset.creationDate?.formatted(date: .abbreviated, time: .omitted) ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func twinRow(index: Int, group: [PHAsset]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Group \(index + 1)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(group, id: \.localIdentifier) { asset in
                        tile(asset, side: 130)
                            .frame(width: 130, height: 130)
                    }
                }
            }
        }
    }

    private var scoopBar: some View {
        Button {
            if tossAssets.isEmpty {
                Task { await scoop() }
            } else {
                confirmTrash = true
            }
        } label: {
            VStack(spacing: 2) {
                if working {
                    ProgressView()
                } else if checking {
                    Text("Hang on, \(game.petName) is still checking...").font(Theme.headline)
                } else if tossAssets.isEmpty {
                    Text("Keep everything").font(Theme.headline)
                } else {
                    Text("Scoop & Sweep \(tossAssets.count)").font(Theme.headline)
                    Text("Frees \(ByteCountFormatter.string(fromByteCount: tossBytes, countStyle: .file))")
                        .font(.caption)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .tint(Theme.sageDeep)
        .disabled(working || checking)
        .padding()
        .background(.bar)
    }

    // MARK: Actions

    /// Protects a photo forever by putting it in the Peanut Vault album
    private func vault(_ asset: PHAsset) {
        let id = asset.localIdentifier
        keep.insert(id)
        reasons[id] = "In the Vault"
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task { await library.addToVault([id]) }
    }

    private func toggle(_ asset: PHAsset) {
        let id = asset.localIdentifier
        if keep.contains(id) { keep.remove(id) } else { keep.insert(id) }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Photos that "Select all" should still leave alone: important-looking screenshots
    /// and the best shot in each twin group
    private var alwaysKeep: Set<String> {
        switch kind {
        case .screenshots: return Set(reasons.keys)
        case .twins: return picks
        case .giants, .oopsies: return []
        }
    }

    private var allSelected: Bool {
        allAssets.allSatisfy { keep.contains($0.localIdentifier) == alwaysKeep.contains($0.localIdentifier) }
    }

    private func selectAll() {
        keep = alwaysKeep
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    private func deselectAll() {
        keep = Set(allAssets.map(\.localIdentifier))
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    private func load() async {
        guard !loaded else { return }
        guard let report = library.report else {
            loaded = true
            return
        }

        switch kind {
        case .screenshots, .giants, .oopsies:
            let ids: [String]
            switch kind {
            case .screenshots: ids = report.screenshots
            case .giants: ids = report.giants
            default: ids = report.oopsies
            }
            available = ids.count
            items = library.assets(for: Array(ids.prefix(batchLimit)))
            let idList = items.map(\.localIdentifier)
            sizes = await Task.detached(priority: .userInitiated) { PhotoLibrary.sizes(for: idList) }.value
            if kind == .oopsies {
                for id in idList {
                    if let reason = report.oopsReasons[id] { reasons[id] = reason }
                }
            }
            loaded = true
            if kind == .screenshots { await readScreenshots(idList) }

        case .twins:
            available = report.count(.twins)
            loaded = true
            await compareTwins(Array(report.twinGroups.prefix(batchLimit)), protected: report.protected)
        }
    }

    /// Reads the text in each screenshot, a few at a time, and keeps the important-looking ones
    private func readScreenshots(_ ids: [String]) async {
        checking = true
        toCheck = ids.count
        checked = 0
        var index = 0
        while index < ids.count {
            let chunk = Array(ids[index..<min(index + 6, ids.count)])
            let found = await Task.detached(priority: .userInitiated) { PhotoSmarts.importantReasons(ids: chunk) }.value
            for (id, reason) in found {
                keep.insert(id)
                reasons[id] = reason
            }
            index += chunk.count
            checked = index
        }
        checking = false
    }

    /// Compares what's actually in each group of photos, splits out the real look-alikes,
    /// and pre-picks the best shot in each
    private func compareTwins(_ candidates: [[String]], protected: Set<String>) async {
        checking = true
        toCheck = candidates.count
        checked = 0
        var notTwins: [String] = []
        for candidate in candidates {
            let result = await Task.detached(priority: .userInitiated) {
                PhotoSmarts.refineTwins(candidate, protected: protected)
            }.value
            notTwins.append(contentsOf: result.singles)
            let newGroups = result.groups.map { library.assets(for: $0) }.filter { $0.count >= 2 }
            let newIDs = newGroups.flatMap { $0.map(\.localIdentifier) }
            let newSizes = await Task.detached(priority: .utility) { PhotoLibrary.sizes(for: newIDs) }.value
            sizes.merge(newSizes) { _, new in new }
            for (id, reason) in result.picks {
                keep.insert(id)
                picks.insert(id)
                reasons[id] = reason
            }
            withAnimation(.snappy) { groups.append(contentsOf: newGroups) }
            checked += 1
        }
        // Photos with no real look-alike won't show up as twins again
        game.markNotTwins(notTwins)
        library.remove(Set(notTwins), deletedCount: 0)
        game.applyScanIfNeeded(library.report)
        checking = false
    }

    private func scoop() async {
        let all = allAssets
        let toss = tossAssets
        let keptIDs = all.map(\.localIdentifier).filter { keep.contains($0) }

        if toss.isEmpty {
            game.keep(keptIDs)
            library.remove(Set(keptIDs), deletedCount: 0)
            game.applyScanIfNeeded(library.report)
            dismiss()
            return
        }

        working = true
        do {
            let bytes = try await library.delete(toss)
            game.keep(keptIDs)
            library.remove(Set(all.map(\.localIdentifier)), deletedCount: toss.count)
            game.applyScanIfNeeded(library.report)
            let result = game.rewardCleanup(kind: kind, count: toss.count, bytes: bytes)
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.spring) { reward = result }
        } catch {
            // Happens if you tap "Don't Allow" on the iOS delete prompt
            errorText = "Your photos are safe. (\(error.localizedDescription))"
        }
        working = false
    }
}

/// Step one of two: a friendly check before iOS asks to delete
struct ConfirmTrashSheet: View {
    let count: Int
    let size: String
    let onConfirm: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "trash.fill")
                .font(.system(size: 26, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 58, height: 58)
                .background(Circle().fill(Theme.terracotta)
                    .overlay(Circle().inset(by: 3).stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5]))))
            Text("Move \(count) \(count == 1 ? "item" : "items") to Trash?")
                .font(Theme.title2)
            Text("Frees \(size). They stay in Recently Deleted for 30 days, so you can still change your mind.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .opacity(0.75)
            HStack(spacing: 12) {
                Button("Not yet") { dismiss() }
                    .buttonStyle(.bordered)
                    .tint(Theme.cocoa)
                Button {
                    onConfirm()
                } label: {
                    Text("Move to Trash").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.terracotta)
            }
            .controlSize(.large)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .paperBackground()
        .foregroundStyle(Theme.cocoa)
    }
}
