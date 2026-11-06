// One-time import of an existing iOS save (the "photopal.save.v2" JSON in UserDefaults),
// so current players keep their pal, coins and outfits when they first sign in.
// Photo IDs in the old save (keptIDs, notTwinIDs) are ignored on purpose: they stay on the phone.

import { Ctx, GameError, cleanName, newPlayer } from "./engine";
import { dayKey } from "./time";
import { JUNK_KINDS, LifeStage, Pal, Palette, PetLook, PlayerState, SPECIES, STAGES, Species } from "./types";

// Swift's JSONEncoder writes Date as seconds since 2001-01-01.
const APPLE_EPOCH_MS = 978_307_200_000;
type J = Record<string, any>;

const num = (v: unknown, lo: number, hi: number, d: number) => (typeof v === "number" && isFinite(v) ? Math.min(hi, Math.max(lo, v)) : d);
const int = (v: unknown, hi: number, d = 0) => Math.round(num(v, 0, hi, d));
const date = (v: unknown, now: number): number | null =>
  typeof v === "number" && isFinite(v) ? Math.min(now, APPLE_EPOCH_MS + v * 1000) : null;
const strs = (v: unknown, known: (s: string) => boolean) =>
  Array.isArray(v) ? [...new Set(v.filter((x): x is string => typeof x === "string" && known(x)))] : [];
const counts = (v: unknown, known: (s: string) => boolean, hi: number) => {
  const out: Record<string, number> = {};
  if (v && typeof v === "object") for (const [k, n] of Object.entries(v)) if (known(k)) { const c = int(n, hi); if (c > 0) out[k] = c; }
  return out;
};

export function fromLegacySave(ctx: Ctx, raw: unknown, timezone: string): PlayerState {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) throw new GameError("invalid-argument", "save must be the app's JSON save object");
  const j = raw as J;
  const cat = ctx.catalog;
  const now = ctx.now;
  const s = newPlayer(ctx, timezone);
  const isItem = (id: string) => cat.items.some((i) => i.id === id);
  const isWearable = (id: string) => cat.items.some((i) => i.id === id && (i.category === "hat" || i.category === "neck"));
  const day = (v: unknown) => { const d = date(v, now); return d === null ? null : dayKey(d, timezone); };

  const look = (v: unknown): PetLook => {
    const l = (v ?? {}) as J;
    const sp: Species = SPECIES.includes(l.species) ? l.species : "dog";
    const pid = cat.species[sp].palettes.some((p) => p.id === l.paletteID) ? l.paletteID : cat.species[sp].palettes[0].id;
    let custom: Palette | null = null;
    const c = l.custom as J | undefined;
    const rgb = (x: J | undefined): [number, number, number] => [num(x?.r, 0, 1, 0.5), num(x?.g, 0, 1, 0.5), num(x?.b, 0, 1, 0.5)];
    if (c && typeof c === "object") custom = { id: "custom", name: "Photo Match", main: rgb(c.main), accent: rgb(c.accent), belly: rgb(c.belly), blaze: c.blaze === true, price: 0 };
    return { species: sp, paletteId: pid, custom };
  };
  const stage = (v: unknown, xp: number): LifeStage =>
    STAGES.includes(v as LifeStage) ? (v as LifeStage) : [...STAGES].reverse().find((st) => xp >= cat.stages[st]) ?? "baby";
  const name = (v: unknown, d: string) => { try { return cleanName(v); } catch { return d; } };
  const wear = (v: unknown) => (typeof v === "string" && isWearable(v) ? v : null);

  const pal = (p: J, id: string): Pal => {
    const xp = int(p.xp, 1_000_000);
    const lk = look(p.look);
    return {
      id, name: name(p.petName ?? p.name, cat.species[lk.species].defaultName), look: lk,
      born: date(p.born, now) ?? now, stage: stage(p.stage, xp), xp, careMistakes: int(p.careMistakes, 100_000),
      food: num(p.food, 0, 100, 80), joy: num(p.joy, 0, 100, 80), energy: num(p.energy, 0, 100, 90), sick: p.sick === true,
      hatId: wear(p.hatID), neckId: wear(p.neckID),
    };
  };
  const uuid = (v: unknown) => (typeof v === "string" && /^[0-9A-Fa-f-]{36}$/.test(v) ? v.toUpperCase() : ctx.uuid());

  s.onboarded = j.onboarded !== false;
  s.pal = pal(j, uuid(j.activeID));
  const seen = new Set([s.pal.look.species]);
  s.otherPals = (Array.isArray(j.otherPals) ? j.otherPals : [])
    .map((p: J) => pal(p, uuid(p.id)))
    .filter((p: Pal) => !seen.has(p.look.species) && seen.add(p.look.species))
    .slice(0, SPECIES.length - 1);
  s.tickets = int(j.tickets, SPECIES.length);
  s.clean = num(j.clean, 0, 100, 100);
  s.sleeping = j.sleeping === true;
  s.sickImmuneUntil = date(j.sickImmuneUntil, Infinity);
  s.lastTick = date(j.lastTick, now) ?? now;
  s.coins = int(j.coins, 1_000_000, s.coins);
  s.inventory = counts(j.inventory, isItem, 10_000);
  s.wardrobe = strs(j.wardrobe, isWearable);
  s.palettesOwned = strs(j.palettesOwned, (k) => { const [sp, id] = k.split("."); return SPECIES.includes(sp as Species) && cat.species[sp as Species].palettes.some((p) => p.id === id); });
  s.photoMatchUnlocked = j.photoMatchUnlocked === true;
  s.decorOwned = counts(j.decorOwned, (id) => cat.items.some((i) => i.id === id && i.category === "decor"), 1_000);
  s.placed = (Array.isArray(j.placed) ? j.placed : [])
    .filter((p: J) => typeof p?.itemID === "string" && (s.decorOwned[p.itemID] ?? 0) > 0)
    .slice(0, 200)
    .map((p: J) => ({ id: uuid(p.id), itemId: p.itemID, x: num(p.x, 0.06, 0.94, 0.5), y: num(p.y, 0.02, 0.95, 0.5) }));
  s.itemsTossed = int(j.itemsTossed, 100_000_000);
  s.bytesFreed = int(j.bytesFreed, 1e15);
  s.cleanups = int(j.cleanups, 10_000_000);
  s.poops = int(j.poops, 10_000_000);
  s.streak = int(j.streak, 100_000);
  s.lastPlayDay = day(j.lastPlayDay);
  s.lastCleanDay = day(j.lastCleanDay);
  s.lastDigDay = day(j.lastDigDay);
  const d = j.daily as J | undefined;
  s.daily = d && JUNK_KINDS.includes(d.kind) && date(d.day, now) !== null
    ? { kind: d.kind, target: int(d.target, 1000, 1), progress: int(d.progress, 100_000), reward: int(d.reward, 1000), day: day(d.day)!, paid: d.paid === true }
    : null;
  s.milestones = strs(j.milestones, (id) => cat.milestones.some((m) => m.id === id));
  s.hasFed = j.hasFed !== false;
  return s;
}
