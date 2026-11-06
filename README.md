# PhotoPal

A Tamagotchi that lives in your camera roll. Junk photos (old screenshots, near-duplicate shots, giant videos) show up as poop in your pal's yard. Your pal sniffs it out, you scoop it in batches, and the coins you earn keep your pal fed, happy and dressed up.

## How the game works

1. **Adopt:** pick a dog, cat, bunny, panda or fox, name it, and choose its colors.
2. **Poop patrol:** your pal scans the camera roll and gives it a health score from 0 to 100. Each kind of junk becomes a poop pile in the yard: Screenshots, Twin shots, Giant videos (over 50 MB) and Oopsies (dark, blurry or pocket shots).
   - Never treated as poop: Favorites, photos in albums you made, and screenshots from the last 7 days.
   - Screenshots get their text read on the phone; ones that look important (tickets, receipts, QR codes, addresses) are kept automatically.
   - Twin shots are compared by what's actually in them, and the best one is kept (best faces, or sharpest).
3. **Scoop:** tap a pile. Everything is pre-selected to delete; tap anything you want to keep. For twin shots, your pal pre-picks the best one. iOS asks you to confirm, and deleted items stay in Recently Deleted for 30 days.
4. **Care:** Feed, Play, Lights (sleep) and Medicine, just like a Tamagotchi. Needs are Hunger, Happy, Clean (your real camera roll health) and Energy. A dirty yard or an empty tummy can make your pal sick. Pals never die.
5. **Grow up and collect pals:** every pal starts as a baby (puppy, kitten, cub...) and grows with XP: Baby, Little, Teen, Grown, Legendary. Reaching Teen, Grown and Legendary each earns an adoption ticket for a new animal. All your pals live in the yard together; you care for one at a time and can switch from your pal's profile.
6. **Daily loop:** a daily bounty, a Memory Dig of a photo from this day in past years, streaks, and reminders.
7. **Spend:** treats, toys, medicine, outfits, yard items (Build unlocks after your first scoop), extra colors, and Photo Match, which copies a real pet's colors from a photo.

## Install on your iPhone

You need a Mac with Xcode (free from the Mac App Store) and a USB cable.

1. Clone this repo and open `PhotoPal.xcodeproj` in Xcode.
2. Click the blue `PhotoPal` project icon, then for both the **PhotoPal** and **PeanutWidgetExtension** targets open **Signing & Capabilities**, check **Automatically manage signing**, and choose your Apple ID as the Team.
3. If Xcode complains about the App Group, change `group.com.pranati.PhotoPal` to a group under your own team in both targets (and in `Models.swift`).
4. Plug in your iPhone, pick it from the device menu at the top of Xcode, and press the Play button.
5. First time only, on the iPhone:
   - **Settings > Privacy & Security > Developer Mode**, turn it on and restart.
   - **Settings > General > VPN & Device Management**, tap your Apple ID, then **Trust**.

With a free Apple ID the app expires after 7 days. Plug in and press Play again to refresh it. A paid Apple Developer account ($99/year) removes that limit and lets you share via TestFlight.

## Tweaking the game

- Coin values, prices, colors, animals: `Models.swift`
- Need drain speeds, growing up, rewards: `GameState.swift`
- How your pal and the poop look: `DogArt.swift`

## File map

| File | What it does |
| --- | --- |
| `PeanutWidget/` | Home Screen widget showing your pal |
| `PhotoPalApp.swift` | App entry point and the wooden dock with the Scoop & Sweep spade |
| `OnboardingView.swift` | Adopt flow and first scan |
| `Models.swift` | Animals, colors, junk types, shop items (shared with widget) |
| `DogArt.swift` | Drawings of every animal, outfits, poop, yard items (shared with widget) |
| `GameState.swift` | Needs, coins, growing up, saving progress |
| `PhotoLibrary.swift` | Scanning for junk, thumbnails, deleting |
| `PetViews.swift` | Yard screen: level, coins, paw streak, notes, pile previews, build tray |
| `YardView.swift` | The yard, poop piles, and your pal's behavior |
| `HuntViews.swift` | Scoop & Sweep (camera roll health report) and the scooping screen |
| `BinViews.swift` | Reward screen and photo thumbnails |
| `ShopView.swift` | Shop item rows used by Feed & Care, Closet and Build |
| `ClosetView.swift` | Closet tab (colors, Photo Match, outfits) and your pal's profile (pals, adopting, milestones) |
| `Theme.swift` | Papercraft palette, Fredoka fonts, paper, wood and felt textures |
| `CareView.swift` | Feed & Care tab: pantry, brushing, lights, medicine, treat shop |
| `MemoriesView.swift` | Memories tab: Peanut Vault, Memory Dig, photo book |
| `Fonts/` | Fredoka font files (free, SIL Open Font License) |
| `PhotoMatch.swift` | Reads a real pet's colors from a photo, on device |
| `PhotoSmarts.swift` | On-device checks: protected photos, important screenshots, real twins, oopsies |
| `MemoryDigView.swift` | Daily memory from past years |
| `Notifications.swift` | Reminders |
