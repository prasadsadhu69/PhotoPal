import Foundation
import SwiftUI

// This file is shared by the app AND the Home Screen widget,
// so it must not use app-only types like GameState or PhotoLibrary.

// MARK: - Colors

struct RGB: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    var color: Color { Color(red: r, green: g, blue: b) }
    var luminance: Double { 0.299 * r + 0.587 * g + 0.114 * b }

    func mixed(with other: RGB, _ t: Double) -> RGB {
        RGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }
}

/// A coat of colors for a pet. `accent` is ears, patches, tips or socks depending on the animal.
struct PetPalette: Codable, Hashable, Identifiable {
    var id: String
    var name: String
    var main: RGB
    var accent: RGB
    var belly: RGB
    var blaze: Bool       // white stripe down the nose
    var price: Int        // 0 = free
}

// MARK: - Animals

enum Species: String, Codable, CaseIterable, Identifiable {
    case dog, cat, bunny, panda, fox

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dog: return "Dog"
        case .cat: return "Cat"
        case .bunny: return "Bunny"
        case .panda: return "Panda"
        case .fox: return "Fox"
        }
    }

    var defaultName: String {
        switch self {
        case .dog: return "Peanut"
        case .cat: return "Mochi"
        case .bunny: return "Clover"
        case .panda: return "Bao"
        case .fox: return "Maple"
        }
    }

    var personality: String {
        switch self {
        case .dog: return "Loyal and goofy. Lives for fetch and belly rubs."
        case .cat: return "Sleepy and sassy. Naps in every sunbeam."
        case .bunny: return "Sweet and hoppy. Happiest in the garden."
        case .panda: return "Round and snacky. Never says no to bamboo."
        case .fox: return "A curious explorer who loves digging up memories."
        }
    }

    var babyName: String {
        switch self {
        case .dog: return "Puppy"
        case .cat: return "Kitten"
        case .bunny: return "Baby bunny"
        case .panda: return "Cub"
        case .fox: return "Kit"
        }
    }

    /// Shop item id this animal loves (extra happiness when fed)
    var favoriteFood: String {
        switch self {
        case .dog: return "pupcake"
        case .cat: return "salmon"
        case .bunny: return "carrot"
        case .panda: return "bamboo"
        case .fox: return "berries"
        }
    }

    var palettes: [PetPalette] {
        switch self {
        case .dog:
            return [
                PetPalette(id: "peanut", name: "Peanut", main: RGB(0.95, 0.84, 0.66), accent: RGB(0.86, 0.68, 0.45), belly: RGB(1, 0.98, 0.95), blaze: true, price: 0),
                PetPalette(id: "golden", name: "Golden", main: RGB(0.88, 0.66, 0.38), accent: RGB(0.68, 0.44, 0.22), belly: RGB(0.98, 0.9, 0.78), blaze: false, price: 0),
                PetPalette(id: "choco", name: "Chocolate", main: RGB(0.52, 0.34, 0.22), accent: RGB(0.32, 0.2, 0.13), belly: RGB(0.82, 0.7, 0.6), blaze: false, price: 150),
                PetPalette(id: "husky", name: "Husky", main: RGB(0.6, 0.62, 0.68), accent: RGB(0.34, 0.36, 0.42), belly: RGB(0.98, 0.98, 1), blaze: true, price: 200),
            ]
        case .cat:
            return [
                PetPalette(id: "ginger", name: "Ginger", main: RGB(0.96, 0.62, 0.32), accent: RGB(0.98, 0.72, 0.7), belly: RGB(1, 0.93, 0.84), blaze: false, price: 0),
                PetPalette(id: "tuxedo", name: "Tuxedo", main: RGB(0.2, 0.2, 0.23), accent: RGB(0.95, 0.7, 0.72), belly: RGB(0.97, 0.97, 0.97), blaze: true, price: 0),
                PetPalette(id: "smoky", name: "Smoky", main: RGB(0.62, 0.64, 0.7), accent: RGB(0.95, 0.72, 0.75), belly: RGB(0.92, 0.92, 0.95), blaze: false, price: 150),
                PetPalette(id: "snow", name: "Snowball", main: RGB(0.98, 0.97, 0.95), accent: RGB(0.98, 0.72, 0.78), belly: RGB(1, 1, 1), blaze: false, price: 200),
            ]
        case .bunny:
            return [
                PetPalette(id: "cotton", name: "Cotton", main: RGB(0.97, 0.96, 0.94), accent: RGB(1, 0.76, 0.82), belly: RGB(1, 1, 1), blaze: false, price: 0),
                PetPalette(id: "cocoa", name: "Cocoa", main: RGB(0.62, 0.47, 0.36), accent: RGB(0.9, 0.66, 0.66), belly: RGB(0.92, 0.86, 0.8), blaze: false, price: 0),
                PetPalette(id: "honey", name: "Honey", main: RGB(0.93, 0.76, 0.46), accent: RGB(1, 0.72, 0.72), belly: RGB(1, 0.95, 0.86), blaze: false, price: 150),
                PetPalette(id: "lilac", name: "Lilac", main: RGB(0.8, 0.74, 0.9), accent: RGB(0.98, 0.72, 0.86), belly: RGB(0.96, 0.94, 0.99), blaze: false, price: 200),
            ]
        case .panda:
            return [
                PetPalette(id: "classic", name: "Classic", main: RGB(0.97, 0.97, 0.96), accent: RGB(0.13, 0.13, 0.15), belly: RGB(1, 1, 1), blaze: false, price: 0),
                PetPalette(id: "cocoa", name: "Cocoa", main: RGB(0.96, 0.93, 0.88), accent: RGB(0.45, 0.3, 0.22), belly: RGB(1, 0.98, 0.95), blaze: false, price: 0),
                PetPalette(id: "sakura", name: "Sakura", main: RGB(0.99, 0.94, 0.95), accent: RGB(0.93, 0.5, 0.62), belly: RGB(1, 1, 1), blaze: false, price: 200),
                PetPalette(id: "midnight", name: "Midnight", main: RGB(0.28, 0.28, 0.33), accent: RGB(0.95, 0.95, 0.97), belly: RGB(0.4, 0.4, 0.46), blaze: false, price: 250),
            ]
        case .fox:
            return [
                PetPalette(id: "red", name: "Red", main: RGB(0.95, 0.5, 0.2), accent: RGB(0.25, 0.18, 0.15), belly: RGB(1, 0.97, 0.94), blaze: false, price: 0),
                PetPalette(id: "arctic", name: "Arctic", main: RGB(0.96, 0.97, 1), accent: RGB(0.62, 0.68, 0.8), belly: RGB(1, 1, 1), blaze: false, price: 0),
                PetPalette(id: "fennec", name: "Fennec", main: RGB(0.95, 0.85, 0.65), accent: RGB(0.8, 0.55, 0.4), belly: RGB(1, 0.97, 0.9), blaze: false, price: 150),
                PetPalette(id: "silver", name: "Silver", main: RGB(0.55, 0.55, 0.6), accent: RGB(0.18, 0.18, 0.22), belly: RGB(0.95, 0.95, 0.97), blaze: false, price: 200),
            ]
        }
    }

    func palette(_ id: String) -> PetPalette {
        palettes.first { $0.id == id } ?? palettes[0]
    }
}

/// What a pet looks like: the animal, its colors, and an optional custom coat from a real photo.
struct PetLook: Codable, Hashable {
    var species: Species = .dog
    var paletteID: String = "peanut"
    var custom: PetPalette? = nil

    var palette: PetPalette { custom ?? species.palette(paletteID) }
}

// MARK: - Growing up

enum LifeStage: String, Codable, CaseIterable {
    case baby, kid, teen, adult, radiant

    /// XP needed to reach this stage
    var xpNeeded: Int {
        switch self {
        case .baby: return 0
        case .kid: return 150
        case .teen: return 400
        case .adult: return 800
        case .radiant: return 1500
        }
    }

    var next: LifeStage? {
        switch self {
        case .baby: return .kid
        case .kid: return .teen
        case .teen: return .adult
        case .adult: return .radiant
        case .radiant: return nil
        }
    }

    /// Short stage name, like "Teen"
    var title: String {
        switch self {
        case .baby: return "Baby"
        case .kid: return "Little"
        case .teen: return "Teen"
        case .adult: return "Companion"
        case .radiant: return "Legend"
        }
    }

    /// Stage name for a specific animal, like "Puppy" or "Teen cat"
    func name(for species: Species) -> String {
        switch self {
        case .baby: return species.babyName
        case .kid: return "Little \(species.title.lowercased())"
        case .teen: return "Teen \(species.title.lowercased())"
        case .adult: return "Companion"
        case .radiant: return "Legend"
        }
    }

    /// Overall size compared to a grown-up
    var scale: CGFloat {
        switch self {
        case .baby: return 0.62
        case .kid: return 0.74
        case .teen: return 0.87
        case .adult, .radiant: return 1
        }
    }

    /// Babies have big heads
    var headRatio: CGFloat {
        switch self {
        case .baby: return 1.22
        case .kid: return 1.14
        case .teen: return 1.06
        case .adult, .radiant: return 1
        }
    }
}

enum PetMood: String, Codable {
    case starving = "Starving", grumpy = "Grumpy", content = "Content", happy = "Happy", thriving = "Thriving"

    static func from(food: Double, joy: Double, clean: Double = 100) -> PetMood {
        if food < 15 { return .starving }
        let avg = (food + joy + clean) / 3
        switch avg {
        case ..<35: return .grumpy
        case ..<60: return .content
        case ..<85: return .happy
        default: return .thriving
        }
    }
}

struct PetCondition: Equatable {
    var sleeping = false
    var sick = false
    var dirty = false
}

// MARK: - Poop (junk photos)

enum JunkKind: String, Codable, CaseIterable, Identifiable {
    case screenshots, twins, giants, oopsies

    var id: String { rawValue }

    var title: String {
        switch self {
        case .screenshots: return "Screenshots"
        case .twins: return "Twin shots"
        case .giants: return "Giant videos"
        case .oopsies: return "Oopsies"
        }
    }

    var poopName: String {
        switch self {
        case .screenshots: return "Screenshot poop"
        case .twins: return "Twin poops"
        case .giants: return "Mega poop"
        case .oopsies: return "Oopsie poop"
        }
    }

    var blurb: String {
        switch self {
        case .screenshots: return "Old screenshots you probably don't need anymore"
        case .twins: return "Near-duplicate shots. Keep the best, scoop the rest"
        case .giants: return "Videos over 50 MB that hog the most space"
        case .oopsies: return "Blurry, pitch-black or accidental pocket shots"
        }
    }

    var symbol: String {
        switch self {
        case .screenshots: return "iphone"
        case .twins: return "square.on.square"
        case .giants: return "film"
        case .oopsies: return "eye.slash"
        }
    }

    var coinsPerItem: Int {
        switch self {
        case .screenshots, .twins, .oopsies: return 1
        case .giants: return 4
        }
    }

    var dailyTarget: Int {
        switch self {
        case .screenshots: return 20
        case .twins: return 10
        case .giants: return 2
        case .oopsies: return 8
        }
    }

    var dailyReward: Int {
        switch self {
        case .screenshots, .twins, .oopsies: return 30
        case .giants: return 40
        }
    }
}

struct DailyBounty: Codable, Equatable {
    var kind: JunkKind
    var target: Int
    var progress: Int
    var reward: Int
    var day: Date
    var paid: Bool
}

struct Milestone: Identifiable {
    let id: String
    let title: String
    let bytes: Int64
    let coins: Int
    let gift: String?   // a free outfit

    static let all: [Milestone] = [
        Milestone(id: "mb100", title: "Tidy Paws: free 100 MB", bytes: 100_000_000, coins: 30, gift: nil),
        Milestone(id: "gb1", title: "Gigabyte Hero: free 1 GB", bytes: 1_000_000_000, coins: 100, gift: "party"),
        Milestone(id: "gb5", title: "Storage Saver: free 5 GB", bytes: 5_000_000_000, coins: 250, gift: "scarf"),
        Milestone(id: "gb10", title: "Cloud Whisperer: free 10 GB", bytes: 10_000_000_000, coins: 500, gift: "crown"),
        Milestone(id: "gb25", title: "Legend of the Roll: free 25 GB", bytes: 25_000_000_000, coins: 1000, gift: nil),
    ]
}

// MARK: - Shop

enum ItemCategory: String, Codable {
    case food, toy, care, hat, neck, decor
}

struct ShopItem: Identifiable, Hashable {
    let id: String
    let name: String
    let symbol: String          // SF Symbol used in lists
    let category: ItemCategory
    let price: Int
    var food: Double = 0        // treats: fills the tummy
    var joy: Double = 0         // treats and toys: boosts happiness
    var comfort: Int = 0        // yard items: makes happiness drain slower

    static let all: [ShopItem] = [
        // Treats
        ShopItem(id: "kibble", name: "Crunchy Kibble", symbol: "circle.grid.2x2.fill", category: .food, price: 8, food: 12, joy: 2),
        ShopItem(id: "berries", name: "Wild Berries", symbol: "leaf.fill", category: .food, price: 10, food: 14, joy: 4),
        ShopItem(id: "carrot", name: "Carrot Stick", symbol: "carrot.fill", category: .food, price: 12, food: 15, joy: 3),
        ShopItem(id: "bamboo", name: "Bamboo Shoots", symbol: "laurel.leading", category: .food, price: 12, food: 18, joy: 3),
        ShopItem(id: "salmon", name: "Salmon Bite", symbol: "fish.fill", category: .food, price: 35, food: 45, joy: 8),
        ShopItem(id: "pupcake", name: "Pupcake", symbol: "birthday.cake.fill", category: .food, price: 80, food: 60, joy: 30),
        // Toys
        ShopItem(id: "tennis", name: "Tennis Ball", symbol: "tennisball.fill", category: .toy, price: 40, joy: 25),
        ShopItem(id: "squeaky", name: "Squeaky Bird", symbol: "bird.fill", category: .toy, price: 60, joy: 40),
        ShopItem(id: "winetoy", name: "Plush Wine Bottle", symbol: "wineglass.fill", category: .toy, price: 70, joy: 45),
        ShopItem(id: "music", name: "Music Box", symbol: "music.note", category: .toy, price: 90, joy: 50),
        // Care
        ShopItem(id: "medicine", name: "Medicine", symbol: "cross.case.fill", category: .care, price: 40),
        // Hats
        ShopItem(id: "party", name: "Party Hat", symbol: "party.popper.fill", category: .hat, price: 120),
        ShopItem(id: "beanie", name: "Cozy Beanie", symbol: "snowflake", category: .hat, price: 150),
        ShopItem(id: "bow", name: "Big Bow", symbol: "gift.fill", category: .hat, price: 100),
        ShopItem(id: "crown", name: "Royal Crown", symbol: "crown.fill", category: .hat, price: 600),
        // Neckwear
        ShopItem(id: "bandana", name: "Red Bandana", symbol: "triangle.fill", category: .neck, price: 90),
        ShopItem(id: "bowtie", name: "Bow Tie", symbol: "sparkles", category: .neck, price: 110),
        ShopItem(id: "collar", name: "Red Collar", symbol: "circle.circle.fill", category: .neck, price: 80),
        ShopItem(id: "scarf", name: "Mint Scarf", symbol: "wind", category: .neck, price: 160),
        // Yard and home
        ShopItem(id: "bowl", name: "Food Bowl", symbol: "circle.bottomhalf.filled", category: .decor, price: 50, comfort: 5),
        ShopItem(id: "flowers", name: "Flower Patch", symbol: "camera.macro", category: .decor, price: 80, comfort: 5),
        ShopItem(id: "lamp", name: "Garden Lamp", symbol: "lamp.floor.fill", category: .decor, price: 120, comfort: 6),
        ShopItem(id: "tree", name: "Shade Tree", symbol: "tree.fill", category: .decor, price: 180, comfort: 8),
        ShopItem(id: "umbrella", name: "Sun Umbrella", symbol: "beach.umbrella.fill", category: .decor, price: 220, comfort: 10),
        ShopItem(id: "bed", name: "Fluffy Pet Bed", symbol: "bed.double.fill", category: .decor, price: 300, comfort: 15),
        ShopItem(id: "pond", name: "Splash Pond", symbol: "water.waves", category: .decor, price: 450, comfort: 12),
        ShopItem(id: "doghouse", name: "Pet House", symbol: "house.fill", category: .decor, price: 800, comfort: 25),
    ]

    static func byID(_ id: String) -> ShopItem? { all.first { $0.id == id } }
}

/// A yard item placed somewhere in the yard
struct PlacedDecor: Codable, Identifiable, Equatable {
    var id = UUID()
    var itemID: String
    var x: Double   // 0 = left edge, 1 = right edge
    var y: Double   // 0 = back by the fence, 1 = front of the yard
}

// MARK: - Data the Home Screen widget reads

enum Shared {
    /// Must match the App Group in Signing & Capabilities (both targets)
    static let appGroup = "group.com.pranati.PhotoPal"
}

struct WidgetSnapshot: Codable {
    var name: String
    var look: PetLook
    var stage: LifeStage
    var food: Double
    var joy: Double
    var clean: Double
    var sleeping: Bool
    var sick: Bool
    var hatID: String?
    var neckID: String?
    var poops: Int
    var streak: Int
    var savedAt: Date

    private static let key = "widget.snapshot.v2"

    static let sample = WidgetSnapshot(name: "Peanut", look: PetLook(), stage: .kid, food: 80, joy: 80, clean: 80,
                                       sleeping: false, sick: false, hatID: nil, neckID: "collar",
                                       poops: 0, streak: 0, savedAt: Date())

    static func load() -> WidgetSnapshot? {
        guard let raw = UserDefaults(suiteName: Shared.appGroup)?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: raw)
    }

    func save() {
        if let raw = try? JSONEncoder().encode(self) {
            UserDefaults(suiteName: Shared.appGroup)?.set(raw, forKey: Self.key)
        }
    }

    /// Fullness and happiness at a later time, using roughly the same drain as the app
    func projected(at date: Date) -> (food: Double, joy: Double) {
        let hours = max(0, date.timeIntervalSince(savedAt) / 3600)
        if sleeping { return (max(0, food - hours * 1.5), joy) }
        return (max(0, food - hours * 3), max(0, joy - hours * 2.5))
    }
}
