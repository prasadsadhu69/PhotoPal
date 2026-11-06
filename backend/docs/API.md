# PhotoPal API

One API for the iOS and Android apps. Every endpoint is a **Firebase callable function** in `us-central1`. Call it with the Firebase Functions SDK (`httpsCallable` on iOS, `getHttpsCallable` on Android). The SDK attaches the player's Firebase Auth token automatically.

## Privacy rule

**No photo, thumbnail, file name or photo ID ever leaves the phone.** Scanning, ML, the kept-photo list and the not-a-twin list all stay in a local database on the device. The API receives only counts and byte totals, such as "42 screenshots, 180 MB", and colors picked by Photo Match.

## Sign-in

1. On first launch, sign in anonymously with `Auth.auth().signInAnonymously()`. No sign-in screen is needed.
2. Later, offer "Save your pal" by linking Sign in with Apple or Google to that same anonymous user (`link(with:)` / `linkWithCredential`). The UID stays the same, so nothing has to be moved.
3. A player who signs in on a new phone (iPhone or Android) gets their pal back.

## Calling pattern

```
launch           -> bootstrap({ timezone })
first launch only -> importLegacySave({ save, timezone })    (iOS players upgrading from the offline version)
every tap         -> act({ action, params })
after a scan      -> act({ action: "reportScan", params: {...} })
after deleting    -> act({ action: "claimCleanup", params: {...} })
```

Every game response has the same shape:

```json
{
  "state":   { ...PlayerState },
  "derived": { "mood": "happy", "level": 3, "levelProgress": 0.4, "nextStage": "teen", "xpToNextStage": 120,
               "growthProgress": 0.52, "cozy": 13, "condition": { "sleeping": false, "sick": false, "dirty": false },
               "buildUnlocked": true, "canDigToday": true, "ageDays": 12,
               "speciesToAdopt": ["bunny", "panda", "fox"], "today": "2026-11-02" },
  "rev": 42,
  "catalogVersion": 1,
  "events": { "grewTo": "teen", "coinsDelta": 71, "reward": { ...CleanReward } }
}
```

The app renders `state` and `derived` as they are; it never computes coins, XP or growth itself. `events` tell the UI what to celebrate. The server's clock decides how much time has passed, so changing the phone's clock does nothing.

For instant-feeling taps, update the UI right away and then replace it with the server's `state` when the call returns. If the call fails, roll back.

## Endpoints

| Function | Input | Returns |
| --- | --- | --- |
| `bootstrap` | `{ timezone }` (IANA name, e.g. `"America/Los_Angeles"`) | Game response plus `isNew`, `canImportLegacySave`. Creates the player on first call. |
| `act` | `{ action, params }` | Game response. Actions are listed below. |
| `importLegacySave` | `{ save, timezone }`, where `save` is the decoded JSON from `UserDefaults` key `photopal.save.v2` | Game response. Allowed once, only before the account has adopted a pal. |
| `getCatalog` | none | The `Catalog`: animals, palettes, shop items, milestones, stages, junk rewards, tuning. Cache it and re-fetch when `catalogVersion` changes. Also readable at Firestore `config/catalog`. |
| `registerDevice` | `{ token, platform: "ios" \| "android", reminders: true }` | `{ ok }`. Call whenever the FCM token changes. |
| `unregisterDevice` | `{ token }` | `{ ok }`. Call on sign-out. |
| `exportMyData` | none | Everything stored about the player. |
| `deleteAccount` | none | `{ ok }`. Deletes all game data and the sign-in account. Required by the App Store and Google Play. |

## Actions for `act`

| Action | Params | Notes |
| --- | --- | --- |
| `adopt` | `species`, `name`, `paletteId` | First-launch adoption; free colors only |
| `finishOnboarding` | none | |
| `rename` | `name` | 1 to 24 characters |
| `feed` | `itemId` | Food or toy from the pantry; favorite food gives +10 joy |
| `play`, `brush`, `pat` | none | Not while asleep (`pat` is ignored) |
| `toggleLights` | none | Sleep or wake |
| `giveMedicine` | none | Needs medicine and a sick pal; 24 h immunity |
| `finishDig` | `foundSomething`, `freedBytes` | Memory Dig; once per local day. The photo is chosen and shown on the phone. |
| `buy` | `itemId` | Server checks price and balance |
| `toggleWear` | `itemId` | Owned hats and neckwear |
| `choosePalette` | `paletteId` | Buys the color if needed |
| `unlockPhotoMatch` | none | 250 coins |
| `applyCustomPalette` | `main`, `accent`, `belly` (each `[r, g, b]` from 0 to 1), `blaze` | Colors only; the photo stays on the phone |
| `switchPal` | `palId` | |
| `adoptPal` | `species`, `name`, `paletteId` | Costs an adoption ticket |
| `placeDecor` | `itemId` | After the first cleanup |
| `moveDecor` | `id`, `x`, `y` | 0 to 1, clamped to the yard |
| `storeDecor` | `id` | |
| `reportScan` | `counts`, `bytes`, `totalAssets` | `counts` and `bytes` are keyed by `screenshots`, `twins`, `giants`, `oopsies`. The server computes the health score and Clean meter and sets the daily bounty. |
| `claimCleanup` | `kind`, `count`, `bytes` | Call after the OS confirms deletion. The count can't exceed the last scan; there is a daily limit (5,000 items) and a bytes-per-item limit. |

## Errors

Errors come back as standard callable errors:

| Code | Meaning | App should |
| --- | --- | --- |
| `unauthenticated` | Not signed in | Sign in anonymously and retry |
| `invalid-argument` | Bad input | Fix the call (a bug) |
| `failed-precondition` | Not allowed right now, e.g. not enough coins or pal asleep | Show the message |
| `not-found` | Unknown item, palette, pal or yard item | Refresh the catalog |
| `resource-exhausted` | Daily cleanup limit | Show the message |
| `internal` | Server problem | Retry later |

## Data model

The full types are in `functions/src/rules/types.ts`, the single source of truth. Times are milliseconds since 1970; "day" fields are the player's local date (`YYYY-MM-DD`).

## Offline

PhotoPal should still open with no network. Keep the last game response on the phone and show it. Queue `act` calls and send them in order when back online; the server applies them with the real time. Scanning and deleting photos work fully offline; claim the cleanup reward when back online.
