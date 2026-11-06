// One entry point for every game action, so the API, tests and any future
// client-side prediction all run the exact same code path.

import * as E from "./engine";
import { GameEvents, PlayerState } from "./types";

type Params = Record<string, unknown>;
type Handler = (ctx: E.Ctx, s: PlayerState, p: Params, ev: GameEvents) => void;

export const ACTIONS: Record<string, Handler> = {
  // onboarding
  adopt: (c, s, p) => E.adopt(c, s, p),
  finishOnboarding: (_c, s) => E.finishOnboarding(s),
  rename: (_c, s, p) => E.rename(s, p.name),
  // care
  feed: (c, s, p, ev) => E.feed(c, s, p.itemId, ev),
  play: (_c, s) => E.play(s),
  brush: (_c, s) => E.brush(s),
  pat: (_c, s) => E.pat(s),
  toggleLights: (_c, s) => E.toggleLights(s),
  giveMedicine: (c, s) => E.giveMedicine(c, s),
  finishDig: (c, s, p) => E.finishDig(c, s, p),
  // shop and looks
  buy: (c, s, p) => E.buy(c, s, p.itemId),
  toggleWear: (c, s, p) => E.toggleWear(c, s, p.itemId),
  choosePalette: (c, s, p) => E.choosePalette(c, s, p.paletteId),
  unlockPhotoMatch: (c, s) => E.unlockPhotoMatch(c, s),
  applyCustomPalette: (_c, s, p) => E.applyCustomPalette(s, p),
  // pals
  switchPal: (c, s, p) => E.switchPal(c, s, p.palId),
  adoptPal: (c, s, p) => E.adoptPal(c, s, p),
  // yard
  placeDecor: (c, s, p) => E.placeDecor(c, s, p.itemId, p),
  moveDecor: (_c, s, p) => E.moveDecor(s, p),
  storeDecor: (_c, s, p) => E.storeDecor(s, p.id),
  // camera roll (counts only, never photo IDs)
  reportScan: (c, s, p) => E.reportScan(c, s, p),
  claimCleanup: (c, s, p, ev) => E.claimCleanup(c, s, p, ev),
};

/** Lets time pass, then applies the action. Throws GameError on an invalid action. */
export function applyAction(ctx: E.Ctx, state: PlayerState, action: string, params: Params = {}) {
  const handler = Object.prototype.hasOwnProperty.call(ACTIONS, action) ? ACTIONS[action] : undefined;
  if (!handler) throw new E.GameError("invalid-argument", `Unknown action ${action}`);
  const s = structuredClone(state);
  const ev: GameEvents = {};
  const coinsBefore = s.coins;
  E.tick(ctx, s, ev);
  handler(ctx, s, params ?? {}, ev);
  if (s.coins !== coinsBefore) ev.coinsDelta = s.coins - coinsBefore;
  return { state: s, events: ev };
}
