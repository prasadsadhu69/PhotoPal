import Photos
import SwiftUI
import UIKit

/// Feed & Care: your pal on a cozy rug, their needs, the pantry, care actions, and the treat shop
struct CareView: View {
    @EnvironmentObject var game: GameState

    @State private var bubble: String?
    @State private var hop = false
    @State private var hearts: [UUID] = []
    @State private var message: String?
    @State private var snack: ShopItem?        // the treat or toy in front of your pal right now
    @State private var bites = 0
    @State private var chomping = false
    @State private var toyBounce = false

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    palCorner.id("pal")
                    needsCard
                    careActions
                    pantry
                    shopSection("Treats", .food)
                    shopSection("Toys", .toy)
                    shopSection("Care", .care)
                }
                .padding()
            }
            .onChange(of: snack) { _, item in
                if item != nil { withAnimation(.easeInOut) { scroller.scrollTo("pal", anchor: .top) } }
            }
            }
            .paperBackground()
            .navigationTitle("Feed & Care")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { CoinBadge() } }
            .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
                Button("OK", role: .cancel) {}
            }
        }
    }

    // MARK: Your pal on a rug

    private var palCorner: some View {
        ZStack {
            Ellipse()
                .fill(Theme.terracotta.opacity(0.25))
                .overlay(Ellipse().inset(by: 6).stroke(Theme.terracotta.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])))
                .frame(width: 230, height: 60)
                .offset(y: 80)
            PalView(size: 150, chomping: chomping)
                .scaleEffect(hop ? 1.1 : 1, anchor: .bottom)
                .overlay(alignment: .top) {
                    if let bubble {
                        Text(bubble)
                            .font(Theme.headline)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(Theme.paper, in: Capsule())
                            .shadow(color: Theme.cocoa.opacity(0.15), radius: 3, y: 1)
                            .fixedSize()
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .overlay {
                    ZStack { ForEach(hearts, id: \.self) { _ in FloatingHeart() } }
                }
                .onTapGesture { react("Hehe!", hearts: 1) { game.pat() } }
            if let snack {
                ZStack {
                    FoodArt(id: snack.id, size: 58)
                        .scaleEffect(max(0.05, 1 - 0.3 * CGFloat(bites)))
                        .opacity(bites >= 3 ? 0 : 1)
                        .offset(y: toyBounce ? -26 : 0)
                    // crumbs fly off with each bite
                    ForEach(0..<bites * 3, id: \.self) { i in
                        Circle()
                            .fill(Theme.woodDark.opacity(0.7))
                            .frame(width: 5, height: 5)
                            .offset(x: CGFloat([-26, 22, -14, 30, -32, 12, 26, -20, 6][i % 9]),
                                    y: CGFloat([6, 2, 14, 12, -2, 18, -6, 20, 14][i % 9]))
                            .transition(.scale.combined(with: .opacity))
                    }
                }
                .offset(x: 34, y: 74)
                .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 230)
        .paperCard(padding: 8, radius: 28)
    }

    private var needsCard: some View {
        VStack(spacing: 12) {
            StatBar(label: "Hunger", value: game.food, color: Theme.mustard, symbol: "fork.knife")
            StatBar(label: "Happy", value: game.joy, color: Theme.terracotta, symbol: "heart.fill")
            StatBar(label: "Clean (your camera roll)", value: game.clean, color: Theme.sageDeep, symbol: "sparkles")
            StatBar(label: "Energy", value: game.energy, color: Theme.plum, symbol: "bolt.fill")
        }
        .paperCard()
    }

    // MARK: Care buttons

    private var careActions: some View {
        HStack(spacing: 10) {
            careButton("Brush", "hands.sparkles.fill", Theme.dustyBlue, disabled: game.sleeping) {
                react("Ahh, fluffy!", hearts: 2) { game.brush() }
            }
            careButton(game.sleeping ? "Wake up" : "Lights off", game.sleeping ? "sun.max.fill" : "moon.fill", Theme.plum, disabled: false) {
                withAnimation { game.toggleLights() }
            }
            careButton("Medicine (\(game.medicineCount))", "cross.case.fill", .red, disabled: !game.sick) {
                if game.giveMedicine() {
                    react("All better!", hearts: 3) {}
                } else {
                    message = "You're out of medicine. Buy some below."
                }
            }
        }
    }

    private func careButton(_ title: String, _ symbol: String, _ color: Color, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Circle().fill(disabled ? Color.gray.opacity(0.4) : color)
                        .overlay(Circle().inset(by: 3).stroke(Color.white.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 2.5]))))
                Text(title)
                    .font(Theme.label)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .frame(maxWidth: .infinity)
            .paperCard(padding: 10, radius: 18)
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }

    // MARK: Pantry

    private var pantry: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pantry").font(Theme.title3)
            let owned = ShopItem.all.filter {
                ($0.category == .food || $0.category == .toy) && (game.inventory[$0.id] ?? 0) > 0
            }
            if owned.isEmpty {
                Text("Empty! Scoop poop to earn coins, then buy treats below.")
                    .font(.subheadline)
                    .opacity(0.7)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(owned) { item in
                        Button {
                            feed(item)
                        } label: {
                            VStack(spacing: 4) {
                                FoodArt(id: item.id, size: 40)
                                Text(item.name).font(.caption).lineLimit(1)
                                Text("x\(game.inventory[item.id] ?? 0)").font(Theme.label)
                                if game.isFavorite(item) {
                                    Text("Favorite").font(Theme.label).foregroundStyle(.white).feltBadge(Theme.terracotta)
                                }
                            }
                            .frame(maxWidth: .infinity, minHeight: 92)
                            .paperCard(padding: 8, radius: 18)
                        }
                        .buttonStyle(.plain)
                        .disabled(game.sleeping || snack != nil)
                    }
                }
            }
        }
    }

    private func feed(_ item: ShopItem) {
        guard snack == nil, !game.sleeping else { return }
        let favorite = game.isFavorite(item)
        guard game.feed(item) else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        bites = 0
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) { snack = item }

        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.5))
            if item.category == .food {
                // munch, munch, munch
                chomping = true
                for bite in 1...3 {
                    try? await Task.sleep(for: .seconds(0.6))
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.5)) { bites = bite }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                }
                try? await Task.sleep(for: .seconds(0.3))
                chomping = false
                react(favorite ? "My favorite!!" : "Nom nom! Yum!", hearts: favorite ? 6 : 3) {}
            } else {
                // a toy: it bounces, your pal bounces
                for _ in 0..<3 {
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) { toyBounce = true }
                    try? await Task.sleep(for: .seconds(0.3))
                    withAnimation(.spring(response: 0.25, dampingFraction: 0.45)) { toyBounce = false }
                    try? await Task.sleep(for: .seconds(0.3))
                }
                react("Yay, a \(item.name.lowercased())!", hearts: 4) {}
                try? await Task.sleep(for: .seconds(1.2))
            }
            try? await Task.sleep(for: .seconds(0.4))
            withAnimation(.easeOut) {
                snack = nil
                bites = 0
            }
        }
    }

    // MARK: Shop

    private func shopSection(_ title: String, _ category: ItemCategory) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Shop: \(title)").font(Theme.title3)
            VStack(spacing: 8) {
                ForEach(ShopItem.all.filter { $0.category == category }) { item in
                    ShopRow(item: item)
                }
            }
        }
    }

    // MARK: Little reactions

    private func react(_ line: String, hearts count: Int, _ action: () -> Void) {
        guard !game.sleeping else {
            withAnimation { bubble = "Zzz..." }
            clearBubble()
            return
        }
        action()
        withAnimation(.spring) { bubble = line }
        withAnimation(.spring(response: 0.2, dampingFraction: 0.4)) { hop = true }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.2))
            withAnimation(.spring) { hop = false }
        }
        for i in 0..<count {
            let id = UUID()
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(Double(i) * 0.12))
                hearts.append(id)
                try? await Task.sleep(for: .seconds(1.5))
                hearts.removeAll { $0 == id }
            }
        }
        clearBubble()
    }

    private func clearBubble() {
        let current = bubble
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            if bubble == current { withAnimation { bubble = nil } }
        }
    }
}
