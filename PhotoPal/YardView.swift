import Combine
import Photos
import SwiftUI
import UIKit

/// Your pal's yard. Junk photos show up as poop piles your pal sniffs out.
/// Tap a pile to scoop it, tap your pal for pets, tap the grass to throw a ball.
struct YardView: View {
    @EnvironmentObject var game: GameState
    @EnvironmentObject var library: PhotoLibrary
    @EnvironmentObject var router: Router
    @Binding var editing: Bool
    @Binding var feedRequest: ShopItem?
    var playToken: Int
    /// Space at the top and bottom covered by floating buttons, so nothing important hides under them
    var topInset: CGFloat = 0
    var bottomInset: CGFloat = 0
    /// Pets hold still while you build, so dragging stays smooth
    var animated = true

    // Positions are 0 to 1 inside the grass (x: left to right, y: back to front)
    @State private var petPos = CGPoint(x: 0.5, y: 0.55)
    @State private var ball: CGPoint?
    @State private var bubble: String?
    @State private var bubbleSymbol: String?
    @State private var bubbleToken = UUID()
    @State private var hearts: [UUID] = []
    @State private var hop = false
    @State private var busyUntil = Date.distantPast
    @State private var dragging: [UUID: CGSize] = [:]
    @State private var friendPos: [UUID: CGPoint] = [:]
    @State private var friendBubble: UUID?

    private let wander = Timer.publish(every: 3.5, on: .main, in: .common).autoconnect()

    /// Where each kind of poop piles up
    private func pileSpot(_ kind: JunkKind) -> CGPoint {
        switch kind {
        case .screenshots: return CGPoint(x: 0.14, y: 0.9)
        case .twins: return CGPoint(x: 0.87, y: 0.8)
        case .giants: return CGPoint(x: 0.5, y: 0.1)
        case .oopsies: return CGPoint(x: 0.36, y: 0.44)
        }
    }

    private func poopCount(_ kind: JunkKind) -> Int { library.report?.count(kind) ?? 0 }

    private func friendSpot(_ index: Int) -> CGPoint {
        let spots = [CGPoint(x: 0.22, y: 0.55), CGPoint(x: 0.78, y: 0.4), CGPoint(x: 0.4, y: 0.82), CGPoint(x: 0.7, y: 0.9)]
        return spots[index % spots.count]
    }

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let horizon = topInset + (h - topInset - bottomInset) * 0.24
            let ground = max(1, h - horizon - bottomInset)

            ZStack(alignment: .topLeading) {
                scenery(w: w, h: h, horizon: horizon)

                homeAndZones(w: w, horizon: horizon, ground: ground)

                ForEach(game.placed) { item in
                    decor(item, w: w, horizon: horizon, ground: ground)
                }

                ForEach(JunkKind.allCases) { kind in
                    if poopCount(kind) > 0 {
                        pile(kind, w: w, horizon: horizon, ground: ground)
                    }
                }

                ForEach(Array(game.otherPals.enumerated()), id: \.element.id) { index, friend in
                    friendView(friend, index: index, w: w, horizon: horizon, ground: ground)
                }

                pal(w: w, horizon: horizon, ground: ground)

                if let ball {
                    Image(systemName: "tennisball.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color(red: 0.8, green: 0.95, blue: 0.2))
                        .shadow(radius: 2)
                        .position(x: ball.x * w, y: horizon + ball.y * ground)
                        .zIndex(Double(ball.y) + 0.5)
                        .transition(.scale)
                }

                if game.sleeping {
                    lightsOff(w: w, h: h, horizon: horizon)
                        .zIndex(20)
                        .transition(.opacity)
                }

                if false {
                    Text("Drag things around. Tap the x to put them away.")
                        .font(.caption.bold())
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Theme.paper.opacity(0.92), in: Capsule())
                        .frame(width: w)
                        .padding(.top, topInset + 8)
                        .zIndex(30)
                }
            }
            .frame(width: w, height: h)
            .contentShape(Rectangle())
            .coordinateSpace(.named("yard"))
            .onTapGesture(coordinateSpace: .local) { location in
                handleTap(location, w: w, horizon: horizon, ground: ground)
            }
        }
        .onReceive(wander) { _ in
            wanderStep()
            wanderFriends()
        }
        .onChange(of: feedRequest) { _, item in
            guard let item else { return }
            react(to: item)
            feedRequest = nil
        }
        .onChange(of: playToken) { _, _ in
            throwBall(to: CGPoint(x: CGFloat.random(in: 0.15...0.85), y: CGFloat.random(in: 0.2...0.9)))
        }
        .onChange(of: game.sleeping) { _, asleep in
            if asleep { goToBed() }
        }
        .onChange(of: router.celebrate) { _, _ in
            guard !game.sleeping else { return }
            jump()
            burst(5)
            say(["Yay, so clean!", "Thank you!!", "Sparkly yard!"].randomElement() ?? "Yay!", symbol: "sparkles")
            after(0.45) { jump() }
        }
    }

    // MARK: Scenery (changes with the real time of day)

    private enum DayPart { case morning, day, evening, night }

    private var dayPart: DayPart {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 6..<10: return .morning
        case 10..<17: return .day
        case 17..<20: return .evening
        default: return .night
        }
    }

    private var skyColors: [Color] {
        switch dayPart {
        case .morning: return [Color(red: 1.0, green: 0.82, blue: 0.7), Color(red: 0.75, green: 0.88, blue: 1.0)]
        case .day: return [Color(red: 0.55, green: 0.78, blue: 0.98), Color(red: 0.85, green: 0.94, blue: 1.0)]
        case .evening: return [Color(red: 0.98, green: 0.6, blue: 0.55), Color(red: 1.0, green: 0.84, blue: 0.62)]
        case .night: return [Color(red: 0.12, green: 0.14, blue: 0.32), Color(red: 0.3, green: 0.3, blue: 0.52)]
        }
    }

    private var grassColors: [Color] {
        dayPart == .night
            ? [Color(red: 0.32, green: 0.5, blue: 0.36), Color(red: 0.2, green: 0.36, blue: 0.27)]
            : [Color(red: 0.66, green: 0.85, blue: 0.5), Color(red: 0.47, green: 0.72, blue: 0.4)]
    }

    private func scenery(w: CGFloat, h: CGFloat, horizon: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            LinearGradient(colors: skyColors, startPoint: .top, endPoint: .bottom)
                .frame(width: w, height: horizon + 40)

            // sun or moon
            if dayPart == .night {
                Image(systemName: "moon.fill")
                    .font(.system(size: 30))
                    .foregroundStyle(Color(red: 1, green: 0.95, blue: 0.75))
                    .position(x: w * 0.82, y: horizon * 0.55)
            } else {
                Circle()
                    .fill(Color(red: 1, green: 0.88, blue: 0.45))
                    .frame(width: 46, height: 46)
                    .shadow(color: .yellow.opacity(0.6), radius: 16)
                    .position(x: w * 0.82, y: horizon * (dayPart == .day ? 0.45 : 0.75))
            }
            cloud.position(x: w * 0.2, y: horizon * 0.55)
            cloud.scaleEffect(0.7).position(x: w * 0.55, y: horizon * 0.75)

            // rolling hills
            Ellipse().fill(grassColors[1].opacity(0.75))
                .frame(width: w * 1.1, height: 120)
                .position(x: w * 0.15, y: horizon + 18)
            Ellipse().fill(grassColors[0].opacity(0.9))
                .frame(width: w * 1.0, height: 100)
                .position(x: w * 0.9, y: horizon + 22)

            // the lawn
            LinearGradient(colors: grassColors, startPoint: .top, endPoint: .bottom)
                .frame(width: w, height: h - horizon)
                .offset(y: horizon)

            fence(w: w).offset(y: horizon - 22)
            bushes(w: w).offset(y: horizon - 6)
            lawnDetails(w: w, h: h, horizon: horizon)
        }
        .frame(width: w, height: h, alignment: .topLeading)
        .ignoresSafeArea()
    }

    private var cloud: some View {
        ZStack {
            Capsule().fill(.white).frame(width: 74, height: 24)
            Circle().fill(.white).frame(width: 32, height: 32).offset(x: -8, y: -11)
            Circle().fill(.white).frame(width: 24, height: 24).offset(x: 13, y: -8)
        }
        .opacity(dayPart == .night ? 0.25 : 0.9)
    }

    private func fence(w: CGFloat) -> some View {
        let count = max(1, Int(w / 24))
        let wood = Color(red: 0.99, green: 0.95, blue: 0.88)
        return ZStack(alignment: .top) {
            HStack(spacing: 10) {
                ForEach(0..<count, id: \.self) { _ in
                    UnevenRoundedRectangle(topLeadingRadius: 7, topTrailingRadius: 7)
                        .fill(wood)
                        .frame(width: 14, height: 28)
                        .shadow(color: Theme.cocoa.opacity(0.12), radius: 1, y: 1)
                }
            }
            Capsule().fill(wood.opacity(0.95))
                .frame(width: w, height: 5)
                .offset(y: 9)
        }
        .frame(width: w, height: 28, alignment: .top)
    }

    private func bushes(w: CGFloat) -> some View {
        let leaf = dayPart == .night ? Color(red: 0.25, green: 0.42, blue: 0.3) : Color(red: 0.42, green: 0.66, blue: 0.38)
        return ZStack(alignment: .topLeading) {
            ForEach(0..<5, id: \.self) { i in
                let x = w * CGFloat([0.04, 0.3, 0.52, 0.76, 0.98][i])
                HStack(spacing: -10) {
                    Circle().fill(leaf).frame(width: 26, height: 26)
                    Circle().fill(leaf.opacity(0.95)).frame(width: 34, height: 34).offset(y: -6)
                    Circle().fill(leaf).frame(width: 24, height: 24)
                }
                .position(x: x, y: 8)
            }
        }
        .frame(width: w, height: 30, alignment: .topLeading)
    }

    /// Little grass tufts and flowers, always in the same spots
    private func lawnDetails(w: CGFloat, h: CGFloat, horizon: CGFloat) -> some View {
        let spots: [(CGFloat, CGFloat, Int)] = [
            (0.08, 0.2, 0), (0.33, 0.12, 1), (0.58, 0.3, 0), (0.9, 0.18, 2), (0.15, 0.5, 1),
            (0.47, 0.55, 0), (0.83, 0.48, 1), (0.28, 0.72, 2), (0.62, 0.7, 0), (0.95, 0.66, 1),
            (0.05, 0.9, 0), (0.52, 0.92, 2), (0.75, 0.95, 0),
        ]
        let ground = h - horizon
        return ZStack(alignment: .topLeading) {
            ForEach(0..<spots.count, id: \.self) { i in
                let spot = spots[i]
                Group {
                    switch spot.2 {
                    case 1:
                        TinyFlower(petal: Color(red: 0.98, green: 0.72, blue: 0.76), size: 11)
                    case 2:
                        TinyFlower(petal: Color(red: 0.97, green: 0.86, blue: 0.55), size: 10)
                    default:
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(Color.green.opacity(0.35))
                            .rotationEffect(.degrees(-30))
                    }
                }
                .position(x: w * spot.0, y: horizon + ground * spot.1)
            }
        }
        .allowsHitTesting(false)
    }

    /// Lights off: the yard goes dark and cozy, like a real Tamagotchi
    private func lightsOff(w: CGFloat, h: CGFloat, horizon: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.06, green: 0.06, blue: 0.2).opacity(0.55)
            ForEach(0..<6, id: \.self) { i in
                Image(systemName: "sparkle")
                    .font(.system(size: 9))
                    .foregroundStyle(.white.opacity(0.8))
                    .position(x: w * CGFloat([0.1, 0.25, 0.4, 0.55, 0.68, 0.32][i]),
                              y: horizon * CGFloat([0.35, 0.6, 0.4, 0.7, 0.3, 0.85][i]))
            }
        }
        .frame(width: w, height: h)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: Home and yard zones (they upgrade as your pal grows)

    static let houseSpot = CGPoint(x: 0.82, y: 0.16)

    private var stageRank: Int { LifeStage.allCases.firstIndex(of: game.stage) ?? 0 }

    @ViewBuilder
    private func homeAndZones(w: CGFloat, horizon: CGFloat, ground: CGFloat) -> some View {
        let spot = Self.houseSpot
        let size = w * 0.3
        // Teen and up: a little garden box
        if stageRank >= 2 {
            GardenBox(width: w * 0.24)
                .position(x: w * 0.13, y: horizon + ground * 0.6)
                .zIndex(0.6)
                .allowsHitTesting(false)
        }
        // Companion and up: a pond
        if stageRank >= 3 {
            DecorArt(id: "pond", size: w * 0.34)
                .position(x: w * 0.2, y: horizon + ground * 0.2)
                .zIndex(0.2)
                .allowsHitTesting(false)
        }
        // Legend: fairy lights along the fence
        if stageRank >= 4 {
            FairyLights(width: w, glowing: game.sleeping || dayPart == .night || dayPart == .evening)
                .position(x: w / 2, y: horizon - 30)
                .zIndex(0.01)
                .allowsHitTesting(false)
        }
        Group {
            switch stageRank {
            case 0, 1: CardboardBox(size: size * 0.8)
            case 2, 3: WoodHouse(size: size, name: game.petName)
            default: Cabin(size: size * 1.15, lit: game.sleeping || dayPart == .night)
            }
        }
        .position(x: spot.x * w, y: horizon + spot.y * ground - size * 0.25)
        .zIndex(Double(spot.y))
        .allowsHitTesting(false)
    }

    // MARK: Poop piles

    private func pile(_ kind: JunkKind, w: CGFloat, horizon: CGFloat, ground: CGFloat) -> some View {
        let spot = pileSpot(kind)
        let count = poopCount(kind)
        let grow = 1 + min(0.9, log10(Double(count) + 1) * 0.35)
        let size = w * 0.1 * CGFloat(grow) * (kind == .giants ? 1.3 : 1)
        return PoopPile(kind: kind, count: count, size: size)
            .opacity(editing ? 0.35 : 1)
            .allowsHitTesting(!editing)
            .position(x: spot.x * w, y: horizon + spot.y * ground - size * 0.3)
            .zIndex(Double(spot.y))
            .onTapGesture {
                guard !editing else { return }
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                withAnimation { router.peek = kind }
            }
    }

    // MARK: Yard items

    private func decor(_ item: PlacedDecor, w: CGFloat, horizon: CGFloat, ground: CGFloat) -> some View {
        let depth = 0.65 + 0.5 * CGFloat(item.y)   // things in front look bigger
        let size = w * 0.2 * DecorArt.yardScale(item.itemID) * depth
        let drag = dragging[item.id] ?? .zero

        return DecorArt(id: item.itemID, size: size)
            .frame(minWidth: 56, minHeight: 56)
            .padding(8)
            .contentShape(Rectangle())
            .scaleEffect(dragging[item.id] != nil ? 1.12 : 1)
            .overlay {
                if editing {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.white, style: StrokeStyle(lineWidth: 2, dash: [5]))
                }
            }
            .overlay(alignment: .topTrailing) {
                if editing {
                    Button {
                        withAnimation(.spring) { game.storeDecor(item.id) }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundStyle(.white, .red)
                    }
                    .offset(x: 8, y: -8)
                }
            }
            .gesture(
                DragGesture(coordinateSpace: .named("yard"))
                    .onChanged { dragging[item.id] = $0.translation }
                    .onEnded { value in
                        let nx = item.x + Double(value.translation.width / w)
                        let ny = item.y + Double(value.translation.height / ground)
                        game.moveDecor(item.id, x: nx, y: ny)
                        dragging[item.id] = nil
                    },
                including: editing ? .all : .none
            )
            .position(x: CGFloat(item.x) * w + drag.width,
                      y: horizon + CGFloat(item.y) * ground + drag.height - size * 0.35)
            .zIndex(dragging[item.id] != nil ? 50 : (editing ? 10 + item.y : item.y))
    }

    // MARK: Your pal (the star of the show)

    private func pal(w: CGFloat, horizon: CGFloat, ground: CGFloat) -> some View {
        let depth = 0.75 + 0.45 * petPos.y
        let size = min(w * 0.42, 190) * depth
        return PalView(size: size, animated: animated)
            .overlay(alignment: .top) {
                speech.offset(y: -size * 0.12)
            }
            .overlay {
                ZStack {
                    ForEach(hearts, id: \.self) { _ in FloatingHeart() }
                }
            }
            .scaleEffect(hop ? 1.1 : 1, anchor: .bottom)
            .opacity(editing ? 0.45 : 1)
            .allowsHitTesting(!editing)
            .onTapGesture { patPal() }
            .position(x: petPos.x * w, y: horizon + petPos.y * ground - size * 0.5)
            .zIndex(Double(petPos.y) + 0.01)
    }

    /// Pals you aren't caring for right now, relaxing in the yard
    private func friendView(_ friend: Pal, index: Int, w: CGFloat, horizon: CGFloat, ground: CGFloat) -> some View {
        let pos = friendPos[friend.id] ?? friendSpot(index)
        let depth = 0.75 + 0.45 * pos.y
        let size = min(w * 0.3, 140) * depth
        return PetFigure(look: friend.look, stage: friend.stage, mood: .happy,
                         condition: PetCondition(sleeping: game.sleeping, sick: false, dirty: false),
                         hatID: friend.hatID, neckID: friend.neckID, size: size, animated: animated)
            .overlay(alignment: .top) {
                if friendBubble == friend.id {
                    Text(friend.name)
                        .font(.caption.bold())
                        .foregroundStyle(Theme.cocoa)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.paper, in: Capsule())
                        .shadow(color: Theme.cocoa.opacity(0.15), radius: 3, y: 1)
                        .fixedSize()
                        .offset(y: -size * 0.05)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .opacity(editing ? 0.45 : 1)
            .allowsHitTesting(!editing)
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(.spring) { friendBubble = friend.id }
                after(2) { if friendBubble == friend.id { withAnimation { friendBubble = nil } } }
            }
            .position(x: pos.x * w, y: horizon + pos.y * ground - size * 0.5)
            .zIndex(Double(pos.y))
    }

    private func wanderFriends() {
        guard !editing, !game.sleeping, let friend = game.otherPals.randomElement(), Bool.random() else { return }
        let target = CGPoint(x: CGFloat.random(in: 0.12...0.88), y: CGFloat.random(in: 0.3...0.9))
        withAnimation(.easeInOut(duration: 2.2)) { friendPos[friend.id] = target }
    }

    @ViewBuilder
    private var speech: some View {
        if let bubble {
            HStack(spacing: 4) {
                if let bubbleSymbol { Image(systemName: bubbleSymbol) }
                Text(bubble)
            }
            .font(.callout.bold())
            .foregroundStyle(Theme.cocoa)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Theme.paper, in: Capsule())
            .shadow(color: Theme.cocoa.opacity(0.18), radius: 4, y: 2)
            .fixedSize()
            .transition(.scale.combined(with: .opacity))
        } else if !game.sleeping && game.mood == .starving {
            thoughtBubble("fork.knife", .orange)
        } else if !game.sleeping && game.sick {
            thoughtBubble("thermometer.medium", .red)
        }
    }

    private func thoughtBubble(_ symbol: String, _ color: Color) -> some View {
        Image(systemName: symbol)
            .font(.callout.bold())
            .foregroundStyle(color)
            .padding(10)
            .background(Theme.paper, in: Circle())
            .shadow(color: Theme.cocoa.opacity(0.18), radius: 4, y: 2)
    }

    // MARK: Interactions

    private func handleTap(_ p: CGPoint, w: CGFloat, horizon: CGFloat, ground: CGFloat) {
        guard !editing, p.y > horizon else { return }
        let target = CGPoint(x: min(max(p.x / w, 0.05), 0.95),
                             y: min(max((p.y - horizon) / ground, 0.02), 0.98))
        throwBall(to: target)
    }

    private func throwBall(to target: CGPoint) {
        guard ball == nil, !editing else { return }
        if game.sleeping {
            say("Zzz... (turn the lights on first)", symbol: "moon.zzz.fill")
            return
        }
        if game.mood == .starving {
            say("Too hungry to play", symbol: "fork.knife")
            return
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) { ball = target }
        after(0.3) {
            run(to: target) {
                withAnimation(.easeOut(duration: 0.2)) { ball = nil }
                game.play()
                say("Got it!", symbol: "tennisball.fill")
                burst(2)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            }
        }
    }

    private func patPal() {
        guard !editing else { return }
        if game.sleeping {
            say("Zzz...", symbol: "moon.zzz.fill")
            return
        }
        game.pat()
        let lines: [String]
        switch game.species {
        case .dog: lines = ["Woof!", "Arf!", "More pets!"]
        case .cat: lines = ["Mrrp.", "Purrr...", "Fine. One more."]
        case .bunny: lines = ["*nose wiggle*", "Hop hop!", "Eee!"]
        case .panda: lines = ["Nom?", "Hehe", "Hug!"]
        case .fox: lines = ["Yip!", "Ring-ding!", "Hehe"]
        }
        say(lines.randomElement() ?? "Hi!")
        burst(1)
        jump()
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    private func react(to item: ShopItem) {
        if item.category == .food {
            // trot over to the bowl if there is one
            let bowl = game.placed.first { $0.itemID == "bowl" }
            let spot = bowl.map { CGPoint(x: min(0.95, $0.x + 0.1), y: min(0.98, $0.y + 0.03)) } ?? petPos
            run(to: spot) {
                say(game.isFavorite(item) ? "My favorite!!" : "Nom nom!", symbol: item.symbol)
                burst(game.isFavorite(item) ? 5 : 3)
            }
        } else {
            say("Yay, a \(item.name.lowercased())!", symbol: item.symbol)
            burst(4)
            jump()
        }
    }

    /// Every few seconds your pal wanders, or goes and points out poop
    private func wanderStep() {
        guard !editing, !game.sleeping, ball == nil, Date() > busyUntil, game.mood != .starving else { return }

        let piles = JunkKind.allCases.filter { poopCount($0) > 0 }
        if let kind = piles.randomElement(), Int.random(in: 0..<3) == 0 {
            let spot = pileSpot(kind)
            let next = CGPoint(x: min(0.92, max(0.08, spot.x + (spot.x > 0.5 ? -0.14 : 0.14))),
                               y: min(0.96, spot.y + 0.04))
            run(to: next) {
                let count = poopCount(kind)
                say(["Ew! \(count) \(kind.title.lowercased())!", "Poop alert!", "Scoop this please!"].randomElement() ?? "Ew!",
                    symbol: "exclamationmark.triangle.fill")
            }
            return
        }

        if game.sick {
            say("I don't feel good...", symbol: "thermometer.medium")
            busyUntil = Date().addingTimeInterval(6)
            return
        }

        // grumpy pals sulk at their house or bed
        if game.mood == .grumpy, let home = homeSpot() {
            run(to: home)
            return
        }
        guard Int.random(in: 0..<3) > 0 else { return }   // sometimes just sit
        run(to: CGPoint(x: CGFloat.random(in: 0.25...0.75), y: CGFloat.random(in: 0.3...0.8)))
    }

    private func homeSpot() -> CGPoint? {
        if let bed = game.placed.first(where: { $0.itemID == "bed" }) {
            return CGPoint(x: bed.x, y: min(0.98, bed.y + 0.06))
        }
        return CGPoint(x: Self.houseSpot.x - 0.02, y: Self.houseSpot.y + 0.14)
    }

    private func goToBed() {
        if let home = homeSpot() { run(to: home) }
    }

    // MARK: Helpers

    private func run(to target: CGPoint, then done: (() -> Void)? = nil) {
        let distance = hypot(target.x - petPos.x, target.y - petPos.y)
        let duration = max(0.35, Double(distance) * 1.8)
        withAnimation(.easeInOut(duration: duration)) { petPos = target }
        busyUntil = Date().addingTimeInterval(duration + 1)
        if let done { after(duration) { done() } }
    }

    private func jump() {
        withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) { hop = true }
        after(0.2) { withAnimation(.spring) { hop = false } }
    }

    private func say(_ text: String, symbol: String? = nil) {
        let token = UUID()
        bubbleToken = token
        withAnimation(.spring) {
            bubble = text
            bubbleSymbol = symbol
        }
        after(2.2) {
            if bubbleToken == token { withAnimation { bubble = nil } }
        }
    }

    private func burst(_ count: Int) {
        for i in 0..<count {
            let id = UUID()
            after(Double(i) * 0.12) { hearts.append(id) }
            after(1.5 + Double(i) * 0.12) { hearts.removeAll { $0 == id } }
        }
    }

    private func after(_ seconds: Double, _ action: @escaping @MainActor () -> Void) {
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(seconds))
            action()
        }
    }
}

// MARK: - A pile of poop (with flies and a count)

struct PoopPile: View {
    let kind: JunkKind
    let count: Int
    let size: CGFloat

    var body: some View {
        ZStack(alignment: .topTrailing) {
            poops
                .overlay(alignment: .bottom) {
                    Image(systemName: kind.symbol)
                        .font(.system(size: size * 0.2, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                        .offset(y: -size * 0.06)
                }
            Text("\(count)")
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.red, in: Capsule())
                .offset(x: 10, y: -8)
        }
        .overlay(alignment: .top) {
            Flies(size: size).offset(y: -size * 0.25)
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var poops: some View {
        switch kind {
        case .twins:
            HStack(spacing: -size * 0.2) {
                DustBunny(size: size * 0.8)
                DustBunny(size: size * 0.66)
            }
        case .oopsies:
            DustBunny(size: size * 0.9)
        case .screenshots, .giants:
            PoopView(size: size)
        }
    }
}

struct Flies: View {
    let size: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack {
                ForEach(0..<2, id: \.self) { i in
                    let angle = t * 3.2 + Double(i) * 3.1
                    Circle()
                        .fill(Color.black.opacity(0.75))
                        .frame(width: 4, height: 4)
                        .offset(x: CGFloat(cos(angle)) * size * 0.4,
                                y: CGFloat(sin(angle * 1.6)) * size * 0.15)
                }
            }
            .frame(width: size, height: size * 0.4)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Dust bunnies (twin shots and oopsies)

struct DustBunny: View {
    let size: CGFloat
    private let fluff = Color(red: 0.78, green: 0.76, blue: 0.74)

    var body: some View {
        ZStack {
            ForEach(0..<7, id: \.self) { i in
                let angle = Double(i) / 7 * 2 * .pi
                Circle()
                    .fill(fluff)
                    .frame(width: size * 0.42, height: size * 0.42)
                    .offset(x: CGFloat(cos(angle)) * size * 0.26, y: CGFloat(sin(angle)) * size * 0.2)
            }
            Ellipse().fill(fluff.opacity(0.95)).frame(width: size * 0.7, height: size * 0.56)
            HStack(spacing: size * 0.12) {
                Circle().fill(Color(red: 0.2, green: 0.17, blue: 0.16)).frame(width: size * 0.09, height: size * 0.09)
                Circle().fill(Color(red: 0.2, green: 0.17, blue: 0.16)).frame(width: size * 0.09, height: size * 0.09)
            }
            .offset(y: -size * 0.02)
        }
        .frame(width: size, height: size * 0.8)
        .blur(radius: 0.4)
    }
}

// MARK: - Houses (they upgrade as your pal grows)

struct CardboardBox: View {
    let size: CGFloat
    private let card = Color(red: 0.8, green: 0.62, blue: 0.42)

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: size * 0.3) {
                Rectangle().fill(card.opacity(0.85)).frame(width: size * 0.3, height: size * 0.18)
                    .rotationEffect(.degrees(-30), anchor: .bottomTrailing)
                Rectangle().fill(card.opacity(0.85)).frame(width: size * 0.3, height: size * 0.18)
                    .rotationEffect(.degrees(30), anchor: .bottomLeading)
            }
            ZStack {
                Rectangle().fill(card).frame(width: size * 0.9, height: size * 0.6)
                Rectangle().fill(Color(red: 0.9, green: 0.8, blue: 0.6)).frame(width: size * 0.9, height: size * 0.08)
                    .offset(y: -size * 0.26)
                UnevenRoundedRectangle(topLeadingRadius: size * 0.16, topTrailingRadius: size * 0.16)
                    .fill(Color(red: 0.45, green: 0.32, blue: 0.22))
                    .frame(width: size * 0.34, height: size * 0.34)
                    .offset(y: size * 0.13)
            }
        }
        .shadow(color: Theme.cocoa.opacity(0.2), radius: 3, y: 2)
    }
}

struct WoodHouse: View {
    let size: CGFloat
    let name: String

    var body: some View {
        VStack(spacing: -size * 0.04) {
            Triangle()
                .fill(Theme.terracotta)
                .frame(width: size, height: size * 0.42)
            ZStack(alignment: .bottom) {
                Rectangle()
                    .fill(Theme.woodLight)
                    .overlay(WoodGrain())
                    .frame(width: size * 0.82, height: size * 0.56)
                UnevenRoundedRectangle(topLeadingRadius: size * 0.17, topTrailingRadius: size * 0.17)
                    .fill(Color(red: 0.32, green: 0.22, blue: 0.16))
                    .frame(width: size * 0.34, height: size * 0.36)
                Text(name)
                    .font(Theme.header(max(8, size * 0.09), "Bold", relativeTo: .caption2))
                    .foregroundStyle(Theme.cocoa)
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .padding(.horizontal, 4)
                    .background(Theme.paper, in: RoundedRectangle(cornerRadius: 3))
                    .frame(maxWidth: size * 0.6)
                    .offset(y: -size * 0.42)
            }
        }
        .shadow(color: Theme.cocoa.opacity(0.25), radius: 4, y: 2)
    }
}

struct Cabin: View {
    let size: CGFloat
    let lit: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            ZStack(alignment: .top) {
                // chimney smoke
                ForEach(0..<3, id: \.self) { i in
                    let phase = (t * 0.25 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                    Circle()
                        .fill(Color.white.opacity(0.6 * (1 - phase)))
                        .frame(width: size * (0.08 + 0.08 * CGFloat(phase)), height: size * (0.08 + 0.08 * CGFloat(phase)))
                        .offset(x: size * 0.28 + size * 0.05 * CGFloat(sin(phase * 6)), y: -size * 0.1 - size * 0.35 * CGFloat(phase))
                }
                Rectangle().fill(Theme.woodDark).frame(width: size * 0.1, height: size * 0.2).offset(x: size * 0.28, y: size * 0.02)
                VStack(spacing: -size * 0.03) {
                    Triangle().fill(Theme.terracotta).frame(width: size * 1.05, height: size * 0.4)
                    ZStack {
                        Rectangle().fill(Theme.woodLight).frame(width: size * 0.9, height: size * 0.5)
                        VStack(spacing: size * 0.06) {
                            ForEach(0..<5, id: \.self) { _ in
                                Capsule().fill(Theme.woodDark.opacity(0.35)).frame(width: size * 0.9, height: size * 0.025)
                            }
                        }
                        HStack(spacing: size * 0.12) {
                            RoundedRectangle(cornerRadius: size * 0.02)
                                .fill(lit ? Color(red: 1, green: 0.85, blue: 0.45) : Color(red: 0.7, green: 0.85, blue: 0.95))
                                .frame(width: size * 0.2, height: size * 0.17)
                                .shadow(color: lit ? Color.yellow.opacity(0.8) : .clear, radius: 8)
                            UnevenRoundedRectangle(topLeadingRadius: size * 0.12, topTrailingRadius: size * 0.12)
                                .fill(Color(red: 0.32, green: 0.22, blue: 0.16))
                                .frame(width: size * 0.22, height: size * 0.3)
                                .offset(y: size * 0.1)
                        }
                    }
                }
                .padding(.top, size * 0.08)
            }
        }
        .shadow(color: Theme.cocoa.opacity(0.25), radius: 4, y: 2)
    }
}

// MARK: - Yard zones

struct GardenBox: View {
    let width: CGFloat

    var body: some View {
        ZStack(alignment: .bottom) {
            HStack(spacing: -width * 0.08) {
                DecorArt(id: "flowers", size: width * 0.42)
                FoodArt(id: "carrot", size: width * 0.3).rotationEffect(.degrees(180)).offset(y: width * 0.02)
                DecorArt(id: "flowers", size: width * 0.42)
            }
            .offset(y: -width * 0.1)
            RoundedRectangle(cornerRadius: width * 0.06, style: .continuous)
                .fill(Soft.fill(Soft.wood, width))
                .overlay(WoodGrain().clipShape(RoundedRectangle(cornerRadius: width * 0.06, style: .continuous)))
                .frame(width: width, height: width * 0.2)
        }
    }
}

struct Pond: View {
    let width: CGFloat

    var body: some View {
        ZStack {
            Ellipse().fill(Color(red: 0.62, green: 0.6, blue: 0.55)).frame(width: width * 1.06, height: width * 0.46)
            Ellipse().fill(LinearGradient(colors: [Color(red: 0.55, green: 0.78, blue: 0.85), Color(red: 0.38, green: 0.62, blue: 0.75)],
                                          startPoint: .top, endPoint: .bottom))
                .frame(width: width, height: width * 0.4)
            Ellipse().fill(Theme.sageDeep).frame(width: width * 0.16, height: width * 0.07).offset(x: -width * 0.2, y: width * 0.02)
            Ellipse().fill(Theme.sage).frame(width: width * 0.12, height: width * 0.05).offset(x: width * 0.18, y: -width * 0.05)
            Image(systemName: "camera.macro")
                .font(.system(size: width * 0.08))
                .foregroundStyle(Color(red: 1, green: 0.75, blue: 0.82))
                .offset(x: -width * 0.2, y: -width * 0.01)
        }
    }
}

struct FairyLights: View {
    let width: CGFloat
    let glowing: Bool
    private let colors: [Color] = [Theme.mustard, Theme.terracotta, Theme.sage, Theme.dustyBlue, Theme.plum]

    var body: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 0, y: 4))
                p.addQuadCurve(to: CGPoint(x: width / 2, y: 4), control: CGPoint(x: width / 4, y: 22))
                p.addQuadCurve(to: CGPoint(x: width, y: 4), control: CGPoint(x: width * 0.75, y: 22))
            }
            .stroke(Theme.cocoa.opacity(0.5), lineWidth: 1)
            ForEach(0..<12, id: \.self) { i in
                let x = width * (CGFloat(i) + 0.5) / 12
                let local = (x.truncatingRemainder(dividingBy: width / 2)) / (width / 2)
                let y = 4 + 18 * 4 * local * (1 - local) / 2
                Circle()
                    .fill(colors[i % colors.count])
                    .frame(width: 7, height: 7)
                    .shadow(color: glowing ? colors[i % colors.count] : .clear, radius: 5)
                    .position(x: x, y: y + 3)
            }
        }
        .frame(width: width, height: 30)
    }
}

/// A tiny lawn flower
struct TinyFlower: View {
    let petal: Color
    let size: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<5, id: \.self) { i in
                let angle = Double(i) / 5 * 2 * .pi
                Circle().fill(petal)
                    .frame(width: size * 0.5, height: size * 0.5)
                    .offset(x: CGFloat(cos(angle)) * size * 0.28, y: CGFloat(sin(angle)) * size * 0.28)
            }
            Circle().fill(Color(red: 1, green: 0.95, blue: 0.75)).frame(width: size * 0.3, height: size * 0.3)
        }
        .frame(width: size, height: size)
    }
}
