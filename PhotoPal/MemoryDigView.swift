import SwiftUI
import UIKit
import Photos

/// Once a day, your pal digs up a photo from this day in past years.
struct MemoryDigView: View {
    @EnvironmentObject var game: GameState
    @EnvironmentObject var library: PhotoLibrary
    @Environment(\.dismiss) private var dismiss
    @Environment(\.displayScale) private var displayScale

    @State private var asset: PHAsset?
    @State private var image: UIImage?
    @State private var searched = false
    @State private var done: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                if !searched {
                    Spacer()
                    PalView(size: 120)
                    ProgressView("\(game.petName) is digging...")
                    Spacer()
                } else if let done {
                    Spacer()
                    PalView(mood: .thriving, size: 140)
                    Text(done).font(Theme.title3).multilineTextAlignment(.center)
                    Button("Back to the yard") { dismiss() }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.terracotta)
                    Spacer()
                } else if let asset {
                    found(asset)
                } else {
                    Spacer()
                    PalView(mood: .content, size: 130)
                    Text("Nothing buried here yet")
                        .font(Theme.title3)
                    Text("No photos from around this day in past years. \(game.petName) will dig again tomorrow!")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("OK") {
                        game.finishDig(foundSomething: false)
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.terracotta)
                    Spacer()
                }
            }
            .padding()
            .navigationTitle("Memory Dig")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
            }
            .task {
                guard !searched else { return }
                let candidates = library.memories().filter { !game.keptIDs.contains($0.localIdentifier) }
                asset = candidates.randomElement()
                searched = true
                if let asset {
                    let side = 360 * displayScale
                    image = await library.image(for: asset, size: CGSize(width: side, height: side))
                }
            }
        }
    }

    private func found(_ asset: PHAsset) -> some View {
        VStack(spacing: 16) {
            Text("\(game.petName) dug up a memory!")
                .font(Theme.title3)
            Text(whenText(asset))
                .font(.subheadline)
                .foregroundStyle(.secondary)

            ZStack {
                RoundedRectangle(cornerRadius: 20).fill(Color.gray.opacity(0.15))
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    ProgressView()
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(1, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

            HStack(spacing: 10) {
                choice("Toss", "trash.fill", .red) {
                    Task {
                        if let bytes = try? await library.delete([asset]) {
                            game.finishDig(foundSomething: true, freedBytes: bytes)
                            UINotificationFeedbackGenerator().notificationOccurred(.success)
                            withAnimation(.spring) { done = "Scooped! +5 coins for digging." }
                        }
                    }
                }
                choice("Keep", "checkmark", .green) {
                    game.keep([asset.localIdentifier])
                    finish("Kept! +5 coins for digging.")
                }
                choice("Favorite", "heart.fill", .pink) {
                    game.keep([asset.localIdentifier])
                    Task { await library.setFavorite(asset) }
                    finish("Added to your Favorites album! +5 coins.")
                }
            }
        }
    }

    private func choice(_ title: String, _ symbol: String, _ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol).font(.title3)
                Text(title).font(.caption.bold())
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
        }
        .buttonStyle(.bordered)
        .tint(color)
    }

    private func finish(_ message: String) {
        game.finishDig(foundSomething: true)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        withAnimation(.spring) { done = message }
    }

    private func whenText(_ asset: PHAsset) -> String {
        guard let date = asset.creationDate else { return "From a while ago" }
        let years = Calendar.current.dateComponents([.year], from: date, to: Date()).year ?? 0
        let dateText = date.formatted(date: .long, time: .omitted)
        if years <= 0 { return dateText }
        return "\(years) year\(years == 1 ? "" : "s") ago, \(dateText)"
    }
}
