// PhotoPal backend client for iOS.
//
// Setup in Xcode:
//   1. File > Add Package Dependencies > https://github.com/firebase/firebase-ios-sdk
//      Add FirebaseAuth, FirebaseFunctions, FirebaseMessaging, FirebaseCrashlytics, FirebaseAnalytics.
//   2. Add GoogleService-Info.plist from the Firebase console to the PhotoPal target.
//   3. Call FirebaseApp.configure() in PhotoPalApp.init().
//   4. Drag this file into the PhotoPal folder.
//
// The server owns coins, XP, needs and time. This client only sends taps and
// photo *counts*; photo IDs and images never leave the phone.

import FirebaseAuth
import FirebaseFunctions
import Foundation

// MARK: - Shapes returned by the API (mirror backend/functions/src/rules/types.ts)

struct RemoteLook: Codable, Hashable {
    var species: String
    var paletteId: String
    var custom: RemotePalette?
}

struct RemotePalette: Codable, Hashable {
    var id: String
    var name: String
    var main: [Double]
    var accent: [Double]
    var belly: [Double]
    var blaze: Bool
    var price: Int
}

struct RemotePal: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var look: RemoteLook
    var born: Double
    var stage: String
    var xp: Int
    var careMistakes: Int
    var food: Double
    var joy: Double
    var energy: Double
    var sick: Bool
    var hatId: String?
    var neckId: String?
}

struct RemoteDaily: Codable, Hashable {
    var kind: String
    var target: Int
    var progress: Int
    var reward: Int
    var day: String
    var paid: Bool
}

struct RemoteDecor: Codable, Identifiable, Hashable {
    var id: String
    var itemId: String
    var x: Double
    var y: Double
}

struct RemoteState: Codable, Hashable {
    var timezone: String
    var onboarded: Bool
    var pal: RemotePal
    var otherPals: [RemotePal]
    var tickets: Int
    var clean: Double
    var sleeping: Bool
    var coins: Int
    var inventory: [String: Int]
    var wardrobe: [String]
    var palettesOwned: [String]
    var photoMatchUnlocked: Bool
    var decorOwned: [String: Int]
    var placed: [RemoteDecor]
    var itemsTossed: Int
    var bytesFreed: Int64
    var cleanups: Int
    var poops: Int
    var streak: Int
    var daily: RemoteDaily?
    var milestones: [String]
    var hasFed: Bool
}

struct RemoteDerived: Codable, Hashable {
    struct Condition: Codable, Hashable { var sleeping: Bool; var sick: Bool; var dirty: Bool }
    var mood: String
    var level: Int
    var levelProgress: Double
    var nextStage: String?
    var xpToNextStage: Int
    var growthProgress: Double
    var cozy: Int
    var condition: Condition
    var buildUnlocked: Bool
    var canDigToday: Bool
    var ageDays: Int
    var speciesToAdopt: [String]
    var today: String
}

struct RemoteMilestone: Codable, Hashable {
    var id: String
    var title: String
    var bytes: Int64
    var coins: Int
    var gift: String?
}

struct RemoteReward: Codable, Hashable {
    var kind: String
    var count: Int
    var bytes: Int64
    var coins: Int
    var firstTodayBonus: Int
    var streakBonus: Int
    var dailyBonus: Int
    var milestones: [RemoteMilestone]
    var total: Int
}

struct RemoteEvents: Codable, Hashable {
    var grewTo: String?
    var coinsDelta: Int?
    var reward: RemoteReward?
}

struct GameResponse: Codable {
    var state: RemoteState
    var derived: RemoteDerived
    var rev: Int
    var catalogVersion: Int
    var events: RemoteEvents
    var isNew: Bool?
    var canImportLegacySave: Bool?
}

// MARK: - Actions

/// Every tap the app can send. Mirrors the action table in backend/docs/API.md.
enum GameAction {
    case adopt(species: String, name: String, paletteId: String)
    case finishOnboarding
    case rename(String)
    case feed(itemId: String)
    case play, brush, pat, toggleLights, giveMedicine
    case finishDig(foundSomething: Bool, freedBytes: Int64)
    case buy(itemId: String)
    case toggleWear(itemId: String)
    case choosePalette(paletteId: String)
    case unlockPhotoMatch
    case applyCustomPalette(main: [Double], accent: [Double], belly: [Double], blaze: Bool)
    case switchPal(palId: String)
    case adoptPal(species: String, name: String, paletteId: String)
    case placeDecor(itemId: String)
    case moveDecor(id: String, x: Double, y: Double)
    case storeDecor(id: String)
    /// Counts and bytes per junk kind ("screenshots", "twins", "giants", "oopsies"). Never photo IDs.
    case reportScan(counts: [String: Int], bytes: [String: Int64], totalAssets: Int)
    case claimCleanup(kind: String, count: Int, bytes: Int64)

    var payload: [String: Any] {
        func a(_ name: String, _ params: [String: Any] = [:]) -> [String: Any] { ["action": name, "params": params] }
        switch self {
        case let .adopt(s, n, p): return a("adopt", ["species": s, "name": n, "paletteId": p])
        case .finishOnboarding: return a("finishOnboarding")
        case let .rename(n): return a("rename", ["name": n])
        case let .feed(i): return a("feed", ["itemId": i])
        case .play: return a("play")
        case .brush: return a("brush")
        case .pat: return a("pat")
        case .toggleLights: return a("toggleLights")
        case .giveMedicine: return a("giveMedicine")
        case let .finishDig(f, b): return a("finishDig", ["foundSomething": f, "freedBytes": b])
        case let .buy(i): return a("buy", ["itemId": i])
        case let .toggleWear(i): return a("toggleWear", ["itemId": i])
        case let .choosePalette(p): return a("choosePalette", ["paletteId": p])
        case .unlockPhotoMatch: return a("unlockPhotoMatch")
        case let .applyCustomPalette(m, ac, b, bl): return a("applyCustomPalette", ["main": m, "accent": ac, "belly": b, "blaze": bl])
        case let .switchPal(id): return a("switchPal", ["palId": id])
        case let .adoptPal(s, n, p): return a("adoptPal", ["species": s, "name": n, "paletteId": p])
        case let .placeDecor(i): return a("placeDecor", ["itemId": i])
        case let .moveDecor(id, x, y): return a("moveDecor", ["id": id, "x": x, "y": y])
        case let .storeDecor(id): return a("storeDecor", ["id": id])
        case let .reportScan(c, b, t): return a("reportScan", ["counts": c, "bytes": b, "totalAssets": t])
        case let .claimCleanup(k, c, b): return a("claimCleanup", ["kind": k, "count": c, "bytes": b])
        }
    }
}

// MARK: - Client

enum BackendError: LocalizedError {
    case server(code: FunctionsErrorCode, message: String)
    case badResponse

    var errorDescription: String? {
        switch self {
        case let .server(_, message): return message
        case .badResponse: return "Unexpected response from the server"
        }
    }
}

@MainActor
final class PhotoPalBackend: ObservableObject {
    @Published private(set) var game: GameResponse?

    private let functions = Functions.functions(region: "us-central1")
    private let cacheURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("photopal-game.json")

    init() {
        // Show the last known state instantly, even offline
        if let data = try? Data(contentsOf: cacheURL) {
            game = try? JSONDecoder().decode(GameResponse.self, from: data)
        }
    }

    /// Signs in anonymously if needed, then loads (or creates) the player.
    func start() async throws {
        if Auth.auth().currentUser == nil {
            _ = try await Auth.auth().signInAnonymously()
        }
        let response = try await call("bootstrap", ["timezone": TimeZone.current.identifier])
        if response.canImportLegacySave == true, let legacy = Self.legacySave() {
            apply(try await call("importLegacySave", ["save": legacy, "timezone": TimeZone.current.identifier]))
        } else {
            apply(response)
        }
    }

    @discardableResult
    func send(_ action: GameAction) async throws -> RemoteEvents {
        let response = try await call("act", action.payload)
        apply(response)
        return response.events
    }

    func registerPushToken(_ token: String, reminders: Bool = true) async {
        _ = try? await functions.httpsCallable("registerDevice").call(["token": token, "platform": "ios", "reminders": reminders])
    }

    func deleteAccount() async throws {
        _ = try await functions.httpsCallable("deleteAccount").call()
        try? FileManager.default.removeItem(at: cacheURL)
        try? Auth.auth().signOut()
        game = nil
    }

    // MARK: Internals

    private func call(_ name: String, _ data: [String: Any]) async throws -> GameResponse {
        do {
            let result = try await functions.httpsCallable(name).call(data)
            let json = try JSONSerialization.data(withJSONObject: result.data)
            return try JSONDecoder().decode(GameResponse.self, from: json)
        } catch let error as NSError where error.domain == FunctionsErrorDomain {
            let code = FunctionsErrorCode(rawValue: error.code) ?? .internal
            throw BackendError.server(code: code, message: error.localizedDescription)
        } catch is DecodingError {
            throw BackendError.badResponse
        }
    }

    private func apply(_ response: GameResponse) {
        game = response
        if let data = try? JSONEncoder().encode(response) {
            try? FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cacheURL, options: .atomic)
        }
    }

    /// The pre-backend save, sent once so existing players keep their pal.
    /// keptIDs and notTwinIDs are stripped here; they stay on the phone.
    private static func legacySave() -> [String: Any]? {
        guard let raw = UserDefaults.standard.data(forKey: "photopal.save.v2"),
              var json = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { return nil }
        json.removeValue(forKey: "keptIDs")
        json.removeValue(forKey: "notTwinIDs")
        return json
    }
}
