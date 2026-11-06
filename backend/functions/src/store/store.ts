import { Catalog, PlayerState } from "../rules/types";

/** What is stored per player, beside the game state itself. */
export interface PlayerDoc {
  state: PlayerState;
  rev: number;
  createdAt: number;
  updatedAt: number;
  importedLegacy: boolean;
  /** When the active pal will get hungry, for push reminders. Top-level so it can be queried. */
  reminder: { hungryAt: number; sent: boolean } | null;
}

export interface LedgerEntry {
  at: number;
  action: string;
  delta: number;
  balance: number;
}

export interface Device {
  token: string;
  platform: "ios" | "android";
  reminders: boolean;
  updatedAt: number;
}

export interface Tx {
  get(uid: string): Promise<PlayerDoc | null>;
  set(uid: string, doc: PlayerDoc): void;
  addLedger(uid: string, entry: LedgerEntry): void;
}

/**
 * Storage behind the API. FirestoreStore is used in production; MemoryStore in tests.
 * Keeping this narrow means the game and API code never touch Firestore directly.
 */
export interface Store {
  transaction<T>(fn: (tx: Tx) => Promise<T>): Promise<T>;
  read(uid: string): Promise<PlayerDoc | null>;
  catalog(): Promise<Catalog>;
  saveCatalog(c: Catalog): Promise<void>;
  putDevice(uid: string, d: Device): Promise<void>;
  removeDevice(uid: string, token: string): Promise<void>;
  devices(uid: string): Promise<Device[]>;
  /** Players whose reminder is due and not yet sent. */
  dueReminders(now: number, limit: number): Promise<{ uid: string; doc: PlayerDoc }[]>;
  markReminderSent(uid: string): Promise<void>;
  ledger(uid: string, limit: number): Promise<LedgerEntry[]>;
  deletePlayer(uid: string): Promise<void>;
}
