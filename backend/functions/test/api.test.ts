import { describe, expect, it } from "vitest";
import * as api from "../src/api/handlers";
import { GameError } from "../src/rules/engine";
import { MemoryStore } from "../src/store/memory";

const T0 = Date.UTC(2026, 10, 2, 20, 0); // noon in Los Angeles
const H = 3_600_000;

function setup() {
  const store = new MemoryStore();
  let now = T0;
  const env: api.Env = { store, now: () => now, rand: () => 0 };
  return { store, env, advance: (h: number) => (now += h * H) };
}

async function onboard(env: api.Env, uid = "u1") {
  await api.bootstrap(env, uid, { timezone: "America/Los_Angeles" });
  await api.act(env, uid, { action: "adopt", params: { species: "dog", name: "Peanut", paletteId: "peanut" } });
  return api.act(env, uid, { action: "finishOnboarding" });
}

describe("API", () => {
  it("creates a player on first bootstrap and lets time pass after", async () => {
    const { env, advance } = setup();
    const first = await api.bootstrap(env, "u1", { timezone: "America/Los_Angeles" });
    expect(first.isNew).toBe(true);
    expect(first.canImportLegacySave).toBe(true);
    expect(first.derived.mood).toBe("thriving");
    advance(5);
    const again = await api.bootstrap(env, "u1", { timezone: "Not/AZone" });
    expect(again.isNew).toBe(false);
    expect(again.state.timezone).toBe("America/Los_Angeles");
    expect(again.state.pal.food).toBeCloseTo(65);
    expect(again.rev).toBe(2);
  });

  it("runs actions, bumps rev and keeps a coin ledger", async () => {
    const { env, store } = setup();
    await onboard(env);
    const r = await api.act(env, "u1", { action: "buy", params: { itemId: "kibble" } });
    expect(r.state.coins).toBe(22);
    expect(r.events.coinsDelta).toBe(-8);
    expect(await store.ledger("u1", 10)).toEqual([
      { at: T0, action: "buy", delta: -8, balance: 22 },
      { at: T0, action: "create", delta: 30, balance: 30 },
    ]);
  });

  it("refuses actions before bootstrap and passes game errors through", async () => {
    const { env } = setup();
    await expect(api.act(env, "u1", { action: "play" })).rejects.toBeInstanceOf(GameError);
    await onboard(env);
    await expect(api.act(env, "u1", { action: "buy", params: { itemId: "crown" } })).rejects.toMatchObject({ code: "failed-precondition" });
    await expect(api.act(env, "u1", {})).rejects.toMatchObject({ code: "invalid-argument" });
  });

  it("imports an iOS save once, and never over an existing pal", async () => {
    const { env } = setup();
    await api.bootstrap(env, "u1", { timezone: "America/Los_Angeles" });
    const save = { onboarded: true, petName: "Biscuit", coins: 500, look: { species: "fox", paletteID: "red" }, lastTick: (T0 - 978_307_200_000) / 1000 };
    const r = await api.importLegacySave(env, "u1", { save });
    expect(r.state.pal.name).toBe("Biscuit");
    expect(r.state.coins).toBe(500);
    await expect(api.importLegacySave(env, "u1", { save })).rejects.toMatchObject({ code: "failed-precondition" });
    await onboard(env, "u2");
    await expect(api.importLegacySave(env, "u2", { save })).rejects.toMatchObject({ code: "failed-precondition" });
  });

  it("serializes concurrent actions on the same player", async () => {
    const { env } = setup();
    await onboard(env);
    await Promise.all(Array.from({ length: 3 }, () => api.act(env, "u1", { action: "buy", params: { itemId: "kibble" } })));
    const s = await api.bootstrap(env, "u1");
    expect(s.state.coins).toBe(30 - 24);
    // a fourth would overdraw (6 coins left, kibble costs 8)
    await expect(api.act(env, "u1", { action: "buy", params: { itemId: "kibble" } })).rejects.toMatchObject({ code: "failed-precondition" });
  });

  it("sends hungry reminders in the day only, once, and drops dead tokens", async () => {
    const { env, store, advance } = setup();
    await onboard(env);
    await api.registerDevice(env, "u1", { token: "token-good-123", platform: "ios" });
    await api.registerDevice(env, "u1", { token: "token-dead-456", platform: "android" });
    const sent: string[][] = [];
    const send: api.PushSender = async (tokens) => { sent.push(tokens); return { invalidTokens: ["token-dead-456"] }; };

    expect(await api.sendDueReminders(env, send)).toEqual({ due: 0, sent: 0 });
    advance(20); // food 80 -> 20 after 20h; that's 8am in LA, still quiet hours
    expect((await api.sendDueReminders(env, send)).sent).toBe(0);
    advance(2); // 10am
    expect(await api.sendDueReminders(env, send)).toEqual({ due: 1, sent: 1 });
    expect(sent[0]).toEqual(["token-good-123", "token-dead-456"]);
    expect((await store.devices("u1")).map((d) => d.token)).toEqual(["token-good-123"]);
    expect((await api.sendDueReminders(env, send)).due).toBe(0); // not again while still hungry
  });

  it("exports and deletes everything about a player", async () => {
    const { env, store } = setup();
    await onboard(env);
    await api.registerDevice(env, "u1", { token: "token-good-123", platform: "ios" });
    await api.act(env, "u1", { action: "buy", params: { itemId: "kibble" } });
    const exported = await api.exportMyData(env, "u1");
    expect(exported.player?.state.pal.name).toBe("Peanut");
    expect(JSON.stringify(exported)).not.toContain("token-good-123");
    await api.deleteMyData(env, "u1");
    expect(await store.read("u1")).toBeNull();
    expect(await store.devices("u1")).toEqual([]);
    expect(await store.ledger("u1", 10)).toEqual([]);
  });

  it("validates device registration", async () => {
    const { env } = setup();
    await expect(api.registerDevice(env, "u1", { token: "x", platform: "ios" })).rejects.toMatchObject({ code: "invalid-argument" });
    await expect(api.registerDevice(env, "u1", { token: "token-good-123", platform: "web" })).rejects.toMatchObject({ code: "invalid-argument" });
  });
});
