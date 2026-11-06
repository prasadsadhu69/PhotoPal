import { describe, expect, it } from "vitest";
import catalogData from "../src/rules/catalog.data.json";
import { applyAction } from "../src/rules/actions";
import { Ctx, GameError, derive, junkScore, newPlayer } from "../src/rules/engine";
import { fromLegacySave } from "../src/rules/legacy";
import { Catalog, PlayerState } from "../src/rules/types";

const catalog = catalogData as Catalog;
const T0 = Date.UTC(2026, 10, 2, 20, 0); // Nov 2 2026, 12:00 in Los Angeles
const H = 3_600_000;
let n = 0;
const ctx = (now = T0, rand = 0): Ctx => ({ now, catalog, rand: () => rand, uuid: () => `ID-${++n}` });
const TZ = "America/Los_Angeles";

function onboarded(): PlayerState {
  let s = newPlayer(ctx(), TZ);
  s = applyAction(ctx(), s, "adopt", { species: "dog", name: "Peanut", paletteId: "peanut" }).state;
  return applyAction(ctx(), s, "finishOnboarding").state;
}
const scan = (s: PlayerState, now = T0, counts = { screenshots: 100, twins: 10, giants: 3, oopsies: 5 }, totalAssets = 2000) =>
  applyAction(ctx(now), s, "reportScan", {
    counts,
    bytes: { screenshots: counts.screenshots * 1_000_000, twins: counts.twins * 3_000_000, giants: counts.giants * 200_000_000, oopsies: counts.oopsies * 2_000_000 },
    totalAssets,
  }).state;
const expectError = (fn: () => unknown, code: string) => {
  try { fn(); } catch (e) { expect(e).toBeInstanceOf(GameError); expect((e as GameError).code).toBe(code); return; }
  throw new Error("expected an error");
};

describe("catalog", () => {
  it("matches the iOS app", () => {
    expect(catalog.items).toHaveLength(27);
    expect(catalog.species.panda.favoriteFood).toBe("bamboo");
    expect(catalog.items.find((i) => i.id === "doghouse")).toMatchObject({ price: 800, comfort: 25 });
    expect(catalog.milestones.find((m) => m.id === "gb1")).toMatchObject({ coins: 100, gift: "party" });
  });
});

describe("new player and onboarding", () => {
  it("starts like SaveData()", () => {
    const s = newPlayer(ctx(), TZ);
    expect(s).toMatchObject({ coins: 30, inventory: { kibble: 3 }, decorOwned: { bowl: 1 }, onboarded: false, clean: 100 });
    expect(s.pal).toMatchObject({ food: 80, joy: 80, energy: 90, stage: "baby" });
  });
  it("gives Peanut his red collar", () => {
    const s = onboarded();
    expect(s.pal.neckId).toBe("collar");
    expect(s.wardrobe).toContain("collar");
  });
  it("rejects paid colors and a second adopt", () => {
    expectError(() => applyAction(ctx(), newPlayer(ctx(), TZ), "adopt", { species: "dog", name: "X", paletteId: "husky" }), "invalid-argument");
    expectError(() => applyAction(ctx(), onboarded(), "adopt", { species: "cat", name: "X", paletteId: "ginger" }), "failed-precondition");
  });
});

describe("time passing", () => {
  it("drains needs at the GameState.swift rates", () => {
    const s = applyAction(ctx(T0 + 10 * H), onboarded(), "pat").state;
    expect(s.pal.food).toBeCloseTo(80 - 30);
    expect(s.pal.energy).toBeCloseTo(90 - 40);
    // bowl gives comfort 5: factor 1 - 5/120
    expect(s.pal.joy).toBeCloseTo(80 - 10 * 2.5 * (1 - 5 / 120) + 0.5);
  });
  it("falls asleep when tired, gets hungry, sick and counts care mistakes", () => {
    const s = applyAction(ctx(T0 + 40 * H), onboarded(), "pat").state;
    expect(s.sleeping).toBe(true);
    expect(s.pal.food).toBe(0);
    expect(s.pal.sick).toBe(true);
    expect(s.pal.careMistakes).toBeGreaterThanOrEqual(1);
  });
  it("can't be faked: time comes from the server clock only", () => {
    const s = onboarded();
    const later = applyAction(ctx(T0 - 100 * H), s, "pat").state; // a request with an old clock changes nothing
    expect(later.pal.food).toBe(s.pal.food);
  });
});

describe("cleanups", () => {
  it("must follow a scan and stay within it", () => {
    expectError(() => applyAction(ctx(), onboarded(), "claimCleanup", { kind: "screenshots", count: 5 }), "failed-precondition");
    const s = scan(onboarded());
    // inflated claims are capped to the scan, not trusted
    const capped = applyAction(ctx(), s, "claimCleanup", { kind: "giants", count: 400, bytes: 1e15 }).events.reward!;
    expect(capped).toMatchObject({ count: 3, coins: 12, bytes: 3 * 20_000_000_000 });
    const after = applyAction(ctx(), s, "claimCleanup", { kind: "giants", count: 3 }).state;
    expectError(() => applyAction(ctx(), after, "claimCleanup", { kind: "giants", count: 1 }), "failed-precondition");
    expectError(() => applyAction(ctx(), s, "claimCleanup", { kind: "screenshots", count: 0 }), "invalid-argument");
    expectError(() => applyAction(ctx(), s, "claimCleanup", { kind: "nope", count: 1 }), "invalid-argument");
  });
  it("pays like rewardCleanup() in the app", () => {
    const s = scan(onboarded());
    const { state, events } = applyAction(ctx(), s, "claimCleanup", { kind: "screenshots", count: 25, bytes: 25_000_000 });
    expect(events.reward).toMatchObject({ coins: 25, firstTodayBonus: 20, streakBonus: 3 });
    expect(state.coins).toBe(s.coins + events.reward!.total);
    expect(state.pal.xp).toBe(70);
    expect(state.streak).toBe(1);
    expect(state.junk!.counts.screenshots).toBe(75);
    expect(state.junk!.totalAssets).toBe(1975);
    expect(state.clean).toBe(junkScore(catalog, state.junk!.counts, 1975));
    // second cleanup the same day: no first-of-day or streak bonus
    const again = applyAction(ctx(T0 + H), state, "claimCleanup", { kind: "screenshots", count: 2 }).events.reward!;
    expect(again).toMatchObject({ firstTodayBonus: 0, streakBonus: 0 });
  });
  it("caps coins per cleanup at 60 and giants pay 4 each", () => {
    const s = scan(onboarded(), T0, { screenshots: 500, twins: 0, giants: 3, oopsies: 0 });
    expect(applyAction(ctx(), s, "claimCleanup", { kind: "screenshots", count: 200 }).events.reward!.coins).toBe(60);
    expect(applyAction(ctx(), s, "claimCleanup", { kind: "giants", count: 3 }).events.reward!.coins).toBe(12);
  });
  it("grows the streak on consecutive local days", () => {
    let s = scan(onboarded());
    s = applyAction(ctx(), s, "claimCleanup", { kind: "screenshots", count: 1 }).state;
    s = scan(s, T0 + 24 * H);
    const r = applyAction(ctx(T0 + 24 * H), s, "claimCleanup", { kind: "screenshots", count: 1 });
    expect(r.state.streak).toBe(2);
    expect(r.events.reward!.streakBonus).toBe(6);
  });
  it("pays the daily bounty and milestones", () => {
    let s = scan(onboarded()); // rand 0 picks screenshots
    expect(s.daily).toMatchObject({ kind: "screenshots", target: 20, reward: 30 });
    const r = applyAction(ctx(), s, "claimCleanup", { kind: "screenshots", count: 20, bytes: 120_000_000 });
    expect(r.events.reward!.dailyBonus).toBe(30);
    expect(r.state.milestones).toContain("mb100");
    s = scan(r.state, T0, { screenshots: 0, twins: 0, giants: 3, oopsies: 0 });
    const big = applyAction(ctx(), s, "claimCleanup", { kind: "giants", count: 3, bytes: 6_000_000_000 });
    expect(big.state.wardrobe).toEqual(expect.arrayContaining(["party", "scarf"]));
  });
  it("enforces the daily item limit", () => {
    const s = scan(onboarded(), T0, { screenshots: 6000, twins: 0, giants: 0, oopsies: 0 }, 20000);
    expectError(() => applyAction(ctx(), s, "claimCleanup", { kind: "screenshots", count: 5001 }), "resource-exhausted");
  });
});

describe("care, shop, pals and yard", () => {
  it("feeds with a favorite-food bonus and empties the pantry", () => {
    let s = onboarded();
    s.inventory.pupcake = 1;
    s.pal.food = 10; s.pal.joy = 10;
    s = applyAction(ctx(), s, "feed", { itemId: "pupcake" }).state;
    expect(s.pal.food).toBe(70);
    expect(s.pal.joy).toBe(50); // 30 + 10 favorite
    expect(s.inventory.pupcake).toBeUndefined();
    expectError(() => applyAction(ctx(), s, "feed", { itemId: "pupcake" }), "failed-precondition");
    expectError(() => applyAction(ctx(), s, "feed", { itemId: "crown" }), "invalid-argument");
  });
  it("buys within the balance and records the coin change", () => {
    const s = onboarded();
    const r = applyAction(ctx(), s, "buy", { itemId: "kibble" });
    expect(r.state.inventory.kibble).toBe(4);
    expect(r.events.coinsDelta).toBe(-8);
    expectError(() => applyAction(ctx(), s, "buy", { itemId: "crown" }), "failed-precondition");
  });
  it("cures with medicine and grants immunity", () => {
    let s = onboarded();
    s.pal.sick = true; s.inventory.medicine = 1;
    s = applyAction(ctx(), s, "giveMedicine").state;
    expect(s.pal.sick).toBe(false);
    expect(s.sickImmuneUntil).toBe(T0 + 24 * H);
  });
  it("buys palettes per animal and gates Photo Match", () => {
    let s = onboarded();
    s.coins = 1000;
    s = applyAction(ctx(), s, "choosePalette", { paletteId: "husky" }).state;
    expect(s.coins).toBe(800);
    s = applyAction(ctx(), s, "choosePalette", { paletteId: "peanut" }).state;
    s = applyAction(ctx(), s, "choosePalette", { paletteId: "husky" }).state;
    expect(s.coins).toBe(800);
    expectError(() => applyAction(ctx(), s, "applyCustomPalette", { main: [1, 0, 0], accent: [0, 0, 0], belly: [1, 1, 1] }), "failed-precondition");
    s = applyAction(ctx(), s, "unlockPhotoMatch").state;
    s = applyAction(ctx(), s, "applyCustomPalette", { main: [1, 0, 0], accent: [0, 0, 0], belly: [1, 1, 1] }).state;
    expect(s.pal.look.custom?.main).toEqual([1, 0, 0]);
  });
  it("earns adoption tickets from Teen up, adopts and switches pals", () => {
    let s = onboarded();
    s.pal.xp = 799;
    s = applyAction(ctx(), s, "play").state; // 800 XP; like the app, growing happens on the next tick
    expect(s.pal.stage).toBe("baby");
    s = applyAction(ctx(T0 + H), s, "pat").state; // kid, teen and adult at once
    expect(s.pal.stage).toBe("adult");
    expect(s.tickets).toBe(2);
    const dogId = s.pal.id;
    s = applyAction(ctx(), s, "adoptPal", { species: "cat", name: "Mochi", paletteId: "ginger" }).state;
    expect(s.pal.look.species).toBe("cat");
    expect(s.otherPals.map((p) => p.id)).toEqual([dogId]);
    expectError(() => applyAction(ctx(), s, "adoptPal", { species: "dog", name: "Two", paletteId: "peanut" }), "failed-precondition");
    s = applyAction(ctx(), s, "switchPal", { palId: dogId }).state;
    expect(s.pal.id).toBe(dogId);
    expect(derive(ctx(), s).speciesToAdopt).toEqual(["bunny", "panda", "fox"]);
  });
  it("builds the yard only after the first scoop", () => {
    let s = onboarded();
    s.decorOwned.tree = 1;
    expectError(() => applyAction(ctx(), s, "placeDecor", { itemId: "tree" }), "failed-precondition");
    s.cleanups = 1;
    const id = "6F9619FF-8B86-D011-B42D-00C04FC964FF";
    s = applyAction(ctx(), s, "placeDecor", { itemId: "tree", id, x: 0.5, y: 0.4 }).state;
    const tree = s.placed.find((p) => p.itemId === "tree")!;
    expect(tree).toEqual({ id, itemId: "tree", x: 0.5, y: 0.4 });
    s = applyAction(ctx(), s, "moveDecor", { id: tree.id, x: 5, y: -1 }).state;
    expect(s.placed.find((p) => p.id === tree.id)).toMatchObject({ x: 0.94, y: 0.02 });
    s = applyAction(ctx(), s, "storeDecor", { id: tree.id }).state;
    expect(s.placed.some((p) => p.id === tree.id)).toBe(false);
  });
  it("digs once per local day", () => {
    let s = onboarded();
    s = applyAction(ctx(), s, "finishDig", { foundSomething: true }).state;
    expect(s.coins).toBe(35);
    expectError(() => applyAction(ctx(T0 + H), s, "finishDig", {}), "failed-precondition");
    expect(() => applyAction(ctx(T0 + 13 * H), s, "finishDig", {})).not.toThrow(); // next day in LA
  });
  it("rejects unknown actions and bad names", () => {
    expectError(() => applyAction(ctx(), onboarded(), "giveCoins"), "invalid-argument");
    expectError(() => applyAction(ctx(), onboarded(), "rename", { name: "" }), "invalid-argument");
    expectError(() => applyAction(ctx(), onboarded(), "constructor"), "invalid-argument");
  });
});

describe("legacy iOS save import", () => {
  const apple = (ms: number) => (ms - 978_307_200_000) / 1000;
  it("converts Swift dates and drops photo IDs", () => {
    const save = {
      onboarded: true, petName: "Biscuit", born: apple(T0 - 10 * 24 * H), stage: "kid", xp: 200, coins: 412,
      look: { species: "cat", paletteID: "smoky" }, food: 50, joy: 60, energy: 70, clean: 88,
      inventory: { kibble: 2, hacked: 99 }, wardrobe: ["party", "notathing"], keptIDs: ["ABC/L0/001"],
      lastTick: apple(T0 - H), lastPlayDay: apple(T0 - 24 * H), streak: 4, milestones: ["mb100"],
      placed: [{ id: "6F9619FF-8B86-D011-B42D-00C04FC964FF", itemID: "bowl", x: 0.2, y: 0.3 }], decorOwned: { bowl: 1 },
      otherPals: [{ id: "7F9619FF-8B86-D011-B42D-00C04FC964FF", name: "Rex", look: { species: "dog", paletteID: "golden" }, born: apple(T0), stage: "baby", xp: 5, careMistakes: 0, food: 80, joy: 80, energy: 90, sick: false }],
    };
    const s = fromLegacySave(ctx(), save, TZ);
    expect(s.pal).toMatchObject({ name: "Biscuit", stage: "kid", xp: 200, look: { species: "cat", paletteId: "smoky" } });
    expect(s.pal.born).toBe(T0 - 10 * 24 * H);
    expect(s.lastPlayDay).toBe("2026-11-01");
    expect(s.inventory).toEqual({ kibble: 2 });
    expect(s.wardrobe).toEqual(["party"]);
    expect(s.otherPals[0]).toMatchObject({ name: "Rex", look: { species: "dog" } });
    expect(JSON.stringify(s)).not.toContain("ABC/L0/001");
  });
});
