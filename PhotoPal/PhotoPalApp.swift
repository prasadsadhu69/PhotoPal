import Photos
import Combine
import SwiftUI
import UIKit
import WidgetKit

enum AppTab: Hashable {
    case yard, care, closet, memories
}

/// Lets any screen switch tabs, open sheets, or make your pal celebrate
final class Router: ObservableObject {
    @Published var tab: AppTab = .yard
    @Published var cleaning: JunkKind?       // opens a scooping session for one pile
    @Published var showScoop = false         // the camera roll health report
    @Published var showProfile = false       // your pal's profile, other pals, stats
    @Published var peek: JunkKind?           // quick look at a poop pile
    @Published var celebrate = 0             // bump to make your pal do a happy jump
}

@main
struct PhotoPalApp: App {
    @StateObject private var game = GameState()
    @StateObject private var library = PhotoLibrary()
    @StateObject private var router = Router()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Cloud save and server-side game rules (no-op until Firebase is added; see backend/README.md)
        BackendSync.configure()

        // Friendly rounded headers in navigation bars
        if let title = UIFont(name: "Fredoka-SemiBold", size: 18),
           let large = UIFont(name: "Fredoka-Bold", size: 32) {
            let cocoa = UIColor(red: 0.35, green: 0.25, blue: 0.2, alpha: 1)
            UINavigationBar.appearance().titleTextAttributes = [.font: title, .foregroundColor: cocoa]
            UINavigationBar.appearance().largeTitleTextAttributes = [.font: large, .foregroundColor: cocoa]
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .preferredColorScheme(.light)
                .environmentObject(game)
                .environmentObject(library)
                .environmentObject(router)
                .task { await BackendSync.shared.connect(game) }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active:
                        // Your pal gets hungry while the app is closed
                        game.tick()
                        Task { await BackendSync.shared.connect(game) }
                        if game.onboarded && library.hasAccess {
                            Task { await library.refresh(game) }
                            library.loadVault()
                        }
                    case .background:
                        // Refresh reminders and the Home Screen widget with the latest state
                        PeanutNotifier.schedule(for: game)
                        game.exportWidgetSnapshot()
                        WidgetCenter.shared.reloadAllTimelines()
                    default:
                        break
                    }
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject var game: GameState
    @EnvironmentObject var library: PhotoLibrary
    @EnvironmentObject var router: Router

    var body: some View {
        if !game.onboarded {
            AdoptFlow()
        } else if !library.hasAccess {
            AccessView()
        } else {
            ZStack(alignment: .bottom) {
                Group {
                    switch router.tab {
                    case .yard: HomeView()
                    case .care: CareView()
                    case .closet: ClosetView()
                    case .memories: MemoriesView()
                    }
                }
                // leave room under every list for the wooden dock
                .contentMargins(.bottom, CozyDock.height + 16, for: .scrollContent)
                CozyDock()
            }
            .tint(Theme.terracotta)
            .foregroundStyle(Theme.cocoa)
            .sheet(item: $router.cleaning) { kind in
                CleanupView(kind: kind)
            }
            .sheet(isPresented: $router.showScoop) { CleanView() }
            .sheet(isPresented: $router.showProfile) { ProfileSheet() }
            .task {
                await PeanutNotifier.requestPermission()
                await library.refresh(game)
                library.loadVault()
            }
        }
    }
}

// MARK: - The wooden dock at the bottom

struct CozyDock: View {
    /// How much room the dock takes at the bottom of the screen
    static let height: CGFloat = 96

    @EnvironmentObject var router: Router
    @EnvironmentObject var library: PhotoLibrary

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            tab(.yard, "Yard", "house.fill")
            tab(.care, "Feed & Care", "fork.knife")
            spade
            tab(.closet, "Closet", "tshirt.fill")
            tab(.memories, "Memories", "photo.on.rectangle.angled")
        }
        .padding(.horizontal, 8)
        .padding(.top, 10)
        .padding(.bottom, 6)
        .woodPanel(radius: 28)
        .padding(.horizontal, 10)
        .padding(.bottom, 4)
    }

    private func tab(_ tab: AppTab, _ title: String, _ symbol: String) -> some View {
        let selected = router.tab == tab
        return Button {
            withAnimation(.snappy) { router.tab = tab }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 3) {
                Image(systemName: symbol)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 32)
                    .background {
                        if selected {
                            Capsule().fill(Theme.oatmeal.opacity(0.95))
                                .overlay(Capsule().inset(by: 2.5)
                                    .stroke(Theme.woodDark.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [3, 2.5])))
                        }
                    }
                Text(title)
                    .font(Theme.header(11, "SemiBold", relativeTo: .caption2))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(selected ? Theme.cocoa : Color.white.opacity(0.92))
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    /// The big "Scoop & Sweep" spade in the middle
    private var spade: some View {
        Button {
            router.showScoop = true
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } label: {
            VStack(spacing: 2) {
                SpadeIcon()
                    .frame(width: 68, height: 68)
                    .background(Circle().fill(Theme.mustard)
                        .overlay(PaperGrain(opacity: 0.1).clipShape(Circle()))
                        .overlay(Circle().inset(by: 4).stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.3, dash: [4, 3]))))
                    .shadow(color: Theme.cocoa.opacity(0.3), radius: 6, y: 3)
                    .overlay(alignment: .topTrailing) {
                        let count = library.report?.junkCount ?? 0
                        if count > 0 {
                            Text(count > 99 ? "99+" : "\(count)")
                                .font(Theme.header(11, "Bold", relativeTo: .caption2))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.terracotta, in: Capsule())
                                .overlay(Capsule().stroke(Color.white, lineWidth: 1.5))
                        }
                    }
                Text("Scoop & Sweep")
                    .font(Theme.header(11, "Bold", relativeTo: .caption2))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .fixedSize()
            }
            .offset(y: -18)
            .padding(.bottom, -18)
            .frame(width: 84)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Scoop and sweep")
    }
}

/// A little wooden-handled spade
struct SpadeIcon: View {
    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            ZStack {
                // handle
                Capsule()
                    .fill(LinearGradient(colors: [Theme.woodLight, Theme.woodDark], startPoint: .leading, endPoint: .trailing))
                    .frame(width: s * 0.11, height: s * 0.42)
                    .offset(y: -s * 0.2)
                Capsule()
                    .fill(Theme.woodDark)
                    .frame(width: s * 0.24, height: s * 0.08)
                    .offset(y: -s * 0.4)
                // scoop
                UnevenRoundedRectangle(topLeadingRadius: s * 0.05, bottomLeadingRadius: s * 0.2,
                                       bottomTrailingRadius: s * 0.2, topTrailingRadius: s * 0.05)
                    .fill(LinearGradient(colors: [Color(white: 0.93), Color(white: 0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: s * 0.36, height: s * 0.34)
                    .overlay(Capsule().fill(Color.white.opacity(0.7)).frame(width: s * 0.05, height: s * 0.18).offset(x: -s * 0.08))
                    .offset(y: s * 0.13)
            }
            .rotationEffect(.degrees(-25))
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}
