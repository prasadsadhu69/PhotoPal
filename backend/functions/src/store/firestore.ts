import { createHash } from "node:crypto";
import type { Firestore } from "firebase-admin/firestore";
import bundled from "../rules/catalog.data.json";
import { Catalog } from "../rules/types";
import { Device, LedgerEntry, PlayerDoc, Store } from "./store";

// Layout
//   players/{uid}                     PlayerDoc (game state; read-only to its owner)
//   players/{uid}/ledger/{autoId}     every coin change, for support and fraud checks
//   players/{uid}/devices/{tokenHash} push tokens
//   config/catalog                    { data: Catalog } — shop, animals, tuning; public to signed-in users

const CATALOG_TTL_MS = 5 * 60_000;

export class FirestoreStore implements Store {
  private cached: { at: number; value: Catalog } | null = null;

  constructor(private db: Firestore) {}

  private player(uid: string) { return this.db.collection("players").doc(uid); }
  private tokenId(token: string) { return createHash("sha256").update(token).digest("hex").slice(0, 40); }

  transaction<T>(fn: Parameters<Store["transaction"]>[0]): Promise<T> {
    return this.db.runTransaction(async (t) =>
      fn({
        get: async (uid) => ((await t.get(this.player(uid))).data() as PlayerDoc | undefined) ?? null,
        set: (uid, doc) => void t.set(this.player(uid), doc),
        addLedger: (uid, e) => void t.create(this.player(uid).collection("ledger").doc(), e),
      }),
    ) as Promise<T>;
  }

  async read(uid: string) { return ((await this.player(uid).get()).data() as PlayerDoc | undefined) ?? null; }

  /** The live catalog from Firestore, cached per instance; falls back to the copy bundled with the code. */
  async catalog(): Promise<Catalog> {
    const now = Date.now();
    if (this.cached && now - this.cached.at < CATALOG_TTL_MS) return this.cached.value;
    const snap = await this.db.collection("config").doc("catalog").get();
    const value = (snap.data()?.data as Catalog | undefined) ?? (bundled as Catalog);
    this.cached = { at: now, value };
    return value;
  }

  async saveCatalog(c: Catalog) {
    await this.db.collection("config").doc("catalog").set({ data: c, updatedAt: Date.now() });
    this.cached = null;
  }

  async putDevice(uid: string, d: Device) { await this.player(uid).collection("devices").doc(this.tokenId(d.token)).set(d); }
  async removeDevice(uid: string, token: string) { await this.player(uid).collection("devices").doc(this.tokenId(token)).delete(); }
  async devices(uid: string) { return (await this.player(uid).collection("devices").get()).docs.map((d) => d.data() as Device); }

  async dueReminders(now: number, limit: number) {
    const q = await this.db.collection("players")
      .where("reminder.sent", "==", false)
      .where("reminder.hungryAt", "<=", now)
      .orderBy("reminder.hungryAt")
      .limit(limit)
      .get();
    return q.docs.map((d) => ({ uid: d.id, doc: d.data() as PlayerDoc }));
  }

  async markReminderSent(uid: string) { await this.player(uid).update({ "reminder.sent": true }); }

  async ledger(uid: string, limit: number) {
    const q = await this.player(uid).collection("ledger").orderBy("at", "desc").limit(limit).get();
    return q.docs.map((d) => d.data() as LedgerEntry);
  }

  /** Deletes the player document and everything under it (ledger, devices). */
  async deletePlayer(uid: string) { await this.db.recursiveDelete(this.player(uid)); }
}
