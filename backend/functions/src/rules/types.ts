// Shared data model for PhotoPal. Both the iOS and Android apps read these shapes
// from the API, so field names are part of the public contract (see docs/API.md).
// All times are milliseconds since the Unix epoch; "day" fields are local calendar
// days in the player's time zone, formatted YYYY-MM-DD.

export type Species = "dog" | "cat" | "bunny" | "panda" | "fox";
export type LifeStage = "baby" | "kid" | "teen" | "adult" | "radiant";
export type JunkKind = "screenshots" | "twins" | "giants" | "oopsies";
export type ItemCategory = "food" | "toy" | "care" | "hat" | "neck" | "decor";

export const SPECIES: Species[] = ["dog", "cat", "bunny", "panda", "fox"];
export const STAGES: LifeStage[] = ["baby", "kid", "teen", "adult", "radiant"];
export const JUNK_KINDS: JunkKind[] = ["screenshots", "twins", "giants", "oopsies"];

export type RGB = [number, number, number];

export interface Palette {
  id: string;
  name: string;
  main: RGB;
  accent: RGB;
  belly: RGB;
  blaze: boolean;
  price: number;
}

export interface PetLook {
  species: Species;
  paletteId: string;
  /** A coat copied from a real pet photo by Photo Match (computed on the phone). */
  custom: Palette | null;
}

export interface Pal {
  id: string;
  name: string;
  look: PetLook;
  born: number;
  stage: LifeStage;
  xp: number;
  careMistakes: number;
  food: number;
  joy: number;
  energy: number;
  sick: boolean;
  hatId: string | null;
  neckId: string | null;
}

export interface DailyBounty {
  kind: JunkKind;
  target: number;
  progress: number;
  reward: number;
  day: string;
  paid: boolean;
}

export interface PlacedDecor {
  id: string;
  itemId: string;
  x: number;
  y: number;
}

/** Counts from the last on-device scan. Never photo IDs. */
export interface JunkSummary {
  counts: Record<JunkKind, number>;
  bytes: Record<JunkKind, number>;
  totalAssets: number;
  score: number;
  scannedAt: number;
}

export interface PlayerState {
  schema: 1;
  timezone: string;
  onboarded: boolean;
  pal: Pal;
  otherPals: Pal[];
  tickets: number;

  clean: number;
  sleeping: boolean;
  sickImmuneUntil: number | null;
  lastTick: number;

  coins: number;
  inventory: Record<string, number>;
  wardrobe: string[];
  palettesOwned: string[];
  photoMatchUnlocked: boolean;
  decorOwned: Record<string, number>;
  placed: PlacedDecor[];

  itemsTossed: number;
  bytesFreed: number;
  cleanups: number;
  poops: number;
  streak: number;
  lastPlayDay: string | null;
  lastCleanDay: string | null;
  lastDigDay: string | null;
  daily: DailyBounty | null;
  milestones: string[];
  hasFed: boolean;

  junk: JunkSummary | null;
  cleanupToday: { day: string; items: number };
}

export interface ShopItem {
  id: string;
  name: string;
  symbol: string;
  category: ItemCategory;
  price: number;
  food: number;
  joy: number;
  comfort: number;
}

export interface Milestone {
  id: string;
  title: string;
  bytes: number;
  coins: number;
  gift: string | null;
}

export interface Tuning {
  startCoins: number;
  awakeFoodPerHour: number;
  awakeJoyPerHour: number;
  awakeEnergyPerHour: number;
  sleepEnergyPerHour: number;
  sleepFoodPerHour: number;
  sickJoyFactor: number;
  cozyDivisor: number;
  minComfortFactor: number;
  maxCozy: number;
  sickCleanBelow: number;
  medicineImmunityHours: number;
  cleanupCoinCap: number;
  cleanupXpCap: number;
  cleanupXpPerItem: number;
  cleanupXpBonus: number;
  cleanupJoy: number;
  firstCleanTodayBonus: number;
  streakBonusPerDay: number;
  streakBonusMaxDays: number;
  digCoinsFound: number;
  digCoinsEmpty: number;
  digJoy: number;
  digXp: number;
  maxCleanupItemsPerDay: number;
  maxBytesPerItem: Record<JunkKind, number>;
  scoreJunkRatio: number;
}

export interface Catalog {
  version: number;
  species: Record<Species, { title: string; defaultName: string; babyName: string; favoriteFood: string; palettes: Palette[] }>;
  items: ShopItem[];
  milestones: Milestone[];
  stages: Record<LifeStage, number>;
  junk: Record<JunkKind, { coinsPerItem: number; dailyTarget: number; dailyReward: number }>;
  prices: { photoMatch: number };
  tuning: Tuning;
}

/** What happened in one action, for the app to celebrate. */
export interface GameEvents {
  grewTo?: LifeStage;
  reward?: CleanReward;
  coinsDelta?: number;
}

export interface CleanReward {
  kind: JunkKind;
  count: number;
  bytes: number;
  coins: number;
  firstTodayBonus: number;
  streakBonus: number;
  dailyBonus: number;
  milestones: Milestone[];
  total: number;
}
