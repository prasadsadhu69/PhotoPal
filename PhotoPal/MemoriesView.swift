import Photos
import PhotosUI
import SwiftUI
import UIKit

/// Memories & Keepsakes: the Peanut Vault, today's memory dig, and a photo book of favorites
struct MemoriesView: View {
    @EnvironmentObject var game: GameState
    @EnvironmentObject var library: PhotoLibrary

    @State private var picks: [PhotosPickerItem] = []
    @State private var adding = false
    @State private var showDig = false
    @State private var favorites: [String] = []
    @State private var removing: String?

    private let columns = [GridItem(.adaptive(minimum: 96), spacing: 6)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    vault
                    digCard
                    photoBook
                    record
                }
                .padding()
            }
            .paperBackground()
            .navigationTitle("Memories")
            .onAppear {
                library.loadVault()
                favorites = library.favoriteIDs()
            }
            .onChange(of: picks) { _, items in
                guard !items.isEmpty else { return }
                Task { await addPicked(items) }
            }
            .sheet(isPresented: $showDig) { MemoryDigView() }
            .confirmationDialog("Take this photo out of the Peanut Vault?",
                                isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                                titleVisibility: .visible) {
                Button("Take it out") {
                    if let id = removing { Task { await library.removeFromVault([id]) } }
                    removing = nil
                }
                Button("Keep it in the Vault", role: .cancel) { removing = nil }
            } message: {
                Text("The photo stays in your library. It just won't be protected anymore.")
            }
        }
    }

    // MARK: The Peanut Vault

    private var vault: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle()
                        .fill(LinearGradient(colors: [Color(red: 0.98, green: 0.82, blue: 0.4), Theme.mustard],
                                             startPoint: .top, endPoint: .bottom))
                        .overlay(Circle().inset(by: 3).stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: [3, 2.5]))))
                    .shadow(color: Theme.mustard.opacity(0.5), radius: 6, y: 2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(PhotoLibrary.vaultName).font(Theme.title3)
                    Text("Receipts, IDs and favorite memories in here are never flagged as junk.")
                        .font(.caption)
                        .opacity(0.7)
                }
            }

            if library.vaultIDs.isEmpty {
                Text("Your vault is empty. Add anything you want to keep safe.")
                    .font(.subheadline)
                    .opacity(0.7)
            } else {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(library.assets(for: library.vaultIDs), id: \.localIdentifier) { asset in
                        Thumbnail(asset: asset, side: 110)
                            .overlay(alignment: .topTrailing) {
                                Image(systemName: "lock.fill")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(5)
                                    .background(Theme.mustard, in: Circle())
                                    .padding(4)
                            }
                            .onLongPressGesture { removing = asset.localIdentifier }
                    }
                }
                Text("Press and hold a photo to take it out.")
                    .font(.caption2)
                    .opacity(0.6)
            }

            PhotosPicker(selection: $picks, maxSelectionCount: 50, matching: .any(of: [.images, .videos]),
                         photoLibrary: .shared()) {
                HStack {
                    if adding { ProgressView() } else { Image(systemName: "plus") }
                    Text(adding ? "Adding..." : "Add to the Vault")
                }
                .font(Theme.headline)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(Theme.mustard)
            .disabled(adding)

            Text("It's a real album in your Photos app, so you can also add things there.")
                .font(.caption2)
                .opacity(0.6)
        }
        .paperCard()
    }

    private func addPicked(_ items: [PhotosPickerItem]) async {
        adding = true
        let ids = items.compactMap { $0.itemIdentifier }
        await library.addToVault(ids)
        game.keep(ids)
        picks = []
        adding = false
    }

    // MARK: Memory dig

    private var digCard: some View {
        Button {
            showDig = true
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Theme.plum, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(game.canDigToday ? "\(game.petName) dug something up!" : "Today's dig is done")
                        .font(Theme.headline)
                    Text(game.canDigToday ? "See a photo from this day in past years." : "Come back tomorrow for another memory.")
                        .font(.caption)
                        .opacity(0.7)
                }
                Spacer()
                Image(systemName: "chevron.right").opacity(0.5)
            }
            .paperCard(padding: 12)
        }
        .buttonStyle(.plain)
        .disabled(!game.canDigToday)
    }

    // MARK: Photo book

    @ViewBuilder
    private var photoBook: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Photo book").font(Theme.title3)
            Text("Your favorites, like a little scrapbook. Favorites are always protected.")
                .font(.caption)
                .opacity(0.7)
            if favorites.isEmpty {
                Text("Tap the heart on photos in your Photos app, or choose Favorite in a Memory Dig, and they'll show up here.")
                    .font(.subheadline)
                    .opacity(0.7)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 12)], spacing: 14) {
                    ForEach(Array(library.assets(for: favorites).enumerated()), id: \.element.localIdentifier) { index, asset in
                        Thumbnail(asset: asset, side: 110)
                            .padding(5)
                            .padding(.bottom, 12)
                            .background(Color.white)
                            .shadow(color: Theme.cocoa.opacity(0.15), radius: 3, y: 2)
                            .rotationEffect(.degrees(index % 3 == 0 ? -3 : index % 3 == 1 ? 2 : -1))
                    }
                }
                .padding(.top, 4)
            }
        }
        .paperCard()
    }

    private var record: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Your scooping record").font(Theme.headline)
            LabeledContent("Space freed", value: ByteCountFormatter.string(fromByteCount: game.bytesFreed, countStyle: .file))
            LabeledContent("Poops scooped", value: "\(game.itemsTossed)")
            LabeledContent("Paw streak", value: "\(game.streak) day\(game.streak == 1 ? "" : "s")")
        }
        .font(.subheadline)
        .paperCard()
    }
}
