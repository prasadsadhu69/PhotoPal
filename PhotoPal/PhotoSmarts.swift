import CoreGraphics
import Foundation
import Photos
import UIKit
import Vision

/// The "smart" part of sniffing: on-device checks that decide what's probably junk
/// and what you'd want to keep. Everything here runs on the phone; nothing is uploaded.
enum PhotoSmarts {

    // MARK: Never touch these

    /// Favorites and anything in an album you made
    nonisolated static func protectedIDs() -> Set<String> {
        var ids = Set<String>()
        let favorites = PHFetchOptions()
        favorites.predicate = NSPredicate(format: "favorite == YES")
        PHAsset.fetchAssets(with: favorites).enumerateObjects { asset, _, _ in
            ids.insert(asset.localIdentifier)
        }
        let albums = PHAssetCollection.fetchAssetCollections(with: .album, subtype: .albumRegular, options: nil)
        albums.enumerateObjects { album, _, _ in
            PHAsset.fetchAssets(in: album, options: nil).enumerateObjects { asset, _, _ in
                ids.insert(asset.localIdentifier)
            }
        }
        return ids
    }

    // MARK: Important screenshots (tickets, receipts, codes)

    /// Reads the text in each screenshot and returns the ones that look important, with a reason
    nonisolated static func importantReasons(ids: [String]) -> [String: String] {
        let keywords: [(String, String)] = [
            ("boarding", "Looks like a boarding pass"),
            ("flight", "Looks like travel info"),
            ("itinerary", "Looks like travel info"),
            ("check-in", "Looks like travel info"),
            ("reservation", "Looks like a reservation"),
            ("booking", "Looks like a booking"),
            ("confirmation", "Looks like a confirmation"),
            ("ticket", "Looks like a ticket"),
            ("receipt", "Looks like a receipt"),
            ("subtotal", "Looks like a receipt"),
            ("order total", "Looks like a receipt"),
            ("order #", "Looks like an order"),
            ("order number", "Looks like an order"),
            ("invoice", "Looks like an invoice"),
            ("tracking", "Has a tracking number"),
            ("password", "Has a password"),
            ("verification code", "Has a code"),
            ("account number", "Has account info"),
            ("routing", "Has account info"),
            ("member id", "Looks like an ID card"),
            ("policy number", "Looks like insurance info"),
            ("prescription", "Looks like medical info"),
            ("appointment", "Looks like an appointment"),
            ("wi-fi", "Has Wi-Fi info"),
            ("wifi", "Has Wi-Fi info"),
        ]
        let addressPattern = #"\b\d{1,5} [a-z]+ (st|street|ave|avenue|rd|road|blvd|dr|drive|ln|lane|way|ct|court)\b"#

        var result: [String: String] = [:]
        for id in ids {
            guard let asset = findAsset(id),
                  let cg = image(for: asset, side: 1400, allowNetwork: true) else { continue }
            let handler = VNImageRequestHandler(cgImage: cg, options: [:])
            let textRequest = VNRecognizeTextRequest()
            textRequest.recognitionLevel = .fast
            textRequest.usesLanguageCorrection = false
            let codeRequest = VNDetectBarcodesRequest()
            try? handler.perform([textRequest, codeRequest])

            if let codes = codeRequest.results, !codes.isEmpty {
                result[id] = "Has a QR or barcode"
                continue
            }
            let text = (textRequest.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
                .lowercased()
            if let hit = keywords.first(where: { text.contains($0.0) }) {
                result[id] = hit.1
            } else if text.range(of: addressPattern, options: .regularExpression) != nil {
                result[id] = "Has an address"
            }
        }
        return result
    }

    // MARK: Twins (compares what's actually in the photos)

    /// Splits a group of photos taken close together into real look-alikes,
    /// and picks the best shot in each: best faces (eyes open, in focus) or the sharpest.
    nonisolated static func refineTwins(_ group: [String], protected: Set<String>)
        -> (groups: [[String]], picks: [String: String], singles: [String]) {

        var ids: [String] = []
        var images: [CGImage] = []
        var prints: [VNFeaturePrintObservation?] = []
        for id in group {
            guard let a = findAsset(id), let cg = image(for: a, side: 512, allowNetwork: true) else { continue }
            let request = VNGenerateImageFeaturePrintRequest()
            request.revision = VNGenerateImageFeaturePrintRequestRevision2
            try? VNImageRequestHandler(cgImage: cg, options: [:]).perform([request])
            ids.append(id)
            images.append(cg)
            prints.append(request.results?.first)
        }

        // Cluster photos whose "fingerprints" are close together
        var clusters: [[Int]] = []
        for i in ids.indices {
            var placed = false
            if let fp = prints[i] {
                for c in clusters.indices {
                    guard let anchor = prints[clusters[c][0]] else { continue }
                    var distance: Float = 0
                    if (try? fp.computeDistance(&distance, to: anchor)) != nil, distance < 0.55 {
                        clusters[c].append(i)
                        placed = true
                        break
                    }
                }
            }
            if !placed { clusters.append([i]) }
        }

        var groups: [[String]] = []
        var picks: [String: String] = [:]
        var singles: [String] = []
        for cluster in clusters {
            let members = cluster.map { ids[$0] }
            if members.count < 2 {
                singles.append(contentsOf: members)
                continue
            }
            groups.append(members)

            var faceScores: [String: Double] = [:]
            var sharpness: [String: Double] = [:]
            for i in cluster {
                let faces = VNDetectFaceCaptureQualityRequest()
                try? VNImageRequestHandler(cgImage: images[i], options: [:]).perform([faces])
                let scores = (faces.results ?? []).compactMap { $0.faceCaptureQuality.map { Double($0) } }
                if !scores.isEmpty {
                    faceScores[ids[i]] = scores.reduce(0, +) / Double(scores.count)
                }
                sharpness[ids[i]] = stats(images[i], side: 200)?.sharpness ?? 0
            }

            var best = members[0]
            var reason = "Sharpest"
            if let top = faceScores.max(by: { $0.value < $1.value }) {
                best = top.key
                reason = "Best faces"
            } else if let top = sharpness.max(by: { $0.value < $1.value }) {
                best = top.key
            }
            if let favorite = members.first(where: { protected.contains($0) }) {
                best = favorite
                reason = "Favorite"
            }
            picks[best] = reason
        }
        return (groups, picks, singles)
    }

    // MARK: Oopsies (dark, blurry, pocket shots)

    /// Checks your most recent photos for accidents. Returns (photo ID, reason) pairs.
    nonisolated static func oopsies(skip: Set<String>, limit: Int = 250) -> [(String, String)] {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.predicate = NSPredicate(format: "mediaType == %d", PHAssetMediaType.image.rawValue)
        var candidates: [PHAsset] = []
        PHAsset.fetchAssets(with: options).enumerateObjects { asset, _, stop in
            if skip.contains(asset.localIdentifier) || asset.mediaSubtypes.contains(.photoScreenshot) { return }
            candidates.append(asset)
            if candidates.count >= limit { stop.pointee = true }
        }

        var found: [(String, String)] = []
        for asset in candidates {
            // Local copies only, so this stays fast and doesn't download from iCloud
            guard let cg = image(for: asset, side: 240, allowNetwork: false),
                  let s = stats(cg, side: 160) else { continue }
            if s.mean < 14 {
                found.append((asset.localIdentifier, "Too dark"))
            } else if s.std < 7 {
                found.append((asset.localIdentifier, "Pocket shot"))
            } else if s.sharpness < 15 {
                found.append((asset.localIdentifier, "Blurry"))
            }
        }
        return found
    }

    // MARK: Helpers

    nonisolated static func findAsset(_ id: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [id], options: nil).firstObject
    }

    nonisolated static func image(for asset: PHAsset, side: CGFloat, allowNetwork: Bool) -> CGImage? {
        let opts = PHImageRequestOptions()
        opts.isSynchronous = true
        opts.deliveryMode = .highQualityFormat
        opts.resizeMode = .fast
        opts.isNetworkAccessAllowed = allowNetwork
        var result: CGImage?
        PHImageManager.default().requestImage(for: asset, targetSize: CGSize(width: side, height: side),
                                              contentMode: .aspectFit, options: opts) { image, _ in
            result = image?.cgImage
        }
        return result
    }

    /// Brightness, contrast and sharpness from a small grayscale copy.
    /// Sharpness is the "variance of the Laplacian": crisp edges score high, blur scores low.
    nonisolated static func stats(_ cg: CGImage, side: Int) -> (mean: Double, std: Double, sharpness: Double)? {
        var px = [UInt8](repeating: 0, count: side * side)
        let drew: Bool = px.withUnsafeMutableBytes { raw -> Bool in
            guard let ctx = CGContext(data: raw.baseAddress, width: side, height: side,
                                      bitsPerComponent: 8, bytesPerRow: side,
                                      space: CGColorSpaceCreateDeviceGray(),
                                      bitmapInfo: CGImageAlphaInfo.none.rawValue) else { return false }
            ctx.interpolationQuality = .medium
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drew else { return nil }

        let n = Double(px.count)
        var sum = 0.0
        var sumSq = 0.0
        for v in px {
            let d = Double(v)
            sum += d
            sumSq += d * d
        }
        let mean = sum / n
        let std = (max(0, sumSq / n - mean * mean)).squareRoot()

        var lapSum = 0.0
        var lapSq = 0.0
        var count = 0.0
        for y in 1..<(side - 1) {
            for x in 1..<(side - 1) {
                let i = y * side + x
                let center = 4 * Double(px[i])
                let across = Double(px[i - 1]) + Double(px[i + 1])
                let vertical = Double(px[i - side]) + Double(px[i + side])
                let lap = center - across - vertical
                lapSum += lap
                lapSq += lap * lap
                count += 1
            }
        }
        guard count > 0 else { return nil }
        let lapMean = lapSum / count
        return (mean, std, lapSq / count - lapMean * lapMean)
    }
}
