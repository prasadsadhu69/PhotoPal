import Combine
import Photos
import UIKit

/// What your pal sniffed out in the camera roll
struct JunkReport {
    var screenshots: [String] = []          // photo IDs, oldest first
    var twinGroups: [[String]] = []         // photos taken close together (checked for real look-alikes when scooping)
    var giants: [String] = []               // biggest videos first
    var oopsies: [String] = []              // dark, blurry or pocket shots
    var oopsReasons: [String: String] = [:]
    var protected: Set<String> = []         // favorites and album photos: never pre-selected
    var bytes: [JunkKind: Int64] = [:]
    var totalAssets = 0

    func count(_ kind: JunkKind) -> Int {
        switch kind {
        case .screenshots: return screenshots.count
        case .twins:
            return twinGroups.reduce(0) { total, group in
                let keepers = max(1, group.filter { protected.contains($0) }.count)
                return total + max(0, group.count - keepers)
            }
        case .giants: return giants.count
        case .oopsies: return oopsies.count
        }
    }

    func bytesFor(_ kind: JunkKind) -> Int64 { bytes[kind] ?? 0 }

    var junkCount: Int { JunkKind.allCases.reduce(0) { $0 + count($1) } }
    var junkBytes: Int64 { bytes.values.reduce(0, +) }

    /// 0 to 100, like a credit score for your camera roll
    var score: Int {
        guard totalAssets > 0 else { return 100 }
        let ratio = Double(junkCount) / Double(totalAssets)
        let value = 100 * (1 - min(1, ratio / 0.35))
        return max(0, min(100, Int(value.rounded())))
    }

    /// The pile worth scooping first (most space)
    var biggest: JunkKind? {
        JunkKind.allCases
            .filter { count($0) > 0 }
            .max { bytesFor($0) < bytesFor($1) }
    }
}

/// Talks to the iPhone camera roll: scanning for poop, thumbnails, and deleting
@MainActor
final class PhotoLibrary: ObservableObject {
    @Published private(set) var status: PHAuthorizationStatus
    @Published private(set) var report: JunkReport?
    @Published private(set) var scanning = false

    private var lastScan: Date?
    private let manager = PHCachingImageManager()

    init() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    var hasAccess: Bool { status == .authorized || status == .limited }

    func requestAccess() async {
        status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    // MARK: Sniffing for poop

    /// Scans the camera roll and updates your pal's Clean meter
    func refresh(_ game: GameState, force: Bool = false) async {
        if let report = await scan(kept: game.keptIDs, notTwins: game.notTwinIDs, force: force) {
            game.applyScan(report)
        }
    }

    @discardableResult
    func scan(kept: Set<String>, notTwins: Set<String>, force: Bool = false) async -> JunkReport? {
        guard hasAccess, !scanning else { return report }
        if !force, let lastScan, let report, Date().timeIntervalSince(lastScan) < 300 {
            return report
        }
        scanning = true

        // Favorites and album photos are never treated as poop
        let protected = await Task.detached(priority: .userInitiated) { PhotoSmarts.protectedIDs() }.value
        let skip = kept.union(protected)
        let twinSkip = kept.union(notTwins)

        let shots = await Task.detached(priority: .userInitiated) { PhotoLibrary.screenshotIDs(skip: skip) }.value
        let twins = await Task.detached(priority: .userInitiated) { PhotoLibrary.twinIDs(skip: twinSkip) }.value
            .filter { group in group.contains { !protected.contains($0) } }
        let giantResult = await Task.detached(priority: .userInitiated) { PhotoLibrary.giantVideos(skip: skip) }.value
        let total = await Task.detached(priority: .userInitiated) { PhotoLibrary.totalCount() }.value

        let twinMembers = Set(twins.flatMap { $0 })
        let oopsSkip = skip.union(twinMembers)
        let oops = await Task.detached(priority: .utility) { PhotoSmarts.oopsies(skip: oopsSkip) }.value
        let oopsIDs = oops.map { $0.0 }

        let extras = twins.flatMap { Array($0.dropFirst()) }
        let shotBytes = await Task.detached(priority: .utility) { PhotoLibrary.estimateBytes(ids: shots, sample: 150) }.value
        let twinBytes = await Task.detached(priority: .utility) { PhotoLibrary.estimateBytes(ids: extras, sample: 150) }.value
        let oopsBytes = await Task.detached(priority: .utility) { PhotoLibrary.estimateBytes(ids: oopsIDs, sample: 150) }.value

        var r = JunkReport()
        r.screenshots = shots
        r.twinGroups = twins
        r.giants = giantResult.ids
        r.oopsies = oopsIDs
        r.oopsReasons = Dictionary(oops, uniquingKeysWith: { first, _ in first })
        r.protected = protected
        r.totalAssets = total
        r.bytes = [.screenshots: shotBytes, .twins: twinBytes, .giants: giantResult.bytes, .oopsies: oopsBytes]
        report = r
        lastScan = Date()
        scanning = false
        return r
    }

    /// Takes scooped or kept photos out of the report right away, so the poop disappears instantly
    func remove(_ ids: Set<String>, deletedCount: Int) {
        guard var r = report else { return }
        let before = JunkKind.allCases.map { r.count($0) }
        r.screenshots.removeAll { ids.contains($0) }
        r.giants.removeAll { ids.contains($0) }
        r.oopsies.removeAll { ids.contains($0) }
        r.twinGroups = r.twinGroups
            .map { group in group.filter { !ids.contains($0) } }
            .filter { $0.count >= 2 }
        for (i, kind) in JunkKind.allCases.enumerated() where before[i] > 0 {
            let share = Double(r.count(kind)) / Double(before[i])
            r.bytes[kind] = Int64(Double(r.bytesFor(kind)) * share)
        }
        r.totalAssets = max(0, r.totalAssets - deletedCount)
        report = r
    }

    /// Screenshots, skipping ones from the last 7 days (you might still need those)
    nonisolated static func screenshotIDs(skip: Set<String>) -> [String] {
        let albums = PHAssetCollection.fetchAssetCollections(with: .smartAlbum, subtype: .smartAlbumScreenshots, options: nil)
        guard let album = albums.firstObject else { return [] }
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: true)]
        var ids: [String] = []
        PHAsset.fetchAssets(in: album, options: options).enumerateObjects { asset, _, _ in
            guard !skip.contains(asset.localIdentifier) else { return }
            if let created = asset.creationDate, created > cutoff { return }
            ids.append(asset.localIdentifier)
        }
        return ids
    }

    /// Videos over 50 MB, biggest first, using real file sizes
    nonisolated static func giantVideos(skip: Set<String>, minBytes: Int64 = 50_000_000) -> (ids: [String], bytes: Int64) {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.video.rawValue)
        var sized: [(String, Int64)] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
            guard !skip.contains(asset.localIdentifier) else { return }
            let size = PhotoLibrary.fileSize(of: asset)
            if size >= minBytes { sized.append((asset.localIdentifier, size)) }
        }
        sized.sort { $0.1 > $1.1 }
        return (sized.map { $0.0 }, sized.reduce(Int64(0)) { $0 + $1.1 })
    }

    nonisolated static func totalCount() -> Int {
        PHAsset.fetchAssets(with: nil).count
    }

    /// Photos taken within 10 seconds of each other are possible twins (checked properly when scooping)
    nonisolated static func twinIDs(skip: Set<String>, maxGroups: Int = 200) -> [[String]] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        let result = PHAsset.fetchAssets(with: options)

        var groups: [[String]] = []
        var current: [String] = []
        var lastDate: Date?
        result.enumerateObjects { asset, _, stop in
            guard let date = asset.creationDate,
                  !skip.contains(asset.localIdentifier),
                  !asset.mediaSubtypes.contains(.photoScreenshot) else { return }
            if let last = lastDate, abs(last.timeIntervalSince(date)) <= 10 {
                current.append(asset.localIdentifier)
            } else {
                if current.count >= 2 { groups.append(Array(current.prefix(6))) }
                current = [asset.localIdentifier]
            }
            lastDate = date
            if groups.count >= maxGroups { stop.pointee = true }
        }
        if current.count >= 2 && groups.count < maxGroups { groups.append(Array(current.prefix(6))) }
        return groups
    }

    /// Adds up file sizes for a sample, then scales up to the full list
    nonisolated static func estimateBytes(ids: [String], sample: Int) -> Int64 {
        guard !ids.isEmpty else { return 0 }
        let picked = Array(ids.prefix(sample))
        var total: Int64 = 0
        var counted = 0
        PHAsset.fetchAssets(withLocalIdentifiers: picked, options: nil).enumerateObjects { asset, _, _ in
            total += PhotoLibrary.fileSize(of: asset)
            counted += 1
        }
        guard counted > 0 else { return 0 }
        return Int64(Double(total) / Double(counted) * Double(ids.count))
    }

    /// File size for each photo ID
    nonisolated static func sizes(for ids: [String]) -> [String: Int64] {
        guard !ids.isEmpty else { return [:] }
        var result: [String: Int64] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            result[asset.localIdentifier] = PhotoLibrary.fileSize(of: asset)
        }
        return result
    }

    nonisolated static func fileSize(of asset: PHAsset) -> Int64 {
        PHAssetResource.assetResources(for: asset)
            .compactMap { ($0.value(forKey: "fileSize") as? CLong).map(Int64.init) }
            .reduce(0, +)
    }

    // MARK: Looking things up

    /// Assets for IDs, in the same order
    func assets(for ids: [String]) -> [PHAsset] {
        guard !ids.isEmpty else { return [] }
        var byID: [String: PHAsset] = [:]
        PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil).enumerateObjects { asset, _, _ in
            byID[asset.localIdentifier] = asset
        }
        return ids.compactMap { byID[$0] }
    }

    func image(for asset: PHAsset, size: CGSize) async -> UIImage? {
        await withCheckedContinuation { continuation in
            let opts = PHImageRequestOptions()
            opts.deliveryMode = .highQualityFormat   // guarantees exactly one callback
            opts.isNetworkAccessAllowed = true       // pulls from iCloud if needed
            opts.resizeMode = .fast
            manager.requestImage(for: asset, targetSize: size, contentMode: .aspectFill, options: opts) { image, _ in
                continuation.resume(returning: image)
            }
        }
    }

    // MARK: Scooping (deleting)

    /// Deletes for real. iOS shows its own "Delete N items?" prompt,
    /// and everything sits in Recently Deleted for 30 days.
    func delete(_ assets: [PHAsset]) async throws -> Int64 {
        let bytes = assets.reduce(Int64(0)) { $0 + Self.fileSize(of: $1) }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.deleteAssets(assets as NSArray)
        }
        return bytes
    }

    // MARK: Peanut Vault (a real album in Photos; anything in it is never flagged)

    static let vaultName = "Peanut Vault"

    @Published private(set) var vaultIDs: [String] = []

    nonisolated static func findVault() -> PHAssetCollection? {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "title = %@", "Peanut Vault")
        return PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: options).firstObject
    }

    func loadVault() {
        guard hasAccess, let album = Self.findVault() else {
            vaultIDs = []
            return
        }
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        var ids: [String] = []
        PHAsset.fetchAssets(in: album, options: options).enumerateObjects { asset, _, _ in
            ids.append(asset.localIdentifier)
        }
        vaultIDs = ids
    }

    /// Puts photos in the Peanut Vault album (creating it the first time)
    func addToVault(_ ids: [String]) async {
        guard hasAccess, !ids.isEmpty else { return }
        if Self.findVault() == nil {
            let title = Self.vaultName
            try? await PHPhotoLibrary.shared().performChanges {
                _ = PHAssetCollectionChangeRequest.creationRequestForAssetCollection(withTitle: title)
            }
        }
        guard let album = Self.findVault() else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        try? await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest(for: album)?.addAssets(assets)
        }
        remove(Set(ids), deletedCount: 0)
        loadVault()
    }

    func removeFromVault(_ ids: [String]) async {
        guard let album = Self.findVault(), !ids.isEmpty else { return }
        let assets = PHAsset.fetchAssets(withLocalIdentifiers: ids, options: nil)
        try? await PHPhotoLibrary.shared().performChanges {
            PHAssetCollectionChangeRequest(for: album)?.removeAssets(assets)
        }
        loadVault()
    }

    /// Your favorites, newest first, for the photo book
    func favoriteIDs(limit: Int = 60) -> [String] {
        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "favorite == YES")
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        var ids: [String] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
            ids.append(asset.localIdentifier)
        }
        return ids
    }

    // MARK: Memory dig

    /// Photos from this calendar day in past years. Widens to nearby days if that day is empty.
    func memories(on date: Date = Date()) -> [PHAsset] {
        for window in [0, 3, 10] {
            let found = memories(on: date, windowDays: window)
            if !found.isEmpty { return found }
        }
        return []
    }

    private func memories(on date: Date, windowDays: Int) -> [PHAsset] {
        let cal = Calendar.current
        var found: [PHAsset] = []
        for yearsAgo in 1...15 {
            guard let day = cal.date(byAdding: .year, value: -yearsAgo, to: date),
                  let start = cal.date(byAdding: .day, value: -windowDays, to: cal.startOfDay(for: day)),
                  let end = cal.date(byAdding: .day, value: windowDays + 1, to: cal.startOfDay(for: day)) else { continue }
            let options = PHFetchOptions()
            options.predicate = NSPredicate(format: "mediaType == %d AND creationDate >= %@ AND creationDate < %@",
                                            PHAssetMediaType.image.rawValue, start as NSDate, end as NSDate)
            options.fetchLimit = 30
            PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, _ in
                if !asset.mediaSubtypes.contains(.photoScreenshot) { found.append(asset) }
            }
        }
        return found
    }

    func setFavorite(_ asset: PHAsset) async {
        try? await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest(for: asset).isFavorite = true
        }
    }
}
