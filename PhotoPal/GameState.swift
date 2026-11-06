import Combine
import Foundation

/// A pal that's resting in the yard while you care for a different one.
/// Its meters pause until you switch back to it.
struct Pal: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var look: PetLook
    var born: Date
    var stage: LifeStage
    var xp: Int
    var careMistakes: Int
    var food: Double
    var joy: Double
    var energy: Double
    var sick: Bool
    var hatID: String?
    var neckID: String?
}

/// Everything that gets saved between app launches
private struct SaveData: Codable {
    var activeID = UUID()
    var otherPals: [Pal] = []
    var tickets = 0           // adoption tickets, earned by growing up
    var onboarded = false
    var look = PetLook()
    var petName = "Peanut"
    var born = Date()
    var stage: LifeStage = .baby
    var careMistakes = 0

    // Needs (0 to 100)
    var food = 80.0
    var joy = 80.0
    var energy = 90.0
    var clean = 100.0          // mirrors your camera roll health score
    var sleeping = false
    var sick = false
    var sickImmuneUntil: Date? = nil

    var coins = 30
    var xp = 0
    var inventory: [String: Int] = ["kibble": 3]
    var keptIDs: Set<String> = []   // photos you chose to keep, so they never count as poop again
    var notTwinIDs: Set<String> = [] // photos checked and found to have no real look-alike
    var itemsTossed = 0
    var bytesFreed: Int64 = 0
    var cleanups = 0
    var poops = 0
    var streak = 0
    var lastPlayDay: Date? = nil
    var lastCleanDay: Date? = nil
    var lastTick = Date()
    var lastDigDay: Date? = nil
    var daily: DailyBounty? = nil
    var milestones: Set<String> = []
    var hasFed = false

    // Looks
    var hatID: String? = nil
    var neckID: String? = nil
    var wardrobe: Set<String> = []
    var palettesOwned: Set<String> = []
    var photoMatchUnlocked = false

    // Yard
    var decorOwned: [String: Int] = ["bowl": 1]
    var placed: [PlacedDecor] = [PlacedDecor(itemID: "bowl", x: 0.22, y: 0.3)]

    init() {}

    private enum LegacyKeys: String, CodingKey { case furID }

    /// Reads a save from any earlier version. Missing fields get defaults, so updates never wipe progress.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SaveData()
        // Saves from before the adoption screen existed already have a pet
        onboarded = try c.decodeIfPresent(Bool.self, forKey: .onboarded) ?? true
        if let look = try c.decodeIfPresent(PetLook.self, forKey: .look) {
            self.look = look
        } else {
            let legacy = try decoder.container(keyedBy: LegacyKeys.self)
            let fur = try legacy.decodeIfPresent(String.self, forKey: .furID) ?? "peanut"
            let map = ["golden": "golden", "choco": "choco", "gray": "husky"]
            self.look = PetLook(species: .dog, paletteID: map[fur] ?? "peanut", custom: nil)
        }
        petName = try c.decodeIfPresent(String.self, forKey: .petName) ?? d.petName
        born = try c.decodeIfPresent(Date.self, forKey: .born) ?? d.born
        careMistakes = try c.decodeIfPresent(Int.self, forKey: .careMistakes) ?? 0
        food = try c.decodeIfPresent(Double.self, forKey: .food) ?? d.food
        joy = try c.decodeIfPresent(Double.self, forKey: .joy) ?? d.joy
        energy = try c.decodeIfPresent(Double.self, forKey: .energy) ?? d.energy
        clean = try c.decodeIfPresent(Double.self, forKey: .clean) ?? d.clean
        sleeping = try c.decodeIfPresent(Bool.self, forKey: .sleeping) ?? false
        sick = try c.decodeIfPresent(Bool.self, forKey: .sick) ?? false
        sickImmuneUntil = try c.decodeIfPresent(Date.self, forKey: .sickImmuneUntil)
        coins = try c.decodeIfPresent(Int.self, forKey: .coins) ?? d.coins
        xp = try c.decodeIfPresent(Int.self, forKey: .xp) ?? 0
        stage = try c.decodeIfPresent(LifeStage.self, forKey: .stage) ?? (xp >= 400 ? .adult : xp >= 120 ? .kid : .baby)
        inventory = try c.decodeIfPresent([String: Int].self, forKey: .inventory) ?? d.inventory
        keptIDs = try c.decodeIfPresent(Set<String>.self, forKey: .keptIDs) ?? []
        notTwinIDs = try c.decodeIfPresent(Set<String>.self, forKey: .notTwinIDs) ?? []
        itemsTossed = try c.decodeIfPresent(Int.self, forKey: .itemsTossed) ?? 0
        bytesFreed = try c.decodeIfPresent(Int64.self, forKey: .bytesFreed) ?? 0
        cleanups = try c.decodeIfPresent(Int.self, forKey: .cleanups) ?? (itemsTossed > 0 ? 1 : 0)
        poops = try c.decodeIfPresent(Int.self, forKey: .poops) ?? 0
        streak = try c.decodeIfPresent(Int.self, forKey: .streak) ?? 0
        lastPlayDay = try c.decodeIfPresent(Date.self, forKey: .lastPlayDay)
        lastCleanDay = try c.decodeIfPresent(Date.self, forKey: .lastCleanDay)
        lastTick = try c.decodeIfPresent(Date.self, forKey: .lastTick) ?? Date()
        lastDigDay = try c.decodeIfPresent(Date.self, forKey: .lastDigDay)
        daily = try c.decodeIfPresent(DailyBounty.self, forKey: .daily)
        milestones = try c.decodeIfPresent(Set<String>.self, forKey: .milestones) ?? []
        hasFed = try c.decodeIfPresent(Bool.self, forKey: .hasFed) ?? true
        hatID = try c.decodeIfPresent(String.self, forKey: .hatID)
        neckID = try c.decodeIfPresent(String.self, forKey: .neckID)
        wardrobe = try c.decodeIfPresent(Set<String>.self, forKey: .wardrobe) ?? []
        palettesOwned = try c.decodeIfPresent(Set<String>.self, forKey: .palettesOwned) ?? []
        photoMatchUnlocked = try c.decodeIfPresent(Bool.self, forKey: .photoMatchUnlocked) ?? false
        decorOwned = try c.decodeIfPresent([String: Int].self, forKey: .decorOwned) ?? d.decorOwned
        placed = try c.decodeIfPresent([PlacedDecor].self, forKey: .placed) ?? d.placed
        activeID = try c.decodeIfPresent(UUID.self, forKey: .activeID) ?? UUID()
        otherPals = try c.decodeIfPresent([Pal].self, forKey: .otherPals) ?? []
        tickets = try c.decodeIfPresent(Int.self, forKey: .tickets) ?? 0
    }
}

/// What you got for scooping a pile of poop
struct CleanReward {
    var kind: JunkKind
    var count: Int
    var bytes: Int64
    var coins: Int
    var firstTodayBonus: Int
    var streakBonus: Int
    var dailyBonus: Int
    var milestones: [Milestone]
    var grewTo: LifeStage?

    var total: Int {
        coins + firstTodayBonus + streakBonus + dailyBonus + milestones.reduce(0) { $0 + $1.coins }
    }
}

@MainActor
final class GameState: ObservableObject {
    @Published private var data: SaveData { didSet { save() } }
    /// Set when your pal grows up outside of a scooping session (shows a celebration on Home)
    @Published var justGrew: LifeStage?
    private static let saveKey = "photopal.save.v2"

    init() {
        if let raw = UserDefaults.standard.data(forKey: Self.saveKey),
           let decoded = try? JSONDecoder().decode(SaveData.self, from: raw) {
            data = decoded
        } else {
            data = SaveData()
        }
        tick()
    }

    // MARK: Reading the save

    var onboarded: Bool { data.onboarded }
    var look: PetLook { data.look }
    var species: Species { data.look.species }
    var stage: LifeStage { data.stage }
    var coins: Int { data.coins }
    var food: Double { data.food }
    var joy: Double { data.joy }
    var energy: Double { data.energy }
    var clean: Double { data.clean }
    var sleeping: Bool { data.sleeping }
    var sick: Bool { data.sick }
    var careMistakes: Int { data.careMistakes }
    var inventory: [String: Int] { data.inventory }
    var keptIDs: Set<String> { data.keptIDs }
    var notTwinIDs: Set<String> { data.notTwinIDs }
    var itemsTossed: Int { data.itemsTossed }
    var bytesFreed: Int64 { data.bytesFreed }
    var cleanups: Int { data.cleanups }
    var streak: Int { data.streak }
    var lastPlayDay: Date? { data.lastPlayDay }
    var daily: DailyBounty? { data.daily }
    var milestonesReached: Set<String> { data.milestones }
    var hasFed: Bool { data.hasFed }
    var hatID: String? { data.hatID }
    var neckID: String? { data.neckID }
    var placed: [PlacedDecor] { data.placed }
    var photoMatchUnlocked: Bool { data.photoMatchUnlocked }
    var buildUnlocked: Bool { data.cleanups >= 1 }
    var ageDays: Int { max(0, Int(Date().timeIntervalSince(data.born) / 86400)) }

    var petName: String {
        get { data.petName }
        set {
            data.petName = newValue
            sync(.rename(newValue))
        }
    }

    var mood: PetMood {
        let m = PetMood.from(food: data.food, joy: data.joy, clean: data.clean)
        if data.sick && (m == .happy || m == .thriving) { return .content }
        return m
    }

    var condition: PetCondition {
        PetCondition(sleeping: data.sleeping, sick: data.sick, dirty: data.clean < 50)
    }

    /// Sum of comfort from yard items. Higher = happiness drains slower.
    var cozy: Int { Self.cozy(of: data.placed) }

    private static func cozy(of placed: [PlacedDecor]) -> Int {
        min(100, placed.reduce(0) { $0 + (ShopItem.byID($1.itemID)?.comfort ?? 0) })
    }

    // MARK: Growing up

    var xp: Int { data.xp }
    var tickets: Int { data.tickets }

    /// Every 100 XP is a level
    var level: Int { data.xp / 100 + 1 }
    var levelProgress: Double { Double(data.xp % 100) / 100 }

    var nextStageHint: String {
        guard let next = data.stage.next else { return "Fully grown and legendary!" }
        let left = max(0, next.xpNeeded - data.xp)
        return "\(left) XP until \(data.petName) becomes \(next == .adult ? "a Companion" : next == .radiant ? "a Legend" : "a " + next.name(for: data.look.species).lowercased()). Scooping poop earns the most XP."
    }

    var growthProgress: Double {
        guard let next = data.stage.next else { return 1 }
        let start = data.stage.xpNeeded
        let span = Double(next.xpNeeded - start)
        return min(1, max(0, Double(data.xp - start) / span))
    }

    /// Grows your pal as far as its XP allows. Each new stage from Teen up earns an adoption ticket.
    private static func advanceStage(_ d: inout SaveData) -> LifeStage? {
        var grew: LifeStage?
        while let next = d.stage.next, d.xp >= next.xpNeeded {
            d.stage = next
            grew = next
            let owned = 1 + d.otherPals.count
            if next != .kid && owned < Species.allCases.count {
                d.tickets += 1
            }
        }
        return grew
    }

    // MARK: Your pals (collecting more animals)

    var otherPals: [Pal] { data.otherPals }
    var activeID: UUID { data.activeID }

    /// Animals you don't have yet
    var speciesToAdopt: [Species] {
        let owned = Set([data.look.species] + data.otherPals.map(\.look.species))
        return Species.allCases.filter { !owned.contains($0) }
    }

    private func activeAsPal(_ d: SaveData) -> Pal {
        Pal(id: d.activeID, name: d.petName, look: d.look, born: d.born, stage: d.stage, xp: d.xp,
            careMistakes: d.careMistakes, food: d.food, joy: d.joy, energy: d.energy, sick: d.sick,
            hatID: d.hatID, neckID: d.neckID)
    }

    private func load(_ pal: Pal, into d: inout SaveData) {
        d.activeID = pal.id
        d.petName = pal.name
        d.look = pal.look
        d.born = pal.born
        d.stage = pal.stage
        d.xp = pal.xp
        d.careMistakes = pal.careMistakes
        d.food = pal.food
        d.joy = pal.joy
        d.energy = pal.energy
        d.sick = pal.sick
        d.hatID = pal.hatID
        d.neckID = pal.neckID
        d.sleeping = false
        d.lastTick = Date()
    }

    /// Care for a different pal. The current one rests in the yard.
    func switchTo(_ id: UUID) {
        tick()
        guard let index = data.otherPals.firstIndex(where: { $0.id == id }) else { return }
        var d = data
        let chosen = d.otherPals.remove(at: index)
        d.otherPals.append(activeAsPal(d))
        load(chosen, into: &d)
        data = d
        sync(.switchPal(palId: id.uuidString))
    }

    /// Spends a ticket to adopt a new baby animal, who becomes the one you're caring for
    @discardableResult
    func adoptNewPal(species: Species, name: String, paletteID: String) -> Bool {
        guard data.tickets > 0, speciesToAdopt.contains(species) else { return false }
        tick()
        var d = data
        d.tickets -= 1
        d.otherPals.append(activeAsPal(d))
        let baby = Pal(id: UUID(), name: name, look: PetLook(species: species, paletteID: paletteID, custom: nil),
                       born: Date(), stage: .baby, xp: 0, careMistakes: 0,
                       food: 80, joy: 85, energy: 90, sick: false, hatID: nil, neckID: nil)
        load(baby, into: &d)
        data = d
        sync(.adoptPal(species: species.rawValue, name: name, paletteId: paletteID))
        return true
    }

    // MARK: Time passing (the Tamagotchi part)

    func tick(now: Date = Date()) {
        let hours = now.timeIntervalSince(data.lastTick) / 3600
        guard hours > 0.005 else { return }
        var d = data
        let wasFed = d.food > 0
        let wasHappy = d.joy > 0

        if d.sleeping {
            d.energy = min(100, d.energy + hours * 14)
            d.food = max(0, d.food - hours * 1.5)
            if d.energy >= 100 { d.sleeping = false }   // wakes up rested
        } else {
            d.food = max(0, d.food - hours * 3)
            let comfort = max(0.4, 1 - Double(Self.cozy(of: d.placed)) / 120)
            let sickFactor = d.sick ? 1.6 : 1.0
            d.joy = max(0, d.joy - hours * 2.5 * comfort * sickFactor)
            d.energy = max(0, d.energy - hours * 4)
            if d.energy <= 0 { d.sleeping = true }      // dozed off on its own
        }
        if wasFed && d.food <= 0 { d.careMistakes += 1 }
        if wasHappy && d.joy <= 0 { d.careMistakes += 1 }
        Self.checkSick(&d, now: now)
        let grew = Self.advanceStage(&d)
        d.lastTick = now
        data = d
        if let grew { justGrew = grew }
    }

    private static func checkSick(_ d: inout SaveData, now: Date) {
        guard !d.sick else { return }
        if let immune = d.sickImmuneUntil, now < immune { return }
        if d.food <= 0 || d.clean < 20 { d.sick = true }
    }

    // MARK: Poop (camera roll scans)

    func applyScan(_ report: JunkReport) {
        var d = data
        d.clean = Double(report.score)
        d.poops = report.junkCount
        let cal = Calendar.current
        if d.daily == nil || !cal.isDateInToday(d.daily!.day) {
            d.daily = Self.makeDaily(report)
        }
        Self.checkSick(&d, now: Date())
        data = d
        // Only counts and sizes go to the server, never photo IDs
        var counts: [String: Int] = [:]
        var bytes: [String: Int64] = [:]
        for kind in JunkKind.allCases {
            counts[kind.rawValue] = report.count(kind)
            bytes[kind.rawValue] = report.bytesFor(kind)
        }
        sync(.reportScan(counts: counts, bytes: bytes, totalAssets: report.totalAssets))
    }

    func applyScanIfNeeded(_ report: JunkReport?) {
        if let report { applyScan(report) }
    }

    private static func makeDaily(_ report: JunkReport) -> DailyBounty? {
        let options = JunkKind.allCases.filter { report.count($0) > 0 }
        guard let kind = options.randomElement() else { return nil }
        let target = min(kind.dailyTarget, report.count(kind))
        return DailyBounty(kind: kind, target: target, progress: 0, reward: kind.dailyReward, day: Date(), paid: false)
    }

    /// Call after photos were actually deleted
    func rewardCleanup(kind: JunkKind, count: Int, bytes: Int64) -> CleanReward {
        var d = data
        let cal = Calendar.current

        let coins = min(60, count * kind.coinsPerItem)
        let firstToday = (d.lastCleanDay.map { !cal.isDateInToday($0) } ?? true) ? 20 : 0

        if let last = d.lastPlayDay, cal.isDateInToday(last) {
            // already played today
        } else if let last = d.lastPlayDay, cal.isDateInYesterday(last) {
            d.streak += 1
        } else {
            d.streak = 1
        }
        d.lastPlayDay = Date()
        d.lastCleanDay = Date()
        let streakBonus = firstToday > 0 ? min(d.streak, 7) * 3 : 0

        var dailyBonus = 0
        if var daily = d.daily, daily.kind == kind, !daily.paid, cal.isDateInToday(daily.day) {
            daily.progress += count
            if daily.progress >= daily.target {
                daily.paid = true
                dailyBonus = daily.reward
            }
            d.daily = daily
        }

        d.itemsTossed += count
        d.bytesFreed += bytes
        d.cleanups += 1
        d.joy = min(100, d.joy + 8)

        var reached: [Milestone] = []
        for m in Milestone.all where !d.milestones.contains(m.id) && d.bytesFreed >= m.bytes {
            d.milestones.insert(m.id)
            reached.append(m)
            if let gift = m.gift { d.wardrobe.insert(gift) }
        }

        let reward = CleanReward(kind: kind, count: count, bytes: bytes, coins: coins,
                                 firstTodayBonus: firstToday, streakBonus: streakBonus,
                                 dailyBonus: dailyBonus, milestones: reached, grewTo: nil)
        d.coins += reward.total
        d.xp += min(60, count * 3) + 10
        let grew = Self.advanceStage(&d)
        data = d
        sync(.claimCleanup(kind: kind.rawValue, count: count, bytes: bytes))

        var result = reward
        result.grewTo = grew
        return result
    }

    /// Photos the player chose to keep stop counting as poop
    func keep(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        data.keptIDs.formUnion(ids)
    }

    /// Photos that turned out not to have a real twin stop showing up in Twin shots
    func markNotTwins(_ ids: [String]) {
        guard !ids.isEmpty else { return }
        data.notTwinIDs.formUnion(ids)
    }

    // MARK: Caring for your pal

    @discardableResult
    func feed(_ item: ShopItem) -> Bool {
        guard item.category == .food || item.category == .toy,
              !data.sleeping,
              let owned = data.inventory[item.id], owned > 0 else { return false }
        var d = data
        d.inventory[item.id] = owned == 1 ? nil : owned - 1
        d.food = min(100, d.food + item.food)
        var joyGain = item.joy
        if item.id == d.look.species.favoriteFood { joyGain += 10 }
        d.joy = min(100, d.joy + joyGain)
        d.xp += 3
        d.hasFed = true
        let grew = Self.advanceStage(&d)
        data = d
        if let grew { justGrew = grew }
        sync(.feed(itemId: item.id))
        return true
    }

    func isFavorite(_ item: ShopItem) -> Bool { item.id == data.look.species.favoriteFood }

    /// Fetch in the yard
    func play() {
        guard !data.sleeping else { return }
        var d = data
        d.joy = min(100, d.joy + 4)
        d.energy = max(0, d.energy - 2)
        d.xp += 1
        data = d
        sync(.play)
    }

    /// Grooming: a quick brush makes your pal happy
    func brush() {
        guard !data.sleeping else { return }
        var d = data
        d.joy = min(100, d.joy + 3)
        d.xp += 1
        data = d
        sync(.brush)
    }

    /// Pats are tiny (+0.5 joy) and frequent, so they stay on the phone and aren't sent to the server
    func pat() {
        guard !data.sleeping else { return }
        data.joy = min(100, data.joy + 0.5)
    }

    func toggleLights() {
        data.sleeping.toggle()
        sync(.toggleLights)
    }

    var medicineCount: Int { data.inventory["medicine"] ?? 0 }

    @discardableResult
    func giveMedicine() -> Bool {
        guard data.sick, medicineCount > 0 else { return false }
        var d = data
        d.inventory["medicine"] = medicineCount == 1 ? nil : medicineCount - 1
        d.sick = false
        d.sickImmuneUntil = Date().addingTimeInterval(24 * 3600)
        d.joy = min(100, d.joy + 5)
        data = d
        sync(.giveMedicine)
        return true
    }

    // MARK: Memory dig (once a day)

    var canDigToday: Bool {
        guard let last = data.lastDigDay else { return true }
        return !Calendar.current.isDateInToday(last)
    }

    func finishDig(foundSomething: Bool, freedBytes: Int64 = 0) {
        var d = data
        d.lastDigDay = Date()
        d.coins += foundSomething ? 5 : 2
        d.joy = min(100, d.joy + 3)
        d.xp += 5
        if freedBytes > 0 {
            d.bytesFreed += freedBytes
            d.itemsTossed += 1
        }
        data = d
        sync(.finishDig(foundSomething: foundSomething, freedBytes: freedBytes))
    }

    // MARK: Shop

    @discardableResult
    func buy(_ item: ShopItem) -> Bool {
        guard data.coins >= item.price else { return false }
        var d = data
        switch item.category {
        case .hat, .neck:
            guard !d.wardrobe.contains(item.id) else { return false }
            d.wardrobe.insert(item.id)
            if item.category == .hat { d.hatID = item.id } else { d.neckID = item.id }
        case .decor:
            d.decorOwned[item.id, default: 0] += 1
        case .food, .toy, .care:
            d.inventory[item.id, default: 0] += 1
        }
        d.coins -= item.price
        data = d
        sync(.buy(itemId: item.id))
        return true
    }

    // MARK: Looks

    func owns(_ item: ShopItem) -> Bool { data.wardrobe.contains(item.id) }
    func isWearing(_ item: ShopItem) -> Bool { data.hatID == item.id || data.neckID == item.id }

    func toggleWear(_ item: ShopItem) {
        guard owns(item) else { return }
        switch item.category {
        case .hat: data.hatID = (data.hatID == item.id) ? nil : item.id
        case .neck: data.neckID = (data.neckID == item.id) ? nil : item.id
        default: return
        }
        sync(.toggleWear(itemId: item.id))
    }

    private func paletteKey(_ p: PetPalette) -> String { "\(data.look.species.rawValue).\(p.id)" }

    func ownsPalette(_ p: PetPalette) -> Bool { p.price == 0 || data.palettesOwned.contains(paletteKey(p)) }

    func isUsingPalette(_ p: PetPalette) -> Bool { data.look.custom == nil && data.look.paletteID == p.id }

    /// Buys the color if needed, then puts it on
    @discardableResult
    func choosePalette(_ p: PetPalette) -> Bool {
        var d = data
        if !ownsPalette(p) {
            guard d.coins >= p.price else { return false }
            d.coins -= p.price
            d.palettesOwned.insert(paletteKey(p))
        }
        d.look.paletteID = p.id
        d.look.custom = nil
        data = d
        sync(.choosePalette(paletteId: p.id))
        return true
    }

    static let photoMatchPrice = 250

    @discardableResult
    func unlockPhotoMatch() -> Bool {
        guard data.coins >= Self.photoMatchPrice else { return false }
        var d = data
        d.coins -= Self.photoMatchPrice
        d.photoMatchUnlocked = true
        data = d
        sync(.unlockPhotoMatch)
        return true
    }

    func applyCustomPalette(_ p: PetPalette) {
        data.look.custom = p
        // Photo Match runs on the phone; only the three colors are sent
        sync(.applyCustomPalette(main: [p.main.r, p.main.g, p.main.b], accent: [p.accent.r, p.accent.g, p.accent.b],
                                 belly: [p.belly.r, p.belly.g, p.belly.b], blaze: p.blaze))
    }

    // MARK: Adopting (first launch)

    func adopt(species: Species, name: String, paletteID: String) {
        var d = data
        d.activeID = UUID()
        d.look = PetLook(species: species, paletteID: paletteID, custom: nil)
        d.petName = name
        d.born = Date()
        d.stage = .baby
        d.xp = 0
        // Peanut always wears his red collar
        if species == .dog && paletteID == "peanut" {
            d.wardrobe.insert("collar")
            d.neckID = "collar"
        }
        data = d
        sync(.adopt(species: species.rawValue, name: name, paletteId: paletteID))
    }

    func finishOnboarding() {
        data.onboarded = true
        sync(.finishOnboarding)
    }

    /// Erases the pal on the phone and, when the backend is on, deletes the cloud save and starts a new account
    func resetGame() {
        data = SaveData()
        Task { await BackendSync.shared.resetAccount() }
    }

    // MARK: Yard building

    func decorOwned(_ id: String) -> Int { data.decorOwned[id] ?? 0 }

    func decorAvailable(_ id: String) -> Int {
        decorOwned(id) - data.placed.filter { $0.itemID == id }.count
    }

    func placeDecor(_ id: String) {
        guard decorAvailable(id) > 0 else { return }
        let decor = PlacedDecor(itemID: id, x: Double.random(in: 0.25...0.75), y: Double.random(in: 0.25...0.6))
        data.placed.append(decor)
        sync(.placeDecor(itemId: id, id: decor.id.uuidString, x: decor.x, y: decor.y))
    }

    func moveDecor(_ id: UUID, x: Double, y: Double) {
        guard let i = data.placed.firstIndex(where: { $0.id == id }) else { return }
        data.placed[i].x = min(max(x, 0.06), 0.94)
        data.placed[i].y = min(max(y, 0.02), 0.95)
        sync(.moveDecor(id: id.uuidString, x: data.placed[i].x, y: data.placed[i].y))
    }

    func storeDecor(_ id: UUID) {
        data.placed.removeAll { $0.id == id }
        sync(.storeDecor(id: id.uuidString))
    }

    // MARK: Widget

    func exportWidgetSnapshot() {
        tick()
        WidgetSnapshot(name: data.petName, look: data.look, stage: data.stage,
                       food: data.food, joy: data.joy, clean: data.clean,
                       sleeping: data.sleeping, sick: data.sick,
                       hatID: data.hatID, neckID: data.neckID,
                       poops: data.poops, streak: data.streak, savedAt: Date()).save()
    }

    private func save() {
        if let raw = try? JSONEncoder().encode(data) {
            UserDefaults.standard.set(raw, forKey: Self.saveKey)
        }
    }

    // MARK: Backend sync (see BackendSync.swift)

    private func sync(_ action: GameAction) {
        BackendSync.shared.send(action)
    }

    /// The on-device save as JSON, sent once when a player first connects so they keep their pal.
    /// Photo IDs (kept photos, checked twins) are removed: they stay on the phone.
    func legacySaveForUpload() -> [String: Any]? {
        guard let raw = try? JSONEncoder().encode(data),
              var json = (try? JSONSerialization.jsonObject(with: raw)) as? [String: Any] else { return nil }
        json.removeValue(forKey: "keptIDs")
        json.removeValue(forKey: "notTwinIDs")
        return json
    }

    /// Replaces the local game with the server's version. Photo IDs stay as they are on the phone.
    func applyRemote(_ r: RemoteState, grewTo: String?) {
        var d = data
        let before = (id: d.activeID, stage: d.stage)
        let active = Self.pal(from: r.pal)

        d.onboarded = r.onboarded
        d.activeID = active.id
        d.petName = active.name
        d.look = active.look
        d.born = active.born
        d.stage = active.stage
        d.xp = active.xp
        d.careMistakes = active.careMistakes
        d.food = active.food
        d.joy = active.joy
        d.energy = active.energy
        d.sick = active.sick
        d.hatID = active.hatID
        d.neckID = active.neckID
        d.otherPals = r.otherPals.map { Self.pal(from: $0) }
        d.tickets = r.tickets

        d.clean = r.clean
        d.sleeping = r.sleeping
        d.sickImmuneUntil = r.sickImmuneUntil.map { Date(timeIntervalSince1970: $0 / 1000) }
        d.lastTick = Date(timeIntervalSince1970: r.lastTick / 1000)

        d.coins = r.coins
        d.inventory = r.inventory
        d.wardrobe = Set(r.wardrobe)
        d.palettesOwned = Set(r.palettesOwned)
        d.photoMatchUnlocked = r.photoMatchUnlocked
        d.decorOwned = r.decorOwned
        d.placed = r.placed.map { PlacedDecor(id: UUID(uuidString: $0.id) ?? UUID(), itemID: $0.itemId, x: $0.x, y: $0.y) }

        d.itemsTossed = r.itemsTossed
        d.bytesFreed = r.bytesFreed
        d.cleanups = r.cleanups
        d.poops = r.poops
        d.streak = r.streak
        d.lastPlayDay = Self.day(r.lastPlayDay)
        d.lastCleanDay = Self.day(r.lastCleanDay)
        d.lastDigDay = Self.day(r.lastDigDay)
        d.daily = r.daily.flatMap { b in
            JunkKind(rawValue: b.kind).map {
                DailyBounty(kind: $0, target: b.target, progress: b.progress, reward: b.reward, day: Self.day(b.day) ?? Date(), paid: b.paid)
            }
        }
        d.milestones = Set(r.milestones)
        d.hasFed = r.hasFed
        data = d

        // Celebrate growing up only if the server's pal grew past what the phone already showed
        if let grew = grewTo.flatMap(LifeStage.init(rawValue:)), before.id == d.activeID, before.stage != grew {
            justGrew = grew
        }
    }

    private static func pal(from p: RemotePal) -> Pal {
        Pal(id: UUID(uuidString: p.id) ?? UUID(), name: p.name, look: look(from: p.look),
            born: Date(timeIntervalSince1970: p.born / 1000), stage: LifeStage(rawValue: p.stage) ?? .baby,
            xp: p.xp, careMistakes: p.careMistakes, food: p.food, joy: p.joy, energy: p.energy, sick: p.sick,
            hatID: p.hatId, neckID: p.neckId)
    }

    private static func look(from l: RemoteLook) -> PetLook {
        PetLook(species: Species(rawValue: l.species) ?? .dog, paletteID: l.paletteId, custom: l.custom.map { palette(from: $0) })
    }

    private static func palette(from p: RemotePalette) -> PetPalette {
        func rgb(_ v: [Double]) -> RGB { v.count == 3 ? RGB(v[0], v[1], v[2]) : RGB(0.5, 0.5, 0.5) }
        return PetPalette(id: p.id, name: p.name, main: rgb(p.main), accent: rgb(p.accent), belly: rgb(p.belly),
                          blaze: p.blaze, price: p.price)
    }

    /// The server's local-day strings ("2026-11-02") as a date at noon on that day
    private static func day(_ s: String?) -> Date? {
        guard let parts = s?.split(separator: "-").compactMap({ Int($0) }), parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: 12))
    }
}
