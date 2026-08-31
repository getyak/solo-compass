export const WEEKDAY_CODES = ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"] as const;
export type WeekdayCode = (typeof WEEKDAY_CODES)[number];

export interface OpeningWindow {
  readonly startMinute: number;
  readonly endMinute: number;
}

export interface WeeklyOpeningHours {
  readonly kind: "weekly";
  readonly sourceText: string;
  readonly days: Readonly<Record<WeekdayCode, readonly OpeningWindow[]>>;
}

const CODE_INDEX = new Map<WeekdayCode, number>(WEEKDAY_CODES.map((code, index) => [code, index]));

/**
 * Strict, deliberately small OSM opening_hours parser.
 *
 * It handles the common deterministic subset (`24/7`, day lists/ranges,
 * multiple HH:MM-HH:MM spans, and `off`). Unsupported constructs such as
 * public-holiday overrides, sunrise/sunset, week numbers, and comments return
 * `undefined`; callers must preserve them as unknown instead of guessing.
 */
export function parseSimpleOpeningHours(raw: string): WeeklyOpeningHours | undefined {
  const sourceText = raw.trim();
  if (!sourceText) return undefined;
  const mutableDays = emptyDays();
  if (sourceText === "24/7") {
    for (const code of WEEKDAY_CODES) mutableDays[code] = [{ startMinute: 0, endMinute: 1440 }];
    return { kind: "weekly", sourceText, days: mutableDays };
  }
  if (/["'+]|\b(?:PH|SH|week|sunrise|sunset|dawn|dusk)\b/i.test(sourceText)) return undefined;

  const segments = sourceText.split(";").map((segment) => segment.trim());
  if (segments.some((segment) => segment.length === 0)) return undefined;
  for (const segment of segments) {
    const parsed = parseSegment(segment);
    if (!parsed) return undefined;
    for (const day of parsed.days) {
      mutableDays[day] = parsed.closed
        ? []
        : mergeWindows([...mutableDays[day], ...parsed.windows]);
    }
    for (const spill of parsed.overnightSpill) {
      mutableDays[spill.day] = mergeWindows([...mutableDays[spill.day], spill.window]);
    }
  }

  for (const code of WEEKDAY_CODES) mutableDays[code] = mergeWindows(mutableDays[code]);
  return { kind: "weekly", sourceText, days: mutableDays };
}

export function isWeeklyOpeningHours(value: unknown): value is WeeklyOpeningHours {
  if (!isRecord(value) || value["kind"] !== "weekly" || typeof value["sourceText"] !== "string") {
    return false;
  }
  const days = value["days"];
  if (!isRecord(days)) return false;
  return WEEKDAY_CODES.every((code) => {
    const windows = days[code];
    return (
      Array.isArray(windows) &&
      windows.every(
        (window) =>
          isRecord(window) &&
          typeof window["startMinute"] === "number" &&
          typeof window["endMinute"] === "number" &&
          window["startMinute"] >= 0 &&
          window["endMinute"] <= 1440 &&
          window["startMinute"] < window["endMinute"],
      )
    );
  });
}

export function windowsForDay(
  hours: WeeklyOpeningHours,
  dayOfWeek: number,
): readonly OpeningWindow[] {
  if (!Number.isInteger(dayOfWeek) || dayOfWeek < 0 || dayOfWeek > 6) {
    throw new Error("dayOfWeek must be an integer from 0 (Sunday) through 6 (Saturday)");
  }
  const code = WEEKDAY_CODES[dayOfWeek];
  return code ? hours.days[code] : [];
}

interface ParsedSegment {
  readonly days: readonly WeekdayCode[];
  readonly windows: readonly OpeningWindow[];
  readonly closed: boolean;
  readonly overnightSpill: readonly { day: WeekdayCode; window: OpeningWindow }[];
}

function parseSegment(segment: string): ParsedSegment | undefined {
  const firstSpace = segment.search(/\s/);
  let daySpec: string;
  let timeSpec: string;
  if (firstSpace < 0) {
    if (segment === "off" || segment === "closed") {
      daySpec = "Su-Sa";
      timeSpec = segment;
    } else if (looksLikeTimeSpec(segment)) {
      daySpec = "Su-Sa";
      timeSpec = segment;
    } else {
      return undefined;
    }
  } else {
    const first = segment.slice(0, firstSpace);
    if (looksLikeTimeSpec(first)) {
      daySpec = "Su-Sa";
      timeSpec = segment;
    } else {
      daySpec = first;
      timeSpec = segment.slice(firstSpace).trim();
    }
  }
  const days = parseDays(daySpec);
  if (!days) return undefined;
  if (timeSpec === "off" || timeSpec === "closed") {
    return { days, windows: [], closed: true, overnightSpill: [] };
  }

  const windows: OpeningWindow[] = [];
  const spills: Array<{ day: WeekdayCode; window: OpeningWindow }> = [];
  for (const part of timeSpec.split(",").map((value) => value.trim())) {
    const match = /^(\d{1,2}):(\d{2})-(\d{1,2}):(\d{2})$/.exec(part);
    if (!match) return undefined;
    const start = clockMinute(match[1], match[2]);
    const end = clockMinute(match[3], match[4]);
    if (start === undefined || end === undefined || start === 1440 || start === end)
      return undefined;
    if (end > start) {
      windows.push({ startMinute: start, endMinute: end });
      continue;
    }
    windows.push({ startMinute: start, endMinute: 1440 });
    if (end > 0) {
      for (const day of days) {
        spills.push({
          day: WEEKDAY_CODES[(CODE_INDEX.get(day)! + 1) % 7]!,
          window: { startMinute: 0, endMinute: end },
        });
      }
    }
  }
  return { days, windows: mergeWindows(windows), closed: false, overnightSpill: spills };
}

function parseDays(spec: string): WeekdayCode[] | undefined {
  const days: WeekdayCode[] = [];
  for (const token of spec.split(",")) {
    const range = /^([A-Z][a-z])-([A-Z][a-z])$/.exec(token);
    if (range) {
      const start = asDay(range[1]);
      const end = asDay(range[2]);
      if (!start || !end) return undefined;
      let index = CODE_INDEX.get(start)!;
      const endIndex = CODE_INDEX.get(end)!;
      for (let count = 0; count < 7; count += 1) {
        const day = WEEKDAY_CODES[index];
        if (!day) return undefined;
        days.push(day);
        if (index === endIndex) break;
        index = (index + 1) % 7;
      }
      continue;
    }
    const day = asDay(token);
    if (!day) return undefined;
    days.push(day);
  }
  return [...new Set(days)];
}

function asDay(value: string | undefined): WeekdayCode | undefined {
  return WEEKDAY_CODES.find((code) => code === value);
}

function looksLikeTimeSpec(value: string): boolean {
  return value === "off" || value === "closed" || /^\d{1,2}:\d{2}-/.test(value);
}

function clockMinute(
  hourText: string | undefined,
  minuteText: string | undefined,
): number | undefined {
  const hour = Number(hourText);
  const minute = Number(minuteText);
  if (!Number.isInteger(hour) || !Number.isInteger(minute) || minute < 0 || minute > 59) {
    return undefined;
  }
  if (hour === 24 && minute === 0) return 1440;
  if (hour < 0 || hour > 23) return undefined;
  return hour * 60 + minute;
}

function emptyDays(): Record<WeekdayCode, OpeningWindow[]> {
  return { Su: [], Mo: [], Tu: [], We: [], Th: [], Fr: [], Sa: [] };
}

function mergeWindows(windows: readonly OpeningWindow[]): OpeningWindow[] {
  const sorted = [...windows].sort(
    (a, b) => a.startMinute - b.startMinute || a.endMinute - b.endMinute,
  );
  const merged: OpeningWindow[] = [];
  for (const window of sorted) {
    const previous = merged[merged.length - 1];
    if (!previous || window.startMinute > previous.endMinute) {
      merged.push({ ...window });
    } else {
      merged[merged.length - 1] = {
        startMinute: previous.startMinute,
        endMinute: Math.max(previous.endMinute, window.endMinute),
      };
    }
  }
  return merged;
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
