# PhotoPal backend

The server side of PhotoPal on Google Cloud (Firebase). One backend for the iOS and Android apps.

**Privacy:** photos, thumbnails and photo IDs never leave the phone. The server stores the pet, coins and progress, and receives only junk *counts* and byte totals from scans.

## What's here

| Path | What it is |
| --- | --- |
| `functions/src/rules/` | The game rules ported from `GameState.swift`: needs, growing up, sickness, cleanups, daily bounties, shop, pals, yard. Pure TypeScript with no Firebase code. |
| `functions/src/rules/catalog.data.json` | Animals, colors, shop items, milestones and tuning, generated from `Models.swift`. Editable without an app release. |
| `functions/src/api/handlers.ts` | The API: bootstrap, actions, legacy save import, catalog, push devices, data export, account deletion, hungry reminders. |
| `functions/src/store/` | Storage. `firestore.ts` for production, `memory.ts` for tests. |
| `functions/src/index.ts` | Firebase entry point (callable functions and a 30-minute reminder job). |
| `functions/test/` | 30 tests for the rules and the API. |
| `firestore.rules` | Players can read only their own data; only the server writes. |
| `docs/API.md` | The contract both apps follow. |
| `../PhotoPal/BackendSync.swift` | The iOS app's connection to this backend (already wired into `GameState`). |
| `clients/ios/PhotoPalBackend.swift` | A standalone iOS client, kept for reference. The app uses `BackendSync.swift`. |
| `clients/android/PhotoPalBackend.kt` | Android client starter with the same API. |

## Services

| Service | Built with |
| --- | --- |
| Identity | Firebase Auth: anonymous first, then Sign in with Apple or Google |
| Cloud save | Firestore `players/{uid}`, written only by Cloud Functions in transactions |
| Game rules and economy | Cloud Functions using the server clock; every coin change is recorded in `players/{uid}/ledger` |
| Content catalog and tuning | Firestore `config/catalog`, with a bundled fallback |
| Push reminders | FCM, sent by a scheduled function when a pal gets hungry (not between 9 pm and 9 am local time) |
| Privacy | `exportMyData` and `deleteAccount` |
| Analytics and crashes | Firebase Analytics and Crashlytics SDKs in the apps (no backend code needed) |

## Deploy to your Google Cloud account (one time, about 20 minutes)

You need Node.js 22 and the Firebase CLI: `npm install -g firebase-tools`.

1. **Create the project.** Go to [console.firebase.google.com](https://console.firebase.google.com), choose *Create a project*, and link it to your existing Google Cloud billing account. Cloud Functions needs the pay-as-you-go *Blaze* plan; the free allowance still applies.
2. **Set a budget alert first.** In Google Cloud console > Billing > Budgets & alerts, add a budget (for example $25/month) with alerts at 50%, 90% and 100%.
3. **Turn on the services** in the Firebase console:
   - Authentication > Sign-in method: enable **Anonymous**, **Apple** and **Google**.
   - Firestore Database: create it in production mode, location `nam5` (or the region closest to your players).
4. **Point this folder at the project.** Put your project ID in `backend/.firebaserc`, then:
   ```bash
   cd backend
   firebase login
   cd functions && npm install && npm test && cd ..
   firebase deploy --only functions,firestore
   ```
5. **Upload the catalog** (optional; the functions use the bundled copy until you do):
   ```bash
   gcloud auth application-default login
   cd functions && npm run seed:catalog
   ```
6. **Register the apps** in Firebase project settings: add an iOS app (bundle ID `com.clubooo.PhotoPal`) and download `GoogleService-Info.plist`; add an Android app later and download `google-services.json`.
7. **Turn on App Check** (recommended before launch): register both apps under App Check, then set `ENFORCE_APP_CHECK = true` in `functions/src/index.ts` and deploy again.

## Day-to-day

| Task | Command |
| --- | --- |
| Run tests | `cd functions && npm test` |
| Change prices, items or tuning | Edit `functions/src/rules/catalog.data.json`, bump `version`, run `npm run seed:catalog` |
| Re-sync the catalog from `Models.swift` | `npm run gen:catalog` |
| Deploy code changes | `firebase deploy --only functions` (tests run first) |
| See logs | `npm run logs`, or Cloud console > Logging |

## Cost guard rails already in place

- `maxInstances: 20` per function caps runaway scaling.
- 256 MiB functions in a single region.
- The catalog is cached in memory for 5 minutes per instance.
- One Firestore read and one write per action, plus a ledger write only when coins change.
- The game state field is excluded from Firestore indexing.

## Not built yet

- **Real-money purchases.** Add RevenueCat (or App Store and Play receipt validation) when you decide to sell anything. Grants then go through the same ledger.
- **Social features**, such as visiting yards and leaderboards.
- **Sign in with Apple.** Players are anonymous for now, so a pal doesn't yet follow them to a new phone. Linking Apple or Google sign-in to the anonymous account is the next step.
- **Push tokens from the app.** The reminder job is ready, but the app doesn't register for FCM yet (needs FirebaseMessaging and the Push Notifications capability).
- **Saving the offline queue.** Actions taken offline are queued in memory and lost if the app is closed before it reconnects.

## Turn the backend on in the iOS app

The app is already wired to sync. It stays fully offline until these two things are added in Xcode:

1. **Add the Firebase package:** File > Add Package Dependencies, enter `https://github.com/firebase/firebase-ios-sdk`, and add **FirebaseAuth** and **FirebaseFunctions** to the PhotoPal target (not the widget).
2. **Add the config file:** download `GoogleService-Info.plist` from the Firebase console (Project settings > your iOS app) and drag it into the PhotoPal folder, checked for the PhotoPal target.

Build and run. On first launch the app signs in anonymously, uploads the existing pal once (without any photo IDs), and from then on the server keeps the score. Without the plist, nothing is sent.
