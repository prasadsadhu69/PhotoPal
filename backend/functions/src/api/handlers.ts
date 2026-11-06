// The PhotoPal API, independent of Firebase so it can be tested with MemoryStore.
// index.ts wraps each handler as a Firebase callable function.

import { randomUUID } from "node:crypto";
import { applyAction } from "../rules/actions";
import { Ctx, GameError, derive, newPlayer, tick } from "../rules/engine";
import { fromLegacySave } from "../rules/legacy";
import { HOUR, isValidTimeZone } from "../rules/time";
import { Catalog, GameEvents, PlayerState } from "../rules/types";
import { PlayerDoc, Store, Tx } from "../store/store";

export interface Env {
  store: Store;
  now?: () => number;
  rand?: () => number;
}

const REMINDER_FOOD_LEVEL = 20;

function ctxFor(env: Env, catalog: Catalog): Ctx {
  return { now: env.now?.() ?? Date.now(), catalog, rand: env.rand ?? Math.random, uuid: () => randomUUID().toUpperCase() };
}

function timezoneOr(tz: unknown, fallback: string) {
  return isValidTimeZone(tz) ? tz : fallback;
}

/** When the active pal's tummy will drop to the reminder level, from the last tick. */
function reminderFor(cat: Catalog, s: PlayerState, prev: PlayerDoc["reminder"]): PlayerDoc["reminder"] {
  if (!s.onboarded) return null;
  const t = cat.tuning;
  const rate = s.sleeping ? t.sleepFoodPerHour : t.awakeFoodPerHour;
  const hungryNow = s.pal.food <= REMINDER_FOOD_LEVEL;
  const hungryAt = hungryNow ? s.lastTick : s.lastTick + ((s.pal.food - REMINDER_FOOD_LEVEL) / rate) * HOUR;
  return { hungryAt: Math.round(hungryAt), sent: hungryNow ? prev?.sent ?? false : false };
}

function write(tx: Tx, uid: string, ctx: Ctx, prev: PlayerDoc | null, state: PlayerState, action: string, extra: Partial<PlayerDoc> = {}) {
  const doc: PlayerDoc = {
    state,
    rev: (prev?.rev ?? 0) + 1,
    createdAt: prev?.createdAt ?? ctx.now,
    updatedAt: ctx.now,
    importedLegacy: prev?.importedLegacy ?? false,
    reminder: reminderFor(ctx.catalog, state, prev?.reminder ?? null),
    ...extra,
  };
  tx.set(uid, doc);
  const before = prev?.state.coins ?? 0;
  if (state.coins !== before) tx.addLedger(uid, { at: ctx.now, action, delta: state.coins - before, balance: state.coins });
  return doc;
}

function view(ctx: Ctx, doc: PlayerDoc, events: GameEvents = {}) {
  return { state: doc.state, derived: derive(ctx, doc.state), rev: doc.rev, catalogVersion: ctx.catalog.version, events };
}

/** First call on every launch: creates the player if needed and lets time pass. */
export async function bootstrap(env: Env, uid: string, data: { timezone?: unknown } = {}) {
  const catalog = await env.store.catalog();
  return env.store.transaction(async (tx) => {
    const ctx = ctxFor(env, catalog);
    const prev = await tx.get(uid);
    const events: GameEvents = {};
    let state: PlayerState;
    if (!prev) {
      state = newPlayer(ctx, timezoneOr(data.timezone, "UTC"));
    } else {
      state = structuredClone(prev.state);
      state.timezone = timezoneOr(data.timezone, state.timezone);
      tick(ctx, state, events);
    }
    const doc = write(tx, uid, ctx, prev, state, prev ? "bootstrap" : "create");
    return { ...view(ctx, doc, events), isNew: !prev, canImportLegacySave: !doc.importedLegacy && !state.onboarded };
  });
}

/** Every game action goes through here; see rules/actions.ts for the list. */
export async function act(env: Env, uid: string, data: { action?: unknown; params?: unknown }) {
  if (typeof data?.action !== "string") throw new GameError("invalid-argument", "action is required");
  const params = data.params && typeof data.params === "object" && !Array.isArray(data.params) ? (data.params as Record<string, unknown>) : {};
  const catalog = await env.store.catalog();
  return env.store.transaction(async (tx) => {
    const ctx = ctxFor(env, catalog);
    const prev = await tx.get(uid);
    if (!prev) throw new GameError("failed-precondition", "Call bootstrap first");
    const { state, events } = applyAction(ctx, prev.state, data.action as string, params);
    const doc = write(tx, uid, ctx, prev, state, data.action as string);
    return view(ctx, doc, events);
  });
}

/** Moves an existing on-device iOS save into the account. Allowed once, before onboarding on the server. */
export async function importLegacySave(env: Env, uid: string, data: { save?: unknown; timezone?: unknown }) {
  const catalog = await env.store.catalog();
  return env.store.transaction(async (tx) => {
    const ctx = ctxFor(env, catalog);
    const prev = await tx.get(uid);
    if (prev && (prev.importedLegacy || prev.state.onboarded)) {
      throw new GameError("failed-precondition", "This account already has a pal");
    }
    const state = fromLegacySave(ctx, data?.save, timezoneOr(data?.timezone, prev?.state.timezone ?? "UTC"));
    const events: GameEvents = {};
    tick(ctx, state, events);
    const doc = write(tx, uid, ctx, prev, state, "importLegacySave", { importedLegacy: true });
    return view(ctx, doc, events);
  });
}

export async function getCatalog(env: Env) {
  return env.store.catalog();
}

export async function registerDevice(env: Env, uid: string, data: { token?: unknown; platform?: unknown; reminders?: unknown }) {
  if (typeof data?.token !== "string" || data.token.length < 10 || data.token.length > 4096) throw new GameError("invalid-argument", "token is required");
  if (data.platform !== "ios" && data.platform !== "android") throw new GameError("invalid-argument", "platform must be ios or android");
  await env.store.putDevice(uid, { token: data.token, platform: data.platform, reminders: data.reminders !== false, updatedAt: env.now?.() ?? Date.now() });
  return { ok: true };
}

export async function unregisterDevice(env: Env, uid: string, data: { token?: unknown }) {
  if (typeof data?.token === "string") await env.store.removeDevice(uid, data.token);
  return { ok: true };
}

/** Everything stored about the player (privacy: right of access). Push tokens are left out. */
export async function exportMyData(env: Env, uid: string) {
  const [doc, ledger, devices] = await Promise.all([env.store.read(uid), env.store.ledger(uid, 1000), env.store.devices(uid)]);
  return { player: doc, ledger, devices: devices.map(({ platform, reminders, updatedAt }) => ({ platform, reminders, updatedAt })) };
}

/** Deletes the player's game data. index.ts also deletes the sign-in account. */
export async function deleteMyData(env: Env, uid: string) {
  await env.store.deletePlayer(uid);
  return { ok: true };
}

export type PushSender = (tokens: string[], msg: { title: string; body: string }) => Promise<{ invalidTokens: string[] }>;

/**
 * Scheduled job: nudges players whose pal is getting hungry. Skips their local night hours
 * (the reminder stays due and goes out on a later run).
 */
export async function sendDueReminders(env: Env, send: PushSender, limit = 500) {
  const now = env.now?.() ?? Date.now();
  const due = await env.store.dueReminders(now, limit);
  let sent = 0;
  for (const { uid, doc } of due) {
    const hour = Number(new Intl.DateTimeFormat("en-US", { timeZone: doc.state.timezone, hour: "numeric", hourCycle: "h23" }).format(new Date(now)));
    if (hour >= 21 || hour < 9) continue;
    const tokens = (await env.store.devices(uid)).filter((d) => d.reminders).map((d) => d.token);
    if (tokens.length) {
      const name = doc.state.pal.name;
      const { invalidTokens } = await send(tokens, { title: `${name} is hungry`, body: `Your pal's tummy is rumbling. Stop by with a treat!` });
      for (const t of invalidTokens) await env.store.removeDevice(uid, t);
      sent += 1;
    }
    await env.store.markReminderSent(uid);
  }
  return { due: due.length, sent };
}
