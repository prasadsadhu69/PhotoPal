// Generates src/rules/catalog.data.json from the iOS app's Models.swift,
// so the backend content catalog starts identical to what ships in the app today.
// Usage: node scripts/gen-catalog.mjs ../../PhotoPal/Models.swift
import { readFileSync, writeFileSync } from "node:fs";

const src = readFileSync(process.argv[2], "utf8");
const num = (s) => Number(s.trim());
const rgb = (s) => s.split(",").map(num);

// --- Species, with their palettes and per-animal text
const species = {};
const speciesIds = ["dog", "cat", "bunny", "panda", "fox"];
const pick = (fnName, id) => {
  const block = src.slice(src.indexOf(`var ${fnName}:`));
  const m = block.match(new RegExp(`case \\.${id}: return "([^"]*)"`));
  return m ? m[1] : null;
};
const paletteBlock = src.slice(src.indexOf("var palettes: [PetPalette]"), src.indexOf("func palette(_ id"));
for (const id of speciesIds) {
  const start = paletteBlock.indexOf(`case .${id}:`);
  const next = speciesIds.map((s) => paletteBlock.indexOf(`case .${s}:`)).filter((i) => i > start).sort((a, b) => a - b)[0] ?? paletteBlock.length;
  const chunk = paletteBlock.slice(start, next);
  const palettes = [...chunk.matchAll(/PetPalette\(id: "(\w+)", name: "([^"]+)", main: RGB\(([^)]+)\), accent: RGB\(([^)]+)\), belly: RGB\(([^)]+)\), blaze: (true|false), price: (\d+)\)/g)]
    .map((m) => ({ id: m[1], name: m[2], main: rgb(m[3]), accent: rgb(m[4]), belly: rgb(m[5]), blaze: m[6] === "true", price: num(m[7]) }));
  species[id] = {
    title: pick("title", id),
    defaultName: pick("defaultName", id),
    babyName: pick("babyName", id),
    favoriteFood: pick("favoriteFood", id),
    palettes,
  };
}

// --- Shop items
const items = [...src.matchAll(/ShopItem\(id: "(\w+)", name: "([^"]+)", symbol: "([^"]+)", category: \.(\w+), price: (\d+)([^)]*)\)/g)].map((m) => {
  const extra = m[6];
  const field = (k) => { const f = extra.match(new RegExp(`${k}: ([\\d.]+)`)); return f ? num(f[1]) : 0; };
  return { id: m[1], name: m[2], symbol: m[3], category: m[4], price: num(m[5]), food: field("food"), joy: field("joy"), comfort: field("comfort") };
});

// --- Milestones
const milestones = [...src.matchAll(/Milestone\(id: "(\w+)", title: "([^"]+)", bytes: ([\d_]+), coins: (\d+), gift: (nil|"(\w+)")\)/g)]
  .map((m) => ({ id: m[1], title: m[2], bytes: Number(m[3].replaceAll("_", "")), coins: num(m[4]), gift: m[6] ?? null }));

const out = {
  version: 1,
  species,
  items,
  milestones,
  stages: { baby: 0, kid: 150, teen: 400, adult: 800, radiant: 1500 },
  junk: {
    screenshots: { coinsPerItem: 1, dailyTarget: 20, dailyReward: 30 },
    twins: { coinsPerItem: 1, dailyTarget: 10, dailyReward: 30 },
    giants: { coinsPerItem: 4, dailyTarget: 2, dailyReward: 40 },
    oopsies: { coinsPerItem: 1, dailyTarget: 8, dailyReward: 30 },
  },
  prices: { photoMatch: 250 },
  // Values from GameState.swift. Kept in the catalog so they can be tuned without an app release.
  tuning: {
    startCoins: 30,
    awakeFoodPerHour: 3, awakeJoyPerHour: 2.5, awakeEnergyPerHour: 4,
    sleepEnergyPerHour: 14, sleepFoodPerHour: 1.5,
    sickJoyFactor: 1.6, cozyDivisor: 120, minComfortFactor: 0.4, maxCozy: 100,
    sickCleanBelow: 20, medicineImmunityHours: 24,
    cleanupCoinCap: 60, cleanupXpCap: 60, cleanupXpPerItem: 3, cleanupXpBonus: 10, cleanupJoy: 8,
    firstCleanTodayBonus: 20, streakBonusPerDay: 3, streakBonusMaxDays: 7,
    digCoinsFound: 5, digCoinsEmpty: 2, digJoy: 3, digXp: 5,
    // Server-side guard rails (not in the iOS app)
    maxCleanupItemsPerDay: 5000,
    maxBytesPerItem: { screenshots: 50000000, twins: 100000000, giants: 20000000000, oopsies: 100000000 },
    scoreJunkRatio: 0.35,
  },
};

const counts = { species: Object.keys(species).length, palettes: Object.values(species).reduce((n, s) => n + s.palettes.length, 0), items: items.length, milestones: milestones.length };
if (counts.items !== 27 || counts.milestones !== 5 || Object.values(species).some((s) => !s.palettes.length || !s.favoriteFood)) {
  throw new Error("Catalog parse looks wrong: " + JSON.stringify(counts));
}
writeFileSync(new URL("../src/rules/catalog.data.json", import.meta.url), JSON.stringify(out, null, 2) + "\n");
console.log("Wrote catalog", counts);
