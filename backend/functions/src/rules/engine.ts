// The PhotoPal game rules, ported from GameState.swift.
// Pure functions: no Firebase, no I/O. Every action takes the saved state, the
// catalog (content + tuning) and the current time, and returns the new state.
// The server is the only place these run, so coins, XP and time can't be faked
// on the phone, and the iOS and Android apps always play by the same rules.

import {
  Catalog, CleanReward, GameEvents, JUNK_KINDS, JunkKind, JunkSummary, LifeStage, Pal, Palette,
  PetLook, PlayerState, SPECIES, STAGES, ShopItem, Species,
} from "./types";
import { HOUR, dayKey, isToday, isYesterday } from "./time";

export interface Ctx {
  now: number;
  catalog: Catalog;
  rand: () => number;
  uuid: () => string;
}

export type ErrorCode = "invalid-argument" | "failed-precondition" | "not-found" | "resource-exhausted";

export class GameError extends Error {
  constructor(public code: ErrorCode, message: string) {
    super(message);
  }
}

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
const fail = (code: ErrorCode, msg: string): never => {
  throw new GameError(code, msg);
};

// ---------------------------------------------------------------- lookups

export function item(cat: Catalog, id: unknown): ShopItem {
  const it = typeof id === "string" ? cat.items.find((i) => i.id === id) : undefined;
  return it ?? fail("not-found", `Unknown item ${String(id)}`);
}

export function palette(cat: Catalog, species: Species, id: unknown): Palette {
  const p = typeof id === "string" ? cat.species[species].palettes.find((x) => x.id === id) : undefined;
  return p ?? fail("not-found", `Unknown palette ${String(id)} for ${species}`);
}

function species(v: unknown): Species {
  return SPECIES.includes(v as Species) ? (v as Species) : fail("invalid-argument", `Unknown animal ${String(v)}`);
}

function junkKind(v: unknown): JunkKind {
  return JUNK_KINDS.includes(v as JunkKind) ? (v as JunkKind) : fail("invalid-argument", `Unknown junk kind ${String(v)}`);
}

export function cleanName(v: unknown): string {
  const name = typeof v === "string" ? v.replace(/[\u0000-\u001f\u007f]/g, "").trim() : "";
  if (name.length < 1 || name.length > 24) fail("invalid-argument", "Names are 1 to 24 characters");
  return name;
}

function count(v: unknown, max: number, label: string): number {
  if (typeof v !== "number" || !Number.isInteger(v) || v < 0 || v > max) fail("invalid-argument", `${label} must be a whole number from 0 to ${max}`);
  return v as number;
}

function nextStage(stage: LifeStage): LifeStage | null {
  const i = STAGES.indexOf(stage);
  return i < STAGES.length - 1 ? STAGES[i + 1] : null;
}

// ---------------------------------------------------------------- new player

export function newPlayer(ctx: Ctx, timezone: string): PlayerState {
  const t = ctx.catalog.tuning;
  return {
    schema: 1,
    timezone,
    onboarded: false,
    pal: {
      id: ctx.uuid(), name: "Peanut", look: { species: "dog", paletteId: "peanut", custom: null },
      born: ctx.now, stage: "baby", xp: 0, careMistakes: 0, food: 80, joy: 80, energy: 90, sick: false,
      hatId: null, neckId: null,
    },
    otherPals: [],
    tickets: 0,
    clean: 100,
    sleeping: false,
    sickImmuneUntil: null,
    lastTick: ctx.now,
    coins: t.startCoins,
    inventory: { kibble: 3 },
    wardrobe: [],
    palettesOwned: [],
    photoMatchUnlocked: false,
    decorOwned: { bowl: 1 },
    placed: [{ id: ctx.uuid(), itemId: "bowl", x: 0.22, y: 0.3 }],
    itemsTossed: 0,
    bytesFreed: 0,
    cleanups: 0,
    poops: 0,
    streak: 0,
    lastPlayDay: null,
    lastCleanDay: null,
    lastDigDay: null,
    daily: null,
    milestones: [],
    hasFed: false,
    junk: null,
    cleanupToday: { day: dayKey(ctx.now, timezone), items: 0 },
  };
}

// ---------------------------------------------------------------- derived values (for both apps' UI)

export function cozy(cat: Catalog, s: PlayerState): number {
  const sum = s.placed.reduce((n, p) => n + (cat.items.find((i) => i.id === p.itemId)?.comfort ?? 0), 0);
  return Math.min(cat.tuning.maxCozy, sum);
}

export function mood(s: PlayerState): string {
  const { food, joy } = s.pal;
  let m: string;
  if (food < 15) m = "starving";
  else {
    const avg = (food + joy + s.clean) / 3;
    m = avg < 35 ? "grumpy" : avg < 60 ? "content" : avg < 85 ? "happy" : "thriving";
  }
  if (s.pal.sick && (m === "happy" || m === "thriving")) return "content";
  return m;
}

export function derive(ctx: Ctx, s: PlayerState) {
  const next = nextStage(s.pal.stage);
  const st = ctx.catalog.stages;
  const owned = new Set([s.pal.look.species, ...s.otherPals.map((p) => p.look.species)]);
  return {
    mood: mood(s),
    level: Math.floor(s.pal.xp / 100) + 1,
    levelProgress: (s.pal.xp % 100) / 100,
    nextStage: next,
    xpToNextStage: next ? Math.max(0, st[next] - s.pal.xp) : 0,
    growthProgress: next ? clamp((s.pal.xp - st[s.pal.stage]) / (st[next] - st[s.pal.stage]), 0, 1) : 1,
    cozy: cozy(ctx.catalog, s),
    condition: { sleeping: s.sleeping, sick: s.pal.sick, dirty: s.clean < 50 },
    buildUnlocked: s.cleanups >= 1,
    canDigToday: !isToday(s.lastDigDay, ctx.now, s.timezone),
    ageDays: Math.max(0, Math.floor((ctx.now - s.pal.born) / (24 * HOUR))),
    speciesToAdopt: SPECIES.filter((x) => !owned.has(x)),
    today: dayKey(ctx.now, s.timezone),
  };
}

// ---------------------------------------------------------------- growing up and time passing

/** Grows the pal as far as its XP allows. Each new stage from Teen up earns an adoption ticket. */
function advanceStage(cat: Catalog, s: PlayerState): LifeStage | undefined {
  let grew: LifeStage | undefined;
  for (let next = nextStage(s.pal.stage); next && s.pal.xp >= cat.stages[next]; next = nextStage(s.pal.stage)) {
    s.pal.stage = next;
    grew = next;
    if (next !== "kid" && 1 + s.otherPals.length < SPECIES.length) s.tickets += 1;
  }
  return grew;
}

function checkSick(cat: Catalog, s: PlayerState, now: number) {
  if (s.pal.sick) return;
  if (s.sickImmuneUntil && now < s.sickImmuneUntil) return;
  if (s.pal.food <= 0 || s.clean < cat.tuning.sickCleanBelow) s.pal.sick = true;
}

/** The Tamagotchi part: needs drain with real (server) time. */
export function tick(ctx: Ctx, s: PlayerState, ev: GameEvents) {
  const t = ctx.catalog.tuning;
  const hours = (ctx.now - s.lastTick) / HOUR;
  if (!(hours > 0.005)) return;
  const p = s.pal;
  const wasFed = p.food > 0;
  const wasHappy = p.joy > 0;
  if (s.sleeping) {
    p.energy = Math.min(100, p.energy + hours * t.sleepEnergyPerHour);
    p.food = Math.max(0, p.food - hours * t.sleepFoodPerHour);
    if (p.energy >= 100) s.sleeping = false;
  } else {
    p.food = Math.max(0, p.food - hours * t.awakeFoodPerHour);
    const comfort = Math.max(t.minComfortFactor, 1 - cozy(ctx.catalog, s) / t.cozyDivisor);
    const sickFactor = p.sick ? t.sickJoyFactor : 1;
    p.joy = Math.max(0, p.joy - hours * t.awakeJoyPerHour * comfort * sickFactor);
    p.energy = Math.max(0, p.energy - hours * t.awakeEnergyPerHour);
    if (p.energy <= 0) s.sleeping = true;
  }
  if (wasFed && p.food <= 0) p.careMistakes += 1;
  if (wasHappy && p.joy <= 0) p.careMistakes += 1;
  checkSick(ctx.catalog, s, ctx.now);
  const grew = advanceStage(ctx.catalog, s);
  if (grew) ev.grewTo = grew;
  s.lastTick = ctx.now;
}

// ---------------------------------------------------------------- camera roll scans (counts only)

export function junkScore(cat: Catalog, counts: Record<JunkKind, number>, totalAssets: number): number {
  if (totalAssets <= 0) return 100;
  const junk = JUNK_KINDS.reduce((n, k) => n + counts[k], 0);
  const value = 100 * (1 - Math.min(1, junk / totalAssets / cat.tuning.scoreJunkRatio));
  return clamp(Math.round(value), 0, 100);
}

/** The phone scanned the camera roll and reports how much junk of each kind it found. */
export function reportScan(ctx: Ctx, s: PlayerState, input: { counts?: unknown; bytes?: unknown; totalAssets?: unknown }) {
  const totalAssets = count(input.totalAssets, 10_000_000, "totalAssets");
  const rawCounts = (input.counts ?? {}) as Record<string, unknown>;
  const rawBytes = (input.bytes ?? {}) as Record<string, unknown>;
  const counts = {} as Record<JunkKind, number>;
  const bytes = {} as Record<JunkKind, number>;
  for (const k of JUNK_KINDS) {
    counts[k] = count(rawCounts[k] ?? 0, totalAssets, `counts.${k}`);
    // Byte totals are estimates on the phone, so cap them instead of rejecting the scan
    bytes[k] = Math.min(count(rawBytes[k] ?? 0, Number.MAX_SAFE_INTEGER, `bytes.${k}`), counts[k] * ctx.catalog.tuning.maxBytesPerItem[k]);
  }
  const score = junkScore(ctx.catalog, counts, totalAssets);
  s.junk = { counts, bytes, totalAssets, score, scannedAt: ctx.now };
  s.clean = score;
  s.poops = JUNK_KINDS.reduce((n, k) => n + counts[k], 0);
  if (!s.daily || !isToday(s.daily.day, ctx.now, s.timezone)) s.daily = makeDaily(ctx, s, s.junk);
  checkSick(ctx.catalog, s, ctx.now);
}

function makeDaily(ctx: Ctx, s: PlayerState, junk: JunkSummary) {
  const options = JUNK_KINDS.filter((k) => junk.counts[k] > 0);
  if (!options.length) return null;
  const kind = options[Math.floor(ctx.rand() * options.length)];
  const j = ctx.catalog.junk[kind];
  return { kind, target: Math.min(j.dailyTarget, junk.counts[kind]), progress: 0, reward: j.dailyReward, day: dayKey(ctx.now, s.timezone), paid: false };
}

/**
 * Called after the phone actually deleted junk. Only the kind, count and bytes are sent.
 * The server checks them against the last scan and daily limits before paying out.
 */
export function claimCleanup(ctx: Ctx, s: PlayerState, input: { kind?: unknown; count?: unknown; bytes?: unknown }, ev: GameEvents) {
  const t = ctx.catalog.tuning;
  const kind = junkKind(input.kind);
  if (!s.junk) fail("failed-precondition", "Report a scan before claiming a cleanup");
  const junk = s.junk as JunkSummary;
  // Pay for at most what the last scan found; an inflated count is capped, not trusted
  const asked = count(input.count, 1_000_000, "count");
  if (asked < 1) fail("invalid-argument", "count must be at least 1");
  if (junk.counts[kind] < 1) fail("failed-precondition", `No ${kind} left from the last scan`);
  const n = Math.min(asked, junk.counts[kind]);
  const bytes = Math.min(count(input.bytes ?? 0, Number.MAX_SAFE_INTEGER, "bytes"), n * t.maxBytesPerItem[kind]);
  const today = dayKey(ctx.now, s.timezone);
  if (s.cleanupToday.day !== today) s.cleanupToday = { day: today, items: 0 };
  if (s.cleanupToday.items + n > t.maxCleanupItemsPerDay) fail("resource-exhausted", "Daily cleanup limit reached");
  s.cleanupToday.items += n;

  const coins = Math.min(t.cleanupCoinCap, n * ctx.catalog.junk[kind].coinsPerItem);
  const firstToday = isToday(s.lastCleanDay, ctx.now, s.timezone) ? 0 : t.firstCleanTodayBonus;
  if (isToday(s.lastPlayDay, ctx.now, s.timezone)) {
    // already played today
  } else if (isYesterday(s.lastPlayDay, ctx.now, s.timezone)) s.streak += 1;
  else s.streak = 1;
  s.lastPlayDay = today;
  s.lastCleanDay = today;
  const streakBonus = firstToday > 0 ? Math.min(s.streak, t.streakBonusMaxDays) * t.streakBonusPerDay : 0;

  let dailyBonus = 0;
  const d = s.daily;
  if (d && d.kind === kind && !d.paid && d.day === today) {
    d.progress += n;
    if (d.progress >= d.target) {
      d.paid = true;
      dailyBonus = d.reward;
    }
  }

  s.itemsTossed += n;
  s.bytesFreed += bytes;
  s.cleanups += 1;
  s.pal.joy = Math.min(100, s.pal.joy + t.cleanupJoy);

  const reached = ctx.catalog.milestones.filter((m) => !s.milestones.includes(m.id) && s.bytesFreed >= m.bytes);
  for (const m of reached) {
    s.milestones.push(m.id);
    if (m.gift && !s.wardrobe.includes(m.gift)) s.wardrobe.push(m.gift);
  }

  const total = coins + firstToday + streakBonus + dailyBonus + reached.reduce((x, m) => x + m.coins, 0);
  const reward: CleanReward = { kind, count: n, bytes, coins, firstTodayBonus: firstToday, streakBonus, dailyBonus, milestones: reached, total };
  s.coins += total;
  s.pal.xp += Math.min(t.cleanupXpCap, n * t.cleanupXpPerItem) + t.cleanupXpBonus;
  const grew = advanceStage(ctx.catalog, s);
  if (grew) ev.grewTo = grew;
  ev.reward = reward;
  ev.coinsDelta = total;

  // Take the scooped items out of the last scan, like PhotoLibrary.remove() does on the phone
  const before = junk.counts[kind];
  junk.bytes[kind] = Math.round(junk.bytes[kind] * ((before - n) / before));
  junk.counts[kind] = before - n;
  junk.totalAssets = Math.max(0, junk.totalAssets - n);
  junk.score = junkScore(ctx.catalog, junk.counts, junk.totalAssets);
  s.clean = junk.score;
  s.poops = JUNK_KINDS.reduce((x, k) => x + junk.counts[k], 0);
}

// ---------------------------------------------------------------- caring for your pal

export function feed(ctx: Ctx, s: PlayerState, itemId: unknown, ev: GameEvents) {
  const it = item(ctx.catalog, itemId);
  if (it.category !== "food" && it.category !== "toy") fail("invalid-argument", `${it.name} can't be fed`);
  if (s.sleeping) fail("failed-precondition", "Your pal is asleep");
  const owned = s.inventory[it.id] ?? 0;
  if (owned < 1) fail("failed-precondition", `No ${it.name} in the pantry`);
  if (owned === 1) delete s.inventory[it.id];
  else s.inventory[it.id] = owned - 1;
  s.pal.food = Math.min(100, s.pal.food + it.food);
  const fav = ctx.catalog.species[s.pal.look.species].favoriteFood === it.id;
  s.pal.joy = Math.min(100, s.pal.joy + it.joy + (fav ? 10 : 0));
  s.pal.xp += 3;
  s.hasFed = true;
  const grew = advanceStage(ctx.catalog, s);
  if (grew) ev.grewTo = grew;
}

export function play(s: PlayerState) {
  if (s.sleeping) fail("failed-precondition", "Your pal is asleep");
  s.pal.joy = Math.min(100, s.pal.joy + 4);
  s.pal.energy = Math.max(0, s.pal.energy - 2);
  s.pal.xp += 1;
}

export function brush(s: PlayerState) {
  if (s.sleeping) fail("failed-precondition", "Your pal is asleep");
  s.pal.joy = Math.min(100, s.pal.joy + 3);
  s.pal.xp += 1;
}

export function pat(s: PlayerState) {
  if (s.sleeping) return;
  s.pal.joy = Math.min(100, s.pal.joy + 0.5);
}

export function toggleLights(s: PlayerState) {
  s.sleeping = !s.sleeping;
}

export function giveMedicine(ctx: Ctx, s: PlayerState) {
  const have = s.inventory["medicine"] ?? 0;
  if (!s.pal.sick) fail("failed-precondition", "Your pal isn't sick");
  if (have < 1) fail("failed-precondition", "No medicine");
  if (have === 1) delete s.inventory["medicine"];
  else s.inventory["medicine"] = have - 1;
  s.pal.sick = false;
  s.sickImmuneUntil = ctx.now + ctx.catalog.tuning.medicineImmunityHours * HOUR;
  s.pal.joy = Math.min(100, s.pal.joy + 5);
}

/** Daily Memory Dig. The photo itself is picked and shown on the phone. */
export function finishDig(ctx: Ctx, s: PlayerState, input: { foundSomething?: unknown; freedBytes?: unknown }) {
  const t = ctx.catalog.tuning;
  if (isToday(s.lastDigDay, ctx.now, s.timezone)) fail("failed-precondition", "Already dug today");
  const freed = count(input.freedBytes ?? 0, t.maxBytesPerItem.giants, "freedBytes");
  s.lastDigDay = dayKey(ctx.now, s.timezone);
  s.coins += input.foundSomething === true ? t.digCoinsFound : t.digCoinsEmpty;
  s.pal.joy = Math.min(100, s.pal.joy + t.digJoy);
  s.pal.xp += t.digXp;
  if (freed > 0) {
    s.bytesFreed += freed;
    s.itemsTossed += 1;
  }
}

// ---------------------------------------------------------------- shop and looks

export function buy(ctx: Ctx, s: PlayerState, itemId: unknown) {
  const it = item(ctx.catalog, itemId);
  if (s.coins < it.price) fail("failed-precondition", "Not enough coins");
  switch (it.category) {
    case "hat":
    case "neck":
      if (s.wardrobe.includes(it.id)) fail("failed-precondition", `Already own ${it.name}`);
      s.wardrobe.push(it.id);
      if (it.category === "hat") s.pal.hatId = it.id;
      else s.pal.neckId = it.id;
      break;
    case "decor":
      s.decorOwned[it.id] = (s.decorOwned[it.id] ?? 0) + 1;
      break;
    default:
      s.inventory[it.id] = (s.inventory[it.id] ?? 0) + 1;
  }
  s.coins -= it.price;
}

export function toggleWear(ctx: Ctx, s: PlayerState, itemId: unknown) {
  const it = item(ctx.catalog, itemId);
  if (!s.wardrobe.includes(it.id)) fail("failed-precondition", `You don't own ${it.name}`);
  if (it.category === "hat") s.pal.hatId = s.pal.hatId === it.id ? null : it.id;
  else if (it.category === "neck") s.pal.neckId = s.pal.neckId === it.id ? null : it.id;
}

const paletteKey = (s: PlayerState, id: string) => `${s.pal.look.species}.${id}`;

export function choosePalette(ctx: Ctx, s: PlayerState, paletteId: unknown) {
  const p = palette(ctx.catalog, s.pal.look.species, paletteId);
  if (p.price > 0 && !s.palettesOwned.includes(paletteKey(s, p.id))) {
    if (s.coins < p.price) fail("failed-precondition", "Not enough coins");
    s.coins -= p.price;
    s.palettesOwned.push(paletteKey(s, p.id));
  }
  s.pal.look.paletteId = p.id;
  s.pal.look.custom = null;
}

export function unlockPhotoMatch(ctx: Ctx, s: PlayerState) {
  if (s.photoMatchUnlocked) return;
  const price = ctx.catalog.prices.photoMatch;
  if (s.coins < price) fail("failed-precondition", "Not enough coins");
  s.coins -= price;
  s.photoMatchUnlocked = true;
}

/** Photo Match reads colors from a photo on the phone; only the three colors come here. */
export function applyCustomPalette(s: PlayerState, input: { main?: unknown; accent?: unknown; belly?: unknown; blaze?: unknown }) {
  if (!s.photoMatchUnlocked) fail("failed-precondition", "Unlock Photo Match first");
  const color = (v: unknown, label: string): [number, number, number] => {
    if (!Array.isArray(v) || v.length !== 3 || v.some((c) => typeof c !== "number" || !(c >= 0 && c <= 1))) {
      fail("invalid-argument", `${label} must be [r, g, b] with values from 0 to 1`);
    }
    return v as [number, number, number];
  };
  s.pal.look.custom = {
    id: "custom", name: "Photo Match", main: color(input.main, "main"), accent: color(input.accent, "accent"),
    belly: color(input.belly, "belly"), blaze: input.blaze === true, price: 0,
  };
}

// ---------------------------------------------------------------- adopting and switching pals

/** First-launch adoption, before onboarding finishes. */
export function adopt(ctx: Ctx, s: PlayerState, input: { species?: unknown; name?: unknown; paletteId?: unknown }) {
  if (s.onboarded) fail("failed-precondition", "Already adopted; use adoptPal with a ticket");
  const sp = species(input.species);
  const p = palette(ctx.catalog, sp, input.paletteId);
  if (p.price > 0) fail("invalid-argument", "Pick a free color to start");
  s.pal = { ...s.pal, id: ctx.uuid(), name: cleanName(input.name), look: { species: sp, paletteId: p.id, custom: null }, born: ctx.now, stage: "baby", xp: 0 };
  if (sp === "dog" && p.id === "peanut") {
    if (!s.wardrobe.includes("collar")) s.wardrobe.push("collar");
    s.pal.neckId = "collar";
  }
}

export function finishOnboarding(s: PlayerState) {
  s.onboarded = true;
}

export function rename(s: PlayerState, name: unknown) {
  s.pal.name = cleanName(name);
}

function resting(s: PlayerState): Pal {
  return structuredClone(s.pal);
}

export function switchPal(ctx: Ctx, s: PlayerState, id: unknown) {
  const i = s.otherPals.findIndex((p) => p.id === id);
  if (i < 0) fail("not-found", "No such pal");
  const [chosen] = s.otherPals.splice(i, 1);
  s.otherPals.push(resting(s));
  s.pal = chosen;
  s.sleeping = false;
  s.lastTick = ctx.now;
}

export function adoptPal(ctx: Ctx, s: PlayerState, input: { species?: unknown; name?: unknown; paletteId?: unknown }) {
  const sp = species(input.species);
  if (s.tickets < 1) fail("failed-precondition", "You need an adoption ticket");
  const owned = new Set([s.pal.look.species, ...s.otherPals.map((p) => p.look.species)]);
  if (owned.has(sp)) fail("failed-precondition", `You already have a ${sp}`);
  const p = palette(ctx.catalog, sp, input.paletteId);
  if (p.price > 0) fail("invalid-argument", "Pick a free color to start");
  s.tickets -= 1;
  s.otherPals.push(resting(s));
  s.pal = {
    id: ctx.uuid(), name: cleanName(input.name), look: { species: sp, paletteId: p.id, custom: null } as PetLook,
    born: ctx.now, stage: "baby", xp: 0, careMistakes: 0, food: 80, joy: 85, energy: 90, sick: false, hatId: null, neckId: null,
  };
  s.sleeping = false;
  s.lastTick = ctx.now;
}

// ---------------------------------------------------------------- yard building

export function placeDecor(ctx: Ctx, s: PlayerState, itemId: unknown, at: { id?: unknown; x?: unknown; y?: unknown } = {}) {
  const it = item(ctx.catalog, itemId);
  if (s.cleanups < 1) fail("failed-precondition", "Build unlocks after your first scoop");
  const available = (s.decorOwned[it.id] ?? 0) - s.placed.filter((p) => p.itemId === it.id).length;
  if (available < 1) fail("failed-precondition", `No ${it.name} left to place`);
  // The app may pick the id and spot itself, so the item doesn't jump when the server answers
  const id = typeof at.id === "string" && /^[0-9A-F-]{36}$/.test(at.id) && !s.placed.some((p) => p.id === at.id) ? at.id : ctx.uuid();
  const x = typeof at.x === "number" && isFinite(at.x) ? clamp(at.x, 0.06, 0.94) : 0.25 + ctx.rand() * 0.5;
  const y = typeof at.y === "number" && isFinite(at.y) ? clamp(at.y, 0.02, 0.95) : 0.25 + ctx.rand() * 0.35;
  s.placed.push({ id, itemId: it.id, x, y });
}

export function moveDecor(s: PlayerState, input: { id?: unknown; x?: unknown; y?: unknown }) {
  const p = s.placed.find((d) => d.id === input.id);
  if (!p) fail("not-found", "No such yard item");
  if (typeof input.x !== "number" || typeof input.y !== "number" || !isFinite(input.x) || !isFinite(input.y)) {
    fail("invalid-argument", "x and y must be numbers");
  }
  p!.x = clamp(input.x as number, 0.06, 0.94);
  p!.y = clamp(input.y as number, 0.02, 0.95);
}

export function storeDecor(s: PlayerState, id: unknown) {
  const before = s.placed.length;
  s.placed = s.placed.filter((d) => d.id !== id);
  if (s.placed.length === before) fail("not-found", "No such yard item");
}
