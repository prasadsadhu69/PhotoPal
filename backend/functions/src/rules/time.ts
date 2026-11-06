const formatters = new Map<string, Intl.DateTimeFormat>();

/** Checks an IANA time zone name such as "America/Los_Angeles". */
export function isValidTimeZone(tz: unknown): tz is string {
  if (typeof tz !== "string" || tz.length > 64) return false;
  try {
    new Intl.DateTimeFormat("en-CA", { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

/** The player's local calendar day as YYYY-MM-DD. */
export function dayKey(ms: number, tz: string): string {
  let f = formatters.get(tz);
  if (!f) {
    f = new Intl.DateTimeFormat("en-CA", { timeZone: tz, year: "numeric", month: "2-digit", day: "2-digit" });
    formatters.set(tz, f);
  }
  return f.format(new Date(ms));
}

export const HOUR = 3_600_000;
export const DAY = 24 * HOUR;

export function isToday(day: string | null | undefined, now: number, tz: string): boolean {
  return !!day && day === dayKey(now, tz);
}

export function isYesterday(day: string | null | undefined, now: number, tz: string): boolean {
  if (!day) return false;
  // Noon-anchored so daylight-saving shifts never skip or repeat a day
  const today = dayKey(now, tz);
  const [y, m, d] = today.split("-").map(Number);
  const prev = new Date(Date.UTC(y, m - 1, d, 12) - DAY).toISOString().slice(0, 10);
  return day === prev;
}
