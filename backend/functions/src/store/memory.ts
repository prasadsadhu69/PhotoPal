import bundled from "../rules/catalog.data.json";
import { Catalog } from "../rules/types";
import { Device, LedgerEntry, PlayerDoc, Store, Tx } from "./store";

/** In-memory store for tests and local experiments. Transactions run one at a time. */
export class MemoryStore implements Store {
  players = new Map<string, PlayerDoc>();
  ledgers = new Map<string, LedgerEntry[]>();
  deviceMap = new Map<string, Map<string, Device>>();
  cat: Catalog = structuredClone(bundled as Catalog);
  private queue: Promise<unknown> = Promise.resolve();

  transaction<T>(fn: (tx: Tx) => Promise<T>): Promise<T> {
    const run = async () => {
      const writes = new Map<string, PlayerDoc>();
      const ledger: [string, LedgerEntry][] = [];
      const tx: Tx = {
        get: async (uid) => structuredClone(this.players.get(uid) ?? null),
        set: (uid, doc) => void writes.set(uid, structuredClone(doc)),
        addLedger: (uid, e) => void ledger.push([uid, e]),
      };
      const result = await fn(tx);
      for (const [uid, doc] of writes) this.players.set(uid, doc);
      for (const [uid, e] of ledger) this.ledgers.set(uid, [...(this.ledgers.get(uid) ?? []), e]);
      return result;
    };
    const p = this.queue.then(run, run);
    this.queue = p.catch(() => undefined);
    return p;
  }

  async read(uid: string) { return structuredClone(this.players.get(uid) ?? null); }
  async catalog() { return structuredClone(this.cat); }
  async saveCatalog(c: Catalog) { this.cat = structuredClone(c); }
  async putDevice(uid: string, d: Device) {
    const m = this.deviceMap.get(uid) ?? new Map();
    m.set(d.token, d);
    this.deviceMap.set(uid, m);
  }
  async removeDevice(uid: string, token: string) { this.deviceMap.get(uid)?.delete(token); }
  async devices(uid: string) { return [...(this.deviceMap.get(uid)?.values() ?? [])]; }
  async dueReminders(now: number, limit: number) {
    return [...this.players.entries()]
      .filter(([, d]) => d.reminder && !d.reminder.sent && d.reminder.hungryAt <= now)
      .slice(0, limit)
      .map(([uid, doc]) => ({ uid, doc: structuredClone(doc) }));
  }
  async markReminderSent(uid: string) {
    const d = this.players.get(uid);
    if (d?.reminder) d.reminder.sent = true;
  }
  async ledger(uid: string, limit: number) { return (this.ledgers.get(uid) ?? []).slice(-limit).reverse(); }
  async deletePlayer(uid: string) {
    this.players.delete(uid);
    this.ledgers.delete(uid);
    this.deviceMap.delete(uid);
  }
}
