import Photos
import SwiftUI
import UIKit

/// One item for sale, used by the shops in Feed & Care and the Closet
struct ShopRow: View {
    let item: ShopItem
    @EnvironmentObject var game: GameState

    private var isOutfit: Bool { item.category == .hat || item.category == .neck }
    private var ownedOutfit: Bool { isOutfit && game.owns(item) }

    var body: some View {
        HStack(spacing: 12) {
            ItemIcon(item: item)
                .background(Theme.oatmeal, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name).font(Theme.headline)
                    if game.isFavorite(item) {
                        Text("Favorite").font(Theme.label).foregroundStyle(.white).feltBadge(Theme.terracotta)
                    }
                }
                Text(detail).font(.caption).opacity(0.7)
                if let count = ownedCount, count > 0 {
                    Text("You have \(count)").font(Theme.label).foregroundStyle(Theme.terracotta)
                }
            }
            Spacer()
            if ownedOutfit {
                Text("Owned").font(Theme.label).opacity(0.6)
            } else {
                Button {
                    if game.buy(item) {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "dollarsign.circle.fill")
                        Text("\(item.price)")
                    }
                    .font(Theme.header(15, "Bold", relativeTo: .subheadline))
                    .foregroundStyle(.white)
                    .feltBadge(game.coins >= item.price ? Theme.mustard : Color.gray.opacity(0.5))
                }
                .buttonStyle(.plain)
                .disabled(game.coins < item.price)
            }
        }
        .paperCard(padding: 10, radius: 18)
    }

    private var ownedCount: Int? {
        switch item.category {
        case .food, .toy, .care: return game.inventory[item.id] ?? 0
        case .decor: return game.decorOwned(item.id)
        case .hat, .neck: return nil
        }
    }

    private var detail: String {
        switch item.category {
        case .food: return "+\(Int(item.food)) hunger, +\(Int(item.joy)) happy"
        case .toy: return "+\(Int(item.joy)) happy"
        case .care: return "Cures a sick pal and protects them for a day"
        case .hat, .neck: return "Dress up \(game.petName)"
        case .decor: return "+\(item.comfort) cozy, so happiness drains slower"
        }
    }
}
