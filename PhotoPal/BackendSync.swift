import Foundation
#if canImport(FirebaseAuth) && canImport(FirebaseFunctions)
import FirebaseAuth
import FirebaseCore
import FirebaseFunctions
#endif

// Keeps the game in sync with the PhotoPal backend (backend/docs/API.md).
//
// How it works: every tap still changes GameState on the phone right away, so the app
// feels instant and works offline. The same action is queued here and sent to the
// server in order. The server is the source of truth: when the queue is empty, its
// answer replaces the local state. Coins, XP and time are decided on the server.
//
// Privacy: only taps and photo *counts* are sent. Photo IDs, thumbnails and images
// never leave the phone.
//
// Until the Firebase package and GoogleService-Info.plist are added in Xcode,
// isEnabled stays false and the app runs fully offline, exactly as before.

/// One player action, as the backend's `act` function expects it.
enum GameAction {
    case adopt(species: String, name: String, paletteId: String)
    case finishOnboarding
    case rename(String)
    case feed(itemId: String)
    case play, brush, toggleLights, giveMedicine
    case finishDig(foundSomething: Bool, freedBytes: Int64)
    case buy(itemId: String)
    case toggleWear(itemId: String)
    case choosePalette(paletteId: String)
    case unlockPhotoMatch
    case applyCustomPalette(main: [Double], accent: [Double], belly: [Double], blaze: Bool)
    case switchPal(palId: String)
    case adoptPal(species: String, name: String, paletteId: String)
    case placeDecor(itemId: String, id: String, x: Double, y: Double)
    case moveDecor(id: String, x: Double, y: Double)
    case storeDecor(id: String)
    case reportScan(counts: [String: Int], bytes: [String: Int64], totalAssets: Int)
    case claimCleanup(kind: String, count: Int, bytes: Int64)

    var payload: [String: Any] {
        func a(_ name: String, _ params: [String: Any] = [:]) -> [String: Any] { ["action": name, "params": params] }
        switch self {
        case let .adopt(species, name, paletteId): return a("adopt", ["species": species, "name": name, "paletteId": paletteId])
        case .finishOnboarding: return a("finishOnboarding")
        case let .rename(name): return a("rename", ["name": name])
        case let .feed(itemId): return a("feed", ["itemId": itemId])
        case .play: return a("play")
        case .brush: return a("brush")
        case .toggleLights: return a("toggleLights")
        case .giveMedicine: return a("giveMedicine")
        case let .finishDig(found, freed): return a("finishDig", ["foundSomething": found, "freedBytes": freed])
        case let .buy(itemId): return a("buy", ["itemId": itemId])
        case let .toggleWear(itemId): return a("toggleWear", ["itemId": itemId])
        case let .choosePalette(paletteId): return a("choosePalette", ["paletteId": paletteId])
        case .unlockPhotoMatch: return a("unlockPhotoMatch")
        case let .applyCustomPalette(main, accent, belly, blaze):
            return a("applyCustomPalette", ["main": main, "accent": accent, "belly": belly, "blaze": blaze])
        case let .switchPal(palId): return a("switchPal", ["palId": palId])
        case let .adoptPal(species, name, paletteId): return a("adoptPal", ["species": species, "name": name, "paletteId": paletteId])
        case let .placeDecor(itemId, id, x, y): return a("placeDecor", ["itemId": itemId, "id": id, "x": x, "y": y])
        case let .moveDecor(id, x, y): return a("moveDecor", ["id": id, "x": x, "y": y])
        case let .storeDecor(id): return a("storeDecor", ["id": id])
        case let .reportScan(counts, bytes, totalAssets):
            return a("reportScan", ["counts": counts, "bytes": bytes, "totalAssets": totalAssets])
        case let .claimCleanup(kind, count, bytes): return a("claimCleanup", ["kind": kind, "count": count, "bytes": bytes])
        }
    }
}

// MARK: - What the server sends back (fields from backend/functions/src/rules/types.ts)

struct RemotePalette: Codable {
    var id: String
    var name: String
    var main: [Double]
    var accent: [Double]
    var belly: [Double]
    var blaze: Bool
    var price: Int
}

struct RemoteLook: Codable {
    var species: String
    var paletteId: String
    var custom: RemotePalette?
}

struct RemotePal: Codable {
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

struct RemoteDaily: Codable {
    var kind: String
    var target: Int
    var progress: Int
    var reward: Int
    var day: String
    var paid: Bool
}

struct RemoteDecor: Codable {
    var id: String
    var itemId: String
    var x: Double
    var y: Double
}

struct RemoteState: Codable {
    var onboarded: Bool
    var pal: RemotePal
    var otherPals: [RemotePal]
    var tickets: Int
    var clean: Double
    var sleeping: Bool
    var sickImmuneUntil: Double?
    var lastTick: Double
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
    var lastPlayDay: String?
    var lastCleanDay: String?
    var lastDigDay: String?
    var daily: RemoteDaily?
    var milestones: [String]
    var hasFed: Bool
}

struct RemoteEvents: Codable {
    var grewTo: String?
    var coinsDelta: Int?
}

struct GameResponse: Codable {
    var state: RemoteState
    var rev: Int
    var events: RemoteEvents
    var isNew: Bool?
    var canImportLegacySave: Bool?
}

enum BackendError: LocalizedError {
    case disabled
    /// `retry` means the action wasn't rejected, the server just couldn't be reached
    case server(retry: Bool, message: String)

    var errorDescription: String? {
        switch self {
        case .disabled: return "The backend isn't set up in this build"
        case let .server(_, message): return message
        }
    }

    var shouldRetry: Bool {
        if case let .server(retry, _) = self { return retry }
        return false
    }
}

// MARK: - Sync

@MainActor
final class BackendSync {
    static let shared = BackendSync()

    /// True once Firebase is configured. False means the app runs offline only.
    private(set) var isEnabled = false

    private weak var game: GameState?
    private var queue: [GameAction] = []
    private var connected = false
    private var connecting = false
    private var flushing = false
    private let maxQueued = 500
    #if canImport(FirebaseAuth) && canImport(FirebaseFunctions)
    private lazy var functions = Functions.functions(region: "us-central1")
    #endif

    /// Call once at launch. Does nothing until GoogleService-Info.plist is in the app.
    static func configure() {
        #if canImport(FirebaseAuth) && canImport(FirebaseFunctions)
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        // Configure once. (Don't call FirebaseApp.app() first: it logs a "not yet configured" warning.)
        guard !shared.isEnabled else { return }
        FirebaseApp.configure()
        shared.isEnabled = true
        #if DEBUG
        // Free local testing: run `firebase emulators:start` in backend/, then set the
        // PHOTOPAL_EMULATOR_HOST environment variable in the Xcode scheme (127.0.0.1 for the Simulator).
        if let host = ProcessInfo.processInfo.environment["PHOTOPAL_EMULATOR_HOST"], !host.isEmpty {
            Auth.auth().useEmulator(withHost: host, port: 9099)
            shared.functions.useEmulator(withHost: host, port: 5001)
            print("[PhotoPal backend] Using local emulators at \(host)")
        }
        #endif
        #endif
    }

    /// Signs in (anonymously the first time), loads the player and sends anything queued.
    /// Safe to call on every launch and every return to the foreground.
    func connect(_ game: GameState) async {
        self.game = game
        guard isEnabled, !connecting else { return }
        connecting = true
        defer { connecting = false }
        do {
            try await signInIfNeeded()
            let timezone = TimeZone.current.identifier
            var response = try await call("bootstrap", ["timezone": timezone])
            // First time on the backend: bring the existing pal along
            if response.canImportLegacySave == true, game.onboarded, let save = game.legacySaveForUpload() {
                response = try await call("importLegacySave", ["save": save, "timezone": timezone])
            }
            connected = true
            if queue.isEmpty {
                game.applyRemote(response.state, grewTo: response.events.grewTo)
            }
            await flush()
        } catch {
            connected = false
            report(error)
        }
    }

    /// Queues an action for the server. GameState has already applied it locally.
    func send(_ action: GameAction) {
        guard isEnabled else { return }
        queue.append(action)
        if queue.count > maxQueued { queue.removeFirst(queue.count - maxQueued) }
        Task {
            if connected {
                await flush()
            } else if let game {
                await connect(game)
            }
        }
    }

    /// "Erase and start over": deletes the cloud save and starts a fresh account.
    func resetAccount() async {
        guard isEnabled else { return }
        queue.removeAll()
        connected = false
        #if canImport(FirebaseAuth) && canImport(FirebaseFunctions)
        _ = try? await functions.httpsCallable("deleteAccount").call()
        try? Auth.auth().signOut()
        #endif
        if let game { await connect(game) }
    }

    // MARK: Internals

    private func flush() async {
        guard connected, !flushing, let game else { return }
        flushing = true
        defer { flushing = false }
        var resync = false
        while let action = queue.first {
            do {
                let response = try await call("act", action.payload)
                if !queue.isEmpty { queue.removeFirst() }
                if queue.isEmpty && !resync {
                    game.applyRemote(response.state, grewTo: response.events.grewTo)
                }
            } catch let error as BackendError where error.shouldRetry {
                // Offline or the server is busy: keep the queue and try again later
                connected = false
                report(error)
                return
            } catch {
                // The server said no (for example not enough coins). Drop it and take the server's state.
                if !queue.isEmpty { queue.removeFirst() }
                resync = true
                report(error)
            }
        }
        if resync, let response = try? await call("bootstrap", ["timezone": TimeZone.current.identifier]), queue.isEmpty {
            game.applyRemote(response.state, grewTo: nil)
        }
    }

    private func signInIfNeeded() async throws {
        #if canImport(FirebaseAuth) && canImport(FirebaseFunctions)
        if Auth.auth().currentUser == nil {
            _ = try await Auth.auth().signInAnonymously()
        }
        #else
        throw BackendError.disabled
        #endif
    }

    private func call(_ name: String, _ data: [String: Any]) async throws -> GameResponse {
        #if canImport(FirebaseAuth) && canImport(FirebaseFunctions)
        let result: HTTPSCallableResult
        do {
            result = try await functions.httpsCallable(name).call(data)
        } catch let error as NSError where error.domain == FunctionsErrorDomain {
            let code = FunctionsErrorCode(rawValue: error.code)
            let retry = code == .unavailable || code == .deadlineExceeded || code == .internal || code == .unauthenticated
            throw BackendError.server(retry: retry, message: error.localizedDescription)
        } catch {
            throw BackendError.server(retry: true, message: error.localizedDescription)
        }
        let json = try JSONSerialization.data(withJSONObject: result.data)
        return try JSONDecoder().decode(GameResponse.self, from: json)
        #else
        throw BackendError.disabled
        #endif
    }

    private func report(_ error: Error) {
        #if DEBUG
        print("[PhotoPal backend]", error.localizedDescription)
        #endif
    }
}
