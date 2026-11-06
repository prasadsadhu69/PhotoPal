import Photos
import SwiftUI
import UIKit

// MARK: - Home: your pal's yard fills the screen, with a small cozy toolbar

/// Something worth your attention, shown as a little note above the toolbar
struct Notice: Identifiable {
    let id: String
    let symbol: String
    let color: Color
    let title: String
    let subtitle: String
    let action: () -> Void
}

struct HomeView: View {
    @EnvironmentObject var game: GameState
    @EnvironmentObject var library: PhotoLibrary
    @EnvironmentObject var router: Router

    @State private var editing = false
    @State private var feedRequest: ShopItem?
    @State private var playToken = 0
    @State private var showDig = false
    @State private var showNotices = false

    var body: some View {
        GeometryReader { geo in
            let topInset = geo.safeAreaInsets.top + 92
            ZStack {
                YardView(editing: $editing, feedRequest: $feedRequest, playToken: playToken,
                         topInset: topInset, bottomInset: geo.safeAreaInsets.bottom + CozyDock.height + 60, animated: !editing)
                    .ignoresSafeArea()

                VStack(spacing: 10) {
                    if editing {
                        buildHeader
                    } else {
                        topBar
                        sideButtons
                    }
                    Spacer()
                    if editing {
                        BuildTray()
                    } else if let kind = router.peek {
                        PilePeek(kind: kind)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else if let notice = notices.first {
                        noticeCard(notice, more: notices.count - 1)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, CozyDock.height + 8)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: router.peek)
            }
        }
        .sheet(isPresented: $showDig) { MemoryDigView() }
        .sheet(isPresented: $showNotices) {
            NoticesSheet(notices: notices)
                .presentationDetents([.medium])
        }
        .alert(game.justGrew.map { "\(game.petName) grew into a \($0.name(for: game.species))!" } ?? "",
               isPresented: Binding(get: { game.justGrew != nil }, set: { if !$0 { game.justGrew = nil } })) {
            Button("Yay!") {}
        } message: {
            Text(growthMessage)
        }
        .onDisappear { router.peek = nil }
    }

    private var growthMessage: String {
        guard let stage = game.justGrew else { return "" }
        var lines: [String] = []
        switch stage {
        case .kid: lines.append("Keep scooping poop to help them grow even more.")
        case .teen: lines.append("A little garden sprouted in the yard, and they moved into a wooden pet house!")
        case .adult: lines.append("A pond appeared in the yard!")
        case .radiant: lines.append("They moved into a cozy cabin, and fairy lights went up along the fence!")
        case .baby: break
        }
        if stage != .kid && !game.speciesToAdopt.isEmpty {
            lines.append("You earned an adoption ticket! Adopt a new pal from their profile.")
        }
        return lines.joined(separator: " ")
    }

    // MARK: Minimal HUD

    private var topBar: some View {
        HStack(alignment: .center, spacing: 10) {
            Button {
                router.showProfile = true
            } label: {
                HStack(spacing: 10) {
                    LevelRing(level: game.level, progress: game.levelProgress)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(game.petName) · Lv. \(game.level)")
                            .font(Theme.title3)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                        HStack(spacing: 5) {
                            Text(game.stage.name(for: game.species))
                                .font(Theme.label)
                                .foregroundStyle(.white)
                                .feltBadge(Theme.sageDeep)
                            needDots
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(Theme.paper.opacity(0.95), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(PaperGrain().clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous)))
                .shadow(color: Theme.cocoa.opacity(0.12), radius: 8, y: 3)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 6) {
                CoinBadge()
                    .feltBadge(Theme.paper)
                    .shadow(color: Theme.cocoa.opacity(0.12), radius: 5, y: 2)
                HStack(spacing: 4) {
                    Image(systemName: "pawprint.fill")
                    Text("\(game.streak)")
                        .font(Theme.header(15, "Bold", relativeTo: .subheadline))
                }
                .foregroundStyle(.white)
                .feltBadge(Theme.terracotta)
                .shadow(color: Theme.cocoa.opacity(0.12), radius: 5, y: 2)
                .accessibilityLabel("\(game.streak) day paw streak")
            }
        }
    }

    private var buildHeader: some View {
        HStack(spacing: 10) {
            Label("Build mode: drag anything to move it", systemImage: "hand.draw.fill")
                .font(Theme.label)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .feltBadge(Theme.paper)
            Spacer(minLength: 0)
            Button {
                withAnimation(.snappy) { editing = false }
            } label: {
                Text("Done")
                    .font(Theme.headline)
                    .foregroundStyle(.white)
                    .feltBadge(Theme.sageDeep)
            }
            .buttonStyle(.plain)
        }
    }

    /// Tiny meters for the four needs, shown as little dots under the name
    private var needDots: some View {
        HStack(spacing: 4) {
            NeedDot(symbol: "fork.knife", value: game.food, color: Theme.mustard)
            NeedDot(symbol: "heart.fill", value: game.joy, color: Theme.terracotta)
            NeedDot(symbol: "sparkles", value: game.clean, color: Theme.sageDeep)
            NeedDot(symbol: "bolt.fill", value: game.energy, color: Theme.plum)
        }
    }

    private var sideButtons: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                roundWoodButton(game.sleeping ? "sun.max.fill" : "moon.fill",
                                label: game.sleeping ? "Wake up" : "Lights off") {
                    withAnimation(.easeInOut(duration: 0.6)) { game.toggleLights() }
                }
                if game.buildUnlocked {
                    roundWoodButton(editing ? "checkmark" : "hammer.fill", label: editing ? "Done building" : "Build") {
                        withAnimation(.snappy) {
                            editing.toggle()
                            router.peek = nil
                        }
                    }
                }
            }
        }
    }

    private func roundWoodButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.woodLight)
                    .overlay(WoodGrain().clipShape(Circle()))
                    .overlay(Circle().inset(by: 3).stroke(Color.white.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))))
                .shadow(color: Theme.cocoa.opacity(0.25), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    // MARK: Notes

    private var notices: [Notice] {
        var list: [Notice] = []
        if !game.hasFed {
            list.append(Notice(id: "feed", symbol: "fork.knife", color: Theme.mustard,
                               title: "\(game.petName) is hungry!",
                               subtitle: "Head to Feed & Care for a treat.") { router.tab = .care })
        }
        if game.sick {
            list.append(Notice(id: "sick", symbol: "cross.case.fill", color: .red,
                               title: "\(game.petName) feels sick",
                               subtitle: "Give medicine in Feed & Care.") { router.tab = .care })
        }
        if game.tickets > 0 && !game.speciesToAdopt.isEmpty {
            list.append(Notice(id: "ticket", symbol: "ticket.fill", color: Theme.terracotta,
                               title: "You earned an adoption ticket!",
                               subtitle: "Adopt a new pal from \(game.petName)'s profile.") { router.showProfile = true })
        }
        if let daily = game.daily, Calendar.current.isDateInToday(daily.day), !daily.paid {
            list.append(Notice(id: "bounty", symbol: "target", color: Theme.sageDeep,
                               title: "Today's bounty: +\(daily.reward) coins",
                               subtitle: "Scoop \(daily.target) \(daily.kind.title.lowercased()) (\(min(daily.progress, daily.target))/\(daily.target))") {
                router.cleaning = daily.kind
            })
        }
        if game.canDigToday {
            list.append(Notice(id: "dig", symbol: "sparkles", color: Theme.plum,
                               title: "\(game.petName) dug something up!",
                               subtitle: "See a memory from this day.") { showDig = true })
        }
        return list
    }

    private func noticeCard(_ notice: Notice, more: Int) -> some View {
        HStack(spacing: 10) {
            Button(action: notice.action) {
                HStack(spacing: 10) {
                    Image(systemName: notice.symbol)
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(notice.color, in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(notice.title).font(Theme.headline).lineLimit(1)
                        Text(notice.subtitle).font(.caption).opacity(0.7).lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)
            if more > 0 {
                Button {
                    showNotices = true
                } label: {
                    Text("+\(more)")
                        .font(Theme.label)
                        .foregroundStyle(.white)
                        .feltBadge(Theme.terracotta)
                }
                .buttonStyle(.plain)
            }
        }
        .paperCard(padding: 10, radius: 20)
    }
}

/// Level with a cozy progress ring
struct LevelRing: View {
    let level: Int
    let progress: Double

    var body: some View {
        ZStack {
            Circle().fill(Theme.mustard.opacity(0.18))
            Circle()
                .trim(from: 0, to: CGFloat(max(0.02, progress)))
                .stroke(Theme.mustard, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(level)")
                .font(Theme.header(16, "Bold", relativeTo: .headline))
        }
        .frame(width: 40, height: 40)
        .accessibilityLabel("Level \(level)")
    }
}

/// A need shown as a tiny colored dot that turns red when low
struct NeedDot: View {
    let symbol: String
    let value: Double
    let color: Color

    var body: some View {
        let low = value < 25
        Image(systemName: symbol)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(low ? Color.red : color.opacity(0.35 + 0.65 * min(1, max(0, value / 100)))))
    }
}

/// Quick look at a poop pile before scooping
struct PilePeek: View {
    let kind: JunkKind
    @EnvironmentObject var library: PhotoLibrary
    @EnvironmentObject var router: Router
    @EnvironmentObject var game: GameState
    @State private var assets: [PHAsset] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(library.report?.count(kind) ?? 0) \(kind.title.lowercased())")
                    .font(Theme.headline)
                Spacer()
                Button {
                    router.peek = nil
                } label: {
                    Image(systemName: "xmark.circle.fill").font(.title3).opacity(0.5)
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                ForEach(assets, id: \.localIdentifier) { asset in
                    Thumbnail(asset: asset, side: 80)
                        .frame(maxWidth: .infinity)
                }
                if assets.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 70)
                }
            }
            Button {
                router.peek = nil
                router.cleaning = kind
            } label: {
                Label("Scoop this pile", systemImage: "sparkles")
                    .font(Theme.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.sageDeep)
        }
        .paperCard(padding: 12, radius: 22)
        .task(id: kind) {
            guard let report = library.report else { return }
            let ids: [String]
            switch kind {
            case .screenshots: ids = report.screenshots
            case .giants: ids = report.giants
            case .oopsies: ids = report.oopsies
            case .twins: ids = report.twinGroups.flatMap { $0 }
            }
            assets = library.assets(for: Array(ids.prefix(4)))
        }
    }
}

/// Build mode: a slim tray to put yard items out, or buy more
struct BuildTray: View {
    @EnvironmentObject var game: GameState
    @State private var shopping = false

    var body: some View {
        let stored = ShopItem.all.filter { $0.category == .decor && game.decorAvailable($0.id) > 0 }
        let forSale = ShopItem.all.filter { $0.category == .decor }
        VStack(alignment: .leading, spacing: 8) {
            Picker("Tray", selection: $shopping) {
                Text("Storage (\(stored.count))").tag(false)
                Text("Shop").tag(true)
            }
            .pickerStyle(.segmented)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if !shopping && stored.isEmpty {
                        Text("Everything is out in the yard. Tap Shop for more.")
                            .font(.caption)
                            .opacity(0.7)
                            .frame(height: 70)
                    }
                    ForEach(shopping ? forSale : stored) { item in
                        Button {
                            if shopping {
                                if game.buy(item) { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
                            } else {
                                withAnimation(.spring) { game.placeDecor(item.id) }
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            }
                        } label: {
                            VStack(spacing: 1) {
                                DecorArt(id: item.id, size: 30).frame(width: 52, height: 40)
                                if shopping {
                                    Text("\(item.price)")
                                        .font(Theme.label)
                                        .foregroundStyle(game.coins >= item.price ? Theme.woodDark : Color.secondary)
                                } else {
                                    Text("x\(game.decorAvailable(item.id))").font(Theme.label)
                                }
                            }
                            .frame(width: 62, height: 66)
                            .background(Theme.oatmeal, in: RoundedRectangle(cornerRadius: 12))
                            .opacity(shopping && game.coins < item.price ? 0.45 : 1)
                        }
                        .buttonStyle(.plain)
                        .disabled(shopping && game.coins < item.price)
                    }
                }
            }
        }
        .paperCard(padding: 10, radius: 20)
    }
}

/// All of today's notes in one place
struct NoticesSheet: View {
    let notices: [Notice]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(notices) { notice in
                        Button {
                            dismiss()
                            notice.action()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: notice.symbol)
                                    .font(Theme.headline)
                                    .foregroundStyle(.white)
                                    .frame(width: 40, height: 40)
                                    .background(notice.color.gradient, in: Circle())
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(notice.title).font(Theme.headline)
                                    Text(notice.subtitle).font(.caption).opacity(0.7)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").opacity(0.5)
                            }
                            .cozyCard(padding: 12)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .paperBackground()
            .foregroundStyle(Theme.cocoa)
            .navigationTitle("Today")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

/// A need shown as a little round meter
struct NeedBubble: View {
    let symbol: String
    let value: Double
    let color: Color

    var body: some View {
        let low = value < 25
        let tint = low ? Color.red : color
        ZStack {
            Circle().fill(tint.opacity(0.15))
            Circle()
                .trim(from: 0, to: CGFloat(min(max(value, 0), 100) / 100))
                .stroke(tint, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
        }
        .frame(width: 36, height: 36)
    }
}

/// A round toolbar button with a label
struct DockButton: View {
    let symbol: String
    let title: String
    let color: Color
    let disabled: Bool
    var badge: Int = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 50, height: 50)
                    .background((disabled ? Color.gray.opacity(0.5) : color).gradient, in: Circle())
                    .overlay(alignment: .topTrailing) {
                        if badge > 0 {
                            Text(badge > 99 ? "99+" : "\(badge)")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.red, in: Capsule())
                                .offset(x: 6, y: -4)
                        }
                    }
                Text(title)
                    .font(.caption2.bold())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Pantry (feeding)

struct PantrySheet: View {
    @EnvironmentObject var game: GameState
    @EnvironmentObject var router: Router
    @Environment(\.dismiss) private var dismiss
    var onUse: (ShopItem) -> Void

    private let columns = [GridItem(.adaptive(minimum: 90), spacing: 12)]

    var body: some View {
        NavigationStack {
            ScrollView {
                let owned = ShopItem.all.filter {
                    ($0.category == .food || $0.category == .toy) && (game.inventory[$0.id] ?? 0) > 0
                }
                if owned.isEmpty {
                    VStack(spacing: 12) {
                        Text("The pantry is empty!").font(Theme.headline)
                        Text("Scoop poop to earn coins, then buy treats in the Shop.")
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        Button("Go to the Shop") {
                            dismiss()
                            router.tab = .care
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.mustard)
                    }
                    .padding(.top, 30)
                    .padding()
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(owned) { item in
                            Button {
                                if game.feed(item) {
                                    UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                                    onUse(item)
                                    dismiss()
                                }
                            } label: {
                                VStack(spacing: 6) {
                                    Image(systemName: item.symbol).font(.title)
                                    Text(item.name).font(.caption).lineLimit(1)
                                    Text("x\(game.inventory[item.id] ?? 0)").font(.caption2.bold())
                                    if game.isFavorite(item) {
                                        Text("Favorite!").font(.caption2.bold()).foregroundStyle(Theme.terracotta)
                                    }
                                }
                                .frame(maxWidth: .infinity, minHeight: 90)
                                .background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 14))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Pantry")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Your pal, dressed and moody (use anywhere in the app)

struct PalView: View {
    @EnvironmentObject var game: GameState
    var mood: PetMood? = nil
    var size: CGFloat = 160
    var chomping = false
    var animated = true

    var body: some View {
        PetFigure(look: game.look, stage: game.stage, mood: mood ?? game.mood,
                  condition: mood == nil ? game.condition : PetCondition(),
                  hatID: game.hatID, neckID: game.neckID, size: size, animated: animated, chomping: chomping)
    }
}

// MARK: - Small shared pieces

struct NeedMeter: View {
    let symbol: String
    let label: String
    let value: Double
    let color: Color

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.subheadline)
                .foregroundStyle(value < 25 ? Color.red : color)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.secondary.opacity(0.2))
                    Capsule().fill(value < 25 ? Color.red : color)
                        .frame(width: geo.size.width * CGFloat(min(max(value, 0), 100) / 100))
                }
            }
            .frame(height: 6)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12))
    }
}

struct ActionButton: View {
    let symbol: String
    let title: String
    let color: Color
    let disabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption2.bold()).lineLimit(1).minimumScaleFactor(0.7)
            }
            .foregroundStyle(disabled ? Color.secondary : color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background((disabled ? Color.secondary : color).opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

struct HealthBadge: View {
    let score: Int

    private var color: Color {
        switch score {
        case ..<40: return .red
        case ..<70: return .orange
        default: return .green
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle().stroke(color.opacity(0.2), lineWidth: 4)
                Circle().trim(from: 0, to: CGFloat(score) / 100)
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text("\(score)").font(.caption2.bold())
            }
            .frame(width: 34, height: 34)
            Text("Roll\nhealth").font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct FloatingHeart: View {
    @State private var up = false
    @State private var x = CGFloat.random(in: -50...50)

    var body: some View {
        Image(systemName: "heart.fill")
            .font(.title2)
            .foregroundStyle(Theme.terracotta)
            .offset(x: x, y: up ? -120 : -10)
            .opacity(up ? 0 : 1)
            .onAppear { withAnimation(.easeOut(duration: 1.2)) { up = true } }
    }
}

struct StatBar: View {
    let label: String
    let value: Double
    let color: Color
    let symbol: String
    var suffix: String = "%"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(label, systemImage: symbol).font(.subheadline.weight(.semibold))
                Spacer()
                Text("\(Int(value))\(suffix)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(max(value, 0), 100), total: 100).tint(color)
        }
    }
}

struct CoinBadge: View {
    @EnvironmentObject var game: GameState

    var body: some View {
        // An HStack (not a Label) so toolbars always show the number, not just the icon
        HStack(spacing: 4) {
            Image(systemName: "dollarsign.circle.fill")
            Text("\(game.coins)")
        }
        .font(.subheadline.weight(.bold).monospacedDigit())
        .foregroundStyle(Theme.mustard)
        .contentTransition(.numericText())
        .animation(.snappy, value: game.coins)
    }
}
